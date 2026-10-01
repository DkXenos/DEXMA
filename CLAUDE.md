# DEXMA

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
- `main.swift` — pure AppKit entry (no SwiftUI `App`): no default window or Settings scene.
  Runs `DefaultsMigration` (settings from the old `com.jasontio.terminal-application`
  domain) before anything reads UserDefaults.
- Naming: `Notch*` types (`NotchPanel`, `NotchShape`, `NotchGeometry`, `NotchContentView`)
  are named after the hardware notch, not the app — they are not leftovers of the old
  "NotchTerm" name.
- `AppDelegate` — owns everything; builds and wires all objects at launch; applies
  `AppSettings` live; picks the screen (`DisplayChoice`).
- `NotchGeometry` — notch rect from `NSScreen` (`auxiliaryTopLeftArea`/`auxiliaryTopRightArea`,
  `safeAreaInsets`); fallback size for non-notch screens; the panel's window frame.
- `NotchPanel` — borderless non-activating `NSPanel` above the menu bar; `canJoinAllSpaces`
  + `fullScreenAuxiliary` + `stationary`; transparent. Ordered in at launch, never ordered out.
- `NotchShape` — SwiftUI `Shape` with animatable width/height/bottom radius/ear radius.
- `PanelController` — single source of truth: `progress` (0 = notch, 1 = expanded) + state
  (closed/peek/open). Hotkey, gesture, hover and the menu bar item all drive it; owns focus.
- `SpringDriver` — advances `progress` with SwiftUI's `Spring` on the panel's `CADisplayLink`.
- `HotKey` — Carbon `RegisterEventHotKey` wrapper (needs no permissions).
- `NotchContentView` — SwiftUI root inside the panel; derives all geometry from `progress`.
- `ShellSession` — ONE long-lived `LocalProcessTerminalView` + zsh (respawned on exit);
  `TerminalContainerView` masks it to the shape. `TerminalHost` — the `NSViewRepresentable`
  that hands that same view to SwiftUI. Never recreated.
- `GestureRecognizer` (pure, unit-tested) + `GestureEngine` (OpenMultitouchSupport frames →
  recognizer → controller). `ScrollBlocker`/`ScrollGate` — `CGEventTap` on its own thread
  swallowing scroll during a swipe. `AccessibilityPermission` — live AX trust.
- `HoverMonitor` — pointer over the notch → peek. `AppSettings`/`KeyCombo` — UserDefaults.
- UI: `StatusItemController` (menu bar item; also `MainMenu`), `SettingsWindow`
  (`SettingsView`, `TrackpadPreview`, `ShortcutRecorder`), `Onboarding`, `LoginItem`.
- Liquid effect (only while moving): `EffectTuning` (every constant + `scaled(by:)` for the
  Settings "Effect intensity" slider), `MotionEffects` (@Observable per-frame state: jelly
  stretch/wobble, energy, anticipation bulge; stepped by `SpringDriver.onFrame`),
  `LiquidMotionLayer` + `LiquidEffects.metal` (SwiftUI `distortionEffect` stretch and
  `layerEffect` lens/aberration/light over the terminal snapshot), `TerminalSnapshot`
  (pixel-exact picture of the live terminal), `Haptics` (`NSHapticFeedbackManager` ticks),
  `BackdropLens` (macOS 26: a clear `NSGlassEffectView` ring behind the silhouette, so the
  window server bends the desktop/apps behind the notch — no capture, no permission) inside
  `PanelContentView` (the panel's flipped content view: glass below, `NSHostingView` above).
- `DebugSnapshot` — DEBUG-only `-selftest` / `-snapshot <dir>` / `-forcePill` hooks;
  `EffectTest` — DEBUG-only `-effecttest <dir>` (see *Debug snapshots*).

## Animation model
- `progress` is always the on-screen (presentation) value. `SpringDriver` steps it each
  display frame with `Spring.update(value:velocity:target:deltaTime:)`; nothing animates
  it with `withAnimation`. This is what lets a gesture grab the panel mid-flight and a
  release hand its velocity to the spring.
- Views derive every size/radius from `progress`; no implicit or explicit SwiftUI
  animations on anything derived from it.
- The display link is created once at launch and paused while the spring is at rest.
- Liquid effect: `SpringDriver.onFrame` steps `MotionEffects` on the same display link and
  keeps it running until every effect value is *exactly* zero (then the link pauses). The
  black silhouette is always the same vector `shape.fill` — squash/stretch/bulge only scale
  `NotchShape`'s width/height about the top centre (`Frame.scale`, exactly 1 × 1 at rest).
  Shaders touch only the content: while moving, `LiquidMotionLayer` shows a `TerminalSnapshot`
  (the live terminal's mask opacity goes to 0 — never `isHidden`, which would drop first
  responder), bent by the shaders and clipped to the silhouette. At rest the motion layer is
  transparent with `isEnabled: false`. The only thing ever swapped is the text, in one
  SwiftUI update. Snapshots are taken while idle (0.5 s after the last output/input/scroll),
  so `open`/`close` normally do no capture. Reduce Motion or intensity Off → the effect is
  skipped entirely and the old path runs unchanged.
- Screen bending (macOS 26): `PanelController.updateBackdrop` sizes the `BackdropLens` glass
  each effect frame — silhouette + `EffectTuning.backdropRing` × (energy peaking mid-way, or
  the anticipation swell), extended above the window so only its bottom corners show. Under
  ¼ pt it's hidden (not rendered), so at rest nothing changes. Warmed at launch behind the
  closed notch. The user chose this over ScreenCaptureKit (2026-10-01).

## Rules
- **Performance first.** No view recreation on open/close. No main-thread work during
  animation beyond the animation itself (spring step + shape re-render): no view
  creation, no process/IO work, no terminal layout. Pre-warm at launch (panel on screen,
  hosting view built, display link created, zsh spawned). The terminal view keeps a
  fixed frame and is clipped by the shape; never resize it per animation frame.
- **Don't guess third-party APIs.** Before using SwiftTerm or OpenMultitouchSupport, read
  their source in
  `~/Library/Developer/Xcode/DerivedData/DEXMA-*/SourcePackages/checkouts/`
  and use the real signatures. For Apple APIs, check the SDK headers/`.swiftinterface`
  when unsure.
- **Build after every change** and fix all errors AND warnings before saying you're done:
  `xcodebuild -project DEXMA.xcodeproj -scheme DEXMA -configuration Debug -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation build 2>&1 | grep -E 'warning:|error:|BUILD (SUCCEEDED|FAILED)'`
  (While the project's deployment target is above 14.0, also build once with
  `MACOSX_DEPLOYMENT_TARGET=14.0` appended to catch availability errors.)
- **Don't edit `project.pbxproj`** unless absolutely necessary. Adding/removing Swift files
  needs no project edit (the target uses a synchronized folder). For entitlements,
  Info.plist keys, build settings or packages: tell the user, they change it in Xcode.
  (Exception on record: the user OK'd Claude's one pbxproj edit for packages/settings/name.)
- Unit tests: `xcodebuild test … -only-testing:DEXMATests` (Swift Testing).
- Small, focused files. Comment only the non-obvious parts (especially gesture math and
  window levels).
- Work in phases and tick them below. (Phases 2–8 were run back to back at the user's
  request; new work: ask whether to stop between steps.)

## Phases
- [x] 1. Notch panel + global hotkey (Carbon, default ⌥`) toggling open/close with a spring. Plain black rounded rect.
- [x] 2. NotchShape morphing from exact notch geometry to the expanded size.
- [x] 3. SwiftTerm persistent zsh inside the expanded panel.
- [x] 4. Focus: key window when open, Esc closes, restore previous app's focus.
- [x] 5. GestureEngine: two touches starting in the top ~10% of the trackpad moving down drive progress interactively.
- [x] 6. CGEventTap to swallow scroll during the gesture + Accessibility permission onboarding.
- [x] 7. Polish: release velocity, peek state, Reduce Motion, launch at login (SMAppService), multi-display.
- [x] 8. Finished app: status item menu, Settings window, onboarding, gesture fallback, shell respawn, non-notch pill, app icon, Release build.
- [x] 9. Rename NotchTerm / terminal-application → DEXMA (branch `refactor/dexma`).
- [x] 10. Liquid lens effect while opening/closing + haptics (branch `feature/distortion`,
  not merged: the user tests the feel first).

The user asked (2026-10-01) to run phases 2–8 without stopping between them: per phase, read
package sources, build to 0 errors/0 warnings, launch-check, `git commit -m "Phase N: …"`,
update Progress below.

## Progress
- **Project setup (done by Claude with the user's OK):** SwiftTerm 1.20.0 + OpenMultitouchSupport
  3.0.3 (4.x needs macOS 15), App Sandbox off, `LSUIElement`, macOS 14.0, product renamed
  (first `NotchTerm.app`, now `DEXMA.app`). SwiftTerm needs the Metal Toolchain (installed via
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
  is unsandboxed, so its prefs are `~/Library/Preferences/<bundle id>.plist`;
  plain `defaults` reads the stale sandbox container from the old template — pass the plist path.
  zsh's `log` is a builtin: use `/usr/bin/log show --predicate 'subsystem == "<bundle id>"'`.
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
- **Phase 8:** menu bar item (notch glyph, template) with Open/Close Terminal (shows the
  shortcut), Settings… (⌘,), Welcome & Permissions…, Launch at Login ✓, Quit. Settings
  window (grouped Form): shortcut recorder (unregisters the global hotkey while recording;
  warns if Carbon refuses a combo), login item, screen choice, Esc/focus-loss/peek toggles,
  panel width/height, animation speed/bounciness, gesture on/off, start zone, swipe distance,
  live trackpad preview (touch dots + shaded start zone), flip-Y escape hatch, scroll-blocking
  status. Small main menu (About/Settings/Quit, Edit, Window) for those windows. Gesture
  fallback: no multitouch → engine stays off, Settings says so, hotkey/hover/menu still work.
  Non-notch screens show a visible 150×26 pill (verified by snapshot with `-forcePill`). App
  icon generated by a CoreGraphics script (graphite squircle, black notch, green `>_`).
  Release build: `build/DEXMA.app` (Apple Development-signed, hardened runtime,
  multitouch framework embedded), launch-checked via LaunchServices. Verified: selftest
  (settings change resizes panel live 760→880, hotkey re-registers, Settings + status item
  windows exist), 11 unit tests, 0 warnings Debug/Release/tests.
- **Still unverified (needs the user on hardware):** see the final checklist given to the user
  on 2026-10-01 — animation feel, closed-notch invisibility, gesture direction/thresholds,
  scroll swallowing, focus/typing/IME/Esc, Spaces/full screen, external displays, login item,
  Accessibility grant flow, Settings/Welcome visuals (SwiftUI can't be snapshotted here).
- **Rename to DEXMA:** folders, xcodeproj, targets, scheme, product (`DEXMA.app`, module
  `DEXMA`), UI copy, `TERM_PROGRAM=DEXMA`, log fallbacks. Bundle id unchanged (see Project
  facts). Verified: 13 unit tests, selftest identical, `-snapshot` PNGs byte-identical to
  the NotchTerm build. Note: `-snapshot` renders the terminal container hidden (never
  un-hidden by `debugJump`), so it shows the shape only, not text.
- **Phase 10 (liquid effect):** see *Animation model*. Findings that shaped it: SwiftTerm
  draws with CoreGraphics (its Metal renderer is opt-in, off), so `cacheDisplay` works — but
  it misses the caret (a `CALayerDelegate`-drawn subview) and the overlay scroller knob (a
  sublayer with a background colour and a NaN corner radius); `TerminalSnapshot` adds both.
  Pushing the black silhouette through a SwiftUI shader re-rasterises its curved edges
  (single edge pixels off by up to 65/255), so the silhouette stays out of the shaders.
  SwiftUI skips a layer effect whose content is fully transparent, hence the 0.004-alpha
  black base in the motion layer. Measured with `-effecttest` (Debug, built-in display at
  120 Hz): snapshot vs window server 0 px differ (>2/255); motion layer vs live at rest 0 px
  (open and closed); real swap-back converges to the live frame with no in-between frame;
  0 late frames over 6 open/close cycles with the effect on (same as off), main-thread p95
  ≈ 2.5 ms per frame; snapshot capture ≈ 1 ms (optimised) / 3 ms (Debug); `close()` 2–5 ms
  as before; interruptions (mid-flight reversals, grabbing mid-close, flicks, snap-backs)
  all end consistent; `-snapshot` PNGs and `-selftest` identical to main. 18 unit tests.
  ScreenCaptureKit background bending: not built — Screen Recording isn't grantable to the
  CLI, so stream latency/pacing couldn't be measured (the user's rule: unmeasured → don't ship).
  Unverified (needs the user on hardware): the feel, haptics (NSHapticFeedbackManager from a
  non-activating agent panel), Reduce Motion (same code path as intensity Off), macOS 14.
- **Screen bending (Liquid Glass ring):** added after the user asked for the backdrop to warp.
  Verified: rest still pixel-identical (glass hidden), swap-back clean, interaction end states
  OK with the glass hidden afterwards, builds with `MACOSX_DEPLOYMENT_TARGET=14.0`, main-thread
  p95 ≈ 3.5 ms/frame (was 2.5: moving the glass view), no frame over 10.8 ms. Not verifiable
  here: the refraction itself and its window-server cost — an own-window capture has no
  backdrop, so the ring shows as dark grey there.

## Debug snapshots
Screen Recording isn't granted to the CLI, but an app can render its own window. Debug builds
accept `-selftest` (open/close via the controller, printing key window, first responder and
frontmost app at each step) and `-snapshot <dir>`: they type `ls /` into the shell, render the panel at progress
0/0.15/0.5/1 to PNGs, and quit. Run the binary directly:
`.../Debug/DEXMA.app/Contents/MacOS/DEXMA -snapshot /tmp/snap`, then view the PNGs.
`-effecttest <dir>` checks the liquid effect against the window server's own composite of the
panel (`CGWindowListCreateImage` via `dlsym`: deprecated, but an app may capture its own
window without Screen Recording): snapshot fidelity, motion layer vs live at rest, a real
swap-back frame by frame, frame pacing with the effect on/off, gesture/interruption end
states, and posed PNGs (composite them over a grey background to see the rim light). It turns
off close-on-focus-loss, because the user's Mac is usually in use while it runs (another app
taking focus closed the panel mid-test and looked like a bug). Always
check the build succeeded first — a failed build leaves the old binary, which ignores the flag
and never quits (wrap runs in a watchdog).

## Project facts
- Xcode 26.2, Swift 6.2 compiler in Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION =
  MainActor` + approachable concurrency: everything is `@MainActor` unless marked
  `nonisolated`. C callbacks (Carbon, CGEventTap, multitouch) must be `nonisolated`
  functions; hop with `MainActor.assumeIsolated` only when the callback is known to arrive
  on the main thread.
- Project `DEXMA.xcodeproj`, target/scheme `DEXMA` (tests `DEXMATests`, `DEXMAUITests`);
  sources in `DEXMA/`. Swift module `DEXMA` (`@testable import DEXMA`).
- Settings (now in the project): deployment target macOS 14.0, `LSUIElement` = YES, App Sandbox
  OFF, Hardened Runtime ON, product and display name DEXMA, SPM packages SwiftTerm
  (upToNextMajor 1.20.0) + OpenMultitouchSupport (upToNextMinor 3.0.3). Bundle id is still
  the legacy `com.jasontio.terminal-application` until the user changes it in Xcode
  (recommended `com.jasontio.dexma`); `DefaultsMigration` carries settings across. A new
  bundle id also means re-granting Accessibility and re-enabling Launch at Login.
- The Debug `-selftest` deletes the `panelWidth` and `hotKey` defaults when it finishes (real
  prefs domain): back up the user's prefs first if they have customised those.
- Release build: `…build.sh`-style `xcodebuild -configuration Release`, then
  `ditto <DerivedData>/Build/Products/Release/DEXMA.app build/DEXMA.app` (git-ignored).
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
- Hiding (`isHidden`) the view that is first responder moves first responder away; fade it
  via layer opacity instead.
- `NSGraphicsContext(bitmapImageRep:)` of a 2x rep is already in points — don't scale again.
- SwiftUI shaders: `layerEffect`/`distortionEffect` exist on macOS 14; `Shader.compile(as:)`
  is macOS 15+ (on 14, render the effect once at launch to warm it).
