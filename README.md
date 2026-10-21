# Minimal Launcher

A minimal Android home-screen launcher written in Flutter: clock, pinned apps,
a searchable app drawer, and hiding apps. It's meant to be sideloaded for
personal use.

## Build & install

```bash
flutter pub get
flutter build apk --release        # signed with debug keys, fine for sideloading
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Or open the folder in Android Studio and press Run.

Next, press the Home button. Android asks which launcher to use. Pick
**Minimal Launcher** and choose **Always**. You can switch back later in
*Launcher settings → Default home app* or in Android's Settings → Apps →
Default apps → Home app.

## Using it

| Action | How |
|---|---|
| Open the app drawer | Swipe up on home, or tap **Search apps** |
| Search | Type in the drawer. **Enter** launches the top result |
| Close the drawer | Back, Home, or pull down at the top of the list |
| Pin an app to home / hide it / open App info | Long-press an app |
| Settings | Gear icon on home |
| Unhide apps | Settings → Hidden apps |

> **Hiding is cosmetic.** A hidden app is removed from this launcher's home
> screen, drawer and search. The app stays installed, can still run in the
> background, and still shows in Android Settings.

## Code layout

```
lib/
  main.dart                    bootstrap: prefs, platform bridge, app list
  app.dart                     providers + launcher behaviour (Home press, resume)
  core/                        shared code, no feature logic
    platform/launcher_platform.dart   the only Dart code that touches the channels
    apps/apps_controller.dart         installed apps (unfiltered), refresh, launch
    apps/app_cache.dart               on-disk cache of the list and icons
    apps/app_search.dart              label search and ranking
    models/app_info.dart
    routing/app_routes.dart           named routes
    theme/app_theme.dart
    widgets/app_icon.dart             AppIcon / AppTile
  features/
    home/          home screen, clock, pinned apps (HomeAppsController)
    app_drawer/    drawer grid and search
    app_actions/   long-press sheet and openApp() (shared by home and drawer)
    hidden_apps/   HiddenAppsController, VisibleApps filter, hidden and manage screens
    settings/      settings hub, with "Coming soon" placeholders

android/app/src/main/kotlin/com/arun/minimal_launcher/
  MainActivity.kt                       thin: wires channels, Home press, never exits
  platform/LauncherChannel.kt           method channel; the full API is documented at the top
  platform/InstalledAppsSource.kt       PackageManager queries and icon rendering
  platform/PackageEventsStreamHandler.kt install/uninstall events → Dart
```

### Key design points

- **One filter for hidden apps.** `AppsController.apps` holds every app.
  `VisibleApps` is built from the controller and the hidden set in
  `app.dart`. Home, drawer and search read **only** `VisibleApps`. A new
  feature that lists apps should read it too, so hidden apps can't leak.
- **App identity** is `"<package>/<activity>"`. Hidden ids, pinned ids and
  icon-cache keys all use it.
- **Cold start.** The cached list and icons render first. A live
  PackageManager query then reconciles them. Icons are fetched only for apps
  that are new or have been updated (compared by `lastUpdateTime`). The list
  also refreshes on package events and when the app resumes.
- **State** uses `provider` with `ChangeNotifier`. Prefs load before the first
  frame, so hidden apps never flash on screen.

### Adding a feature

1. Create `lib/features/<name>/` with its controller and screens.
2. Register the controller in `_providers` in `app.dart`.
3. Add a route to `core/routing/app_routes.dart` and a tile to
   `features/settings/settings_screen.dart`. You can replace a "Coming soon"
   placeholder.
4. If the feature needs native code, add a new Kotlin class with **its own
   channel** under `platform/` and register it in
   `MainActivity.configureFlutterEngine`. Add a matching Dart wrapper in
   `lib/core/platform/`. Don't grow `LauncherChannel`.

## Tests

```bash
flutter test
```

The tests cover the hidden-app filter, search ranking and hidden-list
persistence.
