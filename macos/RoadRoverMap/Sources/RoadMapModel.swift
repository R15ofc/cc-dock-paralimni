import AppKit
import Foundation
import SwiftUI

struct RoadCell: Identifiable, Hashable {
    let x: Int
    let z: Int
    let y: Int
    let flags: UInt8

    var id: Int64 { Int64(x) << 32 ^ Int64(UInt32(bitPattern: Int32(z))) }
}

struct WorldPoint: Codable, Hashable {
    var x: Double
    var z: Double
}

enum FeatureKind: String, Codable, CaseIterable, Identifiable {
    case building = "Building"
    case street = "Street"
    case place = "Place"
    case customRoad = "Road"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .building: return "building.2.fill"
        case .street: return "signpost.right.fill"
        case .place: return "mappin.circle.fill"
        case .customRoad: return "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
}

struct MapFeature: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: FeatureKind
    var name: String
    var details: String
    var colorHex: String
    var points: [WorldPoint]
}

enum EditorTool: String, CaseIterable, Identifiable {
    case browse = "Browse"
    case road = "Road"
    case building = "Building"
    case label = "Label"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .browse: return "hand.draw.fill"
        case .road: return "point.topleft.down.to.point.bottomright.curvepath"
        case .building: return "building.2.fill"
        case .label: return "textformat"
        }
    }
}

struct MapBounds: Hashable {
    var minX = 0
    var maxX = 1
    var minZ = 0
    var maxZ = 1

    var center: WorldPoint {
        WorldPoint(x: Double(minX + maxX) / 2, z: Double(minZ + maxZ) / 2)
    }
}

@MainActor
final class RoadMapModel: ObservableObject {
    @Published private(set) var cells: [RoadCell] = []
    @Published var features: [MapFeature] = []
    @Published var selectedFeatureID: UUID?
    @Published var tool: EditorTool = .browse
    @Published var searchText = ""
    @Published var showRoads = true
    @Published var showSidewalks = true
    @Published var showCrosswalks = true
    @Published var showTunnels = true
    @Published var statusText = "Loading map…"

    private(set) var bounds = MapBounds()
    private var undoStack: [[MapFeature]] = []
    private var redoStack: [[MapFeature]] = []

    var selectedFeature: MapFeature? {
        guard let selectedFeatureID else { return nil }
        return features.first { $0.id == selectedFeatureID }
    }

    var searchResults: [MapFeature] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return features.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.details.localizedCaseInsensitiveContains(query)
        }
    }

    init() {
        loadFeatures()
        Task { await loadMap() }
    }

    func loadMap() async {
        guard let url = Bundle.main.url(forResource: "minecraft_overworld", withExtension: "rrmap") else {
            statusText = "Embedded road map is missing"
            return
        }
        do {
            let parsed = try await Task.detached(priority: .userInitiated) {
                try Self.parseMap(at: url)
            }.value
            cells = parsed.cells
            bounds = parsed.bounds
            statusText = "\(cells.count.formatted()) mapped cells"
        } catch {
            statusText = "Could not open map: \(error.localizedDescription)"
        }
    }

    func addFeature(_ feature: MapFeature) {
        checkpoint()
        features.append(feature)
        selectedFeatureID = feature.id
        saveFeatures()
    }

    func updateSelected(_ change: (inout MapFeature) -> Void) {
        guard let id = selectedFeatureID, let index = features.firstIndex(where: { $0.id == id }) else { return }
        checkpoint()
        change(&features[index])
        saveFeatures()
    }

    func deleteSelected() {
        guard let id = selectedFeatureID else { return }
        checkpoint()
        features.removeAll { $0.id == id }
        selectedFeatureID = nil
        saveFeatures()
    }

    func selectNearest(to point: WorldPoint, radius: Double) {
        let match = features.min { featureDistance($0, point) < featureDistance($1, point) }
        if let match, featureDistance(match, point) <= radius {
            selectedFeatureID = match.id
        } else {
            selectedFeatureID = nil
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(features)
        features = previous
        selectedFeatureID = nil
        saveFeatures()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(features)
        features = next
        selectedFeatureID = nil
        saveFeatures()
    }

    func exportFeatures() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "RoadRover Map Layers.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try JSONEncoder.pretty.encode(features)
            try data.write(to: url, options: .atomic)
            statusText = "Layers exported"
        } catch {
            statusText = "Export failed: \(error.localizedDescription)"
        }
    }

    func importFeatures() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try JSONDecoder().decode([MapFeature].self, from: Data(contentsOf: url))
            checkpoint()
            features = imported
            selectedFeatureID = nil
            saveFeatures()
            statusText = "Imported \(imported.count) features"
        } catch {
            statusText = "Import failed: \(error.localizedDescription)"
        }
    }

    private func checkpoint() {
        undoStack.append(features)
        if undoStack.count > 80 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func featureDistance(_ feature: MapFeature, _ point: WorldPoint) -> Double {
        feature.points.map { hypot($0.x - point.x, $0.z - point.z) }.min() ?? .infinity
    }

    nonisolated private static func parseMap(at url: URL) throws -> (cells: [RoadCell], bounds: MapBounds) {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 8 else { throw MapError.truncated }
        let magic = data.readUInt32(at: 0)
        guard magic == 0x52524D31 else { throw MapError.invalidHeader }
        let count = Int(data.readUInt32(at: 4))
        guard count >= 0, data.count >= 8 + count * 11 else { throw MapError.truncated }

        var cells: [RoadCell] = []
        cells.reserveCapacity(count)
        var bounds = MapBounds(minX: .max, maxX: .min, minZ: .max, maxZ: .min)
        for index in 0..<count {
            let offset = 8 + index * 11
            let x = Int(Int32(bitPattern: data.readUInt32(at: offset)))
            let z = Int(Int32(bitPattern: data.readUInt32(at: offset + 4)))
            let y = Int(Int16(bitPattern: data.readUInt16(at: offset + 8)))
            let flags = data[offset + 10]
            cells.append(RoadCell(x: x, z: z, y: y, flags: flags))
            bounds.minX = min(bounds.minX, x)
            bounds.maxX = max(bounds.maxX, x)
            bounds.minZ = min(bounds.minZ, z)
            bounds.maxZ = max(bounds.maxZ, z)
        }
        return (cells, bounds)
    }

    private var featuresURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("RoadRover Map", isDirectory: true)
            .appendingPathComponent("features.json")
    }

    private func loadFeatures() {
        do {
            features = try JSONDecoder().decode([MapFeature].self, from: Data(contentsOf: featuresURL))
        } catch {
            features = []
        }
    }

    private func saveFeatures() {
        do {
            try FileManager.default.createDirectory(at: featuresURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.pretty.encode(features).write(to: featuresURL, options: .atomic)
        } catch {
            statusText = "Could not save layers: \(error.localizedDescription)"
        }
    }
}

private enum MapError: LocalizedError {
    case invalidHeader
    case truncated

    var errorDescription: String? {
        switch self {
        case .invalidHeader: return "Invalid RRM1 map"
        case .truncated: return "Map data is truncated"
        }
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }

    func readUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) << 24 |
        UInt32(self[offset + 1]) << 16 |
        UInt32(self[offset + 2]) << 8 |
        UInt32(self[offset + 3])
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
