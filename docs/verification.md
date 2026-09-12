# Source preview verification

This records local checks for the v0.1.0 source preview. It is not a certification
for other macOS versions or third-party applications.

## Local environment

Recorded on 2026-09-12:

- macOS 27.0, build 26A5388g
- Apple Silicon (`arm64`)
- Apple Swift 6.3.3
- CLI Accessibility permission already granted for the local test environment

The deployment target is macOS 14. This local run does not establish that the
minimum supported OS has been exercised.

## Completed checks

| Check | Observation | Scope |
| --- | --- | --- |
| Practice semantic replay | The CLI activated Practice, set the synthetic recipient, pressed Prepare Label, and passed the prepared-state assertion. | Real local Accessibility execution against the included test app. |
| Negative Practice assertion | After resetting Practice, an assertion for the prepared state exited with status `1`; subsequent steps were skipped. | A missing state did not produce a false successful run. |
| Isolated Practice packaging | Debug build and bundle verifier passed using a separate SwiftPM scratch directory. | Executable, metadata, ICNS, and ActionTape license; no signing or notarization claim. |
| Isolated Studio packaging | `ActionTapeStudio` built and was installed as the `ActionTape.app` executable; bundle verifier passed. | App-local SwiftPM resources, ICNS, metadata, executable, and third-party licenses. |
| Documentation and shell checks | Local Markdown links resolved and edited packaging/offline shell scripts passed Bash syntax checking. | Source documentation and script syntax. |

## Checks provided for reproduction

`swift test` exercises the core and CLI with fixtures. The network-denied script
uses clean build/cache directories, builds every product, runs the tests,
checks the actual CLI executable, and validates the example formats:

```bash
bash scripts/check-offline-build.sh
```

The command-line smoke script exercises an actual child process, including
SIGINT cancellation and its resulting trace, without controlling another app:

```bash
bash scripts/test-cli.sh .build/debug/actiontape
```

The GitHub workflow runs these checks and packages both native apps. A workflow
definition is not evidence of a completed CI run; inspect the repository's
current Actions result for the relevant commit.

## Still outside this evidence

- A broad Finder, Notes, TextEdit, Electron, or Catalyst compatibility matrix.
- A clean-account installation and permission-denial/re-grant matrix.
- Intel hardware and a real macOS 14 host.
- Developer ID signing, notarization, and downloaded-binary installation.

Keep the distinction between fixture tests, packaging checks, and actual
Accessibility interaction when reporting additional results.
