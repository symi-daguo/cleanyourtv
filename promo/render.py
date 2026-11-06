#!/usr/bin/env python3
"""逐帧渲染 promo/index.html → MP4。

页面必须暴露 window.__frame(t)，返回 Promise（幕3b 里要等 video seeked）。

用法：
    ./render.py                  # 全片 60s
    ./render.py --until 6        # 只渲前 6 秒（调试）
    ./render.py --fps 30
"""
import argparse
import asyncio
import os
import pathlib
import subprocess
import sys
import time

from playwright.async_api import async_playwright

HERE = pathlib.Path(__file__).resolve().parent
PAGE = HERE / "index.html"
W, H = 1920, 1080


async def render(fps, until, out, frame_dir):
    frames = pathlib.Path(os.environ.get("PROMO_FRAME_DIR", str(frame_dir)))
    frames.mkdir(parents=True, exist_ok=True)

    total = int(round(until * fps))
    n = 0
    t_start = time.time()
    async with async_playwright() as p:
        br = await p.chromium.launch(channel="chrome")
        pg = await br.new_page(viewport={"width": W, "height": H}, device_scale_factor=1)
        errs = []
        pg.on("pageerror", lambda e: errs.append(str(e)[:100]))
        await pg.goto("file://%s" % PAGE, wait_until="load")
        # 等视频元数据就绪，否则幕3b 的 seek 会失败
        try:
            await pg.wait_for_function(
                "() => { const v = document.getElementById('wall');"
                " return v && v.readyState >= 2; }", timeout=15000)
        except Exception:
            print("  ! 视频元数据未就绪（幕3b 可能黑屏）")
        ok = await pg.evaluate("() => typeof window.__frame === 'function'")
        if not ok:
            print("  ✗ 页面没有 window.__frame", file=sys.stderr)
            return 2

        for i in range(total):
            t = i / fps
            await pg.evaluate("t => window.__frame(t)", t)
            await pg.screenshot(path=str(frames / ("f%05d.jpg" % (n + 1))),
                                type="jpeg", quality=92)
            n += 1
            if n % 120 == 0:
                el = time.time() - t_start
                print("  %d/%d 帧  %.0fs  剩余约 %.0fs"
                      % (n, total, el, el / n * (total - n)))
        await br.close()

    # 帧数变少时清尾部（写盘红线：正常重渲零删除）
    stale = [str(x) for x in frames.glob("f*.jpg")
             if x.stem[1:].isdigit() and int(x.stem[1:]) > n]
    if stale:
        subprocess.run(["/bin/rm", "-f"] + stale, check=False)

    if errs:
        print("  JS 错误 %d: %s" % (len(errs), errs[:3]))

    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["ffmpeg", "-y", "-v", "error", "-framerate", str(fps),
           "-i", str(frames / "f%05d.jpg"),
           "-c:v", "libx264", "-preset", "medium", "-crf", "18",
           "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(out)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print("ffmpeg 失败：", r.stderr[-400:], file=sys.stderr)
        return 3
    print("✅ %s  %.1f MB  %.1fs  %d 帧"
          % (out.name, out.stat().st_size / 1048576, n / fps, n))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fps", type=int, default=24)
    ap.add_argument("--until", type=float, default=88.16)
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    name = a.out or ("clean-your-tv-zh-%ds-silent.mp4" % round(a.until))
    rc = asyncio.run(render(a.fps, a.until, HERE / name, HERE / "frames"))
    sys.exit(rc)


if __name__ == "__main__":
    main()
