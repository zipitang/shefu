# -*- coding: utf-8 -*-
"""
《摄伏》UI / 头像 资源管线
--------------------------------------------------
主管线 build_assets.py 只处理「9:16 卡面」，而本轮新增的三类素材是方形或特殊用途，
硬塞进去会被裁成 9:16（头会被切掉），所以单独一条管线：

  1. 角色/头像/*.png      -> assets/chara_face/NNN.webp   （正方形头像，256²）
  2. pUI/*.png            -> assets/ui/pui_*.webp         （资源 / 行动 / 升级图标）
  3. 道具/金刚钺特效图/*.png -> assets/ui/fx_axe.webp      （金刚钺砸落演出图）
  4. 道具/铜钱剑特效图/辟邪.png -> assets/ui/fx_ward.webp   （辟邪横带）
  5. 角色/对局内/*.png    -> assets/chara_scene/NNN.webp  （大厅预览上层·9:16 透明立绘）
     角色/背景/*.png      -> assets/chara_bg/NNN.webp     （大厅预览下层·9:16 背景）

序号规则：以上全部与 assets/chara/NNN.webp 严格同序（同名单、同排序规则），
这样 characters.json 里的 art=assets/chara/008.webp 就一定对应 chara_face/008.webp。

用法：
    python build_ui_assets.py            # 已存在的文件跳过
    python build_ui_assets.py --force    # 全部重建（改了质量/尺寸时用）
"""
import os
import sys
import struct
import json
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

SRC = r"D:/mycp/Edgedownload/shefu"
PROJ = r"D:/mycp/Edgedownload/shefu/SheFu"
QUALITY = 88

## --force：忽略已存在文件，全部重做
FORCE = "--force" in sys.argv

## 大厅预览窗口内两张图的输出尺寸（9:16）
SCENE_W, SCENE_H = 720, 1280

# pUI 图标：文件名 -> 输出名
PUI = {
    "财": "pui_wealth",
    "法": "pui_fa",
    "源": "pui_yuan",
    "气": "pui_qi",
    "行动": "pui_action",
    "千纸鹤": "pui_crane",
    "升级按钮": "pui_upgrade",
}


def square(im: Image.Image, side: int, keep_alpha: bool = False, trim: bool = False) -> Image.Image:
    """裁到正方形再缩放。
    keep_alpha —— 保留透明通道（pUI 图标是透明底，压到深色底上会变成一块方块）
    trim      —— 先按不透明像素的包围盒裁掉四周空白（2048² 的图标实际只占中间一半，
                 不裁的话放进 24px 的药丸里会小得看不清）
    """
    if im.mode not in ("RGBA", "LA", "P"):
        im = im.convert("RGBA" if keep_alpha else "RGB")
    else:
        im = im.convert("RGBA")

    if trim:
        bbox = im.split()[-1].getbbox()
        if bbox:
            pad = int(max(bbox[2] - bbox[0], bbox[3] - bbox[1]) * 0.06)
            im = im.crop((max(0, bbox[0] - pad), max(0, bbox[1] - pad),
                          min(im.width, bbox[2] + pad), min(im.height, bbox[3] + pad)))
        # 裁完补成正方形（居中），避免缩放时被拉变形
        w, h = im.size
        s = max(w, h)
        canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        canvas.paste(im, ((s - w) // 2, (s - h) // 2))
        im = canvas

    w, h = im.size
    s = min(w, h)
    if keep_alpha:
        left = (w - s) // 2
        top = int((h - s) * 0.35)      # 人像偏上取景，别把头顶裁掉
        if top + s > h:
            top = h - s
        im = im.crop((left, top, left + s, top + s))
    else:
        bg = Image.new("RGB", im.size, (14, 12, 20))
        bg.paste(im, mask=im.split()[-1])
        im = bg
        w, h = im.size
        s = min(w, h)
        left = (w - s) // 2
        top = int((h - s) * 0.35)
        if top + s > h:
            top = h - s
        im = im.crop((left, top, left + s, top + s))
    return im.resize((side, side), Image.LANCZOS)


def dump(src: str, dst: str, side: int, keep_alpha: bool = False, trim: bool = False) -> bool:
    if os.path.exists(dst) and not FORCE:
        return False
    im = Image.open(src)
    out = square(im, side, keep_alpha, trim)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if keep_alpha:
        out.save(dst, "WEBP", quality=QUALITY, method=5, lossless=False)
    else:
        out.convert("RGB").save(dst, "WEBP", quality=QUALITY, method=5)
    return True


def dump_wide(src: str, dst: str, width: int) -> bool:
    """横向素材（如铜钱剑/辟邪）：按不透明像素包围盒裁掉四周透明区，
    保留原始宽高比缩放到目标宽度，保留透明通道。
    【为什么不用 square】铜钱剑内容是一条 ~950×280 的横带，硬压正方形
    要么把剑缩成一小条、要么把剑两头切掉 —— 横向素材必须保比。"""
    if os.path.exists(dst) and not FORCE:
        return False
    im = Image.open(src).convert("RGBA")
    bbox = im.split()[-1].getbbox()
    if bbox:
        pad = int(max(bbox[2] - bbox[0], bbox[3] - bbox[1]) * 0.03)
        im = im.crop((max(0, bbox[0] - pad), max(0, bbox[1] - pad),
                      min(im.width, bbox[2] + pad), min(im.height, bbox[3] + pad)))
    w, h = im.size
    nh = max(1, round(h * width / w))
    im = im.resize((width, nh), Image.LANCZOS)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    im.save(dst, "WEBP", quality=QUALITY, method=5, lossless=False)
    return True


def fit_ratio(src: str, dst: str, max_w: int, max_h: int, keep_alpha: bool) -> bool:
    """按原始宽高比整体缩放到「不超过 max_w×max_h」，绝不裁切、绝不变形。

    【为什么不能用 square()】大厅预览是「背景 + 立绘」两层严格 9:16 叠加，
    任何一层被裁一刀，两层就对不齐（人物的脚会飘在背景上沿）。
    keep_alpha=False 的背景走 RGB 存，文件小一半。"""
    if os.path.exists(dst) and not FORCE:
        return False
    im = Image.open(src).convert("RGBA")
    w, h = im.size
    k = min(max_w / w, max_h / h)
    im = im.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if keep_alpha:
        im.save(dst, "WEBP", quality=QUALITY, method=5, lossless=False)
    else:
        im.convert("RGB").save(dst, "WEBP", quality=QUALITY, method=5)
    return True


def main() -> None:
    made = 0

    # ---------- 1. 头像 ----------
    face_src = os.path.join(SRC, "角色", "头像")
    face_out = os.path.join(PROJ, "assets", "chara_face")
    faces = []
    if os.path.isdir(face_src):
        names = sorted(fn for fn in os.listdir(face_src) if fn.lower().endswith(".png"))
        for i, fn in enumerate(names):
            stem = os.path.splitext(fn)[0]
            p = f"{i:03d}.webp"
            if dump(os.path.join(face_src, fn), os.path.join(face_out, p), 256):
                made += 1
            faces.append({"name": stem, "art": f"res://assets/chara_face/{p}"})
        print(f"[FACE] {len(faces)} 张头像 -> assets/chara_face/")

    # ---------- 2. pUI 图标 ----------
    pui_src = os.path.join(SRC, "pUI")
    ui_out = os.path.join(PROJ, "assets", "ui")
    for cn, outname in PUI.items():
        src = os.path.join(pui_src, cn + ".png")
        if not os.path.exists(src):
            print(f"[SKIP] 缺少 pUI/{cn}.png")
            continue
        if dump(src, os.path.join(ui_out, outname + ".webp"), 256, keep_alpha=True, trim=True):
            made += 1

    # ---------- 3. 金刚钺特效图 ----------
    axe = os.path.join(SRC, "道具", "金刚钺特效图", "金刚钺.png")
    if os.path.exists(axe):
        if dump(axe, os.path.join(ui_out, "fx_axe.webp"), 512, keep_alpha=True, trim=True):
            made += 1
    else:
        print("[SKIP] 缺少 金刚钺特效图/金刚钺.png")

    # ---------- 4. 铜钱剑辟邪特效图（横向） ----------
    ward = os.path.join(SRC, "道具", "铜钱剑特效图", "辟邪.png")
    if os.path.exists(ward):
        if dump_wide(ward, os.path.join(ui_out, "fx_ward.webp"), 512):
            made += 1
    else:
        print("[SKIP] 缺少 铜钱剑特效图/辟邪.png")

    # ---------- 5. 大厅预览两层：对局内立绘（上） + 背景（下） ----------
    # 【为什么严格按 faces 的下标输出】预览用的场景立绘/背景，必须和
    # assets/chara/NNN.webp、assets/chara_face/NNN.webp 是同一个角色 ——
    # 三套图的文件名各不相同（背景还带「背景」后缀，吉马卓玛那张甚至没有后缀），
    # 按文件名排序会各排各的。所以统一「以头像的排序为基准」，用名字去取图。
    scene_src = os.path.join(SRC, "角色", "对局内")
    bg_src = os.path.join(SRC, "角色", "背景")
    scene_out = os.path.join(PROJ, "assets", "chara_scene")
    bg_out = os.path.join(PROJ, "assets", "chara_bg")
    n_scene = n_bg = 0
    for i, e in enumerate(faces):
        nm = e["name"]
        # 上层：透明底立绘
        sp = os.path.join(scene_src, nm + ".png")
        if os.path.exists(sp):
            dst = os.path.join(scene_out, f"{i:03d}.webp")
            if fit_ratio(sp, dst, SCENE_W, SCENE_H, True):
                n_scene += 1
            e["scene"] = f"res://assets/chara_scene/{i:03d}.webp"
        else:
            e["scene"] = ""
            print(f"[SKIP] 缺少 对局内/{nm}.png")
        # 下层：背景（优先 <名>背景.png，退回 <名>.png）
        bp = os.path.join(bg_src, nm + "背景.png")
        if not os.path.exists(bp):
            bp = os.path.join(bg_src, nm + ".png")
        if os.path.exists(bp):
            dst = os.path.join(bg_out, f"{i:03d}.webp")
            if fit_ratio(bp, dst, SCENE_W, SCENE_H, False):
                n_bg += 1
            e["bg"] = f"res://assets/chara_bg/{i:03d}.webp"
        else:
            e["bg"] = ""
            print(f"[SKIP] 缺少 背景/{nm}.png")
    made += n_scene + n_bg
    print(f"[SCENE] {n_scene} 张对局立绘 -> assets/chara_scene/ ；[BG] {n_bg} 张背景 -> assets/chara_bg/")

    # 清单最后统一落盘（face / bg / scene 三件套一次写完）
    with open(os.path.join(PROJ, "data", "face_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(faces, f, ensure_ascii=False, indent=1)

    print(f"[OK] 新生成 {made} 个文件")


if __name__ == "__main__":
    main()
