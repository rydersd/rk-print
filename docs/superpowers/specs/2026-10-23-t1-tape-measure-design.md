# REEKON Labeler — T1 Tomahawk tape measure (design spec)

Date: 2026-10-23 · Owner: Ryder · Status: **draft, awaiting review**
Source: `REEKON BLE SDK - Rev 1.5 - October 2026.pdf`, Section I (measuring tools), T1 firmware V1.2.6.
Parent: `2026-10-19-reekon-labeler-design.md`, Later → "Tape-measure field" ("Needs its own spec"). Ryder
2026-10-23: "can the app see the t1?" … "the tomahawk" … "add the spec now".

## Goal

Measure with the T1 Tomahawk, press its save button, and the measurement appears on the label as text in my
unit, ready to print on the P1L. Today the app sees only the printer: `P1LPrinter` keeps names containing "P1".

## Proposed rulings (need Ryder's yes)

| Topic | Proposal |
|---|---|
| Tools | T1 Tomahawk only (device_type 1). T1M and T1R are recognised and shown as "not supported yet" (Later). |
| Trigger | A measurement the user **saves on the tool while connected** goes on the label. The live reading is not used (Later). |
| Backlog | Measurements saved before connecting are not put on the label (they would flood it). |
| Where it lands | Editing a text block: appended to that block's text after a space. Otherwise: a new text block, placed like Add Text. One Undo step either way. |
| Units | One app-wide unit, chosen in the tape sheet: **fractional inches** (default, nearest 1/16, `25 3/8"`), feet-inches (`2' 1 3/8"`), mm (`645 mm`), cm (`64.5 cm`). |
| UI | A **Tape** item in the Input menu (next to Photo) opens the tape sheet: find, connect, unit, status. No new top-bar button. |

## Tool facts this design relies on (SDK Section I)

- Find: scan for manufacturer data starting `F4 0D` (company 0x0DF4), then device_type (1 byte), device_id
  (8 bytes LE) — in the scan response, which iOS foreground scanning receives. Skip tools in Keyboard mode
  (advertise HID 0x1812 or name ends in "[HID]"). Recognise a tool by device_id, never by its address.
- Connect without pairing; one app at a time. The T1 disconnects and stops advertising ~3 min after its last
  use; a button press wakes it.
- Check the Sync Service `43744f76-de4d-4b05-a14a-0c133a785d8e` exists (else: "needs a firmware update in
  REEKON's app"). Protocol Version `2731f0a6-c56c-4da8-85bd-a586145ad952` reads 1 on the T1.
- Subscribe to notify (never indicate) on Comm `6f0b2d1e-99e2-4ef4-bfab-70a5f3890f32`, then write opcode 5
  (Request Unsynced). iOS raises the MTU past the T1's 35 bytes on its own.
- Comm messages: opcode u32, data_len u32, data. T1 measurements are opcode 4, 24 bytes: uuid u32, flags u32
  (0x0001 SYNC = sent by a sync, clear when sent live), position_um i32 (final, as the tool showed it), …
- Repeats happen: identify a measurement by device_id + uuid. Ignore unknown opcodes.
- Do not touch the State Service's other characteristics or the update service (some force pairing).

## Architecture

- `Measuring/T1Tape.swift` — `@Observable @MainActor` CoreBluetooth client with its own `CBCentralManager`
  (the printer keeps its own). States: off, unauthorised, searching, connecting, connected(name), needs
  update, failed(message). Remembers the chosen tool's device_id and reconnects when it advertises again.
  Publishes each new live measurement once.
- `Measuring/T1Protocol.swift` — pure parsing: advertising → `(deviceType, deviceID)` or nil; Comm message →
  `T1Measurement(uuid, flags, positionUM)` or nil. No CoreBluetooth types, so it is unit-tested.
- `Measuring/MeasurementFormat.swift` — `MeasurementUnit` enum and `format(positionUM:unit:) -> String`.
  Negative values (relative mode) keep their minus sign.
- `Measuring/TapeSheet.swift` — the sheet. `LabelEditor.insertMeasurement(_ text: String)` does the edit.
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
and denied; the printer and the T1 connected at once, then printing while a measurement arrives.

### S19 — A saved measurement goes on the label

As Ryder, I press save on the T1 and the measurement appears on my label in my unit.

Acceptance:
1. While connected, each measurement saved on the tool appears on the label within 1 s: appended to the
   text block being edited, otherwise as a new text block. It is one Undo step.
2. It is written in the unit chosen in the tape sheet (fractional inches by default); the choice is
   remembered.
3. Measurements sent by the sync (SYNC flag) and repeats (same device_id + uuid) are not added.

Named tests:
- `MeasurementFormatTests.formatsEachUnit`: 644,525 µm → `25 3/8"`, `2' 1 3/8"`, `645 mm`, `64.5 cm`;
  −12,700 µm → `-1/2"`.
- `T1ProtocolTests.dropsSyncedAndRepeatedMeasurements`: a live opcode-4 message → one measurement with its
  position; the same uuid again → none; SYNC flag set → none; data shorter than 24 bytes → none.
- `LabelEditorTests.insertMeasurementIsOneUndoStep`: with nothing edited it adds one text block with the text;
  with a block being edited it appends; one Undo restores the label either way.

Test plan (RC): ten quick saves in a row (none lost or doubled); measure-back and center-mode readings
against the tool's screen; a reading arriving while dragging or with the crop open; rounding at 1/16 edges
(e.g. 15/16 → next inch).

## Later (not in this spec)

- T1M and T1R (items, opcode 13+; drop the opcode-4 copy with the same uuid), laser and level readings.
- Live reading: a button that inserts the tape's current reading (poll Live Measurement every 200 ms).
- Laser on/off from the app (opcode 11).
- Pulling the tool's saved backlog onto a label (Request All, opcode 7).

## Open questions

- Does the T1 send newly saved measurements without the opcode-5 request? (Device check in S18; we send it
  anyway, as the SDK says.)
