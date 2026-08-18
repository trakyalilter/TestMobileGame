# Shipping Stellar Forge to Google Play

Play rejected `StellarForge.apk` ("Geçerli bir uygulama paketi yükleyin") for
three separate reasons, any one of which is fatal:

1. **It is an APK.** Every app created after August 2021 must publish an Android
   App Bundle. The upload box on that page takes `.aab` only.
2. **It is debug-signed.** `release.yml` signs with `ci-debug.keystore`, which is
   committed to this repo — a key everyone can read is not a signing identity.
3. **It is a debug build.** `--export-debug` marks the package `debuggable`, and
   Play refuses debuggable uploads.

`release.yml` is doing its job — it produces sideloadable dev builds. The Play
artifact comes from **`play-release.yml`** instead.

---

## One-time setup

### 1. Create an upload keystore

Run this on your own machine, not in CI. Keep the file and the passwords: with
Play App Signing you can ask Google to reset a lost upload key, but without it
you would lose the ability to update the app at all.

```bash
keytool -genkeypair -v \
  -keystore stellarforge-upload.keystore \
  -alias stellarforge \
  -keyalg RSA -keysize 2048 -validity 10000
```

It asks for a keystore password, then your name/organisation (any answer is
fine — it is not shown to players), then a key password. Answering "same as
keystore password" for the key password is normal and keeps the secrets simple.

`-validity 10000` (about 27 years) is what Play expects; a key that expires
before your last update is a dead end.

### 2. Put it in repo secrets

```bash
base64 -w0 stellarforge-upload.keystore > keystore.b64   # macOS: base64 -i ... -o ...
```

Then in GitHub → Settings → Secrets and variables → Actions → New repository
secret, add four:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | the whole contents of `keystore.b64` |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
| `ANDROID_KEY_ALIAS` | `stellarforge` (the `-alias` above) |
| `ANDROID_KEY_PASSWORD` | the key password |

Delete `keystore.b64` afterwards. Never commit the keystore itself.

### 3. Enrol in Play App Signing

When you create the app in Play Console, accept Play App Signing (it is the
default). Google then holds the *app signing key* and your keystore is only the
*upload key* — if you ever lose it, support can issue a new one. Managing the
signing key yourself means losing it ends the app.

---

## Building a bundle

Actions → **Build Play bundle (AAB)** → Run workflow:

- **mode** — `release` signs with the secrets above; `dry-run` signs with the
  committed debug key so you can prove the pipeline works before the secrets
  exist. A dry-run bundle is *not* uploadable to Play.
- **version_name** — what players see, e.g. `0.2.0`. Free-form.
- **version_code** — the integer Play orders uploads by. **It must be higher
  than every code you have ever uploaded**, forever. Play never lets you reuse
  or lower one, so start at `1` and increment; if you fat-finger `9999` you have
  burned every number below it.

The bundle lands as a workflow artifact named `StellarForge-<version>-aab`.
Download it, and upload the `.aab` to the internal testing track.

---

## What Play checks after upload

- **Target SDK.** Play enforces a recent `targetSdkVersion`. Godot 4.5's default
  is current as of writing; if Play complains, set `gradle_build/target_sdk` in
  the workflow's export preset.
- **64-bit.** Required. `arm64-v8a` is on.
- **Package name.** `com.stellarforge.game`, set in the preset. It is permanent
  once published — a different package name is a different app.
- **Data safety / content rating / privacy policy.** Console forms, not build
  output. Internal testing still requires them before the track goes live.

## If a build fails

The workflow fails loudly at the first thing that is wrong:

- missing secrets → names exactly which ones
- wrong keystore password or alias → `keytool -list` fails before Gradle starts
- GDScript that will not compile → the "Verify scripts compile" step stops the
  build rather than shipping a bundle that cannot boot

The Gradle step is the one that needs network access for its dependencies; a
transient failure there is worth simply re-running.
