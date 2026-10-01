# DEXMA

A terminal that lives in your MacBook's notch.

Swipe down with two fingers from the top edge of the trackpad and the notch grows into
a full terminal, following your fingers. Let go and it settles into place. Swipe up, press
Esc, or press the shortcut again, and it shrinks back into the notch. Focus returns to the
app you were using. When closed, DEXMA is invisible.

- **Always ready:** one zsh starts when DEXMA launches and keeps running while the panel
  is closed. Your history, working directory and running jobs are still there next time.
- **Tabs:** *Terminal*, *Search* and *Claude*, in a Dynamic-Island-style pill left of the
  notch. Switch with <kbd>⌘</kbd><kbd>1</kbd>–<kbd>3</kbd>, <kbd>⌃</kbd><kbd>Tab</kbd>, a click,
  or by swiping sideways with two fingers (the pages follow your fingers). Right of the
  notch is the tab's context: the terminal's folder (with a green dot while a command
  runs), the page's site, and the tab's buttons. Dots under the card show where you are.
- **Search:** a field at the top of the card: type words to search Google, or an address to
  open it, and press Return. <kbd>⌘</kbd><kbd>L</kbd> jumps to the field. Back, forward and
  reload are <kbd>⌘</kbd><kbd>[</kbd>, <kbd>⌘</kbd><kbd>]</kbd>, <kbd>⌘</kbd><kbd>R</kbd>; Reset
  clears it. Nothing is loaded until your first search.
- **Claude:** claude.ai, loaded at launch so it's instant, and you stay signed in. Links to
  other sites open in your browser. <kbd>⌘</kbd><kbd>⇧</kbd><kbd>R</kbd> starts a new chat,
  <kbd>⌘</kbd><kbd>⇧</kbd><kbd>O</kbd> opens the conversation in your browser, and
  <kbd>⌘</kbd><kbd>L</kbd> lets you paste a link (handy for an email sign-in link). Page zoom
  is in Settings.
  Under the pointer, each tab and button turns into a small drop of liquid glass: it swells
  for a moment, then a gentle lens and highlight follow the pointer; it squashes when you
  press it (with a light tick), and the selection slides between tabs like a droplet.
- **Gesture or shortcut:** a two-finger swipe from the top edge of the trackpad, or
  <kbd>⌥</kbd><kbd>`</kbd> from anywhere (you can change the shortcut). Hovering over the
  notch makes it swell slightly; click to open.
- **Menu bar item:** open or close the terminal, Settings, the welcome screen, Launch at
  Login, and Quit. DEXMA has no Dock icon.
- **Screens without a notch** (external displays, or older Macs) show a small pill at the top
  of the screen instead.
- **Liquid motion:** while opening and closing, the notch moves like a liquid lens. It
  stretches with the motion and wobbles slightly when it lands. Its rim bends the content
  beneath it (the terminal or the Search page), and a soft highlight sweeps along it. If you allow Screen Recording, the real screen
  around the notch warps too, like the screen around the iPhone's Camera Control. Whatever
  is behind it gets pushed out as the notch grows and pulled in as it shrinks, with a colour
  split, and a small lens follows the pointer near the notch. Without the permission (on
  macOS 26), a thin Liquid Glass edge bends the screen instead. The effect only exists while
  the notch moves; at
  rest nothing changes and text stays crisp. The swipe gives Force Touch ticks when it passes
  the point of no return and when it lands. Set the strength in
  *Settings → Animation → Effect intensity* (it scales the tabs' and buttons' glass too); Off,
  or Reduce Motion, turns the lens effect off.

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
| **Screen Recording** (optional) | Bends the real screen around the notch. DEXMA captures only the area under its panel, never saves it, and only while the notch moves or the pointer is near it. macOS shows its recording indicator during that time. | A Liquid Glass edge bends the screen instead (macOS 26), or nothing on older macOS. |
| **Login Items** (optional) | *Launch at Login*, via `SMAppService`. macOS may ask you to approve it in System Settings → General → Login Items. | Start DEXMA yourself. |
| **Files and folders, etc.** (on demand) | Commands you run inside DEXMA's shell count as DEXMA to macOS. So when `ls ~/Desktop` touches a protected folder, macOS asks whether *DEXMA* may access it. | That command gets "Operation not permitted". |

Some things need no permission at all:
- Raw trackpad touches (through the private MultitouchSupport framework).
- The global shortcut (Carbon `RegisterEventHotKey`).
- Hover detection (mouse-moved monitors).

The welcome window, and the *Welcome & Permissions…* item in the menu bar, show whether
Accessibility is granted. They update as soon as you grant it, with no restart needed.

## Project layout

The app uses a feature-based MVVM layout (AppKit + SwiftUI), with one type per file.

- `DEXMA/App/`: the entry point, the app delegate, and `AppCoordinator`, which builds and
  connects everything at launch.
- `DEXMA/Core/`: shared building blocks with no UI: spring animation, notch geometry, the
  settings store, permissions, launch at login.
- `DEXMA/Features/`: one folder per feature: `Notch`, `Terminal`, `WebTab`, `Search`, `Gestures`,
  `LiquidMotion`, `ScreenWarp`, `HotKey`, `MenuBar`, `Settings` and `Onboarding`. Each is
  split into `Models/`, `ViewModels/`, `Views/` and `Services/` (and `Shaders/` for Metal),
  as far as it needs them.
- `DEXMA/Resources/`: the asset catalog with the app icon.
- `DEXMA/Debug/`: self-checks that only exist in Debug builds (`-selftest`, `-snapshot`,
  `-effecttest`, `-tabtest`, `-swipetest`, `-hovertest`, `-claudeprobe`, `-warptest`).
- `DEXMATests/`: unit tests (Swift Testing), in the same `Core/` and `Features/` folders:
  gesture recognition, geometry, the liquid effect, search addresses, shortcut recording,
  settings migration.
- `DEXMAUITests/`: Xcode's UI test template.
- `CLAUDE.md`: architecture notes, rules and a development log.
