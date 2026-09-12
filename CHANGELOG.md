# Changelog

All notable changes to ActionTape will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project intends to use [Semantic Versioning](https://semver.org/).

## [Unreleased]

No changes yet.

## [0.1.0] — Source preview

### Added

- Native Studio with a local tape library, YAML import/export, editable steps,
  locator and retry editors, variable inputs, and a live per-step trace.
- App-selective semantic click recording with a floating Stop control.
- Deterministic Accessibility runner for application activation, press, value
  assignment, hotkeys, waits, assertions, and pauses.
- YAML validation, variable interpolation, bounded retries and timeouts,
  application-scoped targeting, and ambiguous-match failure.
- Dependency-free CLI argument parsing, validation, dry-run, permission checks,
  point inspection, replay, cancellation, and value-redacted trace export.
- ActionTape Practice, an in-memory native app with a synthetic first-run tape.
- Source documentation, compatibility guidance, examples, and development app
  packaging for Studio and Practice.
- Vendored Yams 6.2.2 with Yams/libyaml MIT notices for offline source builds.
- Clean, network-denied Swift build/test checks and app-local resource/icon
  verification; local bundles include all license notices.

### Preview limitations

- Recording captures app activation and supported clicks; text and hotkey steps
  must be authored manually.
- Traces do not contain screenshots or Accessibility-tree diffs.
- Packaging builds for the host architecture without Developer ID signing or
  notarization. Broad third-party app compatibility is not established.
- Tape and trace formats are pre-stable. See the
  [release notes](docs/releases/v0.1.0.md) for the compatibility policy.
