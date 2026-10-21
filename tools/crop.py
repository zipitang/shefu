"""临时截图裁剪工具：crop.py <src> <dst> x0 y0 x1 y1 [scale]

用于把 1920x1061 截图里的局部放大目检（大本营 / 右栏 / 弹窗）。
"""
import sys
from PIL import Image

def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    x0, y0, x1, y1 = (int(v) for v in sys.argv[3:7])
    scale = float(sys.argv[7]) if len(sys.argv) > 7 else 1.0
    im = Image.open(src).convert("RGB")
    box = im.crop((x0, y0, x1, y1))
    if scale != 1.0:
        box = box.resize((int(box.width * scale), int(box.height * scale)), Image.LANCZOS)
    box.save(dst)
    print(f"[CROP] {src} im={im.size} -> {dst} {box.size}")

if __name__ == "__main__":
    main()
