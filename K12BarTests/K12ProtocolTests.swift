import XCTest
@testable import K12Bar

/// Byte fixtures come from USB captures of the Ninja71 software driving a Keychron K3 v2 (OpenRGB issue 1790).
final class K12ProtocolTests: XCTestCase {
    private func hex(_ string: String) -> [UInt8] {
        string.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    private func padded(_ string: String) -> [UInt8] {
        let bytes = hex(string)
        return bytes + [UInt8](repeating: 0, count: K12Protocol.pageSize - bytes.count)
    }

    func testWriteLEDPacketMatchesCapture() {
        XCTAssertEqual(K12Protocol.packet(.writeLED, pages: 18), padded("04 13 00 00 00 00 00 00 12"))
        XCTAssertEqual(K12Protocol.packet(.effectStart), padded("04 f0"))
    }

    func testAck() {
        XCTAssertTrue(K12Protocol.isAck(padded("04 13 00 01 00 00 00 00 12"), for: .writeLED))
        XCTAssertFalse(K12Protocol.isAck(padded("04 13 00 ff 00 00 00 00 12"), for: .writeLED))
        XCTAssertFalse(K12Protocol.isAck(padded("04 13 00 01"), for: .end))
        XCTAssertFalse(K12Protocol.isAck([], for: .end))
    }

    func testChecksum() {
        XCTAssertEqual(K12Protocol.checksum(of: hex("01 ff 00 00 00 00 00 00 00 10 0c 00 00 00 aa 55")), 0x21B)
        XCTAssertEqual(K12Protocol.checksum(inEndResponse: padded("04 02 00 01 d4 bf 00 00")), 0xBFD4)
        XCTAssertNil(K12Protocol.checksum(inEndResponse: padded("04 02 00 ff d4 bf 00 00")))
    }

    func testEffectRoundTripsCapturedUnits() throws {
        let staticRed = hex("01 ff 00 00 00 00 00 00 00 10 0c 00 00 00 aa 55")
        let effect = try XCTUnwrap(K12Protocol.Effect(bytes: staticRed))
        XCTAssertEqual(effect, .init(mode: 1, red: 0xFF, green: 0, blue: 0, fullColor: false, brightness: 16, speed: 12, direction: 0))
        XCTAssertEqual(effect.bytes, staticRed)

        let rainbowRolling = hex("0b 00 00 ff 00 00 00 00 01 10 01 00 00 00 aa 55")
        let rolling = try XCTUnwrap(K12Protocol.Effect(bytes: rainbowRolling))
        XCTAssertTrue(rolling.fullColor)
        XCTAssertEqual(rolling.speed, 1)
        XCTAssertEqual(rolling.bytes, rainbowRolling)

        let scrollingDown = hex("0a 00 00 ff 00 00 00 00 00 10 0c 03 00 00 aa 55")
        XCTAssertEqual(K12Protocol.Effect(bytes: scrollingDown)?.direction, 3)
    }

    func testEffectRejectsBadInput() {
        XCTAssertNil(K12Protocol.Effect(bytes: hex("01 ff 00 00 00 00 00 00 00 10 0c 00 00 00 00 00")))
        XCTAssertNil(K12Protocol.Effect(bytes: hex("01 ff 00")))
    }

    func testZoneOnlyChangesActiveEffect() throws {
        let original = [UInt8](repeating: 0x80, count: K12Protocol.ledZonePages * K12Protocol.pageSize)
        let effect = K12Protocol.Effect(mode: 7, red: 1, green: 2, blue: 3, fullColor: false, brightness: 8, speed: 4, direction: 0)
        let zone = try XCTUnwrap(K12Protocol.zone(original, settingActiveEffect: effect))

        XCTAssertEqual(K12Protocol.activeEffect(inZone: zone), effect)
        XCTAssertEqual(Array(zone[..<K12Protocol.activeEffectOffset]), Array(original[..<K12Protocol.activeEffectOffset]))
        XCTAssertEqual(Array(zone[(K12Protocol.activeEffectOffset + 16)...]), Array(original[(K12Protocol.activeEffectOffset + 16)...]))
        XCTAssertNil(K12Protocol.zone([0, 1, 2], settingActiveEffect: effect))
        XCTAssertNil(K12Protocol.activeEffect(inZone: [0, 1, 2]))
    }
}
