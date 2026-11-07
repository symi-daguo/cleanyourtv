#!/usr/bin/env python3
"""字幕：每幕一句关键短语，按幕起止整段显示。

**为什么不用口播全文当字幕**（这是之前做错的地方）：
    旧版成片（miloco 120s）的字幕不是逐字念稿，是每幕一句提炼 ——
    口播「家里那台米家摄像头，本来只负责录。现在它能看懂…」，
    画面字幕只写「摄像头不只是看」。
    把口播全文压成字幕条有两个问题：
      ① 画面上已经有大标题，两套文字打架，看着乱；
      ② 字幕一秒切两三次，观众眼睛一直在跳。

**为什么时间按幕给，不按字数比例**：
    字数比例 ≠ 真实语速（数字、英文、标点的读法差很多），
    实测会出现字幕和语音差半句。幕起止来自 whisper 时间戳（timeline.json），
    是真实语音时间。

用法：
    ./subs.py
输入：
    cues.txt       10 行，每幕一句（和 index.html 的幕数一致）
    timeline.json  align.py 生成的幕起止
输出：
    subs.json + 注入 index.html 的 // <SUBS> 块
"""
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ORDER = ["s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10"]
MAX_CHARS = 26          # 单行上限（英文/数字视觉窄，比纯中文放宽）


def main():
    cues = [l.strip() for l in (HERE / "cues.txt").read_text(encoding="utf-8").splitlines()
            if l.strip()]
    tl = json.loads((HERE / "timeline.json").read_text(encoding="utf-8"))
    spans = tl["spans"]

    if len(cues) != len(ORDER):
        print("cues.txt 有 %d 行，但幕有 %d 个 —— 必须一一对应" % (len(cues), len(ORDER)),
              file=sys.stderr)
        return 2

    rows = []
    for k, txt in zip(ORDER, cues):
        if k not in spans:
            print("timeline.json 里没有 %s" % k, file=sys.stderr)
            return 3
        s, e = spans[k]
        if len(txt) > MAX_CHARS:
            print("  ⚠ %s 字幕 %d 字，超过 %d：%s" % (k, len(txt), MAX_CHARS, txt))
        # 幕尾留 0.25s 空档，避免和下一幕字幕粘连
        rows.append([round(s + 0.06, 2), round(max(s + 0.5, e - 0.25), 2), txt])

    (HERE / "subs.json").write_text(
        json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")

    payload = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    block = "// <SUBS>\nconst SUBS = %s;\n// </SUBS>" % payload
    html = HERE / "index.html"
    src = html.read_text(encoding="utf-8")
    out = re.sub(r"// <SUBS>.*?// </SUBS>", lambda m: block, src, flags=re.S)
    if out == src and "// <SUBS>" not in src:
        print("index.html 里没有 // <SUBS> 占位块", file=sys.stderr)
        return 3
    html.write_text(out, encoding="utf-8")

    print("  %d 幕字幕：" % len(rows))
    for r in rows:
        print("  %6.2f-%6.2f  %s" % (r[0], r[1], r[2]))
    print("  → subs.json，已注入 index.html")
    return 0


if __name__ == "__main__":
    sys.exit(main())
