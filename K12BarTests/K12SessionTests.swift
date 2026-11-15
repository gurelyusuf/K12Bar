import XCTest
@testable import K12Bar

/// Models the K12 V1.16 feature report state machine as recovered from the firmware:
/// one shared buffer, commands handled after a delay, a remembered GET that makes the next
/// read skip its status reply, and every report after a write command programmed as data.
private final class FakeKeyboard {
    private enum State { case idle, awaitingStatusGet, reading, writing, awaitingEnd }

    var zone: [UInt8]
    var info = [UInt8](repeating: 0x11, count: 2 * 64)
    /// GETs that still see the unprocessed command after each SET.
    var lag = 0
    var corruptChecksum = false
    private(set) var savedSettings = 0
    private(set) var reports: [[UInt8]] = []

    private var buffer = [UInt8](repeating: 0, count: 64)
    private var state = State.idle
    private var getRemembered = false
    private var pendingLag = 0
    private var transfer: [UInt8] = []
    private var writeCommand = false
    private var cursor = 0
    private var pagesLeft = 0
    private var sum: UInt32 = 0

    init(zone: [UInt8]) { self.zone = zone }

    func set(_ report: [UInt8]) {
        reports.append(report)
        buffer = report
        pendingLag = lag
        switch state {
        case .writing:
            zone.replaceSubrange(cursor..<cursor + 64, with: report)
            sum &+= K12Protocol.checksum(of: report)
            cursor += 64
            pagesLeft -= 1
            if pagesLeft == 0 { state = .awaitingEnd }
        case .awaitingEnd where report[0] == 4 && report[1] == 0x02:
            let value = corruptChecksum ? sum &+ 1 : sum
            buffer[3] = 1
            for index in 0..<4 { buffer[4 + index] = UInt8(value >> (8 * UInt32(index)) & 0xFF) }
            state = .idle
        case .idle where report[0] == 4:
            command(report[1], pages: Int(report[8]))
        default:
            buffer[3] = 0xFF
        }
    }

    private func command(_ code: UInt8, pages: Int) {
        buffer[3] = 1
        sum = 0
        cursor = 0
        pagesLeft = pages
        switch code {
        case 0x05: transfer = info; writeCommand = false
        case 0x12: transfer = zone; writeCommand = false
        case 0x13: writeCommand = true
        case 0xF0: savedSettings += 1; return
        default: buffer[3] = 0xFF; return
        }
        state = .awaitingStatusGet
        if getRemembered {
            getRemembered = false
            begin()
        }
    }

    private func begin() {
        if writeCommand {
            state = .writing
        } else {
            state = .reading
            loadPage()
        }
    }

    private func loadPage() {
        buffer = Array(transfer[cursor..<cursor + 64])
        sum &+= K12Protocol.checksum(of: buffer)
        cursor += 64
        pagesLeft -= 1
    }

    func get() -> [UInt8] {
        if pendingLag > 0 {
            pendingLag -= 1
            return reports.last!
        }
        let reply = buffer
        switch state {
        case .awaitingStatusGet: begin()
        case .reading: if pagesLeft > 0 { loadPage() } else { state = .awaitingEnd }
        case .idle: getRemembered = true
        case .writing, .awaitingEnd: break
        }
        return reply
    }
}

final class K12SessionTests: XCTestCase {
    private let zone = (0..<K12Protocol.ledZonePages * K12Protocol.pageSize).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 1) }

    private func session(_ keyboard: FakeKeyboard) -> K12Session {
        K12Session(send: keyboard.set, receive: keyboard.get, pause: {})
    }

    func testReadsWithAndWithoutStatusReply() throws {
        let keyboard = FakeKeyboard(zone: zone)
        // First read gets a status reply; its final GET makes the second read skip the status.
        XCTAssertEqual(try session(keyboard).read(.readInfo, pages: 2), keyboard.info)
        XCTAssertEqual(try session(keyboard).read(.readLED, pages: K12Protocol.ledZonePages), zone)
        XCTAssertEqual(try session(keyboard).read(.readLED, pages: K12Protocol.ledZonePages), zone)
    }

    func testReadWaitsForSlowFirmware() throws {
        let keyboard = FakeKeyboard(zone: zone)
        keyboard.lag = 3
        XCTAssertEqual(try session(keyboard).read(.readLED, pages: K12Protocol.ledZonePages), zone)
    }

    func testWriteProgramsExactlyTheZoneThenSaves() throws {
        let keyboard = FakeKeyboard(zone: [UInt8](repeating: 0, count: zone.count))
        _ = try session(keyboard).read(.readInfo, pages: 2)
        let before = keyboard.reports.count
        try session(keyboard).writeLEDZone(zone)

        XCTAssertEqual(keyboard.zone, zone)
        XCTAssertEqual(keyboard.savedSettings, 1)
        let sent = Array(keyboard.reports[before...])
        XCTAssertEqual(sent.count, 1 + K12Protocol.ledZonePages + 2)
        XCTAssertEqual(sent.first, K12Protocol.packet(.writeLED, pages: K12Protocol.ledZonePages))
        XCTAssertEqual(sent.last, K12Protocol.packet(.effectStart))
    }

    func testWriteReportsChecksumMismatch() {
        let keyboard = FakeKeyboard(zone: zone)
        keyboard.corruptChecksum = true
        XCTAssertThrowsError(try session(keyboard).writeLEDZone(zone)) { error in
            guard case K12Session.Failure.checksumMismatch = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(keyboard.savedSettings, 0)
    }

    func testWriteRejectsWrongSizeBeforeSendingAnything() {
        let keyboard = FakeKeyboard(zone: zone)
        XCTAssertThrowsError(try session(keyboard).writeLEDZone([1, 2, 3]))
        XCTAssertTrue(keyboard.reports.isEmpty)
    }
}
