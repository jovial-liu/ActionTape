import ActionTapeCore
import Foundation

public enum CLIExecutor {
    public static func execute(arguments: [String]) async -> Int32 {
        do {
            let options = try CLIOptions.parse(arguments)
            switch options.command {
            case .help:
                print(CLIHelp.text(topic: options.helpTopic))
                return 0
            case .version:
                print(ActionTapeCore.version)
                return 0
            case .validate:
                return try validate(options)
            case .run:
                return try await run(options)
            case .inspect:
                return try await inspect(options)
            case .doctor:
                let trusted = MacOSAccessibilityDriver.isTrusted(prompt: options.requestAccess)
                print("ActionTape: \(ActionTapeCore.version)")
                print("System: \(ProcessInfo.processInfo.operatingSystemVersionString)")
                print("Accessibility: \(trusted ? "granted" : "not granted")")
                print("Network services: none")
                if !trusted { writeError(permissionMessage) }
                return trusted ? 0 : 77
            }
        } catch let error as CLIUsageError {
            writeError("Usage error: \(error.localizedDescription)")
            return 64
        } catch is CancellationError {
            writeError("Cancelled.")
            return 130
        } catch {
            writeError(error.localizedDescription)
            return 65
        }
    }

    private static func validate(_ options: CLIOptions) throws -> Int32 {
        let workflow = try load(options)
        let issues = WorkflowSchemaValidator().validate(workflow)
        if options.json {
            print(try jsonString(issues))
        } else {
            for issue in issues {
                print("\(issue.severity.rawValue): \(safeTerminal(issue.path)): \(safeTerminal(issue.message))")
            }
            if !issues.contains(where: { $0.severity == .error }) {
                print("Valid: \(safeTerminal(workflow.name)) — \(workflow.steps.count) steps, format v\(workflow.formatVersion)")
            }
        }
        return issues.contains(where: { $0.severity == .error }) ? 65 : 0
    }

    private static func run(_ options: CLIOptions) async throws -> Int32 {
        let workflow = try load(options)
        try WorkflowSchemaValidator().validateOrThrow(workflow)
        let overrides = try options.resolvedVariables(environment: ProcessInfo.processInfo.environment)
        try validateInputs(workflow, overrides: overrides)
        if options.dryRun {
            print("Dry run: \(safeTerminal(workflow.name))")
            for step in workflow.steps {
                print("  \(safeTerminal(step.id)): \(step.action.kind.rawValue)")
            }
            print("Validated \(workflow.steps.count) steps. No UI actions were performed.")
            return 0
        }

        let traceURL = options.trace.map { URL(fileURLWithPath: $0) }
        if let traceURL {
            try TraceWriter.preflight(destination: traceURL, source: URL(fileURLWithPath: options.tape!))
        }
        let requiresAccessibility = workflow.steps.contains { $0.action.kind != .pause }
        guard !requiresAccessibility || MacOSAccessibilityDriver.isTrusted() else {
            writeError(permissionMessage)
            return 77
        }
        try Task.checkCancellation()
        let driver = MacOSAccessibilityDriver(configuration: .init(
            allowCoordinateFallback: options.allowCoordinateFallback
        ))
        let runner = WorkflowRunner(driver: driver, configuration: .init(
            defaultTimeout: options.timeout,
            continueAfterFailure: options.continueAfterFailure
        ))
        print("Running: \(safeTerminal(workflow.name))")
        let result = await runner.run(workflow, variables: overrides) { step in
            let seconds = String(format: "%.2fs", step.duration)
            print("\(step.status.rawValue): \(safeTerminal(step.stepID))  \(seconds)")
            if let message = step.message { print("  \(safeTerminal(message))") }
        }
        if let traceURL {
            try TraceWriter.write(result, to: traceURL)
            print("Trace saved: \(safeTerminal(traceURL.path))")
        }
        switch result.status {
        case .succeeded:
            print("Completed in \(String(format: "%.2fs", result.duration)).")
            return 0
        case .failed:
            writeError("Run failed: \(result.message ?? "one or more steps failed")")
            return 1
        case .cancelled:
            writeError("Run cancelled.")
            return 130
        }
    }

    private static func inspect(_ options: CLIOptions) async throws -> Int32 {
        guard MacOSAccessibilityDriver.isTrusted() else {
            writeError(permissionMessage)
            return 77
        }
        guard let point = options.point else { throw CLIUsageError("A screen point is required.") }
        let driver = MacOSAccessibilityDriver()
        let locator = try await driver.buildLocator(
            at: .init(x: point.x, y: point.y),
            includeCoordinateFallback: options.includeCoordinateFallback
        )
        print(try jsonString(locator))
        return 0
    }

    private static func load(_ options: CLIOptions) throws -> Workflow {
        guard let tape = options.tape else { throw CLIUsageError("A workflow path is required.") }
        return try WorkflowYAML.load(from: URL(fileURLWithPath: tape), validate: false)
    }

    private static func validateInputs(_ workflow: Workflow, overrides: [String: String]) throws {
        let resolved = try VariableResolver.resolve(declarations: workflow.variables, overrides: overrides)
        for step in workflow.steps {
            switch step.action {
            case .activateApp(let target):
                _ = try VariableResolver.interpolate(target, using: resolved.values)
            case .press(let locator), .waitFor(let locator), .assertExists(let locator):
                _ = try VariableResolver.interpolate(locator, using: resolved.values)
            case .setValue(let locator, let value):
                _ = try VariableResolver.interpolate(locator, using: resolved.values)
                _ = try VariableResolver.interpolate(value, using: resolved.values)
            case .hotKey, .pause:
                break
            }
        }
    }

    private static let permissionMessage = """
    Accessibility permission is required for this CLI or its terminal host.
    Run actiontape doctor --request-access, then check System Settings →
    Privacy & Security → Accessibility. Granting access to Studio alone may not
    authorize this executable. ActionTape never changes permissions itself.
    """

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data((safeTerminal(message) + "\n").utf8))
    }

    private static func jsonString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    /// Tape content is untrusted terminal text, not ANSI control sequences.
    static func safeTerminal(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.filter {
            $0 == "\n" || $0 == "\t" || !CharacterSet.controlCharacters.contains($0)
        }))
    }
}

public enum TraceWriter {
    public static func preflight(destination: URL, source: URL) throws {
        guard destination.standardizedFileURL.resolvingSymlinksInPath()
                != source.standardizedFileURL.resolvingSymlinksInPath() else {
            throw CLIUsageError("The trace destination must not overwrite the source tape.")
        }
        let parent = destination.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isWritableFile(atPath: parent.path) else {
            throw CLIUsageError("The trace destination directory must exist and be writable.")
        }
        if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw CLIUsageError("The trace destination must be a file, not a directory.")
        }
    }

    public static func write(_ result: WorkflowRunResult, to destination: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(result).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}
