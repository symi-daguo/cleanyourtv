# Hisense VIDAA laser TV: Android 6, no TV Input Framework, needs a low-SDK build

Tested on a China-market Hisense VIDAA set (`VIDAA_TV`, board `MSD6A838`, MStar), Android 6.0 /
API 23, build `MRA58K` / `01.02.41.04`, 1920x1080 at 320dpi, system locale `zh-CN`. VIDAA is
Hisense's own framework on top of Android, not Android TV: it has no `tv_input` service, no package
declares `TV_INPUT_HARDWARE`, and `cmd` does not exist (it arrives in Android 7).

Stock Home is Juguang (`com.jhk.tv.jutv`); the resolved `mHomeProcess` is `com.jamdeo.tv.vod`, so
that package must stay enabled. The live TV app is `com.jamdeo.tv.livetv`.

This is a launcher-only record; no debloat list was applied.

## Three things block the stock build

### 1. minSdk 26 is above the set's API 23

```text
$ adb install -r app-release.apk
Failure [INSTALL_FAILED_OLDER_SDK]
```

Build it for the set instead of lowering `minSdk` for everyone:

```bash
cd launcher && ./gradlew assembleRelease -PlauncherMinSdk=23
```

`minSdk` stays 26 by default, so the upstream build and the CI size gate are untouched. The override
also switches on `coreLibraryDesugaring` with `desugar_jdk_libs`, because `java.time` (`LocalDate`,
`Instant`, `Duration`, `DateTimeFormatter`, `ZoneId`) is used in eight classes and is API 26. The
low-SDK APK is 698 KB against 479 KB; the extra comes from the desugared library.

### 2. Twenty-three API calls are newer than 23

`lintRelease -PlauncherMinSdk=23` listed them; the first one took Home down at `onCreate`:

```text
java.lang.NoSuchMethodError: No virtual method forceHasOverlappingRendering(Z)V in class Landroid/view/View;
```

`Compat.java` carries each one, with the older path it stands in for. Nothing changes on API 26 and
up, where every branch is the call the launcher already made:

| API | Call | Below it |
|---|---|---|
| 24 | `View#forceHasOverlappingRendering` (3 sites) | skipped; the view renders through an offscreen buffer |
| 24 | `UserManager#isUserUnlocked` (2) | true: no direct-boot storage before 7.0 |
| 24 | `ConnectivityManager#registerDefaultNetworkCallback` | an unconstrained `registerNetworkCallback` |
| 24 | `Configuration#getLocales` (2) | the deprecated `configuration.locale` |
| 24 | `TvInputInfo#isHidden` (3) | false |
| 24 | `TvInputInfo#loadCustomLabel` (2) | null |
| 26 | `PackageManager#getChangedPackages` (2) | false: `packageReceiver` already marks the tiles stale |
| 26 | `Resources#getFont` | `Typeface.create("sans-serif")`: the bundled Outfit family is a `res/font` XML |
| 26 | `Bitmap.Config#HARDWARE` | `ARGB_8888` |
| 26 | `Files#readAllLines` + `File#toPath` | `BufferedReader`, still no Android types so the JVM tests hold |

### 3. VIDAA has no TV Input Framework

`getSystemService(TV_INPUT_SERVICE)` answers a `TvInputManager` whose binder is null, so the
`tim != null` check the launcher already does passes and the first call throws:

```text
java.lang.NullPointerException: Attempt to invoke interface method
'java.util.List android.media.tv.ITvInputManager.getTvInputList(int)' on a null object reference
```

`Compat.tvInputs()` probes once and answers null, so the Inputs menu is simply empty here instead of
taking Home down. HDMI switching is not available through this app on this set.

## What works

- The launcher installs, starts and stays up; no crash in `logcat`.
- Chinese UI from the set's own `zh-CN` locale, including the dock, the tiles and the settings panel.
- VIDAA **does** accept a third-party HOME: pressing Home opens the system's `选择主屏幕应用`
  chooser with `聚好看` and this launcher, which is the opposite of the Fengmi `FMProjA2` record.
  Choosing `主屏幕` starts CleanYourTV; `始终` has to be picked to make it stick.
- The stock Home is left enabled throughout.

## Measured

| | |
|---|---|
| Cold start (`am start -W`, after `force-stop`) | 4260 ms |
| PSS, just after start | 20,052 KB |
| PSS, 35 s idle | 19,256 KB |
| Breakdown at idle | Java 2,436 / Native 7,996 / Code 8,032 KB |

Compare with the ZTE record: 1077 ms cold start on Android 9. The gap is the board, not the build —
MSD6A838 is a 2016 MStar part, and the same APK on RK3566 starts four times sooner. Memory goes the
other way, 19 MB against 27 MB, because the older ART maps less of the app into native memory.

`Code` at 8 MB is the desugared library plus the two dex files being mapped in; on this set `dumpsys`
counts them there rather than under Native.

### 960x540dp: the fourth row scrolls

1920x1080 at 320dpi is **960x540dp**, the normal figure for a 1080p TV. The app row is a scrollable
list, so the fourth row sits half off-screen and the scrollbar on the left is the way to it. A
1280x800dp box (the ZTE record) shows the same row in full. This is the layout behaving as designed,
not a clipped screen — compare dp, not pixels, before calling it a bug.

## The Home button reports F12

`input keyevent 3` logs:

```text
map KEYCODE_HOME to KEYCODE_F12 for hisense internal usage.
```

So the remote's Home button is remapped inside VIDAA. `HomeKeyService` only acts on
`KEYCODE_HOME` (with `stock_home_redirect`) and `KEYCODE_ALL_APPS`, so the physical button has not
been confirmed to reach it — that needs a real press on the remote, not an injected key.

## Restore

The stock Home was never disabled, so only the install has to go:

```bash
adb uninstall com.gathin.tvhome
```

If this launcher was made the default Home with `始终`, clear that choice first: Settings > Apps >
Default apps, or pick `聚好看` in the same chooser after uninstalling.
