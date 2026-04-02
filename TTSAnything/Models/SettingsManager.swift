import Foundation
import Carbon
import AppKit

enum Voice: String, CaseIterable, Identifiable {
    case alloy, echo, fable, onyx, nova, shimmer

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

struct Hotkey: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if modifiers & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 { carbon |= UInt32(cmdKey) }
        if modifiers & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 { carbon |= UInt32(optionKey) }
        if modifiers & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 { carbon |= UInt32(shiftKey) }
        if modifiers & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 { carbon |= UInt32(controlKey) }
        return carbon
    }

    var displayKeys: [String] {
        var keys: [String] = []
        if modifiers & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 { keys.append("⌃") }
        if modifiers & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 { keys.append("⌥") }
        if modifiers & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 { keys.append("⇧") }
        if modifiers & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 { keys.append("⌘") }
        keys.append(Self.keyName(for: keyCode))
        return keys
    }

    static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
            0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
            0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
            0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
            0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M",
            0x2F: ".", 0x31: " ", 0x32: "`",
            0x24: "↩", 0x30: "⇥", 0x33: "⌫", 0x35: "⎋",
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
            0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
            0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        ]
        return names[keyCode] ?? "?"
    }

    static let `default` = Hotkey(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(NSEvent.ModifierFlags.option.rawValue))
}

class SettingsManager: ObservableObject {
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: "apiKey") }
    }
    @Published var selectedVoice: Voice {
        didSet { UserDefaults.standard.set(selectedVoice.rawValue, forKey: "selectedVoice") }
    }
    @Published var playbackSpeed: Double {
        didSet { UserDefaults.standard.set(playbackSpeed, forKey: "playbackSpeed") }
    }
    @Published var hotkey: Hotkey {
        didSet {
            UserDefaults.standard.set(Int(hotkey.keyCode), forKey: "hotkeyKeyCode")
            UserDefaults.standard.set(Int(hotkey.modifiers), forKey: "hotkeyModifiers")
            onHotkeyChanged?()
        }
    }

    var onHotkeyChanged: (() -> Void)?

    var isConfigured: Bool { !apiKey.isEmpty }

    init() {
        let savedKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        let savedVoice = UserDefaults.standard.string(forKey: "selectedVoice") ?? ""
        let savedSpeed = UserDefaults.standard.double(forKey: "playbackSpeed")

        self.apiKey = savedKey
        self.selectedVoice = Voice(rawValue: savedVoice) ?? .nova
        self.playbackSpeed = savedSpeed > 0 ? savedSpeed : 1.5

        let savedKeyCode = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        let savedModifiers = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        if savedModifiers != 0 {
            self.hotkey = Hotkey(keyCode: UInt32(savedKeyCode), modifiers: UInt32(savedModifiers))
        } else {
            self.hotkey = .default
        }

        if self.apiKey.isEmpty {
            self.apiKey = Self.readOutloudAPIKey() ?? ""
        }
    }

    private static func readOutloudAPIKey() -> String? {
        let path = NSString("~/.config/outloud.env").expandingTildeInPath
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("OPENAI_API_KEY=") {
                let value = String(trimmed.dropFirst("OPENAI_API_KEY=".count))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }
}
