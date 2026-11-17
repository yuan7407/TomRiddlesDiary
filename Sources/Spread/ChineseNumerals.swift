//
//  ChineseNumerals.swift
//  模块：Spread（「对开」的纯逻辑层，只依赖 Foundation）
//
//  文件职责：页眉日期与页码用的中文数字（计划 P2）。照搬网页原型的 `cnNum` / `folio` / `TODAY`。
//
//  为什么日期和页码的写法不一样：
//  日期按读法写（十七、二十、三十一），页码按数码逐位写（十二 → 「一二」，一〇三 → 「一〇三」）——
//  旧书的页码就是这样印的，逐位写也不会因为页数变大而越写越长。
//
//  为什么自己写而不用 `NumberFormatter` 的 `.spellOut`：spellOut 给的是「十七」这一种读法，
//  页码要的逐位写法它给不出来；而且它的输出随系统语言变，页眉不该因为手机设成英文就印出 seventeen。
//

import Foundation

nonisolated enum ChineseNumerals {
    private static let digits: [Character] = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

    /// 按读法写 0…99：七、十、十七、二十、三十一。超出范围按逐位写，不编造读法。
    static func spoken(_ value: Int) -> String {
        guard (0 ... 99).contains(value) else { return folio(value) }
        if value < 10 { return String(digits[value]) }
        if value == 10 { return "十" }
        if value < 20 { return "十" + String(digits[value - 10]) }
        let tens = String(digits[value / 10]) + "十"
        return value % 10 == 0 ? tens : tens + String(digits[value % 10])
    }

    /// 页码：逐位写。负数不应该出现，出现了就照实写出负号而不是吞掉。
    static func folio(_ value: Int) -> String {
        let sign = value < 0 ? "负" : ""
        return sign + String(abs(value)).compactMap { $0.wholeNumberValue.map { digits[$0] } }.map(String.init).joined()
    }

    /// 页眉日期：「十一月十七日　星期二」。中间是全角空格，和原型一致。
    /// - Parameter weekday: 公历星期，1 = 星期日 … 7 = 星期六（`Calendar` 的约定）。
    static func dateLine(month: Int, day: Int, weekday: Int) -> String {
        let names: [Character] = ["日", "一", "二", "三", "四", "五", "六"]
        let name = (1 ... 7).contains(weekday) ? String(names[weekday - 1]) : "?"
        return "\(spoken(month))月\(spoken(day))日　星期\(name)"
    }
}
