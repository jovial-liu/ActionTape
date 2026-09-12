import Foundation
import Testing
@testable import ActionTapeCore

@Suite("Workflow YAML and validation")
struct WorkflowYAMLTests {
    private let sample = """
    formatVersion: 1
    name: Search Notes
    description: A deterministic example
    variables:
      query:
        default: ActionTape
        required: false
        secret: false
    steps:
      - id: open
        action: activateApp
        app:
          bundleIdentifier: com.apple.Notes
      - id: search
        action: hotKey
        hotKey:
          key: f
          modifiers: [command]
      - id: type-query
        action: setValue
        timeout: 3.5
        retry:
          maxAttempts: 2
          delay: 0.1
        locator:
          identifier: SearchField
          role: AXTextField
          ancestry:
            - role: AXToolbar
          fallback:
            x: 400
            y: 80
        value: "{{query}}"
      - id: settle
        action: pause
        duration: 0.25
    """

    @Test("Decodes the hand-editable flattened schema")
    func decodeSchema() throws {
        let workflow = try WorkflowYAML.decode(sample)
        #expect(workflow.name == "Search Notes")
        #expect(workflow.variables["query"]?.defaultValue == "ActionTape")
        #expect(workflow.steps.count == 4)
        #expect(workflow.steps[2].timeout == 3.5)
        #expect(workflow.steps[2].retry == RetryPolicy(maxAttempts: 2, delay: 0.1))
        guard case .setValue(let locator, let value) = workflow.steps[2].action else {
            Issue.record("Expected setValue payload")
            return
        }
        #expect(locator.identifier == "SearchField")
        #expect(locator.fallback == CoordinateFallback(x: 400, y: 80))
        #expect(value == "{{query}}")
    }

    @Test("YAML round-trips all action payloads")
    func roundTrip() throws {
        let original = try WorkflowYAML.decode(sample)
        let encoded = try WorkflowYAML.encode(original)
        let decoded = try WorkflowYAML.decode(encoded)
        #expect(decoded == original)
        #expect(encoded.contains("action: setValue"))
        #expect(encoded.contains("default: ActionTape"))
    }

    @Test("Missing optional collections receive stable defaults")
    func defaults() throws {
        let workflow = try WorkflowYAML.decode("""
        name: Tiny
        steps:
          - id: wait
            action: pause
            duration: 0
        """)
        #expect(workflow.formatVersion == Workflow.currentFormatVersion)
        #expect(workflow.variables.isEmpty)
        #expect(workflow.steps[0].retry == .none)
    }

    @Test("Schema reports duplicate ids and invalid retry policy")
    func structuralValidation() {
        let workflow = Workflow(name: "Bad", steps: [
            Step(id: "same", action: .pause(duration: 0)),
            Step(id: "same", action: .pause(duration: -1), retry: .init(maxAttempts: 0, delay: -1))
        ])
        let issues = WorkflowSchemaValidator().validate(workflow)
        let codes = Set(issues.map(\.code))
        #expect(codes.contains("duplicate_step_id"))
        #expect(codes.contains("invalid_duration"))
        #expect(codes.contains("invalid_attempts"))
        #expect(codes.contains("invalid_retry_delay"))
    }

    @Test("Undeclared interpolation is rejected")
    func undeclaredVariable() {
        let workflow = Workflow(name: "Bad", steps: [
            Step(
                id: "type",
                action: .setValue(locator: Locator(role: "AXTextField"), value: "{{missing}}")
            )
        ])
        let issues = WorkflowSchemaValidator().validate(workflow)
        #expect(issues.contains { $0.code == "undeclared_variable" })
    }

    @Test("Secret defaults are a warning, not a decoding failure")
    func secretDefaultWarning() throws {
        let workflow = Workflow(
            name: "Secret",
            variables: ["password": .init(defaultValue: "plaintext", secret: true)],
            steps: [Step(id: "pause", action: .pause(duration: 0))]
        )
        let issues = WorkflowSchemaValidator().validate(workflow)
        #expect(issues.contains { $0.code == "secret_default" && $0.severity == .warning })
        try WorkflowSchemaValidator().validateOrThrow(workflow)
    }

    @Test("Variable interpolation trims names and catches malformed input")
    func interpolation() throws {
        #expect(try VariableResolver.interpolate("Hello {{ name }}!", using: ["name": "Ada"]) == "Hello Ada!")
        #expect(VariableResolver.placeholderNames(in: "{{a}}/{{ b }}") == ["a", "b"])
        #expect(throws: VariableResolutionError.self) {
            try VariableResolver.interpolate("{{missing}}", using: [:])
        }
        #expect(throws: VariableResolutionError.self) {
            try VariableResolver.interpolate("{{open", using: [:])
        }
    }

    @Test("Required variables must be supplied")
    func requiredVariable() throws {
        #expect(throws: VariableResolutionError.missingRequired("token")) {
            try VariableResolver.resolve(declarations: ["token": .init(required: true)])
        }
        let resolved = try VariableResolver.resolve(
            declarations: ["token": .init(required: true, secret: true)],
            overrides: ["token": "abc"]
        )
        #expect(resolved.values["token"] == "abc")
        #expect(resolved.redactedValue(for: "token") == "••••••")
    }

    @Test("YAML rejects unknown fields and payloads from a different action")
    func invalidPayloadsAreRejected() {
        for extra in ["unexpected: true", "locator: {identifier: submit}"] {
            let yaml = """
            name: Invalid
            steps:
              - id: pause
                action: pause
                duration: 0
                \(extra)
            """
            #expect(throws: WorkflowYAMLError.self) { try WorkflowYAML.decode(yaml) }
        }
    }

    @Test("YAML rejects duplicate keys and aliases")
    func ambiguousYAMLIsRejected() {
        for yaml in [
            "name: First\nname: Second\nsteps: [{id: pause, action: pause, duration: 0}]",
            "name: Alias\nsteps: [&step {id: pause, action: pause, duration: 0}, *step]"
        ] {
            #expect(throws: WorkflowYAMLError.self) { try WorkflowYAML.decode(yaml) }
        }
    }
}
