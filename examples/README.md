# Example tapes

Start with **ActionTape Practice**, the included native test app. Its identifiers
are owned by this repository, and the entire label workflow stays in memory.

```bash
bash scripts/package-practice-app.sh
open 'dist/ActionTape Practice.app'
swift run actiontape validate examples/practice-label.yaml
swift run actiontape run examples/practice-label.yaml --dry-run
swift run actiontape doctor
```

After granting Accessibility access to the CLI or its terminal host, replay:

```bash
swift run actiontape run examples/practice-label.yaml \
  --variable 'recipient=Ada Lovelace' \
  --trace .build/practice-trace.json
```

The four steps activate Practice, fill Recipient, press Prepare Label, and
assert that the `prepared-status` element exists. Reset the form, move its
window, and replay to try the same locators at a different screen position.

The system-app tapes are format demonstrations, not a compatibility test matrix:
Apple can change Accessibility roles, hierarchy, and localized labels between
macOS/app versions.

| Tape | Intended effect | Side effects |
| --- | --- | --- |
| [`practice-label.yaml`](practice-label.yaml) | Prepares a synthetic label in ActionTape Practice. | In-memory state only; build and open Practice first. |
| [`finder-applications.yaml`](finder-applications.yaml) | Opens the Applications folder in Finder and asserts a semantic file list. | Opens a Finder window; does not modify files. |
| [`textedit-draft.yaml`](textedit-draft.yaml) | Creates an unsaved TextEdit document and inserts synthetic text. | Leaves an unsaved document open. |
| [`notes-new-note.yaml`](notes-new-note.yaml) | Creates a Notes note with synthetic text. | Creates a note that may sync through the configured account. |

Validate an example without controlling another application:

```bash
swift run actiontape validate examples/practice-label.yaml
```

Then read every step before choosing to run it. Use English UI language for the
repository locators as written, grant Accessibility access only to the local
build under test. For example, to try Finder after Practice:

```bash
swift run actiontape run examples/finder-applications.yaml \
  --trace .build/finder-trace.json
```

None of these tapes contains or needs a coordinate fallback. Do not substitute
real credentials or personal data for the synthetic defaults.

Initial UI state matters: the Finder example's `AXOutline` assumes list view;
TextEdit may show a document chooser and uses your configured document format;
Notes may create and sync content in the selected account. Close unrelated
documents, inspect the current app, and adjust locators when necessary. Format
validation in CI is not evidence that these real-app workflows have replayed
successfully on your macOS version.
