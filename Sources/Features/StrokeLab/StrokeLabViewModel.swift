//
//  StrokeLabViewModel.swift
//  模块：Features/StrokeLab（仅供开发验证的诊断界面，不属于最终用户体验）
//
//  文件职责：持有当前夹具与重播状态，把夹具经 StrokePipeline 转成可重播序列。
//
//  设计原因：
//  - 重播完成用一个可取消的 MainActor 任务收尾，而不是让渲染层永久以 60 Hz 刷新：
//    画完就该停，否则空转会持续耗电。
//  - 用 replayStartedAt 时间戳做过期判定：连点重播或播放中切夹具时，
//    旧任务醒来必须认出自己已过期，不能把新一轮的状态清掉。
//

import Combine
import Foundation

@MainActor
final class StrokeLabViewModel: ObservableObject {
    @Published var selectedFixtureID: String {
        didSet {
            guard selectedFixtureID != oldValue else { return }
            rebuildSequence()
        }
    }

    @Published private(set) var sequence = StrokeSequence(strokes: [])
    @Published private(set) var replayStartedAt: Date?

    let fixtures: [StrokeLabFixture]

    private let pipeline = StrokePipeline()
    private let configuration = HumanizerConfiguration(
        sampleSpacing: 1.25,
        jitterAmplitude: 0.22,
        pointsPerSecond: 72,
        durationVariation: 0.06,
        minimumDuration: 0.12,
        basePressure: 0.7,
        pressureVariation: 0.07,
        minimumPressure: 0.12,
        maximumPressure: 0.92,
        taperFraction: 0.16
    )
    private var replayCompletionTask: Task<Void, Never>?

    init(fixtures: [StrokeLabFixture] = FixtureCatalog.fixtures) {
        precondition(!fixtures.isEmpty, "The stroke lab requires at least one fixture")
        self.fixtures = fixtures
        selectedFixtureID = fixtures[0].id
        rebuildSequence()
    }

    var selectedFixture: StrokeLabFixture {
        fixtures.first { $0.id == selectedFixtureID } ?? fixtures[0]
    }

    var sampleCount: Int {
        sequence.strokes.reduce(into: 0) { $0 += $1.samples.count }
    }

    func replay() {
        replayCompletionTask?.cancel()

        let duration = sequence.totalDuration
        guard duration > 0 else {
            replayStartedAt = nil
            replayCompletionTask = nil
            return
        }

        let startedAt = Date()
        replayStartedAt = startedAt
        replayCompletionTask = Task { @MainActor [weak self] in
            do {
                try await Task<Never, Never>.sleep(
                    nanoseconds: UInt64(duration * 1_000_000_000)
                )
            } catch {
                return
            }

            guard let self, self.replayStartedAt == startedAt else { return }
            self.replayStartedAt = nil
            self.replayCompletionTask = nil
        }
    }

    func elapsedTime(at date: Date) -> TimeInterval {
        guard let replayStartedAt else { return sequence.totalDuration }
        return max(0, date.timeIntervalSince(replayStartedAt))
    }

    private func rebuildSequence() {
        replayCompletionTask?.cancel()
        replayCompletionTask = nil
        replayStartedAt = nil

        // 每个夹具固定自己的 seed：切来切回时手绘抖动保持一致，便于肉眼对比。
        let fixture = selectedFixture
        sequence = pipeline.process(
            fixture.strokes,
            configuration: configuration,
            seed: fixture.seed
        )
    }
}
