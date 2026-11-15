# Firmware notes

How K12Bar talks to the Keychron K12 (RGB, stock firmware V1.16), found by reverse engineering.

## Features

| Feature | Cable (USB) | Bluetooth |
| --- | --- | --- |
| Battery level in the menu bar | no | yes |
| Low battery notification (20%) | no | yes |
| Lighting: effect, color, rainbow, brightness, speed, direction | yes | no |
| Lighting presets | yes | no |
| Key remap (macOS side, this Mac only) | yes | yes |
| Launch at login | yes | yes |

Auto sleep, factory reset and the fn layers exist only as key combinations in the firmware; the app lists them under "Keyboard-only shortcuts".

## Why the split

- **Battery** is measured by the keyboard's Bluetooth module and sent as HID input report `0x03` (0 to 100). The main MCU never sees it, so it is not available over USB. macOS does not show it anywhere.
- **Lighting** uses the vendor protocol on a 64 byte HID feature report that exists only on the USB interface. The firmware has no path from the Bluetooth module to that protocol.
- The keyboard cannot report lighting changed with its own keys. The app shows the last lighting it wrote.

## How lighting is written

`K12Session.writeLEDZone` rewrites the 18 page LED zone in the keyboard's flash (`0x9340` to `0x97bf`) and then saves the settings. Only the first 12 bytes of the last page change; the rest is sent back as read. Each write is one flash write cycle, so changes are applied 0.4 s after the last edit: dragging a slider or the color wheel results in a single write.

Things the firmware does that the code relies on (found by reverse engineering, see comments in `K12Session.swift` and `K12Protocol.swift`):

- It programs every report received after the write command without validating it. If a transfer is interrupted the keyboard keeps waiting for pages; unplug and replug it.
- A page count of 0 is treated as 256 pages and would overwrite firmware code. The page count is fixed at 18.
- A feature report starting with `aa 42 89 5a ff 71 62 cc` enters the bootloader. The app never sends it.

The first LED zone read from a keyboard is kept at `~/Library/Application Support/K12Bar/led-zone-backup.bin`.

## Permissions

Input Monitoring (System Settings > Privacy & Security): macOS requires it to open a keyboard's HID device.

## Limits

- The keyboard uses USB IDs `05AC:024F`, which it borrows from Apple, so it is also matched by the product name "Keychron K12".
- Lighting is enabled only when the keyboard reports firmware V1.16. Other K12 variants (optical, white backlight) run different firmware that was not analysed.
- Effect names come from the vendor Windows software for this firmware family. Five were matched to mode numbers in USB captures of a K3 v2; that the K12 uses the same order is an assumption.
- Only the K12 RGB firmware V1.16 was analysed and tested.

## Build

```sh
xcodebuild -project K12Bar.xcodeproj -scheme K12Bar -configuration Release build
xcodebuild -project K12Bar.xcodeproj -scheme K12Bar test
```

Tests do not touch the keyboard.
