//
//  InkAge.swift
//  模块：StrokeEngine（纯逻辑，只依赖 Foundation）
//
//  文件职责：墨的年纪——一段墨写下去多久了、现在有多湿。
//  刚落下的墨是蓝黑色、略微鼓起；两三秒后干成墨黑。颜色本身在配置层，这里只算 0…1 的湿度。
//
//  为什么墨要有年纪：
//  原来纸上所有的墨是同一个颜色，分不出哪一笔是刚写的。
//  加上「湿 → 干」以后，笔尖后面拖着一小段蓝黑色，眼睛会自然跟着它走，
//  「有人正在写」这件事不用任何光标或高亮就看得出来。
//
//  为什么按「每一段」算而不是按「每一笔」算：
//  一笔长横要写零点几秒，写到末尾时开头已经开始干了。
//  整笔一个颜色的话，每写完一笔颜色会跳一下；按段算，蓝色是沿着笔画连续褪掉的。
//
//  为什么墨龄按墙上的钟走、不按播放进度走：
//  回应被用户落笔打断后，播放定格在半截字上（决策 14），但已经写下的墨不该跟着「定格」——
//  它是真的落在纸上了，照样会干。所以 `age` 要的是「从这段回应开始写算起、真实过去了几秒」，
//  调用方在定格以后仍然要把这个数往前推。
//
//  这里不碰时钟，时间一律由调用方给，所以丢帧不会累积误差。
//

import Foundation

/// 墨干得多快。
nonisolated struct InkDrying: Equatable, Sendable {
    /// 墨从落下到干透要几秒。
    let dryingTime: TimeInterval
    /// 湿度随时间下降的曲线指数。1 是匀速变干；大于 1 时开头干得快，后面拖一点尾巴。
    let curveExponent: Double

    init(dryingTime: TimeInterval, curveExponent: Double) {
        precondition(dryingTime > 0 && dryingTime.isFinite, "Drying time must be positive and finite")
        precondition(curveExponent > 0 && curveExponent.isFinite, "Curve exponent must be positive and finite")
        self.dryingTime = dryingTime
        self.curveExponent = curveExponent
    }

    /// 写下去 `age` 秒的墨有多湿：1 刚落下，0 干透。
    /// 还没落下的墨（负数）按最湿算；算不出来的（NaN）按干透算——宁可少画一点蓝，也不让坏数据把整页染蓝。
    func wetness(age: TimeInterval) -> Double {
        guard !age.isNaN else { return 0 }
        guard age > 0 else { return 1 }
        let remaining = min(1, max(0, 1 - age / dryingTime))
        return pow(remaining, curveExponent)
    }
}

/// 一段回应里每一笔是第几秒落下的。用来回答「这一段墨写下去多久了」。
nonisolated struct InkAgeTimeline: Equatable, Sendable {
    /// 每一笔从整段开始算第几秒落笔（已经算上它前面的停顿）。
    let inkStartTimes: [TimeInterval]
    /// 每一笔写多久。
    let durations: [TimeInterval]

    init(sequence: StrokeSequence) {
        var starts: [TimeInterval] = []
        var durations: [TimeInterval] = []
        starts.reserveCapacity(sequence.strokes.count)
        durations.reserveCapacity(sequence.strokes.count)
        // 和 `StrokeSequence.totalDuration` 用同一种累加方式（逐笔加「停顿 + 时长」），
        // 否则最后一笔的结束时刻会和整段时长差一个浮点尾数（见 MEMORY「已知陷阱」）。
        var clock: TimeInterval = 0
        for stroke in sequence.strokes {
            starts.append(clock + stroke.pauseBefore)
            durations.append(stroke.duration)
            clock += stroke.totalDuration
        }
        self.inkStartTimes = starts
        self.durations = durations
    }

    /// 第 `index` 笔上、时间比例为 `fraction`（0 起笔，1 收笔）的那一段墨，现在几岁。
    /// 下标越界时返回 0（当作刚落下），不崩：渲染层每帧都在调它。
    func age(ofStroke index: Int, fraction: Double, secondsSinceStart: TimeInterval) -> TimeInterval {
        guard inkStartTimes.indices.contains(index) else { return 0 }
        let clamped = min(1, max(0, fraction))
        return secondsSinceStart - (inkStartTimes[index] + clamped * durations[index])
    }
}
