import Foundation
import Observation
import ServiceManagement
import os

/// Keyboard state shown in the menu. All HID callbacks arrive on the main run loop.
@Observable
final class KeyboardModel {
    var transport: HIDTransport.Transport?
    var battery: Int?
    private(set) var error: String?
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled

    var remaps: [KeyRemap.Pair] {
        didSet {
            defaults.set(try? JSONEncoder().encode(remaps), forKey: Self.remapsKey)
            applyRemaps()
        }
    }

    struct Preset: Codable, Identifiable {
        var id = UUID()
        var name: String
        var effect: K12Protocol.Effect
    }

    /// Lighting shown in the menu; every change is written to the keyboard shortly after.
    /// The keyboard cannot report lighting changed with its own keys, so this starts from the last host write.
    var lighting = K12Protocol.Effect(mode: 1, red: 255, green: 255, blue: 255, fullColor: false, brightness: 16, speed: 8, direction: 0) {
        didSet { if lighting != oldValue { scheduleApply() } }
    }
    private var pendingApply: DispatchWorkItem?
    var presets: [Preset] {
        didSet { defaults.set(try? JSONEncoder().encode(presets), forKey: Self.presetsKey) }
    }
    /// Last LED zone read from the keyboard; writes modify a copy of it. Nil unless connected by cable.
    var ledZone: [UInt8]?
    var canControlLighting: Bool { ledZone != nil }
    /// True when a cable-connected keyboard runs a firmware other than the one this app can write to.
    private(set) var unsupportedFirmware = false

    private static let presetsKey = "presets"

    private let log = Logger(subsystem: "com.gurel.K12Bar", category: "model")
    private static let remapsKey = "remaps"
    private let hid = HIDTransport()
    private var lowBattery = LowBatteryAlert()
    private var batteryTimer: Timer?

    /// True once the keyboard devices could be opened (Input Monitoring granted).
    private var opened = false
    private let defaults: UserDefaults
    /// False in unit tests, which are hosted by the app and must never touch the keyboard or `hidutil`.
    private let live: Bool

    init(defaults: UserDefaults = .standard,
         live: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil) {
        self.defaults = defaults
        self.live = live
        let saved = defaults.data(forKey: Self.remapsKey)
        remaps = saved.flatMap { try? JSONDecoder().decode([KeyRemap.Pair].self, from: $0) } ?? []
        let savedPresets = defaults.data(forKey: Self.presetsKey)
        presets = savedPresets.flatMap { try? JSONDecoder().decode([Preset].self, from: $0) } ?? []

        hid.onTransportChange = { [weak self] transport in
            guard let self else { return }
            self.transport = transport
            if transport != .bluetooth { battery = nil }
            if transport != nil, !remaps.isEmpty { applyRemaps() }
            if transport == .usb { loadLighting() } else { ledZone = nil; unsupportedFirmware = false }
        }
        hid.onBattery = { [weak self] level in
            guard let self else { return }
            battery = level
            if lowBattery.shouldAlert(level: level) { LowBatteryAlert.notify(level: level) }
        }
        guard live else { return }
        do {
            try hid.start()
            opened = true
        } catch HIDTransport.StartError.inputMonitoringDenied {
            error = "Allow K12Bar in System Settings > Privacy & Security > Input Monitoring, then relaunch."
        } catch {
            self.error = "Could not open the keyboard: \(error)"
        }
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.hid.refreshBattery()
        }
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = "Could not change launch at login: \(error.localizedDescription)"
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    private var session: K12Session { K12Session(send: hid.sendFeature, receive: hid.receiveFeature) }

    /// Reads the LED zone from the keyboard. Sends read commands only.
    private func loadLighting() {
        // Without Input Monitoring the keyboard is listed but not open; keep that message on screen.
        guard opened, ledZone == nil, hid.hasFeatureChannel else { return }
        do {
            let info = try session.read(.readInfo, pages: 2)
            unsupportedFirmware = Array(info[4...9]) != K12Protocol.supportedDeviceInfo
            guard !unsupportedFirmware else { return }
            let zone = try session.read(.readLED, pages: K12Protocol.ledZonePages)
            try backUp(zone)
            ledZone = zone
            if let stored = K12Protocol.activeEffect(inZone: zone), K12Protocol.Effect.modes.contains(stored.mode), stored.brightness > 0 {
                lighting = stored
            }
        } catch {
            log.error("lighting read failed: \(String(describing: error), privacy: .public)")
            self.error = "Could not read the lighting data: \(error)"
        }
    }

    /// Every write is a flash write cycle, so a drag on a slider or the color wheel becomes one write
    /// once the value has been still for a moment.
    private func scheduleApply() {
        pendingApply?.cancel()
        let apply = DispatchWorkItem { [weak self] in self?.applyLighting() }
        pendingApply = apply
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: apply)
    }

    /// Writes `lighting` to the keyboard's flash unless the keyboard already holds it.
    private func applyLighting() {
        guard live, let zone = ledZone, K12Protocol.activeEffect(inZone: zone) != lighting,
              let updated = K12Protocol.zone(zone, settingActiveEffect: lighting) else { return }
        do {
            try session.writeLEDZone(updated)
            ledZone = updated
            error = nil
        } catch {
            // A failed transfer can leave the firmware waiting for more pages; only a power cycle resets it.
            ledZone = nil
            log.error("lighting write failed: \(String(describing: error), privacy: .public)")
            self.error = "Lighting was not applied (\(error)). Unplug the keyboard, plug it back in and try again."
        }
    }

    func savePreset(named name: String) {
        presets.append(Preset(name: name, effect: lighting))
    }

    func apply(_ preset: Preset) {
        lighting = preset.effect
    }

    /// Keeps the first LED zone ever read, so the factory lighting data can be restored.
    private func backUp(_ zone: [UInt8]) throws {
        let folder = URL.applicationSupportDirectory.appending(path: "K12Bar")
        let file = folder.appending(path: "led-zone-backup.bin")
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(zone).write(to: file)
    }

    private func applyRemaps() {
        guard live, transport != nil else { return }
        do {
            try KeyRemap.apply(remaps)
        } catch {
            self.error = "Could not apply the key remap: \(error)"
        }
    }
}
