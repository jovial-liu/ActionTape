# Studio guide

Studio turns a tape into three connected views: your local library on the left,
ordered steps in the center, and the selected step's editor on the right.

## Open a first tape

Build Studio and the Practice app from the repository root:

```bash
bash scripts/package-app.sh
bash scripts/package-practice-app.sh
open 'dist/ActionTape Practice.app'
open .build/artifacts/ActionTape.app
```

Choose **Import tape…** in Studio and select `examples/practice-label.yaml`.
Inspect each of its four steps. The final assertion looks for the
`prepared-status` element, which Practice exposes after preparing a label.

Choose **Grant access** if Studio does not yet have Accessibility permission.
After approving the exact local build in System Settings, return to Studio;
the permission indicator refreshes. The command-line runner's permission is
separate from Studio's.

Choose **Replay**, review the Recipient input, and continue. The Practice form
changes in memory and the timeline reports each step's result. Reset Practice,
move its window, and replay again to see identifier-based targeting survive
the move.

## Edit and save

Change a tape's name or description directly above the timeline. **Add step**
supports every action kind. Selecting a step opens its action fields, locator,
timeout, and retry settings. Use the arrows to reorder a step, or duplicate and
delete from its controls or context menu.

Place an **Activate app** step before actions that inspect or control another
app. A bundle identifier is usually more portable than an absolute path. Use
identifier and role for locators when the app provides them; add other fields
only when they help identify the intended control. Every supplied criterion
must match.

Draft edits are saved in `~/Library/Application Support/ActionTape/Tapes/`.
Incomplete drafts can be saved; validation issues must be resolved before
replay. The save indicator and banner report persistence failures. Export a
YAML copy when you want to version a tape or share it with another person.

## Variables and private inputs

Open **Variables** to add a named input. Refer to it as `{{name}}` in text,
locators, or app targets. Non-secret defaults are saved in plaintext YAML.
Turning on **Secret (run-time only)** removes the default and requests the value
at replay time. Runtime input fields are cleared when replay starts or is
cancelled; values still exist in memory while the run needs them.

An imported YAML file can already contain a plaintext secret default. The
editor offers to remove it. Review imported tapes before sharing, and keep
credentials out of literal `setValue` fields.

## Record across selected apps

Open the target apps first, then choose **Record**. Select the apps to include;
switches among them become activation steps. Other applications and Studio are
ignored. A floating **Stop** control remains available while another app is
active.

The recorder captures only controls that expose an `AXPress` action, including
an appropriate button ancestor when a click lands on its text or image. It
skips unsupported controls and text fields. Keystrokes, field contents, and
screen images are not recorded. Add text and shortcut actions manually after
stopping, then review the full tape before replaying it.

The selected-app list limits what ActionTape records; it does not narrow the
broad Accessibility permission granted by macOS. Control and window labels can
still contain private data.

## Inspect a run

Choose **Inspect matches** for a selected locator step to activate its preceding
target app and read the current Accessibility tree. The result shows candidate
count, roles, identifiers, labels, scores, and scoring explanations. Inspection
does not press controls or assign values. It reports unique, missing, and
ambiguous outcomes, requests only variables used by the target or locator, and
can be cancelled. Use it to understand a locator before replaying the action.
Supplied secret-variable values are redacted from diagnostics. This is not
automatic detection of every secret in an app: accessible labels and
descriptions can still contain private document or account information.

Each timeline step shows its status and, after execution, duration and attempts.
Select a failed step to inspect its error and locator. Missing or ambiguous
controls need a corrected locator or expected app state; a retry does not make
a wrong locator more specific.

**Run this step** also activates the most recent preceding target app. It does
not replay all earlier setup steps, so the target application's current state
still matters. Use the floating **Stop** or Studio's **Stop Run** to cancel.
Already completed effects are not undone.

Export a trace for debugging after a run. Trace files omit resolved variable
values and `setValue` contents, but may contain private UI labels, step IDs, or
workflow names. Review a trace before attaching it to a public issue.
