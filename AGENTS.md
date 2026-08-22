# AGENTS.md

Guidance for agents and humans working in this repository. This file is self-contained. Check the repository's source, Mise configuration, Lefthook configuration, Xcode project, and workflows for facts that can vary instead of copying versions or commands from another project.

## Working here

- Read the relevant code, configuration, tests, and sibling implementations before editing. Existing code and reference implementations are evidence; understand the invariant and ownership boundary before choosing a solution.
- Target current supported behaviour. Prefer the simplest design that reduces state and machinery, and bring the affected path into conformance when existing code disagrees with this baseline.
- Preserve unrelated work. Keep changes focused, remove artifacts orphaned by the change, and keep generated outputs with their source change.
- Verify framework and platform APIs from the SDK and deployment target used by the Xcode project.
- Keep secrets, credentials, real identities, production data, Keychain contents, and local environment files out of source, fixtures, logs, and commits.

## Baseline

- Write idiomatic, modern code for the versions and deployment targets pinned by this repository.
- Keep operations idempotent. Re-running bootstrap, backup preparation, cleanup, or reconciliation with identical input shouldn't accumulate side effects.
- Stay DRY and minimal without premature abstraction. Three similar call sites are fine; add a helper, protocol, options type, or reusable view when real callers need the variance it provides.
- Comments explain non-obvious constraints, invariants, and external requirements. Names and structure carry the ordinary narrative.
- Do not add file banners, author or date headers, or comment-based change logs. Git owns provenance and history.
- Write prose from the repository's point of view. Use `we` and `our` for the organisation, and `the app`, `the service`, `the command`, or direct wording for this repository. Omit organisation and product names when context already identifies them; keep names that are identifiers or distinguish an external system.
- Keep tracked documentation durable and present-tense. READMEs use a terse introduction and the relevant established emoji-led sections; omit migration history, temporary setup state, and inventories of absent features.
- Keep one-time local and external-service setup notes out of tracked files. If asked to preserve them locally, leave them untracked without adding ignore or exclude rules.
- Tests protect behaviour and contracts at the lowest useful boundary. Use temporary paths and focused fakes for filesystem, process, Keychain, and Kopia boundaries.

## Repository tooling

- Mise owns command-line tools and repository tasks. Run `mise tasks` and read `.mise/config.toml` before choosing task names or invoking pinned tools directly.
- Lefthook extends the shared organisation configuration. Read `.lefthook.toml` and use `lefthook dump` when merged hook behaviour matters; local hooks contain only repository-specific additions.
- SwiftFormat owns Swift formatting. The Xcode project and shared schemes own targets, build settings, deployment targets, signing inputs, and test selection.
- Use the runner's default Xcode selection. Select another toolchain only when the repository has a verified version requirement.
- Run focused checks while working, then the relevant format, lint, test, build, workflow, signing, packaging, and notarization checks before calling the work complete.

## Swift and macOS

- Use Swift 6 language mode and strict concurrency. Prefer `async`/`await`, task groups, actors, and `AsyncSequence`; isolate UI state to the main actor, keep cross-actor values `Sendable`, propagate cancellation, and avoid detached tasks unless inherited isolation is unsuitable.
- Build the interface with SwiftUI and one clear owner for mutable state. Prefer Observation for new model state, derive view state, and keep user actions in handlers.
- Use AppKit only through narrow, documented bridges when current SwiftUI APIs do not provide the required macOS behaviour. Keep AppKit types and lifecycle concerns at that boundary.
- Model expected states directly. Surface actionable failures at the UI or command boundary and preserve underlying errors for logs and diagnostics.
- Validate every filesystem target before mutation. Resolve and compare canonical paths, constrain operations to the intended home, and define symlink behaviour at the filesystem boundary.
- Treat external processes as cancellable dependencies with explicit arguments, output capture, exit-status handling, and time bounds.
- Interface copy carries useful meaning. Omit manufactured metadata, and give independent facts separate semantic structure instead of joining them with decorative glyphs. Preserve intentional Unicode content rather than replacing punctuation mechanically.
- Keep tests deterministic. Use temporary directories, fake processes, and injected stores; exercise destructive workflows against synthetic homes only.

## Git and completion

- Use focused Conventional Commits; Release Please derives versions from them where configured.
- Commit, push, publish, deploy, contact live systems, mutate a real home, or perform destructive operations only when explicitly requested.
- Report the checks run, behaviour changed, signing or packaging evidence collected, and any verification that couldn't be completed.

## Repository contract

- A successful Kopia snapshot is the gate before Office cleanup and home reconciliation. Stop the workflow at the first failed stage.
- The app runs as the logged-in user without privileged helpers. Credentials live in the login Keychain and file operations remain inside the validated target home.
- Release automation produces the signed and notarized ZIP. Bootstrap, reset, and reconciliation behaviour share the same configuration and safety boundaries.
