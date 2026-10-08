# Contributing

Thank you for your help. Read this page before you send a change.

## The license on your change

ASCKitEngine is available under the PolyForm Noncommercial License 1.0.0. The
ASCKit app is a paid product, and it uses this engine. So a change that you send
needs a wider license than PolyForm Noncommercial.

When you send a pull request, you agree to these terms for the change:

- You wrote the change, or you have the right to send it under these terms.
- You keep the copyright on your change.
- You give Alecs Popa a perpetual, worldwide, non-exclusive, royalty-free and
  irrevocable license to use, copy, change, publish, distribute and sublicense
  your change, for any purpose. Commercial purposes are included.
- You give the same license for any patent claim that you can license and that
  your change uses.
- Everybody else gets your change under the PolyForm Noncommercial License
  1.0.0, the same as the rest of the code.

Write this line in the description of the pull request:

```
I agree to the terms in CONTRIBUTING.md.
```

If you do not agree, do not send the change. Open an issue that tells the
problem instead.

## Before you send a change

- Run `swift test`. All tests must pass.
- Run `swiftformat --lint .`. SwiftLint runs on every build.
- Every sentence that a person reads in the app is a string catalog entry. A
  sentence in this package names its own bundle:
  `LocalizedStringResource("…", bundle: .here)`.
- The command line tool stays in English.
- A test never reaches Apple. Use `StubTransport` from `ASCKitTestSupport`.
