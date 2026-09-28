import SwiftUI

public struct VolumeMeterView: View {
    @ObservedObject var micTest = MicTestManager.shared
    @ObservedObject var audioEngine = AudioEngine.shared

    private let segmentCount = 18

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Live VU Level Meter Bar
            HStack(spacing: 3) {
                ForEach(0..<segmentCount, id: \.self) { index in
                    let threshold = Float(index) / Float(segmentCount)
                    let isActive = micTest.isRecording && !audioEngine.isMuted && micTest.audioLevel >= threshold

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

            // 2. Main Action Row (Record / Stop Test)
            HStack(spacing: 12) {
                Button(action: {
                    micTest.toggleRecording()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: micTest.isRecording ? "stop.fill" : (micTest.hasRecording ? "arrow.clockwise" : "mic.fill"))
                        Text(micTest.isRecording ? "Stop Test" : (micTest.hasRecording ? "Record Again" : "Record Mic Test"))
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(micTest.isRecording ? .red : (micTest.hasRecording ? .secondary : .accentColor))

                if micTest.isRecording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text(formatTime(micTest.recordingDuration))
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(.red)

                        if audioEngine.isMuted {
                            Text("— (Microphone Muted)")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Text("— Speak to record...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else if !micTest.hasRecording {
                    Text("Click to record a test clip without feedback echo.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // 3. Playback Controls Card (Appears after recording)
            if micTest.hasRecording && !micTest.isRecording {
                HStack(spacing: 12) {
                    // Play / Pause Button
                    Button(action: {
                        micTest.togglePlayback()
                    }) {
                        Image(systemName: micTest.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help(micTest.isPlaying ? "Pause Playback" : "Play Recorded Mic Clip")

                    // Scrubber Slider
                    Slider(
                        value: Binding(
                            get: { micTest.playbackProgress },
                            set: { micTest.seek(to: $0) }
                        ),
                        in: 0...1
                    )
                    .controlSize(.small)

                    // Timestamp
                    Text("\(formatTime(micTest.playbackTime)) / \(formatTime(micTest.totalDuration))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 70, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                )
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

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(0, time))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
