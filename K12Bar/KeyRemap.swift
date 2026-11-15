import Foundation

/// Key remapping done by macOS (the `hidutil` UserKeyMapping property). Nothing is written to the keyboard.
/// The mapping is lost when the keyboard reconnects, so it is applied again on every connect.
enum KeyRemap {
    struct Pair: Codable, Equatable, Identifiable {
        var id = UUID()
        /// HID keyboard usages (usage page 0x07).
        var from: Int
        var to: Int
    }

    enum Failure: Error {
        case hidutilFailed(status: Int32, output: String)
    }

    /// Keys offered in the editor, as (name, HID keyboard usage).
    static let keys: [(name: String, usage: Int)] = {
        let letters = (0..<26).map { (String(UnicodeScalar(UInt8(65 + $0))), 0x04 + $0) }
        let digits = (0..<10).map { (String(($0 + 1) % 10), 0x1E + $0) }
        let functionKeys = (0..<12).map { ("F\($0 + 1)", 0x3A + $0) }
        let named: [(String, Int)] = [
            ("Return", 0x28), ("Escape", 0x29), ("Delete", 0x2A), ("Tab", 0x2B), ("Space", 0x2C),
            ("-", 0x2D), ("=", 0x2E), ("[", 0x2F), ("]", 0x30), ("\\", 0x31), (";", 0x33), ("'", 0x34),
            ("`", 0x35), (",", 0x36), (".", 0x37), ("/", 0x38), ("Caps Lock", 0x39),
            ("Right Arrow", 0x4F), ("Left Arrow", 0x50), ("Down Arrow", 0x51), ("Up Arrow", 0x52),
            ("Left Control", 0xE0), ("Left Shift", 0xE1), ("Left Option", 0xE2), ("Left Command", 0xE3),
            ("Right Control", 0xE4), ("Right Shift", 0xE5), ("Right Option", 0xE6), ("Right Command", 0xE7),
        ]
        return named + letters + digits + functionKeys
    }()

    /// The `--set` argument for hidutil. An empty list clears the mapping.
    static func hidutilProperty(for pairs: [Pair]) throws -> String {
        let keyboardPage = 0x7_0000_0000
        let mapping = pairs.map {
            ["HIDKeyboardModifierMappingSrc": keyboardPage | $0.from, "HIDKeyboardModifierMappingDst": keyboardPage | $0.to]
        }
        let data = try JSONSerialization.data(withJSONObject: ["UserKeyMapping": mapping], options: .sortedKeys)
        return String(decoding: data, as: UTF8.self)
    }

    static func apply(_ pairs: [Pair]) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = [
            "property", "--matching", #"{"VendorID":1452,"ProductID":591}"#,
            "--set", try hidutilProperty(for: pairs),
        ]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw Failure.hidutilFailed(status: process.terminationStatus, output: text)
        }
    }
}
