# Python 0.7.5 parity

The primary reference is `vendor/typesafe-sdk-python` at `f36e68549ceca3191e5791e5f99ea1baa1a258b5` (v0.7.5). Reviewed changes since 0.7.2 include stricter Choice/Noul validation, non-finite number strings, image assets and multipart bodies, scoped attachments, Box questions/answers, zstd compression, and bounded debug body logging. JS 0.7.0 at `b844cd1aca12855a5d24a2df52a1401c86e7d37a` is a secondary reference.

## Coverage

| Upstream feature | Swift implementation | Verification |
| --- | --- | --- |
| POST `/v1/systemone`, GET `/v1/models` | `TypeSafeClient.systemOne`, `models.list` / `listModels` | `CoreTests`, `HTTPClientTests` |
| Caller-defined response model | Generic `systemOne(..., responseModel:)` with `Decodable & Sendable` response type | `CoreTests` |
| Noul, Choice, ordered Score rubrics | `Question`, `Answer`, typed payloads | `CoreTests`, `ConfigurationTests`, `MacroAPITests` |
| Images from bytes/files/base64, inline and named references, scoped attachments | `Image`, direct `Image` state, `JSONValue.image`, `assets:`, `withAttachedAssets` | `Upstream075Tests`, `ImageConcurrencyTests`, native multipart HTTP test |
| Box questions and nullable-confidence answers | Dynamic `.box`, typed `Box`, `@Box`, `.boxes` | `Upstream075Tests`, macro expansion/diagnostic tests |
| zstd requests at 1024 bytes, opt-out, stable retry bytes | `RequestCompression`, official zstd 1.5.7 | Threshold, decompression, JSON/multipart, and retry tests |
| Non-finite number strings; bounded debug bodies | `JSONValue` encoding, 4096-byte wire log limit | `Upstream075Tests`, `LoggingTests` |
| Text, objects, arrays; rich descriptions; explicit null; raw extension questions | `JSONValue`, `.raw`, optional descriptions | `ConfigurationTests`, `CoreTests` |
| At least one question, Choice/Score criterion, described Noul | Preflight validation; one-entry score rubrics accepted | `ConfigurationTests`, `CoreTests` |
| Model override and shallow extra-body override | Per-call model and `extraBody`, including collisions | `ConfigurationTests`, `CoreTests` |
| Explicit options > trimmed environment > defaults | Constructor plus injectable environment | `ConfigurationTests` |
| Case-insensitive header merging and protected SDK headers | Prepared request and attempt headers | `RetryTests`, `CoreTests`, native HTTP round trip |
| Response validation with field paths and request context | `TypeSafeError.responseValidation` | `CoreTests`, `ErrorTests` |
| Optional token usage, integer score maps, unknown fields | Codable models and score-map validation | `CoreTests`, `ErrorTests` |
| Unknown answer types skipped with warning; original payload available | Dynamic decoding, `rawHTTPResponse`, swift-log | `CoreTests`, `LoggingTests` |
| Response request ID, raw HTTP data, metadata excluded from serialization | Value-type responses | `CoreTests`, `HTTPClientTests` |
| HTTP status error categories and message extraction | `APIError.kind`, JSON/plain text body and headers | `ErrorTests` |
| Two retries for connection/timeout/408/429/5xx | `RetryPolicy` | `RetryTests` |
| Exponential backoff, subtractive jitter, server delays, HTTP dates | `RetryPolicy.delay` and `retryAfter` | `RetryTests`, including overflow cases |
| Retry scheduling budget; per-call policy replacement | Per-call execution state | `RetryTests` |
| Custom retry predicate / exception matching | Sendable predicate over Swift errors | `RetryTests` |
| Concurrent calls and cancellation | Immutable client, per-call state, structured tasks | `RetryTests`, native cancellation/body-timeout tests |
| Custom transport/client and connection settings | `TypeSafeTransport`, `HTTPClientTransport(client:options:)` | Mock transport tests and native adapter tests |
| Log levels and credential header redaction | Injected swift-log logger and environment level | `LoggingTests` |
| Trimmed, printable ASCII API keys; credential redaction in connection errors | Client initialization and transport error mapping | `ConfigurationTests`, `LoggingTests` |
| Typed question schema (Swift addition) | `@QuestionSet`, `@Choice`, `@Noul`, `@Score` | Macro expansion/diagnostic tests, runtime typed decoding, external Examples package |
| Typed ad-hoc questions (Swift addition) | `QuestionBuilder`, `Choice<Label>`, `Noul`, `Score`, flat answer tuples | `QuestionBuilderTests`, external Examples package |

The native adapter tests exercise the URLSession-backed client on macOS and the AsyncHTTPClient-backed client on Linux under the default `URLSession` trait. The `AsyncHTTPClient` trait selects AsyncHTTPClient on every platform. They include chunked POST requests, model listing, actual retry headers, timeout before headers and during response bodies, cancellation, and the response size limit.

## Criteria ordering

Python dictionaries preserve insertion order. Swift Choice and Noul `criteria:` literals preserve their written order by default across dynamic, macro, and builder APIs, including custom response models. Omitted enum-backed choice criteria follow `allCases`. Supplied criteria retain their existing subset and their insertion order. Regression tests inspect request bytes because decoding into a dictionary discards order.

For runtime ordered entries, pass `Criteria` through the same `criteria:` argument. Repeated keys retain their first position and final description. Existing dictionary variables remain accepted: dynamic Choice and Noul sort keys; enum-backed choices follow `allCases` with unknown keys sorted afterward. Swift dictionaries have already lost insertion order, so these compatibility overloads provide deterministic ordering rather than the caller's original insertion order.

Raw JSON and `extraBody` objects have no key-order guarantee. Direct Foundation Codable encoding does not guarantee object-key order; the ordering contract applies to `TypeSafeClient` requests.

## Deliberate Swift adaptations

- Content retains the `JSONValue` name and gains `.image(Image)` and `.image(Data)`. `Image` can be passed directly as `state` across every question API, whether constructed from bytes, a file URL, or base64. `Image` is an immutable Sendable value with a private byte/file source; copies preserve its reference identifier and share Data storage through copy-on-write. Unlike Python's per-object resolution cache, a file-backed value reads the current file contents for each new request. Repeated aliases resolve the image once within that request, and HTTP retries reuse the prepared body without rereading files. To reuse fixed bytes across requests, load the file explicitly and pass `Image(data:)`. Image loading uses a caller-awaited `@concurrent` function with cancellation checks before and after resolution, without locks, queues, image actors, or spawned tasks. The Foundation file read is synchronous on the cooperative pool and cannot be interrupted midway; `@concurrent` keeps it off the caller's actor. Python Pillow/buffer conversions are language-specific; encode platform images to `Data` before constructing an `Image`.
- Explicit asset aliases use sorted order because Swift dictionaries do not retain insertion order. Multiple aliases for an image upload one part per alias; inline image values use the last alias in that order. Image values are discovered from the effective request fields after extra-body overrides; Foundation encoding receives an immutable alias map. Reference discovery scans encoded JSON in order, including instructions, criteria, and extra-body values. An `extraBody["assets"]` override skips automatic resolution/upload. Unknown references stay plain text, matching Python.
- `withAttachedAssets` is an async scoped closure with cleanup on success, failure, and cancellation. An actor registry shares attachments between copies of the same client and its concurrent calls; overlapping scopes retain shared images until the last scope ends. Cleanup is awaited before a scope returns or throws, preserving caller isolation and non-Sendable return values.
- zstd is always available through the source-built official C dependency, so compression defaults to `.zstd`. `.disabled` opts out. JSON and multipart bodies below 1024 bytes remain uncompressed; larger bodies are compressed once before retrying. Multipart bodies retain immutable Data segments and stream them through zstd without first assembling a full uncompressed body. A noncopyable C context owns cleanup; Swift Collections `RigidArray`/`OutputSpan` provides reusable uninitialized output scratch storage compatible with OS 26. The native adapter sends at most 64 KiB per writer call, avoiding the dependency's full-body Data-to-UniqueArray conversion. Custom transports may use `bodySegments`; reading `body` explicitly flattens a segmented body. Backend/socket buffers still copy bytes; this is not an end-to-end zero-copy guarantee. Debug bodies remain uncompressed and truncate at 4096 bytes.
- Python's truststore TLS workaround and httpx 30-second keepalive setting are backend-specific. Swift continues using the configured Apple HTTP proposal backend and caller-owned injected clients rather than configuring Python-style pools.
- The client is async-only. Swift task cancellation replaces Python task cancellation and JS abort signals. Synchronous wrappers, Python pickling, and cached-object identity are language/runtime details rather than ported APIs.
- Python 0.7.0 replaces `msgspec` with Pydantic. Swift continues to use Foundation Codable, which already provides its equivalent wire serialization and typed response decoding. Python's `response_model` accepts a Pydantic type; Swift's `responseModel:` accepts a `Decodable & Sendable` type. Custom Swift models do not receive SDK-only raw-response metadata, matching the distinction between custom and standard upstream responses.
- `QuestionSet` creates a concrete answer struct. Missing answers, incorrect kinds, or choice labels outside the declared enum are errors. The dynamic API retains Python's lenient unknown-answer behavior.
- The ad-hoc result builder returns `TypedSystemOneResponse`, preserving model, usage, request ID, raw HTTP metadata, and the original dynamic response just like `QuestionSet`. Its `.answers` contains a flat tuple of typed answers (or the answer itself for one question), using the same dynamic request path and typed response accessors as `QuestionSet`. Its wire keys are positional (`question_0`, `question_1`, ...). It does not support conditional question insertion/runtime-sized loops. Empty builders and empty score rubrics fail the existing preflight validation. Scores remain fractional `Double` values with ordered criteria.
- Swift's timeout is a deadline for the whole HTTP attempt, including body consumption. Python/httpx has separate connect/read/write/pool inactivity timeouts and permits disabling them. Those httpx-specific options are not exposed by Apple's default client. Inject a configured HTTPClient for available backend-specific controls; SDK request deadlines remain positive finite values.
- The default transport uses the shared client of the backend selected by the `URLSession` (default) or `AsyncHTTPClient` package trait, instead of the proposal's `DefaultHTTPClient`, so only one HTTP stack is compiled. Injected HTTP clients remain caller-owned and are not closed by the SDK. Use the HTTP implementation's scoped lifetime or shutdown API outside the SDK. There is no redundant SDK `close` method for borrowed resources.
- A Swift retry predicate replaces Python's exception-class set and predicate. It receives SDK errors; transport failures are represented as connection errors. Cancellation always propagates, even if the predicate would retry other errors.
- Error categories are enum cases and `APIError.kind`, rather than an exception subclass hierarchy. Missing response metadata is optional instead of throwing on property access.
- Request state is validated as text/object/array. Unknown question tags and raw fields pass through to the server. Normal Swift numeric values are Int64/Double rather than Python arbitrary-precision integers.
- Response collection defaults to 16 MiB and is configurable. This bounds memory use; upstream Python does not impose that SDK limit.
- Structured timeout cleanup waits for child operations to finish. Custom transports must cooperate with cancellation.
- Debug bodies are intentionally not redacted, matching upstream. Header credentials are redacted. Logger configuration uses swift-log conventions.

## JS discrepancies retained intentionally

- Python accepts a one-entry score rubric; JS requires at least two.
- JS rejects unused explicit asset aliases and unknown image references; Python sends explicit assets even when unused and treats unknown references as text. Swift follows Python.
- Python uses a default 30-second retry scheduling budget; JS has no total retry budget and caps server delay acceptance.
- Python validates response bodies and supports optional usage token counts. JS interfaces alone do not provide equivalent runtime validation.
- Python's explicit extra-body merge remains available. JS Promise wrappers and browser opt-in checks are specific to that runtime.

## Verification boundaries

All automated tests use fixtures or loopback HTTP servers. They establish SDK behavior without spending TypeSafe credits. The example compiles but is not executed against the production API without credentials. Hosted CI and Apple mobile simulator/device runs are distinct from local macOS and Linux verification; do not describe them as completed unless their results have been checked.

## Verification record

- Swift 6.4.0 selected through swiftly on macOS arm64.
- 98 runtime/API tests and 6 macro expansion/diagnostic tests passed under both the default URLSession backend and the AsyncHTTPClient trait, including parameterized cases and native multipart image round trips.
- The default backend suite also passed with `DISPATCH_COOPERATIVE_POOL_STRICT=1`.
- The external Examples package compiled successfully, including direct Image state, Box macro, and scoped attachment calls.
- `git diff --check` passed.
- Local Linux verification was attempted in Docker, but the Swift image could not be unpacked after the host exhausted disk space; no local Linux tests ran. Hosted CI results are tracked separately on [PR #10](https://github.com/ainame/swift-typesafe/pull/10). Production API calls and Apple mobile simulator/device testing were not performed.

## Image request memory measurement

A release-mode macOS arm64 harness loaded one 16 MiB pseudorandom image, retained its `Image` through the call, and sent a Box question using a mock transport that returned a fixture without flattening or retaining the request. Each variant ran in a fresh process three times; the table reports median maximum resident set size from `/usr/bin/time -l`. The measured commits were `24796fc` (baseline) and `7e521d0` (segmented), using the same harness and Swift 6.4 with Swift Collections 1.6.0. No API calls were made.

| Request preparation | Baseline RSS | Segmented RSS |
| --- | --- | --- |
| Compression disabled | 39.3 MiB | 23.4 MiB |
| zstd enabled | 56.3 MiB | 42.9 MiB |

These figures measure request preparation, not full HTTP transfer or production concurrency. The storage-sharing regression verifies that a large image segment points to the original Data allocation. Native HTTP tests verify multi-chunk uploads and retries with both macOS backends; backend and socket buffering still perform copies.
