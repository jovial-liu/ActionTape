import Foundation
import Yams
import CYaml

public enum ValidationSeverity: String, Codable, Sendable {
    case error
    case warning
}

public struct ValidationIssue: Codable, Sendable, Equatable, Identifiable {
    public var path: String
    public var code: String
    public var message: String
    public var severity: ValidationSeverity

    public var id: String { "\(path):\(code)" }

    public init(path: String, code: String, message: String, severity: ValidationSeverity = .error) {
        self.path = path
        self.code = code
        self.message = message
        self.severity = severity
    }
}

public struct WorkflowValidationError: Error, Codable, Sendable, Equatable, LocalizedError {
    public var issues: [ValidationIssue]

    public init(issues: [ValidationIssue]) {
        self.issues = issues
    }

    public var errorDescription: String? {
        issues.map { "\($0.path): \($0.message)" }.joined(separator: "\n")
    }
}

public enum WorkflowYAMLError: Error, Sendable, Equatable, LocalizedError {
    case decoding(String)
    case encoding(String)
    case validation(WorkflowValidationError)
    case file(String)

    public var errorDescription: String? {
        switch self {
        case .decoding(let message): "Invalid workflow YAML: \(message)"
        case .encoding(let message): "Could not encode workflow YAML: \(message)"
        case .validation(let error): error.localizedDescription
        case .file(let message): message
        }
    }
}

public enum WorkflowYAML {
    public static let maximumFileBytes = 1_048_576

    public static func decode(_ yaml: String, validate: Bool = true) throws -> Workflow {
        let workflow: Workflow
        do {
            try preflight(yaml)
            let parser = try Parser(yaml: yaml, resolver: .basic.appending(.merge), encoding: .utf8)
            workflow = try withExtendedLifetime(parser) {
                guard let root = try parser.singleRoot() else {
                    throw WorkflowYAMLError.decoding("The document is empty.")
                }
                try validateShape(root, as: .workflow, path: "workflow")
                return try YAMLDecoder(encoding: .utf8).decode(Workflow.self, from: root)
            }
        } catch let error as WorkflowYAMLError {
            throw error
        } catch {
            // Parser errors may quote an entire input line, including literal passwords. Report
            // the schema location without echoing imported content into logs or crash reports.
            if let error = error as? DecodingError {
                let context: DecodingError.Context
                switch error {
                case .dataCorrupted(let value), .keyNotFound(_, let value),
                     .typeMismatch(_, let value), .valueNotFound(_, let value): context = value
                @unknown default: throw WorkflowYAMLError.decoding("The document does not match the workflow schema.")
                }
                let path = context.codingPath.map(\.stringValue).joined(separator: ".")
                throw WorkflowYAMLError.decoding("Missing or invalid field at \(path.isEmpty ? "workflow" : path).")
            }
            throw WorkflowYAMLError.decoding("Malformed YAML. Check indentation, quoting, and duplicate keys.")
        }

        if validate {
            do {
                try WorkflowSchemaValidator().validateOrThrow(workflow)
            } catch let error as WorkflowValidationError {
                throw WorkflowYAMLError.validation(error)
            }
        }
        return workflow
    }

    public static func encode(_ workflow: Workflow, validate: Bool = true) throws -> String {
        if validate {
            do {
                try WorkflowSchemaValidator().validateOrThrow(workflow)
            } catch let error as WorkflowValidationError {
                throw WorkflowYAMLError.validation(error)
            }
        }
        do {
            return try YAMLEncoder().encode(workflow)
        } catch {
            throw WorkflowYAMLError.encoding(String(describing: error))
        }
    }

    public static func load(from url: URL, validate: Bool = true) throws -> Workflow {
        do {
            guard url.isFileURL else { throw WorkflowYAMLError.file("Workflow input must be a local file.") }
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw WorkflowYAMLError.file("Workflow input must be a regular file.")
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: maximumFileBytes + 1) ?? Data()
            guard data.count <= maximumFileBytes else {
                throw WorkflowYAMLError.decoding("Workflow files must not exceed 1 MiB.")
            }
            guard let yaml = String(data: data, encoding: .utf8) else {
                throw WorkflowYAMLError.decoding("Workflow files must be UTF-8.")
            }
            return try decode(yaml, validate: validate)
        } catch let error as WorkflowYAMLError {
            throw error
        } catch {
            throw WorkflowYAMLError.file("Could not read \(url.path): \(error.localizedDescription)")
        }
    }

    public static func save(_ workflow: Workflow, to url: URL, validate: Bool = true) throws {
        let yaml = try encode(workflow, validate: validate)
        do {
            try yaml.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw WorkflowYAMLError.file("Could not write \(url.path): \(error.localizedDescription)")
        }
    }

    /// Inspect libyaml tokens before Yams constructs recursive nodes. This blocks alias
    /// expansion and excessive nesting even in unused fields or complex mapping keys.
    private static func preflight(_ yaml: String) throws {
        guard yaml.utf8.count <= maximumFileBytes else {
            throw WorkflowYAMLError.decoding("Workflow files must not exceed 1 MiB.")
        }
        var parser = yaml_parser_t()
        guard yaml_parser_initialize(&parser) != 0 else {
            throw WorkflowYAMLError.decoding("Could not initialize the YAML parser.")
        }
        defer { yaml_parser_delete(&parser) }
        try Array(yaml.utf8).withUnsafeBufferPointer { buffer in
            yaml_parser_set_input_string(&parser, buffer.baseAddress, buffer.count)
            var depth = 0
            var tokens = 0
            while true {
                var token = yaml_token_t()
                guard yaml_parser_scan(&parser, &token) != 0 else {
                    throw WorkflowYAMLError.decoding("Malformed YAML near line \(parser.problem_mark.line + 1).")
                }
                let type = token.type
                yaml_token_delete(&token)
                tokens += 1
                guard tokens <= 100_000 else { throw WorkflowYAMLError.decoding("Workflow YAML contains too many tokens.") }
                switch type {
                case YAML_ALIAS_TOKEN, YAML_ANCHOR_TOKEN, YAML_TAG_TOKEN:
                    throw WorkflowYAMLError.decoding("YAML anchors, aliases, and explicit tags are not supported in workflows.")
                case YAML_BLOCK_SEQUENCE_START_TOKEN, YAML_BLOCK_MAPPING_START_TOKEN,
                     YAML_FLOW_SEQUENCE_START_TOKEN, YAML_FLOW_MAPPING_START_TOKEN:
                    depth += 1
                    guard depth <= 32 else { throw WorkflowYAMLError.decoding("Workflow YAML nesting exceeds 32 levels.") }
                case YAML_BLOCK_END_TOKEN, YAML_FLOW_SEQUENCE_END_TOKEN, YAML_FLOW_MAPPING_END_TOKEN:
                    depth -= 1
                case YAML_STREAM_END_TOKEN: return
                default: break
                }
            }
        }
    }

    private enum Shape {
        case workflow, variables, variable, steps, step, app, locator, ancestry, ancestor, fallback, retry, hotKey, modifiers, scalar

        var fields: [String: Shape] {
            switch self {
            case .workflow: ["formatVersion": .scalar, "name": .scalar, "description": .scalar, "variables": .variables, "steps": .steps]
            case .variable: ["default": .scalar, "required": .scalar, "secret": .scalar, "description": .scalar]
            case .step: ["id": .scalar, "name": .scalar, "action": .scalar, "timeout": .scalar, "retry": .retry,
                         "app": .app, "locator": .locator, "value": .scalar, "hotKey": .hotKey, "duration": .scalar]
            case .app: ["bundleIdentifier": .scalar, "name": .scalar, "path": .scalar]
            case .locator: ["identifier": .scalar, "role": .scalar, "title": .scalar, "description": .scalar, "ancestry": .ancestry, "fallback": .fallback]
            case .ancestor: ["identifier": .scalar, "role": .scalar, "title": .scalar]
            case .fallback: ["x": .scalar, "y": .scalar, "coordinateSpace": .scalar]
            case .retry: ["maxAttempts": .scalar, "delay": .scalar]
            case .hotKey: ["key": .scalar, "modifiers": .modifiers]
            default: [:]
            }
        }
    }

    private static func validateShape(_ node: Node, as shape: Shape, path: String) throws {
        if case .scalar = node, node.null != nil { return } // Codable decides which fields permit null.
        switch shape {
        case .scalar:
            guard case .scalar = node else { throw WorkflowYAMLError.decoding("Expected a scalar at \(path).") }
        case .steps, .ancestry, .modifiers:
            guard case .sequence(let sequence) = node else { throw WorkflowYAMLError.decoding("Expected a list at \(path).") }
            let limit = shape == .steps ? WorkflowSchemaValidator.maximumSteps : (shape == .ancestry ? 32 : 5)
            guard sequence.count <= limit else { throw WorkflowYAMLError.decoding("Too many entries at \(path); maximum is \(limit).") }
            let child: Shape = shape == .steps ? .step : (shape == .ancestry ? .ancestor : .scalar)
            for (index, value) in sequence.enumerated() { try validateShape(value, as: child, path: "\(path)[\(index)]") }
        default:
            guard case .mapping(let mapping) = node else { throw WorkflowYAMLError.decoding("Expected an object at \(path).") }
            if shape == .variables, mapping.count > 256 { throw WorkflowYAMLError.decoding("A workflow may declare at most 256 variables.") }
            for (key, value) in mapping {
                guard case .scalar(let scalar) = key else { throw WorkflowYAMLError.decoding("Object keys must be strings at \(path).") }
                let key = scalar.string
                let child: Shape
                if shape == .variables { child = .variable }
                else {
                    guard let field = shape.fields[key] else {
                        throw WorkflowYAMLError.decoding("Unknown field at \(path). Check the documented workflow schema.")
                    }
                    child = field
                }
                try validateShape(value, as: child, path: shape == .variables ? "\(path).variable" : "\(path).\(key)")
            }
            if shape == .step {
                let action = mapping[Node("action")]?.string
                let payloads: [String: Set<String>] = ["activateApp": ["app"], "press": ["locator"],
                    "setValue": ["locator", "value"], "hotKey": ["hotKey"], "waitFor": ["locator"],
                    "assertExists": ["locator"], "pause": ["duration"]]
                if let action, let allowed = payloads[action] {
                    let common: Set<String> = ["id", "name", "action", "timeout", "retry"]
                    guard mapping.allSatisfy({ common.union(allowed).contains($0.key.string ?? "") }) else {
                        throw WorkflowYAMLError.decoding("Unexpected action payload at \(path).")
                    }
                }
            }
        }
    }
}

public struct WorkflowSchemaValidator: Sendable {
    public static let maximumSteps = 2_000
    public static let maximumDuration: TimeInterval = 86_400
    public init() {}

    public func validate(_ workflow: Workflow) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if workflow.formatVersion != Workflow.currentFormatVersion {
            issues.append(.init(
                path: "formatVersion",
                code: "unsupported_format",
                message: "Expected formatVersion \(Workflow.currentFormatVersion), got \(workflow.formatVersion)."
            ))
        }
        if workflow.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(path: "name", code: "empty_name", message: "Workflow name must not be empty."))
        }
        if workflow.steps.isEmpty {
            issues.append(.init(path: "steps", code: "empty_steps", message: "A workflow must contain at least one step."))
        }
        if workflow.steps.count > Self.maximumSteps {
            issues.append(.init(path: "steps", code: "too_many_steps", message: "A workflow may contain at most 2,000 steps."))
        }
        if workflow.variables.count > 256 {
            issues.append(.init(path: "variables", code: "too_many_variables", message: "A workflow may declare at most 256 variables."))
        }

        for (name, variable) in workflow.variables.sorted(by: { $0.key < $1.key }) {
            let path = "variables.\(name)"
            if !isValidVariableName(name) {
                issues.append(.init(
                    path: path,
                    code: "invalid_variable_name",
                    message: "Variable names must start with a letter or underscore and contain only letters, digits, underscore, dot, or hyphen."
                ))
            }
            if variable.secret, variable.defaultValue != nil {
                issues.append(.init(
                    path: "\(path).default",
                    code: "secret_default",
                    message: "A secret default is stored in plaintext YAML; prefer a run-time override.",
                    severity: .warning
                ))
            }
        }

        var seenIDs = Set<String>()
        for (index, step) in workflow.steps.enumerated() {
            let path = "steps[\(index)]"
            if step.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(path: "\(path).id", code: "empty_step_id", message: "Step id must not be empty."))
            } else if !seenIDs.insert(step.id).inserted {
                issues.append(.init(path: "\(path).id", code: "duplicate_step_id", message: "Step id '\(step.id)' is duplicated."))
            }
            if let timeout = step.timeout, (!timeout.isFinite || timeout <= 0 || timeout > Self.maximumDuration) {
                issues.append(.init(path: "\(path).timeout", code: "invalid_timeout", message: "Timeout must be positive and at most 86,400 seconds."))
            }
            if step.retry.maxAttempts < 1 || step.retry.maxAttempts > 100 {
                issues.append(.init(path: "\(path).retry.maxAttempts", code: "invalid_attempts", message: "maxAttempts must be between 1 and 100."))
            }
            if !step.retry.delay.isFinite || step.retry.delay < 0 || step.retry.delay > Self.maximumDuration {
                issues.append(.init(path: "\(path).retry.delay", code: "invalid_retry_delay", message: "Retry delay must be between 0 and 86,400 seconds."))
            }
            validate(action: step.action, path: path, declarations: Set(workflow.variables.keys), issues: &issues)
        }
        return issues
    }

    public func validateOrThrow(_ workflow: Workflow) throws {
        let errors = validate(workflow).filter { $0.severity == .error }
        if !errors.isEmpty {
            throw WorkflowValidationError(issues: errors)
        }
    }

    private func validate(
        action: StepAction,
        path: String,
        declarations: Set<String>,
        issues: inout [ValidationIssue]
    ) {
        switch action {
        case .activateApp(let app):
            if !app.hasIdentity {
                issues.append(.init(path: "\(path).app", code: "missing_app_identity", message: "Specify bundleIdentifier, name, or path."))
            }
            validatePlaceholders(in: [app.bundleIdentifier, app.name, app.path], path: "\(path).app", declarations: declarations, issues: &issues)
        case .press(let locator), .waitFor(let locator), .assertExists(let locator):
            validate(locator: locator, path: "\(path).locator", declarations: declarations, issues: &issues)
        case .setValue(let locator, let value):
            validate(locator: locator, path: "\(path).locator", declarations: declarations, issues: &issues)
            validatePlaceholders(in: [value], path: "\(path).value", declarations: declarations, issues: &issues)
        case .hotKey(let hotKey):
            if hotKey.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(path: "\(path).hotKey.key", code: "empty_key", message: "Hot-key key must not be empty."))
            }
            if Set(hotKey.modifiers).count != hotKey.modifiers.count {
                issues.append(.init(path: "\(path).hotKey.modifiers", code: "duplicate_modifier", message: "A modifier is listed more than once."))
            }
            validatePlaceholders(in: [hotKey.key], path: "\(path).hotKey.key", declarations: declarations, issues: &issues)
        case .pause(let duration):
            if !duration.isFinite || duration < 0 || duration > Self.maximumDuration {
                issues.append(.init(path: "\(path).duration", code: "invalid_duration", message: "Pause duration must be between 0 and 86,400 seconds."))
            }
        }
    }

    private func validate(
        locator: Locator,
        path: String,
        declarations: Set<String>,
        issues: inout [ValidationIssue]
    ) {
        if !locator.hasSemanticCriteria, locator.fallback == nil {
            issues.append(.init(path: path, code: "empty_locator", message: "Specify a semantic criterion or coordinate fallback."))
        }
        if !locator.hasSemanticCriteria, locator.fallback != nil {
            issues.append(.init(
                path: path,
                code: "coordinate_only_locator",
                message: "Coordinate-only locators require explicitly enabling coordinate fallback and are fragile.",
                severity: .warning
            ))
        }
        if let fallback = locator.fallback, !fallback.x.isFinite || !fallback.y.isFinite {
            issues.append(.init(path: "\(path).fallback", code: "invalid_coordinate", message: "Fallback coordinates must be finite."))
        }
        for (index, ancestor) in locator.ancestry.enumerated() where !ancestor.hasCriteria {
            issues.append(.init(path: "\(path).ancestry[\(index)]", code: "empty_ancestor", message: "An ancestor selector must contain a criterion."))
        }
        if locator.ancestry.count > 32 {
            issues.append(.init(path: "\(path).ancestry", code: "too_many_ancestors", message: "Ancestry may contain at most 32 selectors."))
        }

        var strings: [String?] = [locator.identifier, locator.role, locator.title, locator.elementDescription]
        for ancestor in locator.ancestry {
            strings.append(contentsOf: [ancestor.identifier, ancestor.role, ancestor.title])
        }
        validatePlaceholders(in: strings, path: path, declarations: declarations, issues: &issues)
    }

    private func validatePlaceholders(
        in strings: [String?],
        path: String,
        declarations: Set<String>,
        issues: inout [ValidationIssue]
    ) {
        for string in strings.compactMap({ $0 }) {
            let names = VariableResolver.placeholderNames(in: string)
            do {
                _ = try VariableResolver.interpolate(string, using: Dictionary(names.map { ($0, "value") }, uniquingKeysWith: { first, _ in first }))
            } catch {
                issues.append(.init(path: path, code: "malformed_placeholder", message: "Malformed variable placeholder; use '{{name}}'."))
            }
            for name in names where !declarations.contains(name) {
                issues.append(.init(
                    path: path,
                    code: "undeclared_variable",
                    message: "Variable '{{\(name)}}' is not declared."
                ))
            }
        }
    }

    private func isValidVariableName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first,
              CharacterSet.letters.union(CharacterSet(charactersIn: "_")).contains(first) else { return false }
        return name.unicodeScalars.dropFirst().allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.-")).contains($0)
        }
    }
}
