import GlassGlow
import SwiftUI

/// The things to put on the stage.
enum DemoScene: String, CaseIterable, Identifiable {
    case symbol = "Symbol"
    case text = "Text"
    case shapes = "Shapes"
    case clock = "Clock"
    case trio = "Trio"
    case collection = "Collection"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .symbol: "heart"
        case .text: "textformat"
        case .shapes: "square.on.circle"
        case .clock: "clock"
        case .trio: "sparkles"
        case .collection: "square.grid.3x2"
        }
    }

    /// Scenes that show several presets at once ignore the chosen palette.
    var usesPalette: Bool { self != .trio && self != .collection }
}

/// SF Symbols that make good glass.
let demoSymbols = ["heart.fill", "sparkles", "bolt.fill", "leaf.fill", "star.fill", "moon.fill", "flame.fill",
                   "drop.fill", "pawprint.fill", "cloud.fill", "music.note", "gamecontroller.fill", "swift"]

/// The stage: the backdrop and the scene, laid out relative to its size so the window and every
/// export size frame it the same way.
struct Stage: View {
    let model: DemoModel
    /// Overrides the model's time (exports pass the frozen time).
    var time: Double?? = nil

    private var t: Double? { time ?? model.liveTime }

    var body: some View {
        GeometryReader { geo in
            let u = min(geo.size.width, geo.size.height)
            ZStack {
                model.backdrop.view
                content(u: u, size: geo.size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private func content(u: CGFloat, size: CGSize) -> some View {
        let style = model.style
        switch model.scene {
        case .symbol:
            Image(systemName: model.symbol)
                .resizable()
                .scaledToFit()
                .frame(width: u * 0.46, height: u * 0.46)
                .glassGlow(style, time: t)
        case .text:
            Text(model.text)
                .font(.system(size: u * 0.34, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.2)
                .frame(maxWidth: size.width * 0.8)
                .fixedSize(horizontal: false, vertical: true)
                .glassGlow(style, time: t)
        case .shapes:
            HStack(spacing: u * 0.12) {
                Circle().frame(width: u * 0.27, height: u * 0.27).glassGlow(style, time: t)
                RoundedRectangle(cornerRadius: u * 0.068, style: .continuous).frame(width: u * 0.27, height: u * 0.27).glassGlow(style, time: t.map { $0 + 2 })
                Star().frame(width: u * 0.3, height: u * 0.3).glassGlow(style, time: t.map { $0 + 4 })
            }
        case .clock:
            VStack(spacing: u * 0.02) {
                Text("Monday, October 12")
                    .font(.system(size: u * 0.045, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                Text("9:41")
                    .font(.system(size: u * 0.3, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .glassGlow(style, time: t)
            }
        case .trio:
            HStack(spacing: u * 0.13) {
                symbol("sparkles", .aurora, u * 0.33, offset: 0)
                symbol("heart.fill", .original, u * 0.4, offset: 1)
                symbol("bolt.fill", .sunset, u * 0.33, offset: 0.5)
            }
        case .collection:
            let names = ["heart.fill", "sparkles", "bolt.fill", "leaf.fill", "moon.fill", "flame.fill", "drop.fill", "star.fill"]
            let presets = GlassGlowPalette.presets.map(\.palette)
            Grid(horizontalSpacing: u * 0.12, verticalSpacing: u * 0.12) {
                ForEach(0..<2) { row in
                    GridRow {
                        ForEach(0..<4) { col in
                            let i = row * 4 + col
                            symbol(names[i], presets[i % presets.count], u * 0.17, offset: Double(i) * 0.75)
                        }
                    }
                }
            }
        }
    }

    private func symbol(_ name: String, _ palette: GlassGlowPalette, _ side: CGFloat, offset: Double) -> some View {
        var style = model.style
        style.palette = palette
        return Image(systemName: name)
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .glassGlow(style, time: t.map { $0 + offset })
    }
}

/// A five-pointed star.
struct Star: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.45
        var path = Path()
        for i in 0..<10 {
            let r = i.isMultiple(of: 2) ? outer : inner
            let a = Double(i) * .pi / 5 - .pi / 2
            let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a) + outer * 0.08)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}
