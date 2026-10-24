import SwiftUI
import RealityKit
import UIKit

/// Modo Objeto: Object Capture da Apple (câmera + LiDAR), reconstrução no próprio iPhone.
@MainActor
final class ObjectCaptureModel: ObservableObject {
    enum Phase {
        case intro, capturing, reconstructing(Double), exporting, done(ScanRecord), failed(String)
    }

    @Published var phase: Phase = .intro
    @Published var session: ObjectCaptureSession?
    @Published var captureState: ObjectCaptureSession.CaptureState = .initializing
    @Published var passCompleted = false
    @Published var name = ""

    private var folder: URL?
    private var observers: [Task<Void, Never>] = []
    private var userCancelled = false

    static var isSupported: Bool { ObjectCaptureSession.isSupported }

    func start() {
        guard Self.isSupported else {
            phase = .failed("Este aparelho não suporta Object Capture (precisa de LiDAR e iOS 17+).")
            return
        }
        do {
            let base = ScanStore.safeName(name, fallback: "objeto")
            let folder = try ScanStore.newFolder(name: base)
            let images = folder.appendingPathComponent("Fotos", isDirectory: true)
            let checkpoints = folder.appendingPathComponent("Checkpoints", isDirectory: true)
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: checkpoints, withIntermediateDirectories: true)
            self.folder = folder

            var config = ObjectCaptureSession.Configuration()
            config.checkpointDirectory = checkpoints
            config.isOverCaptureEnabled = false

            let s = ObjectCaptureSession()
            session = s
            passCompleted = false
            userCancelled = false
            captureState = .initializing
            phase = .capturing
            UIApplication.shared.isIdleTimerDisabled = true
            observe(s)
            s.start(imagesDirectory: images, configuration: config)
        } catch {
            phase = .failed("Não foi possível preparar a pasta: \(error.localizedDescription)")
        }
    }

    func detect() { _ = session?.startDetecting() }
    func resetDetection() { session?.resetDetection() }
    func startCapturing() { session?.startCapturing() }
    func newPass() { session?.beginNewScanPass() }
    func newPassAfterFlip() { session?.beginNewScanPassAfterFlip() }
    func finish() { session?.finish() }

    func cancel() {
        userCancelled = true
        if let session {
            session.cancel()
        } else {
            teardown()
        }
    }

    func teardown() {
        observers.forEach { $0.cancel() }
        observers = []
        session = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func observe(_ s: ObjectCaptureSession) {
        observers.forEach { $0.cancel() }
        observers = [
            Task { [weak self] in
                for await state in s.stateUpdates {
                    self?.handle(state)
                }
            },
            Task { [weak self] in
                for await completed in s.userCompletedScanPassUpdates {
                    self?.passCompleted = completed
                }
            }
        ]
    }

    private func handle(_ state: ObjectCaptureSession.CaptureState) {
        captureState = state
        switch state {
        case .completed:
            session = nil
            Task { await reconstruct() }
        case .failed(let error):
            session = nil
            UIApplication.shared.isIdleTimerDisabled = false
            if userCancelled {
                phase = .intro
            } else {
                phase = .failed(error.localizedDescription)
            }
        default:
            break
        }
    }

    private func reconstruct() async {
        guard let folder else { return }
        phase = .reconstructing(0)
        UIApplication.shared.isIdleTimerDisabled = true

        let base = ScanStore.safeName(name, fallback: "objeto")
        let images = folder.appendingPathComponent("Fotos", isDirectory: true)
        let checkpoints = folder.appendingPathComponent("Checkpoints", isDirectory: true)
        let exports = folder.appendingPathComponent("Exportados", isDirectory: true)
        let usdz = exports.appendingPathComponent("\(base).usdz")

        do {
            try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
            var config = PhotogrammetrySession.Configuration()
            config.checkpointDirectory = checkpoints
            let photogrammetry = try PhotogrammetrySession(input: images, configuration: config)
            try photogrammetry.process(requests: [.modelFile(url: usdz)])

            loop: for try await output in photogrammetry.outputs {
                switch output {
                case .requestProgress(_, let fraction):
                    phase = .reconstructing(fraction)
                case .requestError(_, let error):
                    throw error
                case .processingCancelled:
                    phase = .intro
                    UIApplication.shared.isIdleTimerDisabled = false
                    return
                case .processingComplete:
                    break loop
                default:
                    break
                }
            }

            phase = .exporting
            let options = ExportOptions.current
            let result = try await Task.detached(priority: .userInitiated) {
                try Exporter.exportUSDZ(usdz, baseName: base, folder: exports, options: options)
            }.value

            try? FileManager.default.removeItem(at: checkpoints)
            let photoCount = (try? FileManager.default.contentsOfDirectory(atPath: images.path).count) ?? 0
            var summary = "\(photoCount) fotos"
            if result.triangles > 0 { summary += " · \(Exporter.formatCount(result.triangles)) triângulos" }
            summary += " · \(options.unit.rawValue)"

            let record = ScanStore.finalize(
                folder: folder, name: base, kind: .object,
                files: result.files + [usdz], summary: summary
            )
            phase = .done(record)
        } catch {
            phase = .failed("Falha ao gerar o modelo: \(error.localizedDescription)")
        }
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

struct ObjectCaptureFlow: View {
    @StateObject private var model = ObjectCaptureModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch model.phase {
            case .intro:
                ModeIntro(
                    eyebrow: "Modo objeto",
                    title: "Capturar uma peça",
                    icon: "cube.transparent",
                    tips: [
                        "Objeto fosco e com textura, sobre superfície lisa que contraste com ele.",
                        "Luz difusa: sombra ou dia nublado. Evite reflexos fortes.",
                        "Dê uma volta completa, depois outra mais alta e, se der, vire o objeto."
                    ],
                    name: $model.name,
                    namePlaceholder: "Nome da peça",
                    supported: ObjectCaptureModel.isSupported,
                    unsupportedText: "Precisa de iPhone com LiDAR e iOS 17 ou mais recente.",
                    startTitle: "Começar captura",
                    onStart: { model.start() },
                    onClose: { dismiss() }
                )
            case .capturing:
                if let session = model.session {
                    ObjectCaptureScreen(model: model, session: session)
                } else {
                    WorkingView(title: "Preparando câmera", progress: nil)
                }
            case .reconstructing(let p):
                WorkingView(title: "Gerando o modelo 3D", progress: p)
            case .exporting:
                WorkingView(title: "Convertendo para o Fusion", progress: nil)
            case .done(let record):
                ScanResultView(record: record, onClose: { dismiss() })
            case .failed(let message):
                ErrorView(message: message, onBack: { model.phase = .intro }, onClose: { dismiss() })
            }
        }
        .onDisappear { model.teardown() }
    }
}

private struct ObjectCaptureScreen: View {
    @ObservedObject var model: ObjectCaptureModel
    let session: ObjectCaptureSession

    var body: some View {
        ZStack {
            ObjectCaptureView(session: session)
                .ignoresSafeArea()

            VStack {
                HStack {
                    CloseButton { model.cancel() }
                    Spacer()
                    if let hint { HUDPill(text: hint) }
                }
                .padding()
                Spacer()
                controls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
    }

    private var hint: String? {
        switch model.captureState {
        case .initializing: return "Iniciando sensores"
        case .ready: return "Mire no objeto"
        case .detecting: return "Ajuste a caixa"
        case .capturing: return model.passCompleted ? "Volta completa" : "Ande devagar em volta"
        case .finishing: return "Salvando fotos"
        default: return nil
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch model.captureState {
        case .ready:
            Button { model.detect() } label: { Label("Detectar objeto", systemImage: "scope") }
                .buttonStyle(GoldButtonStyle())
        case .detecting:
            HStack(spacing: 10) {
                Button("Refazer") { model.resetDetection() }
                    .buttonStyle(GoldButtonStyle(filled: false))
                Button { model.startCapturing() } label: { Label("Capturar", systemImage: "camera.aperture") }
                    .buttonStyle(GoldButtonStyle())
            }
        case .capturing:
            if model.passCompleted {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Button("Nova volta") { model.newPass() }
                            .buttonStyle(GoldButtonStyle(filled: false))
                        Button("Virei o objeto") { model.newPassAfterFlip() }
                            .buttonStyle(GoldButtonStyle(filled: false))
                    }
                    Button { model.finish() } label: { Label("Finalizar e gerar", systemImage: "checkmark") }
                        .buttonStyle(GoldButtonStyle())
                }
            } else {
                Button("Finalizar agora") { model.finish() }
                    .buttonStyle(GoldButtonStyle(filled: false))
            }
        case .initializing, .finishing:
            ProgressView().tint(Theme.gold)
        default:
            EmptyView()
        }
    }
}
