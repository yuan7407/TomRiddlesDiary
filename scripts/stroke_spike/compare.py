#!/usr/bin/env python3
"""Task 1 笔画方案对比实验（spike）。

同一素材，两条源各跑一遍，都套同一个 humanizer（压感近似/速度/抖动），
输出「逐笔生长」的动画 SVG，肉眼比较手绘感：

  源①「直接 SVG」   : input/<name>.svg  → 解析路径 → 有序笔画
  源②「生成图抽骨架」: input/<name>.png  → Zhang-Suen 抽骨架 → 理笔顺

这是 Python 探针，不是最终实现。最终 StrokeEngine 在 App target 内用 Swift 重写。
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
    from skimage.morphology import skeletonize
except ImportError as e:  # 暴露问题而非静默
    sys.exit(f"缺少依赖：{e}. 先 `pip install -r requirements.txt`（并激活 venv）。")

HERE = Path(__file__).resolve().parent
IN_DIR = HERE / "input"
OUT_DIR = HERE / "out"
PAPER = "#f5f1e8"   # 暖色纸底
INK = "#2b2b2b"


# ----------------------------- 源②：PNG → 抽骨架 → 笔画 -----------------------------
def load_ink_mask(png_path: Path):
    img = Image.open(png_path).convert("L")
    w, h = img.size
    arr = np.asarray(img)
    return (arr < 128), (w, h)  # 暗像素=墨


def _neighbors(p, pixels):
    x, y = p
    out = []
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            q = (x + dx, y + dy)
            if q in pixels:
                out.append(q)
    return out


def skeleton_to_strokes(mask):
    """把单像素骨架走成有序折线（简化版 StrokeTracer）。"""
    skel = skeletonize(mask)
    ys, xs = np.where(skel)
    pixels = set(zip(xs.tolist(), ys.tolist()))
    if not pixels:
        return []
    deg = {p: len(_neighbors(p, pixels)) for p in pixels}
    seen = set()

    def edge(a, b):
        return frozenset((a, b))

    # 先从端点出发，再从交叉点，最后兜底剩余像素
    starts = ([p for p in pixels if deg[p] == 1]
              + [p for p in pixels if deg[p] >= 3]
              + list(pixels))
    strokes = []
    for s in starts:
        for nb in _neighbors(s, pixels):
            if edge(s, nb) in seen:
                continue
            path = [s]
            prev, cur = s, nb
            seen.add(edge(prev, cur))
            path.append(cur)
            while deg.get(cur, 0) == 2:
                nxt = [q for q in _neighbors(cur, pixels)
                       if q != prev and edge(cur, q) not in seen]
                if not nxt:
                    break
                nn = nxt[0]
                seen.add(edge(cur, nn))
                path.append(nn)
                prev, cur = cur, nn
            if len(path) >= 2:
                strokes.append([(float(x), float(y)) for x, y in path])
    return strokes


# ----------------------------- 源①：SVG → 笔画 -----------------------------
def svg_to_strokes(svg_path: Path):
    try:
        from svgpathtools import svg2paths
    except ImportError as e:
        sys.exit(f"缺少 svgpathtools：{e}")
    paths, _ = svg2paths(str(svg_path))
    strokes = []
    for path in paths:
        if len(path) == 0:
            continue
        length = path.length(error=1e-3)
        n = max(8, int(length * 0.25))
        pts = []
        for i in range(n + 1):
            z = path.point(i / n)
            pts.append((z.real, z.imag))
        strokes.append(pts)
    return strokes


# ----------------------------- 共享 humanizer -----------------------------
def _resample(arr, step=2.0):
    d = np.sqrt((np.diff(arr, axis=0) ** 2).sum(1))
    s = np.concatenate([[0.0], np.cumsum(d)])
    total = float(s[-1])
    if total == 0:
        return arr
    n = max(2, int(total / step))
    si = np.linspace(0, total, n)
    x = np.interp(si, s, arr[:, 0])
    y = np.interp(si, s, arr[:, 1])
    return np.stack([x, y], axis=1)


def humanize(strokes, jitter=0.6, seed=7):
    """抖动 + 重采样；按长度给每笔一个带速度扰动的时长（逐笔重播用）。"""
    rng = np.random.default_rng(seed)
    out, durs = [], []
    for pts in strokes:
        arr = np.asarray(pts, dtype=float)
        if len(arr) < 2:
            continue
        arr = _resample(arr, step=2.0)
        arr = arr + rng.normal(0.0, jitter, arr.shape)
        seg = float(np.linalg.norm(np.diff(arr, axis=0), axis=1).sum())
        out.append(arr)
        durs.append(max(0.25, seg / 220.0 * (1 + rng.normal(0, 0.1))))
    return out, durs


# ----------------------------- 输出逐笔动画 SVG -----------------------------
def _size_from_strokes(strokes, pad=16):
    allpts = np.concatenate(strokes, axis=0)
    w = float(allpts[:, 0].max()) + pad
    h = float(allpts[:, 1].max()) + pad
    return (int(w), int(h))


def write_animated_svg(strokes, durs, out_path: Path, size):
    w, h = size
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
             f'viewBox="0 0 {w} {h}">',
             f'<rect width="{w}" height="{h}" fill="{PAPER}"/>']
    prev_id = None
    for i, (pts, dur) in enumerate(zip(strokes, durs)):
        d = "M " + " L ".join(f"{x:.1f} {y:.1f}" for x, y in pts)
        length = float(np.linalg.norm(np.diff(pts, axis=0), axis=1).sum()) + 1.0
        aid = f"s{i}"
        begin = "0s" if prev_id is None else f"{prev_id}.end"
        parts.append(
            f'<path id="{aid}" d="{d}" fill="none" stroke="{INK}" stroke-width="2.2" '
            f'stroke-linecap="round" stroke-linejoin="round" '
            f'stroke-dasharray="{length:.1f}" stroke-dashoffset="{length:.1f}">'
            f'<animate attributeName="stroke-dashoffset" from="{length:.1f}" to="0" '
            f'begin="{begin}" dur="{dur:.2f}s" fill="freeze"/></path>')
        prev_id = aid
    parts.append("</svg>")
    out_path.write_text("\n".join(parts), encoding="utf-8")


# ----------------------------- 驱动 -----------------------------
def process_png(png_path: Path):
    mask, size = load_ink_mask(png_path)
    strokes = skeleton_to_strokes(mask)
    strokes, durs = humanize(strokes)
    if not strokes:
        return None
    out = OUT_DIR / f"{png_path.stem}_skeleton.svg"
    write_animated_svg(strokes, durs, out, size)
    return out


def process_svg(svg_path: Path):
    strokes = svg_to_strokes(svg_path)
    strokes, durs = humanize(strokes)
    if not strokes:
        return None
    out = OUT_DIR / f"{svg_path.stem}_svg.svg"
    write_animated_svg(strokes, durs, out, _size_from_strokes(strokes))
    return out


def main():
    ap = argparse.ArgumentParser(description="Task 1 笔画方案对比实验")
    ap.add_argument("--name", help="只处理指定 stem（不含扩展名）")
    args = ap.parse_args()

    OUT_DIR.mkdir(exist_ok=True)
    if not IN_DIR.exists() or not any(IN_DIR.iterdir()):
        sys.exit(f"input/ 为空。把线稿 PNG（源②）或 SVG（源①）放进 {IN_DIR} 再跑。")

    stems = {}
    for f in sorted(IN_DIR.iterdir()):
        if f.suffix.lower() in (".png", ".svg"):
            stems.setdefault(f.stem, []).append(f)

    made = 0
    for stem, files in stems.items():
        if args.name and stem != args.name:
            continue
        for f in files:
            out = process_png(f) if f.suffix.lower() == ".png" else process_svg(f)
            if out:
                print(f"  ✓ {f.name}  →  {out.relative_to(HERE)}")
                made += 1
            else:
                print(f"  ⚠ {f.name}：未提取到笔画（检查是否干净线稿/有效 SVG）")

    if made == 0:
        sys.exit("没有产出。确认 input/ 里有匹配素材，或用 --name 指定。")
    print(f"\n完成：{made} 个动画 SVG 在 out/。浏览器并排打开 *_svg.svg 与 *_skeleton.svg 肉眼选源。")


if __name__ == "__main__":
    main()
