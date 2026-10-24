# REEKON Labeler — T1 Tomahawk tape measure (design spec)

Date: 2026-10-23 · Owner: Ryder · Status: **approved 2026-10-23** (Ryder: "start")
Source: `REEKON BLE SDK - Rev 1.5 - October 2026.pdf`, Section I (measuring tools), T1 firmware V1.2.6.
Parent: `2026-10-19-reekon-labeler-design.md`, Later → "Tape-measure field" ("Needs its own spec"). Ryder
2026-10-23: "can the app see the t1?" … "the tomahawk" … "add the spec now".

## Goal

Measure things with the T1 Tomahawk, pick the measurements in the app, and put them on the label as a little
table: a title row naming the thing, then one row per measurement (label + value), ready to print on the P1L.
Today the app sees only the printer: `P1LPrinter` keeps names containing "P1".

Ryder 2026-10-23: "i want to be able to select measurements and insert them onto the label in a little table.
header row with what it is, then a label + measurement. initially 2 rows. i should be able to add more, and if
its 3 measurements i'm selecting, it should infer it's l w d. and have 3 rows."

## Decisions made (2026-10-23, Ryder)

| Topic | Ruling |
|---|---|
| Header row | A title Ryder types, naming the thing measured (e.g. "Cabinet door"), across the top. |
| Table | A real table element: cells edit in place, rows can be added any time, it moves and scales as one. |
| On save | A measurement saved on the tool goes into the app's measurement list only. Nothing lands on the label by itself. Measurements saved before connecting are in the list too. |
| Row labels | 3 picked → L, W, D. 2 picked → L, W. 1, or 4 and up → blank labels to type. Fewer than 2 still gives 2 rows. Every label stays editable. |

## Proposed rulings (approved 2026-10-23, Ryder: "start")

| Topic | Proposal |
|---|---|
| Tools | T1 Tomahawk only (device_type 1). T1M and T1R are recognised and shown as "not supported yet" (Later). |
| UI | Input menu gains **Table** (an empty table) and **Tape** (the tape sheet), next to Photo. No new top-bar button. |
| Units | One app-wide unit, chosen in the tape sheet: **fractional inches** (default, nearest 1/16, `25 3/8"`), feet-inches (`2' 1 3/8"`), mm (`645 mm`), cm (`64.5 cm`). A value becomes cell text when inserted; changing the unit later does not rewrite tables already on labels. |
| List lifetime | The list lives while the app runs and is rebuilt on each connect (Request All). The tool keeps its own copies, so nothing is lost when the app closes. |
| Table look | Thin 1-dot lines around the table and between rows; the title row bold; labels left, values right; text size like Add Text and scaled with the table. |

## Tool facts this design relies on (SDK Section I)

- Find: scan for manufacturer data starting `F4 0D` (company 0x0DF4), then device_type (1 byte), device_id
  (8 bytes LE) — in the scan response, which iOS foreground scanning receives. Skip tools in Keyboard mode
  (advertise HID 0x1812 or name ends in "[HID]"). Recognise a tool by device_id, never by its address.
- Connect without pairing; one app at a time. The T1 disconnects and stops advertising ~3 min after its last
  use; a button press wakes it.
- Check the Sync Service `43744f76-de4d-4b05-a14a-0c133a785d8e` exists (else: "needs a firmware update in
  REEKON's app"). Protocol Version `2731f0a6-c56c-4da8-85bd-a586145ad952` reads 1 on the T1.
- Subscribe to notify (never indicate) on Comm `6f0b2d1e-99e2-4ef4-bfab-70a5f3890f32`, then write opcode 7
  (Request All: every saved measurement, then new ones as they are saved). iOS raises the MTU past the
  T1's 35 bytes on its own.
- Comm messages: opcode u32, data_len u32, data. T1 measurements are opcode 4, 24 bytes: uuid u32, flags u32,
  position_um i32 (final, as the tool showed it), zero_delta_um, active_offset_um, group_number u16 (0 =
  DEFAULT, n = GROUP n+1), measurement_number u16 (0 = A, 1 = B …).
- Repeats happen: identify a measurement by device_id + uuid. Ignore unknown opcodes. No message ends a sync.
- Do not touch the State Service's other characteristics or the update service (some force pairing).

## Architecture

- `Measuring/T1Protocol.swift` — pure parsing: advertising → `(deviceType, deviceID)` or nil; Comm message →
  `T1Measurement(uuid, flags, positionUM, group, letter)` or nil. No CoreBluetooth types, so it is unit-tested.
- `Measuring/T1Tape.swift` — `@Observable @MainActor` CoreBluetooth client with its own `CBCentralManager`
  (the printer keeps its own). States: off, unauthorised, searching, connecting, connected(name), needs
  update, failed(message). Remembers the chosen tool's device_id, reconnects when it advertises again, and
  owns the measurement list (newest first, repeats dropped).
- `Measuring/MeasurementFormat.swift` — `MeasurementUnit` and `format(positionUM:unit:) -> String`. Negative
  values (relative mode) keep their minus sign.
- `Measuring/TapeSheet.swift` — connect, unit, the list with checkmarks, **Insert Table**.
- `Model`: a new `LabelElement` content case, `.table(TableContent)` — `title: String`, `rows: [TableRow]`
  (`label`, `value`), font and size. Saved with the label like other content; labels saved before it decode
  unchanged.
- `LayoutEngine` and `LabelRenderer` lay out and draw the table, so the canvas and the print match.
- `LabelEditor`: `addTable(rows:)`, `addTableRow(to:)`, `setTableCell(...)`, and
  `TableContent.fromMeasurements(_:unit:)` for the L/W/D rule.
- `NSBluetoothAlwaysUsageDescription` becomes "Labeler uses Bluetooth to print on your REEKON P1L and read
  your REEKON tape measure."

## Stories

### S18 — Connect the T1 Tomahawk

As Ryder, I open Tape from the Input menu, see my T1, and connect to it; next time it reconnects by itself.

Acceptance:
1. The tape sheet lists T1 tools in range by name; T1M/T1R show "not supported yet"; a tool in Keyboard
   mode shows "switch it to APP mode".
2. Tapping a T1 connects and the sheet shows Connected with its name. A tool without the Sync Service shows
   the firmware-update message.
3. The chosen tool is remembered by device_id; when it wakes and advertises, the app reconnects without the
   sheet.

Named tests:
- `T1ProtocolTests.recognisesTomahawkAdvertising`: `F4 0D 01` + 8-byte id → type 1 and the id as 16 lowercase
  hex digits, most significant byte first; another company id → nil.
- `T1ProtocolTests.skipsKeyboardMode`: HID service 0x1812 or a name ending "[HID]" → not offered.

Test plan (RC): connect on the real T1; the 3-minute sleep, then a button press reconnects; Bluetooth off
and denied; the printer and the T1 connected at once.

### S19 — The measurement list

As Ryder, I see the measurements saved on my T1 in the tape sheet, including new ones the moment I save them.

Acceptance:
1. On connect, every measurement saved on the tool appears in the list, newest first, each with its value
   in my unit and its letter as the tool shows it (e.g. "A", or "Group 2 · B").
2. A measurement saved on the tool while connected appears at the top within 1 s.
3. A measurement appears once, however many times the tool sends it.

Named tests:
- `T1ProtocolTests.parsesLegacyMeasurement`: a 24-byte opcode-4 message → uuid, position, group, letter;
  shorter data or another opcode → nil.
- `MeasurementListTests.dropsRepeats`: the same uuid twice → one entry; entries newest first.

Test plan (RC): ten quick saves in a row (none lost or doubled); a tool with 50+ saved measurements;
measure-back and center-mode readings against the tool's screen.

### S20 — Table element

As Ryder, I add a little table to my label: a title row, then rows of label and measurement.

Acceptance:
1. Input → **Table** adds a table with a title row and 2 empty rows, selected, inside the label. One Undo
   removes it.
2. Tapping a cell edits it in place (Type tool). **Add Row** in the inspector adds an empty row at the
   bottom; it is one Undo step. The table stays inside the label (it shrinks to fit, like text).
3. Move, Scale, pinch, group and Rotate 90° treat the table as one item. It prints as the canvas shows.
4. A table survives save and reopen.

Named tests:
- `LabelEditorTests.addTableHasTitleAndTwoRows`: one table, 2 empty rows; one Undo removes it.
- `LabelEditorTests.addTableRowIsUndoable`: Add Row → 3 rows; one Undo → 2 rows.
- `LibraryTests.tableRoundTrips`: a table with title and 3 filled rows saves and reopens equal; a label saved
  before S20 still opens.

Test plan (RC): removing a row (not in this story; Later if needed); a table that outgrows a 30 × 50 mm
label; a rotated table; cell editing with the keyboard over the canvas; the print against the canvas.

### S21 — Insert picked measurements as a table

As Ryder, I tick measurements in the list and tap Insert Table, and they go on the label as rows.

Acceptance:
1. Insert Table adds a table (S20) with one row per ticked measurement, in the order ticked, values in my
   unit, title empty and ready to type. One Undo removes it.
2. Row labels: 3 ticked → L, W, D. 2 → L, W. 1, or 4 and up → blank. Fewer than 2 ticked still gives 2 rows.
3. The unit is chosen in the tape sheet (fractional inches by default) and remembered.

Named tests:
- `MeasurementFormatTests.formatsEachUnit`: 644,525 µm → `25 3/8"`, `2' 1 3/8"`, `645 mm`, `64.5 cm`;
  −12,700 µm → `-1/2"`.
- `TableContentTests.threeMeasurementsAreLWD`: 3 → labels L, W, D with formatted values; 2 → L, W.
- `TableContentTests.otherCountsHaveBlankLabels`: 1 → 2 rows, the second empty; 4 → 4 rows, all labels blank.

Test plan (RC): rounding at 1/16 edges (15/16 → next inch); a negative (relative) reading; insert with no
label open in the library; insert while a text block is being edited.

## Later (not in this spec)

- T1M and T1R (items, opcode 13+; drop the opcode-4 copy with the same uuid), laser and level readings.
- Live reading: insert the tape's current reading (poll Live Measurement every 200 ms).
- Remove a table row; reorder rows; more than two columns.
- Laser on/off from the app (opcode 11).
- Keeping the measurement list across app launches.

## Open questions

- Does Request All on the T1 keep sending newly saved measurements afterwards, as Request Unsynced does?
  (Device check in S19; if not, send opcode 5 after the sync goes quiet for 2 s.)
