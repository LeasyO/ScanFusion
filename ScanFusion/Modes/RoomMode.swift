import SwiftUI
import RoomPlan
import simd
import UIKit

/// Modo Ambiente: RoomPlan reconhece paredes, portas, janelas e móveis e gera planta.
final class RoomCaptureController: NSObject, RoomCaptureViewDelegate {
    let captureView: RoomCaptureView
    var onFinish: ((CapturedRoom?, Error?) -> Void)?

    override init() {
        captureView = RoomCaptureView(frame: .zero)
        super.init()
        captureView.delegate = self
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func encode(with coder: NSCoder) {}

    func start() {
        let config = RoomCaptureSession.Configuration()
        captureView.captureSession.run(configuration: config)
    }

    func stop() {
        captureView.captureSession.stop()
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        onFinish?(processedResult, error)
    }
}

private struct RoomCaptureContainer: UIViewRepresentable {
    let controller: RoomCaptureController
    func makeUIView(context: Context) -> RoomCaptureView { controller.captureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

@MainActor
final class RoomModel: ObservableObject {
    enum Phase { case intro, scanning, finishing, exporting, done(ScanRecord), failed(String) }

    @Published var phase: Phase = .intro
    @Published var name = ""
    private(set) var controller: RoomCaptureController?

    static var isSupported: Bool { RoomCaptureSession.isSupported }

    func start() {
        guard Self.isSupported else {
            phase = .failed("Este aparelho não suporta RoomPlan (precisa de LiDAR).")
            return
        }
        let c = RoomCaptureController()
        c.onFinish = { [weak self] room, error in
            Task { @MainActor in self?.finished(room: room, error: error) }
        }
        controller = c
        phase = .scanning
        UIApplication.shared.isIdleTimerDisabled = true
        c.start()
    }

    func stop() {
        phase = .finishing
        controller?.stop()
    }

    func cancel() {
        controller?.stop()
        controller = nil
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .intro
    }

    func teardown() {
        controller?.stop()
        controller = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func finished(room: CapturedRoom?, error: Error?) {
        guard case .finishing = phase else { return }
        guard let room else {
            phase = .failed(error?.localizedDescription ?? "O ambiente não pôde ser processado.")
            return
        }
        phase = .exporting
        let base = ScanStore.safeName(name, fallback: "ambiente")
        let options = ExportOptions.current
        Task {
            do {
                let record = try await Self.export(room: room, base: base, options: options)
                phase = .done(record)
            } catch {
                phase = .failed("Falha ao salvar: \(error.localizedDescription)")
            }
            controller = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private static func export(room: CapturedRoom, base: String, options: ExportOptions) async throws -> ScanRecord {
        let folder = try ScanStore.newFolder(name: base)
        let usdz = folder.appendingPathComponent("\(base).usdz")
        try room.export(to: usdz, exportOptions: .parametric)

        var files: [URL] = []

        let json = folder.appendingPathComponent("\(base)_dados.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode(room).write(to: json)

        let plan = RoomPlanDrawing(room: room)
        let dxf = folder.appendingPathComponent("\(base)_planta.dxf")
        try plan.writeDXF(to: dxf)
        files.append(dxf)

        let meshResult = try await Task.detached(priority: .userInitiated) {
            try Exporter.exportUSDZ(usdz, baseName: base, folder: folder, options: options)
        }.value
        files.append(contentsOf: meshResult.files)
        files.append(usdz)
        files.append(json)

        var summary = "\(room.walls.count) paredes · \(room.doors.count) portas · \(room.windows.count) janelas"
        summary += " · paredes somam \(Exporter.formatLength(plan.totalWallLength))"
        if plan.floorArea > 0.5 { summary += " · piso ≈ \(Exporter.formatArea(plan.floorArea))" }

        return await MainActor.run {
            ScanStore.finalize(folder: folder, name: base, kind: .room, files: files, summary: summary)
        }
    }
}

/// Converte o resultado do RoomPlan em planta baixa (DXF em milímetros).
struct RoomPlanDrawing {
    private var walls: [(SIMD2<Float>, SIMD2<Float>)] = []
    private var doors: [(SIMD2<Float>, SIMD2<Float>)] = []
    private var windows: [(SIMD2<Float>, SIMD2<Float>)] = []
    private var openings: [(SIMD2<Float>, SIMD2<Float>)] = []
    private var objects: [[SIMD2<Float>]] = []
    private var floors: [[SIMD2<Float>]] = []
    private(set) var totalWallLength: Float = 0
    private(set) var floorArea: Float = 0

    init(room: CapturedRoom) {
        func plan(_ p: SIMD3<Float>) -> SIMD2<Float> { SIMD2(p.x, -p.z) }

        func segment(_ s: CapturedRoom.Surface) -> (SIMD2<Float>, SIMD2<Float>) {
            let t = s.transform
            let center = Geometry.xyz(t.columns.3)
            let dir = simd_normalize(Geometry.xyz(t.columns.0))
            let half = s.dimensions.x / 2
            return (plan(center - dir * half), plan(center + dir * half))
        }

        for w in room.walls {
            let seg = segment(w)
            walls.append(seg)
            totalWallLength += simd_distance(seg.0, seg.1)
        }
        doors = room.doors.map(segment)
        windows = room.windows.map(segment)
        openings = room.openings.map(segment)

        for o in room.objects {
            let t = o.transform
            let c = Geometry.xyz(t.columns.3)
            let ax = simd_normalize(Geometry.xyz(t.columns.0)) * (o.dimensions.x / 2)
            let az = simd_normalize(Geometry.xyz(t.columns.2)) * (o.dimensions.z / 2)
            objects.append([plan(c - ax - az), plan(c + ax - az), plan(c + ax + az), plan(c - ax + az)])
        }

        for f in room.floors {
            let pts = f.polygonCorners.map { plan(Geometry.apply(f.transform, $0)) }
            if pts.count >= 3 {
                floors.append(pts)
                floorArea += Self.area(pts)
            }
        }
    }

    static func area(_ pts: [SIMD2<Float>]) -> Float {
        var sum: Float = 0
        for i in 0..<pts.count {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    func writeDXF(to url: URL) throws {
        let dxf = DXFWriter()
        let mm: Float = 1000
        func s(_ p: SIMD2<Float>) -> SIMD2<Float> { p * mm }

        for poly in floors { dxf.polyline(poly.map(s), closed: true, layer: "PISO", color: 8) }
        for (a, b) in walls {
            dxf.line(s(a), s(b), layer: "PAREDES", color: 7)
            let mid = (s(a) + s(b)) / 2
            let d = b - a
            var angle = atan2(d.y, d.x) * 180 / .pi
            if angle > 90 { angle -= 180 }
            if angle < -90 { angle += 180 }
            let label = Exporter.formatLength(simd_distance(a, b))
            dxf.text(label, at: mid + SIMD2(0, 60), height: 100, angleDegrees: angle, layer: "COTAS", color: 2)
        }
        for (a, b) in doors { dxf.line(s(a), s(b), layer: "PORTAS", color: 1) }
        for (a, b) in windows { dxf.line(s(a), s(b), layer: "JANELAS", color: 4) }
        for (a, b) in openings { dxf.line(s(a), s(b), layer: "ABERTURAS", color: 3) }
        for poly in objects { dxf.polyline(poly.map(s), closed: true, layer: "MOBILIARIO", color: 6) }
        try dxf.write(to: url)
    }
}

struct RoomFlow: View {
    @StateObject private var model = RoomModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch model.phase {
            case .intro:
                ModeIntro(
                    eyebrow: "Modo ambiente",
                    title: "Levantar um cômodo",
                    icon: "square.split.bottomrightquarter",
                    tips: [
                        "Acenda as luzes e abra portas que quiser registrar.",
                        "Aponte para paredes, cantos, piso e teto, andando devagar.",
                        "Gera planta DXF com cotas (AutoCAD/Revit), modelo 3D e dados."
                    ],
                    name: $model.name,
                    namePlaceholder: "Nome do ambiente",
                    supported: RoomModel.isSupported,
                    unsupportedText: "Precisa de iPhone com LiDAR.",
                    startTitle: "Começar levantamento",
                    onStart: { model.start() },
                    onClose: { dismiss() }
                )
            case .scanning, .finishing:
                if let controller = model.controller {
                    ZStack {
                        RoomCaptureContainer(controller: controller).ignoresSafeArea()
                        VStack {
                            HStack {
                                CloseButton { model.cancel() }
                                Spacer()
                            }
                            .padding()
                            Spacer()
                            if case .scanning = model.phase {
                                Button { model.stop() } label: { Label("Concluir levantamento", systemImage: "checkmark") }
                                    .buttonStyle(GoldButtonStyle())
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 24)
                            } else {
                                HUDPill(text: "Processando o ambiente", icon: "hourglass")
                                    .padding(.bottom, 32)
                            }
                        }
                    }
                } else {
                    WorkingView(title: "Preparando", progress: nil)
                }
            case .exporting:
                WorkingView(title: "Gerando planta e modelo", progress: nil)
            case .done(let record):
                ScanResultView(record: record, onClose: { dismiss() })
            case .failed(let message):
                ErrorView(message: message, onBack: { model.phase = .intro }, onClose: { dismiss() })
            }
        }
        .onDisappear { model.teardown() }
    }
}
