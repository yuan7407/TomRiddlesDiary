import SwiftUI

struct StrokeCanvasView: View {
    let sequence: StrokeSequence
    let replayStartedAt: Date?

    private let ink = Color(red: 0.12, green: 0.105, blue: 0.09)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: replayStartedAt == nil)) { timelineContext in
            Canvas { context, size in
                let elapsed = replayStartedAt.map { max(0, timelineContext.date.timeIntervalSince($0)) }
                    ?? sequence.totalDuration
                let frame = StrokeReplayTimeline(sequence: sequence).frame(at: elapsed)
                render(sequence: sequence, frame: frame, in: &context, size: size)
            }
        }
        .background(Color(red: 0.985, green: 0.974, blue: 0.94))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.09), lineWidth: 1)
        }
        .accessibilityLabel("Sequential pressure-sensitive stroke replay")
    }

    private func render(
        sequence: StrokeSequence,
        frame: ReplayFrame,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard let transform = CanvasTransform(sequence: sequence, size: size) else { return }

        for (strokeIndex, stroke) in sequence.strokes.enumerated() {
            let progress = frame.progressByStroke.indices.contains(strokeIndex)
                ? frame.progressByStroke[strokeIndex]
                : 0
            draw(stroke: stroke, progress: progress, transform: transform, in: &context)
        }
    }

    private func draw(
        stroke: TimedStroke,
        progress: Double,
        transform: CanvasTransform,
        in context: inout GraphicsContext
    ) {
        guard progress > 0, let first = stroke.samples.first else { return }

        if stroke.samples.count == 1 {
            let center = transform.map(first.point)
            let width = lineWidth(for: first.pressure)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - width / 2, y: center.y - width / 2, width: width, height: width)),
                with: .color(ink)
            )
            return
        }

        let segmentProgress = min(1, progress) * Double(stroke.samples.count - 1)
        let completeSegments = min(stroke.samples.count - 1, Int(segmentProgress.rounded(.down)))

        if completeSegments > 0 {
            for index in 0 ..< completeSegments {
                drawSegment(
                    from: stroke.samples[index],
                    to: stroke.samples[index + 1],
                    transform: transform,
                    in: &context
                )
            }
        }

        let partial = segmentProgress - Double(completeSegments)
        if completeSegments < stroke.samples.count - 1, partial > 0 {
            let start = stroke.samples[completeSegments]
            let end = stroke.samples[completeSegments + 1]
            let partialEnd = StrokeSample(
                point: Point2D.interpolate(from: start.point, to: end.point, fraction: partial),
                pressure: start.pressure + (end.pressure - start.pressure) * partial
            )
            drawSegment(from: start, to: partialEnd, transform: transform, in: &context)
        }
    }

    private func drawSegment(
        from start: StrokeSample,
        to end: StrokeSample,
        transform: CanvasTransform,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: transform.map(start.point))
        path.addLine(to: transform.map(end.point))
        context.stroke(
            path,
            with: .color(ink),
            style: StrokeStyle(
                lineWidth: lineWidth(for: (start.pressure + end.pressure) / 2),
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    private func lineWidth(for pressure: Double) -> Double {
        1.15 + min(1, max(0, pressure)) * 4.6
    }
}

private struct CanvasTransform {
    private let scale: Double
    private let offsetX: Double
    private let offsetY: Double

    init?(sequence: StrokeSequence, size: CGSize) {
        let points = sequence.strokes.flatMap { $0.samples.map(\.point) }
        guard let first = points.first else { return nil }

        let bounds = points.dropFirst().reduce(
            into: (minX: first.x, maxX: first.x, minY: first.y, maxY: first.y)
        ) { bounds, point in
            bounds.minX = min(bounds.minX, point.x)
            bounds.maxX = max(bounds.maxX, point.x)
            bounds.minY = min(bounds.minY, point.y)
            bounds.maxY = max(bounds.maxY, point.y)
        }

        let contentWidth = max(1, bounds.maxX - bounds.minX)
        let contentHeight = max(1, bounds.maxY - bounds.minY)
        let padding = min(42, min(size.width, size.height) * 0.09)
        let availableWidth = max(1, size.width - padding * 2)
        let availableHeight = max(1, size.height - padding * 2)
        scale = min(availableWidth / contentWidth, availableHeight / contentHeight)
        offsetX = (size.width - contentWidth * scale) / 2 - bounds.minX * scale
        offsetY = (size.height - contentHeight * scale) / 2 - bounds.minY * scale
    }

    func map(_ point: Point2D) -> CGPoint {
        CGPoint(x: point.x * scale + offsetX, y: point.y * scale + offsetY)
    }
}
