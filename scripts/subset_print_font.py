#!/usr/bin/env python3
#
#  subset_print_font.py
#  仓库工具：把思源宋体（Noto Serif SC）裁成「印刷体」用的子集（计划 P2，决策 81）。
#
#  为什么要裁：完整字体每个字重约 11 MB。印刷体只用来印系统说的话（日期、页码、扉页、
#  「他读到的是」、故障提示），GB2312 的 6763 个常用汉字 + 标点 + 拉丁字母足够；
#  子集外的生僻字由 iOS 自动回退到系统字体，不会变成方框。
#
#  为什么做成脚本而不是手工裁一次：以后要加字、换字重，照着重跑一遍就能得到同样的结果，
#  不用考古当时裁了什么。
#
#  用法（需要 fonttools；下载的原字体放在任意目录，不进仓库）：
#    python3 scripts/subset_print_font.py <放着 NotoSerifSC-Regular.otf / -SemiBold.otf 的目录>
#  原字体来源：https://github.com/notofonts/noto-cjk 的 Serif/SubsetOTF/SC/，SIL OFL 1.1。
#

import sys
from pathlib import Path

from fontTools import subset

WEIGHTS = ["Regular", "SemiBold"]   # 原型用 400 与 600 两个字重
OUT_DIR = Path(__file__).resolve().parent.parent / "Sources" / "Resources" / "Fonts"


def gb2312_characters() -> str:
    """GB2312 一、二级汉字与全角符号区：逐个双字节码位解码，解得出来的就是。"""
    chars = []
    for high in range(0xA1, 0xF8):
        for low in range(0xA1, 0xFF):
            try:
                chars.append(bytes([high, low]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return "".join(chars)


def wanted_text() -> str:
    ascii_printable = "".join(chr(c) for c in range(0x20, 0x7F))
    # 原型印刷体里出现的、GB2312 之外可能缺的符号：中文数字零、间隔号、全角空格与常用引号。
    extras = "〇·　「」『』“”‘’…—～"
    return gb2312_characters() + ascii_printable + extras


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__ or "用法见文件头", file=sys.stderr)
        return 2
    source = Path(sys.argv[1])
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    text = wanted_text()
    for weight in WEIGHTS:
        src = source / f"NotoSerifSC-{weight}.otf"
        dst = OUT_DIR / f"NotoSerifSC-Print-{weight}.otf"
        options = subset.Options()
        options.layout_features = ["*"]      # 保留标点挤压、竖排等排版特性
        options.name_IDs = ["*"]             # 保留授权与字体名（OFL 要求保留版权声明）
        options.notdef_outline = True
        options.hinting = False              # CFF 字体在 iOS 上不用 hinting，去掉省空间
        font = subset.load_font(str(src), options)
        subsetter = subset.Subsetter(options)
        subsetter.populate(text=text)
        subsetter.subset(font)
        subset.save_font(font, str(dst), options)
        print(f"{dst.name}: {dst.stat().st_size / 1024 / 1024:.2f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
