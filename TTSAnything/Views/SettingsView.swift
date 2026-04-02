import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var hotkey: Hotkey

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.hotkey = hotkey
        view.onRecord = { newHotkey in
            hotkey = newHotkey
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        nsView.hotkey = hotkey
        nsView.needsDisplay = true
    }
}

class ShortcutRecorderView: NSView {
    var hotkey: Hotkey = .default
    var onRecord: ((Hotkey) -> Void)?
    private var isRecording = false
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor
        bg.setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        path.fill()

        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let text: String
        if isRecording {
            text = "Type shortcut..."
        } else {
            text = hotkey.displayKeys.joined(separator: " ")
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        str.draw(at: point)
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        needsDisplay = true
        window?.makeFirstResponder(self)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            let mods = event.modifierFlags.intersection([.command, .option, .shift, .control])
            // Need at least one modifier (not just shift)
            let hasRealModifier = mods.contains(.command) || mods.contains(.option) || mods.contains(.control)
            guard hasRealModifier else { return nil }

            let newHotkey = Hotkey(keyCode: UInt32(event.keyCode), modifiers: UInt32(mods.rawValue))
            self.hotkey = newHotkey
            self.onRecord?(newHotkey)
            self.stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        needsDisplay = true
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("OpenAI API Key")
                    .font(.subheadline)
                    .fontWeight(.medium)
                SecureField("sk-...", text: $settings.apiKey)
                    .textFieldStyle(.roundedBorder)
                if settings.isConfigured {
                    Text("Using OpenAI TTS")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text("No key — using macOS voice (say)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if settings.isConfigured {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Voice")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Picker("", selection: $settings.selectedVoice) {
                        ForEach(Voice.allCases) { voice in
                            Text(voice.displayName)
                                .font(.system(size: 10))
                                .tag(voice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Shortcut")
                    .font(.subheadline)
                    .fontWeight(.medium)
                ShortcutRecorder(hotkey: $settings.hotkey)
                    .frame(height: 28)
                Text("Click to record a new shortcut")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // About
            HStack(spacing: 4) {
                Text("TTS Anything")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("v\(version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    Text("(\(build))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 300, height: settings.isConfigured ? 320 : 260)
    }
}
