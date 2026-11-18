# Home-screen smoothness report

Prepared 2026-11-12 for the review sessions starting 2026-11-13.
Scope: every animation on the home screen (page swipes, drawer, overview, edit and resize, widgets, opening apps and coming back home), on the iQOO at 120 Hz.
Stack: Flutter 3.47.5 with Impeller, `RenderMode.surface`, app widgets shown through `AndroidView`.

This is research only: no code was changed. The `file:line` references are as of today's working tree.

---

## 1. Summary

**Target.** At 120 Hz each frame has **8.3 ms** in total, and the UI thread (build and layout) and the raster thread (GPU) each need to stay **under about 8 ms**. Any one-off spike, such as a rebuild, an image decode or a platform-channel reply at the wrong moment, shows up as a visible hitch. Steady per-frame cost on the raster thread is what makes swipes feel heavy.

**Four root causes.**

1. **The glass effect re-blurs on every frame.**
   - Every `WallpaperGlass` re-blurs the wallpaper (a `saveLayer` with blur) on every frame it moves or repaints.
   - It also runs a real `BackdropFilter` on top. That is two blurs per glass item per frame.
   - The dock, glass folders, glass widgets and glass clocks all use it.
2. **Clocks and other tickers repaint into the glass.**
   - Per-second clock tick animations (31–46 frames every second) have no `RepaintBoundary`.
   - Each of those frames re-blurs the glass panel behind them, all day long.
   - So the raster thread is already busy when a swipe starts.
3. **Rebuilds are scoped too broadly.**
   - `HomeScreen`, `StandardHome`, `Dock` and others `watch` the entire `HomeLayoutController`.
   - Every notification (drag, select, interacting, fit) rebuilds the whole home tree and re-runs `arrange()`.
4. **Work fires during system transitions.**
   - On every resume the wallpaper is re-fetched over the channel, decoded and swapped in, which repaints every glass item.
   - The app list, home role and blur state are also refreshed then.
   - All of this happens exactly while Android is playing the "back to home" animation.

**Ten fixes, in the order to do them:**

| # | Fix | Effort | Expected win |
|---|-----|--------|--------------|
| 1 | Pre-blur the wallpaper **once** into a small `ui.Image`. Glass then just draws that image, with no per-frame blur, and drops `BackdropFilter` once the image is loaded. | M | **Largest**: removes 2 blurs per glass item per frame |
| 2 | Put `RepaintBoundary` around clock hands, futuristic faces, the digital time and the instant hint, and inside `WallpaperGlass` around its child. | S (~10 lines) | Stops the all-day re-blur |
| 3 | On resume, skip the wallpaper reload when it hasn't changed (compare an id or hash natively). Defer the other refreshes until the return animation has finished (~400 ms). | S | Removes the hitch when coming back home |
| 4 | Replace broad `context.watch<HomeLayoutController>()` with `select`. Move the work done in `build`/post-frame (`arrange`, `fitWidgetsTo`, controller writes) out of the hot path. | M | Fewer and cheaper rebuilds during drags |
| 5 | Make the drawer **follow the finger** (drag-driven route, velocity-based settle) instead of a fixed 220 ms play after a fling. | M | Largest gain in *perceived* snappiness |
| 6 | Open apps with an icon-origin animation (`ActivityOptions.makeScaleUpAnimation` / `makeClipRevealAnimation`). | S–M | Launches feel attached to the icon |
| 7 | Freeze `AndroidView` app widgets while they are dragged or resized (snapshot plus `Transform`), and resize natively only on release. Move `setLook` out of `build()`. | M | Resize and drag without jank |
| 8 | Pause every timer and ticker when it is off-screen, covered or in the background (`TickerMode`, lifecycle, page visibility). | S | Idle and battery win, fewer surprise frames |
| 9 | Cache `TextPainter`s, paths and `ColorScheme.fromSeed` results instead of recomputing them on every paint or build. Quantise icon `cacheWidth`. | S–M | Lower UI and raster cost per frame |
| 10 | Try **HCPP** (new platform-view mode, Flutter 3.44+, API 34+, Vulkan). Confirm Impeller is using Vulkan on the iQOO. | S (experiment) | App widgets composited natively |

---

## 2. Measure first (morning of day 1)

We need numbers before and after each fix, otherwise "smoother" is guesswork.

### 2.1 Tools

- **In-app frame meter (recommended to build first).**
  - A small hidden overlay, toggled from settings, that uses `SchedulerBinding.instance.addTimingsCallback`.
  - It shows the build and raster ms for the last ~120 frames, plus a count of frames over 8.3 ms.
  - It works in the **release** build we actually install (memory: profile and debug builds are DEBUGGABLE and janky on this phone, so they can't be judged by feel).
  - It costs nothing when switched off.
- **DevTools in profile mode** (`flutter run --profile`), only for *finding* the cause, never for judging feel.
  - Performance view: timeline, "Track widget builds", "Track layouts", "Track paints".
  - Enable `checkerboardOffscreenLayers` to see every `saveLayer` on screen.
- **Perfetto / system trace** (`adb shell perfetto` or the Android Studio profiler). This shows the SurfaceFlinger side: missed vsyncs, RenderThread, and what the platform thread is doing during resume.
- **`adb shell dumpsys SurfaceFlinger --latency <layer>`** and **`dumpsys gfxinfo`**. These only give partial data for Flutter's SurfaceView, but are useful for the native app-widget views.
- Confirm the renderer: `adb logcat | grep -i impeller`. It should say **Vulkan**. If it falls back to OpenGLES, HCPP is off the table and blur costs more.

### 2.2 Fixed test script (run it before and after each change)

1. Swipe pages left and right 10 times (standard mode, a page with the glass dock, a glass clock and an app widget).
2. Open and close the drawer 10 times; fling to open it, and drag slowly.
3. Long-press empty space to open the overview and close it, 5 times.
4. Edit mode: drag an icon across pages; resize an app widget; resize a glass widget.
5. Open an app from an icon and press Home, 5 times (the resume path).
6. Leave home idle for 60 s and count frames (it should be about 1–2 per second at most with clocks shown, and 0 without).

Record: janky-frame count, worst frame, and the average raster ms for each scenario. Keep a table in this file.

---

## 3. Findings by section

Severity: **H** visibly janks, **M** costs frame budget, **L** worth cleaning.

### 3.1 Glass: `lib/features/appearance/wallpaper_glass.dart`

- **H: two blurs on every frame.**
  - `:30-33` is a `BackdropFilter(blur σ15)`.
  - Inside it, `_RenderWallpaperPatch.paint` (`:111-131`) does a `saveLayer` with `ImageFilter.blur` over a `drawImageRect` of the wallpaper.
- **H: it repaints on every frame while it moves.** `:101-108` checks the transform after every frame and calls `markNeedsPaint`. During a page swipe or route animation, every glass item re-runs both blurs each frame. N glass items means 2N blurs per frame.
- **The BackdropFilter adds almost nothing.** Android draws the wallpaper behind the window, out of `BackdropFilter`'s reach. So once the patch image has loaded, the backdrop only blurs Flutter content behind the item, which is usually transparent, and it pays full cost to do so.
- **Fix:**
  - When the wallpaper loads (`WindowBlurPlatform.refreshWallpaper`), produce **one pre-blurred, downscaled image**.
    - Decode it at 1/4 screen size.
    - Blur it once via `PictureRecorder`, a `saveLayer` with blur and `toImage`, off the critical path.
    - Store it as `blurredWallpaper`.
  - `_RenderWallpaperPatch` then just `drawImageRect`s the right part of it, which is a plain textured quad and very cheap even at 120 Hz.
  - Drop the `BackdropFilter` when the pre-blurred image exists. Keep it only as the "not loaded yet" fallback.
  - Optional: keep the per-frame position check (it is now cheap), or drive it from the scroll and route animation directly.
- **Watch for:** memory (one image of about 270×600 is fine) and getting the blur radius to match visually after downscaling (σ/4).

### 3.2 Home shell: `lib/features/home/home_screen.dart`

- **M: the whole home rebuilds on every layout notification.**
  - `:47-53` `watch`es `VisibleApps`, `HomeAppsController` and **the entire** `HomeLayoutController`. Any `notifyListeners()` (drag start and end, select, `setInteracting`, fit) rebuilds the Scaffold and everything under it.
  - **Fix:** `select` only `mode`, `editing`, `dragging`, `grid`, `widgets.isNotEmpty` and `showLabels`, and push the rest down to the leaves that need it.
- **M: `_HomeWidgets` (`:236-243`) writes controller state in `build` and schedules work on every build.**
  - It writes `layout.cellSize` and schedules `addPostFrameCallback(fitWidgetsTo)` on **every** build.
  - If `fitWidgetsTo` notifies, that causes another rebuild.
  - **Fix:** run it only when `cell` actually changes (remember the last value).
- **M: home fade on drawer open (`:76-79`).**
  - An `AnimatedOpacity` (160 ms) over the whole home, which contains glass and app widgets (`AndroidView`), runs at the same time as the drawer's own fade and slide.
  - That means two full-screen offscreen layers for those frames.
  - **Fix options:**
    - (a) Drive home's opacity from the **drawer route's own animation**, so there is one synchronised curve instead of two independent ones.
    - (b) Don't fade at all: hide home (`Visibility(maintainState: true)` or `Offstage`) once the drawer is fully opaque, and show it again at the start of the close.
  - Also wrap covered home in `TickerMode(enabled: false)` while something is on top, so clocks stop ticking while invisible. (Navigator doesn't do this for routes under a non-opaque route.)
- **L:** `PopScope` rebuilds with `layout.editing`. That is fine once the `select` fix is in.

### 3.3 Drawer and quick-search route: `lib/core/routing/app_routes.dart:84-108`, `features/app_drawer/`

- **Feel: the drawer is not attached to the finger.**
  - Today a fling at more than 300 px/s *triggers* a fixed 220 ms `easeOutCubic` (`home_screen.dart:186-190`).
  - Snappy launchers (Pixel, Lawnchair, Niagara) move the drawer **with the finger** and settle with the release velocity.
  - **Fix:**
    - Push the route on drag start (or keep the drawer pre-built, see the next point).
    - Set `route.controller.value` from the drag delta.
    - On release, `animateWith(SpringSimulation(...))` or `fling(velocity)`.
    - Use a critically damped spring: stiffness of about 600–900, damping ratio 1.0.
    - Apply the same idea to dragging the drawer down to close it (from the list top).
- **First-frame cost.**
  - The drawer is built when it is pushed, so frame 1 of the animation includes building the whole app list, laying out the grid and decoding every visible icon.
  - That is the classic "first frame of the drawer hitches".
  - **Fix options:**
    - Keep the drawer built behind home (offstage, `TickerMode` off) and animate it in.
    - Or at least pre-warm on idle with `precacheImage` for the first screen of icons and lazy grids (`GridView.builder`). Check whether the drawer list is already lazy.
- The fade plus slide of 0.08 is fine. Keep the slide; consider dropping the fade when the drawer is drag-driven.

### 3.4 Overview (long-press): `lib/features/home/home_overview.dart`

- **M: a frosted bar that animates into place.**
  - `_ActionsDock` (`:239-242`) is a `BackdropFilter σ24` inside an `Opacity` plus `Transform` animation (`:181-190`).
  - Each `_PopIn` (`:291`) is a further `Opacity`. That is a saveLayer per button, per frame, for 420 ms.
  - **Fix:**
    - Use the pre-blurred wallpaper glass (3.1) instead of `BackdropFilter`.
    - Replace `Opacity`+`Transform` with `FadeTransition`/`SlideTransition`/`ScaleTransition` driven directly by `_progress` with `Interval` curves. These don't rebuild the subtree each tick.
    - Use `AnimatedBuilder`'s `child` for the static parts.
- **L:** `_HiddenWhenOpen` fades the home dock with a separate `AnimatedOpacity` (200 ms) while the overview dock animates in (420 ms) with a different curve. Synchronise them to the one controller.
- **L:** `setState(_beforeTidyUp = null)` on open rebuilds the whole overview, including home, in the same frame as the haptic. That is fine, but check the trace.

### 3.5 Standard home pager: `lib/features/standard_home/standard_home.dart`

- **M: `build` is heavy and runs often.**
  - `:104` `watch`es all of `HomeLayoutController`, and `:72-77` `watch`es `VisibleApps`, `DockController` and items.
  - `arrange()` (`:122-128`) runs on **every** build.
  - A post-frame callback (`:130-158`) then writes five controller fields and may `commitSlots`, which notifies and rebuilds again.
  - `layout.currentPage = _page` is written during build (`:162`).
- **Fixes:**
  - Memoise `arrange()` on its inputs (items, slots, columns, rows, priority).
  - Only commit or notify when something really changed.
  - Never notify from inside a build or post-frame of the same listener chain.
  - Use `select` for `editing`, `dragging` and `selected`.
- **M: `onPageChanged` calls `setState(_page)`, which rebuilds the whole `StandardHome` including the `PageView`.** This happens at the *midpoint* of a swipe, mid-animation. Move `_page` into a `ValueNotifier` that only the dots and scrubber listen to.
- **Check:** each `_Page` is a heavy subtree. `PageView` already adds `RepaintBoundary` per page; confirm in DevTools that neighbouring pages don't rebuild during a swipe.
- **Feel:** consider custom `PageView` physics so the page settles quicker. Use `PageScrollPhysics` with a stiffer spring (e.g. `SpringDescription.withDampingRatio(mass: 0.5, stiffness: 500, ratio: 1.0)`). Pixel launchers settle in about 250 ms.
- **Edit mode:** `AnimatedOpacity` at `:862`, `:877` and `:942`, plus the frame handles' `setState` per drag delta (`frame_handles.dart:276`, `:604`). Make sure only the handle overlay rebuilds per pointer move, not the page.

### 3.6 Dock: `lib/features/dock/dock.dart`

- **M:** `:93` `watch`es the whole `HomeLayoutController`, so the glass dock rebuilds on every layout notification during drags. Use `select` for `grid`, `dragging` and `mode`.
- The dock is glass, so it gets the 3.1 win directly. It is on screen during **every** swipe and drawer open.
- **L:** the drag feedback at `size*1.06` (`:372`) forces a fresh icon decode at drag start. Reuse the same `cacheWidth`.

### 3.7 Clocks: `lib/features/widgets/clock/`

- **H: no `RepaintBoundary` around the ticking parts, so every tick frame re-blurs the glass.**
  - Analog: a 260 ms tick every second (`analog_clock.dart:137,147`), about 31 frames per second at 120 Hz. The hands are not isolated (only the dial is, at `:191`), and the face sits inside `WallpaperGlass` (`:767`).
  - Futuristic: a 380 ms tick (`futuristic_clock.dart:94,104`), about 46 frames per second, with nothing isolated.
  - Digital: the gradient `ShaderMask` (`digital_clock.dart:604`) is a saveLayer that re-runs every second when seconds are shown.
  - **Fix:** `RepaintBoundary` around the hands' `AnimatedBuilder`, the whole futuristic `CustomPaint` and the digital `_Time`.
- **M: futuristic painters allocate on every frame.**
  - New `TextPainter`s with layout every paint (`:226-253`, gauge `:681-700`, terminal `:706-728`).
  - The matrix face draws about 625 `drawCircle`s per frame (`:497`).
  - The pulse face builds a 120-segment path with `exp()` per frame (`:574`).
  - **Fix:**
    - Cache text and paths per second, since they only change when `now` changes.
    - Record the static grid once into a `ui.Picture`.
    - Animate only what moves.
- **M: analog hand shadows use `MaskFilter.blur` on 2–3 paths per tick frame** (`analog_clock.dart:613-619`). Use an offset, low-alpha solid shadow instead (this also fits the "flat crisp, no glow" taste).
- **M: each tick's `setState` rebuilds the background disc.** `ClockBackground` / `_MaterialDisc` runs `ColorScheme.fromSeed` every second (`:795`). Keep it outside the ticking subtree, or memoise the scheme per seed.
- **M: clock timers ignore visibility.**
  - The `Timer`s (`analog:147`, `futuristic:104`, `digital:479`) keep calling `setState` on off-screen pages, under the drawer and while backgrounded.
  - **Fix:** skip the `setState` (but keep the timer cheap) when `TickerMode.valuesOf(context).enabled` is false or the app isn't resumed. Re-sync on becoming visible.
- **Good already:** the analog dial is isolated; ticks are short eased steps, not a 120 Hz sweep; `shouldRepaint` is implemented correctly.

### 3.8 Music widget: `lib/features/widgets/music/music_widget.dart`

- **L/M:** `:130` `watch`es the whole `NowPlayingController`, so every media event (position, metadata) rebuilds the full widget, including its `AnimatedSwitcher` and `LayoutBuilder`. Use `select` for title, artist, art and playing per sub-part.
- **L:** nested blurs. `_GlassPlay` is a `BackdropFilter` (`:695`) inside the glass panel, and `_VolumeGauge`'s blur (`:393`) is only shown mid-drag. Replace them with a pre-blurred patch or a flat translucent fill.
- **L:** the cover's `BoxShadow` blur 12 (`:637`) sits inside an `AnimatedSwitcher` fade, which is a saveLayer with a blur during the fade. Pre-render the shadow, or fade the image without the shadow.
- **Good already:** the cover is decoded at drawn size and art bytes are reused; progress ticks per second inside its own `RepaintBoundary`.

### 3.9 Instant widget: `lib/features/widgets/instant/instant_widget.dart`

- **M:** the hint-rotation `Timer.periodic` (3.2 s, `:370`) with a 280 ms fade and slide (`:406-420`) never pauses, and repaints into its glass panel with no boundary. **Fix:** `RepaintBoundary`, and pause on `TickerMode` off or background.

### 3.10 Activity, Chrome and controls widgets

- **M: activity (`activity_widget.dart:110-124`) rebuilds its theme on every build.**
  - It calls `ColorScheme.fromSeed` and `Theme.copyWith` on every build, and `watch<AppsController>` rebuilds it on any app-list change. Because of its `LayoutBuilder`, this also runs per frame during resize.
  - **Fix:** cache per seed, and `select` only the apps it shows.
- **M: icons sized from layout re-decode during resize.**
  - `activity_widget.dart:677,754` and Chrome's `_SiteFace` (`chrome_widget.dart:250-263`) pass sizes from layout into `cacheWidth`.
  - So every resize frame means a new image-cache key and a re-decode.
  - **Fix:** quantise `cacheWidth` to buckets (48/64/96/128/192 px) in `AppIcon` (`core/widgets/app_icon.dart:33`).
- **L: brightness and volume controllers (`display_controller.dart:13-15,58`, `sound_controller.dart:14`).**
  - They listen to native changes for the app's whole lifetime and call `notifyListeners()` even when nothing changed. Auto-brightness fires often.
  - **Fix:** notify only on a real change, and attach or detach with visibility and lifecycle like the other controllers.
- **L:** the `_SunPainter` saveLayers (`brightness_widget.dart:167,195`) only run on change. They are acceptable.

### 3.11 Android app widgets (`AndroidView`): `lib/features/widgets/home_widget_view.dart:240-282`

- **Current mode:** `AndroidView` means **Texture Layer Hybrid Composition**. Flutter's docs say this is good for transforms but *janky during quick scrolling*, and it falls back to plain Hybrid Composition, which merges the raster and platform threads, if the widget contains a SurfaceView.
- **H: resize and drag.** The native view gets fractional sizes every frame, which means a native measure/layout plus a texture reallocation per frame.
  - **Fix:** while dragging or resizing, show a **snapshot** (a bitmap from native, or the last texture) scaled with `Transform`, and apply the real size on release.
- **M:** `platform.setLook()` is a channel call **inside `build()`** (`:250`). It is deduped by value, but the scale changes continuously while resizing. Move it to `didUpdateWidget` or post-frame, and throttle it.
- **L:** `_PixelSnapped` calls `localToGlobal` on every paint. It is cheap, but runs on every swipe frame. Fine.
- **Experiment, HCPP:**
  - Hybrid Composition++ (Flutter 3.44+, experimental).
  - Requirements: Android API 34+, Vulkan and Impeller. Check the iQOO's Android version and the logcat renderer line.
  - The platform view and Flutter both render to native surfaces composited by SurfaceFlinger, with "full fidelity and performance".
  - Enable it in `AndroidManifest.xml` inside `<application>`:
    ```xml
    <meta-data android:name="io.flutter.embedding.android.EnableHcpp" android:value="true" />
    ```
  - Test the whole script with and without it: transparency, rounded corners (`ViewOutlineProvider`), opacity fades and drag-to-scroll widgets.
  - Known limitation: transparent platform views break when stacked as canvas → view → overlay → transparent view.

### 3.12 Opening apps and coming back home

- **H: the resume path does heavy work during the system's "back to home" animation.**
  - `app.dart` `onResume` runs `apps.refresh()`, `homeRole.refresh()`, `FullScreenWebController.refresh()`, `HoldSearchController.refresh()`, `WindowBlurPlatform.refresh()` and **`refreshWallpaper()`**.
  - `refreshWallpaper` (`window_blur_platform.dart:38-55`) asks native for the wallpaper bytes, decodes them, and *always* replaces the image and calls `notifyListeners()`. Every glass item then repaints, and with 3.1 not done yet, re-blurs.
  - On the native side the wallpaper is probably re-encoded on the platform thread each time (to verify).
  - **Fix:**
    - Natively, compare the wallpaper id (`WallpaperManager.getWallpaperId`) or a cheap hash and return "unchanged".
    - Only notify on a real change.
    - Defer the other refreshes by about 400 ms, or until the first idle frame after resume, so the system animation and our first frames are clean.
- **M: app launch has no origin animation.**
  - `LauncherChannel.kt:116-119` calls `startActivity(intent)` with no `ActivityOptions`, so you get the system default (or vivo's) open animation, not one growing from the icon.
  - **Fix:** pass the tapped icon's rect from Dart, and use `ActivityOptions.makeScaleUpAnimation(view, x, y, w, h)` or `makeClipRevealAnimation`. Apply it to `LauncherApps.startMainActivity(..., opts.toBundle())` too, if used.
  - Note: real Launcher3-style "app shrinks back into its icon" on return needs the system `RemoteAnimation` permission, which isn't available to us. Some OEMs (vivo) apply their own launcher animation anyway; test what the iQOO does.
- **Optional polish on return:** a subtle home "settle" (scale 0.97 to 1 with fade, about 200 ms) on resume, only if it doesn't fight vivo's own animation.

### 3.13 Native and engine side (already done, plus checks)

- **Done:** `RenderMode.surface` (no TextureView copy), and 120 Hz requested on window and surface on every resume (`DisplayRefreshRate.kt`).
- **Check:** that the vivo/iQOO power manager doesn't drop us to 60 Hz while *idle and then a touch starts*. The first swipe frames at 60 Hz feel like a stutter. Measure with `dumpsys SurfaceFlinger` during the first 200 ms of a swipe.
- **Check:** the platform thread is free during swipes. No channel handlers should do disk or PackageManager work on the main thread at that time (`InstalledAppsSource`, icon rendering in `getAppIcons`). Move them to a background executor and post the result back.
- **Check:** icons are already pre-rendered as PNG bytes to the right size natively. Make sure `Image.memory` gets the **same `Uint8List` instance** across rebuilds. `MemoryImage` keys by identity, so new bytes mean a re-decode.

---

## 4. Rules for a snappy feel (apply in every section)

1. **Follow the finger, then settle with velocity.** Anything the user drags (drawer, pages, sheets, overview) should track the pointer 1:1. On release, run a spring from the release velocity rather than a fixed-duration curve.
2. **Respond on pointer-down.** Give press feedback (scale 0.96, or highlight) in the first frame, and the haptic at the moment of commit, not after the animation.
3. **Durations.**
   - Small elements: 150–200 ms.
   - Screen-level: 250–300 ms.
   - Exits are about 20–30% faster than entries.
   - Nothing over 350 ms unless it is decorative.
4. **Curves.** `easeOutCubic` or `Curves.fastOutSlowIn` for entries, `easeInCubic` for exits, and springs (damping ratio 0.9–1.0) for anything gesture-driven. Avoid `easeOutBack` overshoot on large surfaces.
5. **Interruptible.** A new gesture must take over a running animation from its current value, with no snapping or restarting.
6. **One controller per transition.** Drive everything that moves together from the same `Animation` with `Interval`s, not separate implicit animations with their own timers.
7. **Animate transform and opacity only.** Never animate layout (size, padding) per frame on big subtrees. Use `Transform`, `FadeTransition` and `SlideTransition` with a static `child`.
8. **No new blur, saveLayer or shadow during an animation.** Pre-render it, or swap it for a flat colour while moving.
9. **Nothing heavy in the first frame of a transition.** Pre-build, pre-decode and pre-warm before starting it, or defer the work until it has ended.
10. **Idle means zero frames** (except a visible clock's tick, kept to its own boundary).

---

## 5. Day-by-day plan

| Day | Section | Deliverable |
|-----|---------|-------------|
| 1 | Measurement | In-app frame meter in release; baseline numbers for the test script; check Vulkan and Android version |
| 1 | Glass (3.1) + boundaries (3.7) | Pre-blurred wallpaper; `RepaintBoundary`s; re-measure (expect the largest drop in raster ms) |
| 2 | Resume path (3.12) + app launch animation | Wallpaper "unchanged" check; deferred refreshes; icon-origin `ActivityOptions` |
| 2 | Rebuild scoping (3.2, 3.5, 3.6) | `select` everywhere; memoised `arrange`; `_page` notifier; no controller writes in build |
| 3 | Drawer (3.3) | Finger-following drawer with spring settle; pre-built drawer; synchronised home fade |
| 3 | Overview (3.4) + page physics (3.5) | Transition widgets instead of Opacity; stiffer page spring |
| 4 | App widgets (3.11) | Snapshot during resize and drag; `setLook` out of build; HCPP experiment (keep or revert) |
| 4 | Widget internals (3.7–3.10) | Cached painters, quantised `cacheWidth`, paused timers, memoised schemes |
| 5 | Polish + regression | Full test script; idle-frame check; battery sanity check; commit per section |

Each section is its own commit, so any change that doesn't feel better can be reverted on its own (memory: build new effects as removable add-ons).

---

## 6. Per-section review checklist

Use this when reviewing each screen or widget together:

- [ ] What rebuilds per frame during its animation? (DevTools "Track widget builds")
- [ ] Any `saveLayer`, `BackdropFilter`, `ShaderMask`, `Opacity` or blur shadow on screen while it moves? (checkerboard offscreen layers)
- [ ] Does anything that repaints often have its own `RepaintBoundary`?
- [ ] Are `watch`/`Consumer` calls scoped with `select`?
- [ ] Any work in `build()` that isn't building (channel calls, controller writes, `addPostFrameCallback`, sorting, `fromSeed`)?
- [ ] Do timers and tickers stop when it is hidden, covered or backgrounded?
- [ ] Is the gesture finger-driven and interruptible, with a velocity-aware settle?
- [ ] Are images decoded at a stable, bucketed size, from stable bytes?
- [ ] Do the release-build frame meter's numbers for its scenario come in under 8.3 ms?

---

## 7. Sources

- Flutter docs: platform views on Android (TLHC vs Hybrid Composition vs HCPP, `EnableHcpp` meta-data, requirements): https://docs.flutter.dev/platform-integration/android/platform-views
- Flutter docs: performance best practices (saveLayer, Opacity, clipping, build cost, 120 Hz budget): https://docs.flutter.dev/perf/best-practices
- Flutter docs: Impeller (default on Android API 29+, Vulkan with OpenGLES fallback): https://docs.flutter.dev/perf/impeller
- Impeller Android engine notes: https://flutter.googlesource.com/mirrors/engine/+show/refs/heads/main/impeller/docs/android.md
