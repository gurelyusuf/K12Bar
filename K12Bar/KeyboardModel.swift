import Foundation
import Observation

/// Keyboard state shown in the menu. All HID callbacks arrive on the main run loop.
@Observable
final class KeyboardModel {
    private(set) var transport: HIDTransport.Transport?
    private(set) var battery: Int?
    private(set) var error: String?

    private let hid = HIDTransport()

    init() {
        hid.onTransportChange = { [weak self] transport in
            self?.transport = transport
            if transport != .bluetooth { self?.battery = nil }
        }
        hid.onBattery = { [weak self] level in
            self?.battery = level
        }
        do {
            try hid.start()
        } catch HIDTransport.StartError.inputMonitoringDenied {
            error = "Allow K12Bar in System Settings > Privacy & Security > Input Monitoring, then relaunch."
        } catch {
            self.error = "Could not open the keyboard: \(error)"
        }
    }
}
