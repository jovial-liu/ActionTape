import ActionTapeCore

enum CLIHelp {
    static func text(topic: String?) -> String {
        switch topic {
        case "run":
            return """
            USAGE: actiontape run <tape.yml> [options]

            Replay a reviewed workflow. This can modify other applications.
            Accessibility permission belongs to this executable or its terminal host,
            separately from ActionTape Studio.

              -v, --variable name=value       Supply a variable (repeatable)
              --variable-env name=ENV_VAR     Read a variable from the environment
              --trace <path.json>             Save a value-redacted run trace
              --timeout <seconds>             Default timeout (10; range 0–3600)
              --allow-coordinate-fallback     Opt in to fragile coordinate targeting
              --continue-after-failure        Attempt later steps after failures
              --dry-run                       Validate inputs; perform no UI actions
              -h, --help                      Show this help

            Use --variable-env for secrets to avoid values in shell history.
            Press Control-C to cancel. Ambiguous locators fail without clicking.
            """
        case "validate":
            return """
            USAGE: actiontape validate <tape.yml> [--json]

            Check YAML and the workflow schema without Accessibility permission.
            --json prints machine-readable validation issues.
            Exit status: 0 valid, 65 invalid data, 64 invalid arguments.
            """
        case "inspect":
            return """
            USAGE: actiontape inspect --point <x,y> [--include-coordinate-fallback]

            Print a JSON locator for the accessible element at a global Quartz point.
            The primary screen's origin is its top-left corner. Negative coordinates
            are valid for other displays. No element value is read.
            """
        case "doctor":
            return """
            USAGE: actiontape doctor [--request-access]

            Report runtime and Accessibility permission status.
            --request-access asks macOS to show its authorization prompt.
            ActionTape never edits the macOS permissions database.
            """
        default:
            return """
            ActionTape \(ActionTapeCore.version)
            Replay macOS workflows by meaning, not pixels.

            USAGE: actiontape <command> [options]

              validate <tape.yml>   Validate a workflow without running it
              run <tape.yml>        Replay with the native Accessibility runtime
              inspect --point x,y  Print the semantic locator under a screen point
              doctor               Check permissions and runtime information

              --help               Show help
              --version            Print the version

            Run actiontape <command> --help for command-specific options.
            No cloud, account, LLM, or network connection is required.
            """
        }
    }
}
