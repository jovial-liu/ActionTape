import Foundation
import Testing
@testable import ActionTapeCLIKit

@Test func emptyArgumentsShowHelp() throws {
    #expect(try CLIOptions.parse([]).command == .help)
    #expect(try CLIOptions.parse(["run", "--help"]).helpTopic == "run")
}

@Test func parsesRunOptionsWithoutLosingEqualsInValues() throws {
    let options = try CLIOptions.parse([
        "run", "sample.yml", "-v", "note=a=b", "--variable-env", "password=TEST_SECRET",
        "--trace=result.json", "--timeout", "2.5", "--allow-coordinate-fallback"
    ])
    #expect(options.tape == "sample.yml")
    #expect(options.variables == ["note": "a=b"])
    #expect(options.variableEnvironment == ["password": "TEST_SECRET"])
    #expect(options.timeout == 2.5)
    #expect(options.trace == "result.json")
    #expect(options.allowCoordinateFallback)
    #expect(try options.resolvedVariables(environment: ["TEST_SECRET": "value"])["password"] == "value")
}

@Test(arguments: [
    ["run"], ["inspect"], ["unknown"], ["validate", "one", "two"],
    ["run", "t.yml", "--unknown"], ["run", "t.yml", "--trace"],
    ["run", "t.yml", "--timeout", "nan"], ["run", "t.yml", "--timeout", "inf"],
    ["run", "t.yml", "--timeout", "-1"], ["run", "t.yml", "--timeout", "3601"],
    ["run", "t.yml", "--dry-run=false"], ["validate", "t.yml", "--variable", "x=y"],
    ["run", "t.yml", "-v", "x=a", "--variable-env", "x=SECRET"],
    ["run", "t.yml", "--timeout", "1", "--timeout", "2"],
    ["inspect", "--point", "nan,2"], ["inspect", "--point", "2"],
    ["run", "t.yml", "--dry-run", "--trace", "r.json"]
])
func rejectsInvalidArguments(_ arguments: [String]) {
    #expect(throws: CLIUsageError.self) { try CLIOptions.parse(arguments) }
}

@Test func secretValuesAreNotIncludedInUsageErrors() {
    do {
        _ = try CLIOptions.parse(["run", "t.yml", "--variable", "super-secret-value"])
        Issue.record("Expected invalid assignment to fail")
    } catch {
        #expect(!error.localizedDescription.contains("super-secret-value"))
    }
}

@Test func emptyVariableAndDashPrefixedFileAreSupported() throws {
    let options = try CLIOptions.parse(["run", "--variable=note=", "--", "-file.yml"])
    #expect(options.tape == "-file.yml")
    #expect(options.variables["note"] == "")
}

@Test func negativeScreenCoordinatesAreValid() throws {
    let options = try CLIOptions.parse(["inspect", "--point", "-120,30"])
    #expect(options.point?.x == -120)
    #expect(options.point?.y == 30)
}

@Test func missingEnvironmentIsAnError() throws {
    let options = try CLIOptions.parse(["run", "t.yml", "--variable-env", "note=UNSET_TEST_VAR"])
    #expect(throws: CLIUsageError.self) { try options.resolvedVariables(environment: [:]) }
}

@Test func sourceTapeCannotBeOverwrittenByTrace() {
    let source = URL(fileURLWithPath: "/tmp/source.actiontape.yml")
    #expect(throws: CLIUsageError.self) { try TraceWriter.preflight(destination: source, source: source) }
}

@Test func terminalControlSequencesAreRemoved() {
    #expect(CLIExecutor.safeTerminal("hello\u{1B}[31m") == "hello[31m")
}
