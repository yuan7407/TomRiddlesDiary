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

    @Published var sourceMode: StrokeLabSourceMode = .orderedVector {
        didSet {
            guard sourceMode != oldValue else { return }
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

    var sourceDetail: String {
        switch sourceMode {
        case .orderedVector:
            "Ordered points bypass thinning and tracing."
        case .raster:
            "Binary mask → Zhang–Suen → deterministic tracer."
        }
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

        let fixture = selectedFixture
        sequence = pipeline.process(
            FixtureCatalog.source(for: fixture, mode: sourceMode),
            configuration: configuration,
            seed: fixture.seed
        )
    }
}
