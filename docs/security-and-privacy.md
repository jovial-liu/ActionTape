# Security and privacy

ActionTape is local developer tooling with unusually broad potential authority:
macOS Accessibility permission lets an approved process observe and control UI
in other applications. Treat a tape like a script and a trace like a diagnostic
artifact, not like harmless media.

## Permissions

| Permission | Current need | Why |
| --- | --- | --- |
| Accessibility | Required for semantic inspection and playback | Resolve elements and invoke supported Accessibility actions. |
| Input Monitoring | May be required for Studio recording, depending on macOS policy | Studio uses a global left-click monitor. The core tape model and playback runner do not need this permission. |
| Screen Recording | Not required by the current trace model | Planned opt-in screenshots would require separate consent. |
| Automation / Apple Events | Not part of the current execution design | Application activation uses local system APIs rather than app-specific AppleScript dictionaries. |
| Network | Not required for a checked-out source build or runtime | Yams/libyaml sources are vendored; the current app has no telemetry or cloud execution path. Getting the source or toolchain, and GitHub runner setup, can require network access. |

macOS permission UI and attribution can vary between a packaged app, an
executable launched with `swift run`, and the terminal hosting a development
command. Follow the operating-system prompt and grant access only to the exact
local build you intend to test. Rebuilding or moving an executable can cause
macOS to request approval again.

The source-preview recorder observes application activation and supported
left-click actions only in the running applications explicitly selected in
Studio. It does not install a keyboard event tap or read control values.
Text fields, including secure text fields, are excluded. The floating Stop
control remains available while another app is active. Control labels and
window names can still be sensitive inside an allowed application.

## What files can contain

### Tapes

Tapes are plaintext YAML. They can contain app identities, UI titles,
descriptions, file paths, and literal `setValue` content. `secret: true` marks a
variable's intent but is not encryption. Studio's variable editor removes a
default when an input is marked secret and prompts for the value per run.
Imported tapes can already contain plaintext defaults; review and remove
those before sharing. Do not commit secret defaults.

### Element snapshots

The current semantic snapshot model includes identifier, role, subrole, title,
description, ancestry, and frame. It intentionally does not model an element's
Accessibility value. Titles and descriptions can nevertheless contain customer
names, document names, or other private text.

### Traces

Step traces record action kind, status, attempts, timing, and an optional
diagnostic message. They do not serialize `setValue` content or resolved
variable values. A message can still reveal locator text or application state;
sanitize traces before sharing.

## Trust boundaries

- **Trusted:** the local ActionTape build, a tape you reviewed, and explicit run
  inputs you supplied.
- **Untrusted by default:** downloaded tapes, copied trace files, target-app UI
  content, and paths embedded in a tape.
- **Outside ActionTape's boundary:** macOS permission enforcement, the target
  app's own security, sync behavior, the local account, and third-party build
  infrastructure.

ActionTape is not a sandbox and is not a privilege boundary. It does not make an
untrusted workflow safe. A tape can press destructive buttons, type into the
wrong account, or trigger a target app's network/sync behavior even when
ActionTape itself has no runtime networking.

## Safe-use checklist

1. Read the entire tape and resolve all variables before running it.
2. Use a test account and synthetic data for first runs.
3. Close unrelated applications that display sensitive information.
4. Prefer stable identifier/role locators and keep coordinate fallback off.
5. Start with non-destructive assertions, then add mutating steps deliberately.
6. Confirm the active app and account before a tape that types or submits data.
7. Keep tapes and traces out of public issues until sanitized.
8. Revoke Accessibility access when you no longer use the development build.

## Design protections currently present

- Execution is deterministic and does not send a tape to an LLM.
- Every supplied locator field must match; ambiguous top matches fail safely.
- Recording observes only the running apps explicitly selected for the session.
- Coordinate fallback is disabled by default.
- Snapshot and trace models omit control values and `setValue` contents.
- The runtime design has no telemetry or required network service.

These protections reduce accidental disclosure; they do not replace reviewing
a tape or the target application's own confirmations.

## Development builds

`scripts/package-app.sh` assembles a reproducible directory layout from a local
SwiftPM release build. It does not apply a Developer ID signature and does not
submit the app for notarization. Do not redistribute that development bundle as
if it were an official release, and do not disable Gatekeeper globally to open
it.

The bundle includes the ActionTape, Yams, and libyaml license notices. Automated
packaging checks inspect resources and metadata without granting Accessibility
permission or controlling another app. They are not a signing assessment or a
real-app compatibility test; see [packaging.md](packaging.md).

See [../SECURITY.md](../SECURITY.md) for private vulnerability reporting.
