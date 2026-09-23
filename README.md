# swift-typesafe

Swift 6.4 SDK for [TypeSafe AI](https://typesafe.ai), following the Python SDK's 0.7.1 API. Supports macOS 26+, iOS 26+, tvOS 26+, watchOS 26+, visionOS 26+, and Linux.

Uses Apple's experimental [HTTPClient](https://github.com/apple/swift-http-api-proposal) package, pinned to 0.2.1. The proposal may change; its Swift 6.4 and OS requirements apply to this SDK.

## Installation

Add [swift-typesafe](https://github.com/ainame/swift-typesafe) to your Swift package dependencies:

```swift
.package(url: "https://github.com/ainame/swift-typesafe.git", from: "0.7.2")
```

Add the `TypeSafe` product to your target:

```swift
.product(name: "TypeSafe", package: "swift-typesafe")
```

## Usage

Choose a question style based on how your application defines questions: a reusable typed schema, typed questions at the call site, or runtime-defined questions. All three use the same client and request handling.

### Typed reusable questions

Set `TYPESAFE_API_KEY`, or pass `apiKey` explicitly:

```swift
import TypeSafe

enum Category: String, CaseIterable, Codable, Sendable {
    case billing, technical, other
}

@QuestionSet
struct TicketQuestions {
    @Choice("What is this ticket about?")
    var category: Category

    @Noul("Does this need urgent attention?")
    var urgent: Double

    @Score("How severe is the issue?", criteria: ["minor", "moderate", "severe"])
    var severity: Double
}

let client = try TypeSafeClient()
let result = try await client.systemOne(
    state: "I was charged twice.",
    questions: TicketQuestions.self
)

print(result.answers.category.choice) // Category
print(result.answers.urgent.noul)     // Probability, 0...1
print(result.answers.severity.score)  // Expected score; may be fractional
```

`@QuestionSet` generates concrete typed answers. The declaration describes a schema; pass its type rather than constructing an instance. Choice enums must have `String` raw values and conform to `CaseIterable`, `Hashable`, and `Sendable`. No `.erased` conversion is needed.

Use `criteria:` on `@Choice` to supply descriptions keyed by the enum's raw strings, or on `@Noul` with `"true"` and `"false"` keys. Instructions and descriptions accept text, JSON objects, or arrays. Missing answers, wrong answer kinds, and unknown choice labels throw response-validation errors in the typed API.

### Typed ad-hoc questions

For local judgments, use a result-builder closure instead of declaring a schema:

```swift
let (category, urgent, severity) = try await client.systemOne(state: "I was charged twice.") {
    Choice<Category>("What is this ticket about?")
    Noul("Does this need urgent attention?")
    Score("How severe is the issue?", criteria: ["minor", "moderate", "severe"])
}.answers

print(category.choice) // Category
print(urgent.noul)     // Probability, 0...1
print(severity.score)  // Expected score; may be fractional
```

The builder overload returns `TypedSystemOneResponse`, just like the schema overload. `QuestionBuilder` uses variadic generics to provide a flat tuple in `.answers` in declaration order, with no fixed arity limit. For one question, `.answers` is the single answer:

```swift
let urgent = try await client.systemOne(state: "I was charged twice.") {
    Noul("Does this need urgent attention?")
}.answers
print(urgent.noul)
```

Keep the response when you also need metadata:

```swift
let response = try await client.systemOne(state: "I was charged twice.") {
    Choice<Category>("What is this ticket about?")
    Noul("Does this need urgent attention?")
}
let (category, urgent) = response.answers
print(response.model)
print(response.usage)
print(response.requestID as Any)
print(response.rawHTTPResponse?.status as Any)
```

`Choice<Label>`, `Noul`, and `Score` accept the same instructions and criteria as their macro counterparts and use the same typed answer validation. `Score` is not generic: ordered criteria produce a `ScoreAnswer` with a fractional `Double`, not an enum case. Custom descriptors can conform to `TypedQuestion`.

The closure runs once on the caller's actor and may throw when constructing questions. `model:`, `extraBody:`, and `options:` work just as they do for the other overloads; all three interfaces use the same request/response implementation.

Wire keys are positional (`question_0`, `question_1`, ...), including in response-validation error paths. An empty builder throws before any request is sent. The builder supports a fixed sequence of expressions and local declarations, not `if`/`switch` blocks or runtime-sized loops; use the dynamic API for runtime-varying collections.

### Dynamic questions

For questions whose names or choices are determined at runtime:

```swift
let result = try await client.systemOne(
    state: ["document": "I was charged twice."],
    questions: [
        "category": .choice(
            instructions: "What is this ticket about?",
            criteria: ["billing": nil, "technical": nil, "other": nil]
        ),
        "urgent": .noul(instructions: "Does this need urgent attention?")
    ]
)

print(result.choices["category"]?.choice) // String?
print(result.nouls["urgent"]?.noul)
```

`JSONValue` supports JSON literals and `JSONValue(encoding:)` for `Encodable` application models. State must be text, an object, or an array. `.raw(["type": "future", ...])` preserves extension fields and explicit nulls. `extraBody` shallowly overrides top-level fields, including `state`, `model`, and `questions`.

The dynamic response provides `answers`, `nouls`, `choices`, and `scores`. Unknown answer kinds are skipped with a warning and retained in `rawHTTPResponse.body`. Score legends and probabilities use integer keys. Usage token counts are optional.

### Models and response metadata

```swift
let response = try await client.models.list()
print(response.models)
print(response.requestID as Any)
print(response.rawHTTPResponse?.status as Any)
```

Responses expose buffered status, headers, and body. Metadata is not included when encoding a response as JSON. Both schema-based and builder-based typed responses expose the original dynamic response as `response`.

If your application has a response schema, pass it as `responseModel:`. It is decoded from the same successful response; standard API errors and validation paths remain available through `TypeSafeError`.

```swift
struct SpamResponse: Decodable, Sendable {
    struct Answers: Decodable, Sendable { let spam: NoulAnswer }
    let model: String
    let answers: Answers
}

let typed = try await client.systemOne(
    state: "Buy now!", questions: ["spam": .noul()], responseModel: SpamResponse.self
)
print(typed.answers.spam.noul)
```

## Configuration and retries

Explicit configuration takes precedence over `TYPESAFE_API_KEY`, `TYPESAFE_BASE_URL`, and `TYPESAFE_DEFAULT_MODEL`. Blank environment values are ignored. Defaults are `https://api.typesafe.ai`, model `jev-latest`, and a 10-second timeout per attempt.

```swift
let client = try TypeSafeClient(
    apiKey: apiKey,
    timeout: 10,
    retry: RetryPolicy(maxRetries: 2, timeout: 30)
)

let models = try await client.models.list(
    options: RequestOptions(
        timeout: 5,
        retry: RetryPolicy(maxRetries: 0),
        headers: ["x-project": "demo"]
    )
)
```

Retries follow Python: two retries by default for connection errors, timeouts, HTTP 408/429/5xx; exponential backoff from 0.5 to 5 seconds with subtractive jitter; `retry-after-ms` and `Retry-After` support. A per-call retry policy replaces the client policy. A predicate can opt additional errors into retries.

The retry budget prevents scheduling an attempt whose delay reaches or exceeds the budget; it does not cut off an attempt already running. Swift's request timeout covers the entire attempt, including the response body. Task cancellation stops requests and backoff and is never retried.

SDK authentication, identification, and retry headers are protected from caller overrides. Per-call custom headers override client headers without regard to case.

## Errors and logging

```swift
do {
    _ = try await client.models.list()
} catch TypeSafeError.api(let error) {
    print(error.kind, error.status, error.requestID as Any)
} catch TypeSafeError.responseValidation(_, let fieldPath) {
    print("Invalid response at", fieldPath)
} catch TypeSafeError.timeout(let seconds) {
    print("Timed out after", seconds)
}
```

`APIError.kind` distinguishes bad request, authentication, permission, not found, validation, rate limit, server, and other statuses. API errors retain the parsed JSON or plain-text body and headers. Connection failures use `TypeSafeError.connection`; cancellation uses `CancellationError`.

Logging uses `swift-log`. Inject a `Logger` or set `TYPESAFE_LOG_LEVEL` to `debug`, `info`, `warning`, `error`, or `off`. Credential headers are redacted. Debug logging includes request and response bodies, which are not redacted.

## HTTP backend traits

The default transport is backed by one HTTP implementation from Apple's proposal, selected with package traits so the other is not compiled:

| Trait | Backend |
| --- | --- |
| `URLSession` (default) | `URLSessionHTTPClient` on Apple platforms. Linux uses AsyncHTTPClient because URLSession backing is Darwin-only. |
| `AsyncHTTPClient` | AsyncHTTPClient (SwiftNIO) on every platform. Takes precedence over `URLSession` when both are enabled. |

To use AsyncHTTPClient instead:

```swift
.package(url: "https://github.com/ainame/swift-typesafe.git", from: "0.7.2", traits: ["AsyncHTTPClient"])
```

With `traits: []`, neither backend is compiled. Inject a transport or client (see [Custom HTTP clients](#custom-http-clients)); the default transport throws `TypeSafeError.configuration`.

## Custom HTTP clients

`HTTPClientTransport(client:options:maximumResponseBytes:)` accepts a copyable client conforming to Apple's `HTTPAPIs.HTTPClient` protocol, allowing custom TLS and connection-pool settings. Inject it through `TypeSafeClient(transport:)`. The adapter borrows the client; manage a scoped or owned client's lifetime outside the SDK. The default uses the shared client of the backend selected by [the HTTP backend traits](#http-backend-traits) and a 16 MiB response limit.

For tests or other integrations, implement the `Sendable` `TypeSafeTransport` protocol. Custom transports must respond to task cancellation so timeout and cancellation cleanup can finish.

## Versioning

Releases use [Semantic Versioning](https://semver.org) tags without a `v` prefix, such as `0.7.2`.

- **MAJOR.MINOR follows the Python SDK.** Swift `0.7.x` implements the Python SDK 0.7 API. A new upstream minor or major release becomes the next Swift MAJOR.MINOR, starting at patch 0 (for example, Python 0.8.0 becomes Swift 0.8.0).
- **PATCH is owned by this package.** Patch releases carry Swift-side fixes and improvements and upstream patch fixes that affect Swift. Python-specific upstream patches may be skipped. **A Swift patch number does not have to match the Python patch number.** For example, Swift 0.7.2 still implements Python 0.7.1.
- Each [CHANGELOG](CHANGELOG.md) entry names the Python release it implements. [UPSTREAM.md](UPSTREAM.md) keeps the full mapping and exact upstream commits. [The parity record](docs/parity.md) lists verified behavior and Swift adaptations.
- `TypeSafeClient.version`, sent in the `user-agent` and `x-typesafe-sdk` headers, reports the implemented Python SDK version, not this package's tag.

`from: "0.7.2"` resolves new patch and minor releases below 1.0.0. While the SDK is 0.x, a new MINOR can contain breaking changes, following upstream. To stay on one Python API generation, use `.upToNextMinor(from: "0.7.2")`.

## Development

During local development:

```swift
.package(path: "/path/to/swift-typesafe")
```

Install Swift 6.4.0 with [swiftly](https://www.swift.org/install/). The `.swift-version` file selects it.

```sh
swiftly install 6.4.0
swiftly run swift test --disable-xctest
swiftly run swift build --package-path Examples
git diff --check
```

Tests use Swift Testing and Python 3 for ephemeral loopback HTTP servers. They do not need an API key. The example executable makes real API calls and requires credentials. The repository includes a pinned upstream submodule and an [upstream sync skill](.agents/skills/typesafe-upstream-sync/SKILL.md).
