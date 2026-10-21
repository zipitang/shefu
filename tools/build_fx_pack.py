# -*- coding: utf-8 -*-
"""
《摄伏》技能特效序列帧管线
--------------------------------------------------------------------------
把 D:/BaiduNetdiskDownload/4.116个Q版技能特效序列帧（附带GIF选图用/... 里
选中的 Q 版技能特效序列帧，**横向拼成一条长图**（保留 alpha），写进
SheFu/assets/fx/，并生成 data/fx_manifest.json 供运行期播放。

【为什么拼长条，而不是逐帧拷贝】
  66 组效果、每组 4~30 帧、每帧一个 PNG —— 逐帧拷进去就是 1000+ 个文件，
  光是 .import 就有 1000+ 份，导入/导出/版本管理全都被拖垮。
  拼成一条长图后：一组效果 = 一个 webp + 一行 manifest，
  Godot 侧用 AtlasTexture 每帧改一次 region，零额外解码、零 GC。

【为什么不吃原图尺寸】
  原帧最大 512×340、最长 30 帧，拼起来 7000+ px 宽。桌面 GPU 上限够，
  但为了留余量，超过 MAX_W 的会等比缩一档（只缩尺寸，不裁切）。

【映射原则】
  卡牌技能 fx（CCard.fx_for_type）一共 22 种，每一种挑一组「读得懂」的：
    火 = 燃烧火焰      风 = 起风强化       雷 = 蓝色雷点打击
    冰 = 蓝色冰锥爆炸   治愈 = 恢复回血      护盾 = 透明气功护盾
    还魂 = 十字架复活   毒 = 绿色幽火       魂魄 = 绿色萤火分散
    驱邪 = 绿色闪光暴击 封印 = 金色瞄准     召唤 = 金光翅膀展翅
    增益 = 暴怒动态图标 铜钱 = 金币旋转     斩击 = 绿色剑气斩击
  没有任何一组是「科幻电子」风格 —— 全是 Q 版手绘，和本作调性一致。

用法：
    python tools/build_fx_pack.py
"""
import json
import os

from PIL import Image

SRC = (r"D:/BaiduNetdiskDownload/4.116个Q版技能特效序列帧（附带GIF选图用"
       r"/4.116个Q版技能特效序列帧（附带GIF选图用")
PROJ = r"D:/mycp/Edgedownload/shefu/SheFu"
OUT = os.path.join(PROJ, "assets", "fx")
MANIFEST = os.path.join(PROJ, "data", "fx_manifest.json")

MAX_W = 6144          # 单张长图最大宽度（超过就等比缩）
DEFAULT_DUR = 0.62    # 一组效果的默认播放时长（秒）

# key(fx 名) -> 源目录名
MAP = {
    "slash":  "绿色剑气斩击",
    "smash":  "石破天惊",
    "quake":  "重炮坠击",
    "fire":   "燃烧火焰（动效）",
    "bolt":   "蓝色雷点打击",
    "freeze": "蓝色冰锥爆炸",
    "wind":   "起风强化特效",
    "heal":   "恢复回血",
    "shield": "透明气功护盾",
    "purge":  "绿色闪光暴击",
    "poison": "绿色幽火",
    "soul":   "绿色萤火分散",
    "moon":   "紫色鹰眼动效",
    "revive": "基督十字架复活",
    "summon": "金光翅膀展翅",
    "buff":   "暴怒加强动态图标",
    "seal":   "金色瞄准",
    "coin":   "金币旋转",
    "arrow":  "剑气坠落打击",
    "clash":  "彩色打击",
    "chain":  "紫色能量斩击",
    "draw":   "蓝色能量打击",
    "roar":   "爆炸",
}


def _frames(folder: str) -> list:
    """按文件名尾部数字排序取序列帧（导出工具就是 _0 _1 _2 … 这么命名的）。"""
    fs = [f for f in os.listdir(folder) if f.lower().endswith(".png")]
    def key(fn):
        stem = os.path.splitext(fn)[0]
        tail = stem.rsplit("_", 1)[-1]
        return int(tail) if tail.isdigit() else 0
    return [os.path.join(folder, f) for f in sorted(fs, key=key)]


def _strip(paths: list) -> tuple:
    """把一组帧横向拼成一条长图，返回 (PIL 图, 单帧宽, 单帧高)。"""
    imgs = [Image.open(p).convert("RGBA") for p in paths]
    fw = max(i.width for i in imgs)
    fh = max(i.height for i in imgs)
    total = fw * len(imgs)
    canvas = Image.new("RGBA", (total, fh), (0, 0, 0, 0))
    for k, im in enumerate(imgs):
        # 帧尺寸不一时按底边居中对齐（特效大多是向上生长的）
        x = k * fw + (fw - im.width) // 2
        y = fh - im.height
        canvas.alpha_composite(im, (x, y))
    return canvas, fw, fh


def main() -> None:
    os.makedirs(OUT, exist_ok=True)

    # ---------- 0. 前置校验 ----------
    bad = []
    for key, name in MAP.items():
        p = os.path.join(SRC, name)
        if not os.path.isdir(p):
            bad.append("%s <- %s" % (key, name))
    if bad:
        print("[FAIL] 以下映射的源目录不存在（改过名？）：")
        for b in bad:
            print("   -", b)
        raise SystemExit(1)

    # ---------- 1. 清空旧产物 ----------
    for fn in sorted(os.listdir(OUT)):
        if fn.endswith(".webp") or fn.endswith(".import"):
            os.remove(os.path.join(OUT, fn))

    manifest = {}
    total_bytes = 0
    for key, name in MAP.items():
        paths = _frames(os.path.join(SRC, name))
        if not paths:
            print("[FAIL] %s 没有序列帧" % name)
            raise SystemExit(1)
        canvas, fw, fh = _strip(paths)
        # 过宽就整体缩一档（不裁切）
        if canvas.width > MAX_W:
            k = MAX_W / canvas.width
            canvas = canvas.resize((int(canvas.width * k), max(1, int(canvas.height * k))),
                                   Image.LANCZOS)
            fw = canvas.width // len(paths)
            fh = canvas.height
        dst = os.path.join(OUT, key + ".webp")
        canvas.save(dst, "WEBP", lossless=True, quality=95, method=6)
        total_bytes += os.path.getsize(dst)
        manifest[key] = {
            "file": "res://assets/fx/%s.webp" % key,
            "frames": len(paths),
            "fw": fw,
            "fh": fh,
            "dur": DEFAULT_DUR,
            "src": name,
        }
        print("[FX] %-8s <- %-16s %2d 帧  %dx%d  长图 %dx%d  %.0f KB" % (
            key, name, len(paths), fw, fh, canvas.width, canvas.height,
            os.path.getsize(dst) / 1024))

    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)

    print("[OK] 写入 %d 组特效 -> assets/fx/  合计 %.1f MB" % (
        len(manifest), total_bytes / 1e6))
    print("[OK] manifest -> data/fx_manifest.json")


if __name__ == "__main__":
    main()
