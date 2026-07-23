#!/usr/bin/env python3
"""Generate 10 deterministic GPT-authored line-art fixture pairs.

Each motif is emitted twice from the same ordered strokes:
- SVG: direct ordered-vector source.
- PNG: clean black-line raster source for skeletonization.

These are engineering preflight fixtures, not Qwen-Image quality evidence and not a
substitute for the user's emotional Go/Kill review of real model responses.
"""
from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Iterable, Sequence

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
INPUT_DIR = HERE / "input"
SIZE = 640
INK = (24, 24, 24)
BACKGROUND = (255, 255, 255)
LINE_WIDTH = 5
Point = tuple[float, float]
Stroke = list[Point]


def ellipse(cx: float, cy: float, rx: float, ry: float,
            start: float = 0.0, end: float = math.tau, steps: int = 48) -> Stroke:
    return [
        (cx + rx * math.cos(start + (end - start) * i / steps),
         cy + ry * math.sin(start + (end - start) * i / steps))
        for i in range(steps + 1)
    ]


def spiral(cx: float, cy: float, r0: float, r1: float,
           turns: float, steps: int = 100) -> Stroke:
    points = []
    for i in range(steps + 1):
        t = i / steps
        angle = turns * math.tau * t
        radius = r0 + (r1 - r0) * t
        points.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    return points


def wave(y: float, x0: float, x1: float, amplitude: float,
         cycles: float, steps: int = 60) -> Stroke:
    return [
        (x0 + (x1 - x0) * i / steps,
         y + amplitude * math.sin(cycles * math.tau * i / steps))
        for i in range(steps + 1)
    ]


def motif(identifier: str, emotion: str, representation: str,
          prompt: str, strokes: Sequence[Stroke]) -> dict:
    return {
        "id": identifier,
        "emotion": emotion,
        "representation": representation,
        "prompt": prompt,
        "strokes": list(strokes),
    }


def fixtures() -> list[dict]:
    return [
        motif(
            "01_weary_flower",
            "疲惫与仍未放弃的希望",
            "有机隐喻 / 不对称 / 中等留白",
            "A drooping flower whose stem bends under its weight, while one small leaf still points upward.",
            [
                [(335, 535), (329, 490), (324, 448), (318, 405), (315, 360), (319, 315), (312, 270)],
                [(312, 270), (285, 251), (266, 218), (276, 190), (305, 184), (324, 207)],
                [(324, 207), (350, 184), (381, 190), (390, 217), (374, 244), (340, 257), (312, 270)],
                [(320, 390), (353, 363), (384, 370), (360, 397), (320, 390)],
                [(317, 420), (288, 398), (269, 407), (288, 427), (317, 420)],
                [(190, 548), (275, 542), (360, 546), (450, 540)],
            ],
        ),
        motif(
            "02_anxiety_knot",
            "焦虑、思绪纠缠、找不到出口",
            "高密度抽象 / 连续曲线 / 中心压迫",
            "A dense knot of looping lines tightening toward the center, with short nervous marks around it.",
            [
                spiral(320, 320, 22, 185, 3.4, 130),
                spiral(320, 320, 35, 150, -2.6, 110),
                ellipse(320, 320, 175, 115, 0.3, math.tau + 0.3, 70),
                [(180, 185), (160, 164)], [(245, 145), (237, 116)], [(330, 138), (334, 106)],
                [(418, 160), (436, 133)], [(468, 225), (494, 211)], [(486, 330), (517, 333)],
                [(456, 424), (482, 443)], [(365, 475), (371, 507)], [(258, 478), (250, 507)],
                [(173, 431), (149, 452)], [(145, 338), (113, 340)], [(158, 248), (128, 232)],
            ],
        ),
        motif(
            "03_quiet_pond",
            "平静、停顿、被容纳",
            "极简风景 / 大留白 / 水平节奏",
            "A quiet moon over a still pond, three soft ripples, and two reeds at the edge.",
            [
                ellipse(320, 180, 54, 54, 0, math.tau, 52),
                wave(360, 125, 515, 5, 2.2, 80),
                ellipse(320, 385, 128, 24, 0.08, math.pi - 0.08, 45),
                ellipse(320, 420, 188, 31, 0.12, math.pi - 0.12, 55),
                ellipse(320, 463, 245, 38, 0.18, math.pi - 0.18, 65),
                [(120, 440), (115, 360), (128, 292)],
                [(142, 445), (151, 372), (145, 320)],
                [(113, 352), (91, 330)], [(151, 374), (174, 344)],
            ],
        ),
        motif(
            "04_anger_cage",
            "愤怒、受困、想冲破边界",
            "尖锐几何 / 断裂 / 高能量",
            "A jagged flame-like burst pushing through a broken cage of vertical bars.",
            [
                [(250, 500), (235, 405), (247, 305), (239, 205), (250, 135)],
                [(295, 505), (286, 421), (292, 345)],
                [(292, 270), (286, 205), (294, 130)],
                [(345, 508), (350, 428), (347, 360)],
                [(348, 285), (353, 212), (348, 132)],
                [(395, 500), (408, 403), (399, 305), (410, 210), (398, 137)],
                [(196, 455), (245, 398), (217, 352), (285, 326), (253, 270), (322, 286),
                 (345, 214), (375, 278), (444, 249), (411, 325), (466, 356), (404, 397), (438, 463)],
                [(207, 115), (180, 82)], [(320, 101), (322, 58)], [(432, 116), (467, 82)],
                [(171, 285), (125, 274)], [(468, 292), (516, 282)],
            ],
        ),
        motif(
            "05_crossroads_maze",
            "迷茫、选择过多、寻找方向",
            "抽象几何 / 迷宫 / 分叉叙事",
            "A single path enters a square maze and splits into three imperfect exits.",
            [
                [(320, 575), (320, 510), (265, 470), (265, 412), (365, 412), (365, 350),
                 (225, 350), (225, 275), (420, 275), (420, 205), (305, 205), (305, 130)],
                [(320, 510), (405, 475), (455, 425), (505, 425)],
                [(265, 470), (190, 466), (145, 425), (95, 425)],
                [(145, 185), (145, 515), (495, 515)],
                [(495, 515), (495, 145), (205, 145)],
                [(205, 145), (205, 220), (430, 220)],
                [(95, 425), (75, 410), (95, 395)],
                [(505, 425), (525, 410), (505, 395)],
                [(305, 130), (290, 105), (320, 105), (305, 130)],
            ],
        ),
        motif(
            "06_grief_repair",
            "失落、破裂、缓慢修复",
            "静物隐喻 / 断线 / 缝合痕迹",
            "A cracked bowl whose fragments are held together by visible hand-drawn seams.",
            [
                ellipse(320, 275, 210, 65, 0.05, 1.35, 24),
                ellipse(320, 275, 210, 65, 1.78, 3.09, 24),
                [(111, 282), (140, 395), (215, 470), (320, 492)],
                [(320, 492), (426, 470), (500, 394), (529, 282)],
                [(300, 215), (282, 290), (326, 326), (299, 382), (346, 432), (320, 492)],
                [(277, 286), (301, 279)], [(319, 324), (343, 309)],
                [(293, 378), (271, 394)], [(342, 429), (368, 414)],
                [(232, 530), (320, 542), (408, 530)],
            ],
        ),
        motif(
            "07_weighted_sprout",
            "承压、韧性、微小生长",
            "自然象征 / 上下张力 / 根系",
            "A tiny sprout bends around a heavy stone while its roots spread quietly below.",
            [
                ellipse(320, 315, 165, 82, math.pi, math.tau, 55),
                [(155, 315), (170, 360), (470, 360), (485, 315)],
                [(318, 490), (315, 430), (310, 373), (286, 334), (277, 280), (292, 225)],
                [(291, 252), (250, 227), (218, 241), (252, 267), (291, 252)],
                [(292, 225), (323, 196), (356, 203), (335, 232), (292, 225)],
                [(316, 430), (270, 470), (238, 515)],
                [(318, 438), (340, 482), (382, 525)],
                [(312, 453), (297, 507), (303, 555)],
                [(265, 535), (382, 535)],
            ],
        ),
        motif(
            "08_distant_chairs",
            "孤独、距离、仍存在的联系",
            "叙事场景 / 双主体 / 大面积空白",
            "Two empty chairs face each other across a wide gap, joined only by a loose thread.",
            [
                [(130, 290), (225, 290), (225, 405), (145, 405), (145, 290)],
                [(145, 405), (132, 520)], [(215, 405), (230, 520)],
                [(415, 290), (510, 290), (495, 405), (415, 405), (415, 290)],
                [(425, 405), (410, 520)], [(495, 405), (510, 520)],
                [(225, 350), (270, 340), (305, 360), (340, 338), (380, 355), (415, 345)],
                [(75, 535), (250, 535)], [(390, 535), (565, 535)],
            ],
        ),
        motif(
            "09_released_kite",
            "松开、自由、带一点失去",
            "动态符号 / 对角构图 / 风的轨迹",
            "A kite rises into open space while its broken string curls downward in the wind.",
            [
                [(405, 115), (500, 195), (415, 285), (330, 190), (405, 115)],
                [(405, 115), (415, 285)], [(330, 190), (500, 195)],
                [(415, 285), (380, 325), (405, 352), (365, 390), (388, 420),
                 (340, 455), (355, 495), (302, 535)],
                [(356, 495), (333, 476), (318, 500)],
                [(180, 180), (240, 160), (292, 175)],
                [(145, 235), (215, 220), (275, 238)],
                [(120, 305), (185, 287), (250, 302)],
                [(492, 330), (525, 312), (550, 325)],
            ],
        ),
        motif(
            "10_open_arms_sun",
            "释然、喜悦、重新向外打开",
            "人物姿态 / 放射节奏 / 开放构图",
            "A simple figure stands with open arms beneath a rising sun and generous rays.",
            [
                ellipse(320, 245, 42, 48, 0, math.tau, 42),
                [(320, 293), (320, 405), (275, 500)],
                [(320, 405), (370, 500)],
                [(320, 330), (250, 300), (190, 245)],
                [(320, 330), (390, 300), (455, 240)],
                ellipse(320, 535, 205, 48, math.pi + 0.12, math.tau - 0.12, 60),
                ellipse(320, 115, 60, 60, math.pi, math.tau, 36),
                [(320, 48), (320, 20)], [(260, 64), (240, 38)], [(380, 64), (402, 38)],
                [(215, 105), (180, 96)], [(425, 105), (462, 96)],
                [(182, 235), (155, 215)], [(458, 232), (486, 210)],
            ],
        ),
    ]


def svg_for(item: dict) -> str:
    paths = []
    for stroke in item["strokes"]:
        d = "M " + " L ".join(f"{x:.1f} {y:.1f}" for x, y in stroke)
        paths.append(
            f'  <path d="{d}" fill="none" stroke="#181818" stroke-width="5" '
            'stroke-linecap="round" stroke-linejoin="round"/>'
        )
    metadata = json.dumps(
        {key: item[key] for key in ("id", "emotion", "representation", "prompt")},
        ensure_ascii=False,
    )
    return "\n".join([
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">',
        f"  <metadata>{metadata}</metadata>",
        f'  <rect width="{SIZE}" height="{SIZE}" fill="#ffffff"/>',
        *paths,
        "</svg>",
        "",
    ])


def draw_round_line(draw: ImageDraw.ImageDraw, stroke: Iterable[Point]) -> None:
    points = [(round(x), round(y)) for x, y in stroke]
    if len(points) < 2:
        return
    draw.line(points, fill=INK, width=LINE_WIDTH, joint="curve")
    radius = LINE_WIDTH // 2
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=INK)


def write_fixture(item: dict) -> None:
    stem = item["id"]
    (INPUT_DIR / f"{stem}.svg").write_text(svg_for(item), encoding="utf-8")
    image = Image.new("RGB", (SIZE, SIZE), BACKGROUND)
    draw = ImageDraw.Draw(image)
    for stroke in item["strokes"]:
        draw_round_line(draw, stroke)
    image.save(INPUT_DIR / f"{stem}.png", format="PNG", optimize=True)


def write_contact_sheet(items: Sequence[dict]) -> None:
    columns, rows = 5, 2
    thumb, label_height, gap = 190, 28, 14
    width = gap + columns * (thumb + gap)
    height = gap + rows * (thumb + label_height + gap)
    sheet = Image.new("RGB", (width, height), (244, 241, 234))
    draw = ImageDraw.Draw(sheet)

    for index, item in enumerate(items):
        row, column = divmod(index, columns)
        x = gap + column * (thumb + gap)
        y = gap + row * (thumb + label_height + gap)
        preview = Image.open(INPUT_DIR / f"{item['id']}.png").convert("RGB")
        preview.thumbnail((thumb, thumb), Image.Resampling.LANCZOS)
        sheet.paste(preview, (x, y))
        draw.rectangle((x, y, x + thumb - 1, y + thumb - 1), outline=(196, 190, 178), width=1)
        draw.text((x, y + thumb + 6), item["id"], fill=(35, 35, 35))

    sheet.save(HERE / "fixture_contact_sheet.png", format="PNG", optimize=True)


def main() -> None:
    INPUT_DIR.mkdir(parents=True, exist_ok=True)
    items = fixtures()
    for item in items:
        write_fixture(item)
        print(f"  ✓ {item['id']}: {item['emotion']} / {item['representation']}")

    write_contact_sheet(items)
    manifest = {
        "provenance": "GPT-5.6-authored deterministic engineering fixtures",
        "limitations": [
            "Not generated by Qwen-Image.",
            "Not evidence of emotional response quality.",
            "Use only to preflight SVG-vs-skeleton stroke mechanics.",
        ],
        "canvas": {"width": SIZE, "height": SIZE, "background": "white", "ink": "black"},
        "count": len(items),
        "fixtures": [
            {key: item[key] for key in ("id", "emotion", "representation", "prompt")}
            for item in items
        ],
    }
    (INPUT_DIR / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"\nGenerated {len(items)} SVG+PNG pairs, input/manifest.json, "
        "and fixture_contact_sheet.png"
    )


if __name__ == "__main__":
    main()
