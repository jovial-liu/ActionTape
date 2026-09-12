import AppKit
import ApplicationServices
import Foundation

/// The small driver surface used by the runner. Implementations must cooperate with cancellation:
/// check cancellation before each side effect, and never launch detached work that outlives a call.
public protocol AutomationDriver: Sendable {
    func activateApp(_ target: AppTarget) async throws
    func press(_ locator: Locator) async throws
    func setValue(_ value: String, on locator: Locator) async throws
    func hotKey(_ hotKey: HotKey) async throws
    func exists(_ locator: Locator) async throws -> Bool
}

public enum AutomationDriverError: Error, Sendable, Equatable, LocalizedError {
    case accessibilityPermissionDenied
    case applicationNotFound(AppTarget)
    case noActiveApplication
    case elementNotFound
    case ambiguousLocator(candidateCount: Int, topScore: Int)
    case coordinateFallbackDisabled
    case coordinateOutsideActiveApplication
    case unsupportedKey(String)
    case actionUnsupported(String)
    case accessibilityFailure(operation: String, code: Int32)
    case traversalLimitReached
    case applicationAmbiguous
    case applicationActivationFailed

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            "Accessibility permission is required. Enable ActionTape in System Settings → Privacy & Security → Accessibility."
        case .applicationNotFound(let target):
            "Could not find application \(target.bundleIdentifier ?? target.name ?? target.path ?? "(unspecified)")."
        case .noActiveApplication:
            "No application has been activated for this workflow."
        case .elementNotFound:
            "No accessibility element safely matched the locator."
        case .ambiguousLocator(let count, let score):
            "Locator is ambiguous: \(count) candidates share the top score of \(score)."
        case .coordinateFallbackDisabled:
            "The locator requires coordinate fallback, but coordinate fallback is disabled."
        case .coordinateOutsideActiveApplication:
            "The coordinate fallback points outside the active target application."
        case .unsupportedKey(let key):
            "Unsupported hot-key key '\(key)'."
        case .actionUnsupported(let action):
            "The selected accessibility element does not support \(action)."
        case .accessibilityFailure(let operation, let code):
            "Accessibility operation '\(operation)' failed with AXError \(code)."
        case .traversalLimitReached:
            "Accessibility traversal was incomplete. Increase traversal limits or simplify the target window; no partial match was used."
        case .applicationAmbiguous:
            "More than one running application matches this target. Use a unique bundle identifier or application path."
        case .applicationActivationFailed:
            "The target application could not be activated."
        }
    }
}

public struct AccessibilityConfiguration: Sendable, Equatable {
    public var matcher: LocatorMatcher.Configuration
    public var allowCoordinateFallback: Bool
    public var maximumTraversalDepth: Int
    public var maximumElementCount: Int
    public var ancestryDepth: Int
    public var activationTimeout: TimeInterval
    public var messagingTimeout: TimeInterval

    public init(
        matcher: LocatorMatcher.Configuration = .init(),
        allowCoordinateFallback: Bool = false,
        maximumTraversalDepth: Int = 40,
        maximumElementCount: Int = 10_000,
        ancestryDepth: Int = 4,
        activationTimeout: TimeInterval = 8,
        messagingTimeout: TimeInterval = 0.5
    ) {
        self.matcher = matcher
        self.allowCoordinateFallback = allowCoordinateFallback
        self.maximumTraversalDepth = maximumTraversalDepth
        self.maximumElementCount = maximumElementCount
        self.ancestryDepth = ancestryDepth
        self.activationTimeout = activationTimeout
        self.messagingTimeout = messagingTimeout
    }
}

/// Serialized access to macOS Accessibility and Quartz event APIs.
///
/// Raw `AXUIElement` references never cross this actor boundary. Public methods return value-only
/// snapshots, which avoids pretending the Core Foundation objects are `Sendable`.
public actor MacOSAccessibilityDriver: AutomationDriver {
    public let configuration: AccessibilityConfiguration

    private let matcher: LocatorMatcher
    private var activePID: pid_t?
    private var activeTarget: AppTarget?

    public init(configuration: AccessibilityConfiguration = .init()) {
        var bounded = configuration
        bounded.maximumTraversalDepth = min(128, max(1, configuration.maximumTraversalDepth))
        bounded.maximumElementCount = min(50_000, max(1, configuration.maximumElementCount))
        bounded.ancestryDepth = min(32, max(0, configuration.ancestryDepth))
        bounded.activationTimeout = configuration.activationTimeout.isFinite ? min(60, max(0.1, configuration.activationTimeout)) : 8
        bounded.messagingTimeout = configuration.messagingTimeout.isFinite ? min(5, max(0.05, configuration.messagingTimeout)) : 0.5
        self.configuration = bounded
        matcher = LocatorMatcher(configuration: bounded.matcher)
    }

    public nonisolated static func isTrusted(prompt: Bool = false) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        // The SDK imports the CFString constant as mutable global state under Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func activateApp(_ target: AppTarget) async throws {
        try AutomationExecutionContext.check()
        guard Self.isTrusted() else { throw AutomationDriverError.accessibilityPermissionDenied }
        guard target.hasIdentity else { throw AutomationDriverError.applicationNotFound(target) }

        // A failed activation must not leave the previous workflow target selected.
        activePID = nil
        activeTarget = nil
        if let pid = try await runningPID(for: target) {
            try await activate(pid: pid)
            try AutomationExecutionContext.check()
            activePID = pid
            activeTarget = target
            return
        }

        let opened = try await requestLaunch(of: target)
        try AutomationExecutionContext.check()
        guard opened else { throw AutomationDriverError.applicationNotFound(target) }

        let timeout = max(0.1, configuration.activationTimeout)
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while ContinuousClock.now < deadline {
            try AutomationExecutionContext.check()
            if let pid = try await runningPID(for: target) {
                try await activate(pid: pid)
                try AutomationExecutionContext.check()
                activePID = pid
                activeTarget = target
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw AutomationDriverError.applicationNotFound(target)
    }

    public func press(_ locator: Locator) async throws {
        let element = try await resolveElement(locator)
        try AutomationExecutionContext.check()
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard error == .success else {
            if error == .actionUnsupported {
                throw AutomationDriverError.actionUnsupported("AXPress")
            }
            throw axError(error, operation: "press")
        }
    }

    public func setValue(_ value: String, on locator: Locator) async throws {
        let element = try await resolveElement(locator)
        try AutomationExecutionContext.check()
        // Never read AXValue here. This is important for secure text fields and trace hygiene.
        _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try AutomationExecutionContext.check()
        let error = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef)
        guard error == .success else {
            if error == .attributeUnsupported || error == .notImplemented {
                throw AutomationDriverError.actionUnsupported("AXValue assignment")
            }
            throw axError(error, operation: "setValue")
        }
    }

    public func hotKey(_ hotKey: HotKey) async throws {
        try AutomationExecutionContext.check()
        guard Self.isTrusted() else { throw AutomationDriverError.accessibilityPermissionDenied }
        let pid = try await activeApplicationPID()
        guard let keyCode = Self.keyCode(for: hotKey.key) else {
            throw AutomationDriverError.unsupportedKey(hotKey.key)
        }
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw AutomationDriverError.actionUnsupported("keyboard event creation")
        }
        let flags = Self.eventFlags(for: hotKey.modifiers)
        down.flags = flags
        up.flags = flags
        try AutomationExecutionContext.check()
        // Send both halves to the pinned target even if the user changes focus meanwhile.
        // Do not put a cancellation point between key-down and its matching key-up.
        down.postToPid(pid)
        up.postToPid(pid)
    }

    public func exists(_ locator: Locator) async throws -> Bool {
        try AutomationExecutionContext.check()
        guard Self.isTrusted() else { throw AutomationDriverError.accessibilityPermissionDenied }
        _ = try await activeApplicationPID()
        switch try await locate(locator) {
        case .selected:
            return true
        case .notFound:
            if locator.fallback != nil, configuration.allowCoordinateFallback {
                _ = try coordinateElement(for: locator)
                return true
            }
            return false
        case .ambiguous(let matches):
            throw AutomationDriverError.ambiguousLocator(
                candidateCount: matches.count,
                topScore: matches.first?.score ?? 0
            )
        }
    }

    /// Captures a value-only snapshot at a global screen point without reading the element value.
    public func captureElement(at coordinate: CoordinateFallback) throws -> ElementSnapshot {
        try AutomationExecutionContext.check()
        try validateCoordinate(coordinate)
        guard Self.isTrusted() else { throw AutomationDriverError.accessibilityPermissionDenied }
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(coordinate.x),
            Float(coordinate.y),
            &element
        )
        guard error == .success, let element else { throw axError(error, operation: "captureElement") }
        setMessagingTimeout(on: element)
        let result = snapshot(of: element, path: [-1], ancestry: readAncestry(of: element))
        try AutomationExecutionContext.check()
        return result
    }

    /// Builds a semantic locator from the element under a global screen point.
    public func buildLocator(
        at coordinate: CoordinateFallback,
        includeCoordinateFallback: Bool = true
    ) throws -> Locator {
        let snapshot = try captureElement(at: coordinate)
        return Locator(
            identifier: snapshot.identifier,
            role: snapshot.role,
            title: snapshot.title,
            description: snapshot.elementDescription,
            ancestry: Array(snapshot.ancestry.prefix(max(0, configuration.ancestryDepth))),
            fallback: includeCoordinateFallback ? coordinate : nil
        )
    }

    public func findCandidates(matching locator: Locator) async throws -> [LocatorScore] {
        let candidates = try await collectCandidates()
        return matcher.rank(locator: locator, candidates: candidates.map(\.snapshot))
    }

    public func resolve(_ locator: Locator) async throws -> LocatorSelection {
        try await locate(locator)
    }

    public func focus(_ locator: Locator) async throws {
        let element = try await resolveElement(locator)
        try AutomationExecutionContext.check()
        let error = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard error == .success else { throw axError(error, operation: "focus") }
    }

    public func select(_ locator: Locator) async throws {
        let element = try await resolveElement(locator)
        try AutomationExecutionContext.check()
        var error = AXUIElementSetAttributeValue(element, kAXSelectedAttribute as CFString, kCFBooleanTrue)
        if error == .attributeUnsupported || error == .notImplemented {
            try AutomationExecutionContext.check()
            error = AXUIElementPerformAction(element, kAXPickAction as CFString)
        }
        guard error == .success else {
            if error == .attributeUnsupported || error == .actionUnsupported || error == .notImplemented {
                throw AutomationDriverError.actionUnsupported("selection")
            }
            throw axError(error, operation: "select")
        }
    }

    private struct AXCandidate {
        var snapshot: ElementSnapshot
        var element: AXUIElement
    }

    private func locate(_ locator: Locator) async throws -> LocatorSelection {
        try AutomationExecutionContext.check()
        guard locator.hasSemanticCriteria else { return .notFound }
        let candidates = try await collectCandidates()
        return matcher.select(locator: locator, candidates: candidates.map(\.snapshot))
    }

    private func resolveElement(_ locator: Locator) async throws -> AXUIElement {
        let candidates = try await collectCandidates()
        let selection = matcher.select(locator: locator, candidates: candidates.map(\.snapshot))
        switch selection {
        case .selected(let match):
            guard let candidate = candidates.first(where: { $0.snapshot.path == match.candidate.path }) else {
                throw AutomationDriverError.elementNotFound
            }
            return candidate.element
        case .ambiguous(let matches):
            // Coordinate fallback must never turn an ambiguous semantic match into a click.
            throw AutomationDriverError.ambiguousLocator(
                candidateCount: matches.count,
                topScore: matches.first?.score ?? 0
            )
        case .notFound:
            guard locator.fallback != nil else { throw AutomationDriverError.elementNotFound }
            guard configuration.allowCoordinateFallback else {
                throw AutomationDriverError.coordinateFallbackDisabled
            }
            return try coordinateElement(for: locator)
        }
    }

    private func coordinateElement(for locator: Locator) throws -> AXUIElement {
        try AutomationExecutionContext.check()
        guard let activePID else { throw AutomationDriverError.noActiveApplication }
        guard let coordinate = locator.fallback else { throw AutomationDriverError.elementNotFound }
        try validateCoordinate(coordinate)
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(coordinate.x),
            Float(coordinate.y),
            &element
        )
        guard error == .success, let element else { throw axError(error, operation: "coordinateFallback") }

        setMessagingTimeout(on: element)
        var elementPID: pid_t = 0
        let pidError = AXUIElementGetPid(element, &elementPID)
        guard pidError == .success else { throw axError(pidError, operation: "coordinatePID") }
        guard elementPID == activePID else { throw AutomationDriverError.coordinateOutsideActiveApplication }
        try AutomationExecutionContext.check()
        return element
    }

    private func collectCandidates() async throws -> [AXCandidate] {
        try AutomationExecutionContext.check()
        guard Self.isTrusted() else { throw AutomationDriverError.accessibilityPermissionDenied }
        let pid = try await activeApplicationPID()

        let root = AXUIElementCreateApplication(pid)
        var result: [AXCandidate] = []
        var visited: [CFHashCode: [AXUIElement]] = [:]
        try walk(
            element: root,
            path: [],
            ancestry: [],
            depth: 0,
            result: &result,
            visited: &visited
        )
        try AutomationExecutionContext.check()
        return result
    }

    private func walk(
        element: AXUIElement,
        path: [Int],
        ancestry: [LocatorAncestor],
        depth: Int,
        result: inout [AXCandidate],
        visited: inout [CFHashCode: [AXUIElement]]
    ) throws {
        try AutomationExecutionContext.check()
        let hash = CFHash(element)
        if visited[hash, default: []].contains(where: { CFEqual($0, element) }) { return }
        guard depth <= configuration.maximumTraversalDepth,
              result.count < configuration.maximumElementCount else {
            // Selecting from a truncated tree could hide a second equally plausible candidate.
            throw AutomationDriverError.traversalLimitReached
        }
        visited[hash, default: []].append(element)
        setMessagingTimeout(on: element)

        let elementSnapshot = snapshot(of: element, path: path, ancestry: ancestry)
        result.append(AXCandidate(snapshot: elementSnapshot, element: element))

        let currentAncestor = LocatorAncestor(
            identifier: elementSnapshot.identifier,
            role: elementSnapshot.role,
            title: elementSnapshot.title
        )
        let childAncestry = Array(([currentAncestor] + ancestry).prefix(max(0, configuration.ancestryDepth)))

        for (index, child) in try children(of: element).enumerated() {
            try walk(
                element: child,
                path: path + [index],
                ancestry: childAncestry,
                depth: depth + 1,
                result: &result,
                visited: &visited
            )
        }
    }

    private func snapshot(
        of element: AXUIElement,
        path: [Int],
        ancestry: [LocatorAncestor]
    ) -> ElementSnapshot {
        let role = stringAttribute(kAXRoleAttribute as CFString, of: element)
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, of: element)
        let secure = role == "AXSecureTextField" || subrole == "AXSecureTextField"
        return ElementSnapshot(
            path: path,
            identifier: stringAttribute(kAXIdentifierAttribute as CFString, of: element),
            role: role,
            subrole: subrole,
            title: secure ? nil : stringAttribute(kAXTitleAttribute as CFString, of: element),
            description: secure ? nil : stringAttribute(kAXDescriptionAttribute as CFString, of: element),
            ancestry: ancestry,
            frame: frame(of: element)
        )
    }

    private func readAncestry(of element: AXUIElement) -> [LocatorAncestor] {
        var result: [LocatorAncestor] = []
        var current = element
        for _ in 0..<max(0, configuration.ancestryDepth) {
            guard let parent = elementAttribute(kAXParentAttribute as CFString, of: current) else { break }
            setMessagingTimeout(on: parent)
            let role = stringAttribute(kAXRoleAttribute as CFString, of: parent)
            let secure = role == "AXSecureTextField" || stringAttribute(kAXSubroleAttribute as CFString, of: parent) == "AXSecureTextField"
            result.append(LocatorAncestor(
                identifier: stringAttribute(kAXIdentifierAttribute as CFString, of: parent),
                role: role,
                title: secure ? nil : stringAttribute(kAXTitleAttribute as CFString, of: parent)
            ))
            current = parent
        }
        return result
    }

    private func children(of element: AXUIElement) throws -> [AXUIElement] {
        try AutomationExecutionContext.check()
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        if error == .attributeUnsupported || error == .noValue { return [] }
        guard error == .success else { throw axError(error, operation: "readChildren") }
        guard let value else { return [] }
        guard let children = value as? [AXUIElement] else {
            throw AutomationDriverError.actionUnsupported("invalid AXChildren response")
        }
        return children
    }

    private func stringAttribute(_ name: CFString, of element: AXUIElement) -> String? {
        guard let value = attribute(name, of: element) else { return nil }
        return value as? String
    }

    private func elementAttribute(_ name: CFString, of element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func attribute(_ name: CFString, of element: AXUIElement) -> CFTypeRef? {
        guard (try? AutomationExecutionContext.check()) != nil else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }

    private func frame(of element: AXUIElement) -> ElementFrame? {
        guard let positionValue = attribute(kAXPositionAttribute as CFString, of: element),
              let sizeValue = attribute(kAXSizeAttribute as CFString, of: element),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }

        let axPosition = positionValue as! AXValue
        let axSize = sizeValue as! AXValue
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(axPosition, .cgPoint, &point),
              AXValueGetValue(axSize, .cgSize, &size) else { return nil }
        return ElementFrame(
            x: Double(point.x),
            y: Double(point.y),
            width: Double(size.width),
            height: Double(size.height)
        )
    }

    private func runningPID(for target: AppTarget) async throws -> pid_t? {
        try await MainActor.run {
            try AutomationExecutionContext.check()
            let matches = NSWorkspace.shared.runningApplications.filter { Self.matches($0, target: target) }
            guard matches.count <= 1 else { throw AutomationDriverError.applicationAmbiguous }
            return matches.first?.processIdentifier
        }
    }

    private func requestLaunch(of target: AppTarget) async throws -> Bool {
        try await MainActor.run {
            try AutomationExecutionContext.check()
            let workspace = NSWorkspace.shared
            let url: URL?
            if let path = target.path, !path.isEmpty {
                // An explicit path disambiguates multiple installations of the same bundle.
                // Validate its bundle identifier below instead of using Launch Services' choice.
                url = URL(fileURLWithPath: path)
            } else if let bundleIdentifier = target.bundleIdentifier, !bundleIdentifier.isEmpty {
                url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
            } else if let name = target.name {
                url = workspace.fullPath(forApplication: name).map(URL.init(fileURLWithPath:))
            } else {
                url = nil
            }
            guard let url, url.isFileURL, url.pathExtension.lowercased() == "app",
                  Bundle(url: url)?.bundleIdentifier != nil else { return false }
            if let path = target.path, !path.isEmpty,
               url.standardizedFileURL.path != URL(fileURLWithPath: path).standardizedFileURL.path { return false }
            if let bundle = target.bundleIdentifier, !bundle.isEmpty,
               Bundle(url: url)?.bundleIdentifier != bundle { return false }
            try AutomationExecutionContext.check()
            return workspace.open(url)
        }
    }

    private func activate(pid: pid_t) async throws {
        try await MainActor.run {
            try AutomationExecutionContext.check()
            guard NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows]) == true else {
                throw AutomationDriverError.applicationActivationFailed
            }
        }
    }

    private func activeApplicationPID() async throws -> pid_t {
        try AutomationExecutionContext.check()
        guard let activePID, let target = activeTarget else { throw AutomationDriverError.noActiveApplication }
        let matches = await MainActor.run {
            NSRunningApplication(processIdentifier: activePID).map { Self.matches($0, target: target) } ?? false
        }
        try AutomationExecutionContext.check()
        guard matches else { throw AutomationDriverError.applicationNotFound(target) }
        return activePID
    }

    @MainActor private static func matches(_ application: NSRunningApplication, target: AppTarget) -> Bool {
        guard !application.isTerminated else { return false }
        if let bundle = target.bundleIdentifier, !bundle.isEmpty {
            guard application.bundleIdentifier == bundle else { return false }
            if let path = target.path, !path.isEmpty {
                return application.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path
            }
            return true
        }
        if let path = target.path, !path.isEmpty {
            return application.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path
        }
        if let name = target.name, !name.isEmpty {
            return application.localizedName?.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        return false
    }

    private func validateCoordinate(_ coordinate: CoordinateFallback) throws {
        guard coordinate.x.isFinite, coordinate.y.isFinite,
              abs(coordinate.x) <= 1_000_000, abs(coordinate.y) <= 1_000_000 else {
            throw AutomationDriverError.coordinateOutsideActiveApplication
        }
    }

    private func setMessagingTimeout(on element: AXUIElement) {
        _ = AXUIElementSetMessagingTimeout(element, Float(configuration.messagingTimeout))
    }

    private func axError(_ error: AXError, operation: String) -> AutomationDriverError {
        AutomationDriverError.accessibilityFailure(operation: operation, code: error.rawValue)
    }

    private nonisolated static func eventFlags(for modifiers: [KeyModifier]) -> CGEventFlags {
        modifiers.reduce(into: CGEventFlags()) { flags, modifier in
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            case .shift: flags.insert(.maskShift)
            case .function: flags.insert(.maskSecondaryFn)
            }
        }
    }

    private nonisolated static func keyCode(for rawKey: String) -> CGKeyCode? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mapping: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36,
            "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
            ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49,
            "`": 50, "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
            "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
            "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
            "left": 123, "right": 124, "down": 125, "up": 126
        ]
        return mapping[key]
    }
}
