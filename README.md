# woodsweep

[![Release](https://img.shields.io/github/v/release/woodleighschool/woodsweep?display_name=tag&sort=semver)](https://github.com/woodleighschool/woodsweep/releases/latest)
[![CI](https://github.com/woodleighschool/woodsweep/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/woodleighschool/woodsweep/actions/workflows/ci.yaml)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)
[![License](https://img.shields.io/github/license/woodleighschool/woodsweep)](https://github.com/woodleighschool/woodsweep/blob/main/LICENSE)

Snapshots the current user’s home to a Kopia Repository Server, resets Word, Excel, and PowerPoint user state, then reconciles the home only after the snapshot succeeds.

## 🚀 Usage

Download the macOS app from the [latest release](https://github.com/woodleighschool/woodsweep/releases/latest), extract it, and move `WoodSweep.app` to `/Applications`.

Bootstrap the Mac as root, including before anyone logs in:

```bash
sudo /Applications/WoodSweep.app/Contents/MacOS/WoodSweep bootstrap \
  --server-url "https://kopia.example:51515" \
  --bootstrap-user "bootstrap@woodsweep" \
  --bootstrap-password "BOOTSTRAP_PASSWORD"
```

Bootstrap generates a device ID and password, stores them with the server URL in the System keychain, then provisions the Kopia account `<device-id>@woodsweep`. It does not depend on the Mac’s hostname or a login session. The bootstrap credential is transient. Re-running bootstrap reuses the stored device ID and password, including after an interrupted run. A working enrollment does not change the server.

Each snapshot reads the current hostname and records its source as `<device-id>@<hostname>:/Users/<username>`. Renaming a Mac keeps the same credential and connection. Existing snapshots retain their original hostname.

The System keychain trusts the app that creates the item through its code signature. Use the signed app for both bootstrap and normal operation, and keep its signing identity consistent across releases. This uses macOS's file-based keychain because enrollment must work outside a login session.

Check enrollment and the repository connection without starting a reset:

```bash
/Applications/WoodSweep.app/Contents/MacOS/WoodSweep status
```

`status` works as root or as a user, reports the server, device account, and current hostname without printing credentials, and exits nonzero on failure. It checks repository access; it does not certify Full Disk Access or reset readiness for a particular home. Setup and status use temporary Kopia state, removed on exit. The app maintains its own repository connection settings inside the logged-in user's home.

An MDM install hook can invoke bootstrap directly as root. No console user is required. Intune's post-install hook reports the app as installed even if bootstrap fails; use `status` to diagnose enrollment and rerun bootstrap to repair it.

After setup, open the app and confirm the reset.

## ⚙️ Configuration

The [PPPC profile](Config/WoodSweep.mobileconfig) grants Full Disk Access for the snapshot and lets the app restart the Mac when the reset finishes.

The app requires a Kopia Repository Server with a system-trusted certificate and default ACLs enabled. Create a bootstrap identity permitted to provision machine accounts:

```bash
kopia server acl enable
kopia server users add bootstrap@woodsweep \
  --user-password "BOOTSTRAP_PASSWORD"
kopia server acl add \
  --user bootstrap@woodsweep \
  --access FULL \
  --target type=user
```

Allow device accounts to keep their own snapshots and source policies across hostname changes:

```bash
for manifest_type in snapshot policy; do
  kopia server acl add \
    --overwrite \
    --user '*@woodsweep' \
    --access FULL \
    --target "type=${manifest_type},username=OWN_USER"
done
```

These rules scope access by device ID rather than the snapshot hostname. Each device can access its own sources under any hostname.

The server control API must use the same bootstrap identity so the app can refresh Kopia’s user cache after provisioning a machine account.

Apply the repository-wide policy used by WoodSweep:

```bash
kopia policy set --global \
  --add-ignore="/Library" \
  --ignore-identical-snapshots=true \
  --ignore-file-errors=true \
  --ignore-dir-errors=true
```

`--ignore-file-errors` and `--ignore-dir-errors` are required because a normal macOS home contains paths the logged-in user cannot read. Repository policy also owns retention, compression, maintenance, and exclusions.

At launch, the effective process user must be the active console user with a validated `/Users/<username>` home. Missing configuration, unsafe paths, unavailable backup, or missing credentials stops before cleanup.

## 🧑‍💻 Development

Open `WoodSweep.xcodeproj` in Xcode, or use the repository tasks:

```bash
mise run fmt-check
mise run lint
mise run test
mise run build
```

A local Kopia server is available for development:

```bash
mise run dev-tls-trust
mise run kopia-server
```

It stores ignored state under `.local/kopia`, stays in the foreground, and does not run the app or exercise reset behaviour.

## 📄 License

Licensed under the [Apache License 2.0](LICENSE).
