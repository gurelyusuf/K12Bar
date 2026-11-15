# K12Bar

A macOS menu bar app for the Keychron K12 keyboard, which has no official Mac software.

- Battery level in the menu bar (Bluetooth)
- Lighting: effect, color, brightness, speed (USB cable, K12 RGB with firmware V1.16)
- Key remapping and launch at login

## Install

Requires macOS 14 or later.

1. Download `K12Bar.zip` from the [latest release](https://github.com/gurelyusuf/K12Bar/releases/latest) and unzip it.
2. Drag `K12Bar.app` into Applications and open it.
3. The app is not notarized by Apple, so macOS blocks the first launch. Open System Settings > Privacy & Security, scroll down and click **Open Anyway**.
4. Allow K12Bar under Privacy & Security > Input Monitoring, then open it again.

### Build from source

Needs Xcode. A locally built app is not blocked by macOS.

```sh
git clone https://github.com/gurelyusuf/K12Bar.git
cd K12Bar
xcodebuild -scheme K12Bar -configuration Release -derivedDataPath build build
cp -R build/Build/Products/Release/K12Bar.app /Applications/
```

## Notes

- Lighting changes are written to the keyboard's flash memory. If lighting stops responding, unplug the keyboard and plug it back in.
- Not affiliated with Keychron. Use at your own risk.
- How it works: [docs/firmware-notes.md](docs/firmware-notes.md)
