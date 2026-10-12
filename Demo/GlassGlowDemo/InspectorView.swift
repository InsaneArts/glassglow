import AppKit
import GlassGlow
import SwiftUI

struct InspectorView: View {
    @Bindable var model: DemoModel

    var body: some View {
        Form {
            sceneSection
            Section("Colors") {
                presetGrid
                HStack {
                    Text("Custom")
                    Spacer()
                    ForEach(model.customColors.indices, id: \.self) { i in
                        ColorPicker("", selection: Binding(get: { model.customColors[i] }, set: {
                            model.customColors[i] = $0
                            model.preset = nil
                        }), supportsOpacity: false)
                        .labelsHidden()
                    }
                }
                .disabled(!model.scene.usesPalette)
            }
            Section("Light") {
                slider("Speed", $model.speed, 0...3)
                slider("Intensity", $model.intensity, 0...2)
                slider("Glow", $model.glow, 0...3)
                slider("Refraction", $model.refraction, 0...4)
                slider("Dispersion", $model.dispersion, 0...4)
                Button("Reset") { model.reset() }
            }
            Section("Time") {
                Toggle("Animate", isOn: $model.isPlaying)
                slider("Seconds", $model.time, 0...6)
                    .help("The frozen time while paused, and the time of every export")
            }
            Section("Stage") {
                Picker("Backdrop", selection: $model.backdrop) {
                    ForEach(Backdrop.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Frame", selection: $model.frame) {
                    ForEach(PostFrame.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section("Code") {
                Text(CodeSnippet.swift(for: model))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy Code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(CodeSnippet.swift(for: model), forType: .string)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var sceneSection: some View {
        switch model.scene {
        case .symbol:
            Section("Symbol") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                    ForEach(demoSymbols, id: \.self) { name in
                        Button {
                            model.symbol = name
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 16))
                                .frame(width: 36, height: 30)
                                .background(model.symbol == name ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
            }
        case .text:
            Section("Text") {
                TextField("Text", text: $model.text)
            }
        default:
            EmptyView()
        }
    }

    private var presetGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
            ForEach(GlassGlowPalette.presets, id: \.name) { preset in
                Button {
                    model.preset = preset.name
                } label: {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(AngularGradient(colors: swatch(preset.palette), center: .center))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(model.preset == preset.name ? Color.accentColor : .white.opacity(0.2), lineWidth: 2))
                        Text(preset.name).font(.caption2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(!model.scene.usesPalette)
    }

    private func swatch(_ palette: GlassGlowPalette) -> [Color] {
        let colors = palette.colors.isEmpty ? [Color(red: 1, green: 0.85, blue: 0.75), Color(red: 0.7, green: 0.78, blue: 1)] : palette.colors
        return colors + [colors[0]]
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }
}

/// The Swift for what is on the stage.
enum CodeSnippet {
    static func swift(for model: DemoModel) -> String {
        let view: String
        switch model.scene {
        case .text:
            view = "Text(\"\(model.text)\")\n    .font(.system(size: 120, weight: .black, design: .rounded))"
        case .shapes:
            view = "Circle()\n    .frame(width: 200, height: 200)"
        case .clock:
            view = "Text(\"9:41\")\n    .font(.system(size: 140, weight: .bold, design: .rounded))"
        default:
            view = "Image(systemName: \"\(model.scene == .symbol ? model.symbol : "heart.fill")\")\n    .resizable()\n    .scaledToFit()\n    .frame(width: 240, height: 240)"
        }
        var args: [String] = []
        if model.scene.usesPalette {
            if let preset = model.preset {
                if preset != "Original" { args.append("palette: .\(preset.lowercased())") }
            } else {
                args.append("palette: GlassGlowPalette(\(model.customColors.map(colorCode).joined(separator: ", ")))")
            }
        }
        for (name, value) in [("speed", model.speed), ("intensity", model.intensity), ("glow", model.glow), ("refraction", model.refraction), ("dispersion", model.dispersion)] where abs(value - 1) > 0.005 {
            args.append("\(name): \(String(format: "%.2f", value))")
        }
        let time = model.isPlaying ? "" : ", time: \(String(format: "%.2f", model.time))"
        if args.isEmpty {
            return "\(view)\n    .glassGlow(\(time.isEmpty ? "" : "time: \(String(format: "%.2f", model.time))"))"
        }
        return "\(view)\n    .glassGlow(GlassGlowStyle(\(args.joined(separator: ", ")))\(time))"
    }

    private static func colorCode(_ color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return String(format: "Color(red: %.2f, green: %.2f, blue: %.2f)", c.redComponent, c.greenComponent, c.blueComponent)
    }
}
