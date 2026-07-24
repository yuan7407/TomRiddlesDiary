nonisolated enum StrokeSourcePayload: Equatable, Sendable {
    case raster(BinaryMask)
    case ordered([Polyline])
}

/// Source-pluggable local pipeline. Raster input is thinned and traced; ordered vectors bypass
/// those steps. Both routes share exactly the same humanizer and replay representation.
nonisolated struct StrokePipeline: Sendable {
    private let skeletonizer = Skeletonizer()
    private let tracer = StrokeTracer()
    private let humanizer = StrokeHumanizer()

    func process(
        _ source: StrokeSourcePayload,
        configuration: HumanizerConfiguration = HumanizerConfiguration(),
        seed: UInt64 = 7
    ) -> StrokeSequence {
        let polylines: [Polyline]
        switch source {
        case let .raster(mask):
            polylines = tracer.trace(skeletonizer.skeletonize(mask))
        case let .ordered(ordered):
            polylines = ordered
        }

        return humanizer.humanize(polylines, configuration: configuration, seed: seed)
    }
}
