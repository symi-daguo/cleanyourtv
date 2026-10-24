#!/usr/bin/env bash
# 把 CleanYourTV 桌面装到电视上。自动判断电视的 Android 版本，选对构建参数，装完直接启动。
#
# 用法:
#   TV_HOST=192.168.1.50 skills/cleanyourtv-cn/scripts/install.sh
#   skills/cleanyourtv-cn/scripts/install.sh 192.168.1.50          # 也可以把地址当第一个参数
#   skills/cleanyourtv-cn/scripts/install.sh 192.168.1.50 --build   # 强制重新构建
#   skills/cleanyourtv-cn/scripts/install.sh 192.168.1.50 --apk ~/x.apk  # 用指定的 APK
#
# 只做三件事：构建（需要时）、adb install、启动。不停用任何包，不碰系统设置。
set -euo pipefail

cd "$(dirname "$0")/../../.."
REPO="$(pwd)"
PKG=com.gathin.tvhome
APK=""
FORCE_BUILD=0
TV_HOST="${TV_HOST:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --build) FORCE_BUILD=1; shift ;;
    --apk) APK="${2:?--apk 后面要跟 APK 路径}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) TV_HOST="$1"; shift ;;
  esac
done

say()  { printf '%s\n' "$*"; }
fail() { printf '错误：%s\n' "$*" >&2; exit 1; }

[ -n "$TV_HOST" ] || fail "没有电视地址。用法：TV_HOST=192.168.1.50 $0"

# --- adb ---
if command -v adb >/dev/null 2>&1; then
  ADB=adb
elif [ -n "${ANDROID_HOME:-}" ] && [ -x "$ANDROID_HOME/platform-tools/adb" ]; then
  ADB="$ANDROID_HOME/platform-tools/adb"
elif [ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]; then
  ADB="$HOME/Library/Android/sdk/platform-tools/adb"
else
  fail "找不到 adb。装 Android SDK Platform-Tools，或把 platform-tools 加进 PATH。"
fi

TARGET="$TV_HOST"
case "$TARGET" in *:*) ;; *) TARGET="$TV_HOST:5555" ;; esac

say "== 连接 $TARGET"
"$ADB" connect "$TARGET" >/dev/null 2>&1 || true
STATE=$("$ADB" -s "$TARGET" get-state 2>/dev/null || true)
if [ "$STATE" != "device" ]; then
  if "$ADB" devices | grep -q "^$TARGET[[:space:]]*unauthorized"; then
    fail "电视还没授权这台电脑。电视上会弹一个「允许 USB 调试」的窗口，用遥控器点允许，再跑一次。"
  fi
  fail "连不上 ${TARGET}（状态：${STATE:-无}）。确认电视和电脑在同一网络、电视的「网络调试/ADB 调试」已打开。详见 references/troubleshooting.md。"
fi

SDK=$("$ADB" -s "$TARGET" shell getprop ro.build.version.sdk | tr -d '\r')
MODEL=$("$ADB" -s "$TARGET" shell getprop ro.product.model | tr -d '\r')
REL=$("$ADB" -s "$TARGET" shell getprop ro.build.version.release | tr -d '\r')
LOCALE=$("$ADB" -s "$TARGET" shell getprop persist.sys.locale | tr -d '\r')
say "== 电视：$MODEL / Android $REL (SDK $SDK) / 语言 ${LOCALE:-未知}"

# --- 选构建 ---
# 桌面默认 minSdk 26。低于 26 的机器要带 -PlauncherMinSdk=23，否则 adb install 返回
# INSTALL_FAILED_OLDER_SDK；那个构建会打开 coreLibraryDesugaring（java.time 是 API 26）。
BUILD_ARGS=()
NEED_LOW_SDK=0
if [ -n "$SDK" ] && [ "$SDK" -lt 26 ] 2>/dev/null; then
  NEED_LOW_SDK=1
  BUILD_ARGS+=("-PlauncherMinSdk=$SDK")
  say "== SDK $SDK 低于桌面的 minSdk 26，按 SDK $SDK 构建"
fi

USER_APK=0
[ -n "$APK" ] && USER_APK=1

if [ -z "$APK" ]; then
  APK="$REPO/launcher/app/build/outputs/apk/release/app-release.apk"
fi

# 低版本机器不能复用默认构建的产物：那个 APK 声明 minSdk 26，装上去必然失败。Gradle 是增量的，
# 重编通常十几秒，比让人对着一份旧产物排错划算。
NEED_BUILD=0
if [ "$FORCE_BUILD" = 1 ] || [ ! -f "$APK" ] || { [ "$NEED_LOW_SDK" = 1 ] && [ "$USER_APK" = 0 ]; }; then
  NEED_BUILD=1
fi

if [ "$NEED_BUILD" = 1 ]; then
  say "== 构建 APK（第一次要下载 Gradle 和依赖）"
  ( cd "$REPO/launcher" && ./gradlew assembleRelease "${BUILD_ARGS[@]}" --console=plain ) \
    || fail "构建失败。看 launcher/gradle 的输出；JDK 需要 17 或 21。"
else
  say "== 用已有 APK：${APK}（要重编加 --build）"
fi
[ -f "$APK" ] || fail "APK 不存在：$APK"

say "== APK：$(basename "$APK")（$(( $(wc -c < "$APK") / 1024 )) KB，构建参数：${BUILD_ARGS[*]:-默认 minSdk 26}）"

# --- 安装 ---
say "== 安装"
INSTALL_OUT=$("$ADB" -s "$TARGET" install -r "$APK" 2>&1) || true
printf '%s\n' "$INSTALL_OUT"
case "$INSTALL_OUT" in
  *Success*) ;;
  *INSTALL_FAILED_OLDER_SDK*)
    fail "电视的系统版本低于 APK 的 minSdk。重跑并加 --build，脚本会按这台电视的 SDK 重新构建。" ;;
  *INSTALL_FAILED_VERIFICATION_FAILURE*)
    fail "这台电视拒绝侧载（厂商校验）。桌面这条路走不通，只能做去膨胀，见 references/troubleshooting.md。" ;;
  *INSTALL_FAILED_UPDATE_INCOMPATIBLE*)
    fail "电视上是另一个签名的旧版本。先卸载：$ADB -s $TARGET uninstall $PKG" ;;
  *) fail "安装失败，上面是原始输出。" ;;
esac

# --- 语言 ---
# 桌面没有应用内语言开关：Android 13+ 用 per-app 语言，13 以下跟着系统语言走。
if [ -n "$SDK" ] && [ "$SDK" -ge 33 ] 2>/dev/null; then
  if "$ADB" -s "$TARGET" shell cmd locale set-app-locales "$PKG" --locales zh-CN >/dev/null 2>&1; then
    say "== 已把应用语言设为 zh-CN（Android 13+ 的 per-app 语言）"
  else
    say "== 提示：这台机器没能设置 per-app 语言，界面跟随系统语言"
  fi
else
  say "== 提示：Android $REL 不支持单独设置应用语言，界面跟随系统语言（当前 ${LOCALE:-未知}）"
fi

# --- 启动 ---
say "== 启动"
"$ADB" -s "$TARGET" shell am start -n "$PKG/.MainActivity" >/dev/null || fail "启动失败"
sleep 3
FRONT=$("$ADB" -s "$TARGET" shell 'dumpsys activity activities | grep mResumedActivity' | tr -d '\r')
say "== 当前前台：${FRONT#*u0 }"
case "$FRONT" in
  *"$PKG"*) say "== 成功：桌面已在运行" ;;
  *) say "== 警告：桌面没有留在前台，看 references/troubleshooting.md" ;;
esac

say ""
say "下一步："
say "  1. 默认桌面：按遥控器 Home，在系统弹的选择器里选「主屏幕 / CleanYourTV」并点「始终」。"
say "  2. 核对结果：skills/cleanyourtv-cn/scripts/verify.sh $TV_HOST"
