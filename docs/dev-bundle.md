# Start here: ActionTape development preview

This archive contains locally built applications from the ActionTape source
preview. It is intended for development and testing on macOS 14 or later,
using the architecture named in the archive filename. It is not a universal,
Developer ID-signed, or notarized distribution.

## Contents

- **ActionTape.app** — native tape studio: record, edit, inspect, and replay.
- **ActionTape Practice.app** — an in-memory synthetic label form for first runs.
- **actiontape** — the terminal runner, using the same core as Studio.
- **examples/** — synthetic YAML tapes; start with `practice-label.yaml`.
- **LICENSE** and **Licenses/** — ActionTape, Yams, and libyaml notices. App
  bundles also include the notices required by their own dependencies.

The full source and documentation are at
[github.com/jovial-liu/ActionTape](https://github.com/jovial-liu/ActionTape).

## First replay

Extract the complete archive and keep its contents together. Open
**ActionTape Practice.app** and **ActionTape.app** from Finder. In Studio,
choose **Import tape…**, select `examples/practice-label.yaml`, and inspect its
four steps before replaying.

If Studio asks for Accessibility access, approve that exact local build in
System Settings, then return to Studio. Choose **Replay**, review the synthetic
Recipient input, and continue. Practice should display **Prepared**. Its form
only changes in memory: it does not send, save, or purchase anything.

Reset Practice, move its window, and replay the tape again. The controls are
located by Accessibility identifiers rather than recorded screen positions.

## Terminal use

In Terminal, change into the extracted folder and run:

```bash
./actiontape --version
./actiontape validate examples/practice-label.yaml
./actiontape run examples/practice-label.yaml --dry-run
./actiontape doctor
```

The CLI or its terminal host needs its own Accessibility grant. Studio's grant
does not cover it. `./actiontape doctor --request-access` requests the system
prompt. After reviewing the tape and permissions:

```bash
./actiontape run examples/practice-label.yaml \
  --variable 'recipient=Ada Lovelace' \
  --trace practice-trace.json
```

Control-C cancels a terminal run. Studio provides a floating Stop control.
Cancellation cannot undo actions already performed by a target application.

## Verify the archive

A `.zip.sha256` file accompanies the archive. From the directory containing
both files, run `shasum -a 256 -c` followed by the checksum file's name. A matching
checksum detects changes relative to that checksum file; it does not prove a
publisher's identity or replace code signing.

## Preview limitations

macOS may block an app downloaded from the internet because these development
builds are not signed with a Developer ID or notarized. Build from the reviewed
source if you cannot open this preview; do not disable Gatekeeper globally.

Recording supports selected-app activation and controls exposing `AXPress`.
Text, hotkeys, scrolling, and dragging are not automatically recorded. Add text
and shortcut steps manually. Accessibility support varies by app and version;
the Finder, TextEdit, and Notes tapes may need adjustment for your setup.

Tapes are plaintext and can control other apps. Use reviewed tapes and synthetic
inputs first. Traces omit resolved inputs and `setValue` contents but can still
include private labels, workflow names, or step IDs. Inspect matches redacts
supplied secret-variable values, not every possible secret in an app's UI.
