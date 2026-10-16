# Upstream basis

- Primary behavior: [TypeSafe Python SDK v0.7.5](https://github.com/typesafe-ai/typesafe-sdk-python/tree/v0.7.5), pinned in `vendor/typesafe-sdk-python`.
- Secondary reference: [TypeSafe JS SDK v0.7.0](https://github.com/typesafe-ai/typesafe-sdk-js/tree/v0.7.0).
- Python reviewed commit: `f36e68549ceca3191e5791e5f99ea1baa1a258b5`.
- JS reviewed commit: `b844cd1aca12855a5d24a2df52a1401c86e7d37a`.
- Reviewed: 2026-10-15.
- HTTP dependency: `apple/swift-http-api-proposal` 0.2.1, exact version.
- Swift: 6.4.0 via swiftly; SwiftSyntax 604.0.0.

## Release mapping

MAJOR.MINOR follows the Python SDK release; PATCH belongs to this package (see [Versioning](README.md#versioning)). Record every release here.

| Swift release | Python SDK | Notes |
| --- | --- | --- |
| 0.7.5 | 0.7.5 | Images, Box, compression, and request validation sync |
| 0.7.4 | 0.7.2 | Swift-only: preserve Choice and Noul criteria order |
| 0.7.3 | 0.7.2 | Upstream packaging and documentation sync; no runtime change |
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

Reviewed Python source: `_core/client/aio`, `_core/endpoints.py`, `_core/config.py`, `_core/questions.py`, `_core/assets.py`, `_core/attached.py`, `_core/compression.py`, `_core/multipart.py`, `_core/content_types.py`, `_core/question_types.py`, `_core/response_types.py`, `_core/transport.py`, `_core/errors.py`, `_core/retry.py`, `_core/logging.py`, `_core/schemas/base.py`, `_schemas/models.py`, public constants, and their behavioral tests.

Reviewed JS source: `src/client.ts`, `assets.ts`, `types.ts`, `questions.ts`, `retry.ts`, `api-promise.ts`, and reliability/release regression tests.

The Swift port implements the API feature set with the deliberate Swift adaptations enumerated in [docs/parity.md](docs/parity.md). Runtime state and payload handling follow Python; macro-based schemas and result-builder answer tuples are additional Swift layers. Wire models are handwritten and reviewed against upstream generated models and runtime corrections (including optional usage fields). Python 0.7.0's Pydantic-specific serialization migration is represented in Swift by Codable; its custom response-model feature is available through `responseModel:`. Python 0.7.1's API key validation and transport error redaction are implemented in the shared Swift client.

Python 0.7.3 adds Choice/Noul validation and Python-specific truststore TLS and httpx pool changes. Python 0.7.4 serializes non-finite numbers as strings. Python 0.7.5 adds images, multipart uploads, scoped attachments, Box responses, zstd compression at the 1 KiB threshold, and bounded debug logging. These request/response behaviors are implemented in the shared Swift path. The official zstd 1.5.7 C library is built through SwiftPM. Multipart uploads retain shared Data segments, and streaming zstd avoids assembling a full uncompressed multipart body. The native adapter sends bounded chunks; custom transports can inspect `bodySegments` or request a flattened `body` view. Swift Collections is pinned to 1.6.0 for compatibility with the HTTP dependency's OS 26 container preview APIs.

Images are immutable Swift values: file-backed values read per new request rather than retaining Python's per-object resolution cache; aliases share resolution within a request and retries reuse prepared bytes. Image bytes and file URLs replace Python buffers/path-like objects; platform image objects must be encoded by the caller rather than using Pillow. Swift content retains the `JSONValue` name with an `.image` input case. Explicit asset aliases are sorted because Swift dictionaries have no insertion order; inline references are collected in body order. Attachment scopes use an async closure with awaited actor cleanup and are visible to concurrent calls on the same client. Python's TLS workaround and 30-second httpx pool setting do not apply to Apple's HTTP client backends; injected clients remain caller-owned.

JS 0.7.0 adds similar asset/Box APIs and optional zstd. Its stricter checks for unreferenced aliases and unknown image references are not adopted: Python sends explicit assets and leaves unknown references as text. Python's one-entry Score rubric, retry budget, and runtime response validation remain authoritative.

## Verification

- Swift 6.4.0 through swiftly on macOS arm64.
- Full results are recorded in `docs/parity.md`.
- Linux verification was attempted in Docker, but the Swift image could not be unpacked after the host exhausted available disk space. No local Linux tests ran.
- Hosted CI for the merged SDK sync passed on macOS 26 (both HTTP backends) and Ubuntu 24.04: [run](https://github.com/ainame/swift-typesafe/actions/runs/38870063001).
- All six live image/Box example scenarios passed against `jev-1.14.0` on 2026-10-16; see `docs/parity.md`. Apple mobile device/simulator tests were not run.
