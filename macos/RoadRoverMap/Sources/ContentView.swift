import SwiftUI

struct ContentView: View {
    @StateObject private var model = RoadMapModel()
    @State private var camera = MapCamera()
    @State private var focusPoint: WorldPoint?
    @State private var showLayers = false

    var body: some View {
        ZStack {
            MapCanvasView(model: model, camera: $camera, focusPoint: $focusPoint)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }
            .padding(16)

            HStack {
                toolPalette
                Spacer()
                if model.selectedFeature != nil {
                    inspector
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 86)
            .padding(.bottom, 64)
        }
        .frame(minWidth: 980, minHeight: 640)
        .animation(.easeInOut(duration: 0.25), value: model.selectedFeatureID)
        .onReceive(NotificationCenter.default.publisher(for: .roadRoverChooseTool)) { notification in
            if let tool = notification.object as? EditorTool { model.tool = tool }
        }
        .onReceive(NotificationCenter.default.publisher(for: .roadRoverUndo)) { _ in model.undo() }
        .onReceive(NotificationCenter.default.publisher(for: .roadRoverRedo)) { _ in model.redo() }
        .onReceive(NotificationCenter.default.publisher(for: .roadRoverImport)) { _ in model.importFeatures() }
        .onReceive(NotificationCenter.default.publisher(for: .roadRoverExport)) { _ in model.exportFeatures() }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "map.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 9))
                Text("RoadRover Map")
                    .font(.system(size: 15, weight: .semibold))
            }

            searchField
                .frame(maxWidth: 420)

            Spacer()

            HStack(spacing: 5) {
                toolButton(.browse)
                toolButton(.road)
                toolButton(.building)
                toolButton(.label)
            }
            .padding(4)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13))

            Button {
                showLayers.toggle()
            } label: {
                Image(systemName: "square.3.layers.3d")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .popover(isPresented: $showLayers, arrowEdge: .top) { layersPopover }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.5), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 7)
    }

    private var searchField: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search places and streets", text: $model.searchText)
                    .textFieldStyle(.plain)
                if !model.searchText.isEmpty {
                    Button { model.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.78), in: RoundedRectangle(cornerRadius: 11))

            if !model.searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(model.searchResults.prefix(6)) { feature in
                        Button {
                            model.selectedFeatureID = feature.id
                            focusPoint = feature.points.first
                            model.searchText = ""
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: feature.kind.symbol)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.name).font(.system(size: 13, weight: .semibold))
                                    Text(feature.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 44)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 4)
            }
        }
    }

    private var toolPalette: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CREATE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(EditorTool.allCases) { tool in
                Button { model.tool = tool } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tool.symbol).frame(width: 20)
                        Text(tool.rawValue).font(.system(size: 13, weight: .medium))
                        Spacer()
                        if model.tool == tool {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(model.tool == tool ? Color.accentColor.opacity(0.17) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }

            Divider()
            Text("Draw buildings by dragging. Click once to add a named place. Road mode records a smooth path.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 210)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.45), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.1), radius: 14, y: 5)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Feature").font(.headline)
                Spacer()
                Button { model.selectedFeatureID = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            if let feature = model.selectedFeature {
                LabeledContent("Type") {
                    Picker("", selection: binding(\.kind, fallback: feature.kind)) {
                        ForEach(FeatureKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                TextField("Name", text: binding(\.name, fallback: feature.name))
                    .textFieldStyle(.roundedBorder)
                TextField("Details", text: binding(\.details, fallback: feature.details), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                LabeledContent("Color") {
                    ColorPicker("", selection: colorBinding(feature.colorHex), supportsOpacity: false)
                        .labelsHidden()
                }
                Divider()
                Button(role: .destructive) { model.deleteSelected() } label: {
                    Label("Delete Feature", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .frame(width: 270)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.45), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }

    private var bottomBar: some View {
        HStack {
            Text(model.statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                compactButton("minus") { camera.zoom = max(0.35, camera.zoom / 1.35) }
                Text("\(Int(camera.zoom * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .frame(width: 52)
                compactButton("plus") { camera.zoom = min(80, camera.zoom * 1.35) }
                compactButton("scope") { withAnimation { camera = MapCamera() } }
            }
            .padding(5)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var layersPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Map Layers").font(.headline)
            Toggle("Roads", isOn: $model.showRoads)
            Toggle("Crosswalks", isOn: $model.showCrosswalks)
            Toggle("Sidewalks", isOn: $model.showSidewalks)
            Toggle("Tunnels", isOn: $model.showTunnels)
            Divider()
            Button("Import Layers…") { model.importFeatures() }
            Button("Export Layers…") { model.exportFeatures() }
        }
        .padding(16)
        .frame(width: 220)
    }

    private func toolButton(_ tool: EditorTool) -> some View {
        Button { model.tool = tool } label: {
            Image(systemName: tool.symbol)
                .frame(width: 28, height: 28)
                .foregroundStyle(model.tool == tool ? Color.white : Color.primary)
                .background(model.tool == tool ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(tool.rawValue)
    }

    private func compactButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 24, height: 24) }
            .buttonStyle(.plain)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MapFeature, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { model.selectedFeature?[keyPath: keyPath] ?? fallback },
            set: { value in model.updateSelected { $0[keyPath: keyPath] = value } }
        )
    }

    private func colorBinding(_ fallbackHex: String) -> Binding<Color> {
        Binding(
            get: { Color(hex: model.selectedFeature?.colorHex ?? fallbackHex) },
            set: { color in
                guard let components = NSColor(color).usingColorSpace(.deviceRGB) else { return }
                let hex = String(format: "#%02X%02X%02X", Int(components.redComponent * 255), Int(components.greenComponent * 255), Int(components.blueComponent * 255))
                model.updateSelected { $0.colorHex = hex }
            }
        )
    }
}
