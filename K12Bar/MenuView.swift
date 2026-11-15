import SwiftUI

struct MenuView: View {
    @Bindable var model: KeyboardModel
    @State private var presetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keychron K12").font(.headline)
            if let error = model.error {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("Connection", value: model.transport?.rawValue ?? "Not connected")
            LabeledContent("Battery", value: model.battery.map { "\($0)%" } ?? (model.transport == .usb ? "Bluetooth only" : "—"))
            Divider()
            lighting
            Divider()
            remapEditor
            Divider()
            shortcuts
            Divider()
            Toggle("Launch at login", isOn: Binding(get: { model.launchesAtLogin }, set: model.setLaunchesAtLogin))
            Button("Quit K12Bar") { NSApplication.shared.terminate(nil) }
        }
        .padding()
        .frame(width: 320)
    }

    @ViewBuilder
    private var lighting: some View {
        Text("Lighting").font(.subheadline)
        if model.canControlLighting {
            Picker("Effect", selection: $model.lighting.mode) {
                ForEach(Array(K12Protocol.Effect.modes), id: \.self) { mode in
                    Text("Effect \(mode)").tag(mode)
                }
            }
            Toggle("Rainbow colors", isOn: $model.lighting.fullColor)
            ColorPicker("Color", selection: color, supportsOpacity: false).disabled(model.lighting.fullColor)
            slider("Brightness", value: $model.lighting.brightness, range: 0...16)
            slider("Speed", value: $model.lighting.speed, range: 1...16)
            Toggle("Reverse direction", isOn: Binding(
                get: { model.lighting.direction == 1 },
                set: { model.lighting.direction = $0 ? 1 : 0 }
            ))
            Button("Apply to keyboard") { model.applyLighting() }
            presets
        } else {
            Text(model.transport == .bluetooth
                 ? "Lighting can only be changed over the cable: plug it in and switch the keyboard to Cable."
                 : "Connect the keyboard with the cable to change lighting.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var presets: some View {
        ForEach(model.presets) { preset in
            HStack {
                Button(preset.name) { model.apply(preset) }
                Spacer()
                Button("Delete", systemImage: "minus.circle") {
                    model.presets.removeAll { $0.id == preset.id }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        HStack {
            TextField("Preset name", text: $presetName)
            Button("Save preset") {
                model.savePreset(named: presetName)
                presetName = ""
            }
            .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var color: Binding<Color> {
        Binding(
            get: {
                Color(red: Double(model.lighting.red) / 255, green: Double(model.lighting.green) / 255, blue: Double(model.lighting.blue) / 255)
            },
            set: { newValue in
                guard let rgb = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                model.lighting.red = UInt8((rgb.redComponent * 255).rounded())
                model.lighting.green = UInt8((rgb.greenComponent * 255).rounded())
                model.lighting.blue = UInt8((rgb.blueComponent * 255).rounded())
            }
        )
    }

    private func slider(_ title: String, value: Binding<UInt8>, range: ClosedRange<Double>) -> some View {
        Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = UInt8($0) }), in: range, step: 1) {
            Text(title)
        }
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

    /// Features the firmware only offers through its own key combinations.
    private var shortcuts: some View {
        DisclosureGroup("Keyboard-only shortcuts") {
            Grid(alignment: .leading, verticalSpacing: 4) {
                shortcut("Next light effect", "fn1 + light key")
                shortcut("Backlight on/off", "fn2 + light key")
                shortcut("Change color", "fn2 + ← / →")
                shortcut("Multimedia keys", "fn1 + number row")
                shortcut("F1 – F12", "fn2 + number row")
                shortcut("Disable auto sleep", "fn2 + S + O (4 s)")
                shortcut("Factory reset", "fn1 + J + Z (3 s)")
            }
            .font(.caption)
        }
    }

    private func shortcut(_ name: String, _ keys: String) -> some View {
        GridRow {
            Text(name)
            Text(keys).foregroundStyle(.secondary)
        }
    }
}
