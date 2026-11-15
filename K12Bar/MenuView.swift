import SwiftUI

struct MenuView: View {
    let model: KeyboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keychron K12").font(.headline)
            if let error = model.error {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("Connection", value: model.transport?.rawValue ?? "Not connected")
            LabeledContent("Battery", value: model.battery.map { "\($0)%" } ?? "—")
            Divider()
            Button("Quit K12Bar") { NSApplication.shared.terminate(nil) }
        }
        .padding()
        .frame(width: 260)
    }
}
