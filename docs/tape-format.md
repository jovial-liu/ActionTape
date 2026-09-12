# Tape format

An ActionTape tape is a versioned YAML workflow. Format version `1` is designed
to be readable in a diff and shared by Studio and the CLI.

The loader accepts one UTF-8 YAML document up to 1 MiB. Unknown or duplicate
fields, action-incompatible payloads, anchors, aliases, and explicit tags are
rejected. Workflows support at most 2,000 steps and 256 variable declarations.
These limits also apply to imported Studio tapes.

```yaml
formatVersion: 1
name: Open Applications in Finder
description: A small, non-destructive example.
variables: {}
steps:
  - id: activate-finder
    action: activateApp
    app:
      bundleIdentifier: com.apple.finder

  - id: open-applications
    action: hotKey
    hotKey:
      key: a
      modifiers: [command, shift]

  - id: verify-window
    action: assertExists
    locator:
      role: AXWindow
      title: Applications
    timeout: 5
```

## Workflow fields

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `formatVersion` | integer | no | Defaults to the current format (`1`). Declare it for durable files. |
| `name` | string | yes | Human-readable workflow name. |
| `description` | string | no | Purpose and safety notes. |
| `variables` | mapping | no | Variable name to declaration; defaults to an empty mapping. |
| `steps` | sequence | yes | Ordered workflow steps. |

## Variables

Variables are interpolated with `{{name}}`; whitespace inside the braces is
accepted. Interpolation applies to `setValue` text and relevant app/locator
strings.

```yaml
variables:
  query:
    default: accessibility inspector
    required: false
    secret: false
    description: Synthetic search text.
```

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `default` | string | none | Used when a run does not supply the variable. |
| `required` | boolean | `false` | The run must resolve a value. |
| `secret` | boolean | `false` | Marks sensitive intent for redaction-aware tooling. It does not encrypt YAML. |
| `description` | string | none | Guidance for a caller or editor. |

Never store a real secret as `default`. The tape is plaintext, and the current
project does not provide a secrets vault.

## Common step fields

Every step is a flat mapping.

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `id` | string | yes | Stable, unique step identifier used in traces. |
| `name` | string | no | Human-readable label. |
| `action` | string | yes | One of the action kinds below. |
| `timeout` | seconds | no | Total step time budget across attempts. The runner default applies when omitted. |
| `retry.maxAttempts` | integer | no | Total attempts including the first; default `1`. |
| `retry.delay` | seconds | no | Delay between attempts; default `0.25`. |

Timeout and retry make waiting explicit; they do not change locator meaning.

## Actions

### `activateApp`

Provide at least one app identity. A bundle identifier is usually the most
portable choice.

Place an activation step before UI control steps. A supplied `path` must name
an actual application bundle; it is not a shell command. If both path and
bundle identifier are supplied, they must agree. A failed strong identity does
not fall back to an unrelated app with the same display name.

```yaml
- id: activate-notes
  action: activateApp
  app:
    bundleIdentifier: com.apple.Notes
    # name: Notes
    # path: /System/Applications/Notes.app
```

### `press`

Resolve a semantic UI element and invoke its press action.

```yaml
- id: press-new
  action: press
  locator:
    identifier: new-item
    role: AXButton
    title: New
```

### `setValue`

Set the Accessibility value of a resolved control. Trace entries omit `value`.

```yaml
- id: enter-query
  action: setValue
  locator:
    role: AXTextField
    description: Search
  value: "{{query}}"
```

### `hotKey`

Send a deterministic key plus modifiers. Supported modifier names are
`command`, `option`, `control`, `shift`, and `function`.

```yaml
- id: create-document
  action: hotKey
  hotKey:
    key: n
    modifiers: [command]
```

### `waitFor` and `assertExists`

Both resolve a locator. `waitFor` polls within the timeout; `assertExists` is an
explicit assertion step.

```yaml
- id: wait-for-editor
  action: waitFor
  locator:
    role: AXTextArea
    ancestry:
      - role: AXScrollArea
      - role: AXWindow
  timeout: 8
  retry:
    maxAttempts: 3
    delay: 0.25
```

### `pause`

Pause for a number of seconds. Prefer `waitFor` when a semantic condition
exists; fixed time is inherently sensitive to machine load.

```yaml
- id: short-settle
  action: pause
  duration: 0.25
```

## Locators

A locator can combine:

- `identifier`: Accessibility identifier;
- `role`: exact Accessibility role such as `AXButton`;
- `title`: control title;
- `description`: Accessibility description; and
- `ancestry`: nearest-parent-first list of `{identifier, role, title}` filters.

Titles and descriptions use normalized case/whitespace matching when an exact
match is unavailable. Every supplied field is a constraint: an identifier match
does not override a title or description mismatch. Roles must match. Ancestry
can skip structural containers while preserving order. If top candidates remain
indistinguishable, resolution fails rather than choosing by traversal order.

Prefer an identifier plus role when the target app exposes both. Add ancestry
to disambiguate repeated controls. Localized titles are useful but less
portable across language settings.

### Coordinate compatibility field

The version 1 model can deserialize this escape hatch:

```yaml
fallback:
  x: 640
  y: 420
  coordinateSpace: globalScreen
```

Coordinate execution is disabled by default, not used by the examples, and not
part of ActionTape's portability promise. It requires an explicit runner opt-in
where supported. Prefer fixing the semantic locator.

## Trace shape

A run result contains `workflowName`, overall `status`, start/end dates, and
ordered `steps`. Each step trace contains `stepID`, action kind, status,
attempts, start/end dates, and an optional message. CLI trace exports use ISO
8601 dates. The external trace format remains pre-stable in this preview;
consumers should pin the ActionTape version they use.

Trace records intentionally omit variables and action input text. Error
messages and locator-related context may still disclose UI labels, so traces
remain potentially sensitive.

## Examples and compatibility

See the [example guide](../examples/README.md). Start with the included Practice
app and its stable identifiers. Additional examples use English labels from
macOS system applications to demonstrate the format. Apple can change Accessibility
trees between releases, localization changes titles, and a configured app may
have a different initial state. Validate and inspect a tape before running it;
examples are not a compatibility guarantee.
