# Contributing

Small, focused pull requests are easiest to review.

## Set up

```
xcode-select --install     # Command Line Tools are enough; full Xcode is not required
make deps                  # brew bundle: ffmpeg, pandoc, unar, webp, libreoffice
make test                  # swift run MandarinSelfTests
make app                   # builds dist/<Name>.app
```

## House rules

- **No `@State`, no XCTest, no Swift Testing.** They need a macro plugin that
  only ships inside Xcode.app. Local view state is a small `ObservableObject`;
  tests are plain assertions in `Tests/MandarinSelfTests` (see `PROGRESS.md`).
- **Offline only.** No networking code, no telemetry, no entitlements. See
  `SECURITY.md`.
- **No bundled third-party binaries.** Tools are separate programs the user
  installs; list new ones in `THIRD_PARTY.md` and the `Brewfile`.
- **New conversion = one `Converter`** registered in `ConverterRegistry`; the
  wheel asks the registry what's possible and never hard-codes a list.
- **Tests with generated fixtures.** Create the input file in the test (ImageIO,
  PDFKit, ffmpeg `lavfi`) and inspect the output (ImageIO, PDFKit, `ffprobe`).
- Heavy work belongs off the main thread and must honour cancellation.

## Renaming the project

The product name lives in `Sources/Mandarin/AppIdentity.swift`,
`Resources/Info.plist` (`CFBundleName`, `CFBundleDisplayName`,
`CFBundleExecutable`, `CFBundleIdentifier`) and the README title. A self-test
fails if they disagree. Swift target names (`MandarinApp`, …) are internal.
