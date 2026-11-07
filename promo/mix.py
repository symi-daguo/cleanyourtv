#!/usr/bin/env python3
"""把整条配音混进无声片。

为什么整条：分段合成会让语速漂移（实测 7 段 4.76~6.73 字/秒，差 1.41 倍，
听感就是「一会快一会慢」）。改成一次合成后语速唯一，混音也就不需要
逐段 adelay 拼接 —— 直接把 speak.mp3 从 0 铺上去。

用法：
    ./mix.py
"""
import argparse
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", default="clean-your-tv-zh-silent.mp4")
    ap.add_argument("--audio", default="speak.mp3")
    ap.add_argument("--out", default="净屏-CleanYourTV-中文版.mp4")
    ap.add_argument("--dur", default="", help="成片时长，空 = 读 timeline.json")
    a = ap.parse_args()
    if not a.dur:
        import json as _json
        tl = HERE / "timeline.json"
        a.dur = str(_json.loads(tl.read_text(encoding="utf-8"))["duration"]) if tl.exists() else "86"

    video, audio = HERE / a.video, HERE / a.audio
    for f in (video, audio):
        if not f.exists():
            print("缺文件：%s" % f, file=sys.stderr)
            return 2

    # apad 补静音到整片长度，否则 -shortest 会截到最后一句话结束
    fc = ("[1:a]aresample=48000,aformat=channel_layouts=mono,"
          "volume=1.0,apad=whole_dur=%s,alimiter=limit=0.95[out]" % a.dur)
    out = HERE / a.out
    cmd = ["ffmpeg", "-y", "-v", "error", "-i", str(video), "-i", str(audio),
           "-filter_complex", fc, "-map", "0:v", "-map", "[out]",
           "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
           "-shortest", "-movflags", "+faststart", str(out)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print("ffmpeg 失败：\n" + r.stderr[-700:], file=sys.stderr)
        return 3

    def probe(args):
        return subprocess.run(["ffprobe", "-v", "error"] + args,
                              capture_output=True, text=True).stdout.strip()
    vd = probe(["-select_streams", "v:0", "-show_entries", "stream=duration",
                "-of", "csv=p=0", str(out)])
    ad = probe(["-select_streams", "a:0", "-show_entries", "stream=duration",
                "-of", "csv=p=0", str(out)])
    print("✅ %s  %.1f MB  视频 %ss  音频 %ss"
          % (out.name, out.stat().st_size / 1048576, vd, ad))
    return 0


if __name__ == "__main__":
    sys.exit(main())
