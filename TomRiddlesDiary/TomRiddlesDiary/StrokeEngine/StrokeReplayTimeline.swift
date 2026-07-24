import Foundation

/// Maps elapsed time to per-stroke progress while preserving strict sequential playback.
nonisolated struct StrokeReplayTimeline: Sendable {
    let sequence: StrokeSequence

    var totalDuration: TimeInterval {
        sequence.totalDuration
    }

    func startTime(forStrokeAt index: Int) -> TimeInterval {
        precondition(sequence.strokes.indices.contains(index), "Stroke index is out of range")
        return sequence.strokes[..<index].reduce(into: 0) { total, stroke in
            total += max(0, stroke.duration)
        }
    }

    func frame(at elapsedTime: TimeInterval) -> ReplayFrame {
        let elapsed = elapsedTime.isFinite ? elapsedTime : 0
        var cursor: TimeInterval = 0
        var progress: [Double] = []
        progress.reserveCapacity(sequence.strokes.count)

        for stroke in sequence.strokes {
            let duration = max(0, stroke.duration)
            let strokeProgress: Double

            if duration == 0 {
                strokeProgress = elapsed >= cursor ? 1 : 0
            } else if elapsed <= cursor {
                strokeProgress = 0
            } else if elapsed >= cursor + duration {
                strokeProgress = 1
            } else {
                strokeProgress = (elapsed - cursor) / duration
            }

            progress.append(min(1, max(0, strokeProgress)))
            cursor += duration
        }

        return ReplayFrame(progressByStroke: progress)
    }
}
