//
//  CalibrationReportSummary.swift
//  模块：Calibration（纯逻辑；把真人笔迹量成数字，用来校准手感参数）
//
//  文件职责：把测量结果排成一段人能读的文字，**并把它和当前正在用的猜测值并排放**。
//
//  为什么并排放这么重要：
//  单看一个测量值（「手抖频率 8.3 Hz」）没法判断要不要改。并排看到
//  「现在用的是 10.0，量出来 8.3」，才能一眼看出偏了多少、值不值得动。
//  而这份报告的读者是人（先是我，然后是用户），所以格式要能直接贴进对话里。
//
//  为什么这一层知道 `HandwritingFeel`：
//  它的全部工作就是「拿测量值对照当前配置」，不知道当前配置就没法对照。
//  反过来不成立——`HandwritingFeel` 不知道 Calibration 存在，
//  校准结果要不要采用是人的决定，不是代码自动写回去的。
//  **刻意不做自动写回**：那样一次异常的采样就会悄悄改掉全 App 的手感。
//

import Foundation

nonisolated extension CalibrationReport {
    /// 排成一段可以直接贴进对话的文字。
    var summary: String {
        var lines: [String] = []
        lines.append("── 真人笔迹校准（计划 A10）──")
        lines.append(String(
            format: "样本：%d 笔，%d 次抬笔；落墨 %.1fs，墨迹总长 %.0f 点",
            strokeCount, gapCount, inkDuration, inkLength
        ))
        lines.append("力度信息：\(hasVaryingForce ? "有（但量程未公开）" : "无（这支笔没有压感）")")
        lines.append(inputSourceWarning)
        lines.append("")

        lines.append("【不需要知道字有多大就能量的】")
        lines.append(compare(
            "手抖频率",
            measured: tremorFrequencyInHertz,
            current: HandwritingFeel.handTremorFrequencyInHertz,
            unit: "Hz",
            parameter: "handTremorFrequencyInHertz"
        ))
        lines.append(compare(
            "抬落笔固定耗时",
            measured: penLiftDuration,
            current: HandwritingFeel.penLiftDuration,
            unit: "s",
            parameter: "penLiftDuration"
        ))
        lines.append(compare(
            "空中速度倍数",
            measured: airSpeedMultiple,
            current: HandwritingFeel.airSpeedMultipleOfInkSpeed,
            unit: "倍",
            parameter: "airSpeedMultipleOfInkSpeed"
        ))
        lines.append("")

        lines.append("【要先估出字有多大的】")
        lines.append("字高估算（粗糙，取最高四分之一笔画纵向跨度的中位数）："
            + estimatedGlyphHeight.describe(unit: "点", format: "%.1f")
            + String(format: "　当前配置按 %.1f 点", HandwritingFeel.referenceGlyphHeightInPoints))
        lines.append(compare(
            "书写速度",
            measured: inkSpeedInGlyphHeights,
            current: HandwritingFeel.inkLengthPerSecondInReferenceScales,
            unit: "字高/秒",
            parameter: "inkLengthPerSecondInReferenceScales"
        ))
        lines.append("　（绝对值：" + inkSpeedInPoints.describe(unit: "点/秒", format: "%.1f") + "）")
        lines.append(compare(
            "手抖幅度",
            measured: tremorAmplitudeRatio,
            current: HandwritingFeel.jitterAmplitudeRatio,
            unit: "×字高",
            parameter: "jitterAmplitudeRatio"
        ))
        lines.append("　（绝对值：" + tremorAmplitudeInPoints.describe(unit: "点", format: "%.2f") + "）")
        lines.append("")

        lines.append("【量不了的】")
        lines.append("压感起伏 pressureVariation：" + pressureVariation.describe(unit: ""))
        lines.append("转折加成 curvaturePressureGain：需要力度信息，同上")

        return lines.joined(separator: "\n")
    }

    /// 数据来源那一行。不像笔写的就把话说重一点——这批数字**不能**用来调手感。
    ///
    /// 为什么要这么显眼：模拟器上只能用鼠标画，而鼠标的速度和抖动不是人手的。
    /// 报告本身不说清来源，就只能指望人记得「这次是鼠标」，而人不会一直记得。
    private var inputSourceWarning: String {
        looksLikePenInput
            ? "数据来源：像是真笔（笔与屏幕的夹角在变化）"
            : "数据来源：**不像真笔**（夹角全程不变，多半是鼠标或手指）"
                + "——下面的速度与抖动量的不是人手，只能用来确认这条链路通了，不能拿去调手感"
    }

    /// 一行「量出来 vs 现在用的」。
    ///
    /// 同时给出偏差倍数：人对「差了几倍」比对「差了多少」敏感得多，
    /// 而要不要改参数，看的正是差了几倍。
    private func compare(
        _ label: String,
        measured: CalibrationValue,
        current: Double,
        unit: String,
        parameter: String
    ) -> String {
        let head = "\(label) \(parameter)：" + measured.describe(unit: unit)
        let tail = String(format: "　现在用 %.3f \(unit)", current)

        guard let value = measured.value, current > 0 else { return head + tail }
        return head + tail + String(format: "　偏 %.2f 倍", value / current)
    }
}
