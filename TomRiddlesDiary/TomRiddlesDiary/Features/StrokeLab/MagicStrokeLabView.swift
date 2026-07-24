import SwiftUI

struct MagicStrokeLabView: View {
    @StateObject private var model = StrokeLabViewModel()

    var body: some View {
        GeometryReader { geometry in
            Group {
                if geometry.size.width >= 860 {
                    HStack(spacing: 22) {
                        controls
                            .frame(width: 294)
                        canvasPanel
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            controls
                            canvasPanel
                                .frame(height: min(620, geometry.size.height * 0.62))
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red: 0.925, green: 0.91, blue: 0.875).ignoresSafeArea())
        .tint(Color(red: 0.36, green: 0.25, blue: 0.16))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Magic Stroke Lab")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("Local stroke mechanics, isolated from the Oracle layer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                controlLabel("Fixture")
                Picker("Fixture", selection: $model.selectedFixtureID) {
                    ForEach(model.fixtures) { fixture in
                        Text(fixture.title).tag(fixture.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(model.selectedFixture.theme)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 9) {
                controlLabel("Stroke source")
                Picker("Stroke source", selection: $model.sourceMode) {
                    ForEach(StrokeLabSourceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(model.sourceDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                stat(value: "\(model.sequence.strokes.count)", label: "strokes")
                stat(value: "\(model.sampleCount)", label: "samples")
                stat(value: model.sequence.totalDuration.formatted(.number.precision(.fractionLength(1))) + "s", label: "replay")
            }

            Button(action: model.replay) {
                Label("Replay stroke by stroke", systemImage: "play.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.sequence.strokes.isEmpty)

            Spacer(minLength: 0)

            Label("Deterministic offline fixture · no model or network", systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var canvasPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.selectedFixture.title)
                        .font(.title2.weight(.semibold))
                    Text("Line width follows generated pressure; timing is strictly sequential.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(model.sourceMode.rawValue.uppercased())
                    .font(.caption2.monospaced().weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.07), in: Capsule())
            }

            StrokeCanvasView(
                sequence: model.sequence,
                replayStartedAt: model.replayStartedAt
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(18)
        .background(Color.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func controlLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.monospaced().weight(.bold))
            .foregroundStyle(.secondary)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    MagicStrokeLabView()
}
