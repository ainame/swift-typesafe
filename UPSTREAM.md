# Upstream basis

- Primary behavior: [TypeSafe Python SDK v0.7.1](https://github.com/typesafe-ai/typesafe-sdk-python/tree/v0.7.1), pinned in `vendor/typesafe-sdk-python`.
- Secondary reference: [TypeSafe JS SDK v0.6.0](https://github.com/typesafe-ai/typesafe-sdk-js/tree/v0.6.0).
- Python reviewed commit: `0ffd094c72ed9445223060b24ffd7a56aa781fb4`.
- JS reviewed commit: `66880ccded6cb642dc1809620c2b108c33730214`.
- Reviewed: 2026-09-23.
- HTTP dependency: `apple/swift-http-api-proposal` 0.2.1, exact version.
- Swift: 6.4.0 via swiftly; SwiftSyntax 604.0.0.

## Release mapping

MAJOR.MINOR follows the Python SDK release; PATCH belongs to this package (see [Versioning](README.md#versioning)). Record every release here.

| Swift release | Python SDK | Notes |
| --- | --- | --- |
| 0.7.2 | 0.7.1 | Swift-only: HTTP backend package traits and package-owned patch numbering |
| 0.7.1 | 0.7.1 | Upstream sync |
| 0.7.0 | 0.7.0 | Upstream sync |
| 0.6.0 | 0.6.0 | Initial port |

Python's request/response behavior, configuration, retries, errors, and logging are the parity target. Python synchronous wrappers and Python-specific serialization/runtime mechanisms are not Swift APIs. The macro and ad-hoc result-builder APIs are Swift additions over the same dynamic implementation.

## Sync procedure

1. Resolve the newest stable Python release and its exact commit; compare it with the submodule pin.
2. Review `_core`, `_schemas`, constants, changelog, and behavioral tests. Check the JS release for discrepancies and new coverage.
3. Port each user-visible change and its tests. Keep `docs/parity.md` explicit about deliberate deviations.
4. Update the submodule, this file (including the release mapping), README, and CHANGELOG together. Preserve upstream license notices.
5. Run Swift Testing, compile Examples, and verify HTTP transport behavior on macOS and Linux.
6. Commit the changes. Only after parity gates pass, set `TypeSafeClient.version` to the upstream version and choose the Swift tag. An upstream minor or major release uses its MAJOR.MINOR with patch 0. An upstream patch release uses the next free Swift patch in the current line. Skip upstream patches that only fix Python-specific behavior. Tag from verified main without a `v` prefix.

## Reviewed implementation

Reviewed Python source: `_core/client/aio`, `_core/endpoints.py`, `_core/config.py`, `_core/questions.py`, `_core/question_types.py`, `_core/response_types.py`, `_core/transport.py`, `_core/errors.py`, `_core/retry.py`, `_core/logging.py`, `_core/schemas/base.py`, `_schemas/models.py`, public constants, and their behavioral tests.

Reviewed JS source: `src/client.ts`, `types.ts`, `questions.ts`, `retry.ts`, `api-promise.ts`, and reliability/release regression tests.

The Swift port implements the API feature set with the deliberate Swift adaptations enumerated in [docs/parity.md](docs/parity.md). Runtime state and payload handling follow Python; macro-based schemas and result-builder answer tuples are additional Swift layers. Wire models are handwritten and reviewed against upstream generated models and runtime corrections (including optional usage fields). Python 0.7.0's Pydantic-specific serialization migration is represented in Swift by Codable; its custom response-model feature is available through `responseModel:`. Python 0.7.1's API key validation and transport error redaction are implemented in the shared Swift client.

## Verification

- Swift 6.4.0 through swiftly.
- macOS arm64: 48 runtime/API tests and 4 macro tests passed for this v0.7.1 sync, including native HTTPClient round trips, key validation, credential redaction, retries, timeouts, cancellation, and custom response models.
- The external example package compiled successfully on macOS arm64.
- Linux, live TypeSafe API calls, hosted CI, and Apple mobile device/simulator tests were not run for this sync.
