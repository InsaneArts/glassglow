import CoreImage
import GlassGlow
import SwiftUI

/// The showcase film: a heart lights up, melts from shape to shape, splits into five shapes that
/// take their own colours, and they flow back together as the name. Every frame is the shader's.
///
/// Lengths are in units of the frame's shorter side and positions are from its centre, y down,
/// so every frame size shares the choreography. The music's grid is 80 BPM: a beat is 0.75 s and
/// a bar is 3 s.
enum Film {
    static let duration = 21.0
    static let fps = 60

    enum Shape: CaseIterable {
        case heart, drop, bolt, leaf, star, moon, word

        var symbol: String? {
            switch self {
            case .heart: "heart.fill"
            case .drop: "drop.fill"
            case .bolt: "bolt.fill"
            case .leaf: "leaf.fill"
            case .star: "star.fill"
            case .moon: "moon.fill"
            case .word: nil
            }
        }
    }

    struct Element {
        var shape: Shape
        var x = 0.0
        var y = 0.0
        /// The symbol's box side, or the word's width.
        var size: Double
        /// Elements in one group morph between each other by these weights; groups join as liquid.
        var group = 0
        var weight = 1.0
    }

    /// One frame of the film, before it is drawn.
    struct Frame {
        var elements: [Element]
        /// Each group's presence: below 1 it shrinks, at 0 it is gone.
        var presence: [Double] = [1]
        /// How far apart shapes still flow together, in units.
        var melt = 0.0
        /// The palette of the shared glass, crossfading from `palette.0` to `palette.1` by `palette.2`.
        var palette: (GlassGlowPalette, GlassGlowPalette, Double)
        /// 0: one glass for all shapes. 1: each shape is its own glass, in `own` colours.
        var separate = 0.0
        var own: [GlassGlowPalette] = []
        var intensity = 1.0
        var code = 0.0
        var credit = 0.0
        var fade = 1.0
    }

    /// Heart, then a morph to the next shape on every second beat. Every shape is one piece without
    /// holes: a piece that appears on its own would jump the light, which spans the shape's bounds.
    private static let morphs: [(time: Double, shape: Shape, palette: GlassGlowPalette)] = [
        (0, .heart, .original), (3, .drop, .ocean), (4.5, .moon, .sunset), (6, .bolt, .neon), (7.5, .star, .aurora),
    ]
    private static let five: [(shape: Shape, palette: GlassGlowPalette)] = [
        (.heart, .sunset), (.drop, .ocean), (.bolt, .neon), (.leaf, .aurora), (.moon, .original),
    ]

    static func frame(at t: Double, aspect: Double) -> Frame {
        let wide = aspect > 1
        let u = min(aspect, 1 / aspect)
        let longSide = 1 / u
        // Where the five shapes rest: a row in wide frames, a slowly turning ring in tall ones.
        func rest(_ i: Int) -> (x: Double, y: Double) {
            if wide {
                let spacing = min(0.34, (longSide - 0.4) / 4)
                return (Double(i - 2) * spacing, 0.02 * sin(2 * .pi * t / 3 + Double(i) * 1.3))
            }
            let a = -Double.pi / 2 + Double(i) * 2 * .pi / 5 + 0.06 * (t - 10.5)
            return (0.33 * cos(a), 0.33 * sin(a))
        }
        let wordWidth = min(1.0, 0.82 * (wide ? longSide : 1))
        let wordY = -0.04

        var f = Frame(elements: [], palette: (.original, .original, 0))
        f.intensity = pow(smooth(0, 1.6, t), 2)
        f.code = smooth(16.5, 17.1, t)
        f.credit = smooth(18, 18.6, t)
        f.fade = 1 - smooth(20.25, 21, t)

        if t < 9 {
            // Morph from shape to shape in 0.75 s, melting through the middle.
            let i = morphs.lastIndex { $0.time <= t } ?? 0
            let k = i == 0 ? 1 : smooth(morphs[i].time, morphs[i].time + 0.75, t)
            let size = (wide ? 0.56 : 0.5) * (i == 0 ? 0.94 + 0.06 * smooth(0, 3, t) : 1)
            if i > 0, k < 1 { f.elements.append(Element(shape: morphs[i - 1].shape, size: size, weight: 1 - k)) }
            f.elements.append(Element(shape: morphs[i].shape, size: size, weight: k))
            f.palette = (i > 0 ? morphs[i - 1].palette : morphs[i].palette, morphs[i].palette, k)
            return f
        }

        // 9-10.5 s: the star splits into five; 10.5-15 s: they rest and gather, each in its own
        // colours; 14.25-15.75 s: they flow along the line of the name and become it.
        f.own = five.map(\.palette)
        f.separate = smooth(10.5, 11.25, t) - smooth(14.6, 15.3, t)
        f.palette = (.aurora, .original, smooth(14.6, 15.3, t))
        let out = ease(clamp((t - 9) / 1.5))
        let back = ease(clamp((t - 14.25) / 1.5))
        // The five grow inside the star before it shrinks away; the name grows around them
        // before they go.
        let split = smooth(9, 9.4, t)
        let fadeOut = 1 - smooth(15.2, 15.9, t)
        let word = smooth(14.9, 15.5, t)
        f.presence = [1 - smooth(9.25, 9.9, t)] + Array(repeating: split * fadeOut, count: five.count) + [word]
        f.elements.append(Element(shape: .star, size: wide ? 0.56 : 0.5, group: 0))
        if fadeOut > 0 {
            for (i, s) in five.enumerated() {
                let r = rest(i)
                let line = (x: wordWidth * Double(i - 2) / 5, y: wordY)
                let x = mix(mix(0, r.x, out), line.x, back)
                let y = mix(mix(0, r.y, out), line.y, back)
                let size = mix(mix(0.3, 0.22, out), 0.15, back)
                f.elements.append(Element(shape: s.shape, x: x, y: y, size: size, group: i + 1))
            }
        }
        f.elements.append(Element(shape: .word, y: wordY, size: wordWidth, group: five.count + 1))
        f.melt = 0.06 * (sin(.pi * clamp((t - 9) / 1.5)) + sin(.pi * clamp((t - 14.25) / 1.75)))
        return f
    }

    static func smooth(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let x = clamp((t - a) / (b - a))
        return x * x * (3 - 2 * x)
    }

    static func ease(_ x: Double) -> Double { x * x * x * (x * (x * 6 - 15) + 10) }
    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    static func mix(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }
}

/// Draws the film's frames at one pixel size.
@MainActor
final class FilmRenderer {
    let width: Int
    let height: Int
    private var u: Double { Double(min(width, height)) }
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var glass: [GlassGlowRenderer] = []
    private let codeLine: CIImage
    private let creditLine: CIImage

    /// The shapes' distance fields, built once: each with its length (the symbol's box side or the
    /// word's width) and the radius it shrinks by to vanish, in field pixels.
    private static let library: (field: ShapeField, shapes: [Film.Shape: (index: Int, length: Double, radius: Double)])? = {
        guard let field = ShapeField() else { return nil }
        var shapes: [Film.Shape: (Int, Double, Double)] = [:]
        let pad = 256.0
        for shape in Film.Shape.allCases {
            let view: AnyView
            if let symbol = shape.symbol {
                view = AnyView(Image(systemName: symbol).resizable().scaledToFit().frame(width: 1024, height: 1024).padding(pad))
            } else {
                view = AnyView(Text("GlassGlow").font(.system(size: 400, weight: .black, design: .rounded)).padding(pad))
            }
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let image = renderer.cgImage else { continue }
            let w = Double(image.width) - 2 * pad, h = Double(image.height) - 2 * pad
            shapes[shape] = (field.add(image), shape.symbol == nil ? w : 1024, min(w, h) / 2)
        }
        return (field, shapes)
    }()

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        let u = Double(min(width, height))
        codeLine = Self.image(Text(".glassGlow()").font(.system(size: u * 0.05, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.85)))
        creditLine = Self.image(Text("by InsaneArts").font(.system(size: u * 0.034, weight: .medium)).foregroundStyle(.white.opacity(0.5)))
    }

    private static func image(_ view: some View) -> CIImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.cgImage.map { CIImage(cgImage: $0) } ?? CIImage.empty()
    }

    /// The frame at `t` seconds, on black.
    func image(at t: Double) -> CIImage {
        let f = Film.frame(at: t, aspect: Double(width) / Double(height))
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        var out = CIImage(color: .black).cropped(to: bounds)
        var slot = 0
        func light(_ elements: [Film.Element], _ palette: GlassGlowPalette, opacity: Double, time: Double) {
            guard opacity > 0.002, let mask = mask(elements, presence: f.presence, melt: f.melt) else { return }
            if slot == glass.count, let r = try? GlassGlowRenderer() { glass.append(r) }
            guard slot < glass.count else { return }
            let style = GlassGlowStyle(palette: palette, intensity: f.intensity)
            if let lit = glass[slot].image(mask: mask, style: style, time: time) {
                out = CIImage(cgImage: lit).applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])
                    .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: out])
            }
            slot += 1
        }
        let shared = 1 - f.separate
        light(f.elements, f.palette.0, opacity: shared * (1 - f.palette.2), time: t)
        light(f.elements, f.palette.1, opacity: shared * f.palette.2, time: t)
        for e in f.elements where f.separate > 0 && e.group >= 1 && e.group <= f.own.count {
            light([e], f.own[e.group - 1], opacity: f.separate, time: t + Double(e.group) * 0.8)
        }
        let codeY = height > width ? 0.15 : 0.19
        out = overlay(codeLine, y: codeY, opacity: f.code, on: out)
        out = overlay(creditLine, y: codeY + 0.08, opacity: f.credit, on: out)
        let fade = CGFloat(f.fade)
        return out.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: fade, y: 0, z: 0, w: 0),
                                                    "inputGVector": CIVector(x: 0, y: fade, z: 0, w: 0),
                                                    "inputBVector": CIVector(x: 0, y: 0, z: fade, w: 0)])
            .cropped(to: bounds)
    }

    func cgImage(at t: Double) -> CGImage? {
        context.createCGImage(image(at: t), from: CGRect(x: 0, y: 0, width: width, height: height))
    }

    func render(at t: Double, to buffer: CVPixelBuffer) {
        context.render(image(at: t), to: buffer, bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    /// The shapes' alpha, from their distance fields: groups that have no element here are left out.
    private func mask(_ elements: [Film.Element], presence: [Double], melt: Double) -> CGImage? {
        guard let library = Self.library else { return nil }
        var groups = presence.map { _ in ShapeField.Group(presence: 0, radius: 0) }
        var list: [ShapeField.Element] = []
        for e in elements where e.group < groups.count && presence[e.group] > 0 && e.weight > 0.0005 {
            guard let shape = library.shapes[e.shape] else { continue }
            let s = e.size * u / shape.length
            let center = SIMD2(Float(Double(width) / 2 + e.x * u), Float(Double(height) / 2 + e.y * u))
            list.append(ShapeField.Element(shape: shape.index, group: e.group, center: center, scale: Float(s), weight: Float(e.weight)))
            groups[e.group].presence = Float(presence[e.group])
            groups[e.group].radius = max(groups[e.group].radius, Float(shape.radius * s))
        }
        return library.field.mask(width: width, height: height, elements: list, groups: groups, melt: Float(melt * u))
    }

    private func overlay(_ line: CIImage, y: Double, opacity: Double, on base: CIImage) -> CIImage {
        guard opacity > 0.002 else { return base }
        let w = line.extent.width, h = line.extent.height
        return line
            .transformed(by: CGAffineTransform(translationX: (Double(width) - w) / 2, y: Double(height) / 2 - y * u - h / 2))
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])
            .composited(over: base)
    }
}

/// The film on the stage: plays in a loop, or shows the frame at `time`.
struct FilmPlayer: View {
    let time: Double?
    @State private var cache = Cache()
    @State private var start = Date()

    final class Cache {
        var renderer: FilmRenderer?
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: time != nil)) { context in
                let t = time ?? context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: Film.duration)
                if let image = frame(width: Int(geo.size.width), height: Int(geo.size.height), at: t) {
                    Image(decorative: image, scale: 1)
                }
            }
        }
    }

    /// Drawn at one pixel per point, which keeps the preview near real time.
    @MainActor
    private func frame(width: Int, height: Int, at t: Double) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        if cache.renderer?.width != width || cache.renderer?.height != height {
            cache.renderer = FilmRenderer(width: width, height: height)
        }
        return cache.renderer?.cgImage(at: t)
    }
}
