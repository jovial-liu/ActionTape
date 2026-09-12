# Contributing to ActionTape

Thanks for helping make deterministic macOS automation more approachable.
ActionTape is an early-stage project, so small, well-tested changes are easier
to review than broad rewrites.

## Before opening a change

- Search existing issues and pull requests.
- For a substantial feature or YAML format change, open a proposal first.
- Never include passwords, tokens, private window titles, or unredacted traces
  in an issue, fixture, screenshot, or commit.
- Keep the core deterministic. A recorded tape must not require an LLM or a
  network service to be interpreted.
- Prefer Accessibility semantics (identifier, role, title, and hierarchy) over
  screen coordinates.

## Development setup

You need macOS 14 or later, Xcode 16 (or a compatible Swift 6 toolchain), and
Git.

```bash
git clone https://github.com/jovial-liu/ActionTape.git
cd ActionTape
swift build
swift test
```

All runtime dependency sources are checked in under `Vendor/Yams` with their
licenses. A checked-out source tree builds without dependency downloads once
the Swift toolchain is installed. Run the clean, network-denied local check
with `bash ./scripts/check-offline-build.sh`; it uses a temporary build/cache
directory and does not replay workflows against real applications.

Run the development UI with:

```bash
swift run ActionTapeStudio
```

See the CLI surface that your checkout actually provides with:

```bash
swift run actiontape --help
```

To assemble a local development app bundle:

```bash
./scripts/package-app.sh
```

The script creates `.build/artifacts/ActionTape.app`. It does not add a
Developer ID signature or notarize the result.
The script verifies app-local resource resolution and includes third-party
notices. Read [docs/packaging.md](docs/packaging.md) for the manual relocated-app
launch check that is still required before distribution.

## Pull request checklist

- [ ] `swift build` succeeds.
- [ ] `swift test` succeeds.
- [ ] `bash ./scripts/check-offline-build.sh` succeeds after dependency changes.
- [ ] `./scripts/validate-examples.sh` succeeds when examples changed.
- [ ] New behavior has focused tests.
- [ ] User-visible behavior and YAML changes are documented.
- [ ] Examples contain only synthetic, non-sensitive data.
- [ ] Accessibility permission failure and missing-element cases fail clearly.
- [ ] The change does not silently fall back to coordinate-based replay.
- [ ] The PR describes what was tested on a real Mac, if applicable.

## Code and design guidelines

- Keep `ActionTapeCore` independent from SwiftUI where practical.
- Make serialized formats explicit and backwards-conscious. Discuss breaking
  tape or trace changes before merging them.
- Return actionable errors instead of swallowing Accessibility failures.
- Avoid fixed sleeps in playback. Prefer bounded, observable conditions.
- Treat values captured from UI elements as potentially sensitive.
- Do not add telemetry or runtime network access without an explicit proposal,
  documentation, and an opt-in design.

## Reporting bugs

Use the issue templates and include the macOS version, app under automation,
minimal synthetic tape, and exact command. Remove sensitive text and window
metadata first. Security issues follow [SECURITY.md](SECURITY.md), not the
public bug tracker.

By participating, you agree to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).
