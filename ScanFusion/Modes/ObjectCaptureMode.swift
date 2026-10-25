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
    @Published var flipping = false
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

    // A Apple só aceita a volta após virar com a sessão pausada; chamar em .capturing derruba o app.
    func startFlip() {
        session?.pause()
        flipping = true
    }

    func finishFlip() {
        flipping = false
        guard let session else { return }
        if session.isPaused { session.beginNewScanPassAfterFlip() }
        if session.isPaused { session.resume() }
    }

    func cancelFlip() {
        flipping = false
        if session?.isPaused == true { session?.resume() }
    }

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
                        "Dê uma volta completa, depois outra mais alta e, se der, vire o objeto.",
                        "Com tripé, escolha Tripé antes de detectar: dá para circular por baixo sem virar a peça."
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
    @AppStorage(SettingsKey.objectTripod) private var onTripod = false

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
        case .detecting: return onTripod ? "Caixa só na peça, sem o tripé" : "Ajuste a caixa"
        case .capturing:
            if model.flipping { return "Vire o objeto e toque em Continuar" }
            if !model.passCompleted { return "Ande devagar em volta" }
            return onTripod ? "Nova volta: mais alto ou por baixo" : "Volta completa"
        case .finishing: return "Salvando fotos"
        default: return nil
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch model.captureState {
        case .ready:
            VStack(spacing: 10) {
                Picker("Apoio", selection: $onTripod) {
                    Text("Mesa").tag(false)
                    Text("Tripé").tag(true)
                }
                .pickerStyle(.segmented)
                Button { model.detect() } label: { Label("Detectar objeto", systemImage: "scope") }
                    .buttonStyle(GoldButtonStyle())
            }
        case .detecting:
            HStack(spacing: 10) {
                Button("Refazer") { model.resetDetection() }
                    .buttonStyle(GoldButtonStyle(filled: false))
                Button { model.startCapturing() } label: { Label("Capturar", systemImage: "camera.aperture") }
                    .buttonStyle(GoldButtonStyle())
            }
        case .capturing:
            if model.flipping {
                HStack(spacing: 10) {
                    Button("Voltar") { model.cancelFlip() }
                        .buttonStyle(GoldButtonStyle(filled: false))
                    Button { model.finishFlip() } label: { Label("Continuar", systemImage: "arrow.uturn.up") }
                        .buttonStyle(GoldButtonStyle())
                }
            } else if model.passCompleted {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Button("Nova volta") { model.newPass() }
                            .buttonStyle(GoldButtonStyle(filled: false))
                        if !onTripod {
                            Button("Virar o objeto") { model.startFlip() }
                                .buttonStyle(GoldButtonStyle(filled: false))
                        }
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
