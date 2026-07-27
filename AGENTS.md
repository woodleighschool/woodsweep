# AGENTS.md

Repository rules for agents working on WoodSweep.

## Scope

- WoodSweep is one macOS 26.6+ SwiftUI application for a controlled exam-account reset.
- The application is unsandboxed and hardened. Do not add a helper, XPC service, daemon, agent, startup item, authentication prompt, or elevation path.
- A successful Kopia snapshot is the hard gate before any destructive cleanup.
- Reset only the approved Word, Excel, PowerPoint, and target-home paths. Do not touch Office licensing, identities, credentials, certificates, Keychain data, managed preferences, system paths, repair state, or other Microsoft applications.
- Follow `docs/superpowers/specs/2026-07-27-woodsweep-reboot-design.md` and the current implementation plan. Keep new shapes direct and specific.

## Repository Map

- Application entry and composition: `WoodSweep/WoodSweepApp.swift` and `WoodSweep/Application/`
- Configuration and credentials: `WoodSweep/Configuration/`
- Process, account, filesystem, and restart boundaries: `WoodSweep/System/`
- Kopia integration: `WoodSweep/Backup/`
- Office discovery and reset policy: `WoodSweep/Office/`
- Ordered reset state machine: `WoodSweep/Reset/`
- SwiftUI presentation: `WoodSweep/UI/`
- Focused Swift Testing suites: `WoodSweepTests/`
- Build, packaging, and verification scripts: `scripts/`
- Version and export settings: `Config/`

Test-only fakes and fixtures stay private in the test file that uses them. Do not create a generic mock-support module.

## Commands

Use Mise tasks as the repository contract.

- Format: `mise run format`
- Check formatting: `mise run fmt-check`
- Test: `mise run test`
- Build and unused-code analysis: `mise run periphery`
- Shell lint: `mise run shell-lint`
- Workflow lint: `mise run workflow-lint`
- All non-test checks: `mise run lint`

Run the narrowest relevant check while iterating, then run every check required by the active task. Report checks that ran, checks skipped with a reason, and unresolved failures.

## Destructive Filesystem Rules

- Resolve and validate the configured target account and home directory before filesystem work.
- Constrain every destructive path to the validated target home. Reject the home root itself, paths outside it, `..` traversal, and symlink escapes.
- Never operate on `/`, `/Users`, the current operator's home by assumption, or an unresolved environment variable, glob, or command substitution.
- Stop at the first backup or reset failure. Do not continue cleanup or invent a recovery action.
- Preserve the explicit Office allowlist. Do not broaden deletion scope for convenience.

## Security and Logging

- Non-secret configuration comes from effective UserDefaults; managed values take precedence.
- Secrets belong only in the target user's login Keychain.
- Never log credentials, passwords, secret-access keys, tokens, Keychain values, raw command environments, or other secret material.

## Hooks and Commits

- Keep Lefthook fast: staged-file formatting and commit-message validation only. Builds, tests, and full analysis belong in explicit Mise tasks and CI.
- Use focused Conventional Commits such as `feat(scope):`, `fix(scope):`, `test(scope):`, `docs(scope):`, `build:`, or `chore:`.
- Do not add AI credits, co-author lines, advertising, or tool footers.
