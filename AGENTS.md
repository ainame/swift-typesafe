# Contributor instructions

- Make a git commit for each meaningful change.
- Version tags must not have a `v` prefix.
- Never use `swift-actions/setup-swift@v2` in GitHub Actions.
- Use Swift 6.4 via swiftly (`swiftly run swift test --disable-xctest`).
- Python v0.7.0 is the primary behavioral reference; consult `UPSTREAM.md` and `docs/parity.md` before changing semantics.
- Keep macro and dynamic APIs backed by the same request/response implementation.
- Run `swiftly run swift test --disable-xctest`, build `Examples`, and run `git diff --check` before committing behavior changes.
