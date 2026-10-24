#!/usr/bin/env bash
# 逐项核对 CleanYourTV 桌面在这台电视上的状态，输出「通过 / 警告 / 失败」，最后给一行结论。
#
# 用法:
#   skills/cleanyourtv-cn/scripts/verify.sh 192.168.1.50
#   TV_HOST=192.168.1.50 skills/cleanyourtv-cn/scripts/verify.sh
#
# 退出码：0 = 没有失败项（警告不算失败），1 = 有失败项。
# 只读：不改电视上的任何设置。
set -uo pipefail

cd "$(dirname "$0")/../../.."
PKG=com.gathin.tvhome
TV_HOST="${TV_HOST:-${1:-}}"

PASS=0; WARN=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '[通过] %s\n' "$*"; }
warn() { WARN=$((WARN+1)); printf '[警告] %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '[失败] %s\n' "$*"; }

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

sh_() { "$ADB" -s "$TARGET" shell "$@" 2>/dev/null | tr -d '\r'; }

# --- 1. 连接 ---
"$ADB" connect "$TARGET" >/dev/null 2>&1 || true
if [ "$("$ADB" -s "$TARGET" get-state 2>/dev/null)" = "device" ]; then
  ok "adb 已连接 $TARGET"
else
  bad "adb 连不上 ${TARGET}（先在电视上打开网络调试，并允许这台电脑）"
  printf '\n1 项检查：0 通过，0 警告，1 失败\n'
  exit 1
fi

SDK=$(sh_ getprop ro.build.version.sdk)
MODEL=$(sh_ getprop ro.product.model)
REL=$(sh_ getprop ro.build.version.release)
LOCALE=$(sh_ getprop persist.sys.locale)
printf '电视：%s / Android %s (SDK %s) / 系统语言 %s\n\n' "$MODEL" "$REL" "$SDK" "${LOCALE:-未知}"

# --- 2. 已安装 ---
if sh_ pm list packages | grep -qx "package:$PKG"; then
  VERSION=$(sh_ dumpsys package "$PKG" | grep -m1 versionName | sed 's/.*versionName=//')
  CODE=$(sh_ dumpsys package "$PKG" | grep -m1 versionCode | sed 's/.*versionCode=//')
  ok "已安装 $PKG $VERSION (versionCode $CODE)"
else
  bad "没有安装 ${PKG}，先跑 scripts/install.sh"
  printf '\n1 项检查：0 通过，0 警告，1 失败\n'
  exit 1
fi

# --- 3. 能启动并留在前台 ---
sh_ am start -n "$PKG/.MainActivity" >/dev/null 2>&1
sleep 3
FRONT=$(sh_ 'dumpsys activity activities | grep mResumedActivity')
case "$FRONT" in
  *"$PKG"*) ok "启动后停在前台" ;;
  *) bad "启动后没有留在前台（前台是：${FRONT#*u0 }）" ;;
esac

# --- 4. 没崩 ---
CRASH=$(sh_ 'logcat -d -b crash' | grep -c "$PKG" 2>/dev/null || true)
[ -z "$CRASH" ] && CRASH=0
if [ "$CRASH" -eq 0 ]; then
  ok "崩溃日志里没有本应用"
else
  warn "崩溃缓冲区里有 $CRASH 条本应用记录，机器人可查：adb logcat -d -b crash"
fi

# --- 5. 界面语言 ---
# 桌面没有应用内开关：SDK 33+ 看 per-app 语言，以下看系统语言。
if [ -n "$SDK" ] && [ "$SDK" -ge 33 ] 2>/dev/null; then
  APPLOC=$(sh_ cmd locale get-app-locales "$PKG" 2>/dev/null | head -1)
  case "$APPLOC" in
    *zh*) ok "应用语言：$APPLOC" ;;
    "")   warn "读不到 per-app 语言，界面跟随系统（${LOCALE:-未知}）" ;;
    *)    warn "应用语言是 ${APPLOC}，不是中文；改：cmd locale set-app-locales $PKG --locales zh-CN" ;;
  esac
else
  case "$LOCALE" in
    zh*) ok "系统语言 ${LOCALE}，界面为中文" ;;
    "")  warn "读不到系统语言" ;;
    *)   warn "系统语言是 ${LOCALE}，界面不会是中文；这台 Android $REL 只能改系统语言来切" ;;
  esac
fi

# --- 6. 是否已被设为默认桌面 ---
# Android 7+ 有 cmd package；更老的只能看 dumpsys 的 mHomeProcess。
if [ -n "$SDK" ] && [ "$SDK" -ge 24 ] 2>/dev/null; then
  HOME_ACT=$(sh_ cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -1)
  case "$HOME_ACT" in
    *"$PKG"*) ok "默认桌面已是本应用" ;;
    "")       warn "读不到当前默认桌面" ;;
    *)        warn "默认桌面还是 ${HOME_ACT}；按 Home 在系统选择器里选「始终」即可" ;;
  esac
else
  HOME_PROC=$(sh_ 'dumpsys activity | grep mHomeProcess' | sed -nE 's/.*[: ]([A-Za-z0-9_.]+)\/[A-Za-z0-9_.]+.*/\1/p' | head -1)
  if [ -n "$HOME_PROC" ]; then
    ok "Home 归属进程：${HOME_PROC}（原桌面仍在，可随时回去）"
  else
    warn "这台系统答不出 Home 归属，用遥控器按 Home 眼见为实"
  fi
fi

# --- 7. 恢复入口还在 ---
# 原桌面没被停用，才算有回头路；这是仓库的硬规则。
DISABLED_HOME=$(sh_ pm list packages -d | grep -icE 'launcher|home|jutv|jamdeo' || true)
[ -z "$DISABLED_HOME" ] && DISABLED_HOME=0
if [ "$DISABLED_HOME" -eq 0 ]; then
  ok "没有停用任何桌面类应用，随时能回原桌面"
else
  warn "有 $DISABLED_HOME 个桌面类应用处于停用状态，确认一下是不是你干的"
fi

printf '\n%d 项检查：%d 通过，%d 警告，%d 失败\n' \
  $((PASS+WARN+FAIL)) "$PASS" "$WARN" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
