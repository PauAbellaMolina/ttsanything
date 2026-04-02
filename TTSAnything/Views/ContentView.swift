import SwiftUI

struct ShimmerOverlay: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    Color.white.opacity(0),
                    Color.white.opacity(0.15),
                    Color.white.opacity(0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.6)
            .offset(x: phase * geo.size.width * 1.3)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
        .clipped()
    }
}

struct Scrubber: View {
    let progress: Double
    let onSeek: (Double) -> Void
    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    var displayProgress: Double {
        isDragging ? dragProgress : progress
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 4)

                // Fill
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, geo.size.width * displayProgress), height: 4)

                // Thumb
                Circle()
                    .fill(Color.white)
                    .shadow(radius: 1)
                    .frame(width: 12, height: 12)
                    .offset(x: max(0, min(geo.size.width - 12, geo.size.width * displayProgress - 6)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        dragProgress = max(0, min(1, value.location.x / geo.size.width))
                    }
                    .onEnded { value in
                        let fraction = max(0, min(1, value.location.x / geo.size.width))
                        onSeek(fraction)
                        isDragging = false
                    }
            )
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var ttsService: TTSService
    @EnvironmentObject var audioPlayer: AudioPlayer
    @State private var inputText = ""
    @State private var showSettings = false
    @State private var enterMonitorInstalled = false

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("TTS Anything")
                    .font(.headline)
                Spacer()
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
            }

            if audioPlayer.state == .idle {
                // Text input
                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Paste text here...")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                            .padding(.top, 7)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $inputText)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(1)
                }
                .frame(height: 100)
                .padding(4)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                // Action buttons
                HStack(spacing: 8) {
                    Button(action: {
                        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        appState.readText(inputText)
                    }) {
                        Label("Read Aloud", systemImage: "play.fill")
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(action: {
                        appState.readClipboard()
                    }) {
                        Label("Clipboard", systemImage: "doc.on.clipboard")
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button(action: {
                    audioPlayer.replay()
                }) {
                    Label("Replay Last", systemImage: "arrow.counterclockwise")
                        .font(.callout)
                        .foregroundColor(audioPlayer.hasLastAudio ? .accentColor : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(!audioPlayer.hasLastAudio)
                .padding(.top, -4)
            } else {
                let isLoading = audioPlayer.state == .loading

                VStack(spacing: 6) {
                    // Time labels
                    HStack {
                        Text(isLoading ? "-:--" : formatTime(audioPlayer.currentTime))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(isLoading ? "-:--" : formatTime(audioPlayer.duration))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    // Scrubber
                    Scrubber(progress: isLoading ? 0 : audioPlayer.progress) { fraction in
                        if !isLoading { audioPlayer.seek(to: fraction) }
                    }
                    .frame(height: 16)

                    // Transport controls + speed
                    HStack(spacing: 10) {
                        Button(action: { audioPlayer.skipBackward(5) }) {
                            Image(systemName: "gobackward.5")
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)

                        Button(action: { audioPlayer.togglePlayPause() }) {
                            Image(systemName: isLoading ? "play.fill" : (audioPlayer.state == .playing ? "pause.fill" : "play.fill"))
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)

                        Button(action: { audioPlayer.skipForward(5) }) {
                            Image(systemName: "goforward.5")
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)

                        Button(action: { audioPlayer.stop() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // Speed stepper
                        HStack(spacing: 2) {
                            Button(action: {
                                let newSpeed = max(0.5, settings.playbackSpeed - 0.25)
                                settings.playbackSpeed = newSpeed
                                audioPlayer.setRate(Float(newSpeed))
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoading)

                            Text("\(settings.playbackSpeed, specifier: "%.1f")x")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 30)

                            Button(action: {
                                let newSpeed = min(2.0, settings.playbackSpeed + 0.25)
                                settings.playbackSpeed = newSpeed
                                audioPlayer.setRate(Float(newSpeed))
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoading)
                        }
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    isLoading ?
                        ShimmerOverlay()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    : nil
                )
            }

            Divider()

            if !settings.isConfigured {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .foregroundColor(.secondary)
                    Text("For a better voice, add an OpenAI API key in settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Hotkey hint
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .font(.callout)
                Text("To read clipboard press")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                ForEach(settings.hotkey.displayKeys, id: \.self) { key in
                    keycap(key)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .onAppear { installEnterHandler() }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func keycap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }

    private func installEnterHandler() {
        guard !enterMonitorInstalled else { return }
        enterMonitorInstalled = true
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 36 else { return event }
            if event.modifierFlags.contains(.shift) {
                // Shift+Enter: insert newline (let it through)
                return event
            } else {
                // Enter: read text
                let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    appState.readText(text)
                }
                return nil
            }
        }
    }
}
