#!/usr/bin/env bash
# 卸载 CleanYourTV 桌面，回到原厂桌面。不动任何系统包（本 skill 从没停用过包）。
#
# 用法:
#   skills/cleanyourtv-cn/scripts/uninstall.sh 192.168.1.50
#   TV_HOST=192.168.1.50 skills/cleanyourtv-cn/scripts/uninstall.sh
set -euo pipefail

PKG=com.gathin.tvhome
TV_HOST="${TV_HOST:-${1:-}}"

[ -n "$TV_HOST" ] || { printf '用法：%s <电视地址>\n' "$0" >&2; exit 1; }

if command -v adb >/dev/null 2>&1; then
  ADB=adb
elif [ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]; then
  ADB="$HOME/Library/Android/sdk/platform-tools/adb"
else
  printf '错误：找不到 adb\n' >&2; exit 1
fi

TARGET="$TV_HOST"
case "$TARGET" in *:*) ;; *) TARGET="$TV_HOST:5555" ;; esac

"$ADB" connect "$TARGET" >/dev/null 2>&1 || true
[ "$("$ADB" -s "$TARGET" get-state 2>/dev/null)" = "device" ] \
  || { printf '错误：连不上 %s\n' "$TARGET" >&2; exit 1; }

SDK=$("$ADB" -s "$TARGET" shell getprop ro.build.version.sdk | tr -d '\r')

# 先把默认桌面让回去：卸载一个正在当 Home 的应用，某些固件会短暂落到 FallbackHome。
if [ -n "$SDK" ] && [ "$SDK" -ge 24 ] 2>/dev/null; then
  CUR=$("$ADB" -s "$TARGET" shell cmd package resolve-activity --brief \
        -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tr -d '\r' | tail -1)
  case "$CUR" in
    *"$PKG"*)
      printf '提示：它当前是默认桌面。卸载后系统会回到原桌面；如果黑屏，按 Home 或重启一次电视。\n' ;;
  esac
fi

printf '== 卸载 %s\n' "$PKG"
OUT=$("$ADB" -s "$TARGET" uninstall "$PKG" 2>&1) || true
printf '%s\n' "$OUT"
case "$OUT" in
  *Success*) ;;
  *"not installed"*|*"Unknown package"*) printf '本来就没装。\n' ;;
  *) printf '错误：卸载失败，上面是原始输出\n' >&2; exit 1 ;;
esac

printf '\n== 如果电视提示没有默认桌面，按一次 Home 选原桌面，或重启电视。\n'
printf '== 本脚本从未停用任何系统包，所以没有 pm enable 要做。\n'
