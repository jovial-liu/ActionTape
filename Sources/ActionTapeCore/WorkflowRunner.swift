import Foundation

/// The built-in driver checks this immediately before each mutation and during AX traversal.
/// A task-local deadline also catches expiry while a synchronous AX call blocks the executor.
enum AutomationExecutionContext {
    struct Deadline: Sendable {
        var instant: ContinuousClock.Instant
        var stepID: String
        var timeout: TimeInterval
    }

    @TaskLocal static var deadline: Deadline?

    static func check() throws {
        if let deadline, ContinuousClock.now >= deadline.instant {
            throw WorkflowRunnerError.timeout(stepID: deadline.stepID, seconds: deadline.timeout)
        }
        try Task.checkCancellation()
    }
}

public enum WorkflowRunnerError: Error, Sendable, Equatable, LocalizedError {
    case timeout(stepID: String, seconds: TimeInterval)
    case assertionFailed(stepID: String)
    case invalidWorkflow(String)

    public var errorDescription: String? {
        switch self {
        case .timeout(let stepID, let seconds):
            "Step '\(stepID)' timed out after \(seconds) seconds."
        case .assertionFailed(let stepID):
            "Assertion failed in step '\(stepID)': element does not exist."
        case .invalidWorkflow(let message):
            "Workflow is invalid: \(message)"
        }
    }
}

public struct RunnerConfiguration: Sendable, Equatable {
    public var defaultTimeout: TimeInterval
    public var pollingInterval: TimeInterval
    public var continueAfterFailure: Bool

    public init(
        defaultTimeout: TimeInterval = 10,
        pollingInterval: TimeInterval = 0.2,
        continueAfterFailure: Bool = false
    ) {
        self.defaultTimeout = defaultTimeout
        self.pollingInterval = pollingInterval
        self.continueAfterFailure = continueAfterFailure
    }
}

/// Runs workflows serially and emits a redaction-safe trace after every step.
public actor WorkflowRunner {
    public typealias StepTraceHandler = @Sendable (StepTrace) -> Void

    public let configuration: RunnerConfiguration
    private let driver: any AutomationDriver
    private var isRunning = false

    public init(
        driver: any AutomationDriver,
        configuration: RunnerConfiguration = .init()
    ) {
        self.driver = driver
        self.configuration = configuration
    }

    /// Executes a workflow. Expected automation failures are represented in the returned result,
    /// making this API convenient for both the GUI and a CLI exit-code adapter.
    public func run(
        _ workflow: Workflow,
        variables overrides: [String: String] = [:],
        onStep: StepTraceHandler? = nil
    ) async -> WorkflowRunResult {
        let runStartedAt = Date()
        var traces: [StepTrace] = []

        guard !isRunning else {
            return WorkflowRunResult(workflowName: workflow.name, status: .failed,
                startedAt: runStartedAt, endedAt: Date(), steps: [],
                message: "This runner already has an active workflow.")
        }
        isRunning = true
        defer { isRunning = false }

        do {
            guard configuration.defaultTimeout.isFinite, configuration.defaultTimeout > 0,
                  configuration.defaultTimeout <= WorkflowSchemaValidator.maximumDuration,
                  configuration.pollingInterval.isFinite, configuration.pollingInterval > 0,
                  configuration.pollingInterval <= 60 else {
                throw WorkflowRunnerError.invalidWorkflow("Runner timeout and polling interval must be finite, positive, bounded values.")
            }
            try WorkflowSchemaValidator().validateOrThrow(workflow)
        } catch {
            return WorkflowRunResult(
                workflowName: workflow.name,
                status: .failed,
                startedAt: runStartedAt,
                endedAt: Date(),
                steps: [],
                message: error.localizedDescription
            )
        }

        let resolvedVariables: ResolvedVariables
        do {
            resolvedVariables = try VariableResolver.resolve(
                declarations: workflow.variables,
                overrides: overrides
            )
        } catch {
            return WorkflowRunResult(
                workflowName: workflow.name,
                status: .failed,
                startedAt: runStartedAt,
                endedAt: Date(),
                steps: [],
                message: error.localizedDescription
            )
        }

        // Resolve every action before the first effect, so a bad late placeholder cannot leave a
        // partially executed workflow. Variable values are substituted exactly once.
        let actions: [StepAction]
        do {
            actions = try workflow.steps.map { try VariableResolver.interpolate($0.action, using: resolvedVariables.values) }
        } catch {
            return WorkflowRunResult(workflowName: workflow.name, status: .failed,
                startedAt: runStartedAt, endedAt: Date(), steps: [],
                message: resolvedVariables.redacting(error.localizedDescription))
        }

        var runFailed = false
        for (index, step) in workflow.steps.enumerated() {
            if Task.isCancelled {
                let now = Date()
                let trace = StepTrace(
                    stepID: step.id,
                    action: step.action.kind,
                    status: .cancelled,
                    attempts: 0,
                    startedAt: now,
                    endedAt: now,
                    message: "Run cancelled."
                )
                traces.append(trace)
                onStep?(trace)
                appendSkippedSteps(
                    Array(workflow.steps.dropFirst(index + 1)),
                    message: "Run cancelled.",
                    traces: &traces,
                    onStep: onStep
                )
                return WorkflowRunResult(
                    workflowName: workflow.name,
                    status: .cancelled,
                    startedAt: runStartedAt,
                    endedAt: Date(),
                    steps: traces,
                    message: "Run cancelled."
                )
            }

            var resolvedStep = step
            resolvedStep.action = actions[index]
            var trace = await run(step: resolvedStep)
            trace.message = trace.message.map(resolvedVariables.redacting)
            traces.append(trace)
            onStep?(trace)

            if trace.status == .cancelled {
                appendSkippedSteps(
                    Array(workflow.steps.dropFirst(index + 1)),
                    message: "Run cancelled.",
                    traces: &traces,
                    onStep: onStep
                )
                return WorkflowRunResult(
                    workflowName: workflow.name,
                    status: .cancelled,
                    startedAt: runStartedAt,
                    endedAt: Date(),
                    steps: traces,
                    message: trace.message
                )
            }

            if trace.status == .failed {
                runFailed = true
                guard configuration.continueAfterFailure else {
                    appendSkippedSteps(
                        Array(workflow.steps.dropFirst(index + 1)),
                        message: "Skipped after step '\(step.id)' failed.",
                        traces: &traces,
                        onStep: onStep
                    )
                    return WorkflowRunResult(
                        workflowName: workflow.name,
                        status: .failed,
                        startedAt: runStartedAt,
                        endedAt: Date(),
                        steps: traces,
                        message: trace.message
                    )
                }
            }
        }

        return WorkflowRunResult(
            workflowName: workflow.name,
            status: runFailed ? .failed : .succeeded,
            startedAt: runStartedAt,
            endedAt: Date(),
            steps: traces,
            message: nil
        )
    }

    private func run(step: Step) async -> StepTrace {
        let startedAt = Date()
        let timeout = step.timeout ?? configuration.defaultTimeout
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        let maximumAttempts = max(1, step.retry.maxAttempts)
        var attempts = 0
        var lastError: Error?

        while attempts < maximumAttempts {
            if ContinuousClock.now >= deadline {
                lastError = WorkflowRunnerError.timeout(stepID: step.id, seconds: timeout)
                break
            }
            attempts += 1

            do {
                try Task.checkCancellation()
                try await withTimeout(deadline: deadline, stepID: step.id, reportedTimeout: timeout) { [driver, configuration] in
                    try await Self.execute(
                        step: step,
                        driver: driver,
                        pollingInterval: configuration.pollingInterval
                    )
                }
                try Task.checkCancellation()
                return StepTrace(
                    stepID: step.id,
                    action: step.action.kind,
                    status: .succeeded,
                    attempts: attempts,
                    startedAt: startedAt,
                    endedAt: Date()
                )
            } catch is CancellationError {
                return StepTrace(
                    stepID: step.id,
                    action: step.action.kind,
                    status: .cancelled,
                    attempts: attempts,
                    startedAt: startedAt,
                    endedAt: Date(),
                    message: "Run cancelled."
                )
            } catch {
                lastError = error
                if case WorkflowRunnerError.timeout = error { break }
                guard attempts < maximumAttempts else { break }
                do {
                    try await Task.sleep(until: min(deadline, ContinuousClock.now.advanced(by: .seconds(step.retry.delay))), clock: .continuous)
                } catch {
                    return StepTrace(
                        stepID: step.id,
                        action: step.action.kind,
                        status: .cancelled,
                        attempts: attempts,
                        startedAt: startedAt,
                        endedAt: Date(),
                        message: "Run cancelled."
                    )
                }
            }
        }

        return StepTrace(
            stepID: step.id,
            action: step.action.kind,
            status: .failed,
            attempts: attempts,
            startedAt: startedAt,
            endedAt: Date(),
            message: lastError?.localizedDescription ?? "Step failed."
        )
    }

    private nonisolated static func execute(
        step: Step,
        driver: any AutomationDriver,
        pollingInterval: TimeInterval
    ) async throws {
        try AutomationExecutionContext.check()
        switch step.action {
        case .activateApp(let target):
            try await driver.activateApp(target)
        case .press(let locator):
            try await driver.press(locator)
        case .setValue(let locator, let value):
            try await driver.setValue(value, on: locator)
        case .hotKey(let hotKey):
            try await driver.hotKey(hotKey)
        case .waitFor(let locator):
            while true {
                try AutomationExecutionContext.check()
                if try await driver.exists(locator) { break }
                try await Task.sleep(for: .seconds(max(0.01, pollingInterval)))
            }
        case .assertExists(let locator):
            guard try await driver.exists(locator) else {
                throw WorkflowRunnerError.assertionFailed(stepID: step.id)
            }
        case .pause(let duration):
            try await Task.sleep(for: .seconds(max(0, duration)))
        }
        try AutomationExecutionContext.check()
    }

    private func withTimeout<T: Sendable>(
        deadline: ContinuousClock.Instant,
        stepID: String,
        reportedTimeout: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Structured children are always joined, including on cancellation or error. Never
            // race detached AX work: that would allow a late click after a completed run.
            defer { group.cancelAll() }
            group.addTask {
                try await AutomationExecutionContext.$deadline.withValue(.init(instant: deadline, stepID: stepID, timeout: reportedTimeout)) {
                    try AutomationExecutionContext.check()
                    return try await operation()
                }
            }
            group.addTask {
                try await Task.sleep(until: deadline, clock: .continuous)
                throw WorkflowRunnerError.timeout(stepID: stepID, seconds: reportedTimeout)
            }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            return result
        }
    }

    private func appendSkippedSteps(
        _ steps: [Step],
        message: String,
        traces: inout [StepTrace],
        onStep: StepTraceHandler?
    ) {
        for step in steps {
            let now = Date()
            let trace = StepTrace(
                stepID: step.id,
                action: step.action.kind,
                status: .skipped,
                attempts: 0,
                startedAt: now,
                endedAt: now,
                message: message
            )
            traces.append(trace)
            onStep?(trace)
        }
    }
}
