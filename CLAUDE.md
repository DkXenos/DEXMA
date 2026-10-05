# DEXMA

A hidden terminal that lives in the MacBook notch. It must feel like a native macOS
feature (Notification Center, Dynamic Island) — smooth, instant, finger-driven — never
like a third-party app.

## Vision
- **Closed:** an invisible panel exactly matching the physical notch shape.
- **Trigger:** two-finger swipe DOWN starting at the top edge of the trackpad (raw touches
  via OpenMultitouchSupport). The panel follows finger progress 1:1, then settles with a
  velocity-aware spring on release. Global hotkey (default ⌥`) is the fallback.
- **Open:** the notch morphs into a wide panel with four tabs (an expanding pill left of the
  notch, ⌘1…⌘4, ⌃Tab, or a two-finger sideways swipe): **Terminal** — SwiftTerm
  `LocalProcessTerminalView` running a persistent zsh, spawned at app launch and never killed
  when the panel closes — **Search** — a search field over a `WKWebView` (Google search, or
  any address) — **Claude** — claude.ai in a `WKWebView` — and **Devices** — the Galaxy
  Buds' battery plus quick controls (brightness, volume). See *Tab UI*, *WebTab* and *Devices*.
- **Close:** swipe up, Esc, or hotkey. Focus returns to the previously active app.
- **Draw to ask:** a Capture button at the right end of the band (every tab) or its own
  shortcut (default ⌥⇧`) freezes the display under the pointer; you draw around anything, and
  the crop flies into the notch and lands in claude.ai's message box. See *Capture*.
- **Connect peek:** when the Buds connect, the closed notch grows into a Dynamic-Island pill
  with their levels for ~3 s (click → Devices tab); red when a bud drops to 20 %/10 %.

## Architecture — feature-based MVVM
Sources live in `DEXMA/`, a synchronized folder: adding, moving or renaming files needs no
project edit. One type per file; nothing sits directly in `DEXMA/`.

```
DEXMA/
├── App/            entry point, lifecycle, composition root
├── Core/           shared, UI-free building blocks: Animation, Geometry, Settings,
│                   Permissions, Navigation, System, Extensions
├── Features/<F>/   Models/ · ViewModels/ · Views/ · Services/ (· Shaders/) — only the ones F needs
├── Resources/      Assets.xcassets
└── Debug/          DEBUG-only harnesses, Support/ for their shared helpers
DEXMATests/         Core/ and Features/<F>/, mirroring the app
```

Layers — keep them separated:
- **Models:** values and pure logic (`nonisolated` when used off the main actor or by
  nonisolated tests). No views, no side effects beyond their own storage.
- **ViewModels:** `@Observable` classes views read and call (or an `NSObject` whose `@objc`
  actions AppKit menu items target). They use services and models; windows open through
  `WindowRouter`, never directly.
- **Views:** SwiftUI views, AppKit views and window controllers. Everything comes from their
  view model (or plain values from the parent view): no `UserDefaults`, permissions,
  `LoginItem` or other services. Window controllers tell their view model when the window
  opens and closes.
- **Services:** system and framework work: processes, event taps, multitouch,
  ScreenCaptureKit, Carbon, the effect's per-frame orchestration.
- Features use `Core` freely and other features only through an explicit API (a model, a
  service, a protocol like `SwipeTarget`). `AppCoordinator` is the only type that knows every
  feature. New code goes into the feature it belongs to, in the folder for its layer;
  UI-free and shared → `Core/`.
- Naming: `Notch*` types (`NotchPanel`, `NotchShape`, `NotchGeometry`, `NotchContentView`,
  `NotchViewModel`) are named after the hardware notch, not the app — they are not leftovers
  of the old "NotchTerm" name.

**App**
- `main.swift` — pure AppKit entry (no SwiftUI `App`): no default window or Settings scene.
  Runs `DefaultsMigration` (settings from the old `com.jasontio.terminal-application`
  domain) before anything reads UserDefaults.
- `AppDelegate` — lifecycle only; forwards launch and screen changes to `AppCoordinator`.
- `AppCoordinator` — composition root: builds and wires every feature at launch (the order
  pre-warms everything), applies `AppSettings` live (`applySettings`), opens Settings and
  Welcome (`WindowRouter`).

**Core**
- `Animation/SpringDriver` — advances `progress` with SwiftUI's `Spring` on the panel's
  `CADisplayLink`.
- `Geometry/NotchGeometry` — notch rect from `NSScreen` (`auxiliaryTopLeftArea`/
  `auxiliaryTopRightArea`, `safeAreaInsets`); fallback pill for non-notch screens; the
  panel's window frame, the band's regions, the content card, the page dots, the hover zone
  and `shape(at:)` / `shape(at:activity:)` (with the connect peek's pill,
  `NotchActivityShape`). `NotchShape` — SwiftUI
  `Shape` with animatable width/height/bottom radius/ear radius. `Interpolation` — `lerp`,
  `smoothstep`.
- `Settings/` — `AppSettings` (@Observable, UserDefaults, `onChange` after every edit) with
  `KeyCombo` and `DisplayChoice`; `DefaultsMigration`.
- `Permissions/` — `AccessibilityPermission`, `ScreenRecordingPermission`,
  `BluetoothPermission` (`CBManager.authorization`, asks nothing): live, polled only while a
  window shows them.
- `Navigation/WindowRouter` — opens DEXMA's windows; `AppCoordinator` implements it.
- `System/LoginItem` (SMAppService), `System/FullScreenSpace` (is a full-screen app in front on
  a display: CGS managed spaces via `dlsym`, type 4). `Extensions/` — `Logger(category:)`,
  `NSScreen.displayID`.

**Features**
- `Notch/` — the panel. `NotchViewModel`: single source of truth, `progress` (0 = notch,
  1 = expanded) + `PanelState` (closed/peek/open); hotkey, gesture, hover and the menu bar
  item all drive it; owns the panel window and focus; derives the silhouette, content
  opacity and hover zone for the view; owns the selected `PanelTab` (Model), the tab
  progress (its own `SpringDriver`), tab swipes (`TabSwipeTarget`) and gives each tab the
  keyboard; implements `DeviceActivityTarget` (the connect peek: `activity`, `activityAmount`
  stepped with its own `Spring` on the panel's display link). Models: `TabSwitcherLayout`,
  `PageDotsLayout`, `TerminalContextLayout` (pure band geometry), `ActivityPillLayout` (the
  pill's size, icon and text). Views: `DeviceActivityView` (the pill's content), `NotchPanel` — borderless non-activating
  `NSPanel` above the menu bar; `canJoinAllSpaces` + `fullScreenAuxiliary` + `stationary`;
  transparent; ordered in at launch, never ordered out. `PanelContentView` — the panel's
  flipped content view (warp/glass below, `NSHostingView` above). `NotchContentView` —
  SwiftUI root, everything from the view model. `NotchChrome` (live at rest, a copy in the
  motion layer while moving):
  `TabSwitcher`, `BandContext`, `CardDecoration`, `PageDots`; every band control is a
  `BandButtonStyle`/`BandControl` (white 12 % hover fill, under the liquid lens while
  hovered/pressed); clicks go through `NotchViewModel.click` (haptic tick).
  `ContentPagerView`/`ContentPagerHost` — the card's pages side by side (scrolled by its
  bounds, clipped to the card and the silhouette). AppKit overlays above the SwiftUI band:
  `RunningDotView` (CA-pulsed), `URLEntryField` (⌘L on Claude). Services: `NotchGeometryProvider` (screen
  choice, size clamp, `-forcePill`), `HoverMonitor` (pointer over the notch → peek),
  `FocusHandoff` (keyboard back to the previous app).
- `Terminal/` — `ShellSession`: ONE long-lived `LocalProcessTerminalView` + zsh (respawned
  on exit), its snapshot cache and its `ShellStatus` (working directory via `proc_pidinfo`,
  running = the PTY's foreground group isn't the shell's). Views: `ShellTerminalView`
  (reports output), `TerminalContainerView` (the terminal's page, padded). Never recreated.
  Models: `TerminalSnapshot` (pixel-exact picture of the live terminal), `ShellStatus`,
  `PathAbbreviation` (`~`, middle truncation; pure).
- `WebTab/` — the shared web tab (see *WebTab*): `WebTab` (Service), `WebTabView`,
  `WebPopupController` (sign-in popups), `WebDownloads`, `WebTabViewModel`; Models
  `WebTabConfiguration` (`.search`, `.claude`), `WebNavigationPolicy`, `CSSColor`.
- `Search/` — Model: `SearchQuery` (text → Google search or address, pure); the tab itself is
  `WebTab` with `.search`.
- `Gestures/` — Models: `GestureRecognizer` (pure, unit-tested), `TouchPoint`,
  `GestureParameters`, `GestureEvent`, `TabSwipeTracker` (pure: axis lock, momentum,
  release), `GestureTuning`. Services: `GestureEngine` (OpenMultitouchSupport
  frames → recognizer → `SwipeTarget`, i.e. `NotchViewModel`), `TabSwipeMonitor` (local
  scroll monitor → tracker → `TabSwipeTarget`), `ScrollBlocker`/`ScrollGate`
  (`CGEventTap` on its own thread swallowing scroll during a swipe), `Haptics`
  (`NSHapticFeedbackManager` ticks).
- `LiquidMotion/` (only while moving) — Models: `EffectTuning` (every constant +
  `scaled(by:)` for the Settings "Effect intensity" slider), `MotionEffects` (@Observable
  per-frame state: jelly stretch/wobble, energy, anticipation bulge), `Silhouette` (the shape
  at a progress with the frame's squash and stretch — the one place it's computed),
  `ContentSnapshot` (the picture the motion layer bends), `JellySpring` (the jelly: notch
  stretch/wobble and the indicator's), `BandMotion` (the band: a `ControlLens` per control —
  hover breath/rest lens, cursor follow, press squash — and the selection indicator's droplet
  slide). Services: `LiquidMotionEngine` (the effect around every motion: snapshot swap,
  per-frame step, idle snapshots, screen bend, and the band's frames),
  `MotionContent` (protocol the selected tab's content implements: `ShellSession`, `WebTab`
  — the engine knows neither). Views: `LiquidMotionLayer` +
  `Shaders/LiquidEffects.metal` (SwiftUI `distortionEffect` stretch and `layerEffect`
  lens/aberration/light over the content snapshot), `ControlLensEffect` (the same file's
  `liquidControlLens` on one band control).
- `ScreenWarp/` — `ScreenBender` bends the real screen around the notch: owns
  `ScreenCapture` (a ScreenCaptureKit stream of the panel's screen rect, DEXMA excluded, run
  only around intent) and `ScreenWarpView` + `Shaders/ScreenWarp.metal` (a CAMetalLayer below
  the silhouette presented in the CA transaction); plus the pointer lens; falls back to
  `BackdropLens`, a clear `NSGlassEffectView` ring, without Screen Recording. Models:
  `SilhouetteMotion` (what it bends around), `WarpUniforms` (matches the shader).
- `HotKey/` — `HotKey` (Carbon `RegisterEventHotKey` wrapper, needs no permissions),
  `HotKeyRegistrar` (keeps the settings' combo registered; paused while recording one).
- `MenuBar/` — `MenuBarViewModel` (titles, state, `@objc` actions), `StatusItemController`
  (the menu bar item), `MainMenu` (About/Settings/Quit, Edit, Window).
- `Settings/` — `SettingsViewModel`, `TrackpadPreviewViewModel`; Views:
  `SettingsWindowController`, `SettingsView`, `TrackpadPreview`, `ShortcutRecorder`; Model:
  `ShortcutInput` (key press → shortcut, pure).
- `Onboarding/` — `OnboardingViewModel`, `OnboardingRecord` (the `didShowOnboarding` flag),
  `OnboardingView`, `OnboardingWindowController`.
- `Devices/` — the Buds' battery (see *Devices*). Models: `Device`, `DeviceComponent`,
  `ComponentRole`, `DeviceKind`, `DeviceSource`, `BatteryReading`/`ComponentReading`,
  `RelativeTime`, `LowBatteryPolicy`, `DeviceActivity`, `DeviceSummary` (pure), and the Buds
  protocol: `BudsModel` (the per-model table), `BudsFraming`, `BudsStatusLayout`,
  `BudsMessage`, `BudsChecksum`, `BudsFrameDecoder`, `BudsStatusParser`, `BudsIdentification`
  (pure, unit-tested). Services: `DeviceStore` (@Observable, generic, JSON in Application
  Support), `BluetoothBudsMonitor` (connect/disconnect notifications), `BudsConnection` (SDP →
  RFCOMM → readings, backoff, fallback), `SDPRecords`, `SystemBatteryReader` (fallback),
  `DevicesPage` (the tab's `MotionContent`: `ImageRenderer` picture), `DeviceActivityTarget`
  (protocol; `NotchViewModel`), `SystemVolume` (CoreAudio default output volume/mute with
  listeners), `DisplayBrightness` (built-in display via DisplayServices, `dlsym`). ViewModels:
  `DevicesViewModel` (events → peeks, relative-time clock), `QuickControlsViewModel` (the
  Controls card). Views: `DevicesCardView` (the pager page: hosting view), `DevicesPageView`,
  `DeviceCardView`, `BatteryGauge`, `DevicesEmptyView`, `DevicesPalette`, `QuickControlsCard`,
  `LevelSlider` (Model `SliderTrack`, pure).
- `Capture/` — Draw to ask (see *Capture*). Models: `CaptureSelection` (stroke → box, click →
  window; pure), `CaptureCrop` (points → native pixels; pure), `StrokeGeometry` (Catmull–Rom,
  resampling, rounded-rect points for the morph; pure), `CaptureLook` (every constant +
  `scaled(by:)`), `CaptureBandLayout` (button/chip widths; pure), `FrozenScreen`,
  `CapturedImage`, `PendingCapture`, `CapturePhase`, `ClaudeInsertMethod`. Services:
  `ScreenFreezer` (SCScreenshotManager, DEXMA excluded, window frames), `CaptureEncoder` (crop +
  PNG + thumbnail, off main), `ClaudeAttacher` (into claude.ai's composer), `PasteboardSnapshot`,
  `CaptureArchive` (~/Pictures/DEXMA, opt-in), `CaptureHandoffTarget` (protocol; `NotchViewModel`
  implements it). ViewModels: `CaptureViewModel` (the flow), `CaptureOnboardingViewModel`.
  Views: `CaptureOverlayPanel` (screen-saver level, non-activating), `CaptureOverlayView` (frozen
  frame, dim, lift, flight), `StrokeLayer`, `EdgeGlowLayer`, `CaptureHintView`,
  `CaptureOnboardingView`/`…WindowController`. The band's `CaptureControls` and
  `PendingCaptureChip` live in `Notch/Views` (they're band parts, `BandButtonStyle`).

**Debug** (DEBUG only) — `DebugHarness` dispatches the launch flags to `SelfTest`
(`-selftest`), `SnapshotTest` (`-snapshot <dir>`), `EffectTest` (`-effecttest <dir>`),
`TabTest` (`-tabtest`), `SwipeTest` (`-swipetest`), `HoverTest` (`-hovertest`, `-bandshot`),
`ClaudeProbe` (`-claudeprobe`), `CaptureTest` (`-capturetest`, `-captureorient`), `SizeTest` (`-sizetest`), `DeviceTest` (`-devicetest`) and `WarpTest` (`-warptest <dir>`, `-captureidle <s>`); `MockDevices` (the status item's
*Mock Devices* menu); harness runs leave Bluetooth alone (`DebugHarness.isRequested`); `Support/` holds `DebugImages`,
`FramePacingProbe` and `NotchViewModel.waitForRest()` (see *Debug snapshots*).

## Tab UI (the spec, 2026-10-01, branch `feature/claude-tab`)
True black (#000000) throughout; the shape, size, notch geometry and open/close are unchanged.
- **Swiping:** two-finger left/right (`TabSwipeMonitor` → `TabSwipeTracker`): events pass
  through until 8 pt of travel, then lock to an axis until the fingers lift; horizontal =
  |dx| > 1.5 |dy|. Works anywhere on the band and the terminal; on web pages only where the
  page can't scroll further sideways that way (injected JS); WKWebView's own back/forward
  swipe is off (⌘[ / ⌘] instead). Pages follow the fingers 1:1 (the scroll deltas, so the
  natural-scrolling setting is respected), rubber-band past the ends (0.3 of the fingers, at
  most 0.12 of a page), commit past 35 % or above 1.2 pages/s, settle on the tab
  `SpringDriver` carrying the release speed, interruptible, haptic tick on commit, momentum
  ignored. Constants: `GestureTuning`. Pages, indicator, dots and the context crossfade all
  ride `NotchViewModel.tabProgress`.
- **Band:** 36 pt, padding 14, left and right regions equal, the gap = the notch (or pill).
- **Tab switcher (left):** container padding 3, radius 10, white 7 %, gap 4. Inactive tabs
  icon-only 30 × 26 (icon 12 pt, white 55 %); the active one icon + label, height 26,
  padding 10, spacing 6, label 12.5 pt semibold white, width hugging it. Indicator radius 8,
  white 17 %, droplet stretch. Widths, reveal (fade + 4 pt slide), indicator and colours
  interpolate with the progress (`TabSwitcherLayout`). Hover warp on every tab.
- **Context (right), crossfading:** Terminal — cwd, `~`, middle-truncated, SF Mono 11 white
  55 %, after a 6 pt green dot pulsing while a foreground command runs. Search — lock (https)
  + domain (11 pt white 55 %), Reset, Open in browser. Claude — lock + claude.ai, New chat
  (`square.and.pencil`, "New chat  ⌘⇧R"), Open in browser. Buttons 32 × 28. Never into the gap.
- **Card:** inset 10 left/right/bottom, top 40, radius 19; 1 px inner stroke white 7 %; 1 px
  top-edge highlight white 5 %; background #000 (Terminal), the page's own colour (web tabs,
  JS after load and on theme change), #1C1C1E until known.
- **Page dots:** in the 10 pt margin below the card, centred; 5 pt, white 25 %, 6 pt apart;
  the active one 14 × 5, white 85 %; position and width follow the progress (`PageDotsLayout`).
- **Snapshot rule:** while the panel moves, the motion layer shows the content's picture and a
  copy of the chrome (band, card stroke, page dots), so the distortion bends both; at rest the
  live chrome (outside every shader, flattened with `.compositingGroup()` so its text renders
  like the copy) shows. Why this shape: toggling a SwiftUI layer effect on a visible layer
  draws one frame of its content shifted (~100 × 52 pt here), and keeping the shaders always
  on cost extra frames during hover and swipes — the motion layer is hidden (layer opacity)
  whenever its shaders switch, so that frame is never seen.

## WebTab
One component (`Features/WebTab/`), two configurations (`WebTabConfiguration`):
- Shared: created at launch and never destroyed; one `WKUserContentController` for all its
  web views (scripts: scroll end/sideways edges, page background colour); Safari's user
  agent token; the persistent default website data store (shared by both tabs: sign-ins
  survive restarts); dark appearance; no white flash (a fresh web view shows after its first
  `didFinish`, the card colour behind it until then); `MotionContent` (the field strip via
  `cacheDisplay` + WebKit's async `takeSnapshot` of the page, refreshed at idle and when the
  tab spring settles; with no page picture yet the motion skips the effect, never blank);
  focus memory; downloads to ~/Downloads (quarantined, Dock stack bounce); popups.
- `.search`: a search field on top of the card (words → Google, addresses open; ⌘L focuses
  it), nothing loaded until the first search, every web page stays in the tab (window.open
  loads in the tab), Reset swaps in a pre-made spare web view (instant, history gone).
- `.claude`: https://claude.ai/new loaded at launch; claude.ai/anthropic.com and the sign-in
  hosts (accounts.google.com, accounts.youtube.com, appleid.apple.com) stay in the tab, any
  other main-frame link opens in the default browser; sign-in popups (Google uses one) open
  as a real window (`WebPopupController`, with WebKit's configuration so it reports back);
  focus puts the caret in the message box (`focusComposerScript`, silent if not found);
  New chat (⌘⇧R) loads /new in the same tab; Open in browser (⌘⇧O) opens the current
  conversation and closes the panel; ⌘L shows `URLEntryField` over the band to paste a link
  (e.g. an email sign-in link); page zoom from Settings (`claudeZoom`, default 100 %).

## Capture (Draw to ask, 2026-10-02, branch `feature/capture`)
- **Start:** the band's Capture button (rightmost in the right region on every tab, 32 × 28,
  `pencil.and.scribble`, tooltip with the shortcut; the tab's context gets `contextRegion`, the
  rest), the capture shortcut (`captureHotKey`, default ⌥⇧`, a second `HotKeyRegistrar`; both
  pause while either is recorded; pressing it again cancels), or the menu bar item. The panel's
  own shortcut cancels a capture in progress. Without Screen Recording (checked off the main
  thread, cached once yes) the DEXMA-styled sheet (`CaptureOnboarding…`) explains why, opens
  the pane, polls, then checks ScreenCaptureKit really works (`ScreenFreezer.isWorking`) and
  offers "Relaunch DEXMA" if macOS wants that.
- **Freeze:** the overlay (one `CaptureOverlayPanel`, made at launch) comes up at once on the
  display under the pointer, transparent, edge glow + hint fading in; `ScreenFreezer` takes one
  `SCScreenshotManager` picture at native pixels with `excludingApplications: [DEXMA]` (so the
  closing panel never needs to finish first; measured 22–53 ms) plus the other apps' windows
  front to back (`CGWindowListCopyWindowInfo` order, `SCWindow.frame`, layers 0–19). The frozen
  frame fades in over the live screen, then dims 18 %. Strokes are taken before it arrives.
- **Draw:** `StrokeLayer` — white 4 pt, round caps, Catmull–Rom through points ≥ 1.5 pt apart;
  glow = three wider white strokes in groups with group opacity; shimmer = a pre-rendered tint
  stripe sliding under a mask of the stroke. Chunks of 48 segments are frozen once complete; only
  the last chunk is re-stroked per move; the groups and shimmer only cover the stroke's extent.
  Measured: 1,200 moves at 120 Hz, p95 0.4 ms main thread per move, 0 late frames.
- **Select:** box + 8 pt, clamped, ≥ 24 pt (`CaptureSelection`); a click (< 4 pt travel) picks
  the frontmost window under it (the desktop: the whole display). The core and first glow morph
  into the rounded rect (≤ 480 points, `StrokeGeometry.roundedRectPoints` starting nearest the
  stroke's start, same direction); the other tiers fade in on it; the detailed stroke crossfades
  out. Then the outside dims to 42 % and the selection (same image, `contentsRect`) lifts to
  1.02 with a shadow; haptic tick (`Haptics.tap`). Cropped + PNG-encoded off main meanwhile.
- **Hand-off:** the lifted image flies (CA keyframes, ease-in "suction", droplet stretch,
  rounding) into the notch's centre (the hardware notch has no pixels: it vanishes into it) or
  off the top if the panel opens on another display; the rest fades. At 80 % the notch opens on
  the Claude tab (`openForCapture`: the normal open, so its anticipation swell, jelly and screen
  warp are the "liquid pull"); the overlay orders out when the flight ends, before the panel
  settles (measured: opening ~0.93 s after release, overlay gone ~0.95 s, at rest ~1.56 s).
  Reduce Motion: no morph/lift/flight, a 0.15 s fade, then the open. Esc (or the shortcut, a
  Space switch, a display change) cancels at any stage until the notch opens.
- **Insert (`ClaudeAttacher`), chosen: (a) real paste.** Once the Claude tab is open, at rest
  and key and the composer is there (`chat-input`, TipTap/ProseMirror; not `/login`): save the
  clipboard (`PasteboardSnapshot`), put the PNG on it, `NSApp.sendAction(paste:)` to the web view,
  restore the clipboard as soon as the page's paste event has fired (or 1.5 s; only if nothing
  else was copied meanwhile), verify (an attachment element appears near the composer, or the
  page handled the paste event with the file). Fallbacks: (b) the `file-upload` input via
  DataTransfer + change event, (c) a scripted paste, then drop, event. Then the caret goes to
  the message box. Why (a): trusted input, exactly what a user's ⌘V does, so claude.ai's own
  paste handling (upload, thumbnail, React state) runs unchanged; no temp files.
- **Pending:** not ready (signed out, loading, panel closed) → the chip (thumbnail 20 pt, radius
  6, ✕) left of the Capture button; polled every 250 ms, attaches by itself, gives up after 60 s
  (orange edge; a click shows the Claude tab and retries). "Start a new chat for each capture"
  loads /new as the notch opens. "Also save captures to ~/Pictures/DEXMA" (off by default);
  otherwise captures only live in memory. Capture effects (edge glow + shimmer) follow the glass
  strength unless set apart (Settings → Draw to ask Claude).
- **Cost:** the window server spends ~50 % of a core while anything in the overlay animates at
  120 Hz (glow turning, shimmer) — the same as the notch opening and closing nonstop (49 %);
  ~4 % with the effects still (Reduce Motion) or off. Main thread: begin 5–11 ms once.

## Devices (2026-10-05, branch `feature/devices-tab`)
A 4th tab with the Galaxy Buds' battery (left, right, case), live while connected and kept
with "last seen" after; the data layer is generic so phones/tablets can join later.

**Protocol facts and where they came from** (GalaxyBudsClient by timschneeb, GPLv3: studied
for facts only — `Model/Constants.cs`, `Model/Specifications/*DeviceSpec.cs`,
`DeviceSpecHelper.cs`, `Message/SppMessage.cs`, `Message/SppMessageEnums.cs`,
`Utils/Crc16.cs`, `Message/Decoder/StatusUpdateDecoder.cs` and `ExtendedStatusUpdateDecoder.cs`,
`App.axaml.cs`, `Galaxy Buds Plus RFComm Protocol Notes.md`, and the macOS backend
`GalaxyBudsClient.Platform.OSX/Native/src/Bluetooth.mm`; all code here is our own):
- RFCOMM service UUIDs: Buds (2019) `00001102-0000-1000-8000-00805f9b34fd`; Buds+, Live, Pro
  the standard SPP `00001101-…-00805f9b34fb`; Buds2 and later (incl. Buds3 Pro)
  `2e73a4ad-332d-41fc-90e2-16bef06523f2`. Buds2+ also list `d908aab5-7a90-4cbe-8641-86a553db`
  + 4 hex = Samsung model id, big-endian (Buds3 Pro 340/341).
- Seen on the user's Buds3 Pro "Mewo" (macOS's cached records, 2026-10-05): the status service
  is "GEARMANAGER" on RFCOMM channel 27; the model id service `…86a553db0154` (340);
  "SAMSUNGDEVICE" `a23d00bc-…` ch 28, "SPPSERVICE4" `f8620674-…` (Samsung's alternative
  mode) ch 29, "DEVICEID" ch 22, "FACTORY" (SPP) ch 20, "BTIS" ch 21.
- Framing: `FD` | header (u16 LE: size = id+payload+CRC in the low 10 bits, 0x1000
  request/response, 0x2000 fragment) | id | payload | CRC-16 LE | `DD`; the Buds (2019) use
  `FE`/`EE` and a [type, size] header. CRC = CRC-16/XMODEM (poly 0x1021, init 0) over id +
  payload (check value 0x31C3; the notes' sample frame gives 0xF30F, sent `0F F3`).
- Battery: `STATUS_UPDATED` 0x60 (sent on every change) [rev, L, R, coupled, main bud,
  placement (L high nibble, R low: 0 not connected, 1 worn, 2 out, 3 case, 4 closed case),
  case, charging (Buds2+: 0x10 L, 0x04 R, 0x01 case)]; `EXTENDED_STATUS_UPDATED` 0x61 (sent by
  the Buds right after the channel opens) [rev, ear type, L, R, coupled, main, placement, case,
  …settings…, charging at 42 on Buds3/3 Pro (43 on FE/Core/3 FE, revision-dependent on 2 Pro)].
  Case 101 = unknown (no bud in it). Buds (2019): no case. No request is needed: the client
  replies MANAGER_INFO (0x88) to 0x61, which we don't (read-only).
- macOS keeps a record's one-UUID ServiceClassIDList as a bare UUID element, not a sequence
  (`SDPRecords` reads both; reading only sequences found nothing and the Buds were never
  identified — the first hardware bug).
- macOS: `performSDPQuery(_:uuids:)` silently returns nothing since Ventura → query everything;
  `openRFCOMMChannelSync` reports an error even when the channel opens (we use the async
  open and accept "open" whatever the status).

**Reading (`BluetoothBudsMonitor` → `BudsConnection`):** IOBluetooth connect notification
(plus connected-at-launch from the local paired list) → candidate = Galaxy name or any
audio-class device (renamed Buds look like any headset; "Mewo" had no cached SDP records) →
cached records first, else one `performSDPQuery` → `BudsIdentification` (model id service,
Samsung service + name, name) → RFCOMM channel from the record (never hard-coded) →
`BudsFrameDecoder` (chunked, resyncs on bad SOM/size/CRC/EOM, skips fragments) →
`BudsStatusParser` (levels outside 1…100 or a disconnected bud = unknown) → `DeviceStore`.
Each step logs (category "Buds"), including the first raw bytes and the first reading.
The Buds' link is owned by macOS's audio: inside DEXMA `isConnected()` stays false (the
second hardware bug: DEXMA waited for it and gave up), so after the connect notification it
attaches with `openConnection(self)` (joins the existing link; "connection exists" also comes
back as an error, so it carries on either way) before SDP/RFCOMM. The notifications are the
truth for connected/disconnected; at launch, Buds already connected are found through their
Bluetooth audio route (`BluetoothAudioRoutes`: CoreAudio device UIDs carry the address).
Non-Buds headsets are left alone for the session. Failure (busy channel, no service, timeout)
→ `SystemBatteryReader` (HID `BatteryPercent` in the IORegistry, then `system_profiler -json
SPBluetoothDataType` `device_batteryLevel*`, off main) and retries after 2/10/60 s, then not
until the next connect; no status 5 s after opening → the fallback meanwhile. Disconnect
notification → close, stop, store `disconnected`. Nothing runs while no Buds are connected.

**`DeviceStore`:** `Device {id, name, kind, source, model, components, isConnected,
lastSeen}`, `DeviceComponent {role (left/right/case/main), level?, isCharging?, updatedAt?}`.
`apply(reading)`: known values take the reading's time, unknown ones keep their old value
and time (the case). A newer single `main` value (the fallback) shows alone. Events:
connected / firstReading (first with a level since connect) / reading / disconnected. JSON
(`~/Library/Application Support/DEXMA/devices.json`, ISO 8601 to the second) written 1 s
after the last change on a utility queue, and on quit; `isConnected` false on load; `.mock`
devices dropped by Release builds.

**Tab:** `DevicesPageView` (SwiftUI in `DevicesCardView`, a pager page): a card per device
(radius 16, white 6 %, 1 px white 7 %, padding 16; full width alone, 2 columns from 2), header
(icon, name 14 pt semibold, green dot + "Connected" or "Last seen 2h ago" white 45 %), a
`BatteryGauge` per part (56 pt ring, 5 pt line, track white 12 %, 15 pt rounded digits,
white / green + bolt while charging and connected / red ≤ 20 %, "—" unknown, 45 % when
disconnected, its own "3h ago" when ≥ 60 s older than the newest; level changes animate with
`Spring(duration: 0.45, bounce: 0.2)`, none with Reduce Motion). Relative times: one timer
aimed at the next change (`RelativeTime.nextChange`), none when nothing shows a time. The
liquid effect's picture: `ImageRenderer` of the same view (cacheDisplay can't draw SwiftUI
text), idle like the other tabs. Band: `DeviceSummary.band` of the most recent device.

**Controls (2026-10-05, the user: "the tab is better for QoL features"):** the page is two
columns: devices (or the empty card) left, a Controls card right (36 % of the width, ≥ 180 pt,
same card look, both as tall as the taller): "Display" (the built-in display's brightness)
and "Sound" (the default output's volume), label + percentage over a Control Center-style
`LevelSlider` (28 pt capsule, white 12 % track, white fill growing from the icon's circle,
click/drag follows the pointer, no animation). Volume: CoreAudio
`kAudioHardwareServiceDeviceProperty_VirtualMainVolume` + mute on the default output, with
property listeners (volume keys, Control Center, output switches) on the main queue —
event-driven; raising it unmutes; muted shows 0 and `speaker.slash.fill`; no volume control →
disabled. Brightness: no public API on Apple silicon (IOKit display parameters don't apply) →
DisplayServices `Get/Set/CanChangeBrightness(displayID)` via `dlsym` (what the brightness keys
use; MonitorControl/Lunar do the same), built-in display only (externals need DDC: disabled,
"—"), down to 0 like the brightness keys (the user asked for 0, 2026-10-05; it was clamped at
0.02 before). No change notification is used (its
signature isn't documented), so it's re-read when the tab comes to rest on screen
(`DevicesPage.didShow`: panel settled open on Devices, or the tab spring settled on it) —
never during an animation; a refresh costs 0.17 ms. The page's picture follows the controls'
values (observation), like the devices'.

**Connect peek:** `DevicesViewModel` asks `showDeviceActivity` on the first reading after a
connect (setting on) and when `LowBatteryPolicy` says a bud (not the case, not charging)
crossed 20 % or 10 % (once each per connection, re-armed above +5; already low at connect →
covered by the connect peek, which is then red). `NotchViewModel` refuses while open,
capturing, or (unless "Show in full screen") over a full-screen space; moves to the opening
screen like an open; grows `activityAmount` 0 → 1 with the open spring on the panel's display
link (the jelly gets its speed × the pill's share of the open width; landing squash; screen
warp bends around it via `LiquidMotionEngine.activity`); `ActivityPillLayout`: notch height +
20, wings ≥ 70 pt (text-fitted: buds on one line, case smaller below — one line with the
case was 581 pt wide), icon centred left, text right. ~3 s, longer while hovered; the hover
zone covers the pill (the hover monitor runs while it's out even with peek-on-hover off);
a click (peek state) opens on Devices. Never key. Opening/capture collapses it.

## Animation model
- `progress` is always the on-screen (presentation) value. `SpringDriver` steps it each
  display frame with `Spring.update(value:velocity:target:deltaTime:)`; nothing animates
  it with `withAnimation`. This is what lets a gesture grab the panel mid-flight and a
  release hand its velocity to the spring.
- Views derive every size/radius from `progress`; no implicit or explicit SwiftUI
  animations on anything derived from it.
- The display link is created once at launch and paused while the spring is at rest.
- Liquid effect: `SpringDriver.onFrame` → `LiquidMotionEngine.step` steps `MotionEffects` on
  the same display link and keeps it running until every effect value is *exactly* zero (then
  the link pauses). The black silhouette is always the same vector `shape.fill` —
  squash/stretch/bulge only scale `NotchShape`'s width/height about the top centre
  (`Frame.scale`, through `Silhouette`; exactly 1 × 1 at rest).
  Shaders touch only the content: while moving, `LiquidMotionLayer` shows the selected tab's
  `ContentSnapshot` (the live view's mask opacity goes to 0 — never `isHidden`, which would
  drop first responder), bent by the shaders and clipped to the silhouette. The band beside
  the notch stays live (SwiftUI), given the same squash/stretch as a `scaleEffect`. At rest the motion layer is
  transparent with `isEnabled: false`. The only thing ever swapped is the text, in one
  SwiftUI update. Snapshots are taken while idle (0.5 s after the last output/input/scroll),
  so `open`/`close` normally do no capture. Reduce Motion or intensity Off → the effect is
  skipped entirely and the old path runs unchanged.
- Screen bending: each effect frame `LiquidMotionEngine` hands a `SilhouetteMotion`
  (silhouette, strength = energy peaking mid-way or the anticipation swell, direction from
  the velocity's sign) to `ScreenBender.step`. With Screen Recording (user's choice,
  2026-10-01: Camera-Control
  colour warp) it redraws the captured screen pushed out (growing) / pulled in (shrinking)
  around the silhouette with an RGB split, transparent where the bend is < ½ pt, so it meets
  the real screen seamlessly; the pointer lens magnifies around the cursor near the notch
  (hover monitor → `pointerMoved`, keeps the display link awake). Capture starts on intent
  (pointer within `hoverReach` = 28 pt of the notch — 120 pt kept it running during normal
  menu bar use — fingers armed in the edge zone, open/close) and stops 1.5 s after the last
  use; macOS shows its recording indicator meanwhile (no app can hide it). If the user stops
  it from that indicator, the warp stays off (glass fallback) until relaunch or the switch is
  toggled. Cost while capturing with nothing moving: DEXMA ~1.3 % CPU (Debug), replayd
  ~1.6 %, WindowServer unchanged; 0 when not capturing (`-captureidle <s>` probe). Without the permission:
  the Liquid Glass ring (narrow, clamped to the window). `CGPreflightScreenCaptureAccess`
  costs ~10 ms: only ever called off the main thread (cached).
- Notch warp at rest (the user's clarification of "hover warp", 2026-10-01): the peek swell
  (hover on the closed notch) runs the liquid motion like an open (breath via `anticipate`,
  jelly, rim light), and a resting colour-warp push stays around the silhouette while it's
  swollen (`peekWarp` 4 pt) or open (`openWarp` 6 pt), following the progress in between
  (`LiquidMotionEngine.restingPush`; 0 closed, with Reduce Motion or Off). The user chose the
  ScreenCaptureKit warp over a Liquid Glass rim, knowing macOS's recording indicator stays on
  while the panel is open. At rest the stream is slowed to `restingWarpRate` (60 fps) and the
  warp is redrawn only on new screen frames (`ScreenCapture.onNewFrame`, coalesced; presented
  outside the CA transaction), never every display frame. Measured (`-warptest`, Debug, a busy
  screen behind — a video): 16.5 % CPU before the slowdown → 8.7 % (capture alone 2.8 %); a
  still screen behind sends almost no frames. Capture stops 1.5 s after closing as before.
- Band controls (Phase 13): the same system, locally. `BandMotion` steps on the panel's display
  link (`LiquidMotionEngine.step`, woken by hover/press/select; paused once exactly zero).
  Hover: a breath (everything to full over `controlBreathDuration`, then `controlRest` of it)
  and a magnifier + glint at the pointer (`controlFollow` smoothing); exit decays to exactly 0.
  The shader runs on the SwiftUI control itself (no snapshot), padded by a 4 pt margin =
  `maxSampleOffset` (offsets clamped in the shader): it can't reach the notch gap (12 pt) or the
  card (6 pt below the band). Press: `JellySpring` squash, springs past rest on release; click
  → `Haptics.tap()` (never on hover). Indicator: SwiftUI `Spring` (0.4 s, bounce 0.25) + the
  notch's jelly (stretch ∝ speed in segments/s, same landing kick ratio). Reduce Motion: no
  lens/squash, indicator jumps; intensity Off: plain hover fill, indicator slides unstretched.
  The `layerEffect` stays attached (enabled only while active): attaching/removing it switches
  the label's anti-aliasing (a tick), so the control always renders offscreen; idle it never
  redraws, so there's no GPU cost. Warm-up: `compile(as:)` on macOS 15+, a 16 pt probe in the
  motion layer's launch warm-up on 14.
- Overshoot past fully open eases into the window's room (`NotchGeometry.overshoot`, tanh) and
  squash/stretch is clamped to `silhouetteLimit()`: a fast flick used to run the silhouette
  past the window's bottom edge (a hard straight cut). Identical at progress ≤ 1.

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
- **Don't edit `project.pbxproj`** unless absolutely necessary. Adding, moving or removing
  Swift files needs no project edit (the targets use synchronized folders). For entitlements,
  Info.plist keys, build settings or packages: tell the user, they change it in Xcode.
  (Exception on record: the user OK'd Claude's one pbxproj edit for packages/settings/name.)
- Unit tests: `xcodebuild test … -only-testing:DEXMATests` (Swift Testing), in the folder that
  mirrors the code they test.
- Small, focused files: one type each, in its feature's layer folder (see *Architecture*).
  Comment only the non-obvious parts (especially gesture math and window levels).
- **Commits** are authored by the user's git identity (DkXenos), with no `Co-Authored-By:
  Claude` line (the user's request, 2026-10-01).
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
- [x] 11. Feature-based MVVM refactor (branch `refactor/mvvm`, from `feature/distortion`).
- [x] 12. Tabs (Terminal / Search) beside the notch + Google search in a `WKWebView`
  (branch `feature/tabs`, from `refactor/mvvm`).
- [x] 13. Hover warp on the band's controls (same distortion system), press squash, droplet
  selection indicator (branch `feature/tabs`).
- [x] 14. Tab swiping, tab UI refresh, Claude tab (branch `feature/claude-tab`, from
  `feature/tabs`; pushed, not merged: the user tests first).
- [x] 15. Settings: open panel size first, "Look & performance" (glass effect strength,
  Performance / Balanced / Quality screen-warp slider) (same branch).
- [x] 16. Draw to ask (capture → claude.ai) (branch `feature/capture`, from
  `feature/claude-tab`; pushed, not merged: the user tests first).
- [x] 17. Devices tab: Galaxy Buds battery over Bluetooth, DeviceStore, connect peek (branch
  `feature/devices-tab`, from `feature/capture`; pushed, not merged: the user tests first).

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
  `OnboardingView`: first-run window (gesture + hotkey how-to, why Accessibility, button that
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
- **Phase 7:** `AppSettings` (@Observable, UserDefaults, `onChange` → `AppCoordinator.applySettings`
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

- **Screen warp (ScreenCaptureKit):** measured with `-warptest` (Screen Recording granted to
  DEXMA by the user; Debug and Release share the grant — same bundle id and signature):
  stream start → first frame ≈ 80–90 ms (first after launch 190–450 ms); a hotkey open with
  no stream running gets the warp 170 ms in (gesture/hover start it earlier); pacing with the
  warp 0 late frames over 6 cycles, main-thread p95 3.3 ms; zero-bend warp layer vs the real
  screen: identical raw pixels (seamless). Posed captures show the menu bar items next to the
  notch pushed out and colour-split. Unverified: the feel of the pointer lens.
- **Phase 11 (feature-based MVVM):** every file moved (git mv, history kept) into `App/`,
  `Core/`, `Features/<F>/{Models,ViewModels,Views,Services,Shaders}`, `Resources/` and
  `Debug/`; one type per file. Renamed: `PanelController` → `NotchViewModel`, `TouchPreview`
  → `TrackpadPreviewViewModel`, `ScreenBender.Motion` → `SilhouetteMotion`,
  `ScreenWarpView.Uniforms` → `WarpUniforms`, `DebugSnapshot` → `DebugHarness` + `SelfTest` +
  `SnapshotTest`. Split out: `AppDelegate`'s wiring → `AppCoordinator`, its screen choice →
  `NotchGeometryProvider`, its hotkey handling → `HotKeyRegistrar`; `PanelController`'s
  effect half → `LiquidMotionEngine`, its focus return → `FocusHandoff`. New: view models for
  Settings, Onboarding and the menu bar; `WindowRouter`; `SwipeTarget` (the gesture engine no
  longer knows the panel or the terminal); models `Silhouette`, `ShortcutInput`,
  `OnboardingRecord`. Behaviour unchanged, except three small fixes: the Settings "shortcut
  taken" warning updates live, the welcome window shows the current shortcut, and Settings
  re-reads Launch at Login each time it opens. Verified against the pre-refactor build: 0
  warnings (Debug and Release), 27 unit tests (18 + 9 new), `-snapshot` PNGs and every posed
  `-effecttest` frame byte-identical, `-selftest` output identical, all six interaction checks
  OK, pacing as before (0–1 late frames).

- **Phase 12 (tabs + Search):** the user asked for tabs and a Google search (2026-10-01; their
  spec for this part was lost, so the layout was agreed in chat: tabs left of the notch,
  buttons right, search field on top of the card; phases 12–13 back to back). `NotchGeometry`:
  `bandHeight` (notch height, ≥ 28 pt for the pill), `tabBandFrame`/`actionBandFrame`,
  `terminalFrame` → `contentFrame` (same place on notched screens; the pill's card moved down
  to fit the 28 pt band). The motion engine works on `MotionContent`; the Search card pictures
  itself as AppKit's `cacheDisplay` of the field strip + WebKit's `takeSnapshot` of the page
  (async, while idle), composed in the page's colour space. Focus: the terminal, or for Search
  whatever had it when the panel closed (page, else the field with its text selected); ⌘L →
  field; Esc closes on both tabs (vim etc. still get it on the terminal). Swipe-up closes the
  Search tab only at the page's end. Verified (`-tabtest`, Debug): 14 checks OK (switching,
  focus, ⌘-keys, a real Google search ~1–2 s, swipe rule at top/end, interrupted motions, tab
  switch mid-open); Search snapshot vs live at rest: visually identical (WebKit's picture vs
  its on-screen render differ at anti-aliasing level, median 15/255, plus the overlay scroll
  bar, which WebKit leaves out); pacing on Search 0 late frames, open/close calls 2.5–6 ms
  (like the terminal). Terminal tab vs the pre-tabs build: every `-effecttest` pose/rest/swap
  PNG byte-identical below the band, same numbers, `-selftest` identical, 32 unit tests.
  Unverified (needs the user): typing in Google's own fields, IME in the search field, sign-in
  pages, video/audio while closed (the hidden web view may pause media), feel of the band.

- **Phase 13 (hover warp):** the user's spec (2026-10-01): reuse the distortion system, subtle
  liquid glass under the pointer, press squash + click haptic, droplet indicator, confined to
  the control, zero cost at rest, Off/Reduce Motion fall back to the plain control. The open/
  close tuning is unchanged (`JellySpring` is the old loop, verified equal step by step).
  Verified (`-hovertest`, Debug; hover driven through `ControlLens.hover(at:)` because
  synthetic `mouseMoved` events don't reach SwiftUI's hover tracking): breath peaks at 0.95 →
  rests at 0.40; warp confined to control + margin on a tab segment and the Reload button
  (never the notch gap/card); exit → 0 px vs before; shader attached at ~zero strength → 0 px
  (no tick on enter/exit); press squash 1.04 × 0.90 then rebound; click → Search with the
  indicator stretching to 0.10, landing at −0.005, resting at exactly 1 × 1; Off → 0 px change;
  Reduce Motion → jump, no lens, no squash; closing leaves nothing running. 120 Hz pointer glide
  + typing into the terminal: 0–1 late frames (same noise as the baseline that day), main-thread
  p95 ~3.5 ms, each key handled in p95 0.6 ms. `-effecttest`/`-selftest` as before; 38 unit
  tests. Tab labels now render through the effect's offscreen layer: sub-pixel anti-aliasing
  differences vs Phase 12's capture (invisible), identical before/during-at-zero/after a hover.

- **Phase 14 (swipe, tab UI, Claude):** why swiping "didn't work": it was never built (no scroll
  monitor; the multitouch recognizer ignores sideways moves; it could also start a close on a
  sideways swipe drifting up — closing now needs a clearly vertical start). Verified
  (`-swipetest`): commit by distance and flick, snap back, rubber band ±0.12 exactly, vertical
  scroll passes through, web-page sideways edge rule, interruption, momentum ignored, the
  watchdog for a lost fingers-up event. First-time costs (a web view's first appearance, the
  search field's first focus) moved to launch (`warmUpEffects`). `-claudeprobe`: claude.ai
  loads (no Cloudflare block); "Continue with Google" opens Google's popup flow
  (`display=popup`) and Google's sign-in page loads in it ("Sign in to continue to Claude");
  the email field is found and focusable (not submitted); an image pasted through ⌘V's path
  reaches the page as a PNG file; the web view accepts PNG and file drags. Unverified (needs
  the user's account / hardware): Google's password step, email magic link, staying signed in
  after a restart, real drag of an image.

- **Phase 15 (settings):** the user (2026-10-01) wanted the open panel's size adjustable, the
  glass strength, and the screen warp as a Performance ↔ Quality slider, all in the Settings
  window (the menu bar item keeps Settings… and Quit DEXMA). `RenderQuality` (Core/Settings):
  Performance = no capture at all; Balanced = the warp only while the notch moves
  (`ScreenBender.warpsAtRest` off: no resting warp, no pointer lens); Quality = also the resting
  warp and the pointer lens. Replaces the `screenWarp` switch (on → Quality, off →
  Performance). Verified: `-sizetest` (smallest 480 × 260, default, largest 1100 × 720: card,
  pages, web views, terminal follow; the pill drops to icons when labels don't fit),
  `-warptest` (Balanced stops capture once open, Performance never captures).

- **Phase 16 (Draw to ask):** see *Capture*. Verified with `-capturetest` (synthetic frozen
  screen; real freezes when launched with `open`): overlay orientation, drawing pacing, outline
  on the rectangle after the morph, crop pixel size (1256×752 for a 628×376 pt box at 2x),
  overlay gone before the panel settles, real paste into a stand-in of claude.ai's composer
  (served as https://claude.ai/new) with the clipboard restored and the caret in the box,
  click-to-window (1000×640), Esc while freezing/drawing/selecting/flying, the file-input
  fallback, the chip (signed out → attaches when the box appears; timeout → retry), Reduce
  Motion, real freezes 22–53 ms at 3024×1964 with the open panel absent. On the real claude.ai:
  the composer is `[data-testid=chat-input]` (TipTap), the attach input `file-upload`; a real
  paste reached the page with the file (probe, 2026-10-02). Unverified: the attachment on the
  real composer and sending it (the Claude tab got signed out between two probe runs that day —
  cause unknown; the user has to sign in again), the Settings section's look, saving copies,
  new chat per capture, the onboarding sheet and relaunch, a second display, the feel.

- **Phase 17 (Devices):** see *Devices*. Verified: 0 warnings Debug/Release; unit tests (frame
  decoder incl. split/corrupt/fragment/legacy, CRC vectors, Buds3 Pro extended status with
  charging, unknown case/disconnected bud, per-model layouts, identification incl. renamed
  "Mewo", device merge/staleness/fallback display, relative time, low battery policy, store
  events and persistence, pill layout and shape blend); `-devicetest` (mock Buds through the
  store): no peek before a reading, peek text, pill 421 × 52 (notch 185 × 32) with the
  silhouette matching, no key/frontmost/click-through change, pointer zone, live update,
  collapse after 3 s, red peek at 20 % and 10 % only, case kept when unknown, click → open on
  Devices, band summary, page picture 650 × 350 @2x, ⌘1/⌘4/⌃Tab, 4 pages, no peek while open,
  "Last seen just now", values kept, close/reopen, forget; pacing: the first motion after
  launch drops ~3 frames on the existing hover peek too, after that both device peeks 0 late
  frames of ~150 (step p95 ~1 ms) in two runs; `-swipetest` all OK (rubber band past Devices),
  `-sizetest` OK at all sizes, `-selftest` as before; `-hovertest`'s 3 confinement FAILs are
  identical on the base commit (live video behind the warp; the Reset button moved when the
  Capture button came) — pre-existing. Release: mock menu absent, launches with "Buds
  monitor: on", 0.0 % CPU idle. Bluetooth was already allowed for DEXMA. The full-screen check
  saw the user's full-screen spaces (type 4) correctly. Unverified (needs the Buds): the real
  RFCOMM stream on the Buds3 Pro (SDP records, channel, first 0x61, charging offset 42), the
  fallback's sources for these Buds, connect/disconnect notifications on hardware, energy.

## Hardware test checklist (needs the user)
- Tabs: ⌘1/⌘2/⌘L, clicking segments, focus after reopening (page vs field), Esc on both tabs.
- Search: a Google search, typing in Google's own fields, IME in the field, link clicks,
  target=_blank links, back/forward/reload/open in browser, swipe-up closes only at the page's
  end, video/audio while closed, sign-in pages.
- Hover warp on the tab segments (both tabs) and the Search buttons; cursor-follow smoothness;
  exit decays fully to crisp text; press squash (and the spring back); the click tick (not on
  hover); the indicator's droplet stretch when switching tabs.
- Effect intensity Off (plain hover fill only); Reduce Motion (no warp/squash, instant
  indicator).
- Terminal typing stays smooth while hovering the band.
- The open/close effect on all three tabs feels as before (no blank frames).
- Settings: open panel size sliders (live), glass effect strength, Performance / Balanced /
  Quality (recording indicator: never / only while moving / while open).
- Swipe on each tab: slow, fast flick, half swipe and release, vertical scroll still works,
  horizontal scrolling inside web pages; the pill, indicator, dots and context following it.
- Terminal context: cwd updates after `cd`, the running dot during `sleep 5`.
- Card stroke/highlight; no seams on the web tabs.
- Draw to ask: see the checklist given on 2026-10-02 (button on all tabs, ⌥⇧` with the panel
  closed, frozen video, glow/hint, long scribbles, morph, click-to-window, Esc at every stage,
  Retina sharpness, flight, attaches and sends, clipboard restored, chip when signed out, new
  chat, onboarding, second display, Reduce Motion, no DEXMA in captures).
- Devices: see the checklist given on 2026-10-05 (connect peek values, bud in/out of the case,
  last seen, the case's own time, charging colours, low-battery peek, restart, ⌘4/swipe/hover,
  mock menu absent in Release, energy impact).
- Claude: sign-in (Google popup, email + ⌘L link), still signed in after a restart, focus
  in the message box, New chat, Open in browser, external links in the browser, pasting
  and dragging an image, page zoom.

## Debug snapshots
Screen Recording isn't granted to the CLI, but an app can render its own window. Debug builds
(`DEXMA/Debug/`, flags dispatched by `DebugHarness`) accept `-selftest` (open/close via the controller, printing key window, first responder and
frontmost app at each step) and `-snapshot <dir>`: they type `ls /` into the shell, render the panel at progress
0/0.15/0.5/1 to PNGs, and quit. Run the binary directly:
`.../Debug/DEXMA.app/Contents/MacOS/DEXMA -snapshot /tmp/snap`, then view the PNGs.
`-budsprobe` runs the Buds identification on every paired headset's cached SDP records (no
radio) and prints the model and status channel (launch with `open -n <app> --stdout <file>
--args -budsprobe`).
`-devicetest <dir>` checks the Devices tab and the connect peek with mock Buds (launch it with
`open -n <app> --stdout <dir>/out.txt --args -devicetest <dir>`, read out.txt + PNGs); it also
starts the real Buds monitor once (other harness runs never touch Bluetooth).
`-capturetest <dir>` checks Draw to ask end to end (see Progress, Phase 16; it covers the
built-in display with the overlay for ~2 min and borrows the clipboard, restoring it); launch it
with `open -n <app> --args -capturetest <dir>` to include real freezes, then read
`<dir>/report.txt`. `-hovertest <dir>` checks the band controls' liquid glass (lens, confinement, exit, press,
indicator, Off, Reduce Motion, pacing with typing); `-bandshot <dir>` just captures the open
band at rest (for comparing builds). `-tabtest <dir>` checks the tabs and the Search tab (needs network: it runs a real Google
search; launched with `open` it also captures the real screen). `-effecttest <dir>` checks the liquid effect against the window server's own composite of the
panel (`CGWindowListCreateImage` via `dlsym`: deprecated, but an app may capture its own
window without Screen Recording): snapshot fidelity, motion layer vs live at rest, a real
swap-back frame by frame, frame pacing with the effect on/off, gesture/interruption end
states, and posed PNGs (composite them over a grey background to see the rim light). It turns
off close-on-focus-loss, because the user's Mac is usually in use while it runs (another app
taking focus closed the panel mid-test and looked like a bug). `-warptest <dir>` measures the
screen warp; it needs DEXMA's Screen Recording grant, so launch it with
`open -n -W <Debug DEXMA.app> --args -warptest <dir>` (a shell launch inherits the terminal's
TCC) and read `<dir>/report.txt` + PNGs of the real screen. Always
check the build succeeded first — a failed build leaves the old binary, which ignores the flag
and never quits (wrap runs in a watchdog).

## Project facts
- Xcode 26.2, Swift 6.2 compiler in Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION =
  MainActor` + approachable concurrency: everything is `@MainActor` unless marked
  `nonisolated`. C callbacks (Carbon, CGEventTap, multitouch) must be `nonisolated`
  functions; hop with `MainActor.assumeIsolated` only when the callback is known to arrive
  on the main thread.
- Project `DEXMA.xcodeproj`, target/scheme `DEXMA` (tests `DEXMATests`, `DEXMAUITests`);
  sources in `DEXMA/` (layout under *Architecture*), unit tests in `DEXMATests/` mirroring it.
  Swift module `DEXMA` (`@testable import DEXMA`).
- Settings (now in the project): deployment target macOS 14.0, `LSUIElement` = YES, App Sandbox
  OFF, Hardened Runtime ON, product and display name DEXMA, SPM packages SwiftTerm
  (upToNextMajor 1.20.0) + OpenMultitouchSupport (upToNextMinor 3.0.3). Bundle id is still
  the legacy `com.jasontio.terminal-application` until the user changes it in Xcode
  (recommended `com.jasontio.dexma`); `DefaultsMigration` carries settings across. A new
  bundle id also means re-granting Accessibility and re-enabling Launch at Login.
- The Debug `-selftest` deletes the `panelWidth` and `hotKey` defaults when it finishes, and
  `-sizetest` `panelWidth`/`panelHeight` (real prefs domain): back up the user's prefs first
  (the user has `panelWidth` = 670) and restore them after.
- Devices are stored in `~/Library/Application Support/DEXMA/devices.json` (shared by Debug and
  Release; mock devices only survive in Debug).
- Release build: `scripts/dexma` (the user's `dexma` alias in ~/.zshrc): builds Release
  incrementally (a failed build leaves the running app alone), `ditto`s it to `build/DEXMA.app`
  (git-ignored), quits the running DEXMA (SIGTERM, which DEXMA turns into a normal quit) and
  `open`s the new one. `-d` Debug, `-n` no build, `-p` pull first, `-q` quit, `-l` log stream.
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
- SwiftUI `layerEffect`: it may run per drawn item (light added once per item → boxes):
  `.compositingGroup()` first; it skips transparent areas: give the view a 0.004-alpha base;
  even with `isEnabled: false` it renders the view offscreen (text anti-aliased differently
  from the plain view), so toggle `isEnabled`, don't add/remove the modifier.
- Synthetic `mouseMoved` events sent to the panel don't drive SwiftUI's
  `onHover`/`onContinuousHover` (they follow the real cursor); clicks do work.
- Toggling `isEnabled` of a `layerEffect`/`distortionEffect` on a visible layer draws one frame
  of its content offset; only toggle while the layer is hidden (opacity 0).
- WebKit stops painting while the screen is locked or asleep: debug captures of web pages
  then show an empty card (check `CGSessionCopyCurrentDictionary` / `pmset -g log`).
- A `layerEffect`/`distortionEffect` can't contain AppKit views (NSTextField, representables):
  the chrome's text field and the pulsing dot are AppKit overlays above the hosting view.
- Synthetic scroll events need real timestamps (`CGEvent.timestamp`), or every speed is 0.
- The display turning off pauses `CADisplayLink`: debug runs while the Mac sleeps its display
  show progress frozen and "0 frames" — not a bug (check `pmset -g log`).
- A `WKWebView` added to a zero-sized superview with autoresizing grows by the superview's
  whole size when that gets its frame (the page showed 2× and cut off): set its frame outright.
- `cacheDisplay` over a view containing a `WKWebView` makes WebKit render synchronously
  (~20 ms): picture around it and use `takeSnapshot` (async) for the page.
- Making the search field first responder and selecting its text costs ~2–8 ms with the panel
  becoming key; keep it off the open path when the page had the keyboard.
- SwiftUI shaders: `layerEffect`/`distortionEffect` exist on macOS 14; `Shader.compile(as:)`
  is macOS 15+ (on 14, render the effect once at launch to warm it).
- A layer-hosting view's layer gets its geometry flip from the view's `isFlipped`: setting
  `isGeometryFlipped` on that layer is overridden. The capture canvas is a flipped view
  (`CaptureCanvasView`); before, strokes drew mirrored top to bottom (`-captureorient` checks).
  Test with strokes that aren't symmetric about the screen's centre.
- KVC/`CAAnimation` values of `CATransform3D` must be `NSValue(caTransform3D:)`.
- A `CABasicAnimation` with only `toValue`, added right after setting the model value, jumps:
  give it `fromValue`.
- Animating a path re-strokes it in the window server every frame: five display-wide shape
  layers × 1,500 curves made it fall behind (the window picture showed a stale mid-morph frame).
- `CGContextDrawConicGradient` has no Swift member name: call the C function.
- Measuring the window server: `ps -o time= -p $(pgrep -x WindowServer)` before/after. Any
  120 Hz animation costs it ~50 % of a core on the reference Mac (notch or overlay alike).
- `pkill -f <pattern>` in a watchdog also matches the shell running it (killed the tool call):
  poll for the report file instead.
- `CGWindowListCopyWindowInfo` lists front to back; names need Screen Recording, bounds don't.
- `NSApp.currentSystemPresentationOptions` doesn't report another app's full screen (0 while
  the user was in full-screen spaces); the CGS managed-spaces `type` (4) does.
- IOBluetooth: `isConnected()` is false in DEXMA for a device connected by macOS (audio) until
  this process `openConnection`s it — never gate on it after a connect notification.
- IOBluetooth: a renamed headset has no cached SDP records until something queries it; query
  with `performSDPQuery(_:)` (the UUID variant returns nothing); `IOBluetoothRFCOMMChannel`'s
  close is `close()` in Swift. Delegate callbacks are `nonisolated` here, hopping to main.
- Local `func`s inside a `Task { @MainActor in … }` aren't main-actor isolated in this build
  setup (warnings): mark them `@MainActor`.
- `ImageRenderer` renders a SwiftUI view to a `CGImage` with its text (unlike `cacheDisplay`).
- Built-in display brightness: DisplayServices (private) works, `CanChangeBrightness` is false
  for an external monitor; `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` needs
  `import AudioToolbox`.
