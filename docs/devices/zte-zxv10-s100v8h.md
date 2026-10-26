# ZTE ZXV10 S100V8H: Android 9 at 1280x800dp, the launcher fits without touching anything

Tested on a China Telecom "小翼管家" set-top box (`ZXV10 S100V8H`, ZTE, Rockchip `rk356x_box_32`),
Android 9 / API 28, build `PI eng.sunhai.20260817.163048`, 1280x800 at 160dpi, system locale `zh-CN`.
It answers HOME through the system chooser and needs no workaround.

This is a launcher-only record; no debloat list was applied and nothing was disabled.

## What works

- The `min26` APK installs as-is (`Success`) — no `-PlauncherMinSdk`, no desugared library.
- Starts and stays in front; `logcat -b crash` holds nothing for the package.
- Chinese UI from the set's own `zh-CN`, all seven `verify.sh` checks pass except the Home one.
- Pressing Home offers the system's chooser; `始终` makes it stick. Until then `verify.sh` reports a
  warning, which is the expected state straight after a first install.

## Measured

| | |
|---|---|
| Cold start (`am start -W`, after `force-stop`) | 1077 ms |
| PSS, just after start | 35,245 KB |
| PSS, 35 s idle | 26,827 KB |
| Breakdown at idle | Java 2,116 / Native 17,504 / Code 1,432 KB |

Memory drops once the first frames are drawn, so nothing is leaking. Native heap is the largest part,
which is what an Android 9 box with hardware-composited wallpaper does — the bundled Outfit font and
the app-icon bitmaps live there.

## The one thing that looks wrong and is not

At 1280x800dp the grid shows four rows with room to spare, and the left edge carries a scrollbar. That
scrollbar is not decoration: the app row is a list, and a set with less vertical room scrolls it. On a
960x540dp 1080p panel (see the `hisense-vidaa-laser.md` record) the fourth row sits half off-screen and
is reached by scrolling. Both are the same layout; only the dp height differs.

If you are judging a screenshot, compare dp, not pixels: 1920x1080 at 320dpi is 960x540dp, while
1280x800 at 160dpi is 1280x800dp — more than twice the vertical room.

## Restore

```bash
adb uninstall com.gathin.tvhome
```
