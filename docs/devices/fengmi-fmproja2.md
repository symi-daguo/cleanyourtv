# Fengmi FMProjA2: third-party Home refused, accessibility redirect

Tested on a China-market Fengmi (光峰/峰米) laser projector `FMProjA2` (`jerry`), FengOS,
Android 9 / API 28, firmware `2.1.5.2987` (`PQ3B.190705.003`), 1920x1080, system locale `zh-CN`.
Stock Home is `com.tvfengmi.launcher/com.gala.video.app.epg.HomeActivity` (installed from
`/system/priv-app/GitvVideo/GitvVideo.apk`).

This is a launcher-only record; no debloat list was applied.

## What failed and why

The launcher installs and runs, but FengOS does not expose third-party packages as HOME
candidates:

```text
$ cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME
1 activities found:
  com.android.tv.settings/.system/FallbackHome          # with the stock launcher disabled
  com.tvfengmi.launcher/com.gala.video.app.epg.HomeActivity  # with it enabled

$ cmd package set-home-activity --user 0 com.gathin.tvhome/com.gathin.tvhome.MainActivity
java.lang.IllegalArgumentException: ... cannot be home on user 0
```

The same refusal was reproduced with a test build using another package name and with the
installed Dangbei launcher, so this is not a package-name allowlist. Disabling
`com.tvfengmi.launcher` only moves Home to `FallbackHome`; it does not make the launcher Home.
The stock launcher is therefore kept **enabled**.

## Working setup

Use the upstream `stock_home_redirect` path plus `HomeKeyService`:

- `config.xml`: `stock_home_redirect = com.tvfengmi.launcher`
- `HomeKeyService` receives `TYPE_WINDOW_STATE_CHANGED` and starts this launcher when the stock
  home appears, and `ProbeActivity` covers the boot case where the stock home is already on
  screen before the service binds.
- `HomeKeyService.openHome()` starts `MainActivity` directly. An implicit
  `CATEGORY_HOME` intent with this package throws `ActivityNotFoundException` on this firmware.

```bash
adb install -r app-release.apk
adb shell settings put secure enabled_accessibility_services com.gathin.tvhome/.HomeKeyService
adb shell settings put secure accessibility_enabled 1
adb shell am start -n com.gathin.tvhome/.MainActivity
```

## Validation

- APK `com.gathin.tvhome` 2.7 (versionCode 8), debug-signed, installed over ADB.
- Chinese UI shown with the TV's `zh-CN` locale, no per-app locale command needed.
- Reboot: the projector comes up directly in CleanYourTV; the service setting survives reboot.
- Home from a third-party app (Douyu) returns to CleanYourTV.
- Stock launcher remains enabled and is reachable after disabling the accessibility service.
- TV Input Framework reports HDMI 1/2/3, AV and ADTV; per-port signal switching was not checked.

## Restore

```bash
adb shell settings put secure accessibility_enabled 0
adb shell settings put secure enabled_accessibility_services ''
adb shell am start -n com.tvfengmi.launcher/com.gala.video.app.epg.HomeActivity
adb uninstall com.gathin.tvhome
```

The stock launcher was never disabled, so no `pm enable` is required.
