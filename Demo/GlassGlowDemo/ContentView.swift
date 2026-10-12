import GlassGlow
import SwiftUI

struct ContentView: View {
    @State private var model = DemoModel()
    @State private var showInspector = true

    var body: some View {
        NavigationSplitView {
            List(DemoScene.allCases, selection: Binding(get: { model.scene }, set: { if let s = $0 { model.scene = s } })) { scene in
                Label(scene.rawValue, systemImage: scene.icon).tag(scene)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            StageFrame(model: model)
                .inspector(isPresented: $showInspector) {
                    InspectorView(model: model)
                        .inspectorColumnWidth(min: 280, ideal: 300, max: 360)
                }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.isPlaying.toggle()
                } label: {
                    Label(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])
                .help("Pause to freeze the light at the time set in the inspector")
                Button {
                    Exporter.savePNG(model: model)
                } label: {
                    Label("Export PNG", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e")
                .help("Export the stage as a PNG at the selected frame's size")
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
            }
        }
        .navigationTitle(model.scene.rawValue)
        .frame(minWidth: 1000, minHeight: 640)
    }
}

/// The stage in the window: fills it, or shows the export frame's aspect ratio.
struct StageFrame: View {
    let model: DemoModel

    var body: some View {
        GeometryReader { geo in
            if let px = model.frame.pixels {
                let fit = min((geo.size.width - 48) / px.width, (geo.size.height - 48) / px.height)
                Stage(model: model)
                    .frame(width: px.width * fit, height: px.height * fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.4), radius: 12)
                    .frame(width: geo.size.width, height: geo.size.height)
            } else {
                Stage(model: model)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
