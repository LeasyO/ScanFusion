import Foundation
import simd
import ModelIO
import ARKit

// MARK: - Malha

/// Malha triangular simples: posições + índices (3 por triângulo).
struct MeshData {
    var positions: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    var triangleCount: Int { indices.count / 3 }
    var isEmpty: Bool { indices.isEmpty }

    mutating func append(_ other: MeshData) {
        let base = UInt32(positions.count)
        positions.append(contentsOf: other.positions)
        indices.append(contentsOf: other.indices.map { $0 + base })
    }

    func bounds() -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard var lo = positions.first else { return nil }
        var hi = lo
        for p in positions {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        return (lo, hi)
    }

    /// Converte de metros/Y-para-cima (ARKit) para a unidade e eixo escolhidos.
    func transformed(unit: ExportUnit, up: UpAxis) -> MeshData {
        var out = self
        out.positions = positions.map { Geometry.convert($0, unit: unit, up: up) }
        return out
    }

    /// Simplificação por agrupamento de vértices (rápida, boa para o Fusion).
    func simplified(cellSize: Float) -> MeshData {
        guard cellSize > 0 else { return self }
        var lookup: [SIMD3<Int32>: UInt32] = [:]
        var sums: [SIMD3<Float>] = []
        var counts: [Float] = []
        var remap = [UInt32](repeating: 0, count: positions.count)

        for (i, p) in positions.enumerated() {
            let key = SIMD3<Int32>(
                Int32((p.x / cellSize).rounded(.down)),
                Int32((p.y / cellSize).rounded(.down)),
                Int32((p.z / cellSize).rounded(.down))
            )
            if let id = lookup[key] {
                remap[i] = id
                sums[Int(id)] += p
                counts[Int(id)] += 1
            } else {
                let id = UInt32(sums.count)
                lookup[key] = id
                remap[i] = id
                sums.append(p)
                counts.append(1)
            }
        }

        var out = MeshData()
        out.positions = zip(sums, counts).map { $0 / $1 }
        var seen = Set<SIMD3<UInt32>>()
        var t = 0
        while t + 2 < indices.count {
            let a = remap[Int(indices[t])]
            let b = remap[Int(indices[t + 1])]
            let c = remap[Int(indices[t + 2])]
            t += 3
            if a == b || b == c || a == c { continue }
            let key: SIMD3<UInt32>
            if a < b && a < c {
                key = SIMD3(a, b, c)
            } else if b < a && b < c {
                key = SIMD3(b, c, a)
            } else {
                key = SIMD3(c, a, b)
            }
            if seen.insert(key).inserted {
                out.indices.append(a)
                out.indices.append(b)
                out.indices.append(c)
            }
        }
        return out
    }

    /// Reduz até ficar com no máximo `target` triângulos.
    func simplified(toAtMost target: Int) -> MeshData {
        guard triangleCount > target, let box = bounds() else { return self }
        let diagonal = simd_length(box.max - box.min)
        guard diagonal > 0 else { return self }
        var cell = diagonal / 500
        var result = self
        for _ in 0..<16 {
            result = simplified(cellSize: cell)
            if result.triangleCount <= target { break }
            cell *= 1.3
        }
        return result
    }
}

enum Geometry {
    static func convert(_ p: SIMD3<Float>, unit: ExportUnit, up: UpAxis) -> SIMD3<Float> {
        let q = p * unit.scale
        switch up {
        case .y: return q
        case .z: return SIMD3(q.x, -q.z, q.y)   // rotação de +90° no eixo X
        }
    }

    static func xyz(_ v: SIMD4<Float>) -> SIMD3<Float> { SIMD3(v.x, v.y, v.z) }

    static func apply(_ m: simd_float4x4, _ p: SIMD3<Float>) -> SIMD3<Float> {
        xyz(m * SIMD4<Float>(p.x, p.y, p.z, 1))
    }
}

// MARK: - Leitura de ARKit (LiDAR)

enum MeshClass: UInt8, CaseIterable {
    case none = 0, wall, floor, ceiling, table, seat, window, door

    var fileSuffix: String {
        switch self {
        case .none: return "outros"
        case .wall: return "paredes"
        case .floor: return "piso"
        case .ceiling: return "teto"
        case .table: return "mesas"
        case .seat: return "assentos"
        case .window: return "janelas"
        case .door: return "portas"
        }
    }
}

extension MeshData {
    static func from(anchors: [ARMeshAnchor]) -> MeshData {
        var mesh = MeshData()
        for anchor in anchors {
            let g = anchor.geometry
            let t = anchor.transform
            let base = UInt32(mesh.positions.count)

            let v = g.vertices
            let vPtr = v.buffer.contents().advanced(by: v.offset)
            mesh.positions.reserveCapacity(mesh.positions.count + v.count)
            for i in 0..<v.count {
                let o = i * v.stride
                let p = SIMD3<Float>(
                    vPtr.load(fromByteOffset: o, as: Float.self),
                    vPtr.load(fromByteOffset: o + 4, as: Float.self),
                    vPtr.load(fromByteOffset: o + 8, as: Float.self)
                )
                mesh.positions.append(Geometry.apply(t, p))
            }

            let f = g.faces
            guard f.indexCountPerPrimitive == 3 else { continue }
            let fPtr = f.buffer.contents()
            let total = f.count * 3
            mesh.indices.reserveCapacity(mesh.indices.count + total)
            for i in 0..<total {
                let idx: UInt32
                if f.bytesPerIndex == 4 {
                    idx = fPtr.load(fromByteOffset: i * 4, as: UInt32.self)
                } else {
                    idx = UInt32(fPtr.load(fromByteOffset: i * 2, as: UInt16.self))
                }
                mesh.indices.append(base + idx)
            }
        }
        return mesh
    }

    /// Separa a malha do LiDAR por tipo de superfície (parede, piso, teto…).
    static func split(anchors: [ARMeshAnchor]) -> [MeshClass: MeshData] {
        var result: [MeshClass: MeshData] = [:]
        for anchor in anchors {
            let g = anchor.geometry
            let t = anchor.transform
            let v = g.vertices
            let vPtr = v.buffer.contents().advanced(by: v.offset)
            let f = g.faces
            guard f.indexCountPerPrimitive == 3 else { continue }
            let fPtr = f.buffer.contents()

            func vertex(_ index: Int) -> SIMD3<Float> {
                let o = index * v.stride
                let p = SIMD3<Float>(
                    vPtr.load(fromByteOffset: o, as: Float.self),
                    vPtr.load(fromByteOffset: o + 4, as: Float.self),
                    vPtr.load(fromByteOffset: o + 8, as: Float.self)
                )
                return Geometry.apply(t, p)
            }
            func index(_ i: Int) -> Int {
                if f.bytesPerIndex == 4 {
                    return Int(fPtr.load(fromByteOffset: i * 4, as: UInt32.self))
                }
                return Int(fPtr.load(fromByteOffset: i * 2, as: UInt16.self))
            }

            for face in 0..<f.count {
                var cls = MeshClass.none
                if let c = g.classification {
                    let raw = c.buffer.contents().load(fromByteOffset: c.offset + face * c.stride, as: UInt8.self)
                    cls = MeshClass(rawValue: raw) ?? .none
                }
                var part = result[cls] ?? MeshData()
                let base = UInt32(part.positions.count)
                part.positions.append(vertex(index(face * 3)))
                part.positions.append(vertex(index(face * 3 + 1)))
                part.positions.append(vertex(index(face * 3 + 2)))
                part.indices.append(base)
                part.indices.append(base + 1)
                part.indices.append(base + 2)
                result[cls] = part
            }
        }
        return result
    }
}

// MARK: - Leitura de USDZ (Object Capture e RoomPlan)

extension MeshData {
    static func from(asset: MDLAsset) -> MeshData {
        var mesh = MeshData()
        for case let m as MDLMesh in asset.childObjects(of: MDLMesh.self) {
            let world = MDLTransform.globalTransform(with: m, atTime: 0)
            guard let attr = m.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3) else {
                continue
            }
            let base = UInt32(mesh.positions.count)
            for i in 0..<m.vertexCount {
                let o = i * attr.stride
                let p = SIMD3<Float>(
                    attr.dataStart.load(fromByteOffset: o, as: Float.self),
                    attr.dataStart.load(fromByteOffset: o + 4, as: Float.self),
                    attr.dataStart.load(fromByteOffset: o + 8, as: Float.self)
                )
                mesh.positions.append(Geometry.apply(world, p))
            }
            guard let submeshes = m.submeshes as? [MDLSubmesh] else { continue }
            for sub in submeshes where sub.geometryType == .triangles {
                let map = sub.indexBuffer(asIndexType: .uInt32).map()
                for i in 0..<sub.indexCount {
                    mesh.indices.append(base + map.bytes.load(fromByteOffset: i * 4, as: UInt32.self))
                }
            }
        }
        return mesh
    }
}

// MARK: - Nuvem de pontos

struct PointCloud {
    var points: [SIMD3<Float>] = []
    var colors: [SIMD3<UInt8>] = []
    var count: Int { points.count }
}

// MARK: - Escrita de arquivos

final class BufferedWriter {
    private let handle: FileHandle
    private var buffer = Data()

    init(url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        buffer.reserveCapacity(1 << 20)
    }

    func write(_ s: String) {
        buffer.append(contentsOf: Array(s.utf8))
        if buffer.count >= 1 << 20 { flush() }
    }

    func write(_ d: Data) {
        buffer.append(d)
        if buffer.count >= 1 << 20 { flush() }
    }

    private func flush() {
        guard !buffer.isEmpty else { return }
        handle.write(buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    func close() throws {
        flush()
        try handle.close()
    }
}

enum MeshWriter {
    static func fmt(_ v: Float) -> String { String(format: "%.4f", v) }

    static func writeSTL(_ mesh: MeshData, to url: URL) throws {
        var data = Data(capacity: 84 + mesh.triangleCount * 50)
        var header = [UInt8](repeating: 0x20, count: 80)
        for (i, b) in Array("ScanFusion binary STL".utf8).enumerated() { header[i] = b }
        data.append(contentsOf: header)
        appendUInt32(&data, UInt32(mesh.triangleCount))
        var t = 0
        while t + 2 < mesh.indices.count {
            let a = mesh.positions[Int(mesh.indices[t])]
            let b = mesh.positions[Int(mesh.indices[t + 1])]
            let c = mesh.positions[Int(mesh.indices[t + 2])]
            t += 3
            var n = simd_cross(b - a, c - a)
            let len = simd_length(n)
            n = len > 0 ? n / len : SIMD3<Float>(0, 0, 0)
            for v in [n, a, b, c] {
                appendFloat(&data, v.x)
                appendFloat(&data, v.y)
                appendFloat(&data, v.z)
            }
            data.append(contentsOf: [UInt8(0), UInt8(0)])
        }
        try data.write(to: url, options: .atomic)
    }

    static func writeOBJ(_ mesh: MeshData, to url: URL) throws {
        let w = try BufferedWriter(url: url)
        w.write("# ScanFusion\n")
        for p in mesh.positions {
            w.write("v \(fmt(p.x)) \(fmt(p.y)) \(fmt(p.z))\n")
        }
        var t = 0
        while t + 2 < mesh.indices.count {
            w.write("f \(mesh.indices[t] + 1) \(mesh.indices[t + 1] + 1) \(mesh.indices[t + 2] + 1)\n")
            t += 3
        }
        try w.close()
    }

    static func writePLY(_ mesh: MeshData, to url: URL) throws {
        let w = try BufferedWriter(url: url)
        w.write("ply\nformat binary_little_endian 1.0\ncomment ScanFusion\n")
        w.write("element vertex \(mesh.positions.count)\nproperty float x\nproperty float y\nproperty float z\n")
        w.write("element face \(mesh.triangleCount)\nproperty list uchar int vertex_indices\nend_header\n")
        var chunk = Data()
        chunk.reserveCapacity(1 << 20)
        for p in mesh.positions {
            appendFloat(&chunk, p.x)
            appendFloat(&chunk, p.y)
            appendFloat(&chunk, p.z)
            if chunk.count > 1 << 20 { w.write(chunk); chunk.removeAll(keepingCapacity: true) }
        }
        var t = 0
        while t + 2 < mesh.indices.count {
            chunk.append(UInt8(3))
            appendUInt32(&chunk, mesh.indices[t])
            appendUInt32(&chunk, mesh.indices[t + 1])
            appendUInt32(&chunk, mesh.indices[t + 2])
            t += 3
            if chunk.count > 1 << 20 { w.write(chunk); chunk.removeAll(keepingCapacity: true) }
        }
        w.write(chunk)
        try w.close()
    }

    static func writeCloudPLY(_ cloud: PointCloud, to url: URL) throws {
        let w = try BufferedWriter(url: url)
        w.write("ply\nformat binary_little_endian 1.0\ncomment ScanFusion\n")
        w.write("element vertex \(cloud.count)\nproperty float x\nproperty float y\nproperty float z\n")
        w.write("property uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n")
        var chunk = Data()
        chunk.reserveCapacity(1 << 20)
        for i in 0..<cloud.count {
            let p = cloud.points[i]
            let c = cloud.colors[i]
            appendFloat(&chunk, p.x)
            appendFloat(&chunk, p.y)
            appendFloat(&chunk, p.z)
            chunk.append(contentsOf: [c.x, c.y, c.z])
            if chunk.count > 1 << 20 { w.write(chunk); chunk.removeAll(keepingCapacity: true) }
        }
        w.write(chunk)
        try w.close()
    }

    /// Formato PTS (texto) — abre no Autodesk ReCap e daí vai para o Revit.
    static func writeCloudPTS(_ cloud: PointCloud, to url: URL) throws {
        let w = try BufferedWriter(url: url)
        w.write("\(cloud.count)\n")
        for i in 0..<cloud.count {
            let p = cloud.points[i]
            let c = cloud.colors[i]
            w.write("\(fmt(p.x)) \(fmt(p.y)) \(fmt(p.z)) 0 \(c.x) \(c.y) \(c.z)\n")
        }
        try w.close()
    }

    private static func appendUInt32(_ d: inout Data, _ v: UInt32) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
    }

    private static func appendFloat(_ d: inout Data, _ v: Float) {
        appendUInt32(&d, v.bitPattern)
    }
}

// MARK: - DXF (planta baixa para AutoCAD / Revit)

final class DXFWriter {
    private var body = ""

    func line(_ a: SIMD2<Float>, _ b: SIMD2<Float>, layer: String, color: Int) {
        body += "0\nLINE\n8\n\(layer)\n62\n\(color)\n10\n\(f(a.x))\n20\n\(f(a.y))\n30\n0.0\n11\n\(f(b.x))\n21\n\(f(b.y))\n31\n0.0\n"
    }

    func polyline(_ pts: [SIMD2<Float>], closed: Bool, layer: String, color: Int) {
        guard pts.count >= 2 else { return }
        for i in 0..<(pts.count - 1) { line(pts[i], pts[i + 1], layer: layer, color: color) }
        if closed, let first = pts.first, let last = pts.last { line(last, first, layer: layer, color: color) }
    }

    func text(_ s: String, at p: SIMD2<Float>, height: Float, angleDegrees: Float, layer: String, color: Int) {
        body += "0\nTEXT\n8\n\(layer)\n62\n\(color)\n10\n\(f(p.x))\n20\n\(f(p.y))\n30\n0.0\n40\n\(f(height))\n1\n\(s)\n50\n\(f(angleDegrees))\n"
    }

    /// Unidades em milímetros ($INSUNITS = 4).
    func write(to url: URL) throws {
        let doc = "0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1009\n9\n$INSUNITS\n70\n4\n0\nENDSEC\n"
            + "0\nSECTION\n2\nENTITIES\n" + body + "0\nENDSEC\n0\nEOF\n"
        try doc.write(to: url, atomically: true, encoding: .utf8)
    }

    private func f(_ v: Float) -> String { String(format: "%.3f", v) }
}
