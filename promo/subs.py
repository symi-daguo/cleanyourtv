#!/usr/bin/env python3
"""生成字幕并注入 index.html。

时间从 whisper 的 speak.json 来（真实语音时间），
文本用 speak.txt 的原文 —— whisper 会把「净屏」听成「静平」、「臃肿」听成「雍总」，
字幕直接用它就露馅了。

对齐办法：原文按标点切成短句，按累计字数比例映射到 whisper 的起止区间。
TTS 语速均匀，这个映射的误差在 0.3s 内，肉眼看不出。

用法：
    ./subs.py
"""
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
MAX_CHARS = 22          # 单行上限
MIN_CHARS = 5           # 太短的并到下一句，避免闪一下


def clean(s):
    return re.sub(r"\s+", "", s)


def split_units(text):
    """句号优先：一句话就是一行字幕，只有超长才按逗号拆。

    按逗号切会把「关不掉，也删不掉。」拆成两段，再合并时又跟上一句粘在一起，
    出现「你每次真的看完了吗？关不掉，」这种跨句字幕（实测）。
    """
    units = []
    for sent in re.split(r"(?<=[。？！])", clean(text)):
        sent = sent.strip()
        if not sent:
            continue
        if len(sent) <= MAX_CHARS:
            units.append(sent)
            continue
        for p in re.split(r"(?<=[，、；：])", sent):
            p = p.strip()
            if not p:
                continue
            while len(p) > MAX_CHARS:
                cut = max(p.rfind("，", 0, MAX_CHARS), p.rfind("、", 0, MAX_CHARS))
                if cut <= 2:
                    cut = MAX_CHARS
                units.append(p[:cut + 1])
                p = p[cut + 1:]
            if p:
                units.append(p)
    return units


def merge_short(units):
    """把过短的句并到前一句，避免字幕一闪而过。"""
    out = []
    for u in units:
        if out and len(clean(u)) < MIN_CHARS and len(clean(out[-1]) + clean(u)) <= MAX_CHARS:
            out[-1] = out[-1] + u
        elif out and len(clean(u)) < MIN_CHARS:
            out.append(u)          # 并不上就单独留
        else:
            out.append(u)
    return out


def main():
    txt = (HERE / "speak.txt").read_text(encoding="utf-8").strip()
    jf = HERE / "speak.json"
    if not jf.exists():
        print("缺 speak.json（先跑 whisper）", file=sys.stderr)
        return 2
    segs = json.loads(jf.read_text(encoding="utf-8")).get("segments") or []
    if not segs:
        print("speak.json 没有 segments", file=sys.stderr)
        return 2

    total_audio = segs[-1]["end"]
    units = merge_short(split_units(txt))
    n_chars = sum(len(clean(u)) for u in units)

    rows, cum = [], 0
    for u in units:
        c = len(clean(u))
        s = total_audio * (cum / n_chars)
        cum += c
        e = total_audio * (cum / n_chars)
        rows.append({"s": round(s, 2), "e": round(e, 2), "t": u})

    (HERE / "subs.json").write_text(
        json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")

    # 注入 index.html
    html = HERE / "index.html"
    src = html.read_text(encoding="utf-8")
    payload = json.dumps([[r["s"], r["e"], r["t"]] for r in rows],
                         ensure_ascii=False, separators=(",", ":"))
    block = "// <SUBS>\nconst SUBS = %s;\n// </SUBS>" % payload
    src2 = re.sub(r"// <SUBS>.*?// </SUBS>", lambda m: block, src, flags=re.S)
    if src2 == src and "// <SUBS>" not in src:
        print("  ! index.html 里没有 // <SUBS> 占位块", file=sys.stderr)
        return 3
    html.write_text(src2, encoding="utf-8")

    print("  %d 行字幕 / 原文 %d 字 / 语音 %.2fs" % (len(rows), n_chars, total_audio))
    for r in rows[:6]:
        print("  %5.2f-%5.2f  %s" % (r["s"], r["e"], r["t"]))
    print("  …")
    for r in rows[-3:]:
        print("  %5.2f-%5.2f  %s" % (r["s"], r["e"], r["t"]))
    print("  → subs.json，已注入 index.html")
    return 0


if __name__ == "__main__":
    sys.exit(main())
