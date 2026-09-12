# Maintainer launch checklist

This checklist deliberately separates source readiness from a public release.
Completing repository setup does not mean a signed binary exists.

## Before making the repository public

- [ ] Confirm `swift build`, `swift test`, and `./scripts/package-app.sh` on a
      macOS 14+ development machine, and record its OS, architecture, and Swift
      version. A separate clean-account install check belongs to distribution.
- [ ] Run `bash ./scripts/check-offline-build.sh` with a preinstalled Swift 6
      toolchain; confirm no dependency cache or network is required.
- [ ] Move the packaged app outside the checkout, open it, and verify its icon
      and Studio window load without the `.build` resource directory.
- [ ] Confirm the packaged `Contents/Resources/Licenses` contains ActionTape,
      Yams 6.2.2, and libyaml notices.
- [ ] Replay the included Practice tape with synthetic data and record macOS
      and architecture. Label system-app examples as unverified unless their
      exact target version and initial state have also been tested.
- [ ] Replace future demo placeholders only with footage of the checked-in code.
- [ ] Review tapes, screenshots, fixtures, and traces for private information.
- [ ] Enable GitHub private vulnerability reporting.
- [ ] Update repository owner links if the final owner is not `jovial-liu`.
- [ ] Add repository description: “Playwright-style semantic automation and
      traces for macOS — native, deterministic, AX-first.”
- [ ] Add topics such as `macos`, `swift`, `accessibility`, `automation`,
      `testing`, `developer-tools`, and `trace-viewer`.
- [ ] Add a real screenshot captured from the current Studio UI; a custom social
      preview can follow after the source release.

## Before the first tagged source release

- [ ] Decide and document the tape/trace compatibility policy.
- [ ] Move completed items from `[Unreleased]` into a versioned changelog entry.
- [ ] Verify that README feature statuses match the tag, not the default branch.
- [ ] Attach checksums if distributing manually assembled artifacts; GitHub's
      generated source archives do not establish binary provenance.
- [ ] State clearly that a bundle is unsigned/unnotarized unless a real signing
      and notarization pipeline has completed.
- [ ] State the tested macOS and hardware architecture. The local packaging
      script produces the host architecture, not a universal app.
- [ ] Test ambiguous locator, cancellation, and a failing assertion. Record
      which checks used fixtures and which used live UI. Document permission
      and installation checks that still need a clean-account test.

## Before distributing a binary

- [ ] Use a controlled Developer ID signing identity.
- [ ] Harden and notarize the exact release artifact.
- [ ] Staple and verify the notarization ticket.
- [ ] Publish provenance and checksums.
- [ ] Verify upgrade and uninstall behavior.
- [ ] Update privacy documentation if screenshots, recording, telemetry, or any
      network feature has been added.

No item in this file claims that a GitHub repository, tag, signed app, or
notarized release already exists.
