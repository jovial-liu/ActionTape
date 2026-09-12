# Security Policy

ActionTape can observe and control user-interface elements through macOS
Accessibility APIs. Bugs can therefore have consequences beyond a normal
desktop utility. Please treat unexpected control of another app, disclosure of
captured UI text, unsafe tape parsing, or bypasses of an intended confirmation
as security-sensitive.

## Supported versions

There are no tagged releases yet. Security fixes currently target the latest
commit on the default branch. This policy will be updated when the first stable
release is published.

## Report a vulnerability privately

Use GitHub's **Security → Advisories → Report a vulnerability** flow when it is
available for this repository. If private vulnerability reporting is not yet
enabled, open a public issue titled `Security contact requested` with no exploit
details, traces, screenshots, or personal information. A maintainer can then
arrange a private channel.

Please include privately:

- the affected commit or version;
- macOS and hardware architecture;
- impact and realistic attack scenario;
- minimal reproduction using synthetic data; and
- any suggested mitigation.

Do not test against systems, accounts, or applications you do not own or have
explicit permission to automate.

## Response expectations

The maintainers aim to acknowledge a report within seven days and provide an
initial assessment within fourteen days. These are best-effort targets, not a
service-level agreement. Please allow a reasonable remediation window before
public disclosure.

## Security boundaries

- A tape is active automation, not a passive document. Review untrusted tapes
  before running them.
- Accessibility permission is broad and granted by macOS to a particular local
  executable. ActionTape cannot narrow that operating-system permission.
- Development app bundles produced by `scripts/package-app.sh` are not signed
  with a Developer ID and are not notarized.
- Tape and trace files may contain UI labels, app identifiers, window metadata,
  and user-provided text. Store and share them as sensitive data.
- macOS, the target application, and the local user account are outside
  ActionTape's trust boundary.

See [docs/security-and-privacy.md](docs/security-and-privacy.md) for the user
threat model and safe-use guidance.
