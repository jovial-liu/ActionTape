# Application compatibility

ActionTape automates the Accessibility tree an application exposes, not its
pixels. This is substantially more resilient than recorded coordinates, but it
also means compatibility depends on the target application's Accessibility
quality.

## Usually good candidates

For a controlled first run, use the included **ActionTape Practice** app with
[`examples/practice-label.yaml`](../examples/practice-label.yaml). Its native
form exposes stable identifiers for the field, button, and prepared state, and
only changes in-memory data. It is a demo fixture, not evidence of support for
all SwiftUI applications.

These are candidates to investigate, not a list of certified integrations.
No broad cross-application compatibility matrix has been established for this
source preview.

- Native AppKit and SwiftUI apps with identifiers, roles, and actions.
- Mac Catalyst apps that expose a coherent Accessibility hierarchy.
- Electron apps whose controls expose useful roles, names, and actions.
- Browser chrome or web content with a stable Accessibility representation,
  when desktop-level automation is actually needed.

Support in these categories is not automatic or guaranteed. Test the exact app
and version you intend to automate.

## Common sources of drift

- An application update changes identifiers or hierarchy.
- A localized UI changes titles and descriptions.
- Two controls expose the same semantics, producing an intentional ambiguity
  failure.
- A custom-drawn control exposes no Accessibility action.
- The application has a different initial account, window, or document state.
- A permission prompt, modal dialog, or onboarding window becomes active.

## Locator authoring strategy

Use the smallest combination that remains unique:

1. Prefer a stable `identifier` and `role`.
2. Add title or description when the app lacks an identifier.
3. Add nearest-parent-first `ancestry` to distinguish repeated controls.
4. Add a bounded `waitFor` for UI that appears asynchronously.
5. Treat ambiguity as a tape bug to fix, not a reason to click by coordinates.

Coordinate fallback exists only as an explicit, disabled-by-default
compatibility escape hatch. It is omitted from repository examples.

## What automated checks establish

CI builds Studio, Practice, and the CLI, runs model/CLI/driver-fixture tests, validates the
example YAML files, and verifies `.app` resources and metadata. Those checks do
not replay Finder, Notes, or TextEdit and do not establish UI compatibility.

In particular, Finder's `AXOutline` example assumes a list-view Accessibility
structure, TextEdit can begin at a document chooser or with another document
open, and Notes depends on account and selection state. Inspect and adjust a
locator for the exact application state before treating an example as a test.

## Reporting an incompatibility

Use the bug template with:

- macOS and target app versions;
- app technology (native, Catalyst, Electron, or web) if known;
- a minimal tape containing synthetic text;
- expected and observed semantic element details; and
- a sanitized trace.

Never attach a raw snapshot or screenshot containing credentials, private
documents, customer information, or personal window titles.
