import SwiftUI

public struct VolumeMeterView: View {
    @ObservedObject var micTest = MicTestManager.shared
    @ObservedObject var audioEngine = AudioEngine.shared

    private let segmentCount = 18

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Level Meter Bar
            HStack(spacing: 3) {
                ForEach(0..<segmentCount, id: \.self) { index in
                    let threshold = Float(index) / Float(segmentCount)
                    let isActive = micTest.isTesting && !audioEngine.isMuted && micTest.audioLevel >= threshold

                    RoundedRectangle(cornerRadius: 2)
                        .fill(segmentColor(for: index, isActive: isActive))
                        .frame(height: 14)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            // Status & Controls
            HStack(spacing: 12) {
                Button(action: {
                    micTest.toggleTesting()
                }) {
                    Label(
                        micTest.isTesting ? "Stop Test" : "Test Microphone",
                        systemImage: micTest.isTesting ? "stop.fill" : "play.fill"
                    )
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(micTest.isTesting ? .orange : .accentColor)

                Toggle("Hear myself (feedback)", isOn: $micTest.isHearMyselfEnabled)
                    .font(.caption)
                    .disabled(!micTest.isTesting)
                    .help("Route mic audio to your output device. Use headphones to prevent echo.")

                Spacer()

                if audioEngine.isMuted && micTest.isTesting {
                    Text("Mic is Muted")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fontWeight(.semibold)
                } else if micTest.isTesting {
                    Text(micTest.audioLevel > 0.05 ? "Signal Active" : "Speak to test...")
                        .font(.caption)
                        .foregroundColor(micTest.audioLevel > 0.05 ? .green : .secondary)
                        .fontWeight(.medium)
                }
            }
        }
    }

    private func segmentColor(for index: Int, isActive: Bool) -> Color {
        guard isActive else {
            return Color.secondary.opacity(0.15)
        }

        let ratio = Double(index) / Double(segmentCount)
        if ratio < 0.65 {
            return Color.green
        } else if ratio < 0.85 {
            return Color.yellow
        } else {
            return Color.red
        }
    }
}
