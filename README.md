# woodsweep

[![Release](https://img.shields.io/github/v/release/woodleighschool/woodsweep?display_name=tag&sort=semver)](https://github.com/woodleighschool/woodsweep/releases/latest)
[![CI](https://github.com/woodleighschool/woodsweep/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/woodleighschool/woodsweep/actions/workflows/ci.yaml)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)
[![License](https://img.shields.io/github/license/woodleighschool/woodsweep)](https://github.com/woodleighschool/woodsweep/blob/main/LICENSE)

Snapshots the current user’s home to a Kopia Repository Server, resets Word, Excel, and PowerPoint user state, then reconciles the home only after the snapshot succeeds.

## 🚀 Usage

Download the macOS app from the [latest release](https://github.com/woodleighschool/woodsweep/releases/latest), extract it, and move `WoodSweep.app` to `/Applications`.

Bootstrap the logged-in user once:

```bash
/Applications/WoodSweep.app/Contents/MacOS/WoodSweep bootstrap \
  --server-url "https://kopia.example:51515" \
  --bootstrap-user "bootstrap@woodsweep" \
  --bootstrap-password "BOOTSTRAP_PASSWORD"
```

Bootstrap creates a machine-specific Kopia user and stores only its generated password in the login Keychain. After that, open the app and confirm the reset.

## ⚙️ Configuration

The [PPPC profile](Config/WoodSweep.mobileconfig) grants Full Disk Access for the snapshot and lets WoodSweep open the macOS restart dialog when cleanup finishes.

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
