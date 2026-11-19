# Nali

Nali combines the Moshi Flutter application shell (Home, navigation, library, profile, settings and Liquid Glass UI) with the Android/Kotlin feature implementation and original BitChord modules supplied in Tori.

## Project structure
- `lib/`: Flutter UI and app-level screens/services retained from Moshi.
- `android/app/src/main/kotlin/com/pokke/music/`: Tori's Android/Kotlin feature runtime and repositories. The shared feature sources match Tori's supplied sources; the Flutter launcher remains the app entry point.
- `integration/bitchord/`: original BitChord shared and shared-UI modules. These files are kept unchanged.
- `android/app/src/main/assets/canvas/`: Tori Canvas media assets.
- `database/`, `docs/`, `samples/`: supporting Tori database migration, plugin documentation and community plugin template.
- `.github/workflows/build-apk.yml` and `deploy-web.yml`: Moshi's APK and web workflows retained. Tori's separate TV/cancel workflows are not copied.
- `assets/fonts/`: add the four requested font files here manually. The default selection is `nothing-font-5x7.otf`.

## Fonts
Add `nothing-font-5x7.otf`, `Clamofte-4nB54.otf`, `Rogbold-3llGM.otf`, and `Alkia.ttf` to `assets/fonts/`. The directory is already declared as a Flutter asset directory. Users can also import additional TTF/OTF fonts from Settings → Fonts.

## Important integration note
The Kotlin/BitChord runtime is retained as supplied; this package is an integration baseline, not a claim that every Flutter playback action has already been migrated from the legacy Dart audio controller to the Kotlin PlayerController. Validate the playback bridge and provider credentials before publishing a release APK. Existing `pokke://` callback URIs are retained for backwards compatibility; a `nali://spotify-callback` intent filter is also registered.

## Android player architecture (Nali)

On Android, Flutter is the application shell and UI for Home, navigation, library, profile and settings. Playback is owned by the native Kotlin `PlayerController` / Media3 `PlaybackService`; Flutter sends commands through `nali/player` and receives the native queue and playback state through `nali/player/events`. This avoids running the old Flutter `audioplayers` engine alongside Media3.

Opening the mini-player on Android launches `BitChordPlayerActivity`, which hosts Tori's original BitChord Compose `NowPlayingScreen` through `BitChordNowPlayingHost`. The original BitChord sources under `integration/bitchord` are kept as-is; app-specific Android adapters and the Flutter bridge live outside that directory. Web and iOS continue using the Flutter audio implementation.

The Android Gradle wrapper is included under `android/gradlew` and `android/gradle/wrapper/`.
