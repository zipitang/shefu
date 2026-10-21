# -*- coding: utf-8 -*-
"""
《摄伏》资源管线
--------------------------------------------------
把 1.3GB 的原始 PNG 立绘批量压缩为游戏用卡面（WebP），
并按【天/地/人/道具/角色】归档，同时产出 asset_manifest.json。

用法：
    python build_assets.py
"""
import os
import json
import hashlib
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

SRC = r"D:/mycp/Edgedownload/shefu"
PROJ = r"D:/mycp/Edgedownload/shefu/SheFu"

# 卡面尺寸（9:16 竖版，与原图一致）
CARD_W, CARD_H = 540, 960
THUMB_W, THUMB_H = 180, 320
QUALITY = 80

# 顶层目录 -> 资源大类 key
TOP = {
    "天": "tian",
    "地": "di",
    "人": "ren",
    "道具": "item",
    "角色": "chara",
}


def slug_index():
    """全局递增序号，保证 ASCII 文件名稳定。"""
    return {}


def walk_group(root, top_key):
    """返回 [(rel_dir_parts, filename_stem, abs_path)]"""
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for fn in sorted(filenames):
            if not fn.lower().endswith(".png"):
                continue
            rel = os.path.relpath(dirpath, root)
            parts = [] if rel == "." else rel.split(os.sep)
            out.append((parts, os.path.splitext(fn)[0], os.path.join(dirpath, fn)))
    return out


def convert(src, dst_webp, dst_thumb):
    im = Image.open(src)
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        bg = Image.new("RGB", im.size, (14, 12, 20))
        bg.paste(im, mask=im.split()[-1])
        im = bg
    else:
        im = im.convert("RGB")

    # 按短边裁剪到 9:16 再缩放，避免拉伸变形
    w, h = im.size
    target_ratio = CARD_W / CARD_H
    ratio = w / h
    if ratio > target_ratio:      # 太宽 -> 裁左右
        nw = int(h * target_ratio)
        left = (w - nw) // 2
        im = im.crop((left, 0, left + nw, h))
    elif ratio < target_ratio:    # 太高 -> 裁上下（保头留上 1/3）
        nh = int(w / target_ratio)
        top = int((h - nh) * 0.15)
        im = im.crop((0, top, w, top + nh))

    card = im.resize((CARD_W, CARD_H), Image.LANCZOS)
    card.save(dst_webp, "WEBP", quality=QUALITY, method=5)

    thumb = im.resize((THUMB_W, THUMB_H), Image.LANCZOS)
    thumb.save(dst_thumb, "WEBP", quality=72, method=5)


def main():
    manifest = []
    file_counters = {}   # 文件名：大类内全局递增，避免跨组覆盖
    id_counters = {}     # 卡牌 id：大类/分组内递增，保证 id 语义稳定
    total_src = 0
    total_dst = 0

    for top_cn, top_key in TOP.items():
        root = os.path.join(SRC, top_cn)
        if not os.path.isdir(root):
            continue
        entries = walk_group(root, top_key)
        for parts, stem, apath in entries:
            group = "_".join(parts) if parts else "root"
            fidx = file_counters.get(top_key, 0)
            file_counters[top_key] = fidx + 1
            gkey = f"{top_key}/{group}"
            iidx = id_counters.get(gkey, 0)
            id_counters[gkey] = iidx + 1

            out_dir = os.path.join(PROJ, "assets", top_key)
            out_name = f"{fidx:03d}.webp"
            out_thumb = f"{fidx:03d}_t.webp"
            dst = os.path.join(out_dir, out_name)
            dst_t = os.path.join(out_dir, out_thumb)
            os.makedirs(out_dir, exist_ok=True)

            if not os.path.exists(dst):
                try:
                    convert(apath, dst, dst_t)
                except Exception as e:
                    print(f"[FAIL] {apath}: {e}")
                    continue

            card_id = f"{top_key}_{group}_{iidx:03d}"
            ssize = os.path.getsize(apath)
            dsize = os.path.getsize(dst) if os.path.exists(dst) else 0
            total_src += ssize
            total_dst += dsize

            manifest.append({
                "id": card_id,
                "name": stem,
                "top": top_cn,
                "topKey": top_key,
                "group": group,
                "path": parts,
                "art": f"res://assets/{top_key}/{out_name}",
                "thumb": f"res://assets/{top_key}/{out_thumb}",
            })

    with open(os.path.join(PROJ, "data", "asset_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)

    # 完整性校验：art 路径必须唯一，否则不同名的卡会共用同一张图
    seen = {}
    dup = 0
    for m in manifest:
        if m["art"] in seen:
            dup += 1
            print(f"[DUP] {m['art']}: {seen[m['art']]} / {m['name']}")
        seen[m["art"]] = m["name"]
    if dup:
        raise SystemExit(f"[FATAL] {dup} 个 art 路径冲突")
    missing = [m for m in manifest
               if not os.path.exists(os.path.join(PROJ, m["art"].replace("res://", "").replace("/", os.sep)))]
    if missing:
        for m in missing[:10]:
            print(f"[MISSING] {m['name']} -> {m['art']}")
        raise SystemExit(f"[FATAL] {len(missing)} 个 art 文件不存在")

    print(f"[OK] {len(manifest)} cards (无冲突)")
    print(f"[SIZE] src {total_src/1048576:.1f}MB -> dst {total_dst/1048576:.1f}MB "
          f"({100*total_dst/max(total_src,1):.1f}%)")

    # 分组统计
    stats = {}
    for m in manifest:
        k = f"{m['top']}/{m['group']}"
        stats[k] = stats.get(k, 0) + 1
    for k in sorted(stats):
        print(f"  {k}: {stats[k]}")


if __name__ == "__main__":
    main()
