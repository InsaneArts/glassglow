import SwiftUI

/// The colours of the lights that move through the glass.
///
/// The ten lights take the colours in order and wrap around, so one colour tints them all and
/// three colours alternate. Each light keeps its own brightness; only its hue changes.
public struct GlassGlowPalette: Equatable, Sendable {
    /// The light colours. Empty means the original warm and cool whites.
    public var colors: [Color]

    public init(_ colors: [Color]) {
        self.colors = colors
    }

    public init(_ colors: Color...) {
        self.colors = colors
    }

    /// Warm and cool whites, the look the effect was fitted to.
    public static let original = GlassGlowPalette([])
    /// Green, teal and violet.
    public static let aurora = GlassGlowPalette(Color(red: 0.35, green: 1, blue: 0.62), Color(red: 0.25, green: 0.85, blue: 1), Color(red: 0.62, green: 0.4, blue: 1))
    /// Orange, pink and gold.
    public static let sunset = GlassGlowPalette(Color(red: 1, green: 0.48, blue: 0.2), Color(red: 1, green: 0.32, blue: 0.55), Color(red: 1, green: 0.78, blue: 0.35))
    /// Blues and cyan.
    public static let ocean = GlassGlowPalette(Color(red: 0.2, green: 0.55, blue: 1), Color(red: 0.3, green: 0.95, blue: 1), Color(red: 0.45, green: 0.45, blue: 1))
    /// Reds and orange.
    public static let ember = GlassGlowPalette(Color(red: 1, green: 0.3, blue: 0.12), Color(red: 1, green: 0.62, blue: 0.2), Color(red: 1, green: 0.18, blue: 0.25))
    /// Magenta and cyan.
    public static let neon = GlassGlowPalette(Color(red: 1, green: 0.2, blue: 0.85), Color(red: 0.2, green: 0.9, blue: 1), Color(red: 0.6, green: 0.3, blue: 1))
    /// Neutral white.
    public static let mono = GlassGlowPalette(.white)

    /// Every preset, with its name, in display order.
    public static let presets: [(name: String, palette: GlassGlowPalette)] = [
        ("Original", .original), ("Aurora", .aurora), ("Sunset", .sunset), ("Ocean", .ocean),
        ("Ember", .ember), ("Neon", .neon), ("Mono", .mono),
    ]
}

/// How the glass glows: the light colours, the animation speed and the strength of each part.
///
/// Every number is a multiplier of the fitted look, so 1 is the original and 0 turns that part off.
public struct GlassGlowStyle: Equatable, Sendable {
    /// The light colours.
    public var palette: GlassGlowPalette
    /// Animation speed. At 1 the light loops every 6 seconds.
    public var speed: Double
    /// Brightness of the whole effect.
    public var intensity: Double
    /// Strength of the halo around the shape.
    public var glow: Double
    /// How far the glass edge bends the light inward.
    public var refraction: Double
    /// Colour split along the glass edge.
    public var dispersion: Double

    public init(palette: GlassGlowPalette = .original, speed: Double = 1, intensity: Double = 1, glow: Double = 1, refraction: Double = 1, dispersion: Double = 1) {
        self.palette = palette
        self.speed = speed
        self.intensity = intensity
        self.glow = glow
        self.refraction = refraction
        self.dispersion = dispersion
    }

    /// The original look.
    public static let `default` = GlassGlowStyle()

    /// The length of one loop in seconds at `speed` 1.
    public static let loopDuration: Double = Double(LightModel.period)
}

/// A style with its colours resolved to sRGB, ready for the GPU.
struct ResolvedStyle {
    var colours: [SIMD3<Float>]
    var intensity: Float
    var glow: Float
    var refraction: Float
    var dispersion: Float
}

extension GlassGlowStyle {
    func resolved(in environment: EnvironmentValues) -> ResolvedStyle {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let hues: [SIMD3<Float>] = palette.colors.map { color in
            let cg = color.resolve(in: environment).cgColor
            let c = cg.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components ?? [1, 1, 1, 1]
            return c.count >= 3 ? SIMD3(Float(c[0]), Float(c[1]), Float(c[2])) : SIMD3(repeating: Float(c[0]))
        }
        return ResolvedStyle(colours: LightModel.colours(for: hues), intensity: Float(intensity), glow: Float(glow),
                             refraction: Float(refraction), dispersion: Float(dispersion))
    }
}
