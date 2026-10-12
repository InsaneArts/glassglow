import SwiftUI

extension View {
    /// Turns the view into glass with light moving through it.
    ///
    /// The shape is the view's alpha: a shape, an SF Symbol, text, an image or any composition.
    /// The view keeps its layout; the halo spills outside its frame and does not take touches.
    ///
    /// ```swift
    /// Image(systemName: "heart.fill")
    ///     .font(.system(size: 200))
    ///     .glassGlow()
    ///
    /// Text("Glow")
    ///     .font(.system(size: 120, weight: .black))
    ///     .glassGlow(GlassGlowStyle(palette: .sunset, speed: 1.5))
    /// ```
    ///
    /// - Parameters:
    ///   - style: Colours, speed and strengths.
    ///   - time: A fixed time in seconds, to freeze or scrub the animation. Nil animates.
    public func glassGlow(_ style: GlassGlowStyle = .default, time: Double? = nil) -> some View {
        GlassGlowEffect(content: self, style: style, time: time)
    }

    /// Turns the view into glass lit by `palette`.
    ///
    /// ```swift
    /// Circle().frame(width: 200, height: 200)
    ///     .glassGlow(.aurora, speed: 0.8)
    /// ```
    public func glassGlow(_ palette: GlassGlowPalette, speed: Double = 1, glow: Double = 1, time: Double? = nil) -> some View {
        GlassGlowEffect(content: self, style: GlassGlowStyle(palette: palette, speed: speed, glow: glow), time: time)
    }

    /// Draws every `glassGlow` inside this view as a still image at `time` seconds instead of a
    /// live Metal view, so `ImageRenderer` can capture it.
    ///
    /// ```swift
    /// let renderer = ImageRenderer(content: card.glassGlowSnapshot(at: 2))
    /// ```
    public func glassGlowSnapshot(at time: Double) -> some View {
        environment(\.glassGlowSnapshotTime, time)
    }
}

private struct SnapshotTimeKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    var glassGlowSnapshotTime: Double? {
        get { self[SnapshotTimeKey.self] }
        set { self[SnapshotTimeKey.self] = newValue }
    }
}

struct GlassGlowEffect<Content: View>: View {
    let content: Content
    let style: GlassGlowStyle
    let time: Double?

    @Environment(\.self) private var environment
    @Environment(\.displayScale) private var displayScale
    @Environment(\.glassGlowSnapshotTime) private var snapshotTime

    var body: some View {
        if GlowPipelines.shared == nil {
            content
        } else {
            content
                .opacity(0)
                .overlay {
                    GeometryReader { geo in
                        let margin = GlassGlowRenderer.margin(for: geo.size)
                        glow(size: geo.size, margin: margin)
                            .frame(width: geo.size.width + 2 * margin, height: geo.size.height + 2 * margin)
                            .offset(x: -margin, y: -margin)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
        }
    }

    @ViewBuilder
    private func glow(size: CGSize, margin: CGFloat) -> some View {
        if size.width < 1 || size.height < 1 {
            Color.clear
        } else if let snapshotTime, let image = still(size: size, margin: margin, time: time ?? snapshotTime) {
            Image(decorative: image, scale: displayScale)
        } else if snapshotTime == nil {
            GlowSurface(content: content, size: size, margin: margin, scale: displayScale, style: style, time: time, environment: environment)
        }
    }

    private func still(size: CGSize, margin: CGFloat, time: Double) -> CGImage? {
        var env = environment
        env.glassGlowSnapshotTime = nil
        guard let mask = MaskSnapshot.image(content, size: size, margin: margin, scale: displayScale, environment: env),
              let renderer = try? GlassGlowRenderer() else { return nil }
        return renderer.render(mask: mask, style: style.resolved(in: environment), phase: Float(time * style.speed))
    }
}
