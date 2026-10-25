import Foundation

enum SettingsKey {
    static let unit = "export.unit"
    static let upAxis = "export.upAxis"
    static let obj = "export.obj"
    static let stl = "export.stl"
    static let ply = "export.ply"
    static let lite = "export.fusionLite"
    static let liteTriangles = "export.fusionLiteTriangles"
    static let splitClasses = "lidar.splitClasses"
    static let maxDepth = "lidar.maxDepth"
    static let voxelCM = "lidar.voxelCM"
    static let objectTripod = "object.tripod"
    static let lidarPiece = "lidar.piece"
}

enum ExportUnit: String, CaseIterable, Identifiable {
    case mm, cm, m

    var id: String { rawValue }

    var scale: Float {
        switch self {
        case .mm: return 1000
        case .cm: return 100
        case .m: return 1
        }
    }

    var title: String {
        switch self {
        case .mm: return "Milímetros (padrão do Fusion)"
        case .cm: return "Centímetros"
        case .m: return "Metros"
        }
    }
}

enum UpAxis: String, CaseIterable, Identifiable {
    case z, y

    var id: String { rawValue }

    var title: String {
        switch self {
        case .z: return "Z para cima (Fusion, impressão 3D)"
        case .y: return "Y para cima (Blender, USD)"
        }
    }
}

struct ExportOptions {
    var unit: ExportUnit = .mm
    var upAxis: UpAxis = .z
    var writeOBJ = true
    var writeSTL = true
    var writePLY = false
    var fusionLite = true
    var liteTriangles = 20_000
    var splitClasses = false

    static var current: ExportOptions {
        let d = UserDefaults.standard
        var o = ExportOptions()
        if let s = d.string(forKey: SettingsKey.unit), let u = ExportUnit(rawValue: s) { o.unit = u }
        if let s = d.string(forKey: SettingsKey.upAxis), let a = UpAxis(rawValue: s) { o.upAxis = a }
        if d.object(forKey: SettingsKey.obj) != nil { o.writeOBJ = d.bool(forKey: SettingsKey.obj) }
        if d.object(forKey: SettingsKey.stl) != nil { o.writeSTL = d.bool(forKey: SettingsKey.stl) }
        if d.object(forKey: SettingsKey.ply) != nil { o.writePLY = d.bool(forKey: SettingsKey.ply) }
        if d.object(forKey: SettingsKey.lite) != nil { o.fusionLite = d.bool(forKey: SettingsKey.lite) }
        if d.object(forKey: SettingsKey.splitClasses) != nil { o.splitClasses = d.bool(forKey: SettingsKey.splitClasses) }
        let n = d.integer(forKey: SettingsKey.liteTriangles)
        if n > 0 { o.liteTriangles = n }
        return o
    }
}

struct LidarOptions {
    var maxDepth: Float = 4.0
    var voxelSize: Float = 0.01
    /// Passo na imagem de profundidade (1 = todos os pixels).
    var pixelStep = 2

    static var current: LidarOptions {
        let d = UserDefaults.standard
        var o = LidarOptions()
        // Modo Peça: o LiDAR rende mais perto (até ~1 m) e com todos os pixels.
        if d.bool(forKey: SettingsKey.lidarPiece) {
            o.maxDepth = 1.0
            o.voxelSize = 0.002
            o.pixelStep = 1
            return o
        }
        let depth = d.double(forKey: SettingsKey.maxDepth)
        if depth > 0 { o.maxDepth = Float(depth) }
        let voxel = d.double(forKey: SettingsKey.voxelCM)
        if voxel > 0 { o.voxelSize = Float(voxel) / 100 }
        return o
    }
}
