import Foundation
import Observation
import ServiceManagement

/// Keyboard state shown in the menu. All HID callbacks arrive on the main run loop.
@Observable
final class KeyboardModel {
    private(set) var transport: HIDTransport.Transport?
    private(set) var battery: Int?
    private(set) var error: String?
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled

    var remaps: [KeyRemap.Pair] {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(remaps), forKey: Self.remapsKey)
            applyRemaps()
        }
    }

    private static let remapsKey = "remaps"
    private let hid = HIDTransport()
    private var lowBattery = LowBatteryAlert()
    private var batteryTimer: Timer?

    init() {
        let saved = UserDefaults.standard.data(forKey: Self.remapsKey)
        remaps = saved.flatMap { try? JSONDecoder().decode([KeyRemap.Pair].self, from: $0) } ?? []

        hid.onTransportChange = { [weak self] transport in
            guard let self else { return }
            self.transport = transport
            if transport != .bluetooth { battery = nil }
            if transport != nil, !remaps.isEmpty { applyRemaps() }
        }
        hid.onBattery = { [weak self] level in
            guard let self else { return }
            battery = level
            if lowBattery.shouldAlert(level: level) { LowBatteryAlert.notify(level: level) }
        }
        do {
            try hid.start()
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

    private func applyRemaps() {
        guard transport != nil else { return }
        do {
            try KeyRemap.apply(remaps)
        } catch {
            self.error = "Could not apply the key remap: \(error)"
        }
    }
}
