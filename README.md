# woodsweep

Snapshots the current user’s home to a Kopia Repository Server, resets Word, Excel, and PowerPoint user state, then reconciles the home only after the snapshot succeeds.

## 🚀 Usage

Download the signed and notarized ZIP from the [latest release](https://github.com/woodleighschool/woodsweep/releases/latest), move the app to `/Applications`, and deploy [`Config/WoodSweep.mobileconfig`](Config/WoodSweep.mobileconfig).

Bootstrap the logged-in user once:

```bash
/Applications/WoodSweep.app/Contents/MacOS/WoodSweep bootstrap \
  --server-url "https://kopia.example:51515" \
  --bootstrap-user "bootstrap@woodsweep" \
  --bootstrap-password "BOOTSTRAP_PASSWORD"
```

Bootstrap creates a machine-specific Kopia user and stores only its generated password in the login Keychain. After that, open the app and confirm the reset.

## ⚙️ Configuration

The app requires a Kopia Repository Server with a system-trusted certificate and default ACLs enabled:

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

Repository policy owns retention, compression, maintenance, and exclusions. A typical global policy is:

```bash
kopia policy set --global \
  --add-ignore="/Library" \
  --ignore-identical-snapshots=true \
  --ignore-file-errors=true \
  --ignore-dir-errors=true
```

At launch, the effective process user must be the active console user with a validated `/Users/<username>` home. Missing configuration, unsafe paths, unavailable backup, or missing credentials stops before cleanup.

## 🧑‍💻 Development

Open `WoodSweep.xcodeproj` in Xcode, or use the repository tasks:

```bash
mise run lint
mise run test
```

A local Kopia server is available for development:

```bash
mise run dev-tls-trust
mise run kopia-server
```

It stores ignored state under `.local/kopia`, stays in the foreground, and does not run the app or exercise reset behaviour.

## 📄 License

Licensed under the [Apache License 2.0](LICENSE).
