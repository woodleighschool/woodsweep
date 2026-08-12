# WoodSweep

WoodSweep snapshots the current login user's home through a Kopia Repository
Server, resets Word, Excel, and PowerPoint user state, and reconciles that home
only after the snapshot succeeds.

## Repository Server

WoodSweep requires one Kopia Repository Server with a system-trusted TLS
certificate. Enable Kopia's default ACLs, create a shared bootstrap repository
user, and grant it permission to provision users:

```sh
kopia server acl enable
kopia server users add bootstrap@woodsweep \
  --user-password "BOOTSTRAP_PASSWORD"
kopia server acl add \
  --user bootstrap@woodsweep \
  --access FULL \
  --target type=user
```

Start the server control API with that same bootstrap identity and password.
WoodSweep uses it only to refresh Kopia's user cache immediately after adding
or changing a machine user:

```sh
kopia server start \
  --address 0.0.0.0:51515 \
  --tls-cert-file /path/to/server.pem \
  --tls-key-file /path/to/server-key.pem \
  --server-control-username bootstrap@woodsweep \
  --server-control-password "BOOTSTRAP_PASSWORD" \
  --no-ui
```

Set the repository-global snapshot policy once from a directly connected Kopia
client:

```sh
kopia policy set --global \
  --add-ignore="/Library" \
  --ignore-identical-snapshots=true \
  --ignore-file-errors=true \
  --ignore-dir-errors=true
```

Repository policy also owns retention, compression, and maintenance.

## Bootstrap

Run bootstrap as the logged-in user after installing the app:

```sh
/Applications/WoodSweep.app/Contents/MacOS/WoodSweep bootstrap \
  --server-url "https://kopia.example:51515" \
  --bootstrap-user "bootstrap@woodsweep" \
  --bootstrap-password "BOOTSTRAP_PASSWORD"
```

Bootstrap derives the first, lowercased label of the Mac hostname, creates or
updates `woodsweep@<hostname>`, generates a random machine password, connects
the permanent client, and then stores only that generated password in the
logged-in user's login Keychain. Transient bootstrap repository state is
removed and the bootstrap credentials are not persisted.

At launch WoodSweep requires the effective process user to be the active
console user with a validated `/Users/<username>` home. Missing configuration,
missing Keychain credentials, an unsafe home, or an unavailable Kopia server
stops before confirmation or cleanup. A snapshot source is therefore naturally
shaped like:

```text
woodsweep@sc-sac-01:/Users/sacuser
```

## Local Kopia Server

The local server task initializes one persistent filesystem repository under
`.local/kopia`, enables ACLs, provisions `bootstrap@woodsweep`, and serves it
with a locally trusted certificate:

```sh
mise run dev-tls-trust
mise run kopia-server
```

Its fixed development inputs are:

```text
URL:                https://localhost:51515
bootstrap user:     bootstrap@woodsweep
bootstrap password: woodsweep-test-bootstrap
```

The server stays in the foreground and stops with Ctrl-C. Its ignored local
state remains available for the next run. The task only starts Kopia; it does
not launch WoodSweep or exercise reset code.

## Permissions

[`Config/WoodSweep.mobileconfig`](Config/WoodSweep.mobileconfig) grants
WoodSweep Full Disk Access and permission to request the macOS restart dialog
from `loginwindow`.

## Development

Open `WoodSweep.xcodeproj` in Xcode. Command-B builds and Product > Archive
creates an archive.

Repository checks are available through Mise:

```sh
mise run lint
mise run test
```

Release Please and GitHub Actions publish signed and notarized releases.
