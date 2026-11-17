#!/usr/bin/env bash
# Push the wallpaper clips onto a TV and turn the video wallpaper on.
#
# Usage: push-videos.sh <电视IP> [片源目录]
#
# The clips go into the app's own private folder, because a Hisense VIDAA has its external storage cut away
# and nothing can be pushed to /sdcard there. On a set with working external storage the same files can go
# into the theme folder instead, next to config.json.
#
# Needs adb. On the sets this was made for the adb shell runs as root, so the copy is a plain cp.
set -euo pipefail

TV="${1:?用法: push-videos.sh <电视IP> [片源目录]}"
SRC="${2:-$(cd "$(dirname "$0")" && pwd)/../videos}"
PKG=com.gathin.tvhome

command -v adb >/dev/null || { echo "需要 adb"; exit 1; }
[ -d "$SRC" ] || { echo "片源目录不存在：$SRC"; exit 1; }

adb connect "$TV:5555" >/dev/null 2>&1 || true
sleep 2
state=$(adb devices | grep "^$TV:5555" | awk '{print $2}')
if [ "$state" != "device" ]; then
    echo "连不上 $TV（状态 ${state:-无}）。这台电视待机时 adbd 会停止握手，遥控器按一下就恢复。"
    exit 1
fi

echo "推送到 $TV 的私有目录 ..."
count=0
for f in "$SRC"/*.mp4; do
    [ -s "$f" ] || continue
    name=$(basename "$f")
    adb -s "$TV:5555" push "$f" "/data/local/tmp/$name" >/dev/null
    adb -s "$TV:5555" shell "mkdir -p /data/$PKG/files/videos && cp /data/local/tmp/$name /data/$PKG/files/videos/$name" >/dev/null
    adb -s "$TV:5555" shell rm -f "/data/local/tmp/$name"
    echo "  $name"
    count=$((count + 1))
done
echo "推了 $count 支"

echo
echo "重启桌面，让它重新读片源 ..."
adb -s "$TV:5555" shell am force-stop $PKG
sleep 1
adb -s "$TV:5555" shell am start -n "$PKG/.MainActivity" >/dev/null 2>&1
sleep 6
adb -s "$TV:5555" shell dumpsys meminfo $PKG | grep TOTAL | head -1
adb -s "$TV:5555" logcat -d | grep -c "FATAL EXCEPTION" | sed 's/^/崩溃数: /'
