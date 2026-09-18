# Upstream basis

- Primary behavior: [TypeSafe Python SDK v0.6.0](https://github.com/typesafe-ai/typesafe-sdk-python/tree/v0.6.0), pinned in `vendor/typesafe-sdk-python`.
- Secondary reference: [TypeSafe JS SDK v0.6.0](https://github.com/typesafe-ai/typesafe-sdk-js/tree/v0.6.0).
- Python reviewed commit: `420ef4ffb612d5a539a1e0f0fe883ff6770340af`.
- JS reviewed commit: `66880ccded6cb642dc1809620c2b108c33730214`.
- Reviewed: 2026-09-18.
- HTTP dependency: `apple/swift-http-api-proposal` 0.2.1, exact version.
- Swift: 6.4.0 via swiftly; SwiftSyntax 604.0.0.

Python's request/response behavior, configuration, retries, errors, and logging are the parity target. Python synchronous wrappers and Python-specific serialization/runtime mechanisms are not Swift APIs. The macro API is a Swift addition over the same dynamic implementation.

## Sync procedure

1. Resolve the newest stable Python release and its exact commit; compare it with the submodule pin.
2. Review `_core`, `_schemas`, constants, changelog, and behavioral tests. Check the JS release for discrepancies and new coverage.
3. Port each user-visible change and its tests. Keep `docs/parity.md` explicit about deliberate deviations.
4. Update the submodule, this file, README, and CHANGELOG together. Preserve upstream license notices.
5. Run Swift Testing, compile Examples, and verify HTTP transport behavior on macOS and Linux.
6. Commit the changes. Mirror the upstream version only after parity gates pass; tag from verified main without a `v` prefix.

## Initial implementation status

Implementation and verification are in progress. No release tag has been created.
