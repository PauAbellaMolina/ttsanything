import SwiftUI
import Carbon
import Combine

@main
struct TTSAnythingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

// Weak reference for Carbon callback
private weak var sharedAppState: AppState?

class AppState: ObservableObject {
    let settings = SettingsManager()
    let ttsService = TTSService()
    let audioPlayer = AudioPlayer()
    private var hotkeyRef: EventHotKeyRef?

    init() {
        sharedAppState = self
        registerGlobalHotkey()
        settings.onHotkeyChanged = { [weak self] in
            self?.registerGlobalHotkey()
        }
    }

    func readClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        readText(text)
    }

    @Published var lastText: String?

    func readText(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lastText = text

        audioPlayer.stop()

        if settings.isConfigured {
            audioPlayer.state = .loading
            Task {
                do {
                    let data = try await ttsService.synthesize(
                        text: text,
                        voice: settings.selectedVoice,
                        apiKey: settings.apiKey
                    )
                    await MainActor.run {
                        audioPlayer.play(data: data, rate: Float(settings.playbackSpeed))
                    }
                } catch {
                    await MainActor.run {
                        audioPlayer.state = .idle
                        // Fallback to say on API error
                        let rate = Int(settings.playbackSpeed * 205)
                        audioPlayer.playWithSay(text: String(text.prefix(4096)), rate: rate)
                    }
                }
            }
        } else {
            // No API key — use macOS say
            let rate = Int(settings.playbackSpeed * 205)
            audioPlayer.playWithSay(text: String(text.prefix(4096)), rate: rate)
        }
    }

    private var eventHandlerInstalled = false

    private func registerGlobalHotkey() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x54545341), id: 1) // "TTSA"

        if !eventHandlerInstalled {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )

            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                sharedAppState?.readClipboard()
                return noErr
            }, 1, &eventType, nil, nil)

            eventHandlerInstalled = true
        }

        RegisterEventHotKey(
            settings.hotkey.keyCode,
            settings.hotkey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }

    deinit {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let appState = AppState()
    let popover = NSPopover()
    private var stateObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: "TTS Anything")
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        let contentView = ContentView()
            .environmentObject(appState)
            .environmentObject(appState.settings)
            .environmentObject(appState.ttsService)
            .environmentObject(appState.audioPlayer)

        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.behavior = .transient

        stateObserver = appState.audioPlayer.$state.sink { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if state == .loading && !self.popover.isShown {
                    if let button = self.statusItem.button, let window = button.window {
                        let buttonRect = button.convert(button.bounds, to: nil)
                        let screenRect = window.convertToScreen(buttonRect)
                        StatusToast.show("Loading speech...", near: screenRect)
                    }
                } else if state == .playing && !self.popover.isShown {
                    StatusToast.dismiss()
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let quitItem = NSMenuItem(title: "Quit TTS Anything", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

class StatusToast {
    private static var panel: NSPanel?

    static func show(_ message: String, near rect: NSRect) {
        dismiss()

        let label = NSTextField(labelWithString: message)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()

        let padding: CGFloat = 16
        let height: CGFloat = 28
        let width = label.frame.width + padding * 2
        let origin = NSPoint(
            x: rect.midX - width / 2,
            y: rect.minY - height - 4
        )

        let p = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true

        let bg = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        bg.layer?.cornerRadius = height / 2

        label.frame = NSRect(x: padding, y: (height - label.frame.height) / 2, width: label.frame.width, height: label.frame.height)
        bg.addSubview(label)
        p.contentView = bg

        p.alphaValue = 0
        p.orderFrontRegardless()
        panel = p

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1
        }
    }

    static func dismiss() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 0
        }) {
            p.orderOut(nil)
            if panel === p { panel = nil }
        }
    }
}
