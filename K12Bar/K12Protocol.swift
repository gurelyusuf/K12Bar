import Foundation

/// Keychron "Game Keyboard Communication Protocol": 64 byte HID feature reports (report ID 0) over USB.
/// Layouts below were taken from USB captures of a K3 v2, not from the vendor PDF, which differs in places.
enum K12Protocol {
    static let pageSize = 64
    /// The LED zone is always transferred whole: 32 effect slots, per-key colors, then the active effect.
    static let ledZonePages = 18
    /// Offset of the active effect unit inside the LED zone (first bytes of the last page).
    static let activeEffectOffset = (ledZonePages - 1) * pageSize

    enum Command: UInt8 {
        case end = 0x02
        case readInfo = 0x05
        case readLED = 0x12
        case writeLED = 0x13
        case startCustomization = 0x18
        case stopCustomization = 0x19
        case effectStart = 0xF0
    }

    /// Command packet. `pages` is the number of 64 byte data pages that follow.
    static func packet(_ command: Command, pages: Int = 0) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: pageSize)
        packet[0] = 0x04
        packet[1] = command.rawValue
        packet[8] = UInt8(pages & 0xFF)
        packet[9] = UInt8(pages >> 8)
        return packet
    }

    /// The device echoes the command with status 0x01 when it accepts it (0xFF was seen when busy).
    static func isAck(_ response: [UInt8], for command: Command) -> Bool {
        response.count >= 4 && response[0] == 0x04 && response[1] == command.rawValue && response[3] == 0x01
    }

    /// The reply to `end` carries the sum of all data bytes of the transaction, little endian, in bytes 4...7.
    static func checksum(of data: [UInt8]) -> UInt32 {
        data.reduce(UInt32(0)) { $0 &+ UInt32($1) }
    }

    static func checksum(inEndResponse response: [UInt8]) -> UInt32? {
        guard isAck(response, for: .end), response.count >= 8 else { return nil }
        return response[4...7].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    /// One 16 byte lighting effect unit.
    struct Effect: Equatable {
        static let size = 16
        static let customMode: UInt8 = 0x80

        var mode: UInt8
        var red: UInt8
        var green: UInt8
        var blue: UInt8
        /// Rainbow colors instead of `red`/`green`/`blue`.
        var fullColor: Bool
        /// 1 (off) ... 16 (brightest).
        var brightness: UInt8
        /// 1 ... 16.
        var speed: UInt8
        /// 0/1 for horizontal effects, 2/3 for vertical ones.
        var direction: UInt8

        init(mode: UInt8, red: UInt8, green: UInt8, blue: UInt8, fullColor: Bool, brightness: UInt8, speed: UInt8, direction: UInt8) {
            self.mode = mode
            self.red = red
            self.green = green
            self.blue = blue
            self.fullColor = fullColor
            self.brightness = brightness
            self.speed = speed
            self.direction = direction
        }

        /// Fails when the unit does not end with the AA 55 marker.
        init?(bytes: [UInt8]) {
            guard bytes.count == Self.size, bytes[14] == 0xAA, bytes[15] == 0x55 else { return nil }
            self.init(mode: bytes[0], red: bytes[1], green: bytes[2], blue: bytes[3], fullColor: bytes[8] == 1,
                      brightness: bytes[9], speed: bytes[10], direction: bytes[11])
        }

        var bytes: [UInt8] {
            [mode, red, green, blue, 0, 0, 0, 0, fullColor ? 1 : 0, brightness, speed, direction, 0, 0, 0xAA, 0x55]
        }
    }

    /// The effect the keyboard is currently showing, read from a full LED zone.
    static func activeEffect(inZone zone: [UInt8]) -> Effect? {
        guard zone.count == ledZonePages * pageSize else { return nil }
        return Effect(bytes: Array(zone[activeEffectOffset..<activeEffectOffset + Effect.size]))
    }

    /// Returns the zone with only the active effect replaced. Nil when the zone has the wrong size.
    static func zone(_ zone: [UInt8], settingActiveEffect effect: Effect) -> [UInt8]? {
        guard zone.count == ledZonePages * pageSize else { return nil }
        var zone = zone
        zone.replaceSubrange(activeEffectOffset..<activeEffectOffset + Effect.size, with: effect.bytes)
        return zone
    }
}
