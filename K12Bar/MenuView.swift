import SwiftUI

struct MenuView: View {
    @Bindable var model: KeyboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keychron K12").font(.headline)
            if let error = model.error {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("Connection", value: model.transport?.rawValue ?? "Not connected")
            LabeledContent("Battery", value: model.battery.map { "\($0)%" } ?? "—")
            Divider()
            remapEditor
            Divider()
            Toggle("Launch at login", isOn: Binding(get: { model.launchesAtLogin }, set: model.setLaunchesAtLogin))
            Button("Quit K12Bar") { NSApplication.shared.terminate(nil) }
        }
        .padding()
        .frame(width: 300)
    }

    @ViewBuilder
    private var remapEditor: some View {
        Text("Key remap (this Mac only)").font(.subheadline)
        ForEach($model.remaps) { $pair in
            HStack {
                keyPicker($pair.from)
                Image(systemName: "arrow.right")
                keyPicker($pair.to)
                Button("Remove", systemImage: "minus.circle") {
                    model.remaps.removeAll { $0.id == pair.id }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        HStack {
            Button("Add") { model.remaps.append(.init(from: 0x39, to: 0x29)) }
            Button("Reset") { model.remaps = [] }.disabled(model.remaps.isEmpty)
        }
    }

    private func keyPicker(_ usage: Binding<Int>) -> some View {
        Picker("Key", selection: usage) {
            ForEach(KeyRemap.keys, id: \.usage) { key in
                Text(key.name).tag(key.usage)
            }
        }
        .labelsHidden()
    }
}
