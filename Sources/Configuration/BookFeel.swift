//
//  BookFeel.swift
//  模块：Configuration（集中配置。本文件只用 Foundation）
//
//  文件职责：「对开」这一层的全部经验性常数——墨多久干、他读得多快、他想的时候墨点洇多大、
//  句读后面停多久、怎样算写得快、合页多少度算合上。
//
//  ── 这些数是哪来的（必须先读）──
//  **全部未经真机验证。** 它们是 2026-11-11 在网页原型里用鼠标书写、肉眼调出来的，
//  原型的页面按 iPhone Duo 内屏的点数等比搭建（890 × 626 点，字高 34 点约 6 毫米）。
//  打算怎么验：真机到手后，每一项单独看——
//  · 墨干的时间：对着真的钢笔字看，蓝黑转黑是不是这个节奏；
//  · 阅读速度、句读停顿：让三个没见过的人各写一段，问「它读的时候你觉得快还是慢」；
//  · 写得快 / 慢的界线：用 A10 的量尺量出真人的书写速度分布再定。
//
//  单位约定与仓库一致（决策 25）：长度一律写成「魂的字高」的倍数，时间用绝对秒。
//

import Foundation

nonisolated enum BookFeel {
    // MARK: 墨的年纪

    /// 墨从湿到干要多久，以及变干的曲线。
    /// 2.8 秒是原型里看着「不拖也不抢」的值；指数 1.4 让墨先慢后快地变干
    /// （刚写下的一小段时间里明显是湿的，然后较快地转黑）。
    static let inkDrying = InkDrying(dryingTime: 2.8, curveExponent: 1.4)

    /// 湿墨比干墨粗多少（比例）。湿的时候墨在纸面上鼓着，看起来略粗。
    static let wetInkWidthGain: Double = 0.18

    /// 一轮的一生（计划 P4，网页原型 drawDrink / drawSinking / 压痕）。全部照搬原型，未经真机复核。
    /// 长度是原型单位（乘 `PaperLook.pointsPerPrototypeUnit`）。
    enum Drink {
        /// 纸把你这一轮的字喝下去用多久（秒，原型 DRINK）。上一段回应沉下去也用这么久。
        static let duration: TimeInterval = 1.5
        /// 一笔接一笔地喝：第 i 笔（共 n 笔）晚 i/n × 0.55 × duration 开始，每笔喝 0.45 × duration。
        static let staggerShare: Double = 0.55
        static let perStrokeShare: Double = 0.45
        /// 喝的时候朝书脊偏多远（原型 7）。
        static let shiftTowardSpine: Double = 7
        /// 墨宽从原来的宽度按 (1 − p)^0.8 收细，最后留一根 0.15 的线头（原型 2.7·(1−p)^0.8 + 0.15）。
        static let widthExponent: Double = 0.8
        static let widthFloor: Double = 0.15
        /// 喝完留下的压痕：很淡（0.05）、略糊（1.2 点），在喝到四成以后才慢慢浮出来（原型 smooth(0.4, 1, q)）。
        static let ghostOpacity: Double = 0.05
        static let ghostBlur: Double = 1.2
        static let ghostAppearsFrom: Double = 0.4
        /// 上一段回应沉下去：朝书脊偏 8、糊到 2.4 点、淡到没有（原型 drawSinking）。
        static let sinkShift: Double = 8
        static let sinkBlur: Double = 2.4
    }

    /// 笔尖那一滴（计划 P3，网页原型 Script.draw 末尾）：他正在写的那一笔，笔尖挂着一滴湿墨，
    /// 带一点反光。全部数值照搬原型，未经真机复核。
    enum NibBead {
        /// 墨珠半径 = 此处墨宽 × 0.72，最小 1.1 原型单位（墨宽很细时也看得见）。
        static let radiusOfInkWidth: Double = 0.72
        static let minimumRadius: Double = 1.1
        /// 颜色 rgba(14, 22, 70, 0.92)：比湿墨更深的蓝黑。
        static let tone = InkTone(red: 14.0 / 255, green: 22.0 / 255, blue: 70.0 / 255)
        static let opacity: Double = 0.92
        /// 反光：白色 0.55，圆心偏左上 (−0.32r, −0.34r)，半径 0.26r。
        static let glintOpacity: Double = 0.55
        static let glintOffsetX: Double = -0.32
        static let glintOffsetY: Double = -0.34
        static let glintRadius: Double = 0.26
    }

    // MARK: 他在读

    /// 他读你的字时，那一小段「重新变湿」的墨怎么走。
    /// 速度 25 字高/秒：一句十来个字的话大约读一秒。上下限保证太短的话也看得见、太长的话不拖。
    static let readingSweep = ReadingSweepConfiguration(
        speedInGlyphHeightsPerSecond: 25,
        shortestDuration: 0.7,
        longestDuration: 1.5,
        tailFractionOfInk: 0.45,
        shortestTailInGlyphHeights: 1.2,
        longestTailInGlyphHeights: 4.4,
        fadeOutDuration: 0.3
    )

    // MARK: 他在想

    /// 笔尖停在纸上时那一点墨：起始半径、最多再洇开多少（都是字高的倍数），以及洇开的时间常数。
    /// 含义是「停得越久洇得越大」，但有上限——真的钢笔尖停在纸上也不会无限洇下去。
    static let restingBlotBaseRadiusRatio: Double = 0.038
    static let restingBlotGrowthRatio: Double = 0.068
    static let restingBlotTimeConstant: TimeInterval = 3

    // MARK: 他的手有情绪

    /// 句读后面停多久（秒）。逗号顿一下，句号顿得久一点，问号、省略号最久。
    /// 这些是加在「写完整段要多久」之外的时间，不随魂的书写速度缩放：
    /// 它们表达的是他在斟酌，不是手在移动。
    static let replyCadence = ReplyCadence(configuration: ReplyCadenceConfiguration(
        pauseAfter: [
            "，": 0.16, "、": 0.12, ",": 0.14,
            "；": 0.22, "：": 0.20,
            "。": 0.36, "！": 0.36, ".": 0.34,
            "？": 0.46, "…": 0.50, "—": 0.40,
        ],
        sentenceEnds: ["。", "！", "？", "…", "."],
        hesitation: 0.42 ... 0.67,
        closingSlowdown: 1.22
    ))

    // MARK: 你下笔的样子

    /// 怎样算只点了一下、一个圈（`WritingManner`，2026-11-18 收窄成只看「写没写字」）。
    /// 原来还有快慢与停顿的门槛，随着「写了字就不告诉他怎么写的」一起删了。
    static let writingManner = WritingMannerThresholds(
        tapBelowGlyphHeights: 0.4,
        loopAboveGlyphHeights: 2.6
    )

    // MARK: 断行

    /// 魂的回应用的换行规则：在禁则与不拆词之外，再加上「按意思换行」。
    ///
    /// 0.5 的意思是：这一行排过一半、又刚好说完一句或半句，就换行。
    /// **未经验证**：0.5 与 2.2 是在网页原型里试出来的（0.56 时短句偶尔断不开，0.4 时行太碎）。
    /// 验证办法：拿 C1 的 11 段参考答案各排一遍，看有没有哪一段断得别扭。
    /// 代价要知道：按意思换行会让文字块变高，页面快写满时更容易触发翻页。
    static let lineBreaking: LineBreakRules = {
        var rules = LineBreakRules.standard
        rules.phraseBreakFill = 0.5
        return rules
    }()

    // MARK: 笔法

    /// 楷书笔法的强弱（0 不加，1 是 `BrushShaping` 里曲线的原样）。
    /// **未经验证**：曲线和这个 1 都是在网页原型里对着屏幕肉眼定的，没有真人笔迹依据。
    /// 验证办法：真机上同一段话分别用 0、0.5、1 写三遍并排看；A10 真笔校准时一并复核。
    static let brushStrength: Double = 1

    /// 短于「这个比例 × 字高」的笔当作「点」。来源同上（原型里取 0.14），未经验证。
    static let brushDotLengthInGlyphHeights: Double = 0.14

    // MARK: 触感

    /// 他写字时手里的感觉（见 `HapticScore`）。强度是 0…1。
    /// **全部未经验证**：这几个数是按「要轻到像纸，不能像通知」估的，没有在任何设备上试过。
    /// 验证办法：真机上合着本子握在手里听他写一段，调到「感觉得到但不想甩开」为止。
    static let haptics = HapticScoreConfiguration(
        tapIntensity: 0.22 ... 0.5,
        tapSharpness: 0.55,
        dragIntensity: 0.06 ... 0.2,
        dragSharpness: 0.18,
        shortestDrag: 0.16
    )

    // MARK: 合页

    /// 只拿得到角度、拿不到系统状态时，多少度算合上、多少度算摊平，以及防抖用的回差。
    /// 真机上优先用系统给的状态（`DeviceHinge.Status`），这三个数只是后备。
    static let posture = BookPostureThresholds(closedBelowDegrees: 25, flatAboveDegrees: 165, hysteresisDegrees: 6)
}
