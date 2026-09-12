# ActionTape roadmap

ActionTape's north star is **“Playwright for your Mac”**: record intent as
semantic Accessibility actions, replay it deterministically, and inspect a
useful trace when it fails.

This is a direction, not a release promise. Items are marked as **available**,
**in progress**, or **planned**. The root README is the user-facing source of
truth for the exact current surface.

## Foundations — source preview

- **Available:** versioned YAML model with typed steps and variables.
- **Available:** semantic locator scoring across identifier, role, title,
  description, and ancestry, with safe ambiguity failure.
- **Available:** structured, value-redacted run/step trace model.
- **Available:** local AX execution across every declared action.
- **Available:** CLI commands for validation, execution, variable overrides,
  point inspection, and trace export, without a separate parser dependency.
- **Available:** native Studio tape library, YAML import/export, replay, live
  trace timeline, trace export, and semantic click recording.
- **Available:** native in-memory Practice app and a synthetic first-run tape.
- **Available:** Swift build/test scripts and a GitHub Actions configuration,
  examples, privacy guidance, and local
  development app packaging with bundled resources, icons, and licenses.
- **Available:** vendored Yams/libyaml and a clean network-denied build/test check.

## Recorder and authoring

- **Available:** choose an explicit set of running apps and capture their
  activation and supported `AXPress` clicks.
- **Available:** map captured clicks to AX identifiers, roles, labels, and
  ancestry while excluding text fields and control values.
- **Available:** add, edit, duplicate, delete, and reorder all seven action kinds;
  edit locators, ancestors, text, shortcuts, timeouts, and retries.
- **Available:** variable editor and per-run inputs, with secret fields and no
  secret defaults created by the editor.
- **Planned:** explicit Input Monitoring status and consent guidance in Studio.
- **Planned:** broader interaction capture beyond clicks.
- **Planned:** coalesce typing into editable, redactable actions.
- **Available:** read-only locator inspection with ranked candidates, score
  explanations, and unique/missing/ambiguous diagnostics.
- **Planned:** interactive locator repair and suggested selectors.
- **Available:** floating Stop control and selected-app recording scope.
- **Planned:** recording pause zones within selected applications.

## Trace viewer

- **Available:** per-step status, duration, attempts, and failure messages.
- **Planned:** timeline scrubber and historical run comparisons.
- **Planned:** opt-in screenshots with explicit Screen Recording consent.
- **Planned:** sanitized Accessibility-tree snapshots and semantic diffs.
- **Available:** current locator and ranked candidates in read-only inspection.
- **Planned:** candidate snapshots attached to historical run traces.
- **Planned:** exportable support bundle with a redaction review step.

## Reliability and testing

- **Planned:** richer semantic wait conditions and assertions.
- **Available (early):** cooperative run cancellation and Studio's stop control.
- **Planned:** robust interruption and target-app crash recovery.
- **Planned:** schema migrations and a stated backwards-compatibility window.
- **Planned:** compatibility fixtures across representative AppKit, SwiftUI,
  Catalyst, and Electron applications.
- **Planned:** headful CI strategy for deterministic test apps.

## Distribution

- **Planned:** signed and notarized universal macOS releases.
- **Planned:** Homebrew distribution after a repeatable release process exists.
- **Planned:** artifact checksums and build provenance.
- **Planned:** stable tape/trace documentation and release migration notes.

## Explicit non-goals

- Requiring an LLM or cloud account to replay a tape.
- Treating screen coordinates as the normal selector strategy.
- Hiding or bypassing macOS privacy permission prompts.
- Stealth monitoring, remote administration, or automation without the local
  user's authorization.
- Claiming a signed binary or compatibility level that has not been tested.

Feature requests are welcome when they preserve deterministic execution,
semantic targeting, explicit consent, and inspectable failure behavior.
