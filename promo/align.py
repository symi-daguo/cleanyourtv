#!/usr/bin/env python3
"""用 whisper 的转写时间戳，把整条配音对齐到幕。

为什么要有这一步：
    分段合成会让语速漂移（实测 7 段从 4.76 到 6.73 字/秒，差 1.41 倍，
    听感就是「一会快一会慢」）。改成整条一次合成后，语速唯一，
    但每句落在什么时间只能靠转写拿 —— 幕切换必须跟着语音走，
    不能按字数估。

用法：
    ./align.py            # 读 speak.json 写 timeline.json
"""
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent

# 每幕的识别关键词（whisper 会把「五百七十六」写成「576」，所以多给几个候选）
# 画面 10 幕 vs 配音 9 段：不是一一对应。
# s2 是 s1 内部的切分（前半抛问题，后半讲痛点），所以按段1 的字数比例算。
# 其余按语义对齐 —— 之前按序号硬对，结果「坦白」那幕配的是「仓库在我主页」，
# 错位整整一幕（实测 85s 时画面还在说芯片空洞，配音已经在讲收尾）。
CUES = [
    ("s1", ["国产电视", "开机那三十秒", "三十秒广告"]),
    ("s3", ["净屏", "CleanYourTV 中文版", "中文版"]),
    ("s4", ["官方版要求", "要求 Android", "八点零", "八点〇"]),
    ("s5", ["照片能当桌面", "而且是动的", "照片能"]),
    ("s6", ["卡片可以调成半透明", "半透明"]),
    ("s7", ["应用列表按", "使用频率", "使用频率排"]),
    ("s8", ["整包", "五百七十六", "576"]),
    ("s9", ["说个实在的", "实在的"]),
    ("s10", ["仓库在我主页", "打包好"]),
]
# s2 在段1 里的字数位置：「国产电视开机那三十秒广告，你每次真的看完了吗？」= 前 24 字
S2_SPLIT = 24 / 32.0


def norm(s):
    return s.replace(" ", "").replace("，", "").replace("。", "").replace("、", "").lower()


def main():
    jf = HERE / "speak.json"
    if not jf.exists():
        print("缺 speak.json：先跑 whisper speak.mp3 --model small --language zh "
              "--output_format json --output_dir .", file=sys.stderr)
        return 2
    segs = json.loads(jf.read_text(encoding="utf-8")).get("segments") or []
    if not segs:
        print("speak.json 里没有 segments", file=sys.stderr)
        return 2

    total = segs[-1]["end"]
    starts, used = {}, -1
    for name, cues in CUES:
        hit = None
        for i, s in enumerate(segs):
            if i <= used:
                continue
            t = norm(s["text"])
            if any(norm(c) in t for c in cues):
                hit = (i, s)
                break
        if not hit:
            print("  ✗ %s 没匹配到（关键词 %s）" % (name, cues[:2]), file=sys.stderr)
            return 3
        used, seg = hit
        starts[name] = round(seg["start"], 2)

    # 幕1 从 0 开始；s2 按段1 的字数比例切
    starts["s1"] = 0.0
    # s2 的起点找「关不掉」那句话的真实起点 —— 按字数比例切出来只有 1.6s，
    # 钩子幕会一闪而过（实测）。
    starts["s2"] = None
    for sg in segs:
        t2 = norm(sg["text"])
        if "关不掉" in t2 or "删不掉" in t2:
            starts["s2"] = round(sg["start"], 2)
            break
    if starts["s2"] is None:
        seg1_end = None
        for sg in segs:
            if any(norm(c) in norm(sg["text"]) for c in CUES[0][1]):
                seg1_end = sg["end"]
                break
        starts["s2"] = round((seg1_end or 6.0) * 0.72, 2)

    # 末尾留 1.6s 收口（结尾降速是转化率更高的一种收法）
    end = round(total + 1.6, 2)

    # 幕间时长
    order = ["s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10"]
    out = {"duration": end, "audio_total": round(total, 2), "starts": starts,
           "spans": {}}
    for i, k in enumerate(order):
        s = starts[k]
        e = starts[order[i + 1]] if i + 1 < len(order) else end
        out["spans"][k] = [s, round(e, 2)]

    (HERE / "timeline.json").write_text(
        json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")

    # 写回 index.html：时间轴只有一处真相，不手抄
    html = HERE / "index.html"
    src = html.read_text(encoding="utf-8")
    lines = ["const DUR = %.2f;" % end,
             "const SC = {"]
    keys = list(order)
    for i, k in enumerate(keys):
        sp = out["spans"][k]
        tail = "" if i == len(keys) - 1 else ","
        lines.append("  %s:[%.2f,%.2f]%s" % (k, sp[0], sp[1], tail))
    lines.append("};")
    block = "// <TIMELINE>\n" + "\n".join(lines) + "\n// </TIMELINE>"
    import re as _re
    src2 = _re.sub(r"// <TIMELINE>.*?// </TIMELINE>", block, src, flags=_re.S)
    if src2 != src:
        html.write_text(src2, encoding="utf-8")
        print("  时间轴已写入 index.html")
    else:
        print("  ! index.html 的 <TIMELINE> 块没找到，时间轴未写入", file=sys.stderr)

    print("  配音总长 %.2fs，成片 %.2fs" % (total, end))
    print("  幕   起      止     时长")
    for k in order:
        s, e = out["spans"][k]
        print("  %-4s %6.2f  %6.2f  %5.2f" % (k, s, e, e - s))
    print("\n  → timeline.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
