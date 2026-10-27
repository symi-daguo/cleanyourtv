#!/usr/bin/env bash
# 对比本仓库和上游，回答一个问题：上游改了哪些我们还没跟，我们又改了哪些上游没有。
#
# 用法：tools/fork-sync.sh [上游 owner/repo]
#
# 依赖 gh（已登录）。不修改任何文件，只读。
set -u
UPSTREAM="${1:-Gathin23/cleanyourtv}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
JAVA="$HERE/launcher/app/src/main/java/com/gathin/tvhome"

say() { printf '%s\n' "$*"; }

say "=== 上游 $UPSTREAM 与本地对比 ==="
say ""

# 上游最新提交
LATEST=$(gh api "repos/$UPSTREAM/commits" --jq '.[0] | "\(.sha[0:8])  \(.commit.author.date)  \(.commit.message | split("\n")[0])"' 2>/dev/null)
say "上游最新：$LATEST"
say ""

BEHIND=0
AHEAD=0
SAME=0
MISSING=0

for f in "$JAVA"/*.java; do
  NAME=$(basename "$f")
  LOCAL_LINES=$(wc -l < "$f" | tr -d ' ')
  REMOTE=$(gh api "repos/$UPSTREAM/contents/launcher/app/src/main/java/com/gathin/tvhome/$NAME" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)
  if [ -z "$REMOTE" ]; then
    say "  [本地独有] ${NAME}（${LOCAL_LINES} 行）"
    MISSING=$((MISSING + 1))
    continue
  fi
  REMOTE_LINES=$(printf '%s' "$REMOTE" | wc -l | tr -d ' ')
  DIFF=$((LOCAL_LINES - REMOTE_LINES))
  # 差一行几乎都是行尾换行的统计差异，不算改动；只看真正的行数差。
  if [ "$DIFF" -ge -1 ] && [ "$DIFF" -le 1 ]; then
    SAME=$((SAME + 1))
  elif [ "$DIFF" -lt 0 ]; then
    say "  [落后 $((-DIFF)) 行] ${NAME}（上游 ${REMOTE_LINES}，本地 ${LOCAL_LINES}）"
    BEHIND=$((BEHIND + 1))
  else
    say "  [领先 ${DIFF} 行] ${NAME}（上游 ${REMOTE_LINES}，本地 ${LOCAL_LINES}）"
    AHEAD=$((AHEAD + 1))
  fi
done

say ""
say "=== 汇总 ==="
say "  一致：$SAME 个文件"
say "  落后上游：$BEHIND 个（上游加了东西，我们没跟）"
say "  领先上游：$AHEAD 个（我们的改动，提 PR 或留在 Fork）"
say "  本地独有：$MISSING 个（Fork 特供，上游没有）"
say ""
say "看具体差异："
say "  gh api repos/$UPSTREAM/contents/<路径> --jq .content | base64 -d > /tmp/up.java && diff -u /tmp/up.java <本地文件>"
