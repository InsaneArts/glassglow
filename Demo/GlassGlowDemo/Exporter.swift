import AppKit
import GlassGlow
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum Exporter {
    /// The stage at the frame's pixel size (2 pixels per point), frozen at the model's time.
    @MainActor
    static func image(model: DemoModel, pixels: CGSize) -> CGImage? {
        let points = CGSize(width: pixels.width / 2, height: pixels.height / 2)
        let stage = Stage(model: model, time: .some(model.time))
            .frame(width: points.width, height: points.height)
            .environment(\.colorScheme, .dark)
            .glassGlowSnapshot(at: model.time)
        let renderer = ImageRenderer(content: stage)
        renderer.scale = 2
        renderer.isOpaque = model.backdrop != .transparent
        return renderer.cgImage
    }

    @MainActor
    static func savePNG(model: DemoModel) {
        let size = model.frame.pixels ?? stageSize()
        guard let image = image(model: model, pixels: size) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "glassglow-\(model.scene.rawValue.lowercased())-\(Int(size.width))x\(Int(size.height)).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(image, to: url)
    }

    static func write(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    /// The window's stage size in pixels, for the Window frame.
    @MainActor
    private static func stageSize() -> CGSize {
        let window = NSApp.keyWindow?.contentView?.bounds.size ?? CGSize(width: 1200, height: 800)
        return CGSize(width: (window.width - 480) * 2, height: window.height * 2)
    }
}

/// `GlassGlowDemo --render-assets <dir>` writes the README and social images and quits.
enum AssetRenderer {
    @MainActor
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-assets"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        func render(_ name: String, _ frame: PostFrame, time: Double = 1.5, _ configure: (DemoModel) -> Void) {
            let model = DemoModel()
            model.time = time
            configure(model)
            if let image = Exporter.image(model: model, pixels: frame.pixels!) {
                Exporter.write(image, to: dir.appendingPathComponent("\(name).png"))
            }
        }

        render("hero", .readme, time: 0) { $0.scene = .trio; $0.backdrop = .night }
        render("collection", .readme, time: 0.6) { $0.scene = .collection }
        render("heart", .square, time: 1) { $0.scene = .symbol }
        render("text", .readme, time: 4) { $0.scene = .text; $0.preset = "Sunset" }
        render("shapes", .readme, time: 1.2) { $0.scene = .shapes; $0.preset = "Aurora" }
        render("social-portrait", .portrait, time: 4.2) { $0.scene = .symbol; $0.backdrop = .night }
        render("social-clock", .portrait, time: 4.2) { $0.scene = .clock; $0.preset = "Neon" }
        render("social-story", .story, time: 0) { $0.scene = .symbol; $0.symbol = "sparkles"; $0.preset = "Aurora"; $0.backdrop = .night }
        render("social-landscape", .landscape, time: 0) { $0.scene = .trio }
        exit(0)
    }
}
