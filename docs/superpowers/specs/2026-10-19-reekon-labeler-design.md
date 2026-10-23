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

### S5 — Select several blocks and group them

Added 2026-10-20 on Ryder's request ("select text(s) with a tap and group them"). Rulings: multi-select via
a Select toggle; groups are lasting (saved with the label).

As Ryder, I turn on Select, tap blocks to pick several, group them, and then move, scale and delete the
group as one; Ungroup splits it again.

Acceptance:
1. A **Select** toggle in the toolbar. While on, each tap adds or removes a block from the selection and
   no keyboard appears. Turning it off returns to tap-to-type. Tapping empty canvas clears the selection.
2. With two or more blocks selected, **Group** joins them. The group is saved with the label.
3. Outside Select mode, tapping any member selects the whole group. A drag moves every member by the same
   amount, keeping their positions relative to each other; the drag stops when the group's outer edge meets
   the printable edge. Pinch, and the inspector's font, weight, size and alignment, apply to every selected
   block. The width handle shows only when a single ungrouped block is selected.
4. Double-tapping a member edits that member's text.
5. **Ungroup** splits the selected group. Delete removes every selected block. Both are undoable.

Named tests:
- `LabelEditorTests.groupMovesAsOneAndStopsAtEdge`: two grouped blocks 10 mm apart, dragged +100 mm, stay
  10 mm apart and the rightmost member's right edge is at the printable edge.
- `LabelEditorTests.deleteGroupIsUndoable`: delete a group, undo, and both blocks return with the same
  group.
- `EditorUITests.selectModeGroupsTwoBlocks`: add two blocks; in Select mode tap both and Group; Select off;
  tapping one block selects both (the Ungroup button appears).

Test plan (RC): group of three or more; group with blocks on both sides of the label; scaling a group until
a member shrinks to fit; groups after a label-size change; VoiceOver in Select mode.

### S6 — Rotate text 90°

Added 2026-10-20 on Ryder's request ("then rotate 90 deg"). Ruling: each tap turns a quarter turn
clockwise. This rotates the selected text, separately from the bottom bar's whole-label Rotate.

As Ryder, I rotate a block or a group a quarter turn at a time so text can run up or down the label.

Acceptance:
1. **Rotate 90°** in the inspector turns the selection clockwise: 0° → 90° → 180° → 270° → 0°. A group
   turns about its centre, so its layout turns with it.
2. A rotated block's footprint (its frame turned 90° when at 90° or 270°) stays inside the printable area.
   After a rotation the block or group is nudged back inside. Snapping and clamping apply to the footprint.
   Shrink-to-fit measures available space along the rotated text's height direction.
3. The canvas and the print show the rotated text, both from the same bitmap.
4. Labels saved before this story open unchanged (no rotation, no group).

Named tests:
- `LabelRendererTests.rotatedBlockPrintsSideways`: a one-line block at 90° renders ink whose bounding box
  is taller than it is wide, and every black dot lies inside the block's footprint.
- `LayoutEngineTests.rotatingNearEdgeStaysInside`: a wide block against the right edge, rotated 90°, has
  its footprint inside the printable area.
- `LibraryTests.labelSavedBeforeRotationStillOpens`: S4-era JSON (no `rotation` or `groupID` keys) decodes
  to blocks at 0° with no group.

Test plan (RC): 180° and 270° on paper; rotated multi-line and centred text; typing into a rotated block
(caret position); rotating a group larger than the label's short side; rotated blocks on a rotated label.

### S7 — Add a picture from Photos

Added 2026-10-20 on Ryder's request ("add pictures from phone, and rotate those as well"). Rulings:
dither by default with a per-picture line-art switch; pictures and text group together.

As Ryder, I add a picture from my photo library, place and scale it on the label, rotate it, and group it
with text; the print shows it in black-and-white dots.

Acceptance:
1. **+ Picture** opens the system photo picker (no photo-library permission prompt). The picture is added
   at the next free spot, selected, at most the printable width, keeping its proportions.
2. A picture keeps its proportions. A corner handle and pinch scale it, and it stays inside the printable
   area like text (snap and clamp apply).
3. Pictures are printed **dithered** (error diffusion at the final dot size), so greys become dot
   patterns. A per-picture **Line art** switch uses a hard black/white cut instead. A **Brightness** slider
   shifts both. The canvas shows exactly the dots that print.
4. Pictures rotate (S6), select, group with text, move, delete and undo (S5) like text blocks.
5. Saved labels keep their pictures. A picture is stored once, downscaled so its longer side is at most
   1024 px, in greyscale.

Named tests:
- `LabelRendererTests.ditheredGreyIsPartInk`: a uniform 60 %-brightness picture filling a frame prints
  25–55 % of that frame's dots black when dithered, and 0 % in line art.
- `LayoutEngineTests.pictureKeepsAspectWhenClamped`: a 2:1 picture scaled past the right edge stops at
  the printable edge, still 2:1.
- `LibraryTests.labelWithPictureRoundTrips`: a label with a picture and a text block saves and reopens
  unchanged, including the picture's pixels.

Test plan (RC): large HEIC and panorama photos (memory, time to add); transparent PNGs (transparency
prints white); very small pictures scaled up; a picture rotated in a group on paper; ≤ 60 ms interaction
while dragging a picture.

### S8 — Crop a picture

Added 2026-10-20 on Ryder's request (ruling: "crop in the app"). Split from S7 per §3a.

As Ryder, I crop a picture when I add it, and can re-crop it later.

Acceptance:
1. After a picture is picked, a crop screen shows it with a free-aspect crop rectangle (corner and edge
   handles, drag to move). **Done** adds the cropped picture; **Cancel** adds nothing.
2. **Crop** in the inspector reopens the crop screen for the selected picture. The full original is kept,
   so a later crop can widen again. Re-cropping keeps the picture's width on the label and refits it inside.
3. Re-crop is undoable.

Named tests:
- `ImageElementTests.cropPrintsOnlyCroppedPart`: a picture whose left half is black and right half white,
  cropped to its left half, prints every dot black inside its frame, and the frame is twice as tall as its
  width relative to the uncropped picture.
- `LabelEditorTests.recropIsUndoable`: re-crop, then undo, restores the previous crop rect and frame.

Test plan (RC): crop of a rotated picture; crop to a sliver (minimum 2 mm on the label); re-crop inside a
group.

### S9 — Every label lives in the library (autosave, empty state)

Added 2026-10-20 on Ryder's request. Rulings: "every label lives in library"; renaming from the library;
default name is the first line of text. Amends S4 acceptance 1 (explicit Save) by that ruling; S4 is
otherwise unchanged.

As Ryder, I never lose a label: every label I make is in the library, and an empty library tells me how
to start one.

Acceptance:
1. **New Label** (editor and library) creates a library entry at once; the editor's Save button is gone.
2. Every edit saves to that entry within 1 s of the last change (debounced), including the thumbnail.
   Reopening the app reopens the last label.
3. An unnamed label is listed under its first line of text ("Untitled" when it has none). A label renamed
   in the library keeps that name.
4. The empty library shows "No Labels" with a **New Label** button that opens a new label in the editor.

Named tests:
- `LibraryTests.editsSaveWithoutSave`: a new label's entry exists before any edit; after typing "SHELF A"
  and the debounce, the entry's document holds "SHELF A" and its listed name is "SHELF A".
- `LibraryTests.renamedNameSurvivesEdits`: rename to "Bins", edit the text, and the name stays "Bins".
- `LibraryUITests.testEmptyLibraryCreatesLabel`: open the empty library, tap New Label, type, reopen the
  library, and one label is listed.

Test plan (RC): app killed within the debounce window; many quick New Label taps leaving empty labels;
the label open in the editor deleted from the library; migrating the S4 working label into the library.

### S10 — Label folders by drag and drop

Added 2026-10-20 on Ryder's request. Ruling: delete asks each time ("Delete group, keep labels" or
"Delete group and labels"); both are undoable.

As Ryder, I drag one label onto another to put them in a folder, like the Home Screen, and delete the
folder when I am done with it.

Acceptance:
1. Dropping a label on another label makes a folder holding both, named "Folder" (renamable). Dropping a
   label on a folder adds it to that folder. Dragging a label out of an open folder returns it to the top.
2. Tapping a folder opens it and lists its labels; a folder emptied to one label stays a folder.
3. Deleting a folder asks: **Delete Folder, Keep Labels** (labels return to the top level) or
   **Delete Folder and Labels**. Either is undoable in one step.

Named tests:
- `LibraryTests.dropOnLabelMakesFolder`: dropping B on A leaves one folder holding A and B at the top level.
- `LibraryTests.deleteFolderKeepingLabelsIsUndoable`: delete keeping labels puts A and B at the top
  level; undo restores the folder with both.
- `LibraryTests.deleteFolderAndLabelsIsUndoable`: delete with labels removes all three; undo restores them.

Test plan (RC): drag performance with many labels; dropping a label on itself; folders inside folders
(not supported: dropping a folder on a label does nothing); VoiceOver alternative to drag ("Move to
Folder" in the context menu). Added at build: drag and drop on the device (the drop targets are untested by automation);
the "Drop here to move out of the folder" row and the "Move Out of Folder" menu inside a folder; the
delete dialog's swipe and context-menu paths; folder rename.

### S11 — Templates

Added 2026-10-20 on Ryder's request. Ruling: a template is a starting point copied on use. Moves
"templates" out of Later.

As Ryder, I save a label as a template and start new labels from it without changing the template.

Acceptance:
1. **Save as Template** in the editor stores a copy of the current label as a template, named like the
   label.
2. The library shows templates in their own **Templates** section above the labels.
3. Tapping a template creates a new library label from a copy (new ids) and opens it; editing it never
   changes the template. Templates can be renamed and deleted (undoable).

Named tests:
- `LibraryTests.labelFromTemplateLeavesTemplateUnchanged`: make a label from a template, edit its text,
  and the template's document is byte-for-byte unchanged.
- `LibraryTests.templateDeleteIsUndoable`: delete a template, undo, and it is back.

Test plan (RC): template with pictures (size); template whose fonts are gone; editing a template itself
(not supported in this story: replace it by saving a new one). Added at build: Save as Template sits in a long-press menu on the
bottom bar's New Label, because a title menu or another top-bar button collapses Add Text into the
overflow menu (seen in the UI test hierarchy); taste review of that placement and whether saving needs
visible confirmation; template rename.

### S12 — Text boxes fit their text

Added 2026-10-23 on Ryder's request ("the bounding box fits the type, not wildly extends it"). Ruling: auto
width.

As Ryder, I type a short word and its box is only as wide as the word.

Acceptance:
1. New text is **auto width**: its box hugs its longest line and grows as I type. It wraps only where the
   next character would leave the printable area.
2. Dragging the width handle switches that block to a fixed width that wraps, as today.
3. Labels saved before S12 keep their fixed widths.

Named tests:
- `LayoutTests.autoWidthHugsText`: "M6" at 14 pt lays out narrower than a quarter of the printable width,
  and as wide as the text's own line.
- `LayoutTests.autoWidthWrapsAtLabelEdge`: auto-width text longer than the label wraps inside the
  printable area.
- `LabelEditorTests.dragHandleFixesWidth`: after a width-handle drag the block is fixed width at the
  dragged width.

Test plan (RC): centre and right alignment of multi-line auto text; rotated auto text; Undo across the
switch to fixed width.

### S13 — Input and Adjust tools

Added 2026-10-23 on Ryder's request. Rulings: two tool dropdowns, Input first then Adjust; Move and Scale
both select; Scale resizes in proportion.

As Ryder, I pick what my finger does: make things (Type, Draw, Photo) or arrange them (Move, Scale).

Acceptance:
1. The top bar's Select, Add Picture and Add Text buttons are replaced by two menus, **Input** (Type, Draw,
   Photo) and **Adjust** (Move with a four-way arrow icon, Scale), each showing the current tool.
2. **Type:** tapping text edits it; tapping empty label adds a text block at the tap.
3. **Move:** tapping selects, and tapping more adds to the selection (Group appears for two or more). A
   drag moves the selection. The keyboard never opens.
4. **Scale:** selects like Move; a drag on the selection scales it in proportion (text point size, or
   picture or scribble width), kept on the label. Pinch still scales in every tool.
5. **Photo** opens Photos at once and returns to the previous tool.

Named tests:
- `LabelEditorTests.typeToolTapOnEmptyAddsTextThere`: in Type, a tap on empty label at (10, 8) mm adds
  text there and starts editing it.
- `LabelEditorTests.moveToolNeverEdits`: in Move, tapping a text block twice selects it and never edits.
- `LabelEditorTests.scaleDragGrowsText`: in Scale, a drag on a 14 pt block makes it larger, kept on the
  label.

Test plan (RC): tool menus with VoiceOver; switching tools mid-edit dismisses the keyboard; the existing
UI tests move to the tool menus.

### S14 — Draw scribbles

Added 2026-10-23 on Ryder's request ("scribble on a photo"). Rulings: strokes until a pause make one
scribble; scribbles can go anywhere on the label.

As Ryder, I draw with my finger on the label, over a photo or not, and the scribble prints.

Acceptance:
1. In **Draw**, a finger drag draws a black stroke. Strokes started within 1 s of the last one ending join
   the same scribble; after a pause the next stroke starts a new scribble.
2. A scribble is its own item: in Move or Scale it selects with a bounding box that fits its strokes, and
   it moves, scales, groups, rotates and deletes like a picture, staying on the label.
3. What the canvas shows is what prints, and scribbles save with the label. Undo removes the last stroke.

Named tests:
- `ScribbleTests.strokesWithinPauseJoinOneScribble`: two strokes 0.5 s apart make one scribble; a third
  2 s later makes a second.
- `ScribbleTests.scribbleBoxFitsStrokes`: a scribble's layout frame is its strokes' bounds plus the pen
  width, and it prints ink only inside that frame.
- `LibraryTests.scribbleRoundTrips`: a label with a scribble saves and reopens unchanged.

Test plan (RC): pen width on 203 dpi stock; drawing performance with long strokes; scribbles inside a
rotated group.

### S15 — Insert a template into a label

Added 2026-10-23 on Ryder's request ("a plus to insert a template"). Ruling: + adds the template's items
to the current label.

As Ryder, I tap + and pick a template, and its items land on the label I am working on.

Acceptance:
1. The top bar's **+** lists my templates. Picking one copies its items (new ids) into the current label
   as one group, selected, kept on the label. It is one Undo step.
2. With no templates, + says how to make one (Save as Template).

Named tests:
- `LabelEditorTests.insertTemplateAddsGroupedCopy`: inserting a two-block template adds two new elements,
  one group, selected; the template is unchanged.
- `LabelEditorTests.insertTemplateIsUndoable`: one Undo removes the inserted items.

Test plan (RC): a template from a bigger label size; inserting into a label that already has groups.

### S16 — White or yellow label stock

Added 2026-10-23 on Ryder's request. Ruling: per label, chosen in the size sheet.

As Ryder, I tell the app I loaded the yellow REEKON labels, and the canvas shows yellow.

Acceptance:
1. The label-size sheet offers **White** and **Yellow** stock. The canvas and the library thumbnail show
   that colour; the print is unchanged.
2. Each label keeps its colour; a new label uses the last colour chosen. Labels saved before S16 are
   white.

Named tests:
- `LibraryTests.stockColourRoundTrips`: a yellow label saves and reopens yellow; an S15 label decodes white.
- `LabelEditorTests.newLabelKeepsLastStockColour`: after choosing Yellow, New Label is yellow.

Test plan (RC): yellow against dark mode; thumbnail colour in the library.

### S17 — App icon

Added 2026-10-23 on Ryder's request: "[R]" on yellow, the R in Avenir Next.

Acceptance: the app icon shows "[R]" in Avenir Next on REEKON yellow, at every size iOS asks for.

Named tests: none (an asset). Evidence: the 1024 px icon image shown to Ryder, and the build on the phone.

## Later (not in this spec)

- **Tape-measure field**: connect to a T1/T1M/T1R (SDK Section I), insert the received or live measurement
  into a text block in the user's chosen unit. Needs its own spec.
- **Stock auto-detect spike**: log `0xAE02` notifications while swapping rolls; build detection only if the
  bytes reliably identify the stock.
- Other elements (QR/barcodes, icons, lines). (Templates moved to S11 on 2026-10-20.)

## Open questions

- Are the 1 mm head margins centred on a 50 mm label? (Verify on paper in the S3 RC pass.)
- What is the feed-axis printable length for custom sizes? (`length × 8 − 16` dots is an assumption.)
