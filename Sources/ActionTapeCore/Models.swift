import Foundation

/// A complete, portable macOS automation workflow.
public struct Workflow: Codable, Sendable, Equatable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var name: String
    public var description: String?
    public var variables: [String: WorkflowVariable]
    public var steps: [Step]

    public init(
        formatVersion: Int = Workflow.currentFormatVersion,
        name: String,
        description: String? = nil,
        variables: [String: WorkflowVariable] = [:],
        steps: [Step]
    ) {
        self.formatVersion = formatVersion
        self.name = name
        self.description = description
        self.variables = variables
        self.steps = steps
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, name, description, variables, steps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? Self.currentFormatVersion
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        variables = try container.decodeIfPresent([String: WorkflowVariable].self, forKey: .variables) ?? [:]
        steps = try container.decode([Step].self, forKey: .steps)
    }
}

/// A declared input to a workflow. Values are supplied at run time or fall back to `defaultValue`.
public struct WorkflowVariable: Codable, Sendable, Equatable {
    public var defaultValue: String?
    public var required: Bool
    public var secret: Bool
    public var description: String?

    public init(
        defaultValue: String? = nil,
        required: Bool = false,
        secret: Bool = false,
        description: String? = nil
    ) {
        self.defaultValue = defaultValue
        self.required = required
        self.secret = secret
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case defaultValue = "default"
        case required, secret, description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        secret = try container.decodeIfPresent(Bool.self, forKey: .secret) ?? false
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }
}

/// Identifies an application without depending on a localized display name alone.
public struct AppTarget: Codable, Sendable, Equatable {
    public var bundleIdentifier: String?
    public var name: String?
    public var path: String?

    public init(bundleIdentifier: String? = nil, name: String? = nil, path: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.path = path
    }

    public var hasIdentity: Bool {
        [bundleIdentifier, name, path].contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// A semantic locator, optionally carrying a disabled-by-default coordinate escape hatch.
public struct Locator: Codable, Sendable, Equatable {
    public var identifier: String?
    public var role: String?
    public var title: String?
    public var elementDescription: String?
    public var ancestry: [LocatorAncestor]
    public var fallback: CoordinateFallback?

    public init(
        identifier: String? = nil,
        role: String? = nil,
        title: String? = nil,
        description: String? = nil,
        ancestry: [LocatorAncestor] = [],
        fallback: CoordinateFallback? = nil
    ) {
        self.identifier = identifier
        self.role = role
        self.title = title
        self.elementDescription = description
        self.ancestry = ancestry
        self.fallback = fallback
    }

    public var hasSemanticCriteria: Bool {
        [identifier, role, title, elementDescription].contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } || !ancestry.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case identifier, role, title
        case elementDescription = "description"
        case ancestry, fallback
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        elementDescription = try container.decodeIfPresent(String.self, forKey: .elementDescription)
        ancestry = try container.decodeIfPresent([LocatorAncestor].self, forKey: .ancestry) ?? []
        fallback = try container.decodeIfPresent(CoordinateFallback.self, forKey: .fallback)
    }
}

public struct LocatorAncestor: Codable, Sendable, Equatable {
    public var identifier: String?
    public var role: String?
    public var title: String?

    public init(identifier: String? = nil, role: String? = nil, title: String? = nil) {
        self.identifier = identifier
        self.role = role
        self.title = title
    }

    public var hasCriteria: Bool {
        [identifier, role, title].contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

public struct CoordinateFallback: Codable, Sendable, Equatable {
    public enum CoordinateSpace: String, Codable, Sendable, CaseIterable {
        /// Quartz/Accessibility global screen coordinates.
        case globalScreen
    }

    public var x: Double
    public var y: Double
    public var coordinateSpace: CoordinateSpace

    public init(x: Double, y: Double, coordinateSpace: CoordinateSpace = .globalScreen) {
        self.x = x
        self.y = y
        self.coordinateSpace = coordinateSpace
    }

    private enum CodingKeys: String, CodingKey {
        case x, y, coordinateSpace
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        coordinateSpace = try container.decodeIfPresent(CoordinateSpace.self, forKey: .coordinateSpace) ?? .globalScreen
    }
}

public struct RetryPolicy: Codable, Sendable, Equatable {
    public var maxAttempts: Int
    public var delay: TimeInterval

    public init(maxAttempts: Int = 1, delay: TimeInterval = 0.25) {
        self.maxAttempts = maxAttempts
        self.delay = delay
    }

    public static let none = RetryPolicy()
}

public enum KeyModifier: String, Codable, Sendable, CaseIterable {
    case command
    case option
    case control
    case shift
    case function
}

public struct HotKey: Codable, Sendable, Equatable {
    public var key: String
    public var modifiers: [KeyModifier]

    public init(key: String, modifiers: [KeyModifier]) {
        self.key = key
        self.modifiers = modifiers
    }
}

public enum StepActionKind: String, Codable, Sendable, CaseIterable {
    case activateApp
    case press
    case setValue
    case hotKey
    case waitFor
    case assertExists
    case pause
}

/// The strongly typed payload of a workflow step.
public enum StepAction: Sendable, Equatable {
    case activateApp(AppTarget)
    case press(Locator)
    case setValue(locator: Locator, value: String)
    case hotKey(HotKey)
    case waitFor(Locator)
    case assertExists(Locator)
    case pause(duration: TimeInterval)

    public var kind: StepActionKind {
        switch self {
        case .activateApp: .activateApp
        case .press: .press
        case .setValue: .setValue
        case .hotKey: .hotKey
        case .waitFor: .waitFor
        case .assertExists: .assertExists
        case .pause: .pause
        }
    }
}

extension StepAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, app, locator, value, hotKey, duration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StepActionKind.self, forKey: .type)
        switch type {
        case .activateApp:
            self = .activateApp(try container.decode(AppTarget.self, forKey: .app))
        case .press:
            self = .press(try container.decode(Locator.self, forKey: .locator))
        case .setValue:
            self = .setValue(
                locator: try container.decode(Locator.self, forKey: .locator),
                value: try container.decode(String.self, forKey: .value)
            )
        case .hotKey:
            self = .hotKey(try container.decode(HotKey.self, forKey: .hotKey))
        case .waitFor:
            self = .waitFor(try container.decode(Locator.self, forKey: .locator))
        case .assertExists:
            self = .assertExists(try container.decode(Locator.self, forKey: .locator))
        case .pause:
            self = .pause(duration: try container.decode(TimeInterval.self, forKey: .duration))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)
        switch self {
        case .activateApp(let app):
            try container.encode(app, forKey: .app)
        case .press(let locator), .waitFor(let locator), .assertExists(let locator):
            try container.encode(locator, forKey: .locator)
        case .setValue(let locator, let value):
            try container.encode(locator, forKey: .locator)
            try container.encode(value, forKey: .value)
        case .hotKey(let hotKey):
            try container.encode(hotKey, forKey: .hotKey)
        case .pause(let duration):
            try container.encode(duration, forKey: .duration)
        }
    }
}

/// One traceable, retryable unit of work. Its YAML encoding is intentionally flat and hand-editable.
public struct Step: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String?
    public var action: StepAction
    public var timeout: TimeInterval?
    public var retry: RetryPolicy

    public init(
        id: String,
        name: String? = nil,
        action: StepAction,
        timeout: TimeInterval? = nil,
        retry: RetryPolicy = .none
    ) {
        self.id = id
        self.name = name
        self.action = action
        self.timeout = timeout
        self.retry = retry
    }
}

extension Step: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, action, timeout, retry, app, locator, value, hotKey, duration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout)
        retry = try container.decodeIfPresent(RetryPolicy.self, forKey: .retry) ?? .none

        switch try container.decode(StepActionKind.self, forKey: .action) {
        case .activateApp:
            action = .activateApp(try container.decode(AppTarget.self, forKey: .app))
        case .press:
            action = .press(try container.decode(Locator.self, forKey: .locator))
        case .setValue:
            action = .setValue(
                locator: try container.decode(Locator.self, forKey: .locator),
                value: try container.decode(String.self, forKey: .value)
            )
        case .hotKey:
            action = .hotKey(try container.decode(HotKey.self, forKey: .hotKey))
        case .waitFor:
            action = .waitFor(try container.decode(Locator.self, forKey: .locator))
        case .assertExists:
            action = .assertExists(try container.decode(Locator.self, forKey: .locator))
        case .pause:
            action = .pause(duration: try container.decode(TimeInterval.self, forKey: .duration))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(action.kind, forKey: .action)
        try container.encodeIfPresent(timeout, forKey: .timeout)
        if retry != .none {
            try container.encode(retry, forKey: .retry)
        }

        switch action {
        case .activateApp(let app):
            try container.encode(app, forKey: .app)
        case .press(let locator), .waitFor(let locator), .assertExists(let locator):
            try container.encode(locator, forKey: .locator)
        case .setValue(let locator, let value):
            try container.encode(locator, forKey: .locator)
            try container.encode(value, forKey: .value)
        case .hotKey(let hotKey):
            try container.encode(hotKey, forKey: .hotKey)
        case .pause(let duration):
            try container.encode(duration, forKey: .duration)
        }
    }
}

public enum WorkflowRunStatus: String, Codable, Sendable {
    case succeeded
    case failed
    case cancelled
}

public enum StepTraceStatus: String, Codable, Sendable {
    case succeeded
    case failed
    case cancelled
    case skipped
}

public struct StepTrace: Codable, Sendable, Equatable, Identifiable {
    public var id: String { stepID }
    public var stepID: String
    public var action: StepActionKind
    public var status: StepTraceStatus
    public var attempts: Int
    public var startedAt: Date
    public var endedAt: Date
    public var message: String?

    public init(
        stepID: String,
        action: StepActionKind,
        status: StepTraceStatus,
        attempts: Int,
        startedAt: Date,
        endedAt: Date,
        message: String? = nil
    ) {
        self.stepID = stepID
        self.action = action
        self.status = status
        self.attempts = attempts
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.message = message
    }

    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
}

public struct WorkflowRunResult: Codable, Sendable, Equatable {
    public var workflowName: String
    public var status: WorkflowRunStatus
    public var startedAt: Date
    public var endedAt: Date
    public var steps: [StepTrace]
    public var message: String?

    public init(
        workflowName: String,
        status: WorkflowRunStatus,
        startedAt: Date,
        endedAt: Date,
        steps: [StepTrace],
        message: String? = nil
    ) {
        self.workflowName = workflowName
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.steps = steps
        self.message = message
    }

    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
}
