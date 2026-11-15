import SwiftUI

@main
struct K12BarApp: App {
    @State private var model = KeyboardModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
            if let battery = model.battery {
                Text("\(battery)%")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon: a compact keyboard with its keys cut out.
/// A template image, so macOS tints it for light and dark menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            NSColor.black.set()

            // Keyboard body.
            let body = NSRect(x: 1, y: 3.5, width: 20, height: 11)
            NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3).fill()

            // Keys are cut out of the body: two rows of six, then a space bar between two keys.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let key = 1.9, gap = 1.0, height = 1.75, left = 2.8
            for row in [11, 8.125] {
                for column in 0..<6 {
                    NSBezierPath(roundedRect: NSRect(x: left + Double(column) * (key + gap), y: row, width: key, height: height),
                                 xRadius: 0.5, yRadius: 0.5).fill()
                }
            }
            let spaceBar = 16.4 - 2 * (key + gap)
            for (x, width) in [(left, key), (left + key + gap, spaceBar), (left + key + gap + spaceBar + gap, key)] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 5.25, width: width, height: height), xRadius: 0.5, yRadius: 0.5).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "K12Bar"
        return image
    }()
}
