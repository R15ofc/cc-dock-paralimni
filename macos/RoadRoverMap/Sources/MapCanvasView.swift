import SwiftUI

struct MapCamera: Equatable {
    var zoom: CGFloat = 1
    var offset: CGSize = .zero
}

struct MapCanvasView: View {
    @ObservedObject var model: RoadMapModel
    @Binding var camera: MapCamera
    @Binding var focusPoint: WorldPoint?

    @State private var dragStartOffset: CGSize?
    @State private var drawStart: WorldPoint?
    @State private var draftPoints: [WorldPoint] = []
    @State private var zoomStart: CGFloat?
    @State private var hoverPoint: WorldPoint?

    var body: some View {
        GeometryReader { proxy in
            let transform = MapTransform(size: proxy.size, bounds: model.bounds, camera: camera)
            ZStack {
                Canvas(opaque: true, rendersAsynchronously: true) { context, size in
                    drawMap(context: &context, size: size, transform: transform)
                }
                .background(Color(red: 0.88, green: 0.88, blue: 0.85))
                .contentShape(Rectangle())
                .gesture(dragGesture(transform: transform))
                .simultaneousGesture(magnificationGesture)
                .simultaneousGesture(tapGesture(transform: transform))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): hoverPoint = transform.world(from: location)
                    case .ended: hoverPoint = nil
                    }
                }

                ScrollWheelCapture { delta, location in
                    let factor = pow(1.0018, -delta)
                    zoom(by: factor, around: location, transform: transform)
                }
                .allowsHitTesting(false)
            }
            .onChange(of: focusPoint) { point in
                guard let point else { return }
                withAnimation(.easeInOut(duration: 0.45)) {
                    camera.zoom = max(camera.zoom, 5)
                    camera.offset = transform.offsetToCenter(point)
                }
                focusPoint = nil
            }
            .overlay(alignment: .bottomLeading) {
                if let hoverPoint {
                    Text("x \(Int(hoverPoint.x))   z \(Int(hoverPoint.z))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(14)
                }
            }
        }
        .clipped()
    }

    private func drawMap(context: inout GraphicsContext, size: CGSize, transform: MapTransform) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.90, green: 0.90, blue: 0.87)))

        if model.showRoads || model.showSidewalks || model.showCrosswalks {
            var roads = Path()
            var sidewalks = Path()
            var markers = Path()
            var surfaces = Path()
            var tunnels = Path()
            let cellSize = max(0.75, transform.scale * 1.08)
            let visible = transform.visibleWorld.expanded(by: 4)

            for cell in model.cells where visible.contains(x: Double(cell.x), z: Double(cell.z)) {
                let point = transform.screen(WorldPoint(x: Double(cell.x), z: Double(cell.z)))
                let rect = CGRect(x: point.x - cellSize / 2, y: point.y - cellSize / 2, width: cellSize, height: cellSize)
                if cell.flags & 16 != 0, model.showTunnels {
                    tunnels.addRect(rect)
                } else if cell.flags & 2 != 0, model.showCrosswalks {
                    markers.addRect(rect)
                } else if cell.flags & 4 != 0, model.showCrosswalks {
                    surfaces.addRect(rect)
                } else if cell.flags & 1 != 0, model.showRoads {
                    roads.addRect(rect)
                } else if cell.flags & 8 != 0, model.showSidewalks {
                    sidewalks.addRect(rect)
                }
            }

            context.fill(sidewalks, with: .color(Color(red: 0.70, green: 0.71, blue: 0.69)))
            context.fill(roads, with: .color(Color(red: 0.33, green: 0.36, blue: 0.38)))
            context.fill(tunnels, with: .color(Color(red: 0.26, green: 0.29, blue: 0.32).opacity(0.72)))
            context.fill(surfaces, with: .color(.white))
            context.fill(markers, with: .color(Color(red: 0.98, green: 0.74, blue: 0.12)))
        }

        drawFeatures(context: &context, transform: transform)
        drawDraft(context: &context, transform: transform)
    }

    private func drawFeatures(context: inout GraphicsContext, transform: MapTransform) {
        for feature in model.features {
            let color = Color(hex: feature.colorHex)
            let selected = feature.id == model.selectedFeatureID
            switch feature.kind {
            case .building:
                guard feature.points.count >= 2 else { continue }
                let first = transform.screen(feature.points[0])
                let second = transform.screen(feature.points[1])
                let rect = CGRect(x: min(first.x, second.x), y: min(first.y, second.y), width: abs(second.x - first.x), height: abs(second.y - first.y))
                context.fill(Path(roundedRect: rect, cornerRadius: min(8, rect.width / 5)), with: .color(color.opacity(0.72)))
                context.stroke(Path(roundedRect: rect, cornerRadius: min(8, rect.width / 5)), with: .color(selected ? .accentColor : color.opacity(0.95)), lineWidth: selected ? 3 : 1.2)
                drawLabel(feature.name, at: CGPoint(x: rect.midX, y: rect.midY), context: &context, selected: selected)
            case .customRoad, .street:
                guard feature.points.count > 1 else { continue }
                var path = Path()
                path.move(to: transform.screen(feature.points[0]))
                feature.points.dropFirst().forEach { path.addLine(to: transform.screen($0)) }
                context.stroke(path, with: .color(selected ? .accentColor : color), style: StrokeStyle(lineWidth: selected ? 7 : 5, lineCap: .round, lineJoin: .round))
                if let midpoint = feature.points.dropFirst(feature.points.count / 2).first {
                    drawLabel(feature.name, at: transform.screen(midpoint), context: &context, selected: selected)
                }
            case .place:
                guard let point = feature.points.first else { continue }
                let screen = transform.screen(point)
                let pin = Path(ellipseIn: CGRect(x: screen.x - 7, y: screen.y - 7, width: 14, height: 14))
                context.fill(pin, with: .color(selected ? .accentColor : color))
                context.stroke(pin, with: .color(.white), lineWidth: 2)
                drawLabel(feature.name, at: CGPoint(x: screen.x, y: screen.y - 17), context: &context, selected: selected)
            }
        }
    }

    private func drawDraft(context: inout GraphicsContext, transform: MapTransform) {
        guard !draftPoints.isEmpty else { return }
        if model.tool == .building, draftPoints.count >= 2 {
            let first = transform.screen(draftPoints[0])
            let second = transform.screen(draftPoints[1])
            let rect = CGRect(x: min(first.x, second.x), y: min(first.y, second.y), width: abs(second.x - first.x), height: abs(second.y - first.y))
            context.fill(Path(rect), with: .color(.accentColor.opacity(0.25)))
            context.stroke(Path(rect), with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
        } else if model.tool == .road, draftPoints.count > 1 {
            var path = Path()
            path.move(to: transform.screen(draftPoints[0]))
            draftPoints.dropFirst().forEach { path.addLine(to: transform.screen($0)) }
            context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [8, 5]))
        }
    }

    private func drawLabel(_ text: String, at point: CGPoint, context: inout GraphicsContext, selected: Bool) {
        guard !text.isEmpty else { return }
        let label = Text(text)
            .font(.system(size: 11, weight: selected ? .bold : .semibold))
            .foregroundColor(.primary)
        context.draw(context.resolve(label), at: point, anchor: .center)
    }

    private func dragGesture(transform: MapTransform) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                let world = transform.world(from: value.location)
                switch model.tool {
                case .browse:
                    if dragStartOffset == nil { dragStartOffset = camera.offset }
                    let start = dragStartOffset ?? .zero
                    camera.offset = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                case .building:
                    if drawStart == nil { drawStart = transform.world(from: value.startLocation) }
                    draftPoints = [drawStart ?? world, world]
                case .road:
                    if draftPoints.isEmpty { draftPoints = [transform.world(from: value.startLocation)] }
                    if let last = draftPoints.last, hypot(last.x - world.x, last.z - world.z) > max(1, 5 / Double(transform.scale)) {
                        draftPoints.append(world)
                    }
                case .label:
                    break
                }
            }
            .onEnded { _ in
                defer {
                    dragStartOffset = nil
                    drawStart = nil
                    draftPoints = []
                }
                if model.tool == .building, draftPoints.count == 2 {
                    model.addFeature(MapFeature(kind: .building, name: "New Building", details: "", colorHex: "#D08A54", points: draftPoints))
                } else if model.tool == .road, draftPoints.count > 1 {
                    model.addFeature(MapFeature(kind: .customRoad, name: "New Road", details: "", colorHex: "#F2A93B", points: draftPoints))
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if zoomStart == nil { zoomStart = camera.zoom }
                camera.zoom = min(80, max(0.35, (zoomStart ?? 1) * value))
            }
            .onEnded { _ in zoomStart = nil }
    }

    private func tapGesture(transform: MapTransform) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let world = transform.world(from: value.location)
                if model.tool == .label {
                    model.addFeature(MapFeature(kind: .place, name: "New Place", details: "", colorHex: "#E94D4D", points: [world]))
                } else if model.tool == .browse {
                    model.selectNearest(to: world, radius: max(4, 16 / Double(transform.scale)))
                }
            }
    }

    private func zoom(by factor: CGFloat, around location: CGPoint, transform: MapTransform) {
        let before = transform.world(from: location)
        camera.zoom = min(80, max(0.35, camera.zoom * factor))
        let afterTransform = MapTransform(size: transform.size, bounds: model.bounds, camera: camera)
        let after = afterTransform.screen(before)
        camera.offset.width += location.x - after.x
        camera.offset.height += location.y - after.y
    }
}

struct MapTransform {
    let size: CGSize
    let bounds: MapBounds
    let camera: MapCamera

    var scale: CGFloat {
        let width = max(1, bounds.maxX - bounds.minX)
        let depth = max(1, bounds.maxZ - bounds.minZ)
        return min(size.width / CGFloat(width), size.height / CGFloat(depth)) * camera.zoom * 0.92
    }

    var visibleWorld: WorldRect {
        let topLeft = world(from: .zero)
        let bottomRight = world(from: CGPoint(x: size.width, y: size.height))
        return WorldRect(minX: min(topLeft.x, bottomRight.x), maxX: max(topLeft.x, bottomRight.x), minZ: min(topLeft.z, bottomRight.z), maxZ: max(topLeft.z, bottomRight.z))
    }

    func screen(_ point: WorldPoint) -> CGPoint {
        let center = bounds.center
        return CGPoint(
            x: size.width / 2 + CGFloat(point.x - center.x) * scale + camera.offset.width,
            y: size.height / 2 - CGFloat(point.z - center.z) * scale + camera.offset.height
        )
    }

    func world(from point: CGPoint) -> WorldPoint {
        let center = bounds.center
        return WorldPoint(
            x: center.x + Double((point.x - size.width / 2 - camera.offset.width) / scale),
            z: center.z - Double((point.y - size.height / 2 - camera.offset.height) / scale)
        )
    }

    func offsetToCenter(_ point: WorldPoint) -> CGSize {
        let base = MapTransform(size: size, bounds: bounds, camera: MapCamera(zoom: camera.zoom, offset: .zero)).screen(point)
        return CGSize(width: size.width / 2 - base.x, height: size.height / 2 - base.y)
    }
}

struct WorldRect {
    let minX: Double
    let maxX: Double
    let minZ: Double
    let maxZ: Double

    func contains(x: Double, z: Double) -> Bool {
        x >= minX && x <= maxX && z >= minZ && z <= maxZ
    }

    func expanded(by amount: Double) -> WorldRect {
        WorldRect(minX: minX - amount, maxX: maxX + amount, minZ: minZ - amount, maxZ: maxZ + amount)
    }
}

private struct ScrollWheelCapture: NSViewRepresentable {
    let action: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> ScrollView {
        let view = ScrollView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: ScrollView, context: Context) {
        nsView.action = action
    }

    final class ScrollView: NSView {
        var action: ((CGFloat, CGPoint) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            action?(event.scrollingDeltaY, convert(event.locationInWindow, from: nil))
        }
        override func hitTest(_ point: NSPoint) -> NSView? { self }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red, green, blue: Double
        if cleaned.count == 6 {
            red = Double((value >> 16) & 0xff) / 255
            green = Double((value >> 8) & 0xff) / 255
            blue = Double(value & 0xff) / 255
        } else {
            red = 0.22; green = 0.48; blue = 0.92
        }
        self.init(red: red, green: green, blue: blue)
    }
}
