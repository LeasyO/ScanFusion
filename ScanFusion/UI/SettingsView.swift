import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage(SettingsKey.unit) private var unit: ExportUnit = .mm
    @AppStorage(SettingsKey.upAxis) private var upAxis: UpAxis = .z
    @AppStorage(SettingsKey.stl) private var stl = true
    @AppStorage(SettingsKey.obj) private var obj = true
    @AppStorage(SettingsKey.ply) private var ply = false
    @AppStorage(SettingsKey.lite) private var lite = true
    @AppStorage(SettingsKey.liteTriangles) private var liteTriangles = 20_000
    @AppStorage(SettingsKey.splitClasses) private var splitClasses = false
    @AppStorage(SettingsKey.maxDepth) private var maxDepth = 4.0
    @AppStorage(SettingsKey.voxelCM) private var voxelCM = 1.0

    @State private var pickingFolder = false
    @State private var syncName = SyncFolder.displayName
    @State private var syncError: String?

    var body: some View {
        Form {
            Section {
                Picker("Unidade", selection: $unit) {
                    ForEach(ExportUnit.allCases) { Text($0.title).tag($0) }
                }
                Picker("Eixo vertical", selection: $upAxis) {
                    ForEach(UpAxis.allCases) { Text($0.title).tag($0) }
                }
                Toggle("STL", isOn: $stl)
                Toggle("OBJ", isOn: $obj)
                Toggle("PLY", isOn: $ply)
            } header: {
                Text("Exportação").foregroundStyle(Theme.gold)
            } footer: {
                Text("Milímetros com Z para cima abrem no Fusion na escala e posição certas, sem ajustes.")
            }
            .listRowBackground(Theme.surface)

            Section {
                Toggle("Gerar versão leve", isOn: $lite)
                Stepper(value: $liteTriangles, in: 5_000...60_000, step: 5_000) {
                    Text("Até \(Exporter.formatCount(liteTriangles)) triângulos")
                }
                .disabled(!lite)
            } header: {
                Text("Fusion").foregroundStyle(Theme.gold)
            } footer: {
                Text("O Fusion só converte malha em sólido com poucos triângulos. A versão leve já sai no tamanho certo.")
            }
            .listRowBackground(Theme.surface)

            Section {
                VStack(alignment: .leading) {
                    Text("Alcance máximo: \(String(format: "%.1f", maxDepth)) m")
                    Slider(value: $maxDepth, in: 1...5, step: 0.5)
                }
                VStack(alignment: .leading) {
                    Text("Densidade da nuvem: 1 ponto a cada \(String(format: "%.1f", voxelCM)) cm")
                    Slider(value: $voxelCM, in: 0.5...3, step: 0.5)
                }
                Toggle("Separar malha por tipo (paredes, piso, teto, móveis…)", isOn: $splitClasses)
            } header: {
                Text("LiDAR").foregroundStyle(Theme.gold)
            } footer: {
                Text("O LiDAR do iPhone é mais preciso até uns 3 m. Mais densidade = arquivos maiores.")
            }
            .listRowBackground(Theme.surface)

            Section {
                if let syncName {
                    Label(syncName, systemImage: "folder.fill")
                        .foregroundStyle(Theme.goldLight)
                    Button("Trocar pasta") { pickingFolder = true }
                    Button("Parar de copiar", role: .destructive) {
                        SyncFolder.clear()
                        self.syncName = nil
                    }
                } else {
                    Button {
                        pickingFolder = true
                    } label: {
                        Label("Escolher pasta (Google Drive ou iCloud)", systemImage: "folder.badge.plus")
                    }
                }
                if let syncError {
                    Text(syncError).font(.footnote).foregroundStyle(Theme.danger)
                }
            } header: {
                HStack {
                    Text("Envio automático para o PC").foregroundStyle(Theme.gold)
                    Spacer()
                    InfoButton(text: "Precisa do app Google Drive no iPhone, na mesma conta do PC. Escolha Google Drive › Meu Drive › ScanFusion uma vez só. Cada scan sobe sozinho (no modo Objeto, com as fotos) e aparece no Estúdio 3D › Scanner › Capturas.")
                }
            } footer: {
                Text("No Arquivos, escolha Google Drive › Meu Drive › ScanFusion. Cada scan vai para lá sozinho, com as fotos do modo Objeto, e aparece no Estúdio 3D › Scanner, sem cabo.")
            }
            .listRowBackground(Theme.surface)

            Section {
                LabeledContent("Versão", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                LabeledContent("Atalho", value: "Botão de Ação ou Siri")
            } header: {
                Text("Sobre").foregroundStyle(Theme.gold)
            } footer: {
                Text("No Ajustes do iPhone › Botão de Ação › Atalho, escolha \"Escanear objeto\" do ScanFusion para abrir direto na captura.")
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .studioBackground()
        .tint(Theme.gold)
        .navigationTitle("Ajustes")
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                do {
                    try SyncFolder.set(url)
                    syncName = SyncFolder.displayName
                    syncError = nil
                } catch {
                    syncError = "Não foi possível usar essa pasta: \(error.localizedDescription)"
                }
            case .failure(let error):
                syncError = error.localizedDescription
            }
        }
    }
}
