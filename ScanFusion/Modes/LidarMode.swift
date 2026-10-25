import SwiftUI
import ARKit
import RealityKit
import UIKit

/// Modo LiDAR livre: malha em tempo real (com tipos de superfície) + nuvem de pontos colorida.
final class LidarController: NSObject, ObservableObject, ARSessionDelegate {
    let arView: ARView

    @Published var triangles = 0
    @Published var points = 0
    @Published var recording = false
    @Published var meshVisible = true
    @Published var tracking = "Iniciando"

    private let queue = DispatchQueue(label: "scanfusion.lidar", qos: .userInitiated)
    // Acessados só na fila `queue`:
    private var cloud = PointCloud()
    // Cubinho -> índice do ponto; cada novo acerto entra na média (reduz o ruído do sensor).
    private var voxels: [SIMD3<Int32>: Int] = [:]
    private var hits: [Float] = []
    private var frameCounter = 0
    private var recordingFlag = false
    private var options = LidarOptions.current
    private let maxPoints = 2_500_000

    static var isSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    override init() {
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        super.init()
        arView.session.delegateQueue = queue
        arView.session.delegate = self
        arView.debugOptions.insert(.showSceneUnderstanding)
        arView.renderOptions.insert(.disableMotionBlur)
    }

    func start() {
        let opts = LidarOptions.current
        queue.async {
            self.options = opts
            self.cloud = PointCloud()
            self.voxels.removeAll()
            self.hits.removeAll()
            self.recordingFlag = false
        }
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else {
            config.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        }
        config.environmentTexturing = .none
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        recording = false
        points = 0
        triangles = 0
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func pause() {
        setRecording(false)
        arView.session.pause()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func setRecording(_ on: Bool) {
        recording = on
        queue.async { self.recordingFlag = on }
    }

    func setMeshVisible(_ on: Bool) {
        meshVisible = on
        if on {
            arView.debugOptions.insert(.showSceneUnderstanding)
        } else {
            arView.debugOptions.remove(.showSceneUnderstanding)
        }
    }

    func meshAnchors() -> [ARMeshAnchor] {
        arView.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
    }

    func cloudSnapshot() -> PointCloud {
        queue.sync { cloud }
    }

    // MARK: ARSessionDelegate (executa na fila `queue`)

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCounter += 1
        if frameCounter % 15 == 0 {
            var tris = 0
            for anchor in frame.anchors {
                if let mesh = anchor as? ARMeshAnchor { tris += mesh.geometry.faces.count }
            }
            let pts = cloud.count
            let state = Self.describe(frame.camera.trackingState)
            DispatchQueue.main.async {
                self.triangles = tris
                self.points = pts
                self.tracking = state
            }
        }
        if recordingFlag && frameCounter % 3 == 0 {
            accumulate(frame)
        }
    }

    private static func describe(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal: return "Rastreamento bom"
        case .notAvailable: return "Sem rastreamento"
        case .limited(let reason):
            switch reason {
            case .excessiveMotion: return "Mais devagar"
            case .insufficientFeatures: return "Pouca textura"
            case .initializing: return "Iniciando"
            case .relocalizing: return "Reposicionando"
            @unknown default: return "Rastreamento limitado"
            }
        }
    }

    private func accumulate(_ frame: ARFrame) {
        // A versão suavizada combina vários quadros: menos ruído nas bordas e superfícies.
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }
        let depth = depthData.depthMap
        let confidence = depthData.confidenceMap
        let image = frame.capturedImage

        CVPixelBufferLockBaseAddress(depth, .readOnly)
        CVPixelBufferLockBaseAddress(image, .readOnly)
        if let confidence { CVPixelBufferLockBaseAddress(confidence, .readOnly) }
        defer {
            CVPixelBufferUnlockBaseAddress(depth, .readOnly)
            CVPixelBufferUnlockBaseAddress(image, .readOnly)
            if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
        }

        guard let dBase = CVPixelBufferGetBaseAddress(depth),
              CVPixelBufferGetPlaneCount(image) >= 2,
              let yBase = CVPixelBufferGetBaseAddressOfPlane(image, 0),
              let uvBase = CVPixelBufferGetBaseAddressOfPlane(image, 1) else { return }

        let dw = CVPixelBufferGetWidth(depth)
        let dh = CVPixelBufferGetHeight(depth)
        let dRow = CVPixelBufferGetBytesPerRow(depth)
        let cBase = confidence.flatMap { CVPixelBufferGetBaseAddress($0) }
        let cRow = confidence.map { CVPixelBufferGetBytesPerRow($0) } ?? 0
        let iw = CVPixelBufferGetWidthOfPlane(image, 0)
        let ih = CVPixelBufferGetHeightOfPlane(image, 0)
        let yRow = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
        let uvRow = CVPixelBufferGetBytesPerRowOfPlane(image, 1)

        let k = frame.camera.intrinsics
        let sx = Float(dw) / Float(iw)
        let sy = Float(dh) / Float(ih)
        let fx = k[0][0] * sx
        let fy = k[1][1] * sy
        let cx = k[2][0] * sx
        let cy = k[2][1] * sy
        let t = frame.camera.transform
        let voxel = options.voxelSize
        let maxDepth = options.maxDepth
        let step = options.pixelStep

        func clamp(_ v: Float) -> UInt8 { UInt8(max(0, min(255, v))) }

        var v = 0
        while v < dh {
            var u = 0
            while u < dw {
                defer { u += step }
                if let cBase {
                    let c = cBase.load(fromByteOffset: v * cRow + u, as: UInt8.self)
                    if c < 2 { continue }
                }
                let d = dBase.load(fromByteOffset: v * dRow + u * 4, as: Float32.self)
                if !d.isFinite || d < 0.15 || d > maxDepth { continue }

                let xc = (Float(u) - cx) * d / fx
                let yc = (Float(v) - cy) * d / fy
                let w = t * SIMD4<Float>(xc, -yc, -d, 1)
                let p = SIMD3<Float>(w.x, w.y, w.z)
                let key = SIMD3<Int32>(
                    Int32((p.x / voxel).rounded(.down)),
                    Int32((p.y / voxel).rounded(.down)),
                    Int32((p.z / voxel).rounded(.down))
                )
                if let i = voxels[key] {
                    let n = min(hits[i] + 1, 64)
                    hits[i] = n
                    cloud.points[i] += (p - cloud.points[i]) / n
                    continue
                }
                voxels[key] = cloud.count
                hits.append(1)

                let iu = min(iw - 1, Int(Float(u) / sx))
                let iv = min(ih - 1, Int(Float(v) / sy))
                let luma = Float(yBase.load(fromByteOffset: iv * yRow + iu, as: UInt8.self))
                let uvOffset = (iv / 2) * uvRow + (iu / 2) * 2
                let cb = Float(uvBase.load(fromByteOffset: uvOffset, as: UInt8.self)) - 128
                let cr = Float(uvBase.load(fromByteOffset: uvOffset + 1, as: UInt8.self)) - 128
                let r = luma + 1.402 * cr
                let g = luma - 0.344136 * cb - 0.714136 * cr
                let b = luma + 1.772 * cb

                cloud.points.append(p)
                cloud.colors.append(SIMD3(clamp(r), clamp(g), clamp(b)))
                if cloud.count >= maxPoints {
                    recordingFlag = false
                    DispatchQueue.main.async { self.recording = false }
                    return
                }
            }
            v += step
        }
    }
}

private struct ARViewContainer: UIViewRepresentable {
    let arView: ARView
    func makeUIView(context: Context) -> ARView { arView }
    func updateUIView(_ uiView: ARView, context: Context) {}
}

@MainActor
final class LidarModel: ObservableObject {
    enum Phase { case intro, scanning, exporting, done(ScanRecord), failed(String) }
    @Published var phase: Phase = .intro
    @Published var name = ""
    let controller = LidarController()

    func start() {
        guard LidarController.isSupported else {
            phase = .failed("Este aparelho não tem LiDAR.")
            return
        }
        controller.start()
        phase = .scanning
    }

    func save() {
        let anchors = controller.meshAnchors()
        let cloud = controller.cloudSnapshot()
        controller.pause()
        phase = .exporting
        let base = ScanStore.safeName(name, fallback: "lidar")
        let options = ExportOptions.current

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { () throws -> ([URL], String, URL) in
                    let folder = try ScanStore.newFolder(name: base)
                    var files: [URL] = []
                    var parts: [String] = []
                    let mesh = MeshData.from(anchors: anchors)
                    if !mesh.isEmpty {
                        files += try Exporter.exportMesh(mesh, baseName: base, folder: folder, options: options)
                        parts.append("\(Exporter.formatCount(mesh.triangleCount)) triângulos")
                        if options.splitClasses {
                            let byClass = MeshData.split(anchors: anchors)
                            let classFolder = folder.appendingPathComponent("PorTipo", isDirectory: true)
                            try FileManager.default.createDirectory(at: classFolder, withIntermediateDirectories: true)
                            var classOptions = options
                            classOptions.writeOBJ = false
                            classOptions.writePLY = false
                            classOptions.writeSTL = true
                            classOptions.fusionLite = false
                            for cls in MeshClass.allCases {
                                guard let part = byClass[cls], !part.isEmpty else { continue }
                                files += try Exporter.exportMesh(
                                    part, baseName: "\(base)_\(cls.fileSuffix)", folder: classFolder, options: classOptions
                                )
                            }
                        }
                    }
                    if cloud.count > 0 {
                        files += try Exporter.exportCloud(cloud, baseName: base, folder: folder, options: options)
                        parts.append("\(Exporter.formatCount(cloud.count)) pontos")
                    }
                    if files.isEmpty { throw ExportError.nothingToSave }
                    parts.append(options.unit.rawValue)
                    return (files, parts.joined(separator: " · "), folder)
                }.value
                let record = ScanStore.finalize(
                    folder: result.2, name: base, kind: .lidar, files: result.0, summary: result.1
                )
                phase = .done(record)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        controller.pause()
        phase = .intro
    }

    func teardown() {
        controller.pause()
    }
}

struct LidarFlow: View {
    @StateObject private var model = LidarModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch model.phase {
            case .intro:
                ModeIntro(
                    eyebrow: "Modo LiDAR",
                    title: "Malha e nuvem de pontos",
                    icon: "circle.grid.cross",
                    tips: [
                        "Ideal para coisas grandes: moto, fachada, terreno, cômodo inteiro.",
                        "A malha aparece sobre a câmera enquanto você anda.",
                        "Toque em Gravar nuvem para registrar pontos coloridos (PLY e PTS para ReCap/Revit)."
                    ],
                    name: $model.name,
                    namePlaceholder: "Nome do scan",
                    supported: LidarController.isSupported,
                    unsupportedText: "Precisa de iPhone com LiDAR.",
                    startTitle: "Abrir scanner",
                    onStart: { model.start() },
                    onClose: { dismiss() }
                )
            case .scanning:
                LidarScreen(model: model, controller: model.controller)
            case .exporting:
                WorkingView(title: "Salvando malha e pontos", progress: nil)
            case .done(let record):
                ScanResultView(record: record, onClose: { dismiss() })
            case .failed(let message):
                ErrorView(message: message, onBack: { model.phase = .intro }, onClose: { dismiss() })
            }
        }
        .onDisappear { model.teardown() }
    }
}

private struct LidarScreen: View {
    @ObservedObject var model: LidarModel
    @ObservedObject var controller: LidarController
    @AppStorage(SettingsKey.lidarPiece) private var piece = false

    var body: some View {
        ZStack {
            ARViewContainer(arView: controller.arView).ignoresSafeArea()

            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    CloseButton { model.cancel() }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        HUDPill(text: controller.tracking, icon: "location.viewfinder")
                        HUDPill(text: "\(Exporter.formatCount(controller.triangles)) triângulos", icon: "triangle")
                        if controller.points > 0 || controller.recording {
                            HUDPill(text: "\(Exporter.formatCount(controller.points)) pontos", icon: "circle.dotted")
                        }
                    }
                }
                .padding()

                Spacer()

                VStack(spacing: 10) {
                    if !controller.recording && controller.points == 0 {
                        Picker("Alvo", selection: $piece) {
                            Text("Ambiente").tag(false)
                            Text("Peça · alta precisão").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: piece) { controller.start() }
                        if piece {
                            HUDPill(text: "Fique entre 30 cm e 1 m e passe devagar", icon: "ruler")
                        }
                    }
                    HStack(spacing: 10) {
                        Button {
                            controller.setMeshVisible(!controller.meshVisible)
                        } label: {
                            Label(controller.meshVisible ? "Ocultar malha" : "Mostrar malha",
                                  systemImage: controller.meshVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(GoldButtonStyle(filled: false))

                        Button {
                            controller.setRecording(!controller.recording)
                        } label: {
                            Label(controller.recording ? "Pausar nuvem" : "Gravar nuvem",
                                  systemImage: controller.recording ? "pause.circle" : "record.circle")
                        }
                        .buttonStyle(GoldButtonStyle(filled: false))
                    }
                    HStack(spacing: 10) {
                        Button("Recomeçar") { controller.start() }
                            .buttonStyle(GoldButtonStyle(filled: false))
                        Button { model.save() } label: { Label("Salvar", systemImage: "square.and.arrow.down") }
                            .buttonStyle(GoldButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}
