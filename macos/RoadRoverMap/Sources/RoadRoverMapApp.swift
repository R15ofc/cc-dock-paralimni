import SwiftUI

extension Notification.Name {
    static let roadRoverChooseTool = Notification.Name("RoadRoverChooseTool")
    static let roadRoverUndo = Notification.Name("RoadRoverUndo")
    static let roadRoverRedo = Notification.Name("RoadRoverRedo")
    static let roadRoverImport = Notification.Name("RoadRoverImport")
    static let roadRoverExport = Notification.Name("RoadRoverExport")
}

@main
struct RoadRoverMapApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { NotificationCenter.default.post(name: .roadRoverUndo, object: nil) }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo") { NotificationCenter.default.post(name: .roadRoverRedo, object: nil) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandMenu("Tools") {
                toolCommand(.browse, key: "1")
                toolCommand(.road, key: "2")
                toolCommand(.building, key: "3")
                toolCommand(.label, key: "4")
            }
            CommandGroup(after: .importExport) {
                Button("Import Map Layers…") { NotificationCenter.default.post(name: .roadRoverImport, object: nil) }
                Button("Export Map Layers…") { NotificationCenter.default.post(name: .roadRoverExport, object: nil) }
            }
        }
    }

    private func toolCommand(_ tool: EditorTool, key: KeyEquivalent) -> some View {
        Button(tool.rawValue) {
            NotificationCenter.default.post(name: .roadRoverChooseTool, object: tool)
        }
        .keyboardShortcut(key, modifiers: .command)
    }
}
