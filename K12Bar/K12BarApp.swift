import SwiftUI

@main
struct K12BarApp: App {
    @State private var model = KeyboardModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            if let battery = model.battery {
                Label("\(battery)%", systemImage: "keyboard").labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "keyboard")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
