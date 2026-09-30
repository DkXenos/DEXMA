# DEXMA

A terminal that lives in your MacBook's notch.

Swipe down with two fingers from the top edge of the trackpad and the notch grows into
a full terminal, following your fingers. Let go and it settles into place. Swipe up, press
Esc, or press the shortcut again, and it shrinks back into the notch. Focus returns to the
app you were using. When closed, DEXMA is invisible.

- **Always ready:** one zsh starts when DEXMA launches and keeps running while the panel
  is closed. Your history, working directory and running jobs are still there next time.
- **Gesture or shortcut:** a two-finger swipe from the top edge of the trackpad, or
  <kbd>⌥</kbd><kbd>`</kbd> from anywhere (you can change the shortcut). Hovering over the
  notch makes it swell slightly; click to open.
- **Menu bar item:** open or close the terminal, Settings, the welcome screen, Launch at
  Login, and Quit. DEXMA has no Dock icon.
- **Screens without a notch** (external displays, or older Macs) show a small pill at the top
  of the screen instead.

## Requirements

- macOS 14 Sonoma or later.
- Apple silicon. Intel should build but is untested. A notch is optional.
- A Force Touch or Magic Trackpad for the swipe gesture. Without one, the keyboard shortcut,
  hover and menu bar item still work.
- To build it: Xcode 26 or later, plus the Metal Toolchain (SwiftTerm needs it).

## Building

```sh
git clone https://github.com/DkXenos/DEXMA.git
cd DEXMA
xcodebuild -downloadComponent MetalToolchain   # once per machine

# Debug build
xcodebuild -project DEXMA.xcodeproj -scheme DEXMA -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -skipPackagePluginValidation -skipMacroValidation build

# Unit tests
xcodebuild test -project DEXMA.xcodeproj -scheme DEXMA \
  -destination 'platform=macOS,arch=arm64' \
  -skipPackagePluginValidation -skipMacroValidation -only-testing:DEXMATests
```

You can also open `DEXMA.xcodeproj` in Xcode and run the `DEXMA` scheme. The first time,
Xcode asks you to trust SwiftTerm's build plugin. Swift packages resolve automatically:

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.20: terminal emulation and
  the terminal view.
- [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) 3.0.x: raw
  trackpad touches for the swipe gesture. Version 4 needs macOS 15, so it stays on 3.0.x.

For a Release build, use `-configuration Release`. The app ends up in
`DerivedData/…/Build/Products/Release/DEXMA.app`. To sign it with your own team, set
*Signing & Capabilities → Team* in Xcode.

DEXMA is not sandboxed, because it starts a real login shell with full access to your files.
Hardened Runtime is on.

## Permissions

DEXMA asks for as little as it can. Everything except scroll blocking works with no
permissions at all.

| Permission | Why | Without it |
| --- | --- | --- |
| **Accessibility** (optional) | A scroll-only event tap stops the window under your pointer from scrolling while you swipe the terminal open. It sees scroll events only, never keystrokes. | Everything works, but the page under your pointer may scroll a little during a swipe. |
| **Login Items** (optional) | *Launch at Login*, via `SMAppService`. macOS may ask you to approve it in System Settings → General → Login Items. | Start DEXMA yourself. |
| **Files and folders, etc.** (on demand) | Commands you run inside DEXMA's shell count as DEXMA to macOS. So when `ls ~/Desktop` touches a protected folder, macOS asks whether *DEXMA* may access it. | That command gets "Operation not permitted". |

Some things need no permission at all:
- Raw trackpad touches (through the private MultitouchSupport framework).
- The global shortcut (Carbon `RegisterEventHotKey`).
- Hover detection (mouse-moved monitors).

The welcome window, and the *Welcome & Permissions…* item in the menu bar, show whether
Accessibility is granted. They update as soon as you grant it, with no restart needed.

## Project layout

- `DEXMA/`: app sources (AppKit + SwiftUI, one type per file).
- `DEXMATests/`: unit tests (Swift Testing): gesture recognition, geometry, settings
  migration.
- `DEXMAUITests/`: Xcode's UI test template.
- `CLAUDE.md`: architecture notes, rules and a development log.
