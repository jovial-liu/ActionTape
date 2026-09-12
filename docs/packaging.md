# Local app packaging and verification

ActionTape is an early source preview. These scripts build a development app
from local source; they do not publish it, add a Developer ID signature,
notarize it, or produce a universal binary.

## Build requirements

Use macOS 14 or later with Xcode 16 or a compatible Swift 6 toolchain already
installed. Yams 6.2.2 and its libyaml sources are included in `Vendor/Yams`;
there are no remote SwiftPM dependencies to fetch. Obtaining the repository or
installing the toolchain can still require a network connection.

```bash
swift build
swift test
bash ./scripts/check-offline-build.sh
./scripts/package-app.sh
bash ./scripts/package-practice-app.sh
```

The offline check uses new temporary SwiftPM build/cache/configuration
directories. `sandbox-exec` denies network access to each build, test, and
example-validation process. SwiftPM's nested manifest sandbox is disabled only
inside this outer network-denying sandbox. No target application is controlled.
The temporary outputs are removed when the check exits.

The GitHub Actions configuration is set up to run the same check on a macOS
runner. Hosted results must be verified for the relevant commit; a workflow
file alone does not establish a passing run. Checkout and runner provisioning
need the network. The local check establishes that an existing source checkout
builds and tests without dependency downloads.

## Bundle layout

```text
ActionTape.app/
├── ActionTape_ActionTapeStudio.bundle -> Contents/Resources/ActionTape_ActionTapeStudio.bundle
└── Contents/
    ├── Info.plist
    ├── MacOS/ActionTape
    └── Resources/
        ├── ActionTape.icns
        ├── ActionTape_ActionTapeStudio.bundle/
        │   └── AppIcon.png
        └── Licenses/
            ├── ActionTape-LICENSE.txt
            ├── Yams-LICENSE.txt
            └── ThirdParty-NOTICE.md
```

SwiftPM's generated `Bundle.module` first looks under `Bundle.main.bundleURL`,
which is the app root when packaged. It also embeds an absolute `.build` path
as a fallback. Copying only into `Contents/Resources` can appear to work on the
build Mac and fail after relocation. The app-root relative symlink deliberately
satisfies the first lookup and travels with the app.

`package-app.sh` creates the standard icon sizes with `sips`, converts them to
ICNS with `iconutil`, includes license notices, and runs
`swift scripts/verify-app.swift /path/to/ActionTape.app`. Verification loads the
bundle-local PNG and ICNS, checks metadata, and checks that the executable and
license files exist. It does not launch Studio or assert that macOS will trust
the bundle.

Assembly is staged on the output volume. If an output `ActionTape.app` already
exists, the script preserves it inside a uniquely named `ActionTape-previous.*`
directory before moving the verified app into place. Old backups can be removed
manually once no longer needed.

The default Studio output is `.build/artifacts/ActionTape.app`; Practice uses
`dist/ActionTape Practice.app`. The underlying SwiftPM products are
`ActionTapeStudio`, `ActionTapePractice`, and `actiontape`. Studio's distinct
product name avoids overwriting the CLI on a case-insensitive filesystem.

To change metadata or location:

```bash
ACTIONTAPE_CONFIGURATION=release ACTIONTAPE_VERSION=0.1.0 ACTIONTAPE_BUILD_NUMBER=1 \
  ./scripts/package-app.sh /path/to/output
```

`ACTIONTAPE_CONFIGURATION` accepts `debug` or `release`; the version is numeric
`x.y.z`. The bundle contains a binary for the build Mac's architecture.
Reproducible layout does not imply bit-for-bit reproducible binaries across
toolchain versions.

Both packagers also accept `ACTIONTAPE_SCRATCH_PATH` to keep concurrent builds
in separate directories. For example:

```bash
ACTIONTAPE_CONFIGURATION=debug ACTIONTAPE_SCRATCH_PATH=work/practice-build \
  bash scripts/package-practice-app.sh work/practice-output
```

Practice has no runtime dependency on Yams and includes the ActionTape license.
The Studio bundle includes all third-party notices it uses. Both pass the same
bundle metadata, executable, and icon verifier.

## Manual launch and permissions check

Before claiming a runnable build has been verified, copy the app outside the
checkout while preserving symlinks (Finder or `ditto`), temporarily make the
build-tree resource bundle unavailable, and open the copied app. Check that
Studio and its icon load. Restore the resource directory afterward. This
separates a real relocated-app launch from the headless packaging checks.

Then, in an interactive test account, inspect the permission-denied experience
and grant Accessibility access only to that exact build before a synthetic
replay. Record the tested macOS, architecture, and target-app versions. This
repository's automated checks do not establish cross-application compatibility.

Do not disable Gatekeeper globally. A local development bundle is not a
Developer ID-signed or notarized release; signing and distribution remain
separate items in [launch-checklist.md](launch-checklist.md).
