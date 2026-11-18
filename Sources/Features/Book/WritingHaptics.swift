//
//  WritingHaptics.swift
//  模块：Features/Book（界面层；依赖 CoreHaptics）
//
//  文件职责：把 `HapticScore` 算好的乐谱交给系统的触感引擎播放。只有这一个文件碰 CoreHaptics。
//
//  为什么失败时什么都不做、也不提示：
//  触感是锦上添花，不是信息的唯一通道——他写的字在屏幕上，合着的时候打开就能看到。
//  设备不支持（iPad 没有触感引擎）、引擎被系统收回、用户关了系统触感，这些都不是需要用户处理的故障，
//  所以不往纸上写提示。但 DEBUG 里会打一行日志说明是哪一种，免得调的时候以为代码没跑。
//  这不属于「静默兜底」：那条规则针对的是会让用户看到一片空白的失败路径。
//
//  2026-11-18 接进界面（计划 P10）：`DiaryPageView` 在他开始写时播、被打断或写完时停。
//  模拟器没有触感，只能真机验。
//

import CoreHaptics
import Foundation

/// 播放「他正在写字」的触感。一段回应对应一次 `play`。
@MainActor
final class WritingHaptics {
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?

    /// 这台设备有没有触感引擎。
    static var isSupported: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// 从这段回应的第 `elapsed` 秒开始，把剩下的部分播完。
    /// 再次调用会先停掉上一段。
    func play(_ sequence: StrokeSequence, from elapsed: TimeInterval = 0) {
        stop()
        guard Self.isSupported else { return }
        let beats = HapticScore.beats(for: sequence, startingAt: elapsed, configuration: BookFeel.haptics)
        guard !beats.isEmpty else { return }

        do {
            let engine = try self.engine ?? CHHapticEngine()
            // 引擎被系统停掉（来电、进后台）以后不自动重来：下一段回应会重新 `play`。
            engine.isAutoShutdownEnabled = true
            try engine.start()
            self.engine = engine

            let events = beats.map { beat in
                CHHapticEvent(
                    eventType: beat.kind == .tap ? .hapticTransient : .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(beat.intensity)),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(beat.sharpness)),
                    ],
                    relativeTime: beat.time,
                    duration: beat.duration
                )
            }
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
            self.player = player
        } catch {
            #if DEBUG
            print("[触感] 没能播放：\(error)")
            #endif
        }
    }

    /// 立刻停。用户落笔打断他的时候要调（决策 14：半截字留在纸上，手上也应该同时停）。
    func stop() {
        guard let player else { return }
        self.player = nil
        do {
            try player.stop(atTime: CHHapticTimeImmediate)
        } catch {
            #if DEBUG
            print("[触感] 没能停下：\(error)")
            #endif
        }
    }
}
