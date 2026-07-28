# WoodSweep

WoodSweep snapshots a configured local account with Kopia, resets Word, Excel,
and PowerPoint user state, and reconciles the account home only after the
snapshot succeeds.

## Configure

Run the application executable as the target user:

```sh
/Applications/WoodSweep.app/Contents/MacOS/WoodSweep configure \
  --username "TARGET_USERNAME" \
  --endpoint "S3_ENDPOINT" \
  --bucket "S3_BUCKET" \
  --region "S3_REGION_OR_AUTO" \
  --prefix "OPTIONAL_S3_PREFIX" \
  --access-key "S3_ACCESS_KEY_ID" \
  --secret-access-key "S3_SECRET_ACCESS_KEY" \
  --repository-password "KOPIA_REPOSITORY_PASSWORD"
```

`--region` and `--prefix` are optional. Non-secret values use the
`au.edu.vic.woodleigh.WoodSweep` defaults domain, including its managed
UserDefaults overlay. Secrets are stored in the target user's login Keychain
under service `au.edu.vic.woodleigh.WoodSweep.credentials`.

Set the repository-global snapshot policy once from a connected Kopia client:

```sh
kopia policy set --global \
  --add-ignore="/Library" \
  --ignore-identical-snapshots=true \
  --ignore-file-errors=true \
  --ignore-dir-errors=true
```

Repository policy also owns retention, compression, and maintenance.

## Permissions

Install [`Config/WoodSweep.mobileconfig`](Config/WoodSweep.mobileconfig) through
MDM. It grants WoodSweep Full Disk Access and permission to request the macOS
restart dialog from `loginwindow`.

## Development

Open `WoodSweep.xcodeproj` in Xcode. Command-B builds and Product > Archive
creates an archive.

Repository checks are available through Mise:

```sh
mise run lint
mise run test
```

Release Please and GitHub Actions publish signed and notarized releases.
