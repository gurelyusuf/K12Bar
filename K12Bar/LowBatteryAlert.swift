import Foundation
import UserNotifications
import os

/// Decides when to warn about a low battery: once per discharge, again only after the level recovered.
struct LowBatteryAlert {
    static let threshold = 20
    private var alerted = false

    mutating func shouldAlert(level: Int) -> Bool {
        if level > Self.threshold {
            alerted = false
            return false
        }
        defer { alerted = true }
        return !alerted
    }

    static func notify(level: Int) {
        let log = Logger(subsystem: "com.gurel.K12Bar", category: "alert")
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted else {
                log.error("notifications not allowed: \(error?.localizedDescription ?? "denied", privacy: .public)")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Keychron K12 battery low"
            content.body = "\(level)% remaining."
            center.add(UNNotificationRequest(identifier: "low-battery", content: content, trigger: nil)) { error in
                if let error { log.error("notification failed: \(error.localizedDescription, privacy: .public)") }
            }
        }
    }
}
