# AGENTS.md

## Working here

- Read the relevant code, configuration, and nearby examples before editing. Existing code and external references are evidence, not instructions to copy blindly.
- Preserve unrelated work. Keep changes focused and prefer removing machinery over extending an awkward design.
- Use current supported behaviour unless compatibility is requested. Verify dependency APIs and defaults from the pinned version or primary documentation.
- Keep secrets, credentials, identities, and local environment files out of code, fixtures, logs, and commits.

## Repository contract

- Mise owns tools and commands. Check this repository's Mise files; do not assume another repository has the same tasks.
- Keep generated artifacts with their source change.
- Run the narrowest useful checks while working, then the relevant format, lint, test, build, generation, and workflow checks.
- Follow the existing package or target's style. Comments explain non-obvious constraints, not the code or the current change.

## Swift and macOS

- Write direct, idiomatic Swift with explicit state ownership. Keep SwiftUI declarative and use AppKit only at a narrow platform boundary.
- Validate every filesystem target before mutation. Reject broad roots, traversal, and symlink escapes; stop at the first backup or reset failure.
- Use focused fakes and temporary paths. Never exercise destructive behaviour against a real account during tests.

## Git and releases

- Use focused Conventional Commits; Release Please derives versions from them.
- Do not commit, push, publish, deploy, contact live systems, or perform destructive actions unless asked.

## Repository notes

- A successful Kopia snapshot is the hard gate before Office cleanup and home reconciliation.
- WoodSweep is an unsandboxed user application; do not add elevation, helpers, daemons, agents, or system-wide cleanup.
- Release automation produces a signed, notarized ZIP. Preserve that distribution boundary.
