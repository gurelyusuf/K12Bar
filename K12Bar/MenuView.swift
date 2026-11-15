import SwiftUI

struct MenuView: View {
    private enum Tab: String, CaseIterable {
        case lighting = "Lighting"
        case keys = "Keys"
    }

    @Bindable var model: KeyboardModel
    @State private var tab = Tab.lighting
    @State private var presetName = ""
    @State private var addingPreset = false
    /// Hue and saturation are kept here because RGB alone loses the hue at low saturation.
    @State private var hue = 0.0
    @State private var saturation = 1.0
    @State private var hex = ""

    private static let labelWidth: CGFloat = 80
    private static let swatches: [(name: String, hue: Double, saturation: Double)] = [
        ("Red", 0, 1), ("Orange", 0.08, 1), ("Yellow", 0.16, 1), ("Green", 0.33, 1), ("Cyan", 0.5, 1),
        ("Blue", 0.62, 1), ("Purple", 0.76, 1), ("Pink", 0.9, 1), ("White", 0, 0),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let error = model.error {
                Text(error)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Segments(label: "Section", selection: $tab, options: Tab.allCases.map { ($0.rawValue, $0) })
            switch tab {
            case .lighting: lighting
            case .keys: keys
            }
            Divider()
            HStack {
                Text("Launch at login")
                Spacer()
                Toggle("Launch at login", isOn: Binding(get: { model.launchesAtLogin }, set: model.setLaunchesAtLogin))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            Button("Quit K12Bar") { NSApplication.shared.terminate(nil) }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.body)
        .padding(16)
        .frame(width: 320)
        .onAppear(perform: syncColor)
        .onChange(of: [model.lighting.red, model.lighting.green, model.lighting.blue]) { syncColor() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Keychron K12").font(.headline)
                Text(model.transport.map { "Connected · \($0.rawValue)" } ?? "Not connected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let level = model.battery {
                Label("\(level)%", systemImage: batterySymbol(level))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(level <= LowBatteryAlert.threshold ? .red : .secondary)
            }
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

    // MARK: Building blocks

    /// A row whose label column has a fixed width, so all controls line up.
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: Self.labelWidth, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func levelRow(_ label: String, value: Binding<UInt8>, range: ClosedRange<Double>) -> some View {
        row(label) {
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = UInt8($0.rounded()) }), in: range) {
                Text(label)
            }
            .labelsHidden()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Lighting

    @ViewBuilder
    private var lighting: some View {
        if model.canControlLighting {
            row("Backlight") {
                Toggle("Backlight", isOn: Binding(
                    get: { model.lighting.brightness > 0 },
                    set: { model.lighting.brightness = $0 ? 16 : 0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            row("Effect") {
                Menu {
                    Picker("Effect", selection: $model.lighting.mode) {
                        ForEach(Array(K12Protocol.Effect.modes), id: \.self) { mode in
                            Text(K12Protocol.Effect.name(of: mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    HStack {
                        Text(K12Protocol.Effect.name(of: model.lighting.mode))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: Segments<Int>.height)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .accessibilityLabel("Effect")
                .accessibilityValue(K12Protocol.Effect.name(of: model.lighting.mode))
            }
            if model.lighting.usesColor {
                row("Color") {
                    Segments(label: "Color", selection: $model.lighting.fullColor, options: [("Single", false), ("Rainbow", true)])
                }
                if !model.lighting.fullColor { colorPicker }
            }
            levelRow("Brightness", value: $model.lighting.brightness, range: 0...16)
            if model.lighting.hasSpeed {
                levelRow("Speed", value: $model.lighting.speed, range: 1...16)
            }
            if model.lighting.hasDirection {
                row("Direction") {
                    Segments(label: "Direction", selection: $model.lighting.direction, options: [("Forward", 0), ("Reverse", 1)])
                }
            }
            Divider()
            presets
        } else {
            note(model.transport == .bluetooth
                 ? "Lighting can only be changed over the cable. Plug it in and switch the keyboard to Cable."
                 : "Connect the keyboard with the cable to change lighting.")
        }
    }

    private var colorPicker: some View {
        VStack(spacing: 10) {
            SpectrumPad(hue: $hue, saturation: $saturation, onChange: pushColor)
                .frame(height: 96)
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
                            .overlay(Circle().strokeBorder(.primary.opacity(0.2)))
                            .frame(width: 18, height: 18)
                            .padding(3)
                            .overlay(Circle().strokeBorder(.primary, lineWidth: selected ? 1.5 : 0))
                    }
                    .buttonStyle(.plain)
                    .help(swatch.name)
                    .accessibilityLabel(swatch.name)
                    Spacer(minLength: 0)
                }
                TextField("Hex", text: $hex)
                    .font(.body.monospaced())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .onSubmit(applyHex)
                    .help("RGB as six hex digits, for example FF8800")
            }
        }
    }

    private var lightingColor: NSColor {
        NSColor(srgbRed: CGFloat(model.lighting.red) / 255, green: CGFloat(model.lighting.green) / 255,
                blue: CGFloat(model.lighting.blue) / 255, alpha: 1)
    }

    private func pushColor() {
        guard let rgb = NSColor(hue: hue, saturation: saturation, brightness: 1, alpha: 1).usingColorSpace(.sRGB) else { return }
        model.lighting.red = UInt8((rgb.redComponent * 255).rounded())
        model.lighting.green = UInt8((rgb.greenComponent * 255).rounded())
        model.lighting.blue = UInt8((rgb.blueComponent * 255).rounded())
    }

    /// Accepts RRGGBB with or without a leading #. Anything else restores the current color.
    private func applyHex() {
        let digits = hex.trimmingCharacters(in: .whitespaces).drop { $0 == "#" }
        if digits.count == 6, let value = UInt32(digits, radix: 16) {
            model.lighting.red = UInt8(value >> 16 & 0xFF)
            model.lighting.green = UInt8(value >> 8 & 0xFF)
            model.lighting.blue = UInt8(value & 0xFF)
        }
        syncColor()
    }

    /// Takes hue, saturation and hex from the model when it changed from outside (keyboard read, preset, hex field).
    private func syncColor() {
        hex = String(format: "%02X%02X%02X", model.lighting.red, model.lighting.green, model.lighting.blue)
        let current = lightingColor
        guard let mine = NSColor(hue: hue, saturation: saturation, brightness: 1, alpha: 1).usingColorSpace(.sRGB),
              abs(mine.redComponent - current.redComponent) + abs(mine.greenComponent - current.greenComponent)
                + abs(mine.blueComponent - current.blueComponent) > 0.02 else { return }
        saturation = current.saturationComponent
        if saturation > 0.01 { hue = current.hueComponent }
    }

    @ViewBuilder
    private var presets: some View {
        row("Presets") {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.presets) { preset in
                    Button(preset.name) { model.apply(preset) }
                        .contextMenu {
                            Button("Delete “\(preset.name)”", role: .destructive) {
                                model.presets.removeAll { $0.id == preset.id }
                            }
                        }
                }
                Button("Save Current Lighting as Preset", systemImage: "plus") { addingPreset.toggle() }
                    .labelStyle(.iconOnly)
            }
          }
        }
        if addingPreset {
            HStack {
                TextField("Preset name", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(savePreset)
                Button("Save", action: savePreset)
                    .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.savePreset(named: name)
        presetName = ""
        addingPreset = false
    }

    // MARK: Keys

    @ViewBuilder
    private var keys: some View {
        Text("Remap").font(.headline)
        if model.remaps.isEmpty {
            note("Make one key act as another on this Mac. Nothing is written to the keyboard.")
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
                Button("Remove All") { model.remaps = [] }
            }
        }
        Divider()
        Text("On the keyboard").font(.headline)
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            shortcut("Next light effect", "fn1 + light key")
            shortcut("Backlight on/off", "fn2 + light key")
            shortcut("Change color", "fn2 + ← / →")
            shortcut("Multimedia keys", "fn1 + number row")
            shortcut("F1 – F12", "fn2 + number row")
            shortcut("Disable auto sleep", "fn2 + S + O, hold 4 s")
            shortcut("Factory reset", "fn1 + J + Z, hold 3 s")
        }
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

    private func shortcut(_ name: String, _ keys: String) -> some View {
        GridRow {
            Text(name)
            Text(keys).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
        }
    }
}

/// A full-width segmented control, so every choice in the menu has the same width and height.
private struct Segments<Value: Hashable>: View {
    static var height: CGFloat { 26 }

    let label: String
    @Binding var selection: Value
    let options: [(title: String, value: Value)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.height - 4)
                        .background(selected ? AnyShapeStyle(.background) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 5))
                        .shadow(color: .black.opacity(selected ? 0.2 : 0), radius: 1, y: 0.5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// Two-dimensional color picker: hue across, saturation down (full color at the top, white at the bottom).
/// Brightness is left out because the keyboard has its own brightness setting.
private struct SpectrumPad: View {
    @Binding var hue: Double
    @Binding var saturation: Double
    let onChange: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.1).map { Color(hue: $0, saturation: 1, brightness: 1) },
                               startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(Color(hue: hue, saturation: saturation, brightness: 1))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.4), radius: 1.5)
                    .frame(width: 16, height: 16)
                    .offset(x: hue * (size.width - 16), y: (1 - saturation) * (size.height - 16))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.15)))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                hue = min(max((drag.location.x - 8) / (size.width - 16), 0), 1)
                saturation = 1 - min(max((drag.location.y - 8) / (size.height - 16), 0), 1)
                onChange()
            })
        }
        .accessibilityElement()
        .accessibilityLabel("Color")
        .accessibilityValue("Hue \(Int(hue * 360)) degrees, saturation \(Int(saturation * 100)) percent")
        .accessibilityAdjustableAction { direction in
            hue = min(max(hue + (direction == .increment ? 0.03 : -0.03), 0), 1)
            onChange()
        }
    }
}
