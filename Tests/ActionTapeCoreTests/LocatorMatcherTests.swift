import Testing
@testable import ActionTapeCore

@Suite("Locator matching")
struct LocatorMatcherTests {
    @Test("Every supplied constraint must match, including title with an identifier")
    func explicitStateCannotBeOverriddenByIdentifier() throws {
        let locator = Locator(
            identifier: "save-button",
            role: "AXButton",
            title: "Save",
            description: "Save document",
            ancestry: [LocatorAncestor(role: "AXToolbar")]
        )
        let staleTitle = ElementSnapshot(
            path: [0],
            identifier: "save-button",
            role: "AXButton",
            title: "Changed title",
            description: "Save document",
            ancestry: [LocatorAncestor(role: "AXToolbar")]
        )
        let allOtherSignals = ElementSnapshot(
            path: [1],
            identifier: "different",
            role: "AXButton",
            title: "Save",
            description: "Save document",
            ancestry: [LocatorAncestor(role: "AXToolbar")]
        )

        let exactMatch = ElementSnapshot(
            path: [2], identifier: "save-button", role: "AXButton", title: "Save",
            description: "Save document", ancestry: [LocatorAncestor(role: "AXToolbar")]
        )
        let matcher = LocatorMatcher()
        #expect(matcher.select(locator: locator, candidates: [allOtherSignals, staleTitle]) == .notFound)
        let selection = matcher.select(locator: locator, candidates: [allOtherSignals, staleTitle, exactMatch])
        guard case .selected(let match) = selection else {
            Issue.record("Expected an unambiguous selection")
            return
        }
        #expect(match.candidate.path == [2])
        #expect(match.score == 1_760)
    }

    @Test("Identifier does not override a missing or different description")
    func explicitDescriptionMustMatch() {
        let locator = Locator(identifier: "status", description: "Prepared")
        let matcher = LocatorMatcher()
        #expect(matcher.score(locator: locator, candidate: .init(path: [0], identifier: "status")) == nil)
        #expect(matcher.score(locator: locator, candidate: .init(path: [0], identifier: "status", description: "Ready")) == nil)
        #expect(matcher.score(locator: locator, candidate: .init(path: [0], identifier: "status", description: " PREPARED ")) != nil)
    }

    @Test("Identifier alone remains stable when an unconstrained title changes")
    func unspecifiedFieldsAreNotConstraints() {
        let locator = Locator(identifier: "status")
        let candidate = ElementSnapshot(path: [0], identifier: "status", title: "Prepared")
        #expect(LocatorMatcher().score(locator: locator, candidate: candidate)?.score == 1_000)
    }

    @Test("Equal candidates fail safely")
    func ambiguityFailsSafely() {
        let locator = Locator(role: "AXButton", title: "Continue")
        let candidates = [
            ElementSnapshot(path: [0], role: "AXButton", title: "Continue"),
            ElementSnapshot(path: [1], role: "AXButton", title: "Continue")
        ]

        let selection = LocatorMatcher().select(locator: locator, candidates: candidates)
        guard case .ambiguous(let matches) = selection else {
            Issue.record("Expected ambiguity, never an arbitrary first match")
            return
        }
        #expect(matches.count == 2)
        #expect(matches.allSatisfy { $0.score == 480 })
    }

    @Test("Role mismatch rejects an otherwise tempting candidate")
    func roleMismatchIsRejected() {
        let locator = Locator(role: "AXButton", title: "Delete")
        let candidate = ElementSnapshot(path: [0], role: "AXStaticText", title: "Delete")
        #expect(LocatorMatcher().score(locator: locator, candidate: candidate) == nil)
    }

    @Test("Ancestry allows skipped structural containers")
    func ancestryUsesOrderedSubsequence() throws {
        let locator = Locator(ancestry: [
            LocatorAncestor(role: "AXGroup", title: "Editor"),
            LocatorAncestor(role: "AXWindow", title: "Document")
        ])
        let candidate = ElementSnapshot(path: [2, 1], ancestry: [
            LocatorAncestor(role: "AXGroup", title: "Editor"),
            LocatorAncestor(role: "AXScrollArea"),
            LocatorAncestor(role: "AXWindow", title: "Document")
        ])
        let score = try #require(LocatorMatcher().score(locator: locator, candidate: candidate))
        #expect(score.score == 120)
        #expect(score.components == [.init(signal: .ancestry, points: 120)])
    }

    @Test("Near ties can be configured as ambiguous")
    func configurableAmbiguityWindow() {
        let matcher = LocatorMatcher(configuration: .init(minimumScore: 100, ambiguityTolerance: 30))
        let locator = Locator(role: "AXButton", title: "Run")
        let candidates = [
            ElementSnapshot(path: [0], role: "AXButton", title: "Run"),
            ElementSnapshot(path: [1], role: "AXButton", title: "RUN")
        ]
        guard case .ambiguous(let matches) = matcher.select(locator: locator, candidates: candidates) else {
            Issue.record("Expected scores within tolerance to be ambiguous")
            return
        }
        #expect(matches.map(\.score) == [480, 450])
    }

    @Test("Empty semantic locator has no match")
    func coordinateOnlyDoesNotSemanticallyMatch() {
        let locator = Locator(fallback: CoordinateFallback(x: 10, y: 10))
        let selection = LocatorMatcher().select(
            locator: locator,
            candidates: [ElementSnapshot(path: [0], role: "AXButton")]
        )
        #expect(selection == .notFound)
    }
}
