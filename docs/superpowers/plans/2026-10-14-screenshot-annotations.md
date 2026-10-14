# Screenshot Annotation Implementation Plan

> Execute inline using superpowers:executing-plans. User approved the design and implementation on 2026-10-14.

**Goal:** Standard Mac screenshots appear in a persistent three-item shelf and can be annotated and copied.
**Architecture:** A dependency-free Swift package separates tested history/detection/annotation state and rendering from AppKit windows and filesystem monitoring. Source pixels are the coordinate system; editor zoom is a display transform only.
**Tech Stack:** Swift 5 language mode, macOS 13+, AppKit, SwiftUI shelf, ImageIO, Darwin extended attributes, XCTest.

## Tasks

- [x] 1. Package and core tests: `Package.swift`, `Tests/ParatoolCoreTests/CoreTests.swift`. Verify clipboard self-copy exclusion, highlight opacity, mosaic detail reduction, tag selection, newest-three ordering, duplicate removal, stable-file detection, startup baseline exclusion, undo/redo, coordinate mapping and opaque redaction output. Run `swift test` before implementation to expose missing types.
- [x] 2. Core: `Sources/ParatoolCore/History.swift`, `Annotation.swift`, `Renderer.swift`, `CaptureTracker.swift`. Implement bounded generic history, snapshot-based document undo, top-left pixel coordinates, shared canvas/export renderer, and stable-file candidate tracking. Run `swift test` and require all checks pass.
- [x] 3. Capture and shelf: `Sources/Paratool/CaptureWatcher.swift`, `Shelf.swift`, `AppDelegate.swift`, `main.swift`. Read screenshot preferences, monitor chosen directory, verify screenshot extended metadata, wait for complete images, ignore baseline/exports, handle inaccessible folders, maintain nonactivating bottom-left shelf and menu status. Persist chosen folder. Use lightweight polling to detect both writes and metadata arrival.
- [x] 4. Editor: `Sources/Paratool/Canvas.swift`, `Editor.swift`. Implement tools, swatches, widths, text entry, selection/moving/deletion, undo/redo, zoom/fit, PNG save and copy. Keep documents alive while in shelf or editor. Export at original pixel size with the common renderer, without selection outlines.
- [x] 5. Package: `scripts/build-app.sh`, `README.md`, `.gitignore`. Produce `dist/Paratool.app` with stable bundle ID, accessory activation policy and folder usage description. Document startup, macOS thumbnail delay, folder override and unsupported clipboard-only capture.
- [x] 6. Verify: Run `swift test`, build `.app`, validate its plist, launch smoke test and generate a deterministic preview using the actual editor/rendering path. Exercise screenshot metadata detection with a temporary fixture directory. Record any OS permission/GUI checks that cannot be automated. Review against every design requirement before reporting.

## Acceptance checks

```sh
swift test
./scripts/build-app.sh
plutil -lint dist/Paratool.app/Contents/Info.plist
open dist/Paratool.app
```

Expected: tests pass, release binary builds, plist is valid, menu-bar app stays alive. User subsequently requested disabling the native floating thumbnail; this Mac has show-thumbnail=false. README explains the setting on other Macs.

## Added GitHub distribution task

- [x] 7. `.github/workflows/ci.yml` builds/tests on macos-15 (arm64) and macos-15-intel. `.github/workflows/release.yml` builds version tags and attaches ZIPs plus checksums to a draft release. `scripts/package-release.sh` validates architecture and archives the app using ditto; the build script validates version inputs and signatures. Push to the connected repository, verify Actions runs, and prepare the first release draft for review.

## Local verification results

- Nine core tests pass, including stable-write detection, baseline/duplicate exclusion, bounded history, undo/redo, coordinate mapping, exact RGBA redaction and pixel dimensions.
- GUI smoke test passes using real filesystem writes and screenshot metadata. Four images result in three shelf cards; existing and ordinary images are excluded. Editor and exported PNG previews were visually inspected.
- Release app is ad hoc signed, plist/signature checks pass, ZIP structure and arm64 architecture verification pass.
- The execution environment cannot capture the real desktop (`screencapture` could not create an image), so interactive standard ⌘⇧4 and OS folder-permission prompts still require user-side confirmation. The watcher integration itself was exercised with synthetic screenshot files.

## Added interaction refinements

- [x] ClipboardTracker/ClipboardWatcher: initial/change-count/self-export exclusion with direct PNG/TIFF decoding.
- [x] Highlight, mosaic and numbered tag tools, shared preview/export rendering and tests.
- [x] Inline text creation, editing and cancellation using NSTextView; larger controls; shelf wrapper removed.
- [x] GitHub SDK compatibility: replace NSBitmapImageRep.getPixel (Int vs UInt depends on SDK) with direct byte assertions.
- [x] Verify v0.2.0 builds and release draft on GitHub after these refinements.

- ローカルGUI統合テスト: 名前付きペーストボードからの取り込み、自身のコピー除外、直接入力の確定・取消が成功。更新後のエディタと外枠なしサムネイルを画像で確認。

## Completed GitHub and installation verification

- v0.2.0 release workflow 38550756689 succeeded on arm64 and x86_64; both archives plus SHA256SUMS are attached to a draft release. main CI 38550747262 also passed.
- Downloaded both release ZIPs and verified their SHA-256 checksums. Installed the GitHub-built arm64 bundle into `/Applications/Paratool.app` and verified its signature and version 0.2.0.
- Added and exercised `scripts/install-local.sh --login`. The user LaunchAgent `app.paratool.login` points to the installed bundle, has RunAtLoad=true, and its launcher exited successfully. The installed app process is running.
- Reboot itself was not performed; launch registration and its immediate successful execution were verified.
