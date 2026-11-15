import Foundation
import IOKit.hid
import os

/// Finds the Keychron K12 and reads its HID reports.
/// The keyboard presents itself as Apple 05AC:024F on both USB and Bluetooth.
final class HIDTransport {
    enum Transport: String {
        case usb = "USB"
        case bluetooth = "Bluetooth"
    }

    enum StartError: Error {
        case inputMonitoringDenied
        case openFailed(IOReturn)
    }

    var onTransportChange: ((Transport?) -> Void)?
    var onBattery: ((Int) -> Void)?

    /// Input report carrying Battery Strength (0...100) in the Bluetooth descriptor.
    private static let batteryReportID: UInt32 = 0x03

    private let log = Logger(subsystem: "com.gurel.K12Bar", category: "hid")
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var devices: [IOHIDDevice] = []

    func start() throws {
        let matching = [kIOHIDVendorIDKey: 0x05AC, kIOHIDProductIDKey: 0x024F]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<HIDTransport>.fromOpaque(context!).takeUnretainedValue().attached(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<HIDTransport>.fromOpaque(context!).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { context, _, _, _, reportID, report, length in
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            Unmanaged<HIDTransport>.fromOpaque(context!).takeUnretainedValue().received(reportID, bytes)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        // Opening a keyboard needs Input Monitoring; this shows the system prompt the first time.
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnNotPermitted { throw StartError.inputMonitoringDenied }
        guard result == kIOReturnSuccess else { throw StartError.openFailed(result) }
    }

    private func attached(_ device: IOHIDDevice) {
        devices.append(device)
        let transport = transport(of: device)
        log.info("attached over \(transport?.rawValue ?? "unknown transport", privacy: .public)")
        onTransportChange?(transport)
        if transport == .bluetooth { pollBattery(device) }
    }

    private func removed(_ device: IOHIDDevice) {
        devices.removeAll { $0 == device }
        onTransportChange?(devices.first.flatMap(transport(of:)))
    }

    private func transport(of device: IOHIDDevice) -> Transport? {
        guard let name = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String else { return nil }
        return name.hasPrefix("Bluetooth") ? .bluetooth : name == "USB" ? .usb : nil
    }

    enum ReportError: Error {
        case noFeatureChannel
        case failed(IOReturn)
    }

    /// USB interface 0 exposes one unnumbered 64 byte feature report: the lighting protocol channel.
    private var featureDevice: IOHIDDevice? {
        devices.first { (IOHIDDeviceGetProperty($0, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int ?? 0) >= K12Protocol.pageSize }
    }

    var hasFeatureChannel: Bool { featureDevice != nil }

    func sendFeature(_ bytes: [UInt8]) throws {
        guard let device = featureDevice else { throw ReportError.noFeatureChannel }
        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, bytes, bytes.count)
        guard result == kIOReturnSuccess else { throw ReportError.failed(result) }
    }

    func receiveFeature() throws -> [UInt8] {
        guard let device = featureDevice else { throw ReportError.noFeatureChannel }
        var buffer = [UInt8](repeating: 0, count: K12Protocol.pageSize)
        var length = buffer.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, &buffer, &length)
        guard result == kIOReturnSuccess else { throw ReportError.failed(result) }
        return Array(buffer[..<length])
    }

    func refreshBattery() {
        devices.filter { transport(of: $0) == .bluetooth }.forEach(pollBattery)
    }

    /// Whether the keyboard pushes battery reports on its own is unverified, so the level is polled.
    private func pollBattery(_ device: IOHIDDevice) {
        var buffer = [UInt8](repeating: 0, count: 8)
        var length = buffer.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, CFIndex(Self.batteryReportID), &buffer, &length)
        guard result == kIOReturnSuccess else {
            log.info("battery poll failed: \(String(result, radix: 16), privacy: .public)")
            return
        }
        received(Self.batteryReportID, Array(buffer[..<length]))
    }

    /// `report` starts with the report ID byte.
    private func received(_ reportID: UInt32, _ report: [UInt8]) {
        guard reportID == Self.batteryReportID, report.count >= 2, report[1] <= 100 else { return }
        log.info("battery \(report[1])%")
        onBattery?(Int(report[1]))
    }
}
