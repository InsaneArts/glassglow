import GlassGlow
import SwiftUI

/// What is on the stage and how it glows.
@Observable
final class DemoModel {
    var scene: DemoScene = .symbol
    var symbol = "heart.fill"
    var text = "Glow"

    /// The preset in use, or nil for the custom colours.
    var preset: String? = "Original"
    var customColors: [Color] = [Color(red: 1, green: 0.45, blue: 0.3), Color(red: 0.55, green: 0.4, blue: 1), Color(red: 0.3, green: 0.9, blue: 1)]
    var speed = 1.0
    var intensity = 1.0
    var glow = 1.0
    var refraction = 1.0
    var dispersion = 1.0

    var isPlaying = true
    /// The frozen time while paused, and the time of every export.
    var time = 1.5

    var backdrop: Backdrop = .black
    var frame: PostFrame = .window

    var palette: GlassGlowPalette {
        if let preset, let p = GlassGlowPalette.presets.first(where: { $0.name == preset }) { return p.palette }
        return GlassGlowPalette(customColors)
    }

    var style: GlassGlowStyle {
        GlassGlowStyle(palette: palette, speed: speed, intensity: intensity, glow: glow, refraction: refraction, dispersion: dispersion)
    }

    /// Nil animates; a time freezes.
    var liveTime: Double? { isPlaying ? nil : time }

    func reset() {
        preset = "Original"
        speed = 1
        intensity = 1
        glow = 1
        refraction = 1
        dispersion = 1
    }
}

enum Backdrop: String, CaseIterable, Identifiable {
    case black = "Black"
    case night = "Night"
    case graphite = "Graphite"
    case transparent = "Transparent"

    var id: String { rawValue }

    @ViewBuilder
    var view: some View {
        switch self {
        case .black:
            Color.black
        case .night:
            RadialGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.14), .black], center: .center, startRadius: 0, endRadius: 900)
        case .graphite:
            LinearGradient(colors: [Color(white: 0.13), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
        case .transparent:
            Color.clear
        }
    }
}

/// Export sizes for the places the images go.
enum PostFrame: String, CaseIterable, Identifiable {
    case window = "Window"
    case readme = "README hero 2:1"
    case landscape = "Landscape 16:9"
    case square = "Square 1:1"
    case portrait = "Portrait 4:5"
    case story = "Story 9:16"

    var id: String { rawValue }

    /// Pixel size, or nil for the stage's own size.
    var pixels: CGSize? {
        switch self {
        case .window: nil
        case .readme: CGSize(width: 2400, height: 1200)
        case .landscape: CGSize(width: 1920, height: 1080)
        case .square: CGSize(width: 1080, height: 1080)
        case .portrait: CGSize(width: 1080, height: 1350)
        case .story: CGSize(width: 1080, height: 1920)
        }
    }
}
