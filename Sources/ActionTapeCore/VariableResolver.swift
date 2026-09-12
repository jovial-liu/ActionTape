import Foundation

public enum VariableResolutionError: Error, Sendable, Equatable, LocalizedError {
    case missingRequired(String)
    case unresolved(String)
    case malformedPlaceholder(String)
    case undeclared(String)
    case emptyCriterion

    public var errorDescription: String? {
        switch self {
        case .missingRequired(let name): "Required variable '\(name)' was not provided."
        case .unresolved(let name): "Variable '\(name)' has no value."
        case .malformedPlaceholder: "Malformed variable placeholder; use '{{name}}'."
        case .undeclared(let name): "Variable '\(name)' is not declared by this workflow."
        case .emptyCriterion: "Variable substitution produced an empty application or locator criterion."
        }
    }
}

public struct ResolvedVariables: Sendable, Equatable {
    public var values: [String: String]
    public var secretNames: Set<String>

    public init(values: [String: String], secretNames: Set<String> = []) {
        self.values = values
        self.secretNames = secretNames
    }

    public func redactedValue(for name: String) -> String? {
        guard let value = values[name] else { return nil }
        return secretNames.contains(name) ? "••••••" : value
    }

    /// Redacts diagnostics from drivers too, which may include interpolated application names or values.
    public func redacting(_ message: String) -> String {
        let secrets = Set(secretNames.compactMap { values[$0] }.filter { !$0.isEmpty })
            .sorted { $0.count > $1.count }
        return secrets.reduce(message) { $0.replacingOccurrences(of: $1, with: "••••••") }
    }
}

public enum VariableResolver {
    public static func resolve(
        declarations: [String: WorkflowVariable],
        overrides: [String: String] = [:]
    ) throws -> ResolvedVariables {
        if let unknown = overrides.keys.sorted().first(where: { declarations[$0] == nil }) {
            throw VariableResolutionError.undeclared(unknown)
        }
        var values = overrides
        var secrets = Set<String>()

        for (name, variable) in declarations.sorted(by: { $0.key < $1.key }) {
            if variable.secret { secrets.insert(name) }
            if values[name] == nil, let defaultValue = variable.defaultValue {
                values[name] = defaultValue
            }
            if (values[name] == nil || values[name]?.isEmpty == true), variable.required {
                throw VariableResolutionError.missingRequired(name)
            }
            if values[name] == nil {
                values[name] = ""
            }
        }
        return ResolvedVariables(values: values, secretNames: secrets)
    }

    public static func interpolate(_ input: String, using values: [String: String]) throws -> String {
        var result = ""
        var cursor = input.startIndex

        while let opening = input[cursor...].range(of: "{{") {
            result.append(contentsOf: input[cursor..<opening.lowerBound])
            guard let closing = input[opening.upperBound...].range(of: "}}") else {
                throw VariableResolutionError.malformedPlaceholder(input)
            }
            let rawName = input[opening.upperBound..<closing.lowerBound]
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidName(name) else { throw VariableResolutionError.malformedPlaceholder(input) }
            guard let value = values[name] else { throw VariableResolutionError.unresolved(name) }
            result.append(value)
            cursor = closing.upperBound
        }
        result.append(contentsOf: input[cursor...])
        return result
    }

    public static func placeholderNames(in input: String) -> [String] {
        var names: [String] = []
        var cursor = input.startIndex
        while let opening = input[cursor...].range(of: "{{"),
              let closing = input[opening.upperBound...].range(of: "}}") {
            let name = input[opening.upperBound..<closing.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { names.append(name) }
            cursor = closing.upperBound
        }
        return names
    }

    public static func interpolate(_ locator: Locator, using values: [String: String]) throws -> Locator {
        Locator(
            identifier: try interpolateCriterion(locator.identifier, using: values),
            role: try interpolateCriterion(locator.role, using: values),
            title: try interpolateCriterion(locator.title, using: values),
            description: try interpolateCriterion(locator.elementDescription, using: values),
            ancestry: try locator.ancestry.map { ancestor in
                LocatorAncestor(
                    identifier: try interpolateCriterion(ancestor.identifier, using: values),
                    role: try interpolateCriterion(ancestor.role, using: values),
                    title: try interpolateCriterion(ancestor.title, using: values)
                )
            },
            fallback: locator.fallback
        )
    }

    public static func interpolate(_ target: AppTarget, using values: [String: String]) throws -> AppTarget {
        AppTarget(
            bundleIdentifier: try interpolateCriterion(target.bundleIdentifier, using: values),
            name: try interpolateCriterion(target.name, using: values),
            path: try interpolateCriterion(target.path, using: values)
        )
    }

    public static func interpolate(_ action: StepAction, using values: [String: String]) throws -> StepAction {
        switch action {
        case .activateApp(let target): return .activateApp(try interpolate(target, using: values))
        case .press(let locator): return .press(try interpolate(locator, using: values))
        case .setValue(let locator, let value):
            return .setValue(locator: try interpolate(locator, using: values), value: try interpolate(value, using: values))
        case .hotKey(let hotKey):
            return .hotKey(.init(key: try interpolate(hotKey.key, using: values), modifiers: hotKey.modifiers))
        case .waitFor(let locator): return .waitFor(try interpolate(locator, using: values))
        case .assertExists(let locator): return .assertExists(try interpolate(locator, using: values))
        case .pause: return action
        }
    }

    static func isValidName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first,
              CharacterSet.letters.union(CharacterSet(charactersIn: "_")).contains(first) else { return false }
        return name.unicodeScalars.dropFirst().allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.-")).contains($0)
        }
    }

    private static func interpolateCriterion(_ input: String?, using values: [String: String]) throws -> String? {
        guard let input else { return nil }
        let result = try interpolate(input, using: values)
        if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw VariableResolutionError.emptyCriterion
        }
        return result
    }
}
