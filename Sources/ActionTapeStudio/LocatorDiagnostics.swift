import ActionTapeCore
import Foundation

struct LocatorInspectionRequest: Sendable {
    let documentID: UUID
    let stepID: String
    let app: AppTarget
    let locator: Locator
    let variables: [String: WorkflowVariable]
}

/// Retains only the labels needed to explain a match, after secret-variable redaction.
/// AXValue, keyboard input, and screenshots are never requested for this report.
struct LocatorInspectionResult {
    enum Outcome {
        case selected
        case notFound
        case ambiguous(Int)
        case failed(String)
    }

    struct Candidate: Identifiable {
        let id: String
        let score: Int
        let identifier: String?
        let role: String?
        let title: String?
        let description: String?
        let components: [LocatorScoreComponent]
    }

    let documentID: UUID
    let stepID: String
    let inspectedAt: Date
    let appName: String
    let outcome: Outcome
    let matchCount: Int
    let candidates: [Candidate]

    init(request: LocatorInspectionRequest, app: AppTarget, locator: Locator,
         ranked: [LocatorScore], resolved: ResolvedVariables) {
        documentID = request.documentID
        stepID = request.stepID
        inspectedAt = .now
        appName = resolved.redacting(app.name ?? app.bundleIdentifier ?? app.path ?? "Target app")
        switch LocatorMatcher().select(locator: locator, candidates: ranked.map(\.candidate)) {
        case .selected: outcome = .selected
        case .notFound: outcome = .notFound
        case .ambiguous(let matches): outcome = .ambiguous(matches.count)
        }
        matchCount = ranked.count
        candidates = ranked.prefix(25).map { match in
            let snapshot = match.candidate
            return Candidate(
                id: snapshot.id,
                score: match.score,
                identifier: snapshot.identifier.map(resolved.redacting),
                role: snapshot.role.map(resolved.redacting),
                title: snapshot.title.map(resolved.redacting),
                description: snapshot.elementDescription.map(resolved.redacting),
                components: match.components
            )
        }
    }

    init(request: LocatorInspectionRequest, message: String) {
        documentID = request.documentID
        stepID = request.stepID
        inspectedAt = .now
        appName = "Target app"
        outcome = .failed(message)
        matchCount = 0
        candidates = []
    }
}

enum LocatorInspection {
    private struct Timeout: LocalizedError {
        var errorDescription: String? { "Inspection timed out after 10 seconds. Check that the target app is responding." }
    }

    static func matches(app: AppTarget, locator: Locator) async throws -> [LocatorScore] {
        try await withThrowingTaskGroup(of: [LocatorScore].self) { group in
            group.addTask {
                let driver = MacOSAccessibilityDriver()
                try Task.checkCancellation()
                try await driver.activateApp(app)
                try Task.checkCancellation()
                return try await driver.findCandidates(matching: locator)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw Timeout()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            try Task.checkCancellation()
            return result
        }
    }
}
