//
//  CoverLook.swift
//  模块：Configuration（集中配置，被界面层读取）
//
//  文件职责：外屏那张旧书封面（计划 S 组，决策 83）的全部视觉与交互常量的唯一定义处。
//
//  数从哪来：用户 2026-11-18 给的参考图（深蓝灰皮面、黄铜护角、黑底烫金名牌），
//  在 Duo 外屏（466 × 678 点）上肉眼对照着定。**没有测量依据，全是看出来的**；
//  长度凡是写「封面宽的比例」的，乘封面宽度换成点，换屏幕尺寸也成比例。
//  颜色是 sRGB 0…1。验证办法：真机外屏截图和参考图并排看（计划 S10）。
//

import Foundation

nonisolated enum CoverLook {
    struct RGB: Equatable, Sendable { let red, green, blue: Double }

    // MARK: 皮面（S1）

    enum Leather {
        /// 底色：参考图皮面的深蓝灰。
        static let base = RGB(red: 0.20, green: 0.215, blue: 0.27)
        /// 色块里偏亮的那一种（参考图上皮面有一片片发灰发蓝的亮处）。
        static let light = RGB(red: 0.31, green: 0.33, blue: 0.40)
        /// 颗粒之间的折痕。
        static let crease = RGB(red: 0.10, green: 0.11, blue: 0.14)
        /// 边角被手磨旧的颜色：灰白一点、发干。
        static let worn = RGB(red: 0.36, green: 0.37, blue: 0.40)
        /// 皮纹一个颗粒多大（点）。参考图上一颗约是书宽的 1%，外屏宽 466 点 → 约 5 点。
        static let grainCell: Double = 4.4
        /// 色块明暗起伏的强弱（0 没有，1 满）。
        static let mottle: Double = 0.75
        /// 离边多远以内算会被磨旧（点）。
        static let edgeWear: Double = 16
        /// 书脊那道压槽离左边多远（封面宽的比例）。硬壳书的封面在这里弯折。
        static let grooveFromSpine: Double = 0.045
        /// 每本书的纹路不同，这个数决定这一本长什么样。
        static let seed: Double = 1943
    }

    // MARK: 黄铜护角（S2）

    enum Corner {
        /// 护角一条边多长（封面宽的比例）。参考图约是书宽的 24%。
        static let armLength: Double = 0.25
        /// 黄铜的三种色：暗处、中间、亮处（做旧的古铜，不是新黄铜的亮黄）。
        static let shadow = RGB(red: 0.22, green: 0.16, blue: 0.08)
        static let body = RGB(red: 0.50, green: 0.40, blue: 0.23)
        static let highlight = RGB(red: 0.76, green: 0.64, blue: 0.40)
        /// 铜绿与氧化斑的颜色，以及凸起处被磨亮的颜色。
        static let patina = RGB(red: 0.20, green: 0.19, blue: 0.13)
        static let polished = RGB(red: 0.88, green: 0.79, blue: 0.58)
        /// 打在皮面上的影子：光从左上来，影子落在右下。
        static let dropShadowRadius: Double = 2.5
        static let dropShadowOffset = (x: 1.0, y: 2.5)
        static let dropShadowOpacity: Double = 0.6
        /// 立体感：边缘里侧的一圈亮、一圈暗（点）。
        static let bevelWidth: Double = 1.6
        static let seed: Double = 7
    }

    // MARK: 名牌（S3）

    enum Plate {
        static let text = "TOM RIDDLE DIARY"
        /// IM Fell English SC 子集（`scripts/subset_cover_font.py`，用户 2026-11-18 在五款里选的）。
        static let fontFile = "IMFellEnglishSC-Cover"
        static let fontName = "IM_FELL_English_SC"
        /// 字号与字距（封面宽的比例）。
        static let fontSize: Double = 0.056
        static let tracking: Double = 0.006
        /// 名牌左右、上下留的边（字号的倍数）。
        static let horizontalPadding: Double = 0.9
        static let verticalPadding: Double = 0.42
        /// 名牌中心的位置：横向在书脊压槽右边那块的正中，纵向在封面高的 74% 处（参考图）。
        static let centerHeight: Double = 0.74
        /// 黑皮片的颜色，与烫金的三种金色。
        static let leather = RGB(red: 0.06, green: 0.06, blue: 0.06)
        static let leatherLight = RGB(red: 0.12, green: 0.12, blue: 0.11)
        static let goldDark = RGB(red: 0.58, green: 0.45, blue: 0.22)
        static let gold = RGB(red: 0.84, green: 0.71, blue: 0.42)
        static let goldLight = RGB(red: 0.95, green: 0.87, blue: 0.62)
        /// 烫金磨掉了多少（0 全新，1 几乎磨光）。
        static let goldWear: Double = 0.45
        static let grainCell: Double = 2.6
        static let seed: Double = 31
    }

    // MARK: 翻开与合上（S5、S7）

    enum Motion {
        /// 手指往左拖过封面宽的这么多就算要翻开；或者松手时甩出去的预计位置超过 `flingProgress`。
        static let openProgress: Double = 0.38
        static let flingProgress: Double = 0.7
        /// 少于这么多点的拖动不算翻（防误触）。
        static let minimumDrag: Double = 8
        /// 封面完全翻开时转过的角度。超过 90° 封面就转到屏幕外了，多转一点让它干脆离开。
        static let openAngleDegrees: Double = 100
        /// 透视的强弱（SwiftUI rotation3DEffect 的 perspective）。
        static let perspective: Double = 0.55
        /// 松手后翻开 / 弹回 / 合上回来的时长（秒）。
        static let finishOpenDuration: TimeInterval = 0.45
        static let springBackDuration: TimeInterval = 0.35
        static let closeDuration: TimeInterval = 0.6
        /// 封面转开时变暗多少（转离光源）。
        static let turnDarkening: Double = 0.45
        /// 封面压在纸上的那道影子：最浓多少、多宽（点）。
        static let pageShadowOpacity: Double = 0.32
        static let pageShadowWidth: Double = 46
        /// 教你怎么翻（用户 2026-11-18：「封面 3 秒没反应之后出现 3 秒，循环，无文字」）：
        /// 一点淡淡的光从书口那边（右边中间）往左滑过一段、拖着一小截尾巴，封面右边跟着微微掀起又落回。
        /// 一碰封面就停，重新开始数 3 秒。
        static let hintIdle: TimeInterval = 3
        static let hintDuration: TimeInterval = 3
        /// 封面跟着掀起多少（翻开进度的比例）。
        static let hintLift: Double = 0.06
        /// 光从封面宽的哪儿起、滑到哪儿，在封面高的哪儿；光点多大（封面宽的比例）、最亮多亮。
        static let hintStartX: Double = 0.9
        static let hintEndX: Double = 0.5
        static let hintY: Double = 0.5
        static let hintGlowRadius: Double = 0.05
        static let hintGlowOpacity: Double = 0.38
        /// 尾巴：几个点、每个点落后多少（这一段时间的比例）。
        static let hintTrailCount = 8
        static let hintTrailStep: Double = 0.025
        /// 一段提示里：前多少淡入、到多少开始淡出（这一段时间的比例）。
        static let hintFadeIn: Double = 0.15
        static let hintFadeOutFrom: Double = 0.75
    }
}
