import SwiftUI
import QuickLook

struct ModeIntro: View {
    let eyebrow: String
    let title: String
    let icon: String
    let tips: [String]
    @Binding var name: String
    let namePlaceholder: String
    let supported: Bool
    let unsupportedText: String
    let startTitle: String
    let onStart: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                CloseButton(action: onClose)
            }
            .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    IconTile(systemName: icon, size: 76)
                        .shadow(color: Theme.gold.opacity(0.25), radius: 24)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: eyebrow)
                        Text(title)
                            .font(.system(size: 34, weight: .bold))
                            .tracking(-0.5)
                            .foregroundStyle(Theme.ivory)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Text(String(format: "%02d", index + 1))
                                    .font(Theme.mono(12, weight: .semibold))
                                    .foregroundStyle(Theme.gold)
                                Text(tip)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.ivory.opacity(0.88))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 12)
                            if index < tips.count - 1 {
                                Rectangle().fill(Theme.hairline).frame(height: 0.5)
                            }
                        }
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("NOME")
                            .font(Theme.eyebrow(10))
                            .tracking(1.6)
                            .foregroundStyle(Theme.muted)
                        TextField("", text: $name, prompt: Text(namePlaceholder).foregroundColor(Theme.muted))
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.ivory)
                            .autocorrectionDisabled()
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Theme.rimGradient, lineWidth: 1)
                            )
                    }

                    if !supported {
                        Label(unsupportedText, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            Button(action: onStart) {
                Text(startTitle)
            }
            .buttonStyle(GoldButtonStyle())
            .disabled(!supported)
            .opacity(supported ? 1 : 0.4)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .studioBackground()
    }
}

struct WorkingView: View {
    let title: String
    let progress: Double?

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            if let progress {
                ZStack {
                    Circle()
                        .stroke(Theme.surfaceHigh, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: max(0.02, progress))
                        .stroke(Theme.goldGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Theme.gold.opacity(0.5), radius: 10)
                        .animation(.easeOut(duration: 0.4), value: progress)
                    Text("\(Int(progress * 100))%")
                        .font(Theme.mono(30, weight: .semibold))
                        .foregroundStyle(Theme.ivory)
                }
                .frame(width: 160, height: 160)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.gold)
            }
            Text(title)
                .font(Theme.display(22))
                .foregroundStyle(Theme.ivory)
            Text("Mantenha o app aberto e a tela ligada.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .studioBackground()
    }
}

struct ErrorView: View {
    let message: String
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.gold)
            Text("Não deu certo desta vez")
                .font(Theme.display(24))
                .foregroundStyle(Theme.ivory)
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Tentar de novo", action: onBack)
                .buttonStyle(GoldButtonStyle())
            Button("Fechar", action: onClose)
                .buttonStyle(GoldButtonStyle(filled: false))
        }
        .padding(28)
        .studioBackground()
    }
}

/// Resultado de um scan: arquivos, compartilhar, ver em 3D e dicas para o Fusion.
struct ScanResultView: View {
    @State private var record: ScanRecord
    private let onClose: (() -> Void)?
    @State private var preview: URL?

    init(record: ScanRecord, onClose: (() -> Void)? = nil) {
        _record = State(initialValue: record)
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            ScanDetailContent(record: $record, preview: $preview)
                .navigationTitle("Pronto")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        if let onClose {
                            Button("Concluir", action: onClose)
                                .foregroundStyle(Theme.gold)
                        }
                    }
                }
                .quickLookPreview($preview)
        }
    }
}

struct ScanDetailContent: View {
    @Binding var record: ScanRecord
    @Binding var preview: URL?

    private var existingFiles: [URL] {
        record.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: record.kind.title)
                    Text(record.name)
                        .font(Theme.display(26))
                        .foregroundStyle(Theme.ivory)
                    Text(record.summary)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 6)
                .listRowBackground(Theme.surface)
            }

            Section {
                ForEach(existingFiles, id: \.self) { url in
                    ShareLink(item: url) {
                        HStack(spacing: 12) {
                            Image(systemName: Self.icon(for: url))
                                .foregroundStyle(Theme.gold)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.ivory)
                                    .lineLimit(1)
                                Text(Self.describe(url))
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            } header: {
                Text("Arquivos").foregroundStyle(Theme.gold)
            }

            Section {
                if let usdz = existingFiles.first(where: { $0.pathExtension.lowercased() == "usdz" }) {
                    Button {
                        preview = usdz
                    } label: {
                        Label("Ver em 3D e em realidade aumentada", systemImage: "view.3d")
                    }
                    .listRowBackground(Theme.surface)
                }
                ShareLink(items: existingFiles) {
                    Label("Enviar todos os arquivos", systemImage: "square.and.arrow.up.on.square")
                }
                .listRowBackground(Theme.surface)
                if SyncFolder.isConfigured {
                    Button {
                        record = ScanStore.resync(record)
                    } label: {
                        Label(record.syncedTo == nil ? "Copiar para a pasta de sincronização" : "Copiar de novo para a pasta",
                              systemImage: "icloud.and.arrow.up")
                    }
                    .listRowBackground(Theme.surface)
                }
            } footer: {
                if let synced = record.syncedTo {
                    Text("Copiado para \(synced). Com o iCloud para Windows, aparece sozinho no PC.")
                } else {
                    Text("Os arquivos também ficam em Arquivos › No meu iPhone › ScanFusion › Scans.")
                }
            }

            Section {
                Text(Self.fusionTip(for: record.kind))
                    .font(.footnote)
                    .foregroundStyle(Theme.ivory.opacity(0.85))
                    .listRowBackground(Theme.surface)
            } header: {
                Text("Como usar").foregroundStyle(Theme.gold)
            }
        }
        .scrollContentBackground(.hidden)
        .studioBackground()
        .tint(Theme.gold)
    }

    static func icon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "stl": return "printer"
        case "obj": return "cube"
        case "ply", "pts": return "circle.dotted"
        case "dxf": return "square.split.bottomrightquarter"
        case "csv": return "tablecells"
        case "json": return "curlybraces"
        case "usdz": return "arkit"
        default: return "doc"
        }
    }

    static func describe(_ url: URL) -> String {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix("_fusion-leve.stl") { return "Versão leve para virar sólido no Fusion" }
        switch url.pathExtension.lowercased() {
        case "stl": return "Malha completa · Fusion e impressão 3D"
        case "obj": return "Malha completa · Fusion, Blender, SketchUp"
        case "ply": return name.contains("_nuvem") ? "Nuvem de pontos colorida · CloudCompare" : "Malha · CloudCompare, MeshLab"
        case "pts": return "Nuvem de pontos · Autodesk ReCap → Revit"
        case "dxf": return "Planta em mm · AutoCAD, Revit"
        case "csv": return "Planilha das medidas"
        case "json": return "Dados do levantamento"
        case "usdz": return "Modelo Apple · ver em AR"
        default: return url.pathExtension.uppercased()
        }
    }

    static func fusionTip(for kind: ScanKind) -> String {
        switch kind {
        case .object, .lidar:
            return "No Fusion: Inserir › Inserir malha › escolha o STL ou OBJ › unidade milímetros. Para virar sólido editável, use o arquivo \"fusion-leve\" e, na aba Malha, Converter malha."
        case .room:
            return "A planta DXF já vem em milímetros, com camadas de paredes, portas, janelas, mobiliário e cotas. No Revit: Inserir › Importar CAD. No Fusion: Inserir › Inserir DXF, ou Inserir malha com o STL."
        case .measure:
            return "O CSV abre no Excel. A planta DXF tem a poligonal medida em milímetros, com as cotas de cada trecho."
        }
    }
}
