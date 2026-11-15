import SwiftUI
import XCTest
@testable import K12Bar

/// Renders the menu off screen so its layout can be looked at without the keyboard.
/// The PNG paths are printed in the test log.
final class MenuSnapshotTests: XCTestCase {
    private func render(_ model: KeyboardModel, name: String) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: MenuView(model: model).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let url = FileManager.default.temporaryDirectory.appending(path: "K12Bar-\(name).png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        print("snapshot: \(url.path)")
        return bitmap
    }

    /// A model that keeps its settings out of the app's real preferences.
    private func makeModel() throws -> KeyboardModel {
        let suite = "K12BarTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return KeyboardModel(defaults: defaults, live: false)
    }

    func testMenuOnCableShowsLightingControls() throws {
        let model = try makeModel()
        model.transport = .usb
        model.lighting.mode = 11
        model.ledZone = [UInt8](repeating: 0, count: K12Protocol.ledZonePages * K12Protocol.pageSize)
        model.presets = [.init(name: "Work", effect: model.lighting), .init(name: "Night", effect: model.lighting)]
        model.remaps = [.init(from: 0x39, to: 0x29)]

        let bitmap = try render(model, name: "cable")
        XCTAssertGreaterThan(bitmap.pixelsHigh, 400)
    }

    func testMenuOnBluetoothShowsBattery() throws {
        let model = try makeModel()
        model.transport = .bluetooth
        model.battery = 56

        let bitmap = try render(model, name: "bluetooth")
        XCTAssertGreaterThan(bitmap.pixelsHigh, 200)
    }
}
