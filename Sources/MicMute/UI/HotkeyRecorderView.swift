import SwiftUI
import AppKit
import Carbon

public struct HotkeyRecorderView: View {
    @ObservedObject var settings = SettingsStore.shared
    @State private var isRecording: Bool = false
    @State private var eventMonitor: Any?

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                HStack(spacing: 6) {
                    if isRecording {
                        Image(systemName: "record.circle.fill")
                            .foregroundColor(.red)
                        Text("Press keys...")
                            .fontWeight(.semibold)
                    } else {
                        Image(systemName: "keyboard")
                        Text(settings.keyCombo.displayString)
                            .fontWeight(.semibold)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isRecording ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isRecording ? Color.red : Color.accentColor.opacity(0.4), lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)

            if !isRecording {
                Button("Record New") {
                    startRecording()
                }
                .controlSize(.small)

                if settings.keyCombo != .default {
                    Button("Reset (⌘\\)") {
                        settings.keyCombo = .default
                    }
                    .controlSize(.small)
                }
            } else {
                Button("Cancel") {
                    stopRecording()
                }
                .controlSize(.small)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Handle escape to cancel
            if event.keyCode == UInt16(kVK_Escape) && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                self.stopRecording()
                return nil
            }

            let relevantModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

            // Allow recording if modifier is present OR if it's a function key (F1-F12)
            let isFunctionKey = (Int(event.keyCode) >= kVK_F1 && Int(event.keyCode) <= kVK_F12)
            if !relevantModifiers.isEmpty || isFunctionKey {
                let newCombo = KeyCombo(
                    keyCode: UInt32(event.keyCode),
                    modifierFlags: relevantModifiers
                )
                self.settings.keyCombo = newCombo
                self.stopRecording()
                return nil
            }

            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
