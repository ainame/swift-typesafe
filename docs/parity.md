# Python 0.6.0 parity

The primary reference is `vendor/typesafe-sdk-python` at `420ef4ffb612d5a539a1e0f0fe883ff6770340af`. JS 0.6.0 is a secondary reference, not an interchangeable behavioral specification.

## Coverage

| Upstream feature | Swift implementation | Verification |
| --- | --- | --- |
| POST `/v1/systemone`, GET `/v1/models` | `TypeSafeClient.systemOne`, `models.list` / `listModels` | `CoreTests`, `HTTPClientTests` |
| Noul, Choice, ordered Score rubrics | `Question`, `Answer`, typed payloads | `CoreTests`, `ConfigurationTests`, `MacroAPITests` |
| Text, objects, arrays; rich descriptions; explicit null; raw extension questions | `JSONValue`, `.raw`, optional descriptions | `ConfigurationTests`, `CoreTests` |
| At least one question and score criterion | Preflight validation; one-entry score rubrics accepted | `ConfigurationTests`, `CoreTests` |
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
| Typed question schema (Swift addition) | `@QuestionSet`, `@Choice`, `@Noul`, `@Score` | Macro expansion/diagnostic tests, runtime typed decoding, external Examples package |

The native adapter tests exercise Apple's default URLSession-backed client on macOS and its AsyncHTTPClient-backed implementation on Linux. They include chunked POST requests, model listing, actual retry headers, timeout before headers and during response bodies, cancellation, and the response size limit.

## Deliberate Swift adaptations

- The client is async-only. Swift task cancellation replaces Python task cancellation and JS abort signals. Synchronous wrappers, Python pickling, and cached-object identity are language/runtime details rather than ported APIs.
- `QuestionSet` creates a concrete answer struct. Missing answers, incorrect kinds, or choice labels outside the declared enum are errors. The dynamic API retains Python's lenient unknown-answer behavior.
- Swift's timeout is a deadline for the whole HTTP attempt, including body consumption. Python/httpx has separate connect/read/write/pool inactivity timeouts and permits disabling them. Those httpx-specific options are not exposed by Apple's default client. Inject a configured HTTPClient for available backend-specific controls; SDK request deadlines remain positive finite values.
- The default transport uses `DefaultHTTPClient.shared`. Injected HTTP clients remain caller-owned and are not closed by the SDK. Use the HTTP implementation's scoped lifetime or shutdown API outside the SDK. There is no redundant SDK `close` method for borrowed resources.
- A Swift retry predicate replaces Python's exception-class set and predicate. It receives SDK errors; transport failures are represented as connection errors. Cancellation always propagates, even if the predicate would retry other errors.
- Error categories are enum cases and `APIError.kind`, rather than an exception subclass hierarchy. Missing response metadata is optional instead of throwing on property access.
- Request state is validated as text/object/array. Unknown question tags and raw fields pass through to the server. Normal Swift numeric values are Int64/Double rather than Python arbitrary-precision integers.
- Response collection defaults to 16 MiB and is configurable. This bounds memory use; upstream Python does not impose that SDK limit.
- Structured timeout cleanup waits for child operations to finish. Custom transports must cooperate with cancellation.
- Debug bodies are intentionally not redacted, matching upstream. Header credentials are redacted. Logger configuration uses swift-log conventions.

## JS discrepancies retained intentionally

- Python accepts a one-entry score rubric; JS requires at least two.
- Python uses a default 30-second retry scheduling budget; JS has no total retry budget and caps server delay acceptance.
- Python validates response bodies and supports optional usage token counts. JS interfaces alone do not provide equivalent runtime validation.
- Python's explicit extra-body merge remains available. JS Promise wrappers and browser opt-in checks are specific to that runtime.

## Verification boundaries

All automated tests use fixtures or loopback HTTP servers. They establish SDK behavior without spending TypeSafe credits. The example compiles but is not executed against the production API without credentials. Hosted CI and Apple mobile simulator/device runs are distinct from local macOS and Linux verification; do not describe them as completed unless their results have been checked.

## Initial verification record

- Swift 6.4.0 selected through swiftly on both platforms.
- macOS 27, arm64: 41 runtime/API tests and 4 macro expansion/diagnostic tests passed, including their parameterized cases.
- Ubuntu 24.04, arm64: the same 45 tests passed in an isolated container. Source was mounted read-only and copied into a separate build directory.
- External example package compiled successfully on both macOS and Linux.
- Production API calls, hosted GitHub Actions runs, and Apple mobile simulator/device testing were not performed for this local initial release.
