import Foundation
import Testing
@testable import ActionTapeCore

private enum RecordedEvent: Sendable, Equatable {
    case activate(AppTarget)
    case press(Locator)
    case setValue(String, Locator)
    case hotKey(HotKey)
    case exists(Locator)
}

private enum StubError: Error {
    case plannedFailure
}

private actor StubDriver: AutomationDriver {
    private var recorded: [RecordedEvent] = []
    private var pressFailuresRemaining: Int
    private var existenceResponses: [Bool]

    init(pressFailures: Int = 0, existenceResponses: [Bool] = [true]) {
        pressFailuresRemaining = pressFailures
        self.existenceResponses = existenceResponses
    }

    func activateApp(_ target: AppTarget) async throws {
        recorded.append(.activate(target))
    }

    func press(_ locator: Locator) async throws {
        recorded.append(.press(locator))
        if pressFailuresRemaining > 0 {
            pressFailuresRemaining -= 1
            throw StubError.plannedFailure
        }
    }

    func setValue(_ value: String, on locator: Locator) async throws {
        recorded.append(.setValue(value, locator))
    }

    func hotKey(_ hotKey: HotKey) async throws {
        recorded.append(.hotKey(hotKey))
    }

    func exists(_ locator: Locator) async throws -> Bool {
        recorded.append(.exists(locator))
        guard !existenceResponses.isEmpty else { return false }
        return existenceResponses.removeFirst()
    }

    func events() -> [RecordedEvent] { recorded }
}

@Suite("Workflow runner")
struct WorkflowRunnerTests {
    @Test("Runs actions in order and interpolates values and locators")
    func orderedExecutionAndInterpolation() async throws {
        let driver = StubDriver()
        let workflow = Workflow(
            name: "Happy path",
            variables: [
                "appID": .init(defaultValue: "com.example.App"),
                "field": .init(defaultValue: "search"),
                "query": .init(required: true, secret: true)
            ],
            steps: [
                Step(id: "open", action: .activateApp(.init(bundleIdentifier: "{{appID}}"))),
                Step(id: "focus", action: .press(.init(identifier: "{{field}}", role: "AXTextField"))),
                Step(id: "type", action: .setValue(locator: .init(identifier: "{{field}}"), value: "{{query}}")),
                Step(id: "submit", action: .hotKey(.init(key: "return", modifiers: []))),
                Step(id: "verify", action: .assertExists(.init(role: "AXStaticText", title: "Done")))
            ]
        )
        let result = await WorkflowRunner(driver: driver).run(workflow, variables: ["query": "sensitive text"])

        #expect(result.status == .succeeded)
        #expect(result.steps.count == 5)
        #expect(result.steps.allSatisfy { $0.status == .succeeded })
        let events = await driver.events()
        #expect(events == [
            .activate(.init(bundleIdentifier: "com.example.App")),
            .press(.init(identifier: "search", role: "AXTextField")),
            .setValue("sensitive text", .init(identifier: "search")),
            .hotKey(.init(key: "return", modifiers: [])),
            .exists(.init(role: "AXStaticText", title: "Done"))
        ])

        let encodedTrace = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        #expect(!encodedTrace.contains("sensitive text"))
    }

    @Test("Retries transient failures and reports attempts")
    func retries() async {
        let driver = StubDriver(pressFailures: 2)
        let workflow = Workflow(name: "Retry", steps: [
            Step(
                id: "press",
                action: .press(.init(role: "AXButton", title: "Go")),
                timeout: 2,
                retry: .init(maxAttempts: 3, delay: 0)
            )
        ])
        let result = await WorkflowRunner(driver: driver).run(workflow)
        #expect(result.status == .succeeded)
        #expect(result.steps.first?.attempts == 3)
        #expect(await driver.events().count == 3)
    }

    @Test("waitFor polls until the element exists")
    func waitForPolls() async {
        let driver = StubDriver(existenceResponses: [false, false, true])
        let locator = Locator(identifier: "ready")
        let workflow = Workflow(name: "Wait", steps: [
            Step(id: "wait", action: .waitFor(locator), timeout: 1)
        ])
        let runner = WorkflowRunner(
            driver: driver,
            configuration: .init(defaultTimeout: 1, pollingInterval: 0.001)
        )
        let result = await runner.run(workflow)
        #expect(result.status == .succeeded)
        #expect(await driver.events() == [.exists(locator), .exists(locator), .exists(locator)])
    }

    @Test("Failed assertion skips later steps")
    func failureStopsSafely() async {
        let driver = StubDriver(existenceResponses: [false])
        let workflow = Workflow(name: "Stop", steps: [
            Step(id: "assert", action: .assertExists(.init(identifier: "missing"))),
            Step(id: "dangerous-click", action: .press(.init(identifier: "delete")))
        ])
        let result = await WorkflowRunner(driver: driver).run(workflow)
        #expect(result.status == .failed)
        #expect(result.steps.map(\.status) == [.failed, .skipped])
        #expect(await driver.events().count == 1)
    }

    @Test("Step timeout produces a failed trace")
    func timeout() async {
        let driver = StubDriver()
        let workflow = Workflow(name: "Timeout", steps: [
            Step(id: "long-pause", action: .pause(duration: 1), timeout: 0.02)
        ])
        let result = await WorkflowRunner(driver: driver).run(workflow)
        #expect(result.status == .failed)
        #expect(result.steps.first?.status == .failed)
        #expect(result.steps.first?.message?.contains("timed out") == true)
    }

    @Test("Missing required input fails before touching the driver")
    func missingInput() async {
        let driver = StubDriver()
        let workflow = Workflow(
            name: "Input",
            variables: ["required": .init(required: true)],
            steps: [Step(id: "pause", action: .pause(duration: 0))]
        )
        let result = await WorkflowRunner(driver: driver).run(workflow)
        #expect(result.status == .failed)
        #expect(result.steps.isEmpty)
        #expect(await driver.events().isEmpty)
    }

    @Test("Cancellation stops the current pause and skips later mutations")
    func cancellationSkipsLaterActions() async throws {
        let driver = StubDriver()
        let workflow = Workflow(name: "Cancel", steps: [
            Step(id: "pause", action: .pause(duration: 10), timeout: 20),
            Step(id: "later-click", action: .press(.init(identifier: "delete")))
        ])
        let task = Task { await WorkflowRunner(driver: driver).run(workflow) }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        let result = await task.value
        #expect(result.status == .cancelled)
        #expect(result.steps.map(\.status) == [.cancelled, .skipped])
        #expect(await driver.events().isEmpty)
    }

    @Test("A bad late variable selector fails before any earlier action")
    func lateEmptySelectorIsPreflighted() async {
        let driver = StubDriver()
        let workflow = Workflow(name: "Preflight", variables: ["target": .init()], steps: [
            Step(id: "open", action: .activateApp(.init(bundleIdentifier: "com.example.App"))),
            Step(id: "press", action: .press(.init(identifier: "{{target}}")))
        ])
        let result = await WorkflowRunner(driver: driver).run(workflow)
        #expect(result.status == .failed)
        #expect(result.steps.isEmpty)
        #expect(await driver.events().isEmpty)
    }

    @Test("Expired execution context rejects a mutation before it starts")
    func expiredContextRejectsExecution() {
        let context = AutomationExecutionContext.Deadline(
            instant: ContinuousClock.now.advanced(by: .seconds(-1)), stepID: "expired", timeout: 0.1
        )
        AutomationExecutionContext.$deadline.withValue(context) {
            #expect(throws: WorkflowRunnerError.timeout(stepID: "expired", seconds: 0.1)) {
                try AutomationExecutionContext.check()
            }
        }
    }
}
