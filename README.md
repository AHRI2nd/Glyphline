# Glyphline

> ⚠️ **Development is currently paused.** This project is not being actively worked on right now. The code here reflects its state as of the last commit.

A professional, native macOS subtitle editor — built with Swift, SwiftUI, and libmpv.

Glyphline pairs a frame-accurate video/waveform workspace with a full editing, quality-assurance, and delivery toolchain: multi-format import/export, ASS-level styling, timing tools, batch conversion, and a one-click pipeline for producing client-ready delivery packages. It targets macOS specifically rather than aiming for cross-platform reach — see [Why native, why macOS-only](#why-native-why-macos-only) below.

> **Status:** paused, no stable release yet. The app is unsigned/unnotarized outside of a maintainer's own local build (see [Building](#building)).

---

## Table of contents

- [Highlights](#highlights)
- [Architecture](#architecture)
- [Supported formats](#supported-formats)
- [Feature tour](#feature-tour)
- [Requirements](#requirements)
- [Building](#building)
- [Project layout](#project-layout)
- [Testing](#testing)
- [Why native, why macOS-only](#why-native-why-macos-only)
- [Roadmap / non-goals](#roadmap--non-goals)
- [Acknowledgments](#acknowledgments)

---

## Highlights

- **Frame-accurate media playback** via libmpv's render API — no browser `<video>` codec ceiling (HEVC, MKV, AVI, and anything else mpv handles play natively), no overlay-window hacks.
- **Lossless native project format** (`.glyph`, JSON) with a canonical in-memory subtitle model; every external format is an import/export *adapter*, never the source of truth.
- **11 subtitle formats**: SRT, WebVTT, ASS/SSA (with full inline-tag fidelity), SAMI, YouTube SBV, LRC, plain text, TTML/DFXP, and the two broadcast/legacy formats EBU-STL and Scenarist SCC/CEA-608 — plus the native `.glyph` project format.
- **Free-form docking UI**: drag any panel to split, tab, or merge it anywhere in the window — or drag it clean out of the window to pop it into its own floating OS window, and drag it back in to re-merge. Several utility panels (Activity, Mini Player, Project Dashboard, Shared Glossary) also live as standalone always-available windows.
- **A real timing toolkit**: point-sync retiming, speed/frame-rate conversion, SMPTE drop-frame timecode, shot-change detection with waveform snapping, silence-based auto-spotting, and a batch post-processor for lead-in/lead-out/gap/cut-snap adjustments.
- **Quality assurance built in**: configurable CPS/duration/line-length/overlap checks (with Netflix-style presets), spell checking with a house-style ignore list, translation-consistency checking against a glossary, font-coverage checks, and CSV/HTML QC report export.
- **A unified delivery pipeline**: point it at a folder of subtitle+video pairs and it produces, per item, every requested export format, a burned-in review copy, a QC report, and collected fonts — with a manifest summarizing the whole run.
- **Data safety**: autosave with multi-backup rotation, crash recovery, dirty-close confirmation, and encoding auto-detection (including legacy CJK encodings like CP949/Shift_JIS) on open.
- **Localized UI**: Korean, English, and Japanese, switchable at runtime.

## Architecture

The whole app is built around one rule: **a single canonical in-memory model, with every file format as an adapter around it.**

- The app edits exactly one `SubtitleDocument` in memory. Every UI surface, undo/redo entry, and quality check operates on that model — never on a specific file format's representation.
- **`.glyph`** (JSON) is the lossless serialization of that model — the "save/open" format for real projects.
- **Every other format** (SRT, VTT, ASS, SMI, SBV, LRC, TXT, TTML, STL, SCC) is an import/export adapter registered in `Sources/GlyphlineCore/Formats/Registry.swift`. Information a target format can't represent is either preserved in a side channel (`raw`, `assSpans`, `tokens`) or dropped with an explicit warning to the user — never silently. Adding a new format is one adapter file plus one registry line; the editing core never changes.
- **Media playback** uses libmpv's render API (`mpv_render_context_*`), dynamically loaded via `dlopen` at runtime (the app still launches without mpv installed — it prompts you to `brew install mpv`). The app owns the GL surface directly and repaints on demand, avoiding the flicker/redraw problems of embedding mpv's own window.
- **Undo/redo** is plain value-type snapshotting (Swift structs, copy-on-write) rather than a diff/patch system — simple to reason about, and cheap enough at typical subtitle-document sizes (verified up to 5,000 cues in the performance test suite) that it needs no cleverness.

## Supported formats

| Format | Extension | Notes |
|---|---|---|
| Glyphline project | `.glyph` | Native, lossless, JSON |
| SubRip | `.srt` | |
| WebVTT | `.vtt` | |
| Advanced SubStation Alpha | `.ass`/`.ssa` | Inline override tags, karaoke (`\k`), embedded `[Fonts]`/`[Graphics]` — all preserved verbatim |
| SAMI | `.smi` | CP949 export supported; ASS-only features are dropped with an explicit loss warning |
| YouTube captions | `.sbv` | |
| LRC | `.lrc` | |
| Plain text | `.txt` | Script/transcript export |
| TTML / DFXP | `.ttml` | |
| EBU-STL | `.stl` | Binary broadcast format; ISO 6937 text codec |
| Scenarist SCC (CEA-608) | `.scc` | |

Encoding on open is auto-detected (BOM → UTF-8 → CJK legacy-encoding fallback, including CP949/Shift_JIS); on export you choose encoding, line ending (LF/CRLF), and BOM explicitly.

## Feature tour

**Editing core**
Multi-select, range-select, split/merge/duplicate cues, real-time I/O/P timing keys against the playhead, find & replace (regex-capable), user-defined auto-fix rule sets, batch cleanup (overlap fixing, gap clamping, length limits, empty-cue removal, case conversion, hearing-impaired-tag stripping, duplicate merging), source/translation two-column editing, word/character-level (karaoke) timing, and an ASS inline-tag structural editor with a live position/alignment visual editor.

**Media**
libmpv-backed playback with frame stepping, variable speed, per-cue loop playback, multi-audio-track selection, volume/mute, and a waveform view (downsampled audio extraction, log-scale zoom, playhead-centered auto-scroll, click-to-seek, drag-to-edit cue regions) with an optional spectrogram mode. Broadcast title-safe/action-safe guide overlays and a position-preview overlay are available for on-screen positioning work.

**Timing tools**
Point-sync (two-point linear retiming), speed/frame-rate change with fps presets, SMPTE timecode display with drop-frame support, a batch timing post-processor (lead-in/out, gap snapping, cut snapping), shot-change detection with waveform markers and QC integration, and silence-based auto-spotting.

**Quality & review**
Configurable thresholds (CPS, min/max duration, line length, line count) with a Netflix-style preset, live quality-issue aggregation, spell checking against the system dictionary plus a project- and system-level ignore list, notation-variant detection, translation consistency checking (repeated-source-divergent-translation detection, plus a glossary check that merges a per-project glossary with an app-wide shared glossary), font coverage/glyph checking, and CSV/HTML QC report export.

**Batch & delivery**
Folder-wide batch format conversion with cleanup and collision-safe output naming, and a unified delivery pipeline that — per subtitle/video pair in a scanned folder — runs cleanup, multi-format export, an ffmpeg burned-in review encode, a QC report, and font collection, writing everything into a per-item folder plus a run-level manifest (JSON + human-readable text). Long-running jobs (burn-in, batch conversion, shot-change detection) register as background jobs that stay visible in a persistent Activity window even after their originating panel is closed.

**Windows & layout**
A VS Code–style free-docking layout (split/tab/reorder any panel), persisted across launches. Any panel can be torn off into its own floating OS window by dragging its tab past the main window's edge, and merged back by dragging it back in — reusing the exact same drop-zone logic either way. Dedicated always-available windows: an Activity window (background job monitor), a Mini Player (always-on-top playback controller with the current subtitle line), a Project Dashboard (at-a-glance multi-tab overview with per-tab issue counts and a "save all" action), and a Shared Glossary window (cross-project term reference). The video panel can also be detached to a second monitor independently of the tear-off system.

**Data safety**
30-second autosave with multiple rotating backups, crash recovery on next launch, dirty-close confirmation, drag-and-drop file opening, a recent-files menu, and multi-document tabs (several open files/projects sharing one window).

## Requirements

- macOS 26 (Tahoe) or later — the app targets the current SwiftUI/Observation APIs and doesn't attempt to support older releases.
- [mpv](https://mpv.io/) (`brew install mpv`) for video/audio playback — the app runs and edits subtitles without it, but media playback is disabled until it's installed. The app's Settings screen offers to install it.
- [ffmpeg](https://ffmpeg.org/) (`brew install ffmpeg`) for burn-in review encoding and shot-change detection specifically — every other feature works without it.

## Building

The active codebase is the Swift package under [`native/`](native). (The repository also still contains an earlier Tauri + React + TypeScript implementation at the top level — see the note in [Project layout](#project-layout).)

```bash
git clone https://github.com/AHRI2nd/Glyphline.git
cd Glyphline/native
swift build              # debug build
swift test                # run the test suite (GlyphlineCore is fully unit-tested)
swift run Glyphline        # run the debug build directly
```

To produce a real, launchable `.app` bundle (the debug binary alone has no bundle, so macOS won't treat it as an app):

```bash
cd native
./scripts/release.sh                 # builds, assembles the .app, code-signs it
./scripts/release.sh --notarize      # ...and submits for notarization + staples the ticket
```

Code-signing uses a `Developer ID Application` certificate hardcoded in `scripts/release.sh` — to build your own signed copy, edit `SIGN_IDENTITY` (and `NOTARY_PROFILE`, if you also want to notarize) to match a certificate in your own keychain. Without a matching certificate, `codesign` will fail; you can still run the unsigned `.app` locally by clearing the quarantine attribute (`xattr -dr com.apple.quarantine <path>`) after copying it out of `.build/`.

Pass `--version=X.Y.Z` to stamp `CFBundleShortVersionString`/`CFBundleVersion` in the built `.app` (the release GitHub Actions workflow does this automatically from the pushed tag). This isn't just cosmetic: it's what [Sparkle](https://sparkle-project.org/) — the in-app auto-updater — compares against `appcast.xml` to detect a new release, so a build without a real version number will never show up as an update to anyone already running the app.

## Project layout

```
native/                         # ← the current app (Swift Package)
  Sources/
    GlyphlineCore/              # Pure, platform-agnostic core — fully unit-tested
      Model/                    #   SubtitleDocument, Cue, SyncToken, AssSpan, AssStyle, ...
      Formats/                  #   One adapter per format + the registry
      Core/                     #   Time/color/quality/QC/manifest/pairing logic
      Store/                    #   DocumentModel (undo/redo + editing actions)
      Platform/                 #   File I/O, encoding detection
    Glyphline/                  # The app — SwiftUI + AppKit where needed
      Media/                    #   mpv integration, waveform, transport
      Panels/                   #   Editing tools, batch/delivery panels, settings
      UI/                       #   Docking system, windows, cue grid
      Design/                   #   Design tokens
      Resources/                #   ko/en/ja .strings localization
  Tests/GlyphlineCoreTests/     # Swift Testing suite for GlyphlineCore
  scripts/                      # Release build, code-signing, icon generation

src/, src-tauri/                # Earlier Tauri 2 + React 19 + TypeScript implementation.
                                 # Kept as a reference spec and the source of the ported
                                 # test vectors during the native rewrite — not the
                                 # actively developed app.
```

## Testing

`GlyphlineCore` — the format adapters, timing math, quality checks, and delivery-pipeline logic — is covered by a Swift Testing suite (`swift test` from `native/`), including round-trip tests for every format adapter, hand-verified drop-frame timecode math, and cross-validated binary format tests (EBU-STL and SCC were checked against independent reference implementations — `pycaption`, `ffmpeg` — rather than trusted from memory, since a wrong byte in a binary broadcast format fails silently).

The app layer (SwiftUI views, AppKit/mpv/ffmpeg integration) is verified by building and running the app directly, since it depends on system frameworks and external processes that aren't practical to unit test. `GlyphlineUISmoke` automates the first slice of that: it launches a built `.app` and checks via the Accessibility API that a window actually appears and the menu bar built out, catching launch-time crashes and menu-wiring regressions without needing an Xcode project for real XCUITest.

```bash
swift run GlyphlineUISmoke [path/to/Glyphline.app]   # defaults to .build/Glyphline-release.app, then /Applications/Glyphline.app
```

Requires Accessibility permission for whatever runs it (System Settings → Privacy & Security → Accessibility) — a one-time, local grant, which is also why this isn't wired into CI.

## Why native, why macOS-only

Glyphline started as a Tauri 2 (Rust) + React app, chosen for cross-platform reach. In practice, the app is used almost exclusively on macOS — Windows and Linux already have mature, established subtitle editors — so the cross-platform value never materialized, while the cost stayed: a three-layer stack (TypeScript UI + Rust backend + a native video bridge glued into a WebView) fighting compositing and coordinate-space bugs the whole way. The rewrite to pure Swift/SwiftUI removes that entire class of problem and makes macOS-specific capabilities (system spell-checking, native menus, real multi-window support) straightforward instead of a fight.

## Roadmap / non-goals

Not currently planned: AI-based forced alignment / speech-to-text (e.g. embedding Whisper). Everything else in the feature tour above is implemented, not aspirational.

## Acknowledgments

Glyphline's playback is built on [mpv](https://mpv.io/) via libmpv's render API. Burn-in review encoding and shot-change detection use [ffmpeg](https://ffmpeg.org/). Cross-validation of the EBU-STL and SCC adapters used [pycaption](https://github.com/pbs/pycaption) as an independent reference.
