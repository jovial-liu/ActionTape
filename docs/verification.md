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
| Full Swift test suite | All 37 tests passed. | Core and CLI fixture tests, not a third-party app compatibility matrix. |
| Clean offline build | Network-denied build and tests passed; all four example tapes validated. | Vendored dependency build from clean scratch/cache directories. |
| CLI interruption | The actual CLI child process handled SIGINT and produced a cancelled trace; the smoke script passed. | Real signal handling without UI side effects. |
| Practice semantic replay | The CLI activated Practice, set the synthetic recipient, pressed Prepare Label, and passed the prepared-state assertion. | Real local Accessibility execution against the included test app. |
| Moved Practice window | The same semantic tape replayed successfully after the Practice window moved. | Identifier-based targeting at a different window position. |
| Negative Practice assertion | After resetting Practice, an assertion for the prepared state exited with status `1`; subsequent steps were skipped. | A missing state did not produce a false successful run. |
| Studio replay | A five-step Practice tape completed from the native Studio. | Real GUI-to-core replay in the local environment. |
| Studio locator inspection | `prepare-button` with role `AXButton` produced one matching candidate, score 1180, with the actual accessible label. | Read-only inspection of the live Practice Accessibility tree. |
| Studio layout | The native window showed all toolbar and footer controls after split-view layout correction. | Visual inspection of the current local build. |
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

The GitHub workflow is configured to run these checks and package both native
apps. Hosted CI has not yet been verified for this release. Inspect the
repository's Actions result for the relevant commit before claiming a passing
hosted run.

## Still outside this evidence

- A broad Finder, Notes, TextEdit, Electron, or Catalyst compatibility matrix.
- End-to-end physical click recording. App activation recording was verified;
  background-targeted desktop test events produced no captured clicks, so that
  check does not prove mouse click capture.
- A clean-account installation and permission-denial/re-grant matrix.
- Intel hardware and a real macOS 14 host.
- Developer ID signing, notarization, and downloaded-binary installation.

Keep the distinction between fixture tests, packaging checks, and actual
Accessibility interaction when reporting additional results.
