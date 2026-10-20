# REEKON Labeler — design spec

Date: 2026-10-19 · Owner: Ryder · Status: **draft, awaiting review**
Source: `REEKON BLE SDK - Rev 1.5 - October 2026.pdf`, Section II (P1L printer); Section I (measuring tools) for later.

## Goal

An iPhone app that turns the REEKON P1L into a quick labeler. You type directly on a canvas that is the
size of the real label, place and size each text block, pick its font and weight, and print. What the
canvas shows is exactly what prints. Capturing measurements from the REEKON tape measure onto a label
comes later and is out of scope for this spec except where noted.

## Decisions made (2026-10-19)

| Topic | Ruling |
|---|---|
| Label size | User picks it: presets 30 × 50 mm and 50 × 80 mm, plus custom. The SDK gives no way to read the loaded stock; `0xAE02` status bytes are undocumented (see Later). The last choice is remembered. |
| Orientation | Rotate toggle. The canvas can show a label either way round; the app rotates the bitmap 90° before printing when needed. |
| Fonts | Curated favourites list plus "More…" for every installed family. |
| Persistence | Saved label library (story S4). |
| Layout guards | Multiple text blocks, snap to grid, nothing can leave the printable area. |
| Overflow | Text wraps within its block's width; if wrapped lines would pass the bottom edge, the font steps down until it fits. |
| Rendering | One Core Graphics renderer produces the 1-bit bitmap used for both the canvas and the print job. |

## Printer facts this design relies on (SDK Section II)

- Find: service `0xAE30` on iOS, name contains "P1". No manufacturer data, no pairing.
- Image: 1-bit, 384 dots (48 bytes) across the head, 8 dots/mm (203 dpi). 1 prints black, leftmost dot in bit 7.
- The label's 50 mm side runs across the head. 30 × 50 mm = 384 × 240 dots; 50 × 80 mm = 384 × 624 dots.
  A shorter image is fine: the printer feeds to the end of the label.
- Job = three writes to `0xAE01`, without response: Header 1 `3a 5a 00 00 00 00 00 0a`; Header 2
  `3a 30 hLo hHi lLo lHi 00 05` (height includes the 5 white rows; length = image data bytes); image data
  as row runs (`3c`, count u16, left inset, right inset, row bytes), identical rows merged, 5 white rows at
  the bottom.
- Chunks: `maximumWriteValueLength(for: .withoutResponse)` (fallback 180) about 12 ms apart.
- Wait 1.5 s after a 30 mm label and 2.5 s after a longer one before the next header. No cancel, no "printed" event.

## Geometry

All model coordinates are millimetres in **label space**: the label as the user sees it on the canvas,
origin top-left.

- **Head axis**: the label side that runs across the head (50 mm for both presets).
- **Feed axis**: the other side.
- **Printable area**: 48 mm on the head axis (384 dots), centred, so 1 mm on each side of a 50 mm
  label cannot print. On the feed axis it is the preset's dot count (240 → 30 mm, 624 → 78 mm), or
  `length × 8 − 16` dots for a custom size. The canvas shows the non-printable margins as a hatched band.
- **Orientation**: *head-native* puts the head axis horizontal (30 × 50 reads 50 wide × 30 tall);
  *rotated* puts the feed axis horizontal (50 × 80 reads 80 wide × 50 tall). The renderer draws in label
  space; the encoder rotates the bitmap 90° clockwise for a rotated label, so the head always receives 384-dot rows.
- **Custom sizes**: head axis ≤ 50 mm; narrower stock prints from the left edge of the head (SDK).
  Assumed alignment of narrower stock on the head is unverified (see Test plan).

## Architecture

XcodeGen `project.yml` → `ReekonLabeler.xcodeproj`. iOS 26.0 deployment target (Ryder's phone runs 26.6; amended 2026-10-20), built with the iOS 27 SDK, Swift 6 strict concurrency, SwiftUI,
Swift Testing for unit tests, XCTest UI tests. `Logger` (subsystem `tools.reekon.labeler`), never `print`.

```
ReekonLabeler/
  App/          ReekonLabelerApp, root navigation
  Model/        LabelDocument, TextBlock, LabelSize, Orientation, GridSetting (mm units)
  Layout/       LayoutEngine: clamping, snapping, shrink-to-fit (pure, no UIKit views)
  Rendering/    LabelRenderer: LabelDocument → 1-bit Bitmap (Core Text into an 8-bit gray context,
                antialiasing off, threshold 50%)
  Editor/       CanvasView, TextBlockOverlay, InspectorView, FontPicker
  Printing/     PrintJobEncoder (pure), P1LPrinter (CoreBluetooth), PrintTransport protocol
  Library/      SwiftData store, LibraryView
ReekonLabelerTests/    Swift Testing
ReekonLabelerUITests/  XCUITest
```

Unit boundaries:

- `LabelDocument` is a value type: size, orientation, grid, `[TextBlock]`. Edits go through the document
  and register with the window's `UndoManager`.
- `TextBlock`: id, text, origin (mm), width (mm), font family, face (weight), requested point size,
  alignment. Height is derived from layout, not stored.
- `LayoutEngine` answers three questions: where a dragged or resized block may go (clamped, then
  snapped), the effective point size for a block (shrink-to-fit), and the block's laid-out frame. The
  editor and the renderer both use it, so the canvas and the print use the same numbers.
- `LabelRenderer` draws the document at 8 dots/mm into a bitmap the size of the printable area. The
  canvas displays this bitmap scaled to the screen, with nearest-neighbour filtering.
- `PrintJobEncoder` turns a bitmap into `[header1, header2, data]`. It is a port of SDK Example 7.
- `P1LPrinter` scans, connects, discovers `AE30`/`AE01`, writes the job through `PrintTransport`, and
  enforces the gap between labels. A fake transport in tests records each write with its timestamp.

## Editor behaviour

- **Canvas**: the label, scaled to fit the screen width, with the printable area, hatched margins and
  (when the grid is on) grid dots.
- **Add block**: "+ Text" adds a block at the next free spot, selected and ready to type.
- **Type directly**: tapping a block shows an inline text field over it, matched to the block's frame
  and effective size. The rendered bitmap updates as you type.
- **Move**: drag a selected block. **Resize width**: drag its side handle. **Point size**: inspector
  stepper or slider; pinch on the block as a shortcut.
- **Select / delete**: tap to select; delete from the inspector or the keyboard toolbar. Tap empty
  canvas to deselect.
- **Inspector** (bottom sheet, grouped): font family (favourites: System, System Rounded, System Mono,
  Helvetica Neue, Avenir Next, Futura, DIN Alternate, Menlo; then "More…" with a searchable list of all
  families), weight (only the faces the family has), point size, alignment (left, centre, right).
- **Undo / redo** for add, delete, move, resize, text, font and size changes.
- **Performance**: every interaction presents in ≤ 60 ms; re-rendering a 384 × 640 bitmap per keystroke
  fits in that budget.

## Layout guards

- **Clamp**: a block's laid-out frame always stays inside the printable area. Dragging stops at the edge;
  resizing stops at the edge; a block cannot be narrower than 2 mm.
- **Snap**: grid on by default, step 1 mm (0.5 mm and 2 mm options), toggle in the toolbar. Drags and
  resizes snap the block's origin and right edge to grid lines. Snapping happens before clamping, so an
  edge snap never pushes a block out.
- **Shrink to fit**: text wraps within the block width. If the wrapped height would pass the bottom of
  the printable area, the effective size steps down in 0.5 pt steps until it fits (floor 4 pt). The
  inspector shows "24 pt (fits at 17)". The requested size is kept, so deleting text grows it back.
- **Label change**: switching size or orientation re-clamps and refits every block.

## Stories

Each story is one user-visible behaviour, with 2–3 named tests (§3a). Each has a test plan for the RC pass.

### S1 — Label canvas with multiple text blocks

As Ryder, I pick a label size and orientation, add several text blocks, type directly on the canvas, and
set each block's font, weight, size and alignment.

Acceptance:
1. The canvas has the chosen label's proportions; the printable area and margins are visible.
2. Two or more blocks can be added, each typed into and styled independently.
3. The canvas shows the renderer's bitmap, so on-screen text equals printed text.

Named tests:
- `LabelRendererTests.blockAtMillimetreOriginLandsOnExpectedDots` — for 30 × 50 head-native the bitmap is
  384 × 240; a block at label-space (5 mm, 3 mm) has its frame at dot (32, 24) (5 mm minus the 1 mm
  margin, × 8), and every black dot lies inside that frame.
- `EditorUITests.addTwoBlocksAndTypeInEach` — add two blocks, type "SHELF A" and "BOLTS", both labels'
  accessibility values report the text, and the bitmap is non-blank in both blocks' frames.

Test plan (RC): every favourite family renders at all of its weights; "More…" search; very long single
words; emoji and non-Latin scripts; VoiceOver on the canvas; iPad layout.

### S2 — Snap to grid and stay on the label

As Ryder, I move and resize blocks on a grid, and nothing I do can put text off the label.

Acceptance:
1. With the grid on, drags and resizes land on grid lines.
2. No drag, resize, keystroke, font change or label-size change leaves any part of a block outside the
   printable area; text that would overflow shrinks to fit.
3. Undo restores the block's exact previous position and size.

Named tests:
- `LayoutEngineTests.dragPastEdgeStopsAtPrintableEdge` — a drag of +100 mm puts the block's right edge
  exactly at the printable edge: 49 mm in label space on 50 mm stock (1 mm margin + 48 mm).
- `LayoutEngineTests.overflowingTextShrinksToFit` — text that wraps to five lines at 24 pt in a 30 mm-tall
  label gets an effective size whose laid-out height is ≤ the printable height.
- `LabelDocumentTests.undoRestoresPositionAfterClampedDrag` — move, then undo, gives the original origin.

Test plan (RC): snap at 0.5 / 2 mm; grid off; rotated orientation; switching from 50 × 80 to 30 × 50 with
blocks low on the label; pinch-resize near edges.

### S3 — Print to the P1L

As Ryder, I connect to my P1L and print the label on the canvas.

Acceptance:
1. The app finds a nearby P1L, connects without pairing, and remembers it for next time.
2. Print sends a job that matches the SDK format; the printed label matches the canvas.
3. A second print is held until the gap between labels has passed; the button shows that state.

Named tests:
- `PrintJobEncoderTests.matchesSDKFormat` — a 384 × 2 bitmap (one white row, one row with dots 0–7 black)
  encodes to Header 1 `3a 5a 00 00 00 00 00 0a`, Header 2 `3a 30 07 00 10 00 00 05`, and data
  `3c 01 00 30 00` `3c 01 00 00 2f ff` `3c 05 00 30 00` (the 5 added white rows merged into one run).
- `PrintJobEncoderTests.rotatedLabelIsHeadWide` — a rotated 50 × 80 document encodes with height 629
  (624 + 5) and every row run ≤ 48 bytes wide.
- `P1LPrinterTests.chunksArePacedAndSized` — with a fake transport reporting a 180-byte limit, every
  chunk is ≤ 180 bytes, chunks are ≥ 12 ms apart, and a second job waits ≥ 1.5 s.

Test plan (RC): real prints on 30 × 50 and 50 × 80 stock, head-native and rotated; printer off or out of
range mid-job; Bluetooth denied; app backgrounded mid-print; the 1 mm margin and narrower custom stock
alignment confirmed on paper.

### S4 — Label library

As Ryder, I save labels by name, reopen them, delete them, and reprint them.

Acceptance:
1. Save names and stores the current label; the library lists saved labels with a thumbnail.
2. Reopening a label restores it exactly; it can be edited and printed.
3. Delete can be undone.

Named tests:
- `LibraryTests.saveThenReopenIsIdentical` — a two-block document round-trips through SwiftData unchanged.
- `LibraryTests.deleteIsUndoable` — delete, then undo, restores the label.

Test plan (RC): rename; duplicate names; many labels (scroll performance); fonts no longer installed;
migration when the model changes.

## Later (not in this spec)

- **Tape-measure field**: connect to a T1/T1M/T1R (SDK Section I), insert the received or live measurement
  into a text block in the user's chosen unit. Needs its own spec.
- **Stock auto-detect spike**: log `0xAE02` notifications while swapping rolls; build detection only if the
  bytes reliably identify the stock.
- Other elements (QR/barcodes, icons, lines), templates.

## Open questions

- Are the 1 mm head margins centred on a 50 mm label? (Verify on paper in the S3 RC pass.)
- What is the feed-axis printable length for custom sizes? (`length × 8 − 16` dots is an assumption.)
