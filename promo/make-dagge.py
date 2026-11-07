#!/usr/bin/env python3
"""从标准版生成「大锅版」：内容一样，指纹不一样。

用户 2026-11-07 定的规矩：一稿两版，标准版验收通过才出大锅版；
对外发的是原创，不能被平台/agent 判成同一素材重复投递。

**实测出来的三层微调**（只动指纹，不动内容、不动时长）：

    第 1 层 噪点        noise=alls=3                          改每个像素值
    第 2 层 色阶        eq=brightness/contrast/saturation     改直方图
    第 3 层 署名角标    overlay 右下角「大锅」                 改结构

前两层单独用时，dHash/pHash 距离是 **0/64** —— 平台如果拿感知哈希判重，
照样认成同一条。pHash 看的是结构和构图，整体亮度变化它不敏感，
必须加一个真实元素（角标）才动得了。第三层就是为此加的，顺带也是署名。

**为什么不做裁切 / 不改时长**：
    · 裁 4px 再拉回会让内容放大 0.75%，画面里所有元素都位移（对比图一眼看出）
    · atempo 会让 86.04 → 85.36s，幕切换/字幕/配音三者全错位

用法：
    ./make-dagge.py                 # 标准版 → 大锅版
    ./make-dagge.py --verify        # 附时长/帧数/PSNR
"""
import argparse
import hashlib
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE / "净屏-CleanYourTV-中文版.mp4"
DST = HERE / "净屏-CleanYourTV-中文版-大锅.mp4"
WM = HERE / "wm-dagge.png"


def probe(path, entries):
    return subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                           "-show_entries", entries, "-of", "csv=p=0", str(path)],
                          capture_output=True, text=True).stdout.strip()


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify", action="store_true")
    a = ap.parse_args()

    for f, why in ((SRC, "标准版"), (WM, "角标 wm-dagge.png")):
        if not f.exists():
            print("缺%s：%s" % (why, f), file=sys.stderr)
            return 2

    fc = ("[0:v]eq=brightness=0.010:contrast=1.016:saturation=1.05,"
          "noise=alls=3:allf=t+u[v];"
          "[v][1:v]overlay=W-w-64:H-h-64[outv];"
          "[0:a]volume=1.015,aresample=48000[outa]")

    cmd = ["ffmpeg", "-y", "-v", "error", "-i", str(SRC), "-i", str(WM),
           "-filter_complex", fc,
           "-map", "[outv]", "-map", "[outa]",
           "-c:v", "libx264", "-preset", "slow", "-crf", "20",
           "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
           "-metadata", "title=净屏 · CleanYourTV 中文版（大锅）",
           "-metadata", "artist=大锅",
           "-metadata", "comment=CleanYourTV 中文本地分支 · Android 6.0+",
           "-movflags", "+faststart", str(DST)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print("ffmpeg 失败：\n" + r.stderr[-800:], file=sys.stderr)
        return 3

    print("  ✅ %s  %.1f MB" % (DST.name, DST.stat().st_size / 1048576))

    if a.verify:
        print()
        for p, tag in ((SRC, "标准版"), (DST, "大锅版")):
            d = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
                                "format=duration", "-of", "csv=p=0", str(p)],
                               capture_output=True, text=True).stdout.strip()
            print("  %-6s %8.3fs  %s  %s 帧"
                  % (tag, float(d), probe(p, "stream=width,height"),
                     probe(p, "stream=nb_frames")))
        print("\n  MD5  标准版 %s" % md5(SRC)[:16])
        print("  MD5  大锅版 %s" % md5(DST)[:16])

        ps = subprocess.run(["ffmpeg", "-v", "info", "-i", str(DST), "-i", str(SRC),
                             "-lavfi", "psnr", "-f", "null", "-"],
                            capture_output=True, text=True)
        for line in ps.stderr.splitlines():
            if "PSNR" in line and "average" in line:
                print("  画面 PSNR", line.split("average:")[-1].strip())
                break
    return 0


if __name__ == "__main__":
    sys.exit(main())
