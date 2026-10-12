import SwiftUI
import Testing
import GlassGlow

/// The README's snippets, so they keep compiling.
@MainActor
@Suite("README")
struct ReadmeSnippetTests {
    @Test("snippets type-check and render")
    func snippets() throws {
        _ = Image(systemName: "heart.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 240, height: 240)
            .glassGlow()
        _ = Text("Glow")
            .font(.system(size: 120, weight: .black, design: .rounded))
            .glassGlow(.sunset)
        _ = Circle()
            .frame(width: 200, height: 200)
            .glassGlow(GlassGlowPalette(.pink, .orange, .cyan), speed: 0.8)
        let style = GlassGlowStyle(palette: .aurora, speed: 1.5, intensity: 1.2, glow: 2, refraction: 1, dispersion: 2)
        _ = Image(systemName: "sparkles").glassGlow(style)
        _ = RoundedRectangle(cornerRadius: 40).glassGlow(.ocean, time: 2.5)

        let renderer = try GlassGlowRenderer()
        let image = renderer.image(of: Image(systemName: "bolt.fill").resizable(),
                                   size: CGSize(width: 200, height: 200),
                                   style: GlassGlowStyle(palette: .ember),
                                   time: 1)
        #expect(image != nil)
    }
}
