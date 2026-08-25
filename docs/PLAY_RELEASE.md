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

- **Target SDK.** Play enforces a recent `targetSdkVersion`. The build verifies
  this itself and prints what Gradle actually compiled — the last dry-run
  reported `minSdkVersion="24"`, `targetSdkVersion="35"` from the merged release
  manifest, which meets the current requirement. If a future Play deadline
  raises it, set `gradle_build/target_sdk` in the workflow's export preset.
  (The export log's "Could not find version of build tools that matches Target
  SDK, using 33.0.2" is unrelated — build-tools version is not targetSdk, and
  the compiled manifest is what counts.)
- **64-bit.** Required. `arm64-v8a` is on.
- **Debuggable.** Checked by the build; the job fails rather than shipping one.
- **Package name.** `com.horizon.idle`, set once as `PACKAGE_ID` in
  `play-release.yml` and asserted twice: against the preset Godot actually
  parses, and against the bundle itself. It is permanent once published — a
  different package name is a different app, and there is no migration path for
  anyone who installed the old one. See *Two app ids* below.
- **Data safety / content rating / privacy policy.** Console forms, not build
  output. Internal testing still requires them before the track goes live.

## Two app ids, on purpose

| Build | App id | Signed with |
| --- | --- | --- |
| Play bundle (`play-release.yml`) | `com.horizon.idle` | your private upload key |
| Dev APK (`release.yml`) | `com.stellarforge.game` | the committed debug key |

They must not be the same. Android refuses to install an app over one with the
same id but a different signature, so if the sideloaded dev APK claimed
`com.horizon.idle`, installing the store version later would fail outright and
the only fix would be uninstalling — which deletes the save with it. Different
ids let a dev build and the store build sit on one phone at once.

`com.stellarforge.game` is also the id every dev APK has carried so far, so it
stays as it is: changing it would strand the save on your phone.

### The `#` trap

Both workflows generate `export_presets.cfg` from a heredoc. **No line inside
those heredocs may start with `#`.** Godot's `ConfigFile` uses `;` as its comment
character, so a `#` line ends the parse: every key after it is dropped and the
export silently falls back to defaults — `com.example.$genname` for the package,
nothing for the keystores.

That is not theoretical. A comment added above `package/unique_name` produced a
perfectly valid, correctly-sized, non-debuggable 52 MB bundle whose applicationId
was `com.example.stellarforge`. Every check downstream of the export passed. Had
it been uploaded, the store listing would have been bound to that id forever.

`tools/check_export_preset.gd` now runs between writing the preset and building:
it loads the file with the same parser the exporter uses, prints every key that
survived, and fails if the package name or the required keystore keys are not
what the workflow intended. A parse that stops early shows up as a key list that
simply ends at the offending line.

## If a build fails

The workflow fails loudly at the first thing that is wrong:

- missing secrets → names exactly which ones
- wrong keystore password or alias → `keytool -list` fails before Gradle starts
- GDScript that will not compile → the "Verify scripts compile" step stops the
  build rather than shipping a bundle that cannot boot

The Gradle step is the one that needs network access for its dependencies; a
transient failure there is worth simply re-running.
