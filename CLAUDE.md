# NotchTerm

A hidden terminal that lives in the MacBook notch. It must feel like a native macOS
feature (Notification Center, Dynamic Island) — smooth, instant, finger-driven — never
like a third-party app.

## Vision
- **Closed:** an invisible panel exactly matching the physical notch shape.
- **Trigger:** two-finger swipe DOWN starting at the top edge of the trackpad (raw touches
  via OpenMultitouchSupport). The panel follows finger progress 1:1, then settles with a
  velocity-aware spring on release. Global hotkey (default ⌥`) is the fallback.
- **Open:** the notch morphs into a wide terminal (SwiftTerm `LocalProcessTerminalView`)
  running a persistent zsh, spawned at app launch and never killed when the panel closes.
- **Close:** swipe up, Esc, or hotkey. Focus returns to the previously active app.

## Architecture — keep these separated
- `main.swift` — pure AppKit entry (no SwiftUI `App`): no default window, no Settings
  scene, no implicit main menu.
- `AppDelegate` — owns everything; builds and wires all objects at launch.
- `NotchGeometry` — notch rect from `NSScreen` (`auxiliaryTopLeftArea`/`auxiliaryTopRightArea`,
  `safeAreaInsets`); fallback size for non-notch screens; the panel's window frame.
- `NotchPanel` — borderless non-activating `NSPanel` above the menu bar; `canJoinAllSpaces`
  + `fullScreenAuxiliary` + `stationary`; transparent. Ordered in at launch, never ordered out.
- `NotchShape` (Phase 2) — SwiftUI `Shape` with animatable width/height/bottom corner radii.
- `PanelController` — single source of truth: `progress` (0 = notch, 1 = expanded) + state
  (closed/open; peek arrives in Phase 7). Hotkey and gesture both drive it.
- `SpringDriver` — advances `progress` with SwiftUI's `Spring` on the panel's `CADisplayLink`.
- `HotKey` — Carbon `RegisterEventHotKey` wrapper (needs no permissions).
- `NotchContentView` — SwiftUI root inside the panel; derives all geometry from `progress`.
- `TerminalHost` (Phase 3) — `NSViewRepresentable` wrapping ONE long-lived
  `LocalProcessTerminalView`. Never recreated.
- `GestureEngine` (Phases 5–6) — raw touches → progress; `CGEventTap` swallows scroll
  events while the gesture is active.

## Animation model
- `progress` is always the on-screen (presentation) value. `SpringDriver` steps it each
  display frame with `Spring.update(value:velocity:target:deltaTime:)`; nothing animates
  it with `withAnimation`. This is what lets a gesture grab the panel mid-flight and a
  release hand its velocity to the spring.
- Views derive every size/radius from `progress`; no implicit or explicit SwiftUI
  animations on anything derived from it.
- The display link is created once at launch and paused while the spring is at rest.

## Rules
- **Performance first.** No view recreation on open/close. No main-thread work during
  animation beyond the animation itself (spring step + shape re-render): no view
  creation, no process/IO work, no terminal layout. Pre-warm at launch (panel on screen,
  hosting view built, display link created, zsh spawned). The terminal view keeps a
  fixed frame and is clipped by the shape; never resize it per animation frame.
- **Don't guess third-party APIs.** Before using SwiftTerm or OpenMultitouchSupport, read
  their source in
  `~/Library/Developer/Xcode/DerivedData/terminal-application-*/SourcePackages/checkouts/`
  and use the real signatures. For Apple APIs, check the SDK headers/`.swiftinterface`
  when unsure.
- **Build after every change** and fix all errors AND warnings before saying you're done:
  `xcodebuild -project terminal-application.xcodeproj -scheme terminal-application -configuration Debug -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation build 2>&1 | grep -E 'warning:|error:|BUILD (SUCCEEDED|FAILED)'`
  (While the project's deployment target is above 14.0, also build once with
  `MACOSX_DEPLOYMENT_TARGET=14.0` appended to catch availability errors.)
- **Don't edit `project.pbxproj`** unless absolutely necessary. Adding/removing Swift files
  needs no project edit (the target uses a synchronized folder). For entitlements,
  Info.plist keys, build settings or packages: tell the user, they change it in Xcode.
- Small, focused files. Comment only the non-obvious parts (especially gesture math and
  window levels).
- Work in phases; stop after each so the user can test on real hardware. Don't start the
  next phase without an OK. Tick the phase below when it's done.

## Phases
- [x] 1. Notch panel + global hotkey (Carbon, default ⌥`) toggling open/close with a spring. Plain black rounded rect.
- [x] 2. NotchShape morphing from exact notch geometry to the expanded size.
- [x] 3. SwiftTerm persistent zsh inside the expanded panel.
- [x] 4. Focus: key window when open, Esc closes, restore previous app's focus.
- [x] 5. GestureEngine: two touches starting in the top ~10% of the trackpad moving down drive progress interactively.
- [x] 6. CGEventTap to swallow scroll during the gesture + Accessibility permission onboarding.
- [x] 7. Polish: release velocity, peek state, Reduce Motion, launch at login (SMAppService), multi-display.
- [ ] 8. Finished app: status item menu, Settings window, onboarding, gesture fallback, shell respawn, non-notch pill, app icon, Release build.

The user asked (2026-10-01) to run phases 2–8 without stopping between them: per phase, read
package sources, build to 0 errors/0 warnings, launch-check, `git commit -m "Phase N: …"`,
update Progress below.

## Progress
- **Project setup (done by Claude with the user's OK):** SwiftTerm 1.20.0 + OpenMultitouchSupport
  3.0.3 (4.x needs macOS 15), App Sandbox off, `LSUIElement`, macOS 14.0, product renamed
  `NotchTerm.app`. SwiftTerm needs the Metal Toolchain (installed via
  `xcodebuild -downloadComponent MetalToolchain`) and a build-plugin trust (Xcode asks once;
  CLI builds pass `-skipPackagePluginValidation -skipMacroValidation`).
- **Phase 1:** panel + ⌥` hotkey + display-link spring. Launch-checked (layer 26, frame centred
  on the notch). Unverified: animation feel, hotkey on hardware.
- **Phase 2:** `NotchShape` (animatable width/height/bottom radius/ear radius; concave ears
  flare into the top edge). Closed = notch size with 9 pt radius (a hair rounder than the
  physical notch so nothing peeks out). Launch-checked. Unverified: that the closed shape is
  truly invisible around the physical notch edge.
- **Phase 3:** `ShellSession` owns ONE `LocalProcessTerminalView` running `/bin/zsh` as a login
  shell (argv[0] `-zsh`), started at launch; respawned on exit (throttled to 1/s, screen reset
  with RIS). `TerminalContainerView` keeps the terminal at a fixed frame (`NotchGeometry.terminalFrame`)
  and clips it with a `CAShapeLayer` mask built from the same `NotchShape` each frame; text fades
  in over progress 0.35→0.85; the container is hidden while fully closed. Verified: zsh child
  process at launch, respawn after `kill -9`, no orphan shell after quit, and rendered
  snapshots (see *Debug snapshots*).
- **Phase 4:** the panel is non-activating and only `canBecomeKey` while open. `open()` records
  the frontmost app, makes the panel key and the terminal first responder — the other app
  stays frontmost (menu bar unchanged). `close()` calls `NSApp.deactivate()` first: verified
  that this drops key status immediately (re-`activate()`-ing the frontmost app alone did
  nothing until the animation ended). Esc closes unless a full-screen program (alternate screen:
  vim/less/htop) is running; ⌘C/⌘V/⌘A routed in `NotchPanel.performKeyEquivalent`; ⌘W closes;
  ⌘Q swallowed while the panel is key (would kill the shell); clicking another app closes the
  panel (resignKey). Verified with `-selftest` (key/first-responder/frontmost at each step).
  Unverified: real typing, IME, Esc and shortcuts on hardware.
- **Phase 5:** `GestureRecognizer` (pure, `nonisolated`, unit-tested: 10 tests incl. geometry)
  turns two-finger frames into began/changed(delta)/ended(velocity)/cancelled. Open = both
  fingers land in the top `edgeZone` and move down; close = panel open, terminal scrolled to
  the bottom and not in a full-screen program, fingers move up. Sideways, wrong-way and 3+
  fingers are ignored until all fingers lift. `delta` is added to the progress on screen when
  the fingers landed (grab mid-animation works), rubber-banded past 0/1; release projects
  ~0.2 s ahead with the finger velocity and hands that velocity to the spring.
  `GestureEngine` reads OpenMultitouchSupport's `touchDataStream` (states making/touching =
  in contact) on the main actor. Verified: multitouch device found and listening at launch
  (no permission needed). Unverified: **y orientation** (assumed y = 1 at the far/top edge,
  from MultitouchSupport's normalizedPosition; `GestureEngine.invertsY` flips it), feel of
  thresholds, real-finger accuracy.
- **Phase 6:** `ScrollBlocker` — active `CGEventTap` (scroll wheel only) on its own thread
  (a busy main thread must never delay system scrolling), reading a lock-protected
  `ScrollGate`. Swallows continuous (trackpad) scroll while the recognizer is capturing
  (armed in the edge zone, or tracking), plus momentum for 0.6 s after a completed swipe;
  re-enables itself if macOS times the tap out. Without Accessibility it polls
  `AXIsProcessTrusted` every 1.5 s and starts by itself when granted (no relaunch).
  `Onboarding.swift`: first-run window (gesture + hotkey how-to, why Accessibility, button that
  prompts and opens the Privacy_Accessibility pane, live "Granted" status). Only Done/close
  marks it seen (`didShowOnboarding`), not quitting. Verified: tap created when trusted, waits
  when not (log: `Launched. Multitouch gestures: on; scroll blocking: …`), onboarding shows on
  first run. Unverified: that scroll is actually swallowed during a real swipe; permission
  grant flow end-to-end.
- **Testing gotchas:** launching the binary from a shell inherits the terminal's Accessibility
  grant (TCC "responsible process") — use `open`/LaunchServices to see the real state. The app
  is unsandboxed, so its prefs are `~/Library/Preferences/com.jasontio.terminal-application.plist`;
  plain `defaults` reads the stale sandbox container from the old template — pass the plist path.
  zsh's `log` is a builtin: use `/usr/bin/log show --predicate 'subsystem == "com.jasontio.terminal-application"'`.
  `cacheDisplay` can't render SwiftUI text, so `-snapshot` only covers the panel.
- **Phase 7:** `AppSettings` (@Observable, UserDefaults, `onChange` → `AppDelegate.applySettings`
  re-applies everything live). Release velocity feeds the spring (Phase 5). **Peek**:
  `HoverMonitor` (global + local mouse-moved monitors, no permission) → pointer over the notch
  swells it to progress 0.06 and makes it clickable; click opens. **Reduce Motion**: 0.2 s
  springs without bounce. **Launch at login**: `LoginItem` (SMAppService.mainApp; opens Login
  Items settings if approval is required). **Multi-display**: `DisplayChoice` notched (default)
  or pointer — geometry is re-resolved right before opening from fully closed, so the panel
  moves while invisible; panel size is clamped to the screen. Verified: `-selftest` peek →
  0.06 & clickable → closed & click-through; 11 unit tests (incl. pill geometry). Unverified:
  hover feel, Reduce Motion, login item registration (not exercised to avoid touching the
  user's login items), opening on an external display.

## Debug snapshots
Screen Recording isn't granted to the CLI, but an app can render its own window. Debug builds
accept `-selftest` (open/close via the controller, printing key window, first responder and
frontmost app at each step) and `-snapshot <dir>`: they type `ls /` into the shell, render the panel at progress
0/0.15/0.5/1 to PNGs, and quit. Run the binary directly:
`.../Debug/NotchTerm.app/Contents/MacOS/NotchTerm -snapshot /tmp/snap`, then view the PNGs.

## Project facts
- Xcode 26.2, Swift 6.2 compiler in Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION =
  MainActor` + approachable concurrency: everything is `@MainActor` unless marked
  `nonisolated`. C callbacks (Carbon, CGEventTap, multitouch) must be `nonisolated`
  functions; hop with `MainActor.assumeIsolated` only when the callback is known to arrive
  on the main thread.
- Target/scheme `terminal-application`; sources in `terminal-application/`.
- Intended settings (the user owns these in Xcode): deployment target macOS 14.0,
  `LSUIElement` = YES, App Sandbox OFF, Hardened Runtime ON, SPM packages SwiftTerm +
  OpenMultitouchSupport. Check with `xcodebuild -showBuildSettings` if behaviour looks off.
- Reference hardware: 14" MacBook Pro, built-in display 1512×982 pt @2x, 120 Hz; notch
  185×32 pt (left aux 665 pt, right aux 662 pt — not exactly centered). An external
  2560×1440 display (no notch) is usually the PRIMARY screen.
- Window layers (macOS 26): menu bar 24, status items/Control Center 25, pop-up menus 101.

## AppKit pitfalls
- `NSPanel.hidesOnDeactivate` defaults to true — must be false in an agent app.
- Override `constrainFrameRect(_:to:)` or AppKit may push the panel below the menu bar.
- `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` are in global screen coordinates and are
  `nil` on screens without a notch.
- `NSScreen.main` is the screen with the key window, not the notched one — pick screens
  explicitly.
- `NSHostingView.sizingOptions = []`, or SwiftUI's changing ideal size resizes the panel.
- An agent app with no main menu has no Edit menu, so ⌘C/⌘V don't reach a first
  responder by default — SwiftTerm has `@objc copy:/paste:` but no `performKeyEquivalent`.
- SwiftTerm's `keyDown` is `public`, not `open`: intercept keys in the window's `sendEvent`.
- In `NSViewRepresentable.updateNSView`, touch only layers. Setting `isHidden`/`alphaValue`
  there caused SwiftUI "AttributeGraph: cycle detected" warnings at runtime.
- While a non-activating panel is key, `NSApp.isActive` is true; `NSApp.deactivate()` is what
  hands the keyboard back.
