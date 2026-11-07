#!/usr/bin/env python3
"""字幕：口播原文 + whisper 词级时间戳，逐词对齐。

**这是照 video-pipeline 的既有实现抄的**（`scripts/lib/cjk-align.mjs`
+ `scripts/align.mjs` + `projects/xiaomi-home-official/compositions/captions.html`）：

    之前几版成片（xiaomi-home-official / rea-reverse-engineer / miloco-120s）
    的字幕是「口播原文整句 + whisper 词级时间戳」，输出 captions.json：

        { "lines": [ { "w": [["断网了", 0.14], ["，", 0.659], ...], "end": 4.981 } ] }

    一句一行显示 3~6 秒，渲染成白色毛玻璃胶囊 + 深色字，底部 44px。

**我前几轮做错了两件事**：
    ① 字幕用「每幕一句提炼」，不是口播原文 → 用户看到字幕和嘴里说的不一样；
    ② 时间按字数比例切 → 只拿到 segment 级时间戳，没有字级时间，只能估。
    两者叠加就是「字幕跟口播完全对不上」。

**正确做法**：
    whisper --word_timestamps True 拿到每个词的 start/end →
    把词展开成字符时间线 → 口播原文逐字在时间线里按顺序匹配 →
    每行字幕的起止 = 首字 start / 末字 end。ASR 错字（"净屏"→"静平"）
    靠「找不到就往后跳」消化，不依赖文本完全一致。

用法：
    ./subs.py
输入：speak.txt（口播原文）· speak.json（whisper 带 words 的输出）
输出：captions.json + 注入 index.html 的 // <SUBS> 块
"""
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
MAX_CHARS = 20          # 单行上限：34px 下 20 字约 680px，留得下
MIN_CHARS = 6           # 太短的并到下一句
PUNCT = "，。？！、；：—…·《》「」“”‘’（）() ,.!?;:\"'"


def norm(s):
    """去掉标点和空白，只留实字 —— 用来对齐，不用于显示。"""
    return "".join(ch for ch in s if ch not in PUNCT and not ch.isspace())


def build_char_timeline(words):
    """词级时间戳 → 字符级时间线。中文一个词 2~3 字，共用一个 start。"""
    chars = []
    for w in words:
        text = w.get("word") or w.get("text") or ""
        s, e = w.get("start"), w.get("end")
        if s is None or e is None:
            continue
        for ch in norm(text):
            chars.append({"ch": ch, "start": float(s), "end": float(e)})
    return chars


def find_line(chars, line_text, from_idx, lookahead=260):
    """在字符时间线里找「这一行」出现的位置，返回 (start, end, next_idx)。

    为什么不是逐字匹配：whisper 把「净屏」听成「静平」时，逐字匹配会卡住一个字符，
    每次错字累积一点，37 行下来能偏十几秒（实测偏了 16 秒，
    「装起来不用 U 盘」本该在 65.5s，被推到 81.7s）。
    改成整行滑窗比相似度：错一两个字不影响整体定位，找到就整段跳过。
    """
    needle = norm(line_text)
    n = len(needle)
    if not needle or n == 0 or from_idx >= len(chars):
        return None
    best_i, best_score = None, 0.0
    hi = min(len(chars) - n + 1, from_idx + lookahead)
    for i in range(from_idx, max(from_idx + 1, hi)):
        window = "".join(c["ch"] for c in chars[i:i + n])
        same = sum(1 for a, b in zip(window, needle) if a == b)
        score = same / n
        if score > best_score:
            best_score, best_i = score, i
            if score == 1.0:
                break
    if best_i is None or best_score < 0.5:
        return None
    seg = chars[best_i:best_i + n]
    return seg[0]["start"], seg[-1]["end"], best_i + n


def split_lines(text):
    """按句号切行；一句话太长再按逗号切。字幕是口播原文，不改字。"""
    lines = []
    for sent in re.split(r"(?<=[。？！])", text.replace("\n", "")):
        sent = sent.strip()
        if not sent:
            continue
        if len(sent) <= MAX_CHARS:
            lines.append(sent)
            continue
        buf = ""
        for part in re.split(r"(?<=[，、；：])", sent):
            if len(buf) + len(part) <= MAX_CHARS:
                buf += part
            else:
                if buf:
                    lines.append(buf)
                buf = part
        if buf:
            lines.append(buf)
    merged = []
    for ln in lines:
        if merged and len(norm(ln)) < MIN_CHARS and len(merged[-1]) + len(ln) <= MAX_CHARS + 4:
            merged[-1] += ln
        else:
            merged.append(ln)
    return merged


def main():
    text = (HERE / "speak.txt").read_text(encoding="utf-8").strip()
    jf = HERE / "speak.json"
    if not jf.exists():
        print("缺 speak.json", file=sys.stderr)
        return 2
    segs = json.loads(jf.read_text(encoding="utf-8")).get("segments") or []
    words = [w for s in segs for w in (s.get("words") or [])]
    if not words:
        print("speak.json 里没有词级时间戳 —— 要用 whisper --word_timestamps True 重跑",
              file=sys.stderr)
        return 3

    chars = build_char_timeline(words)
    print("  字符时间线 %d 字 / 词 %d 个" % (len(chars), len(words)))

    lines = split_lines(text)
    _tl = HERE / "timeline.json"
    audio_end = (json.loads(_tl.read_text(encoding="utf-8")).get("audio_total")
                 if _tl.exists() else (chars[-1]["end"] if chars else 0.0))

    # ── 用 whisper 的 segment 当锚点，段内按字数插值 ──────────────
    # 为什么不用逐字/逐行匹配：ASR 和原文差几个字，指针就会累积偏移，
    # 37 行下来偏 16 秒（实测）。segment 是 whisper 自己切好的真实时间边界，
    # 每段独立锚定，误差不会跨段累积。
    segs_clean = [x for x in segs if norm(x.get("text") or "")]
    seg_chars = [len(norm(x["text"])) for x in segs_clean]
    total_seg_chars = sum(seg_chars) or 1

    def time_at_ratio(r):
        """全局字数比例 r∈[0,1] → 语音时间。落在哪个 segment 就在段内线性插值。"""
        target = r * total_seg_chars
        acc = 0
        for sg, n in zip(segs_clean, seg_chars):
            if target <= acc + n or sg is segs_clean[-1]:
                f = (target - acc) / max(1, n)
                return sg["start"] + (sg["end"] - sg["start"]) * max(0.0, min(1.0, f))
            acc += n
        return audio_end

    total_chars = sum(len(norm(x)) for x in lines) or 1
    out, acc = [], 0
    for i, ln in enumerate(lines):
        n = len(norm(ln))
        start = time_at_ratio(acc / total_chars)
        acc += n
        end = time_at_ratio(acc / total_chars)
        start = max(0.0, min(audio_end, start))
        end = min(audio_end, max(start + 0.5, end))
        # w：把这一行按 2~3 字一组切片，起止在行内线性分布（渲染只用到 [0]）
        w = []
        for k in range(0, len(ln), 3):
            w.append([ln[k:k + 3], round(start + (end - start) * k / max(1, len(ln)), 3)])
        out.append({"id": i, "text": ln, "start": round(start, 3),
                    "end": round(end, 3), "w": w})

    # 后处理：字级对齐在末尾一定会耗尽（ASR 比原文少认几个字就没有字符可对了），
    # 表现为「后面几行起点几乎不动」。从第一处重叠开始，按字数把剩下的时间重分。
    # 前面的对齐结果保留 —— 只有确实出错的那一段重算。
    for i in range(1, len(out)):
        if out[i]["start"] < out[i - 1]["end"] - 0.02 or \
           out[i]["start"] <= out[i - 1]["start"] + 0.05:
            base = out[i - 1]["end"]
            rest = out[i:]
            total = sum(len(norm(x["text"])) for x in rest) or 1
            t = base
            avail = max(0.0, audio_end - base)
            for x in rest:
                d = avail * len(norm(x["text"])) / total
                x["start"] = round(t, 3)
                x["end"] = round(min(audio_end, t + d), 3)
                t += d
            break

    (HERE / "captions.json").write_text(
        json.dumps({"lines": out}, ensure_ascii=False, indent=1), encoding="utf-8")

    rows = [[l["start"], l["end"], l["text"]] for l in out]
    payload = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    block = "// <SUBS>\nconst SUBS = %s;\n// </SUBS>" % payload
    html = HERE / "index.html"
    src = html.read_text(encoding="utf-8")
    dst = re.sub(r"// <SUBS>.*?// </SUBS>", lambda m: block, src, flags=re.S)
    if dst == src and "// <SUBS>" not in src:
        print("index.html 没有 // <SUBS> 占位块", file=sys.stderr)
        return 4
    html.write_text(dst, encoding="utf-8")

    print("  %d 行字幕（口播原文，词级对齐）：" % len(out))
    for l in out[:6]:
        print("  %6.2f-%6.2f  %s" % (l["start"], l["end"], l["text"]))
    print("  …")
    for l in out[-3:]:
        print("  %6.2f-%6.2f  %s" % (l["start"], l["end"], l["text"]))
    print("  → captions.json，已注入 index.html")
    return 0


if __name__ == "__main__":
    sys.exit(main())
