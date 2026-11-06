#!/usr/bin/env python3
"""把 promo 的七段口播合成 亖米19（voice19_2026, speed 1.05），实测每段时长。

时长要和分镜对齐：哪段超了，要么压文案，要么改幕长。
输出 beats/01.mp3 … 07.mp3 + beats.json（含实测时长）。

用法：
    ./tts.py            # 全部合成（已有 mp3 且时长变化不大时跳过）
    ./tts.py --force    # 重合成
"""
import argparse
import json
import pathlib
import subprocess
import sys
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
BEATS = HERE / "beats"
API = "https://api.minimaxi.com/v1/t2a_v2"
MODEL = "speech-2.8-hd"
VOICE = "voice19_2026"
SPEED = 1.05

KEY_CANDIDATES = [
    pathlib.Path.home() / ".minimax" / "voice-keys" / "minimax-plan.key",
    pathlib.Path.home() / ".minimax" / "voice-keys" / "minimax-payg.key",
]

# 与 index.html 的幕时间轴一一对应：(段落名, 分镜秒数, 口播)
LINES = [
    ("01-hook", 6, "国产电视开机那三十秒广告，你每次真的看完了吗？"),
    ("02-what", 11, "CleanYourTV 中文版。把电视自带的臃肿桌面换掉，只留下你自己的应用。四百四十二款机型，七十二个品牌。"),
    ("03-android6", 9.5, "官方要求 Android 八点零，这台海信停在六点零，官方装上去是一片空白。我们把它编进去了，还自带五张背景图。"),
    ("04-wallpaper", 9, "照片能当桌面，而且会动。二十秒一轮缓慢平移，每一圈方向都不一样。"),
    ("05-detail", 10, "卡片能调成半透明，照片从下面透出来；换图是淡入淡出，不是硬切。应用还能按你实际的使用频率排序。"),
    ("06-proof", 13.5, "整包五百七十六 KB。实测二十四兆内存，六十帧只掉一点六个百分点。说个实在的：这台芯片每十几帧会自己停一下，官方版一样。"),
    ("07-end", 6, "仓库在我主页，中文分支，五张背景图已经打包好。"),
]


def find_key():
    for p in KEY_CANDIDATES:
        if p.exists():
            return p.read_text(encoding="utf-8").strip()
    raise SystemExit("找不到 MiniMax 密钥（~/.minimax/voice-keys/）")


def synth(key, text, out):
    payload = {
        "model": MODEL, "text": text, "stream": False,
        "voice_setting": {"voice_id": VOICE, "speed": SPEED, "vol": 1.0, "pitch": 0},
        "audio_setting": {"sample_rate": 32000, "bitrate": 128000,
                          "format": "mp3", "channel": 1},
        "output_format": "url",
    }
    req = urllib.request.Request(
        API, data=json.dumps(payload).encode(),
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=90) as r:
        js = json.loads(r.read().decode())
    br = js.get("base_resp") or {}
    if br.get("status_code"):
        raise RuntimeError("%s %s" % (br.get("status_code"), br.get("status_msg")))
    audio = (js.get("data") or {}).get("audio") or ""
    if audio.startswith("http"):
        urllib.request.urlretrieve(audio, str(out))
    else:
        out.write_bytes(bytes.fromhex(audio))


def dur(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                        "-of", "csv=p=0", str(path)], capture_output=True, text=True)
    return float(r.stdout.strip() or 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    BEATS.mkdir(exist_ok=True)
    key = find_key()

    rows, total, slack = [], 0.0, 0.0
    for name, plan, text in LINES:
        out = BEATS / (name + ".mp3")
        if a.force or not out.exists():
            try:
                synth(key, text, out)
            except Exception as e:
                print("  ✗ %s 合成失败: %s" % (name, e), file=sys.stderr)
                return 2
        d = dur(out)
        total += d
        slack += plan - d
        flag = "超长" if d > plan else ("余  %+.1fs" % (plan - d))
        rows.append({"name": name, "plan": plan, "actual": round(d, 2),
                     "chars": len(text), "audio": out.name})
        print("  %-14s 计划 %2ds  实测 %5.2fs  %s  %d 字" % (name, plan, d, flag, len(text)))

    (BEATS / "beats.json").write_text(
        json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
    print("\n  合计口播 %.1fs / 片长 60s，总余量 %+.1fs" % (total, slack))
    over = [r for r in rows if r["actual"] > r["plan"]]
    if over:
        print("  ⚠ 有 %d 段超长：%s" % (len(over), ", ".join(
            "%s(+%.1fs)" % (r["name"], r["actual"] - r["plan"]) for r in over)))
        return 1
    print("  ✅ 每段都在分镜时长内")
    return 0


if __name__ == "__main__":
    sys.exit(main())
