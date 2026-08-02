# AGENTS.md

Repository guidance for WoodSweep.

## Approach

- Stay within the requested scope and preserve unrelated local changes.
- This is one controlled macOS reset application, not a reusable endpoint platform.
- Simplify and modernize existing code before adding helpers, services, compatibility layers, or speculative recovery machinery.
- Keep new code direct and specific to the approved reset contract.

## Repository Map

- Application composition: `WoodSweep/Application` and `WoodSweep/WoodSweepApp.swift`
- Configuration and credentials: `WoodSweep/Configuration`
- Process, account, filesystem, and restart boundaries: `WoodSweep/System`
- Backup: `WoodSweep/Backup`
- Office discovery and reset policy: `WoodSweep/Office`
- Ordered reset state machine: `WoodSweep/Reset`
- SwiftUI: `WoodSweep/UI`
- Tests: `WoodSweepTests`
- Kopia vendoring: `scripts/fetch-kopia.sh`

Test fakes stay private to the test that uses them. Don't create a generic mock-support module.

## Commands

Use Mise tasks as the repository contract.

- Format: `mise run format`; check: `mise run fmt-check`
- Tests: `mise run test`
- Build and unused-code analysis: `mise run periphery`
- Shell and workflow lint: `mise run shell-lint`, `mise run workflow-lint`
- All non-test checks: `mise run lint`

Run the narrowest useful check while iterating, then the relevant root checks before handing over.

## Reset Contract

- WoodSweep is an unsandboxed, hardened macOS application. Do not add elevation, helpers, daemons, agents, startup items, or authentication prompts.
- A successful Kopia snapshot is the hard gate before destructive cleanup.
- Reset only the approved Word, Excel, PowerPoint, and target-home paths.
- Do not touch Office licensing, identities, credentials, certificates, Keychain data, managed preferences, system paths, repair state, or other Microsoft applications.
- Resolve and validate the target account and home before filesystem work. Reject the home root, paths outside it, traversal, and symlink escapes.
- Never operate on `/`, `/Users`, an assumed home, or a path resolved from an unchecked variable, glob, or command substitution.
- Stop at the first backup or reset failure. Do not continue cleanup or invent recovery behavior.
- Treat package directories inside approved reset locations, including Photos libraries, as ordinary contents.

## Security and Logging

- Managed UserDefaults override ordinary non-secret configuration.
- Secrets belong only in the target user's login Keychain.
- Never log credentials, passwords, access keys, tokens, Keychain values, or raw command environments.
- Shared hooks stay fast and staged-file focused. Builds, tests, and full analysis belong in Mise tasks and CI.

## Commits

- Use focused Conventional Commits.
- Don't push, publish, sign, notarize, or run destructive operations on a real account unless explicitly requested.
- Report checks run, skipped checks, physical-machine proof boundaries, and unresolved failures.
