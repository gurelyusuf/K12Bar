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

/// The menu bar icon: a keycap with a K cut out of it. A template image, so macOS tints it.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let cap = rect.insetBy(dx: 1, dy: 1.5)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: cap, xRadius: 4, yRadius: 4).fill()

            let letter = NSAttributedString(string: "K", attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .heavy),
                .foregroundColor: NSColor.black,
            ])
            let letterSize = letter.size()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            letter.draw(at: NSPoint(x: cap.midX - letterSize.width / 2, y: cap.midY - letterSize.height / 2 + 0.5))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "K12Bar"
        return image
    }()
}
