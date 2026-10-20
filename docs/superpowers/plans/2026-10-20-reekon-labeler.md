# REEKON Labeler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An iPhone app that designs text labels on a true-size canvas and prints them on the REEKON P1L.

**Architecture:** A value-type `LabelDocument` in millimetres; a pure `LayoutEngine` (clamp, snap,
shrink-to-fit) shared by the editor and `LabelRenderer`, which draws a 1-bit `Bitmap` at 8 dots/mm. The
canvas shows that bitmap; `PrintJobEncoder` turns it into SDK print jobs, sent by `P1LPrinter` over
CoreBluetooth. Saved labels live in SwiftData as encoded documents.

**Tech Stack:** Swift 6, SwiftUI, Core Text, CoreBluetooth, SwiftData, Swift Testing, XCUITest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-19-reekon-labeler-design.md`

## Global Constraints

- iOS 26.0 deployment target, iOS 27 SDK, Swift 6, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- Bundle id `com.rydersdesign.ReekonLabeler`, team `ASH39KMW4S`, automatic signing.
- `Logger(subsystem: "tools.reekon.labeler", category: …)`, never `print`.
- 8 dots/mm; head 384 dots; presets 30 × 50 → 240 feed dots, 50 × 80 → 624 feed dots; custom `Int(feed × 8) − 16`.
- Header 1 `3a 5a 00 00 00 00 00 0a`; Header 2 `3a 30 hLo hHi lLo lHi 00 05`; 5 white rows; chunks 12 ms apart;
  gap 1.5 s (feed ≤ 30 mm) or 2.5 s.
- Every interaction ≤ 60 ms. Colours from asset/semantic tokens.

## Review Focus

1. Empty block text — must still have a one-line height and be selectable (`LayoutEngineTests.emptyTextHasLineHeight`).
2. Switching 50 × 80 → 30 × 50 with a block low on the label — block must be pulled back inside (`LayoutEngineTests.normalizeAfterSizeChangeKeepsBlocksInside`).
3. Bitmap width < 384 (custom narrow stock) — rows must pad on the right (`PrintJobEncoderTests.narrowBitmapPadsRightInset`).
4. Printer disconnects mid-job — print must fail with a visible error, not hang (manual, RC test plan).
5. A long unbroken word wider than the block — must wrap by character, not overflow (covered by the clamp test frame assertion).

---

### Task 1: Project scaffold, model and geometry (S1)

**Files:** `project.yml`; `ReekonLabeler/App/ReekonLabelerApp.swift`; `ReekonLabeler/Model/{LabelSize,LabelGeometry,TextBlock,LabelDocument,FontSpec}.swift`; `ReekonLabeler/Resources/Assets.xcassets`; tests `ReekonLabelerTests/LabelGeometryTests.swift`

**Produces:**
- `enum Orientation: String, Codable { case headNative, rotated }`
- `struct LabelSize: Codable, Hashable { headMM, feedMM: Double; feedDots: Int; static let small, large; static func custom(headMM:feedMM:); var headDots: Int }` (`headDots` = min(384, multiple of 8 ≤ head × 8))
- `struct LabelGeometry { init(size:orientation:); labelSizeMM: CGSize; printableRect: CGRect; bitmapWidth, bitmapHeight: Int; static let dotsPerMM = 8.0 }`
- `struct FontSpec: Codable, Hashable { family, face: String }`, `enum TextAlignmentOption { left, center, right }`
- `struct TextBlock: Codable, Hashable, Identifiable { id: UUID; text: String; originMM: CGPoint; widthMM: Double; font: FontSpec; pointSize: Double; alignment }`
- `enum GridStep: Double { off = 0, half = 0.5, one = 1, two = 2 }`; `struct LabelDocument { size, orientation, grid, blocks; var geometry }`

- [ ] Test: 30 × 50 head-native → label 50 × 30 mm, printable (1, 0, 48, 30), bitmap 384 × 240; 50 × 80 rotated → label 80 × 50, printable (0, 1, 78, 48), bitmap 624 × 384.
- [ ] Implement, `xcodegen generate`, run tests, commit.

### Task 2: Fonts, layout engine and renderer (S1 + S2 core)

**Files:** `ReekonLabeler/Rendering/{FontCatalog,Bitmap,LabelRenderer}.swift`; `ReekonLabeler/Layout/LayoutEngine.swift`; tests `LabelRendererTests.swift`, `LayoutEngineTests.swift`

**Produces:**
- `FontCatalog.ctFont(_ spec: FontSpec, pointSize: Double) -> CTFont`, `faces(for:) -> [FontFace]`, `favourites`, `allFamilies`
- `struct BlockLayout { frameMM: CGRect; effectivePointSize: Double }`
- `LayoutEngine.layout(_:in:) -> BlockLayout`, `moved(_:from:by:grid:in:) -> CGPoint`, `resizedWidth(_:from:by:grid:in:) -> Double`, `normalized(_ doc:) -> LabelDocument`
- `struct Bitmap { width, height; dots: [UInt8]; subscript(x:y:) -> Bool; inkCount(inDots:) -> Int; rotatedClockwise(); cgImage }`
- `LabelRenderer.render(_ doc:, layouts:) -> Bitmap`

Shrink-to-fit: binary search over 0.5 pt steps in [4, requested] for the largest size whose wrapped height ≤ printable.maxY − origin.y; at the floor, move the origin up. Snap, then clamp. Point → dots: `pt × 25.4 / 72 × 8`.

- [ ] Tests (spec names): `blockAtMillimetreOriginLandsOnExpectedDots`, `dragPastEdgeStopsAtPrintableEdge`, `overflowingTextShrinksToFit`; Review Focus 1, 2.
- [ ] Implement, run, commit.

### Task 3: Editor model with undo (S1 + S2)

**Files:** `ReekonLabeler/Editor/LabelEditor.swift`; test `LabelEditorTests.swift`

**Produces:** `@Observable final class LabelEditor { document; selectedID; bitmap; layouts; undoManager; libraryID; addBlock(); deleteSelected(); setText(_:for:); updateBlock(_:action:_:); beginGesture(); moveBlock(_:translationMM:); resizeBlock(_:deltaMM:); endGesture(action:); setSize; setOrientation; setGrid; load(_:libraryID:) }`. Every mutation normalises, re-renders and registers a whole-document undo snapshot.

- [ ] Test: `undoRestoresPositionAfterClampedDrag` (spec names it `LabelDocumentTests.…`; it lives on the editor, which owns undo).
- [ ] Implement, run, commit.

### Task 4: Editor UI (S1 + S2)

**Files:** `ReekonLabeler/Editor/{EditorScreen,CanvasView,BlockOverlay,InspectorView,FontPickerSheet,LabelSizeSheet}.swift`; `ReekonLabelerUITests/EditorUITests.swift`

Canvas: bitmap with `.interpolation(.none)`, hatched margins, grid dots, overlays. Tap = select and type; drag = move; right handle = width; pinch = size. Each block overlay exposes identifier `block-<index>` and value `<text>|ink:<count>`. "+ Text" button id `addTextButton`.

- [ ] UI test `addTwoBlocksAndTypeInEach`; run on the simulator; commit.

### Task 5: Print job encoder (S3)

**Files:** `ReekonLabeler/Printing/PrintJobEncoder.swift`; test `PrintJobEncoderTests.swift`

**Produces:** `struct PrintJob { header1, header2, data: [UInt8] }`; `PrintJobEncoder.encode(_ bitmap:) -> PrintJob`; `headBitmap(for doc:) -> Bitmap`.

- [ ] Tests: `matchesSDKFormat` (exact bytes in spec), `rotatedLabelIsHeadWide`, Review Focus 3.
- [ ] Implement (port of SDK Example 7), run, commit.

### Task 6: Sender and CoreBluetooth printer (S3)

**Files:** `ReekonLabeler/Printing/{PrintTransport,PrintSender,P1LPrinter,PrinterSheet}.swift`; test `P1LPrinterTests.swift`; Info.plist key `NSBluetoothAlwaysUsageDescription`.

**Produces:** `protocol PrintTransport: AnyObject { var maximumWriteLength: Int; func writeWithoutResponse(_:) async throws }`; `PrintSender.send(_ job:, feedMM:) async throws`; `PrintSender.cooldown(feedMM:) -> Duration`; `@Observable P1LPrinter { state; discovered; startScan(); connect(_:); forget(); print(_ doc:) async }`.

Scan with nil services; accept name containing "P1" with advertised service AE30 or AF30. Remember the peripheral UUID in UserDefaults. Wait for `peripheralIsReady(toSendWriteWithoutResponse:)` when `canSendWriteWithoutResponse` is false.

- [ ] Test `chunksArePacedAndSized` with a fake transport; implement; commit.

### Task 7: Label library (S4)

**Files:** `ReekonLabeler/Library/{SavedLabel,LabelLibrary,LibraryView}.swift`; test `LibraryTests.swift`

**Produces:** `@Model SavedLabel { id, name, modified, documentJSON, thumbnailPNG }`; `LabelLibrary(context:undoManager:) { save(_:name:id:) throws -> UUID; load(_:) throws -> LabelDocument?; delete(_:) throws; rename(_:to:) throws }`. Delete registers its own undo that re-inserts the record.

- [ ] Tests `saveThenReopenIsIdentical`, `deleteIsUndoable`; implement; commit.

### Task 8: Verify, review, install

- [ ] Full test run (`Executed N tests` line recorded); `codex review` of the branch; fix findings.
- [ ] Build for device and install on Ryder's iPhone with `xcrun devicectl device install app`.
