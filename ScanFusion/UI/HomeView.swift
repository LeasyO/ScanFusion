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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    VStack(spacing: 14) {
                        ModeCard(
                            number: "I", title: "Objeto", subtitle: "Peças e itens com detalhe fino. Fotogrametria + LiDAR.",
                            icon: "cube.transparent", supported: ObjectCaptureModel.isSupported
                        ) { active = .object }
                        ModeCard(
                            number: "II", title: "Ambiente", subtitle: "Cômodos com paredes, portas e janelas. Gera planta DXF.",
                            icon: "square.split.bottomrightquarter", supported: RoomModel.isSupported
                        ) { active = .room }
                        ModeCard(
                            number: "III", title: "Malha e nuvem", subtitle: "Escaneamento livre de coisas grandes, com nuvem de pontos colorida.",
                            icon: "circle.grid.cross", supported: LidarController.isSupported
                        ) { active = .lidar }
                        ModeCard(
                            number: "IV", title: "Trena", subtitle: "Distâncias, desnível, perímetro e área com o LiDAR.",
                            icon: "ruler", supported: LidarController.isSupported
                        ) { active = .measure }
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
                            ForEach(recent.prefix(3)) { record in
                                NavigationLink {
                                    ScanDetailScreen(record: record)
                                } label: {
                                    ScanRow(record: record)
                                }
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        NavigationLink {
                            LibraryView()
                        } label: {
                            Label("Biblioteca", systemImage: "books.vertical")
                        }
                        .buttonStyle(GoldButtonStyle(filled: false))
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("Ajustes", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(GoldButtonStyle(filled: false))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .studioBackground()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { recent = ScanStore.all() }
        }
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
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Estúdio de captura 3D")
                .padding(.top, 18)
            Text("ScanFusion")
                .font(Theme.display(44))
                .foregroundStyle(Theme.goldGradient)
            Text("Escaneie com o LiDAR e leve direto para o Fusion, Revit e AutoCAD.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.ivory.opacity(0.75))
            OrnamentDivider().padding(.top, 6)
        }
    }
}

private struct ModeCard: View {
    let number: String
    let title: String
    let subtitle: String
    let icon: String
    let supported: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.ink)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.gold.opacity(0.35), lineWidth: 1)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Theme.goldGradient)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(number)
                            .font(.system(size: 11, weight: .semibold, design: .serif))
                            .foregroundStyle(Theme.gold)
                        Text(title)
                            .font(Theme.display(20))
                            .foregroundStyle(Theme.ivory)
                    }
                    Text(supported ? subtitle : "Indisponível neste aparelho")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.gold.opacity(0.7))
            }
            .card()
        }
        .buttonStyle(.plain)
        .opacity(supported ? 1 : 0.5)
        .disabled(!supported)
    }
}

struct ScanRow: View {
    let record: ScanRecord

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: record.kind.icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.gold)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.ink))
                .overlay(Circle().strokeBorder(Theme.gold.opacity(0.3), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(record.name)
                    .font(.system(size: 15, weight: .medium))
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
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }
}
