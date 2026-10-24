import Foundation
import ModelIO

enum ExportError: LocalizedError {
    case emptyMesh, emptyCloud, unreadable, nothingToSave

    var errorDescription: String? {
        switch self {
        case .emptyMesh: return "A malha ficou vazia. Escaneie mais devagar e mais perto."
        case .emptyCloud: return "Nenhum ponto foi gravado."
        case .unreadable: return "Não foi possível ler o modelo gerado."
        case .nothingToSave: return "Nada para salvar ainda."
        }
    }
}

enum Exporter {
    /// Escreve a malha nos formatos ligados nos Ajustes. Retorna os arquivos criados.
    static func exportMesh(_ raw: MeshData, baseName: String, folder: URL, options: ExportOptions) throws -> [URL] {
        guard !raw.isEmpty else { throw ExportError.emptyMesh }
        let mesh = raw.transformed(unit: options.unit, up: options.upAxis)
        var out: [URL] = []

        if options.writeSTL {
            let url = folder.appendingPathComponent("\(baseName).stl")
            try MeshWriter.writeSTL(mesh, to: url)
            out.append(url)
        }
        if options.writeOBJ {
            let url = folder.appendingPathComponent("\(baseName).obj")
            try MeshWriter.writeOBJ(mesh, to: url)
            out.append(url)
        }
        if options.writePLY {
            let url = folder.appendingPathComponent("\(baseName).ply")
            try MeshWriter.writePLY(mesh, to: url)
            out.append(url)
        }
        if options.fusionLite && mesh.triangleCount > options.liteTriangles {
            let lite = mesh.simplified(toAtMost: options.liteTriangles)
            if !lite.isEmpty {
                let url = folder.appendingPathComponent("\(baseName)_fusion-leve.stl")
                try MeshWriter.writeSTL(lite, to: url)
                out.append(url)
            }
        }
        if out.isEmpty {
            let url = folder.appendingPathComponent("\(baseName).stl")
            try MeshWriter.writeSTL(mesh, to: url)
            out.append(url)
        }
        return out
    }

    static func exportCloud(_ raw: PointCloud, baseName: String, folder: URL, options: ExportOptions) throws -> [URL] {
        guard raw.count > 0 else { throw ExportError.emptyCloud }
        var cloud = raw
        cloud.points = raw.points.map { Geometry.convert($0, unit: options.unit, up: options.upAxis) }
        let ply = folder.appendingPathComponent("\(baseName)_nuvem.ply")
        let pts = folder.appendingPathComponent("\(baseName)_nuvem.pts")
        try MeshWriter.writeCloudPLY(cloud, to: ply)
        try MeshWriter.writeCloudPTS(cloud, to: pts)
        return [ply, pts]
    }

    /// Converte um USDZ (Object Capture ou RoomPlan) nos formatos de malha.
    static func exportUSDZ(_ usdz: URL, baseName: String, folder: URL, options: ExportOptions) throws -> (files: [URL], triangles: Int) {
        let asset = MDLAsset(url: usdz)
        guard asset.count > 0 else { throw ExportError.unreadable }
        let mesh = MeshData.from(asset: asset)
        if mesh.isEmpty {
            // Plano B: conversão nativa da Apple.
            let obj = folder.appendingPathComponent("\(baseName).obj")
            try asset.export(to: obj)
            return ([obj], 0)
        }
        return (try exportMesh(mesh, baseName: baseName, folder: folder, options: options), mesh.triangleCount)
    }

    static func formatCount(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "pt_BR")
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func formatLength(_ meters: Float) -> String {
        if meters < 1 { return String(format: "%.1f cm", meters * 100).replacingOccurrences(of: ".", with: ",") }
        return String(format: "%.2f m", meters).replacingOccurrences(of: ".", with: ",")
    }

    static func formatArea(_ squareMeters: Float) -> String {
        String(format: "%.2f m²", squareMeters).replacingOccurrences(of: ".", with: ",")
    }
}
