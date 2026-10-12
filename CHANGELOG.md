# Changelog

## 0.1.0

First release.

- `glassGlow()` on any SwiftUI view: the view's alpha becomes glass with ten moving lights,
  refraction and colour split at the edge, and a three-radius halo. Metal, on iOS 17, macOS 14,
  tvOS 17 and visionOS 1.
- `GlassGlowStyle` (palette, speed, intensity, glow, refraction, dispersion) and
  `GlassGlowPalette` with seven presets.
- `glassGlowSnapshot(at:)` for `ImageRenderer` exports, and `GlassGlowRenderer` for off-screen images.
- macOS demo app (`Demo/`): scenes, palettes, light controls, Swift code for the stage, PNG export
  at post sizes, and `--render-assets` for the README images.
