import SwiftUI
import ARKit
import RealityKit
import Combine
import UIKit

/// Trena LiDAR: marca pontos no mundo real, mede segmentos, perímetro, desnível e área.
final class MeasureController: NSObject, ObservableObject {
    let arView: ARView
    @Published var points: [SIMD3<Float>] = []
    @Published var aim: SIMD3<Float>?
    @Published var closed = false

    private let root = AnchorEntity(world: .zero)
    private var markers: [Entity] = []
    private var updateSubscription: Cancellable?
    private var frameCounter = 0

    override init() {
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        super.init()
        arView.scene.addAnchor(root)
        updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            self?.tick()
        }
    }

    func start() {
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        config.planeDetection = [.horizontal, .vertical]
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func pause() {
        arView.session.pause()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func tick() {
        frameCounter += 1
        guard frameCounter % 3 == 0 else { return }
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        if let hit = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first {
            aim = Geometry.xyz(hit.worldTransform.columns.3)
        } else {
            aim = nil
        }
    }

    func addPoint() {
        guard let p = aim else { return }
        if let last = points.last { addLine(from: last, to: p) }
        points.append(p)
        addSphere(at: p)
    }

    func undo() {
        if closed {
            closed = false
        } else if !points.isEmpty {
            points.removeLast()
        }
        rebuild()
    }

    func clear() {
        points.removeAll()
        closed = false
        rebuild()
    }

    func toggleClose() {
        guard points.count >= 3 else { return }
        closed.toggle()
        rebuild()
    }

    private func rebuild() {
        markers.forEach { $0.removeFromParent() }
        markers.removeAll()
        for (i, p) in points.enumerated() {
            if i > 0 { addLine(from: points[i - 1], to: p) }
            addSphere(at: p)
        }
        if closed, let first = points.first, let last = points.last {
            addLine(from: last, to: first)
        }
    }

    private var goldMaterial: SimpleMaterial {
        SimpleMaterial(color: UIColor(red: 0.79, green: 0.64, blue: 0.29, alpha: 1), isMetallic: true)
    }

    private func addSphere(at p: SIMD3<Float>) {
        let sphere = ModelEntity(mesh: .generateSphere(radius: 0.007), materials: [goldMaterial])
        sphere.position = p
        root.addChild(sphere)
        markers.append(sphere)
    }

    private func addLine(from a: SIMD3<Float>, to b: SIMD3<Float>) {
        let length = simd_distance(a, b)
        guard length > 0.0001 else { return }
        let line = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.002, 0.002, length)), materials: [goldMaterial])
        let mid = (a + b) / 2
        let dir = simd_normalize(b - a)
        let up: SIMD3<Float> = abs(dir.y) > 0.98 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
        line.look(at: b, from: mid, upVector: up, relativeTo: nil)
        root.addChild(line)
        markers.append(line)
    }

    // MARK: Cálculos

    var segments: [Float] {
        guard points.count >= 2 else { return [] }
        var out = (1..<points.count).map { simd_distance(points[$0 - 1], points[$0]) }
        if closed, let f = points.first, let l = points.last { out.append(simd_distance(l, f)) }
        return out
    }

    var total: Float { segments.reduce(0, +) }

    /// Área da projeção horizontal (planta).
    var area: Float? {
        guard closed, points.count >= 3 else { return nil }
        let pts = points.map { SIMD2<Float>($0.x, $0.z) }
        return RoomPlanDrawing.area(pts)
    }

    var liveDistance: Float? {
        guard let last = points.last, let aim else { return nil }
        return simd_distance(last, aim)
    }

    var lastHeightDelta: Float? {
        guard points.count >= 2 else { return nil }
        return points[points.count - 1].y - points[points.count - 2].y
    }
}

@MainActor
final class MeasureModel: ObservableObject {
    enum Phase { case measuring, saving, done(ScanRecord), failed(String) }
    @Published var phase: Phase = .measuring
    @Published var askName = false
    @Published var name = ""
    let controller = MeasureController()

    func save() {
        let pts = controller.points
        let segs = controller.segments
        let closed = controller.closed
        let area = controller.area
        let total = controller.total
        guard pts.count >= 2 else { return }
        phase = .saving
        let base = ScanStore.safeName(name, fallback: "medicao")
        do {
            let folder = try ScanStore.newFolder(name: base)

            var csv = "ponto;x_m;y_m;z_m\n"
            for (i, p) in pts.enumerated() {
                csv += "\(i + 1);\(String(format: "%.4f", p.x));\(String(format: "%.4f", p.y));\(String(format: "%.4f", p.z))\n"
            }
            csv += "\nsegmento;comprimento_m\n"
            for (i, s) in segs.enumerated() { csv += "\(i + 1);\(String(format: "%.4f", s))\n" }
            csv += "\ntotal_m;\(String(format: "%.4f", total))\n"
            if let area { csv += "area_m2;\(String(format: "%.4f", area))\n" }
            let csvURL = folder.appendingPathComponent("\(base)_medidas.csv")
            try csv.write(to: csvURL, atomically: true, encoding: .utf8)

            let dxf = DXFWriter()
            let plan = pts.map { SIMD2<Float>($0.x, -$0.z) * 1000 }
            dxf.polyline(plan, closed: closed, layer: "MEDICAO", color: 2)
            for i in 1..<plan.count {
                let mid = (plan[i - 1] + plan[i]) / 2
                dxf.text(Exporter.formatLength(segs[i - 1]), at: mid + SIMD2(0, 50), height: 80, angleDegrees: 0, layer: "COTAS", color: 2)
            }
            let dxfURL = folder.appendingPathComponent("\(base)_planta.dxf")
            try dxf.write(to: dxfURL)

            var summary = "\(pts.count) pontos · total \(Exporter.formatLength(total))"
            if let area { summary += " · área \(Exporter.formatArea(area))" }
            let record = ScanStore.finalize(folder: folder, name: base, kind: .measure, files: [csvURL, dxfURL], summary: summary)
            controller.pause()
            phase = .done(record)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

struct MeasureFlow: View {
    @StateObject private var model = MeasureModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch model.phase {
            case .measuring:
                MeasureScreen(model: model, controller: model.controller, onClose: { dismiss() })
            case .saving:
                WorkingView(title: "Salvando medições", progress: nil)
            case .done(let record):
                ScanResultView(record: record, onClose: { dismiss() })
            case .failed(let message):
                ErrorView(message: message, onBack: { model.phase = .measuring }, onClose: { dismiss() })
            }
        }
        .onAppear { model.controller.start() }
        .onDisappear { model.controller.pause() }
    }
}

private struct MeasureScreen: View {
    @ObservedObject var model: MeasureModel
    @ObservedObject var controller: MeasureController
    let onClose: () -> Void

    var body: some View {
        ZStack {
            ARViewContainerMeasure(arView: controller.arView).ignoresSafeArea()

            Reticle(active: controller.aim != nil)

            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    CloseButton(action: onClose)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        if let live = controller.liveDistance {
                            HUDPill(text: Exporter.formatLength(live), icon: "arrow.left.and.right")
                        }
                        if controller.points.count >= 2 {
                            HUDPill(text: "Total \(Exporter.formatLength(controller.total))", icon: "sum")
                        }
                        if let dh = controller.lastHeightDelta, abs(dh) > 0.01 {
                            HUDPill(text: "Desnível \(Exporter.formatLength(abs(dh)))", icon: "arrow.up.and.down")
                        }
                        if let area = controller.area {
                            HUDPill(text: "Área \(Exporter.formatArea(area))", icon: "square.dashed")
                        }
                    }
                }
                .padding()

                Spacer()

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Button("Desfazer") { controller.undo() }
                            .buttonStyle(GoldButtonStyle(filled: false))
                            .disabled(controller.points.isEmpty)
                        Button(controller.closed ? "Abrir" : "Fechar área") { controller.toggleClose() }
                            .buttonStyle(GoldButtonStyle(filled: false))
                            .disabled(controller.points.count < 3)
                        Button("Salvar") { model.askName = true }
                            .buttonStyle(GoldButtonStyle(filled: false))
                            .disabled(controller.points.count < 2)
                    }
                    Button { controller.addPoint() } label: { Label("Marcar ponto", systemImage: "plus.viewfinder") }
                        .buttonStyle(GoldButtonStyle())
                        .disabled(controller.aim == nil)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .alert("Salvar medições", isPresented: $model.askName) {
            TextField("Nome", text: $model.name)
            Button("Salvar") { model.save() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Gera planilha CSV e planta DXF com as cotas.")
        }
    }
}

private struct ARViewContainerMeasure: UIViewRepresentable {
    let arView: ARView
    func makeUIView(context: Context) -> ARView { arView }
    func updateUIView(_ uiView: ARView, context: Context) {}
}

private struct Reticle: View {
    let active: Bool
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(active ? Theme.goldLight : Theme.muted, lineWidth: 1.5)
                .frame(width: 34, height: 34)
            Circle()
                .fill(active ? Theme.gold : Theme.muted)
                .frame(width: 5, height: 5)
        }
        .shadow(color: .black.opacity(0.6), radius: 3)
        .allowsHitTesting(false)
    }
}
