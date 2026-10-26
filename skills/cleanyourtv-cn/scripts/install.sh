#!/usr/bin/env bash
# 把 CleanYourTV 桌面装到电视上。
#
# 默认走最短路径：从发布的 release 里下我们编好、验证过的 APK，直接 adb 安装。不装 JDK、不装 Android SDK、
# 不等 Gradle。只有下载不到、或者这个包在这台电视上装不上时，才回退到本地构建——那说明这台机器有额外的
# 情况（系统裁剪、厂商限制），脚本会把构建参数按它的 Android 版本重算。
#
# 用法:
#   skills/cleanyourtv-cn/scripts/install.sh 192.168.1.50
#   TV_HOST=192.168.1.50 skills/cleanyourtv-cn/scripts/install.sh
#   skills/cleanyourtv-cn/scripts/install.sh 192.168.1.50 --build        # 跳过下载，直接本地构建
#   skills/cleanyourtv-cn/scripts/install.sh 192.168.1.50 --apk ~/x.apk  # 用指定的 APK
#
# 只做三件事：拿到包、adb install、启动。不停用任何包，不碰系统设置。
set -euo pipefail

cd "$(dirname "$0")/../../.."
REPO="$(pwd)"
PKG=com.gathin.tvhome
# 这两个名字在 release 里固定不变，所以 /releases/latest/download/ 永远指向最新一版。
REPO_SLUG="${CLEANYOURTV_REPO:-symi-daguo/cleanyourtv}"
APK=""
FORCE_BUILD=0
TV_HOST="${TV_HOST:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --build) FORCE_BUILD=1; shift ;;
    --apk) APK="${2:?--apk 后面要跟 APK 路径}"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
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

say "== 连接 ${TARGET}"
"$ADB" connect "$TARGET" >/dev/null 2>&1 || true
STATE=$("$ADB" -s "$TARGET" get-state 2>/dev/null || true)
if [ "$STATE" != "device" ]; then
  if "$ADB" devices | grep -q "^$TARGET[[:space:]]*unauthorized"; then
    fail "电视还没授权这台电脑。电视上会弹「允许 USB 调试」的窗口，用遥控器点允许，再跑一次。"
  fi
  fail "连不上 ${TARGET}（状态：${STATE:-无}）。确认电视和电脑在同一网络、电视的「网络调试/ADB 调试」已打开。详见 references/troubleshooting.md。"
fi

SDK=$("$ADB" -s "$TARGET" shell getprop ro.build.version.sdk | tr -d '\r')
MODEL=$("$ADB" -s "$TARGET" shell getprop ro.product.model | tr -d '\r')
REL=$("$ADB" -s "$TARGET" shell getprop ro.build.version.release | tr -d '\r')
LOCALE=$("$ADB" -s "$TARGET" shell getprop persist.sys.locale | tr -d '\r')
say "== 电视：${MODEL} / Android ${REL} (SDK ${SDK}) / 语言 ${LOCALE:-未知}"

if [ -n "$SDK" ] && [ "$SDK" -lt 23 ] 2>/dev/null; then
  fail "这台是 Android ${REL}（SDK ${SDK}），低于这个桌面能编出来的最低版本 23（Android 6.0）。装不了，别试了。"
fi

# --- 按电视版本挑包 ---
# release 里有两个包，名字固定：
#   cleanyourtv-cn-min26.apk  minSdk 26，Android 8.0 起，479 KB
#   cleanyourtv-cn-min23.apk  minSdk 23，Android 6.0 起，698 KB（多了 java.time 的兼容层）
if [ -n "$SDK" ] && [ "$SDK" -lt 26 ] 2>/dev/null; then
  TIER=min23
  BUILD_ARGS=("-PlauncherMinSdk=$SDK")
else
  TIER=min26
  BUILD_ARGS=()
fi
say "== 这台用 ${TIER} 包"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cleanyourtv"
mkdir -p "$CACHE_DIR" 2>/dev/null || CACHE_DIR="$REPO/.cache"
mkdir -p "$CACHE_DIR"

# 下载到 .part 再改名：中途断网留半截文件，下次会被当成完整的包用。
fetch_remote_apk() {
  local dest="$CACHE_DIR/cleanyourtv-cn-$TIER.apk"
  # GitHub 在国内可能很慢，允许换镜像：CLEANYOURTV_APK_URL=https://某个镜像/cleanyourtv-cn-min23.apk
  local url="${CLEANYOURTV_APK_URL:-https://github.com/$REPO_SLUG/releases/latest/download/cleanyourtv-cn-$TIER.apk}"
  # 缓存七天有效。没有过期判断时，release 换了一版、缓存里还是上一版，脚本会把旧包当"上次下载的"
  # 直接装上，人却以为装的是新版。
  if [ -s "$dest" ] && [ -z "$(find "$dest" -mtime +7 2>/dev/null)" ]; then
    say "== 用上次下载的包：${dest}（超过七天会重新下载）"
    return 0
  fi
  say "== 下载现成包 ${TIER}（不用本地构建，约 $([ "$TIER" = min23 ] && echo 700 || echo 480) KB）"
  say "   ${url}"
  if command -v curl >/dev/null 2>&1; then
    # 超时给够：直连 GitHub 下 700 KB 有时要半分钟，断线重试两次再放弃。
    curl -fsSL --connect-timeout 15 --max-time 180 --retry 2 --retry-delay 3 \
      -o "$dest.part" "$url" || { rm -f "$dest.part"; return 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 180 --tries=3 -O "$dest.part" "$url" || { rm -f "$dest.part"; return 1; }
  else
    say "== 没有 curl/wget，跳过下载"
    return 1
  fi
  # curl 在重试之间会把自己的错误打到 stderr，最后成功了却不出声，容易让人以为下载失败了。
  say "== 下载完成（$(( $(wc -c < "$dest.part") / 1024 )) KB）"
  # 下载被截断时 zip 是坏的，装到一半才报错比现在报错更费时间。
  if ! unzip -tq "$dest.part" >/dev/null 2>&1; then
    rm -f "$dest.part"
    say "== 下载的包不完整，作废"
    return 1
  fi
  mv "$dest.part" "$dest"
  return 0
}

build_apk() {
  local apk="$REPO/launcher/app/build/outputs/apk/release/app-release.apk"
  say "== 本地构建（需要 JDK 17 或 21；第一次会下载 Gradle 和依赖）"
  ( cd "$REPO/launcher" && ./gradlew assembleRelease ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} --console=plain ) \
    || return 1
  [ -f "$apk" ] || return 1
  APK="$apk"
  return 0
}

# 0 = 装上了，1 = 这个包不行（换一个还能试），2 = 这台电视不行（换包也没用）
install_apk() {
  local apk="$1" out
  say "== 安装 $(basename "$apk")（$(( $(wc -c < "$apk") / 1024 )) KB）"
  out=$("$ADB" -s "$TARGET" install -r "$apk" 2>&1) || true
  printf '%s\n' "$out"
  case "$out" in
    *Success*) return 0 ;;
    *INSTALL_FAILED_VERIFICATION_FAILURE*)
      say "== 这台电视拒绝了侧载（厂商校验）。桌面这条路走不通，只能做去膨胀，见 references/troubleshooting.md。"
      return 2 ;;
    *INSTALL_FAILED_UPDATE_INCOMPATIBLE*)
      say "== 电视上是另一个签名的旧版本。先执行：$ADB -s $TARGET uninstall $PKG"
      return 2 ;;
    *) return 1 ;;
  esac
}

INSTALLED=0

if [ -n "$APK" ]; then
  # 用户点名要装的包，不做任何替换。
  [ -f "$APK" ] || fail "APK 不存在：${APK}"
  if install_apk "$APK"; then INSTALLED=1; fi
elif [ "$FORCE_BUILD" = 1 ]; then
  build_apk || fail "构建失败。看 launcher 的 Gradle 输出；JDK 需要 17 或 21。"
  if install_apk "$APK"; then INSTALLED=1; fi
else
  # 先下现成的。装上了就结束，绝大部分机器走这条。
  if fetch_remote_apk; then
    RC=0
    install_apk "$CACHE_DIR/cleanyourtv-cn-$TIER.apk" || RC=$?
    [ "$RC" -eq 0 ] && INSTALLED=1
    [ "$RC" -eq 2 ] && exit 1
    [ "$INSTALLED" -eq 1 ] || say "== 现成包在这台没装上，回头按它的 Android 版本本地构建再试"
  else
    say "== 没有拿到现成包（网络或 release 不可用），改走本地构建"
  fi
  # 只有现成包失败才构建：说明这台机器的系统版本或厂商定制和通用包不一样。
  if [ "$INSTALLED" -eq 0 ]; then
    build_apk || fail "下载没成功，本地构建也失败了。要么装 JDK 17/21 重试，要么用 --apk 指定一个包。"
    if install_apk "$APK"; then INSTALLED=1; fi
  fi
fi

[ "$INSTALLED" -eq 1 ] || fail "安装没成功，上面是 adb 的原始输出。对照 references/troubleshooting.md 看是哪一类。"

# --- 语言 ---
# 桌面没有应用内语言开关：Android 13+ 用 per-app 语言，13 以下跟着系统语言走。
if [ -n "$SDK" ] && [ "$SDK" -ge 33 ] 2>/dev/null; then
  if "$ADB" -s "$TARGET" shell cmd locale set-app-locales "$PKG" --locales zh-CN >/dev/null 2>&1; then
    say "== 已把应用语言设为 zh-CN（Android 13+ 的 per-app 语言）"
  else
    say "== 提示：这台机器没能设置 per-app 语言，界面跟随系统语言"
  fi
else
  say "== 提示：Android ${REL} 不支持单独设置应用语言，界面跟随系统语言（当前 ${LOCALE:-未知}）"
fi

# --- 启动 ---
say "== 启动"
# 尝试设为默认桌面。命令行不是万能的：有的电视把 systemui 或自家桌面注册成 HOME 且 isDefault=true，
# 这时 set-home-activity 会返回 Success 却按 Home 仍回原厂（实测中兴 ZXV10 就是这样）。所以这里只当
# 辅助手段，真正的判断交给按一次 Home 键 —— 不承诺成功，也不会因为失败就报错。
SDK=$("$ADB" -s "$TARGET" shell getprop ro.build.version.sdk | tr -d '\r')
if [ "${SDK:-0}" -ge 26 ] 2>/dev/null; then
  "$ADB" -s "$TARGET" shell cmd package set-home-activity --user 0 "$PKG/.MainActivity" >/dev/null 2>&1 || true
fi
say "== 请按一次遥控器 Home 键确认"
say "   回到本桌面：说明已是默认，完成"
say "   回到原厂桌面或弹出选择框：在框里选 CleanYourTV 并勾「始终」；"
say "   若没有勾选项，去 设置 → 应用 → 默认应用 → 主屏幕 改"

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
