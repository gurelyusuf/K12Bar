import Foundation

/// Runs protocol transactions over the keyboard's single 64 byte feature report buffer.
///
/// The firmware handles a SET in its main loop and overwrites the buffer with the reply, so a GET
/// that comes too early returns the command unchanged (status 0). It also remembers that a GET
/// happened: after the GET that follows `end`, the next read command skips its status reply and
/// returns the first data page straight away. Both cases are handled here.
struct K12Session {
    enum Failure: Error, Equatable {
        case noReply(command: UInt8)
        case notAcknowledged(command: UInt8, response: [UInt8])
        case checksumMismatch(expected: UInt32, got: UInt32?)
        case wrongSize(Int)
    }

    let send: ([UInt8]) throws -> Void
    let receive: () throws -> [UInt8]
    /// Time for the firmware main loop to pick up a report.
    var pause: () -> Void = { Thread.sleep(forTimeInterval: 0.02) }

    /// Sends a command and returns the first reply that is not the unprocessed command itself.
    private func exchange(_ command: K12Protocol.Command, pages: Int = 0) throws -> [UInt8] {
        let packet = K12Protocol.packet(command, pages: pages)
        try send(packet)
        for _ in 0..<25 {
            pause()
            let response = try receive()
            if response != packet { return response }
        }
        throw Failure.noReply(command: command.rawValue)
    }

    private func acknowledged(_ command: K12Protocol.Command, pages: Int = 0) throws -> [UInt8] {
        let response = try exchange(command, pages: pages)
        guard K12Protocol.isAck(response, for: command) else {
            throw Failure.notAcknowledged(command: command.rawValue, response: Array(response.prefix(16)))
        }
        return response
    }

    private func end(expecting data: [UInt8]) throws {
        let expected = K12Protocol.checksum(of: data)
        let got = K12Protocol.checksum(inEndResponse: try acknowledged(.end))
        guard got == expected else { throw Failure.checksumMismatch(expected: expected, got: got) }
    }

    /// Reads `pages` 64 byte pages. Read-only on the keyboard. The checksum in the `end` reply
    /// proves the pages were lined up correctly.
    func read(_ command: K12Protocol.Command, pages: Int) throws -> [UInt8] {
        let first = try exchange(command, pages: pages)
        var data: [UInt8] = []
        if !K12Protocol.isAck(first, for: command) {
            guard first.count == K12Protocol.pageSize, first.prefix(2) != [0x04, command.rawValue] else {
                throw Failure.notAcknowledged(command: command.rawValue, response: Array(first.prefix(16)))
            }
            data = first
        }
        while data.count < pages * K12Protocol.pageSize {
            pause()
            data += try receive()
        }
        try end(expecting: data)
        return data
    }

    /// Programs the whole LED zone into the keyboard's flash, which applies its last page at once,
    /// then saves the applied lighting. The firmware programs every report it gets after the
    /// command, so nothing else may be sent until all pages are out.
    func writeLEDZone(_ zone: [UInt8]) throws {
        guard zone.count == K12Protocol.ledZonePages * K12Protocol.pageSize else { throw Failure.wrongSize(zone.count) }
        _ = try acknowledged(.writeLED, pages: K12Protocol.ledZonePages)
        for start in stride(from: 0, to: zone.count, by: K12Protocol.pageSize) {
            try send(Array(zone[start..<start + K12Protocol.pageSize]))
            pause()
        }
        try end(expecting: zone)
        _ = try acknowledged(.effectStart)
    }
}
