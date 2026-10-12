import AppKit
import SwiftUI

/// Writes the film and loops of the stage as videos.
@MainActor
enum FilmExport {
    /// The two cuts: 16:9 for X and the README, 9:16 for Reels and Shorts.
    static let cuts: [(name: String, width: Int, height: Int)] = [("1920x1080", 1920, 1080), ("1080x1920", 1080, 1920)]

    static func film(to url: URL, width: Int, height: Int, master: Bool = false, progress: (Double) -> Void = { _ in }) async throws {
        let renderer = FilmRenderer(width: width, height: height)
        let writer = try VideoWriter(url: url, width: width, height: height, fps: Film.fps, master: master)
        let count = Int(Film.duration * Double(Film.fps))
        for i in 0..<count {
            autoreleasepool {
                writer.append { renderer.render(at: Double(i) / Double(Film.fps), to: $0) }
            }
            progress(Double(i + 1) / Double(count))
            await breathe(i)
        }
        writer.finish()
    }

    /// Gives the run loop a moment every few frames, so the window stays responsive.
    private static func breathe(_ frame: Int) async {
        if frame % 4 == 0 { try? await Task.sleep(for: .milliseconds(1)) }
    }

    /// One loop of the light (6 s) on the stage, at the frame's pixel size.
    static func loop(model: DemoModel, to url: URL, pixels: CGSize, progress: (Double) -> Void = { _ in }) async throws {
        let writer = try VideoWriter(url: url, width: Int(pixels.width), height: Int(pixels.height), fps: Film.fps)
        let context = CIContext()
        let count = Int(6 / model.speed * Double(Film.fps))
        let start = model.time
        defer { model.time = start }
        for i in 0..<count {
            model.time = start + Double(i) / Double(Film.fps)
            autoreleasepool {
                guard let image = Exporter.image(model: model, pixels: pixels) else { return }
                writer.append { context.render(CIImage(cgImage: image), to: $0) }
            }
            progress(Double(i + 1) / Double(count))
            await breathe(i)
        }
        writer.finish()
    }

    /// Asks where to save, then writes the film (on the Film scene) or a loop of the stage.
    static func save(model: DemoModel, progress: @escaping (Double?) -> Void) {
        let size = model.frame.pixels ?? CGSize(width: 1920, height: 1080)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "glassglow-\(model.scene.rawValue.lowercased())-\(Int(size.width))x\(Int(size.height)).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        progress(0)
        Task {
            if model.scene == .film {
                try? await film(to: url, width: Int(size.width), height: Int(size.height)) { progress($0) }
            } else {
                try? await loop(model: model, to: url, pixels: size) { progress($0) }
            }
            progress(nil)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// `--render-film <dir>` writes both cuts as ProRes masters and quits.
    /// `--film-stills <dir> <t,t,...>` writes PNG stills of both cuts at those times and quits.
    static func runIfRequested(_ args: [String]) {
        if let i = args.firstIndex(of: "--render-film"), i + 1 < args.count {
            let dir = URL(fileURLWithPath: args[i + 1])
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            Task {
                for cut in cuts {
                    let start = Date()
                    do {
                        try await film(to: dir.appendingPathComponent("glassglow-film-\(cut.name).mov"), width: cut.width, height: cut.height, master: true)
                        print("\(cut.name): \(Int(Date().timeIntervalSince(start))) s")
                    } catch {
                        print("\(cut.name) failed: \(error)")
                    }
                }
                exit(0)
            }
            // Runs the task before the app opens a window.
            while true { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
        }
        if let i = args.firstIndex(of: "--film-stills"), i + 2 < args.count {
            let dir = URL(fileURLWithPath: args[i + 1])
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let times = args[i + 2].split(separator: ",").compactMap { Double($0) }
            for cut in cuts {
                let renderer = FilmRenderer(width: cut.width, height: cut.height)
                for t in times {
                    if let image = renderer.cgImage(at: t) {
                        Exporter.write(image, to: dir.appendingPathComponent("\(cut.name)-\(String(format: "%05.2f", t)).png"))
                    }
                }
            }
            exit(0)
        }
    }
}
