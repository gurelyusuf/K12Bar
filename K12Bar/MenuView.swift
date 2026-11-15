import SwiftUI

struct MenuView: View {
    @Bindable var model: KeyboardModel
    @State private var presetName = ""
    /// Hue and saturation are kept here because RGB alone loses the hue at low saturation.
    @State private var hue = 0.0
    @State private var saturation = 1.0
    @State private var showsShortcuts = false

    private static let labelWidth: CGFloat = 76
    private static let swatches: [(name: String, hue: Double, saturation: Double)] = [
        ("Red", 0, 1), ("Orange", 0.08, 1), ("Yellow", 0.16, 1), ("Green", 0.33, 1), ("Cyan", 0.5, 1),
        ("Blue", 0.62, 1), ("Purple", 0.76, 1), ("Pink", 0.9, 1), ("White", 0, 0),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            card("Lighting", icon: "light.max", accessory: { lightingSwitch }) { lighting }
            card("Key Remap", icon: "arrow.left.arrow.right") { remapEditor }
            card("Keyboard Shortcuts", icon: "command", accessory: {
                Button(showsShortcuts ? "Hide" : "Show", systemImage: showsShortcuts ? "chevron.up" : "chevron.down") {
                    showsShortcuts.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }) {
                if showsShortcuts { shortcuts }
            }
            footer
        }
        .padding(12)
        .frame(width: 340)
        .onAppear(perform: syncColor)
        .onChange(of: [model.lighting.red, model.lighting.green, model.lighting.blue]) { syncColor() }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Keychron K12").font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(model.transport == nil ? Color.secondary : .green).frame(width: 7, height: 7)
                    Text(model.transport.map { "Connected via \($0.rawValue)" } ?? "Not connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            battery
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var battery: some View {
        if let level = model.battery {
            Label("\(level)%", systemImage: batterySymbol(level))
                .font(.callout.monospacedDigit())
                .foregroundStyle(level <= LowBatteryAlert.threshold ? .red : .primary)
        } else if model.transport == .usb {
            Label("On cable", systemImage: "cable.connector")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("The battery level is only reported over Bluetooth.")
        }
    }

    private func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Launch at login", isOn: Binding(get: { model.launchesAtLogin }, set: model.setLaunchesAtLogin))
                .toggleStyle(.checkbox)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.small)
        .padding(.horizontal, 4)
    }

    // MARK: Building blocks

    private func card<Accessory: View, Content: View>(
        _ title: String, icon: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                accessory()
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    /// A row whose label column has a fixed width, so all controls line up.
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label).frame(width: Self.labelWidth, alignment: .leading)
            content()
        }
    }

    private func levelRow(_ label: String, value: Binding<UInt8>, range: ClosedRange<Double>) -> some View {
        row(label) {
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = UInt8($0.rounded()) }), in: range)
            Text("\(value.wrappedValue)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
        }
    }

    // MARK: Lighting

    @ViewBuilder
    private var lightingSwitch: some View {
        if model.canControlLighting {
            Toggle("Backlight", isOn: Binding(
                get: { model.lighting.brightness > 0 },
                set: { model.lighting.brightness = $0 ? 16 : 0 }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }

    @ViewBuilder
    private var lighting: some View {
        if model.canControlLighting {
            row("Effect") {
                Picker("Effect", selection: $model.lighting.mode) {
                    ForEach(Array(K12Protocol.Effect.modes), id: \.self) { mode in
                        Text(K12Protocol.Effect.name(of: mode)).tag(mode)
                    }
                }
                .labelsHidden()
            }
            if model.lighting.usesColor {
                row("Color") {
                    Picker("Color", selection: $model.lighting.fullColor) {
                        Text("Single").tag(false)
                        Text("Rainbow").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                if !model.lighting.fullColor { colorPicker }
            }
            levelRow("Brightness", value: $model.lighting.brightness, range: 0...16)
            if model.lighting.hasSpeed {
                levelRow("Speed", value: $model.lighting.speed, range: 1...16)
            }
            if model.lighting.hasDirection {
                row("Direction") {
                    Picker("Direction", selection: $model.lighting.direction) {
                        Text("Forward").tag(UInt8(0))
                        Text("Reverse").tag(UInt8(1))
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
            Divider()
            presets
        } else {
            Text(model.transport == .bluetooth
                 ? "Lighting can only be changed over the cable. Plug it in and switch the keyboard to Cable."
                 : "Connect the keyboard with the cable to change lighting.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Self.swatches, id: \.name) { swatch in
                    let selected = abs(swatch.hue - hue) < 0.02 && abs(swatch.saturation - saturation) < 0.02
                    Button {
                        hue = swatch.hue
                        saturation = swatch.saturation
                        pushColor()
                    } label: {
                        Circle()
                            .fill(Color(hue: swatch.hue, saturation: swatch.saturation, brightness: 1))
                            .overlay(Circle().strokeBorder(.primary.opacity(0.25)))
                            .frame(width: 20, height: 20)
                            .padding(3)
                            .overlay(Circle().strokeBorder(.tint, lineWidth: selected ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .help(swatch.name)
                    .accessibilityLabel(swatch.name)
                    if swatch.name != Self.swatches.last?.name { Spacer(minLength: 0) }
                }
            }
            row("Hue") {
                GradientBar(value: $hue, colors: stride(from: 0.0, through: 1.0, by: 0.1).map { Color(hue: $0, saturation: 1, brightness: 1) },
                            thumb: Color(hue: hue, saturation: 1, brightness: 1), label: "Hue", onChange: pushColor)
            }
            row("Saturation") {
                GradientBar(value: $saturation, colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)],
                            thumb: Color(hue: hue, saturation: saturation, brightness: 1), label: "Saturation", onChange: pushColor)
            }
        }
    }

    private func pushColor() {
        guard let rgb = NSColor(hue: hue, saturation: saturation, brightness: 1, alpha: 1).usingColorSpace(.sRGB) else { return }
        model.lighting.red = UInt8((rgb.redComponent * 255).rounded())
        model.lighting.green = UInt8((rgb.greenComponent * 255).rounded())
        model.lighting.blue = UInt8((rgb.blueComponent * 255).rounded())
    }

    /// Takes hue and saturation from the model when it changed from outside (keyboard read, preset).
    private func syncColor() {
        let current = NSColor(srgbRed: CGFloat(model.lighting.red) / 255, green: CGFloat(model.lighting.green) / 255,
                              blue: CGFloat(model.lighting.blue) / 255, alpha: 1)
        guard let mine = NSColor(hue: hue, saturation: saturation, brightness: 1, alpha: 1).usingColorSpace(.sRGB),
              abs(mine.redComponent - current.redComponent) + abs(mine.greenComponent - current.greenComponent)
                + abs(mine.blueComponent - current.blueComponent) > 0.02 else { return }
        saturation = current.saturationComponent
        if saturation > 0.01 { hue = current.hueComponent }
    }

    @ViewBuilder
    private var presets: some View {
        if !model.presets.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.presets) { preset in
                        HStack(spacing: 4) {
                            Button(preset.name) { model.apply(preset) }
                                .buttonStyle(.plain)
                            Button("Delete \(preset.name)", systemImage: "xmark") {
                                model.presets.removeAll { $0.id == preset.id }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
        HStack {
            TextField("Save current lighting as…", text: $presetName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(savePreset)
            Button("Save", action: savePreset)
                .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .controlSize(.small)
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.savePreset(named: name)
        presetName = ""
    }

    // MARK: Remap

    @ViewBuilder
    private var remapEditor: some View {
        if model.remaps.isEmpty {
            Text("Swap keys on this Mac only. Nothing is written to the keyboard.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach($model.remaps) { $pair in
            HStack(spacing: 6) {
                keyPicker($pair.from)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                keyPicker($pair.to)
                Button("Remove", systemImage: "minus.circle.fill") {
                    model.remaps.removeAll { $0.id == pair.id }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        HStack {
            Button("Add Remap", systemImage: "plus") { model.remaps.append(.init(from: 0x39, to: 0x29)) }
            Spacer()
            if !model.remaps.isEmpty {
                Button("Reset") { model.remaps = [] }
            }
        }
        .controlSize(.small)
    }

    private func keyPicker(_ usage: Binding<Int>) -> some View {
        Picker("Key", selection: usage) {
            ForEach(KeyRemap.keys, id: \.usage) { key in
                Text(key.name).tag(key.usage)
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    // MARK: Shortcuts

    /// Features the firmware only offers through its own key combinations.
    private var shortcuts: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
            shortcut("Next light effect", "fn1 + light key")
            shortcut("Backlight on/off", "fn2 + light key")
            shortcut("Change color", "fn2 + ← / →")
            shortcut("Multimedia keys", "fn1 + number row")
            shortcut("F1 – F12", "fn2 + number row")
            shortcut("Disable auto sleep", "fn2 + S + O, hold 4 s")
            shortcut("Factory reset", "fn1 + J + Z, hold 3 s")
        }
        .font(.callout)
    }

    private func shortcut(_ name: String, _ keys: String) -> some View {
        GridRow {
            Text(name)
            Text(keys).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
        }
    }
}

/// A draggable 0...1 value on a gradient track.
private struct GradientBar: View {
    @Binding var value: Double
    let colors: [Color]
    let thumb: Color
    let label: String
    let onChange: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            Capsule()
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .overlay(Capsule().strokeBorder(.primary.opacity(0.15)))
                .frame(height: 10)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(thumb)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .shadow(radius: 1)
                        .frame(width: 16, height: 16)
                        .offset(x: value * (width - 16))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    value = min(max((drag.location.x - 8) / (width - 16), 0), 1)
                    onChange()
                })
        }
        .frame(height: 18)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            value = min(max(value + (direction == .increment ? 0.05 : -0.05), 0), 1)
            onChange()
        }
    }
}
