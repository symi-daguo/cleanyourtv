#!/usr/bin/env bash
# 把一个本地照片目录推到电视上，做成自动轮播的桌面背景。
#
# 用法:
#   skills/cleanyourtv-cn/scripts/set-wallpaper.sh ~/Pictures/家庭照片 192.168.1.50
#   skills/cleanyourtv-cn/scripts/set-wallpaper.sh ~/Pictures/家庭照片 192.168.1.50 --minutes 60 --dim 40
#   skills/cleanyourtv-cn/scripts/set-wallpaper.sh --off 192.168.1.50    # 关掉背景，回到纯色
#
# 照片会自动缩放并裁成 1920x1080、压到 300 KB 以内再传，手机拍的原图直接给就行（HEIC 也认）。
# 只保留当前一张在内存里，实测多占约 5 MB。
set -euo pipefail

MINUTES=30
DIM=35
TILE_OPACITY=45
CAPTIONS=0
OFF=0
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --minutes) MINUTES="${2:?--minutes 后面要跟分钟数}"; shift 2 ;;
    --dim) DIM="${2:?--dim 后面要跟 0-90}"; shift 2 ;;
    --tile-opacity) TILE_OPACITY="${2:?--tile-opacity 后面要跟 0-100}"; shift 2 ;;
    --captions) CAPTIONS=1; shift ;;
    --off) OFF=1; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

say()  { printf '%s\n' "$*"; }
fail() { printf '错误：%s\n' "$*" >&2; exit 1; }

# --off 时只给电视地址；否则第一个参数是照片目录。
if [ "$OFF" = 1 ]; then
  TV_HOST="${ARGS[0]:-${TV_HOST:-}}"
  SRC_DIR=""
else
  SRC_DIR="${ARGS[0]:-}"
  TV_HOST="${ARGS[1]:-${TV_HOST:-}}"
fi
[ -n "$TV_HOST" ] || fail "没有电视地址。用法：$0 <照片目录> <电视地址>"
[ "$OFF" = 1 ] || [ -d "$SRC_DIR" ] || fail "照片目录不存在：${SRC_DIR:-（空）}"

if command -v adb >/dev/null 2>&1; then
  ADB=adb
elif [ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]; then
  ADB="$HOME/Library/Android/sdk/platform-tools/adb"
else
  fail "找不到 adb。"
fi

TARGET="$TV_HOST"
case "$TARGET" in *:*) ;; *) TARGET="$TV_HOST:5555" ;; esac

"$ADB" connect "$TARGET" >/dev/null 2>&1 || true
[ "$("$ADB" -s "$TARGET" get-state 2>/dev/null)" = "device" ] || fail "连不上 ${TARGET}"

PKG=com.gathin.tvhome
DIR=/sdcard/Android/data/$PKG/files

# 有些电视把 /sdcard 裁掉了（海信 VIDAA），应用连外部目录都建不出来，照片无从谈起。
# 先探一次，不然推完一屏报错更让人摸不着头脑。adb shell 的退出码不可靠，得看目录在不在。
"$ADB" -s "$TARGET" shell "mkdir -p $DIR/wallpapers" >/dev/null 2>&1 || true
if ! "$ADB" -s "$TARGET" shell "test -d $DIR/wallpapers && echo YES" 2>/dev/null | tr -d '\r' | grep -q YES; then
  fail "这台电视建不出 ${DIR}（外部存储被裁掉，常见于海信 VIDAA）。照片推不上去，只能把图编译进 APK。"
fi

restart_home() {
  "$ADB" -s "$TARGET" shell am force-stop "$PKG" >/dev/null 2>&1 || true
  sleep 1
  "$ADB" -s "$TARGET" shell am start -n "$PKG/.MainActivity" >/dev/null 2>&1 || true
  sleep 3
}

if [ "$OFF" = 1 ]; then
  say "== 关掉照片背景，回到纯色"
  "$ADB" -s "$TARGET" shell "rm -f $DIR/config.json; rm -f $DIR/wallpapers/*.jpg $DIR/wallpapers/*.jpeg $DIR/wallpapers/*.png $DIR/wallpapers/*.webp 2>/dev/null; echo off-$$ > $DIR/theme_revision"
  restart_home
  say "== 完成"
  exit 0
fi

# --- 处理照片 ---
WORK="${TMPDIR:-/tmp}/cleanyourtv-wallpaper.$$"
mkdir -p "$WORK/photos"
trap 'rm -rf "$WORK"' EXIT

if command -v ffmpeg >/dev/null 2>&1; then
  TOOL=ffmpeg
elif command -v sips >/dev/null 2>&1; then
  TOOL=sips
else
  fail "需要 ffmpeg 或 sips 来压缩图片。macOS 自带 sips；Linux 装 ffmpeg。"
fi
say "== 处理照片（${TOOL}）：$SRC_DIR"

N=0
CAP_FILE="$WORK/photos/captions.txt"
: > "$CAP_FILE"
shopt -s nullglob nocaseglob
for f in "$SRC_DIR"/*.jpg "$SRC_DIR"/*.jpeg "$SRC_DIR"/*.png "$SRC_DIR"/*.heic "$SRC_DIR"/*.webp; do
  N=$((N+1))
  [ "$N" -le 100 ] || { say "== 只取前 100 张（桌面自身的上限）"; break; }
  OUT=$(printf "%03d.jpg" "$N")
  if [ "$TOOL" = ffmpeg ]; then
    # 先缩放到盖满 1920x1080 再居中裁切，省得桌面再去裁一遍浪费像素。
    ffmpeg -v error -i "$f" \
      -vf "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080" \
      -q:v 4 "$WORK/photos/$OUT" -y 2>/dev/null || { N=$((N-1)); continue; }
  else
    sips -Z 1920 -s format jpeg -s formatOptions 60 "$f" --out "$WORK/photos/$OUT" >/dev/null 2>&1 \
      || { N=$((N-1)); continue; }
  fi
  # 名字用原文件名（去掉扩展名），方便在电视上认出是哪张。
  NAME=$(basename "$f")
  NAME="${NAME%.*}"
  printf '%s\t%s\n' "$OUT" "$NAME" >> "$CAP_FILE"
done
[ "$N" -gt 0 ] || fail "目录里没有可用的图片（支持 jpg/jpeg/png/heic/webp）"
say "== 处理完成：$N 张，合计 $(du -sh "$WORK/photos" | awk '{print $1}')"

# --- 配置 ---
{
  printf '{\n'
  printf '  "wallpaper": true,\n'
  printf '  "wallpaper_rotation_minutes": %s,\n' "$MINUTES"
  printf '  "wallpaper_order": "shuffle",\n'
  printf '  "wallpaper_dim": %s,\n' "$DIM"
  printf '  "wallpaper_captions": %s,\n' "$([ "$CAPTIONS" = 1 ] && echo true || echo false)"
  # 卡片和 dock 默认是不透明的深色块，照片背景会被它们盖住。调淡后图标和名字仍不透明。
  printf '  "tile_opacity": %s,\n' "$TILE_OPACITY"
  # dock_band 默认 true，会在第一行四个图标外面画一块固定底板和边框。焦点移到下面的行时它不动，
  # 看着像焦点框卡在第一行。false 让所有图标直接浮在照片上，焦点框才是唯一的框。
  printf '  "dock_band": false,\n'
  # 照片配缓慢的推拉漂移，静态图才不像卡住。只改变换矩阵，不额外占内存。
  printf '  "wallpaper_motion": true\n' 
  printf '}\n'
} > "$WORK/config.json"

# --- 推送：先清旧图，免得换了照片还轮出上一批 ---
say "== 清掉电视上的旧照片"
"$ADB" -s "$TARGET" shell "rm -f $DIR/wallpapers/*.jpg $DIR/wallpapers/*.jpeg $DIR/wallpapers/*.png $DIR/wallpapers/*.webp $DIR/wallpapers/captions.txt 2>/dev/null"

say "== 推送 $N 张"
for f in "$WORK"/photos/*.jpg; do
  "$ADB" -s "$TARGET" push "$f" "$DIR/wallpapers/" >/dev/null 2>&1 || fail "推送 $(basename "$f") 失败"
done
[ "$CAPTIONS" = 1 ] && "$ADB" -s "$TARGET" push "$CAP_FILE" "$DIR/wallpapers/captions.txt" >/dev/null 2>&1
"$ADB" -s "$TARGET" push "$WORK/config.json" "$DIR/config.json" >/dev/null 2>&1 || fail "推送 config.json 失败"
"$ADB" -s "$TARGET" shell "echo wl-$$ > $DIR/theme_revision"

restart_home

say "== 电视上的照片："
"$ADB" -s "$TARGET" shell "ls $DIR/wallpapers" 2>/dev/null | tr -d '\r' | sed 's/^/   /'

FRONT=$("$ADB" -s "$TARGET" shell 'dumpsys activity activities | grep mResumedActivity' 2>/dev/null | tr -d '\r')
case "$FRONT" in
  *"$PKG"*) say "== 成功：背景已换成你的照片，每 ${MINUTES} 分钟换一张" ;;
  *) say "== 背景已推送，但桌面没留在前台（前台是 ${FRONT#*u0 }）" ;;
esac
say ""
say "想停掉：$0 --off $TV_HOST"
