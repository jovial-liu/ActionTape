import Foundation

/// A value-only snapshot of an accessibility element. It is safe to move across concurrency domains.
public struct ElementSnapshot: Codable, Sendable, Equatable, Identifiable {
    /// Traversal indexes from the application root. This is diagnostic, not a persisted selector.
    public var path: [Int]
    public var identifier: String?
    public var role: String?
    public var subrole: String?
    public var title: String?
    public var elementDescription: String?
    /// Nearest parent first.
    public var ancestry: [LocatorAncestor]
    public var frame: ElementFrame?

    public var id: String { path.map(String.init).joined(separator: ".") }
    public var isSecureTextField: Bool {
        role == "AXSecureTextField" || subrole == "AXSecureTextField"
    }

    public init(
        path: [Int],
        identifier: String? = nil,
        role: String? = nil,
        subrole: String? = nil,
        title: String? = nil,
        description: String? = nil,
        ancestry: [LocatorAncestor] = [],
        frame: ElementFrame? = nil
    ) {
        self.path = path
        self.identifier = identifier
        self.role = role
        self.subrole = subrole
        self.title = title
        self.elementDescription = description
        self.ancestry = ancestry
        self.frame = frame
    }

    private enum CodingKeys: String, CodingKey {
        case path, identifier, role, subrole, title
        case elementDescription = "description"
        case ancestry, frame
    }
}

public struct ElementFrame: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var center: CoordinateFallback {
        CoordinateFallback(x: x + width / 2, y: y + height / 2)
    }
}

public enum LocatorSignal: String, Codable, Sendable, CaseIterable {
    case identifier
    case role
    case title
    case description
    case ancestry
}

public struct LocatorScoreComponent: Codable, Sendable, Equatable {
    public var signal: LocatorSignal
    public var points: Int

    public init(signal: LocatorSignal, points: Int) {
        self.signal = signal
        self.points = points
    }
}

public struct LocatorScore: Codable, Sendable, Equatable {
    public var candidate: ElementSnapshot
    public var score: Int
    public var components: [LocatorScoreComponent]

    public init(candidate: ElementSnapshot, score: Int, components: [LocatorScoreComponent]) {
        self.candidate = candidate
        self.score = score
        self.components = components
    }
}

/// A resolution never silently chooses between equally plausible elements.
public enum LocatorSelection: Sendable, Equatable {
    case selected(LocatorScore)
    case notFound
    case ambiguous([LocatorScore])
}

public struct LocatorMatcher: Sendable {
    public struct Configuration: Sendable, Equatable {
        public var minimumScore: Int
        /// Scores within this distance of the best score are considered indistinguishable.
        public var ambiguityTolerance: Int

        public init(minimumScore: Int = 60, ambiguityTolerance: Int = 0) {
            self.minimumScore = minimumScore
            self.ambiguityTolerance = ambiguityTolerance
        }
    }

    public var configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// Every supplied criterion is required. Scores distinguish exact text matches from
    /// normalized matches; an identifier must never override an explicit state assertion.
    public func score(locator: Locator, candidate: ElementSnapshot) -> LocatorScore? {
        guard locator.hasSemanticCriteria else { return nil }

        var components: [LocatorScoreComponent] = []

        if let expected = meaningful(locator.identifier) {
            // A stale identifier must not silently degrade into a role-only click.
            guard let actual = meaningful(candidate.identifier), expected == actual else { return nil }
            components.append(.init(signal: .identifier, points: 1_000))
        }

        if let expected = meaningful(locator.role) {
            // A role mismatch is a strong indication that this is not the intended control.
            guard let actual = meaningful(candidate.role), expected == actual else { return nil }
            components.append(.init(signal: .role, points: 180))
        }

        if let expected = meaningful(locator.title) {
            let actual = meaningful(candidate.title) ?? ""
            if expected == actual {
                components.append(.init(signal: .title, points: 300))
            } else if normalized(expected) == normalized(actual) {
                components.append(.init(signal: .title, points: 270))
            } else {
                return nil
            }
        }

        if let expected = meaningful(locator.elementDescription) {
            let actual = meaningful(candidate.elementDescription) ?? ""
            if expected == actual {
                components.append(.init(signal: .description, points: 220))
            } else if normalized(expected) == normalized(actual) {
                components.append(.init(signal: .description, points: 200))
            } else {
                return nil
            }
        }

        guard let ancestryPoints = scoreAncestry(expected: locator.ancestry, actual: candidate.ancestry) else { return nil }
        if ancestryPoints > 0 {
            components.append(.init(signal: .ancestry, points: ancestryPoints))
        }

        let total = components.reduce(0) { $0 + $1.points }
        guard total > 0, total >= max(1, configuration.minimumScore) else { return nil }
        return LocatorScore(candidate: candidate, score: total, components: components)
    }

    public func rank(locator: Locator, candidates: [ElementSnapshot]) -> [LocatorScore] {
        candidates.compactMap { score(locator: locator, candidate: $0) }
            .sorted {
                if $0.score == $1.score {
                    return $0.candidate.path.lexicographicallyPrecedes($1.candidate.path)
                }
                return $0.score > $1.score
            }
    }

    public func select(locator: Locator, candidates: [ElementSnapshot]) -> LocatorSelection {
        let ranked = rank(locator: locator, candidates: candidates)
        guard let best = ranked.first else { return .notFound }

        let indistinguishable = ranked.prefix {
            best.score - $0.score <= max(0, configuration.ambiguityTolerance)
        }
        if indistinguishable.count > 1 {
            return .ambiguous(Array(indistinguishable))
        }
        return .selected(best)
    }

    private func scoreAncestry(expected: [LocatorAncestor], actual: [LocatorAncestor]) -> Int? {
        guard !expected.isEmpty else { return 0 }
        var points = 0
        var searchStart = 0

        // Both arrays are nearest-parent-first. Permit skipped structural containers while
        // preserving order, which is stable across modest view hierarchy changes.
        for expectedAncestor in expected {
            guard expectedAncestor.hasCriteria, searchStart < actual.count else { return nil }
            var foundIndex: Int?
            for index in searchStart..<actual.count where matches(expectedAncestor, actual[index]) {
                foundIndex = index
                break
            }
            guard let foundIndex else { return nil }
            points += 60
            searchStart = foundIndex + 1
        }
        return min(points, 120)
    }

    private func matches(_ expected: LocatorAncestor, _ actual: LocatorAncestor) -> Bool {
        if let value = meaningful(expected.identifier),
           value != meaningful(actual.identifier) { return false }
        if let value = meaningful(expected.role),
           value != meaningful(actual.role) { return false }
        if let value = meaningful(expected.title),
           normalized(value) != normalized(actual.title ?? "") { return false }
        return true
    }

    private func meaningful(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalized(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }
}
