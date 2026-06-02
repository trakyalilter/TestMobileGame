# Catch Game (TestMobileGame)

A tiny, dependency-light Android game written in Kotlin. Drag the basket to
catch falling fruit — each catch scores a point and speeds things up. Miss
three and it's game over. Tap to play again.

The game is rendered with a plain `SurfaceView` + render thread (no game
engine), so the project builds with just the Android Gradle Plugin and AndroidX.

## How to get the APK (download)

The APK is built automatically by GitHub Actions, because the Android SDK is
not available in every local environment.

### Option A — download from a workflow run (any push)
1. Go to the repo's **Actions** tab.
2. Open the latest **Build APK** run.
3. Download the **`TestMobileGame-release-apk`** artifact (a zip containing
   `app-release.apk`).

### Option B — publish a versioned Release
Push a tag starting with `v` and the workflow attaches the APK to a GitHub
Release:

```bash
git tag v1.0
git push origin v1.0
```

The APK then appears under the repo's **Releases** page as a direct download.

## Install on a device
1. Copy the `.apk` to your Android phone (minSdk 26 / Android 8.0+).
2. Enable "Install unknown apps" for your file manager/browser.
3. Open the APK to install.

The release build is signed with the standard Android **debug** key so it
installs without extra signing setup. For a production/Play Store build,
configure a real `signingConfig` with your own keystore.

## Build locally (requires the Android SDK)
```bash
./gradlew assembleRelease
# output: app/build/outputs/apk/release/app-release.apk
```

## Tech
- Kotlin, AndroidX (`core-ktx`, `appcompat`)
- Android Gradle Plugin 8.5.2, Gradle 8.9, Kotlin 1.9.24
- compileSdk 34, minSdk 26, targetSdk 34
