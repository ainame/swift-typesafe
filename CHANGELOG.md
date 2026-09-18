# Changelog

## 0.6.0 — 2026-09-18

Initial Swift port of TypeSafe AI's Python SDK 0.6.0, with the JS SDK reviewed as a secondary reference.

- Add async System One inference and model listing, Noul/Choice/Score questions, response validation, usage metadata, and raw HTTP response access.
- Add `@QuestionSet`, `@Choice`, `@Noul`, and `@Score` macros that generate concrete typed answers, including enum-valued choices.
- Add dynamic JSON questions, model and request overrides, retries and budgets, cancellation, structured API errors, and credential-redacted logging.
- Use Apple's HTTPClient proposal 0.2.1 with Swift 6.4, Apple OS 26+ deployment targets, and Linux support.
- Add fixture and native HTTP tests, an external example package, CI configuration, pinned upstream metadata, and a repository-local sync skill.

See [the parity record](docs/parity.md) for Swift-specific adaptations and verification boundaries. This repository's initial release has no preceding release or merged PR history.
