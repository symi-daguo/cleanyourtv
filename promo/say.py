#!/usr/bin/env python3
"""把 speak.txt 整条合成 亖米19 的一次性配音。

为什么必须整条：分段合成会让语速漂移（实测 7 段 4.76~6.73 字/秒，差 1.41 倍），
听感就是「一会快一会慢」。MiniMax 的 t2a 不保证跨请求一致。

用法：
    ./say.py
"""
import json
import pathlib
import sys
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
API = "https://api.minimaxi.com/v1/t2a_v2"
MODEL = "speech-2.8-hd"
VOICE = "voice19_2026"
SPEED = 1.05

KEYS = [
    pathlib.Path.home() / ".minimax" / "voice-keys" / "minimax-plan.key",
    pathlib.Path.home() / ".minimax" / "voice-keys" / "minimax-payg.key",
]


def main():
    key = None
    for p in KEYS:
        if p.exists():
            key = p.read_text(encoding="utf-8").strip()
            break
    if not key:
        print("找不到 MiniMax 密钥", file=sys.stderr)
        return 2

    text = (HERE / "speak.txt").read_text(encoding="utf-8").strip()
    if not text:
        print("speak.txt 是空的", file=sys.stderr)
        return 2

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
    with urllib.request.urlopen(req, timeout=180) as r:
        js = json.loads(r.read().decode())
    br = js.get("base_resp") or {}
    if br.get("status_code"):
        print("合成失败 %s %s" % (br.get("status_code"), br.get("status_msg")),
              file=sys.stderr)
        return 3

    audio = (js.get("data") or {}).get("audio") or ""
    out = HERE / "speak.mp3"
    if audio.startswith("http"):
        urllib.request.urlretrieve(audio, str(out))
    else:
        out.write_bytes(bytes.fromhex(audio))

    ms = (js.get("extra_info") or {}).get("audio_length") or 0
    sec = ms / 1000
    print("  ✅ speak.mp3  %.2fs  %d KB  语速 %.2f 字/秒（整条唯一）"
          % (sec, out.stat().st_size // 1024, len(text) / sec if sec else 0))
    print("  下一步：whisper speak.mp3 --model small --language zh "
          "--output_format json --output_dir . --fp16 False")
    return 0


if __name__ == "__main__":
    sys.exit(main())
