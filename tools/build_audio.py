# -*- coding: utf-8 -*-
"""
《摄伏》音效生成器
--------------------------------------------------
用纯 Python 合成一组原创音效（无版权风险），输出到 assets/audio/*.wav。

设计原则：
  · 每个音效 0.12 ~ 0.9 秒，短促不拖沓；
  · 起音用噪声爆点 / 快速扫频制造「打击感」，尾部用指数衰减避免截断声；
  · 攻击/受击走低频冲击，治疗/护盾/祈福走明亮泛音，鬼怪走失谐与颤音。

运行：
  python tools/build_audio.py
"""
import math
import os
import random
import struct
import wave

SR = 22050
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(BASE, "assets", "audio")

rnd = random.Random(20261007)


# ------------------------------------------------------------------ 基础工具
def blank(dur):
    return [0.0] * int(SR * dur)


def add(buf, i, v):
    if 0 <= i < len(buf):
        buf[i] += v


def exp_env(t, dur, attack=0.005, decay=6.0):
    """起音 + 指数衰减包络"""
    if t < attack:
        return t / max(attack, 1e-6)
    k = (t - attack) / max(dur - attack, 1e-6)
    return math.exp(-decay * k)


def sine(buf, f0, f1=None, dur=None, gain=0.5, decay=6.0, attack=0.005,
         detune=0.0, vibrato=0.0):
    dur = dur if dur is not None else len(buf) / SR
    f1 = f0 if f1 is None else f1
    n = min(len(buf), int(SR * dur))
    phase = 0.0
    for i in range(n):
        t = i / SR
        k = t / max(dur, 1e-6)
        f = f0 + (f1 - f0) * k
        if vibrato:
            f *= 1.0 + vibrato * math.sin(2 * math.pi * 5.5 * t)
        phase += 2 * math.pi * f / SR
        v = math.sin(phase)
        if detune:
            v = 0.6 * v + 0.4 * math.sin(phase * (1.0 + detune))
        add(buf, i, v * gain * exp_env(t, dur, attack, decay))


def noise(buf, dur=None, gain=0.4, decay=10.0, attack=0.001, lowpass=0.5):
    dur = dur if dur is not None else len(buf) / SR
    n = min(len(buf), int(SR * dur))
    prev = 0.0
    for i in range(n):
        t = i / SR
        s = rnd.uniform(-1.0, 1.0)
        prev = prev + (s - prev) * lowpass          # 一阶低通，去掉刺耳的高频
        add(buf, i, prev * gain * exp_env(t, dur, attack, decay))


def click(buf, at, gain=0.5, decay=40.0):
    """瞬时爆点（打击/落地的『咔』）"""
    n = min(len(buf) - int(at * SR), int(SR * 0.03))
    for i in range(max(0, n)):
        t = i / SR
        add(buf, int(at * SR) + i, rnd.uniform(-1, 1) * gain * math.exp(-decay * t))


def tone_stack(buf, freqs, dur=None, gain=0.3, decay=5.0, attack=0.004, detune=0.004):
    for f in freqs:
        sine(buf, f, None, dur, gain / len(freqs), decay, attack, detune)


def normalize(buf, peak=0.86):
    m = max((abs(v) for v in buf), default=0.0)
    if m < 1e-6:
        return buf
    k = peak / m
    return [v * k for v in buf]


def fade_out(buf, ms=12):
    n = min(len(buf), int(SR * ms / 1000.0))
    for i in range(n):
        buf[len(buf) - n + i] *= 1.0 - i / max(n, 1)


def save(name, buf):
    os.makedirs(OUT, exist_ok=True)
    buf = normalize(buf)
    fade_out(buf, 14)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32000)) for v in buf)
        w.writeframes(frames)
    return path


# ------------------------------------------------------------------ 各音效配方
def s_draw():
    b = blank(0.22)
    noise(b, 0.16, 0.35, 12.0, 0.004, 0.9)
    sine(b, 3000, 7200, 0.14, 0.10, 14.0, 0.003)
    return b


def s_play():
    """上场：风声 + 上升和弦"""
    b = blank(0.5)
    noise(b, 0.30, 0.30, 9.0, 0.006, 0.55)
    sine(b, 260, 620, 0.42, 0.26, 4.5, 0.02)
    tone_stack(b, [523, 659, 784], 0.44, 0.28, 5.0, 0.02)
    return b


def s_attack():
    b = blank(0.28)
    noise(b, 0.12, 0.55, 26.0, 0.001, 1.0)
    sine(b, 1800, 260, 0.2, 0.22, 12.0, 0.001)
    return b


def s_hit():
    b = blank(0.3)
    click(b, 0.0, 0.7, 34.0)
    sine(b, 150, 48, 0.26, 0.5, 9.0, 0.001)
    noise(b, 0.16, 0.30, 16.0, 0.0, 0.35)
    return b


def s_heal():
    b = blank(0.7)
    tone_stack(b, [392, 523, 659, 784], 0.62, 0.30, 4.0, 0.05)
    sine(b, 1046, 1568, 0.5, 0.14, 5.0, 0.06)
    return b


def s_shield():
    b = blank(0.55)
    tone_stack(b, [440, 880, 1320, 1760], 0.5, 0.24, 6.5, 0.004)
    click(b, 0.0, 0.28, 60.0)
    return b


def s_dice():
    """骰子：三下木质撞击 + 尾滚"""
    b = blank(0.72)
    for k, at in enumerate([0.0, 0.10, 0.19, 0.30]):
        click(b, at, 0.55 - k * 0.07, 55.0)
        sine(b, 900 - k * 90, 420, 0.06, 0.18, 26.0, 0.001)
    noise(b, 0.30, 0.16, 9.0, 0.30, 0.6)
    return b


def s_coin():
    b = blank(0.42)
    for at in [0.0, 0.07, 0.15]:
        click(b, at, 0.35, 70.0)
    tone_stack(b, [1568, 2093, 2637], 0.38, 0.30, 8.0, 0.002)
    return b


def s_purge():
    """钉死 / 镇压：低沉下坠"""
    b = blank(0.62)
    sine(b, 420, 90, 0.55, 0.42, 5.0, 0.004)
    noise(b, 0.36, 0.34, 8.0, 0.002, 0.3)
    click(b, 0.0, 0.5, 30.0)
    return b


def s_fire():
    b = blank(0.6)
    noise(b, 0.5, 0.5, 5.0, 0.01, 0.28)
    sine(b, 90, 220, 0.45, 0.24, 5.0, 0.02)
    return b


def s_bolt():
    b = blank(0.45)
    click(b, 0.0, 0.6, 26.0)
    noise(b, 0.34, 0.42, 6.0, 0.0, 1.0)
    sine(b, 2400, 300, 0.3, 0.26, 10.0, 0.001)
    return b


def s_freeze():
    b = blank(0.6)
    tone_stack(b, [1175, 1568, 1976, 2349], 0.55, 0.22, 6.0, 0.006)
    sine(b, 392, 1568, 0.5, 0.16, 5.0, 0.01)
    return b


def s_wind():
    b = blank(0.62)
    noise(b, 0.55, 0.5, 3.5, 0.09, 0.22)
    return b


def s_moon():
    b = blank(0.85)
    sine(b, 523, 392, 0.8, 0.24, 3.0, 0.15, detune=0.006, vibrato=0.004)
    tone_stack(b, [659, 784], 0.7, 0.18, 3.5, 0.2)
    return b


def s_soul():
    """鬼魅：失谐 + 颤音"""
    b = blank(0.8)
    sine(b, 300, 210, 0.75, 0.26, 3.2, 0.06, detune=0.02, vibrato=0.03)
    sine(b, 452, 318, 0.7, 0.16, 3.5, 0.1, detune=0.03, vibrato=0.02)
    return b


def s_poison():
    b = blank(0.6)
    for k in range(5):
        sine(blank(0.001), 0, 0, 0.001, 0)
    for k, at in enumerate([0.0, 0.11, 0.22, 0.33]):
        seg = blank(0.16)
        sine(seg, 180 + k * 40, 90 + k * 30, 0.14, 0.30, 8.0, 0.005)
        for i, v in enumerate(seg):
            add(b, int(at * SR) + i, v)
    noise(b, 0.4, 0.14, 6.0, 0.05, 0.25)
    return b


def s_revive():
    b = blank(0.9)
    notes = [262, 330, 392, 523, 659, 784]
    for k, f in enumerate(notes):
        seg = blank(0.5)
        sine(seg, f, f * 1.01, 0.45, 0.26, 5.0, 0.01)
        for i, v in enumerate(seg):
            add(b, int(k * 0.09 * SR) + i, v)
    return b


def s_seal():
    b = blank(0.4)
    click(b, 0.0, 0.45, 40.0)
    sine(b, 240, 120, 0.34, 0.34, 9.0, 0.002)
    noise(b, 0.2, 0.22, 14.0, 0.0, 0.3)
    return b


def s_quake():
    b = blank(0.75)
    sine(b, 70, 34, 0.7, 0.5, 4.0, 0.02)
    noise(b, 0.6, 0.38, 4.0, 0.01, 0.18)
    click(b, 0.0, 0.4, 22.0)
    return b


def s_smash():
    b = blank(0.5)
    click(b, 0.0, 0.8, 30.0)
    sine(b, 220, 60, 0.44, 0.5, 8.0, 0.001)
    noise(b, 0.26, 0.36, 12.0, 0.0, 0.4)
    return b


def s_chain():
    b = blank(0.55)
    for k in range(7):
        click(b, k * 0.055, 0.30, 60.0)
        tone_stack(b if k == 0 else b, [1200 + k * 120], 0.1, 0.05, 20.0, 0.001)
    noise(b, 0.4, 0.18, 7.0, 0.02, 0.7)
    return b


def s_clash():
    b = blank(0.5)
    for f in [1318, 1568, 1976, 2637]:
        sine(b, f, f * 0.98, 0.42, 0.16, 9.0, 0.002)
    click(b, 0.0, 0.55, 36.0)
    noise(b, 0.2, 0.24, 16.0, 0.0, 0.9)
    return b


def s_arrow():
    b = blank(0.35)
    sine(b, 2400, 700, 0.3, 0.3, 12.0, 0.001)
    noise(b, 0.24, 0.34, 14.0, 0.0, 0.95)
    click(b, 0.24, 0.4, 46.0)
    return b


def s_roar():
    b = blank(0.8)
    sine(b, 130, 82, 0.75, 0.42, 3.4, 0.03, detune=0.01, vibrato=0.012)
    sine(b, 196, 124, 0.7, 0.22, 3.8, 0.05, detune=0.02)
    noise(b, 0.6, 0.30, 3.2, 0.02, 0.16)
    return b


def s_summon():
    b = blank(0.75)
    noise(b, 0.3, 0.26, 9.0, 0.004, 0.6)
    tone_stack(b, [349, 440, 523, 698], 0.68, 0.28, 4.0, 0.10)
    return b


def s_buff():
    b = blank(0.6)
    tone_stack(b, [523, 698, 880, 1175], 0.55, 0.26, 5.0, 0.012)
    return b


def s_slash():
    b = blank(0.26)
    noise(b, 0.1, 0.5, 30.0, 0.0, 1.0)
    sine(b, 3200, 900, 0.14, 0.20, 18.0, 0.001)
    return b


def s_ui_click():
    b = blank(0.1)
    click(b, 0.0, 0.35, 70.0)
    sine(b, 1400, 900, 0.08, 0.14, 30.0, 0.001)
    return b


def s_synth():
    """合成：三重上升 + 金色轰鸣"""
    b = blank(0.95)
    for k, f in enumerate([330, 440, 554, 659, 880]):
        seg = blank(0.6)
        sine(seg, f, f * 1.5, 0.55, 0.24, 4.0, 0.008)
        for i, v in enumerate(seg):
            add(b, int(k * 0.07 * SR) + i, v)
    sine(b, 110, 220, 0.9, 0.3, 2.6, 0.05)
    return b


def s_turn():
    b = blank(0.5)
    tone_stack(b, [523, 784], 0.45, 0.26, 5.0, 0.02)
    sine(b, 1046, 1046, 0.3, 0.12, 7.0, 0.03)
    return b


def s_win():
    b = blank(1.4)
    for k, f in enumerate([523, 659, 784, 1046, 1318]):
        seg = blank(1.0)
        tone_stack(seg, [f, f * 1.5], 0.95, 0.34, 3.0, 0.02)
        for i, v in enumerate(seg):
            add(b, int(k * 0.14 * SR) + i, v)
    return b


def s_lose():
    b = blank(1.2)
    for k, f in enumerate([392, 330, 262, 196]):
        seg = blank(0.9)
        sine(seg, f, f * 0.98, 0.85, 0.34, 2.8, 0.03, detune=0.006)
        for i, v in enumerate(seg):
            add(b, int(k * 0.16 * SR) + i, v)
    return b


SOUNDS = {
    "draw": s_draw, "play": s_play, "attack": s_attack, "hit": s_hit,
    "heal": s_heal, "shield": s_shield, "dice": s_dice, "coin": s_coin,
    "purge": s_purge, "fire": s_fire, "bolt": s_bolt, "freeze": s_freeze,
    "wind": s_wind, "moon": s_moon, "soul": s_soul, "poison": s_poison,
    "revive": s_revive, "seal": s_seal, "quake": s_quake, "smash": s_smash,
    "chain": s_chain, "clash": s_clash, "arrow": s_arrow, "roar": s_roar,
    "summon": s_summon, "buff": s_buff, "slash": s_slash,
    "ui_click": s_ui_click, "synth": s_synth, "turn": s_turn,
    "win": s_win, "lose": s_lose,
}


def main():
    total = 0
    for name, fn in SOUNDS.items():
        p = save(name, fn())
        total += 1
    print("[audio] 生成 %d 个音效 -> %s" % (total, OUT))
    for name in SOUNDS:
        print("   %s.wav" % name)


if __name__ == "__main__":
    main()
