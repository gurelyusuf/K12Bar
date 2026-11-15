import XCTest
@testable import K12Bar

final class SupportTests: XCTestCase {
    func testLowBatteryAlertsOncePerDischarge() {
        var alert = LowBatteryAlert()
        XCTAssertFalse(alert.shouldAlert(level: 56))
        XCTAssertTrue(alert.shouldAlert(level: 20))
        XCTAssertFalse(alert.shouldAlert(level: 15))
        XCTAssertFalse(alert.shouldAlert(level: 21))
        XCTAssertTrue(alert.shouldAlert(level: 19))
    }

    func testRemapProperty() throws {
        // Caps Lock (0x39) to Escape (0x29) on the keyboard usage page.
        let property = try KeyRemap.hidutilProperty(for: [.init(from: 0x39, to: 0x29)])
        XCTAssertEqual(property, #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingDst":30064771113,"HIDKeyboardModifierMappingSrc":30064771129}]}"#)
        XCTAssertEqual(try KeyRemap.hidutilProperty(for: []), #"{"UserKeyMapping":[]}"#)
    }

    func testRemapKeysAreUnique() {
        XCTAssertEqual(Set(KeyRemap.keys.map(\.usage)).count, KeyRemap.keys.count)
    }
}
