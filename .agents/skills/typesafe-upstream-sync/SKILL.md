---
name: typesafe-upstream-sync
description: Sync this Swift TypeSafe SDK with a stable typesafe-ai/typesafe-sdk-python release, cross-check the JS SDK, and update parity tests and upstream metadata.
---

# TypeSafe upstream sync

Use `UPSTREAM.md` for the reviewed commit and `docs/parity.md` for the behavioral contract. Python is the primary reference. JS is a secondary source of examples and regression cases; do not silently replace Python semantics with JS defaults.

## GitHub access

Use `gh` from a host-network execution context for GitHub-facing release gates and PR work. In particular, prefer `gh release list` or `gh release view` to identify the newest stable release (excluding drafts and prereleases), and use `gh pr` for existing-PR discovery, creation, labels, and final status. Do not treat a sandbox DNS failure as evidence that no release exists; rerun GitHub access outside the sandbox when authorized.

Use Git directly only when it provides repository content that `gh` does not: fetch the exact verified release tag for the vendor gitlink and inspect source/test diffs. Keep that fetch narrow when possible.

1. Initialize `vendor/typesafe-sdk-python` if needed. Use `gh` to verify the newest stable Python release, then fetch that exact tag and compare its commit with the recorded basis. If unchanged, leave the working tree unchanged.
2. Compare the release changes in `src/typesafe_sdk/_core`, `_schemas`, constants, and tests. Cross-check the matching JS release's `src` and regression tests. Record discrepancies, especially score validation, retries, and response decoding.
3. Port runtime behavior into `Sources/TypeSafe` and keep macro-generated requests backed by that implementation. Add fixtures and behavioral tests for each change; macro diagnostics belong in `Tests/TypeSafeMacrosTests`.
4. Keep the submodule pin, exact reviewed SHAs, parity matrix, README, and CHANGELOG aligned. Mirror the upstream version in `TypeSafeClient.version` only when the corresponding parity is verified. Upstream generated schemas are evidence, not an instruction to copy schema bugs over working SDK behavior.
5. Verify with Swift 6.4 via swiftly: `swiftly run swift test --disable-xctest`, `swiftly run swift build --package-path Examples`, and `git diff --check`. Native HTTP tests use a Python 3 loopback server; they require no credentials. Verify Linux as well as macOS before claiming both platforms tested.
6. Commit each meaningful change. Push, PR, and publication follow the user's requested scope. Release tags have no `v` prefix and must point to the verified main commit; do not tag while parity gaps remain unresolved.

Preserve the Swift-specific contracts in the parity document: async-only execution, task cancellation, injected-client ownership, macro response validation, and HTTPClient dependency constraints. If an upstream change conflicts with these contracts, explain the conflict before changing direction.
