#!/usr/bin/env bash
# Fetch the ocean wallpaper clips and turn them into what a TV can actually decode.
#
# Usage: fetch-videos.sh [output-dir]
#
# The clips come from Mixkit's free stock video collection, whose licence covers personal and commercial use
# but asks you not to resell or redistribute the raw files - so this script downloads them from their source
# instead of shipping them in this repository. Swap in your own footage the same way: drop an .mp4 into
# <output-dir>/ and push it with push-videos.sh.
#
# What it does to each clip:
#   - cuts it to a max length and scales it to 1280x720 (the set's panel is 1920x1080; 720p keeps the
#     decoder's buffers small, which matters on a 1 GB TV)
#   - crossfades the last second into the first, so the loop has no seam
#   - encodes H.264 baseline, 25 fps, no audio track
#
# Needs ffmpeg and curl. Nothing leaves the computer except the requests to Mixkit.
set -euo pipefail

OUT="${1:-$(cd "$(dirname "$0")" && pwd)/../videos}"
# The four ocean clips that ship as the default: a school of yellow tangs over the reef, a big school in open
# blue water, a busy reef, and tropical fish moving through the coral. All are Mixkit's, free for personal and
# commercial use. Add more ids here to widen the set; CLIPS="44869 44976 ..." fetches exactly those.
CLIPS="${CLIPS:-44869 44976 47402 44871}"
MAXLEN="${MAXLEN:-24}"
# How much the footage is slowed and at what frame rate it is delivered. These two carry the smoothness:
# the wallpaper has to look calm, so the walk is stretched to a third of its speed and delivered at the
# standard 30 the TV pipeline is tuned for. 15 fps also works; the HSPlayer on these sets paces standard
# rates more evenly, and the hardware-composer path we render through is not the bottleneck any more.
SLOW="${SLOW:-3.0}"
FPS="${FPS:-30}"

command -v ffmpeg >/dev/null || { echo "需要 ffmpeg"; exit 1; }
command -v curl >/dev/null || { echo "需要 curl"; exit 1; }
mkdir -p "$OUT"

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

for ID in $CLIPS; do
    url="https://assets.mixkit.co/videos/$ID/$ID-720.mp4"
    raw="$OUT/.raw-$ID.mp4"
    target="$OUT/ocean-$ID.mp4"

    if [ ! -s "$raw" ]; then
        echo "下载 ${ID} ..."
        got=""
        if curl -sfL -A "$UA" --max-time 180 -o "$raw" "$url"; then
            got="直链"
        else
            # Newer uploads do not follow the /videos/<id>/<id>-720.mp4 shape: their page carries the file
            # under an opaque name. The page is found through the category listing, then read for the file.
            /bin/rm -f "$raw"
            slug=""
            for term in underwater fish ocean coral; do
                listing=$(curl -s --max-time 40 -A "$UA" "https://mixkit.co/free-stock-video/discover/$term/")
                slug=$(echo "$listing" | grep -oE "/free-stock-video/[a-z0-9-]+-$ID/" | head -1 | sed 's#/$##;s#^/free-stock-video/##' || true)
                [ -n "$slug" ] && break
            done
            page=""
            if [ -n "$slug" ]; then
                page=$(curl -s --max-time 40 -A "$UA" "https://mixkit.co/free-stock-video/$slug/" || true)
            fi
            for asset in $(echo "$page" | grep -oE 'https://assets\.mixkit\.co/[a-z0-9]{25,30}' | sort -u); do
                if curl -sfL -A "$UA" -e "https://mixkit.co/" --max-time 180 -o "$raw" "$asset"; then
                    if [ "$(stat -f %z "$raw" 2>/dev/null || echo 0)" -gt 200000 ]; then got="页面"; break; fi
                fi
                /bin/rm -f "$raw"
            done
        fi
        if [ -z "$got" ]; then
            echo "  跳过 ${ID}（取不到源文件）"
            /bin/rm -f "$raw"
            continue
        fi
    fi

    # The cut length is in source seconds; slowing stretches the output to SLOW times that. A wallpaper has
    # to look calm: slowing the footage SLOW times and delivering it at FPS means the decoder handles far
    # fewer frames per second, which is what makes the drift read as smooth on a 1 GB TV.
    dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$raw" | cut -d. -f1)
    [ "$dur" -gt "$MAXLEN" ] && dur=$MAXLEN
    outdur=$(echo "$dur $SLOW" | awk '{printf "%d", $1 * $2}')
    echo "转码 ${ID}：源 ${dur}s，放慢 ${SLOW}x → 约 ${outdur}s，${FPS}fps，无缝循环"
    ffmpeg -v error -y -i "$raw" -filter_complex \
        "[0:v]setpts=${SLOW}*PTS,fps=${FPS},scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,setsar=1,split[a][b];\
[a]trim=0:$((outdur-2)),setpts=PTS-STARTPTS[main];\
[b]trim=$((outdur-2)):$((outdur-1)),setpts=PTS-STARTPTS[tail];\
[main][tail]xfade=transition=fade:duration=1:offset=$((outdur-3))[v]" \
        -map "[v]" -c:v libx264 -profile:v baseline -level 3.1 -preset medium -crf 26 \
        -maxrate 1400k -bufsize 2800k -pix_fmt yuv420p -g $((FPS * 5)) -an -movflags +faststart "$target"
    /bin/rm -f "$raw"
    echo "  → $target  $(du -h "$target" | cut -f1)"
done

echo
echo "片源在 ${OUT}，用 push-videos.sh 推到电视："
echo "  bash push-videos.sh <电视IP> [片源目录]"
