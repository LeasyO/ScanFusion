import SwiftUI

enum CaptureMode: String, Identifiable, CaseIterable {
    case object, room, lidar, measure
    var id: String { rawValue }
}

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var pending: CaptureMode?
}

struct HomeView: View {
    @ObservedObject private var router = AppRouter.shared
    @State private var active: CaptureMode?
    @State private var recent: [ScanRecord] = []

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 2) {
                            Eyebrow(text: "Capturar")
                            InfoButton(text: "Objeto: peças com detalhe e medida (fotos + LiDAR; no PC chega a décimos de mm). Ambiente: cômodo inteiro com paredes, portas e janelas, gera planta DXF. LiDAR: malha e nuvem de pontos de coisas grandes. Trena: distâncias, desnível e área na hora.")
                        }
                        ModeHero(
                            title: "Objeto", tag: "Fotogrametria + LiDAR",
                            subtitle: "Peças e itens com detalhe fino, prontos para o Fusion.",
                            icon: "cube.transparent", supported: ObjectCaptureModel.isSupported
                        ) { active = .object }
                        LazyVGrid(columns: columns, spacing: 12) {
                            ModeTile(
                                title: "Ambiente", tag: "Planta DXF",
                                icon: "square.split.bottomrightquarter", supported: RoomModel.isSupported
                            ) { active = .room }
                            ModeTile(
                                title: "LiDAR", tag: "Malha e nuvem",
                                icon: "circle.grid.cross", supported: LidarController.isSupported
                            ) { active = .lidar }
                            ModeTile(
                                title: "Trena", tag: "Medidas e área",
                                icon: "ruler", supported: LidarController.isSupported
                            ) { active = .measure }
                            NavigationLink {
                                LibraryView()
                            } label: {
                                TileBody(title: "Biblioteca", tag: "Todos os scans", icon: "books.vertical")
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }

                    if !recent.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Eyebrow(text: "Recentes")
                                Spacer()
                                NavigationLink("Ver todos") { LibraryView() }
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.gold)
                            }
                            VStack(spacing: 8) {
                                ForEach(recent.prefix(3)) { record in
                                    NavigationLink {
                                        ScanDetailScreen(record: record)
                                    } label: {
                                        ScanRow(record: record)
                                    }
                                    .buttonStyle(PressableStyle())
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .studioBackground()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { recent = ScanStore.all() }
        }
        .tint(Theme.gold)
        .fullScreenCover(item: $active, onDismiss: { recent = ScanStore.all() }) { mode in
            switch mode {
            case .object: ObjectCaptureFlow()
            case .room: RoomFlow()
            case .lidar: LidarFlow()
            case .measure: MeasureFlow()
            }
        }
        .onReceive(router.$pending) { mode in
            guard let mode else { return }
            router.pending = nil
            active = mode
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                BrandMark(size: 40)
                Spacer()
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ivory)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.rimGradient, lineWidth: 0.75))
                        .environment(\.colorScheme, .dark)
                }
                .accessibilityLabel("Ajustes")
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("ScanFusion")
                    .font(.system(size: 40, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(Theme.ivory)
                Text("Escaneie com o LiDAR e leve direto para o Fusion, Revit e AutoCAD.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Cartão grande do modo principal.
private struct ModeHero: View {
    let title: String
    let tag: String
    let subtitle: String
    let icon: String
    let supported: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    IconTile(systemName: icon, size: 58)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.goldGradient))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(tag.uppercased())
                        .font(Theme.eyebrow(10))
                        .tracking(1.6)
                        .foregroundStyle(Theme.gold)
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.ivory)
                    Text(supported ? subtitle : "Indisponível neste aparelho")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(PressableStyle())
        .opacity(supported ? 1 : 0.45)
        .disabled(!supported)
    }
}

private struct ModeTile: View {
    let title: String
    let tag: String
    let icon: String
    let supported: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TileBody(title: title, tag: supported ? tag : "Indisponível", icon: icon)
        }
        .buttonStyle(PressableStyle())
        .opacity(supported ? 1 : 0.45)
        .disabled(!supported)
    }
}

private struct TileBody: View {
    let title: String
    let tag: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            IconTile(systemName: icon, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ivory)
                Text(tag)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Afunda levemente ao tocar, sem apagar o conteúdo.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct ScanRow: View {
    let record: ScanRecord

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemName: record.kind.icon, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ivory)
                    .lineLimit(1)
                Text(record.date.formatted(date: .abbreviated, time: .shortened) + " · " + record.kind.title)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if record.syncedTo != nil {
                Image(systemName: "icloud.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.gold.opacity(0.8))
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}
