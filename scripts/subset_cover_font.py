#!/usr/bin/env python3
#
#  subset_cover_font.py
#  仓库工具：把封面名牌用的 IM Fell English SC 裁成只剩大写拉丁字母与空格（计划 S3）。
#
#  为什么用它：2026-11-18 用户在五款可免费商用的字体里选了它（老活字，边缘本来就不齐，做旧味最重）。
#  为什么要裁：名牌只印几个大写字母，整套字体 180 KB 没必要进包；留全 A–Z 是为了以后改名牌不用重裁。
#
#  用法（需要 fonttools；原字体放在任意目录，不进仓库）：
#    python3 scripts/subset_cover_font.py <IMFellEnglishSC.ttf 的路径>
#  原字体来源：https://github.com/google/fonts 的 ofl/imfellenglishsc/IMFeENsc28P.ttf，
#  作者 Igino Marini，SIL OFL 1.1（许可证一并放在 Sources/Resources/Fonts/OFL-IMFell.txt）。
#

import sys
from pathlib import Path

from fontTools import subset

OUT = Path(__file__).resolve().parent.parent / "Sources" / "Resources" / "Fonts" / "IMFellEnglishSC-Cover.ttf"


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("用法：python3 scripts/subset_cover_font.py <IMFellEnglishSC.ttf>")
    options = subset.Options()
    options.layout_features = ["kern", "liga"]
    options.name_IDs = ["*"]          # 保留名称表：许可证与 PostScript 名都在里面
    font = subset.load_font(sys.argv[1], options)
    subsetter = subset.Subsetter(options)
    subsetter.populate(text="ABCDEFGHIJKLMNOPQRSTUVWXYZ ")
    subsetter.subset(font)
    subset.save_font(font, str(OUT), options)
    print(f"写出 {OUT}（{OUT.stat().st_size} 字节）")


if __name__ == "__main__":
    main()
