import Foundation

public struct CLIUsageError: Error, LocalizedError, Sendable, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct CLIOptions: Sendable, Equatable {
    public enum Command: String, Sendable {
        case help, version, validate, run, inspect, doctor
    }

    public var command: Command
    public var helpTopic: String?
    public var tape: String?
    public var variables: [String: String] = [:]
    public var variableEnvironment: [String: String] = [:]
    public var trace: String?
    public var timeout: Double = 10
    public var allowCoordinateFallback = false
    public var continueAfterFailure = false
    public var dryRun = false
    public var json = false
    public var point: ScreenPoint?
    public var includeCoordinateFallback = false
    public var requestAccess = false

    public struct ScreenPoint: Sendable, Equatable {
        public let x: Double
        public let y: Double
    }

    public static func parse(_ arguments: [String]) throws -> CLIOptions {
        guard let first = arguments.first else { return .init(command: .help) }
        if ["--help", "-h", "help"].contains(first) {
            return .init(command: .help, helpTopic: arguments.dropFirst().first)
        }
        if ["--version", "-V", "version"].contains(first) {
            guard arguments.count == 1 else { throw CLIUsageError("Version takes no arguments.") }
            return .init(command: .version)
        }
        guard let command = Command(rawValue: first), command != .help, command != .version else {
            throw CLIUsageError("Unknown command. Run actiontape --help.")
        }
        var options = CLIOptions(command: command)
        var seen = Set<String>()
        var index = 1
        var positionalOnly = false

        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if !positionalOnly && argument == "--" {
                positionalOnly = true
                continue
            }
            if !positionalOnly && ["--help", "-h"].contains(argument) {
                return .init(command: .help, helpTopic: command.rawValue)
            }
            if !positionalOnly && argument.hasPrefix("-") {
                let parts = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = String(parts[0])
                let inlineValue = parts.count == 2 ? String(parts[1]) : nil
                let repeatable = ["--variable", "-v", "--variable-env"].contains(key)
                guard repeatable || seen.insert(key).inserted else {
                    throw CLIUsageError("Option \(key) may only be specified once.")
                }
                func value() throws -> String {
                    if let inlineValue { return inlineValue }
                    guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                        throw CLIUsageError("Option \(key) requires a value.")
                    }
                    defer { index += 1 }
                    return arguments[index]
                }
                func flag() throws {
                    if inlineValue != nil { throw CLIUsageError("Flag \(key) does not take a value.") }
                }
                func require(_ allowed: Command...) throws {
                    guard allowed.contains(command) else {
                        throw CLIUsageError("Option \(key) is not supported by \(command.rawValue).")
                    }
                }
                switch key {
                case "--variable", "-v", "--variable-env":
                    try require(.run)
                    let pair = try assignment(try value())
                    guard options.variables[pair.name] == nil, options.variableEnvironment[pair.name] == nil else {
                        throw CLIUsageError("Variable \(pair.name) was supplied more than once.")
                    }
                    if key == "--variable-env" {
                        guard validName(pair.value) else { throw CLIUsageError("Environment variable names must be valid identifiers.") }
                        options.variableEnvironment[pair.name] = pair.value
                    } else {
                        options.variables[pair.name] = pair.value
                    }
                case "--trace":
                    try require(.run)
                    options.trace = try nonEmpty(value(), option: key)
                case "--timeout":
                    try require(.run)
                    guard let seconds = Double(try value()), seconds.isFinite, seconds > 0, seconds <= 3_600 else {
                        throw CLIUsageError("Timeout must be a finite number greater than 0 and at most 3600 seconds.")
                    }
                    options.timeout = seconds
                case "--allow-coordinate-fallback":
                    try require(.run); try flag(); options.allowCoordinateFallback = true
                case "--continue-after-failure":
                    try require(.run); try flag(); options.continueAfterFailure = true
                case "--dry-run":
                    try require(.run); try flag(); options.dryRun = true
                case "--json":
                    try require(.validate); try flag(); options.json = true
                case "--point":
                    try require(.inspect)
                    options.point = try parsePoint(value())
                case "--include-coordinate-fallback":
                    try require(.inspect); try flag(); options.includeCoordinateFallback = true
                case "--request-access":
                    try require(.doctor); try flag(); options.requestAccess = true
                default:
                    throw CLIUsageError("Unknown option for \(command.rawValue). Run actiontape \(command.rawValue) --help.")
                }
            } else {
                guard [.run, .validate].contains(command), options.tape == nil else {
                    throw CLIUsageError("Unexpected positional argument.")
                }
                options.tape = try nonEmpty(argument, option: "tape")
            }
        }
        if [.run, .validate].contains(command), options.tape == nil {
            throw CLIUsageError("A workflow path is required.")
        }
        if command == .inspect, options.point == nil {
            throw CLIUsageError("Inspect requires --point x,y in Quartz global screen coordinates.")
        }
        if options.dryRun && options.trace != nil {
            throw CLIUsageError("--trace cannot be used with --dry-run because no run occurs.")
        }
        return options
    }

    public func resolvedVariables(environment: [String: String]) throws -> [String: String] {
        var result = variables
        for (name, environmentName) in variableEnvironment {
            guard let value = environment[environmentName] else {
                throw CLIUsageError("Required environment variable \(environmentName) is not set.")
            }
            result[name] = value
        }
        return result
    }

    private static func nonEmpty(_ value: String, option: String) throws -> String {
        guard !value.isEmpty else { throw CLIUsageError("\(option) must not be empty.") }
        return value
    }

    private static func assignment(_ value: String) throws -> (name: String, value: String) {
        guard let separator = value.firstIndex(of: "=") else {
            throw CLIUsageError("Variables must use name=value. The supplied value is not printed for privacy.")
        }
        let name = String(value[..<separator])
        guard validName(name) else { throw CLIUsageError("Variable names must be valid identifiers.") }
        return (name, String(value[value.index(after: separator)...]))
    }

    private static func validName(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }

    private static func parsePoint(_ value: String) throws -> ScreenPoint {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let x = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let y = Double(parts[1].trimmingCharacters(in: .whitespaces)),
              x.isFinite, y.isFinite else {
            throw CLIUsageError("Point must contain two finite numbers, for example --point 640,360.")
        }
        return ScreenPoint(x: x, y: y)
    }
}
