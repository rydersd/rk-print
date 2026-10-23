# rk-print

An iPhone app that turns the REEKON P1L Bluetooth label printer into a quick labeler. You design the label
on a canvas the size of the real label, and what the canvas shows is exactly what prints.

## What it does

- **Design on the label itself.** Add text blocks and type straight onto the canvas. Each block has its own
  font, weight, size and alignment. Text wraps within its block and steps down in size rather than run off
  the label.
- **Stay on the label.** Blocks snap to a grid (0.5, 1 or 2 mm, or off), and nothing can be moved or sized
  off the printable area.
- **Two tool menus.** Input (Type, Draw, Photo) makes things; Adjust (Move, Scale) arranges them. Text
  boxes fit their text.
- **Pictures.** Add a photo, crop it, and choose dithered or line-art rendering with a brightness control.
- **Scribbles.** Draw on the label with your finger. Strokes until you pause make one scribble, which you can
  move and scale like anything else.
- **Arrange.** Select several items, group them, and rotate an item or a group by 90°. Turn the whole label
  to work on it either way round. Undo and redo cover every edit.
- **Label sizes and colours.** 30 × 50 mm and 50 × 80 mm presets, or a custom size, on white or yellow stock.
- **Library.** Every label saves itself as you edit and is named after its first line of text until you
  rename it. Drag one label onto another to make a folder, the way you would on the Home Screen. Save any
  label as a template, start new labels from it, or add its items to the label you are on with **+**.
- **Print.** Finds the P1L over Bluetooth LE, with no pairing step, and prints the label as a 203 dpi
  black-and-white image.

## Requirements

- An iPhone on iOS 26 or later
- A REEKON P1L printer
- To build: Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Building

The Xcode project is generated from `project.yml` and is not checked in.

```sh
brew install xcodegen
xcodegen generate
open ReekonLabeler.xcodeproj
```

Choose your own development team under Signing & Capabilities, then run on an iPhone. Printing needs a
real device, because the simulator has no Bluetooth.

To run the tests:

```sh
xcodebuild test -project ReekonLabeler.xcodeproj -scheme ReekonLabeler \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Status

In active development. Planned next: capturing measurements from the REEKON tape measure onto a label.

## Not affiliated with REEKON

This is an independent project. It is not made, endorsed or supported by REEKON. "REEKON" and "P1L" are
used only to say which printer the app works with.
