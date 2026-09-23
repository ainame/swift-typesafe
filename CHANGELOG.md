# Changelog

Versions follow [Semantic Versioning](https://semver.org). MAJOR.MINOR follows the [Python SDK](https://github.com/typesafe-ai/typesafe-sdk-python) release it implements. PATCH is owned by this package, so it can differ from the Python patch number. See [Versioning](README.md#versioning).
Each entry names the Python release it implements. Upstream minor releases can include breaking changes while the SDK is 0.x.

## Unreleased

Implements Python SDK 0.7.1. This will be the first Swift-only patch release, planned as 0.7.2.

### Changed

- Adopt the versioning policy described in [Versioning](README.md#versioning): MAJOR.MINOR follows the Python SDK; PATCH is owned by this package. Existing tags are unchanged; 0.6.0, 0.7.0, and 0.7.1 each match the same Python version.

### Added

- Add `URLSession` (default) and `AsyncHTTPClient` package traits that select the default transport's HTTP backend. Only the selected backend is compiled, rather than both through the proposal's `HTTPClient` product. Linux uses AsyncHTTPClient under the default trait.

## 0.7.1 - 2026-09-23

### Added

- Add a `QuestionBuilder` overload of `systemOne` for typed ad-hoc questions using `Choice<Label>`, `Noul`, and `Score`. It returns `TypedSystemOneResponse`, preserving response metadata and the original dynamic response. Variadic generics produce a flat tuple in `.answers` in declaration order without a fixed arity limit, or a single answer for one question.
- Add the `TypedQuestion` customization protocol, sharing dynamic request handling and existing typed response validation with the macro API.

### Fixed

- Trim and validate API keys during client initialization. Swift 0.7.0 shared the upstream validation gap and could pass malformed keys to the HTTP transport.
- Redact credentials from transport connection error messages. Swift 0.7.0 included raw transport error text, so a transport that echoed a credential could expose it in a `TypeSafeError.connection` message. Python also exposed the original error through its exception chain; Swift did not retain that chain.

### Changed

- Sync the reviewed Python SDK submodule to `v0.7.1` (`0ffd094c72ed9445223060b24ffd7a56aa781fb4`).

## 0.7.0 — 2026-09-20

### Added

- Add `systemOne(..., responseModel:)` for caller-defined `Decodable & Sendable` response models, preserving validation paths and HTTP metadata for an explicit `SystemOneResponse` model. [#1](https://github.com/ainame/swift-typesafe/pull/1)

### Changed

- Sync the reviewed Python SDK submodule to `v0.7.0` (`2ce5c65f13646cab6e6f782328194c9d85f3300a`) and document the Pydantic-to-Codable adaptation. [#1](https://github.com/ainame/swift-typesafe/pull/1)
- Update the repository-local upstream-sync skill to use host-network `gh` for GitHub release and PR operations. [#1](https://github.com/ainame/swift-typesafe/pull/1)

## 0.6.0 — 2026-09-18

Initial Swift port of TypeSafe AI's Python SDK 0.6.0, with the JS SDK reviewed as a secondary reference.

- Add async System One inference and model listing, Noul/Choice/Score questions, response validation, usage metadata, and raw HTTP response access.
- Add `@QuestionSet`, `@Choice`, `@Noul`, and `@Score` macros that generate concrete typed answers, including enum-valued choices.
- Add dynamic JSON questions, model and request overrides, retries and budgets, cancellation, structured API errors, and credential-redacted logging.
- Use Apple's HTTPClient proposal 0.2.1 with Swift 6.4, Apple OS 26+ deployment targets, and Linux support.
- Add fixture and native HTTP tests, an external example package, CI configuration, pinned upstream metadata, and a repository-local sync skill.

See [the parity record](docs/parity.md) for Swift-specific adaptations and verification boundaries. This repository's initial release has no preceding release or merged PR history.
