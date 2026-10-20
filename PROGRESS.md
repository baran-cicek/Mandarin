# Mandarin — Progress

macOS menu-bar file converter with a radial drop wheel (drag a file,
hold a modifier key, drop it on a segment). Fully offline. Not sandboxed,
not for the App Store.

## Environment note (important — read before writing SwiftUI code)
This Mac has only Command Line Tools installed, no full Xcode.app. On this
SDK, SwiftUI's `@State` is macro-based (`SwiftUIMacros.dylib`), and that
plugin ships only inside Xcode.app — so `@State` fails to compile here
("plugin for module 'SwiftUIMacros' not found"). `@ObservedObject`,
`@Published`, `@EnvironmentObject`, `@AppStorage` are classic property
wrappers and compile fine. **Rule for this project: never use `@State`;
model local view state as a small `ObservableObject` with `@Published`
properties and drive the view with `@ObservedObject`.** Two benign linker
warnings about missing CLT `Developer/usr/lib` search paths show up on
every build — toolchain artifacts, not from our code; `swift build`
reports zero warnings/errors on our sources.

Same root cause bit us again at Milestone 3: **both XCTest and Swift
Testing need Xcode.app** here (XCTest.framework isn't even present under
CLT; Swift Testing's macro plugin is missing the same way `@State`'s was).
**Rule: no `.testTarget`, no `import XCTest`/`import Testing`.** Instead,
`Mandarin` is a *library* target, `MandarinApp` is a thin executable that
just calls `MandarinApp.main()`, and `Tests/MandarinSelfTests` is a second
plain executable that `import Mandarin` and asserts directly, printing
PASS/FAIL and exiting non-zero on failure — run via `swift run
MandarinSelfTests`; `build.sh` also runs it automatically before every
release build. One consequence: types exercised by self-tests
(`ImageConverter`, `ConverterRegistry`, `OutputPathPlanner`, `ExternalTool`,
`ConversionOptions`/`ConversionError`) are `public`, since a sibling
executable target can't `@testable import` a library the way a real test
target can.

## Architecture snapshot
- Swift Package Manager, bundled into `.app` by `build.sh`. macOS 13+,
  Apple Silicon. Four targets: `Mandarin` (library — all app logic),
  `MandarinApp` (thin executable, `MandarinApp.main()`), `MandarinSelfTests`
  (plain-assertion test executable), `MandarinConvert` (headless CLI that
  drives the real `ConverterRegistry`/`JobQueue` for scripted end-to-end
  verification without a GUI session — see Milestone 5's final entry).
- `MandarinApp` (SwiftUI `App`, in the library) → `AppDelegate`
  (NSApplicationDelegate) owns the status item, settings store, wheel
  controller, drag watcher, job queue, HUD controller, and onboarding
  window.
- `PermissionsManager` checks/opens Accessibility + Input Monitoring panes.
- `SettingsStore` persists prefs to `UserDefaults`; `launchAtLogin` uses
  `SMAppService.mainApp`; also owns the Shift/Command/Control/Option →
  wheel-kind trigger mapping (Settings → Keys, bijective).
- `Converter` protocol (now returns a `ConversionResult { outputURL,
  warning }` — not bare `Void` — since a few routes produce a different
  location than planned, or want to flag themselves "best effort") +
  `ConverterRegistry.shared` (keyed by `UTType`) → one converter per
  engine: `ImageConverter`, `AVFoundationMediaConverter`,
  `FFmpegMediaConverter`, `PDFExportConverter` (native PDFKit),
  `NativeDocumentConverter` (native `NSAttributedString`),
  `PandocDocumentConverter`, `CSVTSVConverter` (native), `LibreOfficeConverter`,
  `SubtitleConverter` (native), `ArchiveConverter` (system zip/tar/gzip +
  `unar`). `FormatCatalog` + per-family `*Formats` tables (`ImageFormats`,
  `MediaFormats`, `DocumentFormats`, `SpreadsheetFormats`,
  `SubtitleFormats`, `ArchiveFormats`) are the single source of truth for
  extension/icon/UTType lookups, shared by the registry, the wheel, and
  `OutputPathPlanner`, so none of them can disagree about "what formats
  exist." `JobQueue` runs each conversion *or File Action* as its own
  `Job` (one unified model — see Milestone 4) in its own `Task`,
  publishing progress/state for the HUD (`HUDController` + `HUDView`),
  with cancellation support.
- `FileActionRunner` performs the 6 File Actions (AirDrop, Float, Copy,
  Move, Copy Path, Terminal); `FloatPanelController` owns the floating
  preview panels Float opens.

## Milestones

1. **Project skeleton** — menu-bar app, settings window, permissions
   onboarding, build script. ✅ DONE
2. **Global drag detection + floating wheel**, dummy segments, full key
   handling (Shift/Command/Control, release-and-hold, Escape). ✅ DONE
3. **Converter protocol, registry, job queue, HUD. Image conversions +
   tests.** ✅ DONE
4. **File Actions wheel (AirDrop, Float, Copy, Move, Copy Path, Open in
   Terminal).** ✅ DONE
5. **Audio and video conversions.** ✅ DONE
6. **PDF, documents, spreadsheets, slides, subtitles, archives.** ✅ DONE
7. **File Tools wheel (26 tools).** ✅ DONE
8. **Polish: keyboard flow, touch/trackpad, accessibility, error handling,
   launch at login (already wired in M1), README.** ✅ DONE

## Milestone 1 — summary
- **Works:** App builds and launches as a menu-bar-only (LSUIElement) app
  with a status item (SF Symbol `repeat.circle`), a menu (Permissions…,
  Settings…, Quit). Settings window has a General tab (launch at login,
  output-location picker). First-run onboarding window checks Accessibility
  + Input Monitoring permissions, live-updates as they're granted, and deep
  links to the right System Settings panes. `build.sh` produces a signed
  (local dev cert if present, else ad-hoc) `Mandarin.app` under `dist/`.
- **Not done yet:** No drag detection, no wheel UI, no converters. Settings
  window has no Keys/Formats tabs yet (added when those features exist).
- **Next:** Milestone 2 — global drag detection and the floating wheel.

## Milestone 2 — summary
- **Works:** `DragWatcher` polls `NSPasteboard(name: .drag)`'s changeCount
  while the left mouse button is down (there's no public "drag started"
  notification) to detect a file/folder drag system-wide. A global
  `.flagsChanged` monitor detects the edge-down of Shift/Command/Control
  (remappable in Settings → Keys, bijective, swap-on-conflict) and opens a
  borderless, non-activating `NSPanel` wheel (`WheelPanelController` +
  `WheelView`) near the cursor with 4-6 dummy segments per kind. The panel
  is a real `NSDraggingDestination` (`WheelHostingView`), so dropping onto
  it completes the OS drag; hit-testing math lives once in `WheelGeometry`
  and is shared by the SwiftUI drawing and the AppKit drop handler so they
  can't drift. Releasing the modifier key does nothing (wheel stays open);
  tapping a different modifier switches the wheel kind in place; Escape
  (global `.keyDown`, keyCode 53) hides it; mouse-up always ends the drag
  session and hides the wheel. Drops currently just `NSLog` which dummy
  segment was hit (real actions start at Milestone 3). Builds with zero
  warnings on our sources; app launches and stays running with no crash
  reports.
- **Not done yet (at the time):** real conversions/tools/actions, and the
  touch/trackpad + Finder-Enter keyboard flows (deferred to Milestone 8).
- **User-tested result:** Shift/Command/Control wheels, release-and-hold,
  and drop-logging all passed. Escape had a bug: it only closed the wheel
  after also releasing the mouse button, and a drop right after Escape
  should do nothing.
  - **Root cause:** Escape is AppKit's own built-in "cancel this drag" key.
    While Finder (or any drag source) is running its drag-tracking loop, it
    consumes Escape locally; the system only re-broadcasts it to other
    apps' global `.keyDown` monitors once that loop unwinds on mouse-up —
    far too late for us.
  - **Fix:** poll `CGEventSource.keyState(.combinedSessionState, key: 53)`
    on the same 40ms timer already used for drag-pasteboard polling,
    instead of a global `.keyDown` monitor. This reads the raw HID key
    state directly and isn't subject to that delay. Belt-and-suspenders:
    `WheelHostingView.isArmed` is set `false` the instant Escape is
    detected, so even if the window is still visually mid-`orderOut`, a
    drop that lands in that gap is rejected (`performDragOperation`
    returns `false`) rather than silently firing. Both paths log to
    Console (`Escape detected mid-drag — cancelling wheel immediately` /
    `drop rejected — wheel was cancelled`) as the "clearly logged check."

## Milestone 3 — summary
- **Works:** `ImageConverter` (the one `Converter` in `ConverterRegistry`)
  handles the full image family as one pipeline — load a `CGImage` (native
  ImageIO, or SVG via `NSImage` rasterized at 4x into an `NSBitmapImageRep`)
  then write it (native `CGImageDestination`, or WebP by writing a temp PNG
  and shelling out to `cwebp`). Native codec support is probed at runtime
  via `CGImageSourceCopyTypeIdentifiers`/`CGImageDestinationCopyTypeIdentifiers`
  rather than assumed — on this Mac that's JPG/PNG/TIFF/BMP/HEIC/AVIF/PDF
  natively, plus WebP since `cwebp` is installed (`ExternalTool` resolves
  Homebrew tool paths and `checkAllAtStartup()` logs what's missing).
  SVG is input-only, as specified — never offered as an output.
  The Shift/Convert wheel now asks `ConverterRegistry.availableTargets(for:)`
  for the dragged file's actual `UTType` (via `URLResourceValues.contentType`,
  not extension-sniffing) instead of showing dummy segments — a `.docx`
  (no document converter yet) correctly shows zero formats ("No
  conversions" in the wheel's center) rather than image formats. Dropping
  enqueues one `JobQueue` job per file (own `Task`, cancellable, progress
  published to the HUD); output is `OutputPathPlanner`'s non-clobbering
  `file.png` → `file 2.png` next to the source (or the Settings custom
  folder). `HUDController` shows a floating panel per job with a progress
  bar, Cancel while running, and on finish either a green check → Reveal in
  Finder (auto-dismisses after 4s) or a red error that stays until
  dismissed — no silent failures. Wheel background is now a full
  `.regularMaterial` disc behind the wedges (was only each wedge's own
  translucent fill), closing the Finder-text-bleeds-through gap in the
  segment seams; crowded wheels (many targets) drop the text label and
  show icon-only below a 40°-per-segment threshold. 11/11 self-tests pass
  (`swift run MandarinSelfTests`, also run automatically by `build.sh`
  before every release build) covering JPG→PNG dimensions, PNG→PDF,
  PNG→WebP (via cwebp), SVG 4x rasterization, `canConvert` rules, registry
  target filtering, and non-clobbering naming.
- **Not done yet (at the time):** File Actions wheel still dummy (M4). Multi-
  file drags built the Convert wheel from only the *first* dragged file's
  type.
- **User-tested result:** Escape-during-drag, real Shift/Convert targets,
  JPG→PNG with progress HUD + Reveal in Finder, non-clobbering naming,
  PNG→WebP/JPG→PDF, and the error HUD for a fake `.jpg` all passed. One
  bug: non-image files (`.docx`, `.pdf`) showed an empty wheel with the
  center label "No conversations" (typo for "No conversions") and no
  indication of why — looked broken rather than "correctly unsupported."

## Small fixes (before Milestone 4)
- Fixed the typo and the UX: the empty-Convert-wheel center message is now
  "No conversions for this file type (.ext)", sized to the full wheel
  (not the tiny center hole) so it's actually readable.
- Mixed selections: `WheelSegment.convertSegments(for:)` now takes the
  *dragged files' types* (plural) and intersects
  `ConverterRegistry.availableTargets(for:)` across all of them, so e.g. a
  JPEG+PNG selection only offers formats valid for both (excluding JPEG and
  PNG themselves, since each is only "foreign" to the other file) — never a
  format that would silently fail on one of the files. An all-unsupported
  or mixed supported/unsupported selection still just shows the empty
  state, with the message listing every distinct extension found when
  types differ ("No common conversions for mixed types (.docx, .png)").

## Milestone 4 — summary
- **Works:** File Actions wheel (Control, by default) now has real
  segments — `WheelSegment.fileActionSegments()` always returns all 6
  `FileAction` cases, completely independent of `ConverterRegistry`, so it
  is identically available for any file, folder, or mixed selection,
  including types with zero Convert targets. `FileActionRunner` performs
  each:
  - **AirDrop** — `NSSharingService(named: .sendViaAirDrop)`, with a clear
    HUD error if AirDrop can't handle the dropped items.
  - **Copy** / **Move** — a simple `NSOpenPanel` folder picker, then
    `FileManager.copyItem`/`moveItem` per file, each as its own cancellable
    HUD row; destination names are non-clobbering
    (`OutputPathPlanner.nonClobberingURL(copying:into:)`, a sibling of the
    conversion naming that keeps the *original* name/extension instead of
    changing it — also handles extensionless files and folders). The
    folder-picker's modal panel is deliberately run one run-loop tick after
    the drop (`DispatchQueue.main.async`) rather than inside
    `performDragOperation` itself, so it isn't nested inside the *source*
    app's (e.g. Finder's) drag-completion callback.
  - **Copy Path** — every dropped file's full path, one per line, onto
    `NSPasteboard.general`.
  - **Open in Terminal** — resolves each dropped item to its containing
    folder (or itself, if it's already a folder), de-duplicates, and opens
    one new Terminal window per unique folder via
    `NSWorkspace.shared.open(_:withApplicationAt:)`.
  - **Float** — `FloatPanelController` opens one small always-on-top
    `NSPanel` per dropped file (QuickLook thumbnail via
    `QLThumbnailGenerator`, falling back to the Finder icon while it
    loads), cascaded so several don't fully overlap. Each has its own close
    button; a dedicated global Escape monitor (installed only while at
    least one float is open — this one isn't racing an active drag, so no
    `CGEventSource` polling needed) closes all of them at once.

  All six report through the same HUD as conversions: `ConversionJob` was
  generalized into `Job` (a `displayName`/`icon` instead of a hard-coded
  `outputType`, and `succeeded(message:revealURL:)` instead of a bare
  output URL) so one HUD row shape covers "Done, [Reveal in Finder]",
  "Copied, [Reveal in Finder]", "Shared", "Path copied", "Opened Terminal",
  and every failure case — no silent failures anywhere. 16/16 self-tests
  pass, including the new copy/move naming (with-extension and
  extensionless/folder cases) and the mixed-selection intersection logic.
- **Not done yet (at the time):** File Tools wheel is still dummy
  (Milestone 7). No audio/video/documents/etc. (Milestones 5-6). Quality
  (`ConversionOptions.quality`) still isn't user-configurable. Float panels
  don't persist across app restarts (by design) and aren't individually
  repositioned by a "smart" layout, just cascaded.
- **User-tested result:** empty-wheel wording fix and mixed-selection
  intersection both confirmed working. AirDrop/Copy/Move/Copy Path/
  Terminal/Float were not hand-tested — the user asked instead for those
  six actions' logic to be covered by automated self-tests (AirDrop and
  Float's actual OS-level effects are inherently UI/hardware-dependent and
  stay untested; everything else about them doesn't).

## Test coverage extension (before Milestone 5)
Pulled the non-UI logic behind Copy/Move/Copy Path/Open in Terminal out of
`FileActionRunner` into `FileActionLogic` — the exact functions the app
calls, callable headless — and added self-tests for: copy/move
non-clobbering naming (with extension, extensionless files, folders, and a
name collision from a pre-existing file at the destination, not just one
our own planner created), move removing the source vs. copy keeping it,
copy-path text formatting for one and several files, Terminal's
file-vs-folder target resolution, and error propagation for a missing or
read-only destination folder. 25/25 self-tests (was 16).

## Milestone 5 — summary
- **Works:** Two new `Converter`s, both registered in
  `ConverterRegistry`/gated by `MediaFormats` (a table like `ImageFormats`,
  listing each format's `UTType`, extension, icon, `domain` (audio/video),
  and which engine handles it):
  - **`AVFoundationMediaConverter`** — M4A audio and MP4/MOV video, via
    classic `AVAssetExportSession` (`exportAsynchronously`/`.progress`/
    `.cancelExport()` — verified these aren't deprecated at our macOS 13
    deployment target even on this very new SDK, so no `@available` forking
    needed). Also handles extracting a video's audio track to M4A.
  - **`FFmpegMediaConverter`** — everything else: MP3, WAV, FLAC, Opus,
    AIFF, WMA audio; MKV, WebM, AVI, WMV, GIF video; and extracting *any*
    of those audio formats from a video (`-vn`), which is what "extract
    MP3" turns out to be — one case of a general video→audio rule, not a
    special one, since restricting it to MP3-only would have taken *more*
    code via an artificial filter. Progress comes from
    `ffmpeg -progress pipe:1`'s `out_time_us=` lines read as an
    `AsyncSequence` (`FileHandle.bytes.lines`) against the duration from
    `ffprobe`, so large files stream and report real progress rather than
    blocking until done. Cancellation calls `process.terminate()` and
    deletes whatever partial file ffmpeg left; `ExternalTool` gained
    `ffprobe` alongside `ffmpeg`/`cwebp`, all three logged at startup.
    Letting ffmpeg pick its own default codec per output extension works
    correctly for every one of these formats *except two*, caught by
    self-tests rather than guesswork: GIF needs an explicit fps/scale
    filter (the unfiltered default is huge and slow), and — a real bug the
    self-test suite caught before this ever ran for real — this Homebrew
    ffmpeg build has no `libvorbis` encoder, only the native `vorbis`
    encoder, which is experimental (`-strict -2`) and stereo-only (`-ac
    2`); without the fix, every OGG conversion would have failed outright.
  - Both converters' `canConvert` rules: audio↔audio and video↔video
    always allowed; video→audio allowed (extraction); audio→video never
    (doesn't make sense). GIF is tagged `domain: .video` despite its UTI
    nominally being an image type, since here it's a video-conversion
    target, not part of `ImageConverter`'s world at all — no collision,
    since `ImageConverter` never lists `.gif` among its own known types.
  - `ConverterRegistry.candidateOutputTypes` and a new `FormatCatalog`
    (extension/icon lookup across both `ImageFormats` and `MediaFormats`)
    unify the previously image-only registry/wheel/naming code so the
    Convert wheel, `OutputPathPlanner`, and the HUD's job icon all work
    identically for images, audio, and video without special-casing.
  - One format-identity subtlety: "opus" and "ogg" resolve to the *same*
    system UTI (`org.xiph.ogg-audio` — Opus is technically an Ogg
    container variant), which would have collapsed them into one
    indistinguishable Convert-wheel target. `MediaFormats.opus` uses
    `UTType(exportedAs:)` to give Opus its own distinct (if unregistered)
    identifier, so both still appear as separate targets.
  - 35/35 self-tests pass (was 25), including real, non-mocked coverage of
    exactly what the spec asked for: audio→audio (WAV→MP3) and video→audio
    extraction via ffmpeg, video→video via both ffmpeg (WebM, MKV) and
    AVFoundation (MOV), video→M4A extraction via AVFoundation, a real GIF
    byte-signature check, the OGG/Vorbis fix verified via `ffprobe`, the
    registry correctly excluding video targets for audio input while
    including MP3 for video input, and — the one requiring real
    concurrency, not just file checks — starting an 8-second synthetic
    conversion, cancelling it after 300ms, confirming `CancellationError`
    propagates and the partial output file is actually gone. Test fixtures
    are synthetic videos generated on the fly via `ffmpeg`'s `lavfi`
    sources, so no bundled sample media is needed.
- **Not done yet:** File Tools wheel still dummy (Milestone 7). No
  documents/spreadsheets/PDF-export/subtitles/archives yet (Milestone 6).
  `ConversionOptions.quality` still isn't user-configurable (affects image
  lossy formats and ffmpeg's audio quality flags alike). WMA encoding
  works (this ffmpeg build ships `wmav2`), but that's not guaranteed on
  every Homebrew ffmpeg build — if `canConvert` were ever wrong about it,
  the failure would still surface as a normal HUD error, not a crash.
- **End-to-end verified on real/generated files** (not just synthetic
  unit-test fixtures) — see the table below. Only the wheel physically
  appearing and a drag-and-drop are left for a human.
- **Next:** Milestone 6 — PDF, documents, spreadsheets, slides, subtitles,
  archives.

## Milestone 5 end-to-end verification (real files, no drag)

Added `MandarinConvertCLI` (`swift run MandarinConvert <input> <ext>
[--output-dir DIR] [--cancel-after N]`) — a third, headless executable
target, additive only, that drives the *exact* `ConverterRegistry`/
`JobQueue`/`Job` the real Convert-wheel drop uses (same `JobQueue.convert`
call, same `OutputPathPlanner` naming, same cancellation path), printing
progress and the final result. This required making `Job`, `JobQueue`, and
`SettingsStore` (plus `customOutputFolderPath`) `public`, the same pattern
already used for `MandarinSelfTests`. No behavior changed for the real app.

Inputs: `~/Desktop/test.aiff` (the user's real file — mono PCM, 1.494422s)
and, since no `.mov` was actually present on the Desktop, a synthetic
40-second `testsrc`+`sine`-tone video generated via `ffmpeg` (h264+aac,
labeled `synthetic_test_video.mov` throughout). All outputs were written
to a scratchpad directory and deleted afterward — nothing was left
anywhere outside `~/Desktop`, and `test.aiff` itself was never modified.

| Test | Input → Target | Command | Result | Verified | Pass/Fail |
|---|---|---|---|---|---|
| Audio: AIFF→WAV | test.aiff → wav | `MandarinConvert test.aiff wav --output-dir OUT` | `test.wav`, 65982 bytes | ffprobe: `pcm_s16le`, duration `1.494422` (input: `pcm_s16be`, `1.494422` — exact match) | **PASS** |
| Audio: AIFF→FLAC | test.aiff → flac | `MandarinConvert test.aiff flac --output-dir OUT` | `test.flac`, 48898 bytes | ffprobe: `flac`, duration `1.494422` (exact match) | **PASS** |
| Video: MOV→WebM | synthetic.mov → webm | `MandarinConvert synthetic.mov webm --output-dir OUT` | Real streamed progress (0.00→0.92→done) | ffprobe: `matroska,webm` container, video `vp9` + audio `opus` both present, duration `40.008` vs input `40.000` (0.008s diff, ≪0.5s) | **PASS** |
| Video: MOV→MP4 | synthetic.mov → mp4 | `MandarinConvert synthetic.mov mp4 --output-dir OUT` | Done | ffprobe: `mov,mp4,...` container, video `h264` + audio `aac` both present, duration `40.000000` exact | **PASS** |
| Extract audio: MOV→MP3 | synthetic.mov → mp3 | `MandarinConvert synthetic.mov mp3 --output-dir OUT` | Done | ffprobe: container `mp3`, codec `mp3`, only an audio stream (video dropped via `-vn`), duration `40.000000` exact | **PASS** |
| Cancel | synthetic.mov → webm, cancelled at 2s | `MandarinConvert synthetic.mov webm --output-dir OUT --cancel-after 2` | Progress ran 0.00→0.23 then `RESULT cancelled`, exit 0 | `pgrep -fl ffmpeg` → nothing running; output dir → empty, no partial `.webm` | **PASS** |
| Naming | test.aiff → wav, run twice, same dir | two `MandarinConvert test.aiff wav --output-dir OUT` calls | 1st: `test.wav`; 2nd: `test 2.wav` | Both files present with matching sizes (65982 bytes each); `~/Desktop/test.aiff` unchanged after both runs | **PASS** |
| Error | fake.mp3 (plain text, renamed) → wav | `MandarinConvert fake.mp3 wav --output-dir OUT` | `RESULT failed message="... Invalid data found when processing input"`, exit 1 | ffmpeg's real decode error surfaced verbatim (not a crash, not a silent success); output dir stayed empty — no garbage file | **PASS** |

All 8/8 passed on the first run — no fixes were needed this round (the one
real bug Milestone 5 had, the OGG/libvorbis encoder, was already caught
and fixed by the self-test suite before this verification pass).

Minor polish note for later: the error-case message is ffmpeg's raw
multi-line stderr dump, not a one-line summary. It's specific and
readable (clearly says "Invalid data found when processing input"), but
the HUD row only shows 2 lines — worth trimming to just the first
meaningful line in a later polish pass (Milestone 8), not a correctness
issue now.

## Milestone 6 — summary

- **What's genuinely NOT achievable, and why** (checked empirically, not
  guessed): **PDF→DOCX/PPTX/XLSX/EPUB and anything→PAGES are not
  offered.** LibreOffice's headless PDF import only ever produces a Draw
  document — its export filters for a PDF-opened file are limited to
  odg/png/jpg/pdf/html; `soffice --convert-to docx` on a PDF fails with
  "no export filter for ... found, aborting," confirmed directly. Pandoc
  has no PDF reader at all (`pandoc --list-input-formats` doesn't include
  `pdf`). PAGES can't be written by anything available (it's Apple's
  proprietary iWork format), and reading it would mean pulling the
  QuickLook preview PDF out of its bundle instead of real content — a
  fake, not a conversion. Per spec, these are simply not registered
  rather than faked.
- **PDF** (native PDFKit, no external tool) — pages → JPG/PNG at 300 DPI;
  a single page writes the planned file directly, more than one creates a
  new sibling folder (`report/report-1.png`, `report-2.png`, ...) — never
  loose numbered files. Text → TXT natively; → MD is the same extracted
  text with a "best effort — plain text only, no headings or formatting"
  HUD note, since there's no layout-to-Markdown reconstruction happening,
  just honest text extraction.
- **Documents** — `NativeDocumentConverter` handles RTF/RTFD/DOCX/TXT/
  textClipping in, DOCX/TXT/HTML out, entirely via `NSAttributedString`'s
  own document import/export (confirmed by real round-trips before
  relying on it: wrote and read back actual .rtf/.rtfd/.docx files).
  `PandocDocumentConverter` covers the two formats `NSAttributedString`
  can't touch, Markdown and EPUB, letting `pandoc` infer both reader and
  writer from file extensions alone (`pandoc in.md -o out.epub` just
  works, verified) — flagged "best effort" whenever EPUB or DOCX is on
  either side, since reflowing between a word processor and an ebook
  structure is inherently lossy.
- **Spreadsheets** — CSV↔TSV natively (a real RFC4180-aware parser —
  quoted fields, embedded commas/newlines, doubled-quote escaping — not
  just a naive comma/tab swap), since that's a text transform, not
  something that needs LibreOffice's whole engine spun up.
  `LibreOfficeConverter` handles XLSX/ODS/XLS/CSV/TSV → XLSX/ODS/CSV/TSV
  and → PDF export. Each invocation gets its own temp LibreOffice profile
  (`-env:UserInstallation=`) so concurrent conversions don't fight over
  the same profile lock, and `soffice`'s harmless "Fontconfig warning"
  stderr noise is filtered out before anything reaches the HUD as an
  error (found while verifying the error path — the real message was
  there, just buried under six lines of warnings).
- **Slides** — PPT/PPTX → PDF/JPG/PNG via `soffice`. Image export
  deliberately goes through PDF first and `PDFRasterizer` (shared with
  the PDF route) second: verified empirically that LibreOffice's own
  `--convert-to png`/`jpg` silently exports only the *first* slide of a
  multi-slide deck, while `--convert-to pdf` correctly preserves every
  slide as its own page — so going through PDF is the only way to get
  all of them. Flagged "best effort — layout may not match the original
  exactly."
- **Subtitles** — SRT↔VTT↔TXT, entirely native. One small parser keyed
  off any line containing `-->` (so it doesn't care whether an
  index/identifier line precedes it, or whether the decimal separator is
  `,` or `.`) handles both formats; verified a full SRT→VTT→SRT round
  trip comes back byte-identical.
- **Archives** — ZIP↔TAR↔GZIP re-archiving and RAR→any of them, via
  `unar` (extraction — handles zip/tar/gzip/rar alike) and the system's
  own `/usr/bin/zip`/`tar`/`gzip` (always on macOS, not a Homebrew
  dependency that can be missing) for repacking. **Deliberately
  archive-to-archive only** — a universal "compress any file" target
  would add 3 entries to *every* file type's Convert wheel, which is
  exactly the "more than 8 targets" crowding the spec says to avoid; that
  universal action belongs to Milestone 7's "Compress" File Tool instead.
  Two real bugs caught by testing before they'd have shipped: (1) the
  first implementation wrapped the *whole source archive* inside the new
  container instead of extracting-then-repacking its contents (so "zip
  to tar" produced a tar containing one file named `original.zip`, not
  its actual contents) — fixed by always extracting first, for any
  archive input, not just RAR; (2) gzipping multiple files was named
  `.gz` (implying a single compressed stream) while actually containing a
  full tar+gzip — fixed by naming that case `.tar.gz` and returning the
  real path via `ConversionResult`, the same pattern already used for the
  multi-page PDF/slide folder case.
- **Wheel crowding, and a real pre-existing bug it caught**: added a
  permanent self-test asserting no sampled file type exceeds 8 Convert
  targets. It immediately failed — MP4 had 13-14, because Milestone 5 had
  generalized "extract MP3 from video" into "extract to *any* audio
  format" (MP3/WAV/FLAC/Opus/AIFF/WMA/OGG, all 7). Scaled that back to
  MP3-only (what the spec actually asked for) plus the separately-justified,
  already-native M4A extraction via `AVFoundationMediaConverter` — MP4 is
  now exactly 8.
- **Tools**: installed `pandoc`, `unar`, `p7zip` (formulae) and
  `libreoffice` (cask) via Homebrew, all without `sudo` — `/opt/homebrew`
  and `/Applications` are both user-writable, no privilege needed.
  `p7zip` ended up unused (`unar` alone covers every archive route
  Mandarin needs) but is harmless left installed. `ExternalTool` gained
  `pandoc`/`soffice`/`unar`; all six tools (ffmpeg/ffprobe/cwebp/pandoc/
  soffice/unar) are logged at startup. Licenses recorded in
  `THIRD_PARTY.md` (none of these are bundled — Mandarin only shells out
  to what's already installed, same as it always has for ffmpeg/cwebp).
- 54/54 self-tests pass (was 35), covering every route above plus the
  wheel-crowding invariant, a corrupted-XLSX error case, and a fake-RAR
  error case — all with real generated fixtures (a native CoreGraphics+
  `NSAttributedString`-drawn PDF with actual extractable text, real RTF/
  DOCX via `NSAttributedString`, real PPTX via pandoc, real ZIP via
  `/usr/bin/zip`), not just "file exists" checks.
- **Not done yet:** File Tools wheel still dummy (Milestone 7).
  `ConversionOptions.quality` still isn't user-configurable. WMA encoding
  works on this ffmpeg build (ships `wmav2`) but isn't guaranteed on every
  build — if ever wrong, the failure surfaces as a normal HUD error, not
  a crash. The HUD's error text for tool failures is often a raw
  multi-line stderr dump (noted for Milestone 8 polish, not a correctness
  issue — `LibreOfficeConverter` already strips Fontconfig noise, but
  ffmpeg/pandoc errors aren't trimmed to just the first meaningful line).
- **Not personally re-verified by hand** — this entire milestone was
  built and tested exclusively via the headless `MandarinConvert` CLI and
  automated self-tests, per this session's standing instruction to no
  longer ask for manual drag tests. No manual verification has occurred
  for Milestone 6 at all.
- **Next:** Milestone 7 — File Tools wheel (Command key, ~26 tools).

## Milestone 6 verification table

Run via the `MandarinConvert` CLI against real generated fixtures (a real
PDF via `textutil`/`soffice`, a real multi-page PDF, a real DOCX/XLSX/
PPTX via `soffice`/pandoc, a real SRT, a real ZIP via `/usr/bin/zip`),
each verified by actually parsing the output (ffprobe/PDFKit page count/
`tar -tf`/content diff), not just checking it exists — then captured
permanently as the 19 new self-tests listed by name in `swift run
MandarinSelfTests`'s "Milestone 6" sections above.

| Route | Verified via | Result |
|---|---|---|
| PDF → PNG, single page | `sips` pixel dimensions | 2480×3507 (A4 @ 300 DPI) — **PASS** |
| PDF → PNG/JPG, 3 pages | folder contents + `file` | folder with 3 numbered images, no loose file — **PASS** |
| PDF → TXT / MD | content diff | exact text extracted; MD carries the "best effort" HUD note — **PASS** |
| TXT → DOCX → TXT | content round trip | byte-exact (mod. NSAttributedString's own trailing newline) — **PASS** |
| RTF → HTML | content check | real `<html>` output, text preserved — **PASS** |
| DOCX → MD, TXT → EPUB | pandoc + `file` | both succeed, flagged "best effort" — **PASS** |
| CSV ↔ TSV | content round trip | byte-identical after the trailing-newline fix — **PASS** |
| CSV → XLSX → ODS → PDF | `file` on each output | all produced, correct container types — **PASS** |
| PPTX → PDF | PDFKit page count | 2 pages preserved — **PASS** |
| PPTX → PNG | folder contents | 2 slide images in a new folder (not just slide 1) — **PASS** |
| SRT ↔ VTT, SRT → TXT | content round trip | byte-identical; TXT has no timestamps — **PASS** |
| ZIP → TAR | `tar -tf` listing | `a.txt`/`b.txt` at top level (after the extract-then-repack fix) — **PASS** |
| TAR → GZIP (2 files) | filename + `tar -tzf` | named `.tar.gz` (after the naming fix); contents intact — **PASS** |
| Fake RAR → ZIP | exit code + message | "Couldn't recognize the archive format," exit 1 — **PASS** |
| Fake XLSX → CSV | exit code + message | clear "no export filter" error, Fontconfig noise stripped — **PASS** |
| Cancel: XLSX → PDF | `pgrep soffice` + dir listing | no process left, no partial file — **PASS** |
| Non-clobbering: TXT → DOCX ×2 | filenames | `sample.docx`, `sample 2.docx` — **PASS** |
| Wheel crowding: MP4 | `--list-targets` count | 13-14 before the fix, 8 after — **PASS (after fix)** |

## File Tools (26) — chosen list

Gated by `FileTool.tools(for:selectionCount:)`: each tool only shows on
the Command wheel for the file type(s) it applies to; the 3 Merge tools
additionally require 2+ files selected (nothing to merge with one); every
other tool works on a single file, a folder, or each file in a mixed
selection independently. "Compress (Archive)" is universal — it's the one
tool every single type offers, intentionally *not* a Convert-wheel target
(seeM6) to avoid pushing every format past 8 Convert targets.

| # | Tool | Applies to | Parameters (sheet) |
|---|---|---|---|
| 1 | Compress | Image | Quality (0.1-1.0) |
| 2 | Resize | Image | Width, Height |
| 3 | Crop | Image | X, Y, Width, Height |
| 4 | Rotate | Image | Degrees |
| 5 | Flip | Image | Direction (H/V) |
| 6 | Grayscale | Image | — |
| 7 | Strip Metadata | Image | — |
| 8 | Compress | Video | — |
| 9 | Resize | Video | Width, Height |
| 10 | Crop | Video | X, Y, Width, Height |
| 11 | Trim | Video | Start, End (seconds) |
| 12 | Rotate | Video | Degrees |
| 13 | Change Speed | Video | Speed (0.5-2.0×) |
| 14 | Extract Audio | Video | — |
| 15 | Grayscale | Video | — |
| 16 | Merge | Video (2+ files) | — |
| 17 | Trim | Audio | Start, End (seconds) |
| 18 | Change Speed | Audio | Speed (0.5-2.0×) |
| 19 | Merge | Audio (2+ files) | — |
| 20 | Compress | PDF | — (rasterize + rebuild, best effort) |
| 21 | Split | PDF | — (one file per page, into a new folder) |
| 22 | Merge | PDF (2+ files) | — |
| 23 | Rotate | PDF (all pages) | Degrees |
| 24 | Extract Pages | PDF | Pages (e.g. "1-3,5") |
| 25 | Strip Metadata | PDF | — |
| 26 | Compress | Any file/folder (universal) | — |

Dropped from the spec's candidate list to stay at 26 and keep each tool
genuinely simple: Flip Video (redundant with Rotate in spirit) and Split
Audio (Merge Audio is the more commonly useful direction). Not
reconsidered as separate tools since they're already covered: converting
a video's audio to a specific format beyond MP3 (that's a Convert-wheel
route, M5) and converting PDF pages to images (PDF → JPG/PNG, M6).

## Milestone 7 — summary
- **Works:** `FileTool` (26 cases) + `FileTool.tools(for:selectionCount:)`
  decides what the Command wheel shows for a given drag — gated by
  category (image/video/audio/PDF/archive) and, for the 3 Merge tools,
  selection size. Tools needing input (crop area, trim start/end, resize
  dimensions, rotation degrees, flip direction, PDF page range, image
  quality) open a small native sheet (`ToolParameterSheetView`, one
  generic form reused for every tool via a `[ToolParameter]` field list —
  not 10 bespoke views) with sensible defaults, Apply/Cancel; tools
  needing no input run immediately on drop, same as Convert/File Actions.
  Every tool is built entirely on frameworks/tools already integrated and
  tested in Milestones 3-6 — ImageIO/CoreGraphics (image tools), ffmpeg
  (video/audio tools, reusing the same `-progress pipe:1` real-progress
  pattern from Milestone 5), PDFKit (PDF tools), system `zip` (the
  universal Compress). No new external dependency.
  - A new `ProcessRunner` utility (run a process, support cancellation,
    surface a clear error) was extracted since this was about to become
    the 4th near-identical copy of that logic (after
    `FFmpegMediaConverter`/`LibreOfficeConverter`/`ArchiveConverter`,
    left alone to avoid regressing already-tested code for a pure
    refactor).
  - Merge (video/audio/PDF) runs as one `Job` for the whole selection,
    not one per file — "merge 3 clips" should make one output, matching
    the same reasoning already applied to File Actions.
  - Non-clobbering names and cancellation-with-cleanup work exactly like
    every other milestone (same `OutputPathPlanner`, same
    terminate-and-delete-the-partial-file pattern).
- **Three real bugs found by testing, fixed before this shipped:**
  1. **PDF was being offered image tools, not PDF tools.** `ImageFormats`
     lists `.pdf` as an export *target* for images (so Convert can offer
     "PDF" from a photo — Milestone 3), which made
     `ImageFormats.format(for: .pdf)` non-nil and misclassified a dragged
     PDF *itself* as an image in `FileTool`'s category resolution. Fixed
     by checking `.pdf` first, before the image-conformance check.
  2. **A self-test's own cross-test state leakage**, not a product bug,
     but worth recording: `SettingsStore.customOutputFolderPath` persists
     to `UserDefaults.standard` — a process-wide singleton — so one
     test's custom output folder (cleaned up by its own `defer`) leaked
     into the *next* test's fresh `SettingsStore()`, which read the now-
     deleted path back out of `UserDefaults` and failed with "No such
     file or directory." Fixed by resetting
     `customOutputFolderPath = nil` right after constructing every
     `SettingsStore()` in the self-test suite, rather than trusting it
     starts clean.
  3. **A flaky cancellation test**, also test-only: compressing an 8s/
     320x240 synthetic clip took ~0.1s — far faster than the 300ms delay
     before cancelling, so the job legitimately finished before
     cancellation could land. Fixed by using a 60s/1280×720 clip (~2.4s
     to compress) for that one test.
- **The one File Tools wheel that's slightly crowded**: a single video
  file offers 9 tools (8 applicable + the universal Compress Archive),
  one over the informal 8-target ceiling observed for Convert in
  Milestone 6. Milestone 6's "more than 8 targets" rule was written for
  the Convert wheel specifically; File Tools has no matching requirement
  in the spec, and the wheel's existing icon-only-below-40°-per-segment
  fallback (Milestone 3) already keeps a 9-segment wheel legible. Not
  forcing a tool out just to hit a round number that isn't actually
  required here — noted, not hidden.
- 76/76 self-tests pass (was 54), covering `FileTool`'s gating logic
  (category resolution including the GIF/PDF edge cases, Merge's
  selection-size gate), every pure helper function
  (`FileToolImaging`/`FileToolPDF.parsePageRange`/
  `FileToolMediaArgs.rotationFilter`), and full end-to-end runs through
  the real `FileToolRunner` + `JobQueue` for a representative tool in
  every category (Resize Image, Trim Video, Rotate PDF, Extract Pages,
  Split PDF, Merge PDF, Compress Archive) plus cancellation.
- **Not done yet:** Settings (remap keys, default output location,
  enable/disable formats, launch at login — launch-at-login already
  works, the rest is Milestone 8), keyboard-only flow, trackpad
  hold-to-drag, VoiceOver labels, Reduce Motion audit, README, final
  codebase review for dead code/TODOs/networking.
- **Not personally re-verified by hand** — built and tested exclusively
  via automated self-tests and direct `FileToolRunner`/`JobQueue` calls,
  per this session's standing instruction. The one piece that
  structurally cannot be verified this way is the parameter sheet UI
  itself (`ToolParameterSheetView`/`ToolParameterWindowController`) —
  its logic (default values, field-to-parameter wiring) is exercised by
  passing `ToolParameterValues` directly in tests, but the actual window
  appearing, its layout, and clicking Apply/Cancel have not been seen.
- **Next:** Milestone 8 — Polish (keyboard flow, trackpad, accessibility,
  Settings, README, final codebase review).

## Milestone 8 — summary

- **Keyboard-only flow**: `FinderKeyboardController` — select a file in
  Finder, press Return (global `.keyDown` monitor, only acts if Finder is
  frontmost and nothing's already open), and it queries Finder's
  selection via `NSAppleScript` (an Apple Event — macOS prompts for
  "Automation" permission the first time, explained in onboarding now)
  and opens the Convert wheel at the cursor with the first segment
  focused. Arrow keys move the focus (`model.hoveredIndex`, the same
  property mouse-hover already drove), Return calls
  `wheelController.onDrop?` directly — the exact closure a real drop
  calls, so the keyboard path and the drag path share 100% of the actual
  conversion/action/tool logic, not a parallel copy — Escape closes it,
  Command/Control switch kind exactly like the drag flow's modifier taps.
- **Trackpad hold-to-drag**: `DragWatcher` now records when the mouse
  went down, and the moment a drag is first detected (pasteboard
  changed), if that press has already sat still for ≥0.45s, the Convert
  wheel opens automatically — no modifier tap needed. A quick drag
  (pressed and immediately moving) is unaffected and still needs a key
  tap, same as every earlier milestone.
- **VoiceOver**: every wheel segment already had an accessibility label
  (since Milestone 3) — but File Tools' "Compress" (per-category: image/
  video/PDF) and the universal "Compress Archive" can appear in the same
  wheel sharing one short *visual* label, which would read identically to
  VoiceOver too. Added `FileTool.accessibilityLabel` (category-qualified
  for all 26 tools, e.g. "Compress Image" vs "Compress Archive") and a
  `WheelSegment.accessibilityLabel` that uses it for File Tools and falls
  back to the plain title elsewhere, where there's no collision to
  disambiguate.
- **Reduce Motion**: audited — exactly two `.animation()` call sites in
  the whole app (the wheel's hover highlight, the HUD's progress bar),
  both already gated on `accessibilityReduceMotion`. Nothing missed.
- **Wheel background**: bumped from `.regularMaterial` to `.thickMaterial`
  for the backing disc and removed the wedges' own `0.97` opacity (now
  fully opaque) — the translucency that let a sliver of Finder text
  bleed through in the gaps/corners is gone.
- **Settings → Formats**: new tab, one toggle per Convert target
  (`SettingsStore.disabledFormatIdentifiers`, persisted, threaded through
  `WheelPanelController`/`WheelViewModel` into
  `WheelSegment.convertSegments`'s filter). Turning a format off only
  ever affects the Convert wheel — File Tools and File Actions are
  untouched, since "enable/disable formats" in the spec means conversion
  targets, not tools or actions. The other three Settings asks (remap
  trigger keys, default output location, launch at login) were already
  done in Milestones 1-2; this was the one genuinely new piece.
- **Clearer error messages everywhere**: added
  `ConversionError.toolFailed(fromRawOutput:)`, which trims a raw
  multi-line tool dump (ffmpeg/pandoc/cwebp/zip/tar/unar stderr) to its
  first non-blank line before it reaches the HUD — applied at every
  `toolFailed` site across `FFmpegMediaConverter`, `PandocDocumentConverter`,
  `ImageConverter`, `ArchiveConverter`, `ProcessRunner`, and
  `FileToolRunner`. `LibreOfficeConverter` applies the same trimming
  *after* its existing Fontconfig-noise filter (order matters — trimming
  first would often surface a harmless Fontconfig line instead of the
  real error).
- **Final codebase review**:
  - *Duplicated logic*: extracted `ProcessRunner` (Milestone 7) and this
    milestone retrofitted `ArchiveConverter` onto it, removing its own
    copy of the same run-a-process-with-cancellation logic. Deliberately
    **not** retrofitted: `FFmpegMediaConverter`/`FileToolRunner`'s ffmpeg
    runners (they stream stdout for live progress — a real capability
    `ProcessRunner` doesn't have) and `LibreOfficeConverter` (its
    Fontconfig-then-first-line error cleaning is a genuine two-stage
    requirement `ProcessRunner`'s generic trimming can't reproduce without
    losing the Fontconfig filter). Confirmed these are real behavioral
    differences, not laziness, before leaving them alone.
  - *Dead code*: found and removed `ImageConverter.availableOutputs(for:)`
    (never called — `ConverterRegistry` always goes through
    `canConvert` instead) and `DocumentFormats.rtfInput`/`rtfdInput`/
    `textClippingInput`/`isKnownInput` (all unused — `NativeDocumentConverter`
    references the system `.rtf`/`.rtfd` UTTypes directly, not these
    wrapper `Format` values).
  - *TODOs/FIXMEs*: `grep -rn "TODO\|FIXME\|XXX:"` across `Sources/` and
    `Tests/` — zero matches.
  - *Networking*: `grep` for `URLSession`/`NSURLConnection`/`Network`
    framework/`NWConnection`/`CFSocket`/`CFReadStream`/`CFWriteStream`/
    `URLRequest`/`CFHTTPMessage` across `Sources/` — zero matches. No
    `.entitlements` file exists anywhere in the project (`find . -iname
    "*.entitlements"` — zero matches) — the app is unsandboxed with no
    entitlements declared at all, so there's no network entitlement to
    remove; there was never one to begin with.
- **README.md** added: requirements, build instructions, permissions
  (including the new Automation one), how to use every input method,
  a supported-formats summary, Settings, a brief architecture pointer
  back to this file, and known limitations.
- 80/80 self-tests pass (was 76): `SettingsStore.setFormat`/
  `isFormatEnabled` round-trip and default-enabled state, and
  `FileTool.accessibilityLabel` uniqueness/disambiguation. The keyboard
  flow and trackpad hold-to-drag are not covered by self-tests — both
  depend on real global input timing/Finder Apple Events that only mean
  something with an actual human at the keyboard/trackpad; see below.
- **Not personally re-verified by hand, at all, for this entire
  milestone** — per this session's standing instruction. Three pieces
  are *structurally* impossible to verify without a human, listed
  precisely so nothing is assumed working that hasn't been seen:
  1. The keyboard-only flow end to end (Return in Finder actually opening
     the wheel, the Automation permission prompt appearing and being
     grantable, arrow-key focus actually being visible, Command/Control
     actually switching wheels).
  2. Trackpad hold-to-drag actually triggering at the right moment on
     real trackpad hardware (the 0.45s threshold is a guess, not tuned
     against a real finger).
  3. The File Tools parameter sheet window (Milestone 7) — its layout,
     and that clicking Apply/Cancel behaves as expected — still unseen.
  Also unseen but lower-risk (same mechanism already proven working
  visually in Milestones 2-7, just with changed constants): the wheel's
  new background opacity, and the Settings → Formats tab's list/toggle
  layout.
- **Next:** nothing — all 8 milestones are done. Final report follows.

## Phase 9 — Release package (Part A) — DONE
- `AppIdentity` (name + bundle ID) is the one code constant; Info.plist and
  README title mirror it; a self-test (`ReleaseTests.swift`) fails on drift.
- App icon: `build.sh` makes `AppIcon.icns` from `Resources/mandarin-icon.png`
  with sips + iconutil. Menu-bar icon: `MenuBarIcon` (vector ring + dot,
  template image; tested at 16/32 px).
- `install.sh` (checks macOS 13+/arm64/CLT, installs missing brew tools after
  a prompt/`--yes`, builds, copies; `--prefix`, `--skip-deps`; never sudo),
  `uninstall.sh`, `Brewfile`, `Makefile`, `release.sh` (codesign + notarytool
  placeholders; never run), `export-clean.sh` (single neutral commit, aborts
  if personal data is found), CI workflow (macOS, no secrets).
- Docs: README rewritten, LICENSE (MIT), CONTRIBUTING, SECURITY, THIRD_PARTY.
- Hygiene scan: no TODO/FIXME, no absolute user paths, no networking APIs.
  Old git history still has the personal author/hostname — that is why the
  public copy is a fresh single-commit export.
- Session-export `*local-command-caveat*.txt` is git-ignored, never tracked,
  excluded from the export.
- Install dry run verified with `--prefix` into a temp dir.

## Phase 10 — Visual editor windows (Part B) — DONE
All under `Sources/Mandarin/Editors/`; routing in `EditorKind.kind(for:selectionCount:)`
(single selected file only; multi-file drops keep the numeric sheet), opened by
`EditorCoordinator` from `AppDelegate`'s File Tools branch. Exports go through
`EditorExporter` -> `JobQueue` -> HUD; open failures through `JobQueue.reportFailure`.
Escape closes without saving (`EditorWindow.cancelOperation`).
1. **Photo** (`PhotoPipeline`, `CropGeometry`, `PhotoEditorModel/View`, `CropOverlay`):
   crop with 9 aspect presets, rotate/flip, linked resize, brightness/contrast/saturation,
   grayscale, show-original toggle; preview on a 1800 px proxy off-main, export decodes
   full size once. New tool `backgroundImage` (27 tools now).
2. **PDF pages** (`PDFPageList`, `PDFPageBuilder`, `PDFPagesModel/View`): lazy thumbnails
   from private PDFDocument instances on a serial queue, drag/keyboard reorder, delete,
   rotate, extract selected, append PDFs.
3. **Background** (`BackgroundTool`, ...): solid/gradient fill, solid-colour removal with
   tolerance (contiguous or global, click-to-pick), Vision foreground mask on macOS 14+.
4. **Audio** (`WaveformPeaks`, `AudioTrimPlan`, `MediaPreviewPlayer`, ...): streamed peaks
   (AVAudioFile, ffmpeg pipe fallback for OGG/Opus/WMA), trim handles + time fields,
   range preview, fades, volume, split at playhead.
5. **Video** (`VideoTrim`, `VideoEditorModel/View`): thumbnail strip, trim handles, AVPlayer
   layer preview, optional crop box, stream copy when lossless is possible (no crop),
   exact re-encode otherwise. `FFmpegRunner` was extracted from `FileToolRunner`.
Tests: `Tests/MandarinSelfTests/EditorTests.swift` (crop fuzz, trim times, peaks, page
order, naming, exports verified with ImageIO/PDFKit/ffprobe, offscreen view snapshots;
set `MANDARIN_SNAPSHOT_DIR` to save PNGs).
Not automatically verifiable: real mouse dragging feel, live AVPlayer video/audio output,
VoiceOver speech, Vision cutout quality on real photos.
