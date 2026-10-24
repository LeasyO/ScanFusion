import SwiftUI
import AppIntents

@main
struct ScanFusionApp: App {
    init() {
        Theme.applyUIKitAppearance()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
        }
    }
}

// MARK: - Atalhos (Siri, app Atalhos e Botão de Ação do iPhone 15 Pro Max)

struct ScanObjectIntent: AppIntent {
    static var title: LocalizedStringResource = "Escanear objeto"
    static var description = IntentDescription("Abre o ScanFusion direto na captura de objeto.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pending = .object
        return .result()
    }
}

struct ScanRoomIntent: AppIntent {
    static var title: LocalizedStringResource = "Escanear ambiente"
    static var description = IntentDescription("Abre o ScanFusion direto no levantamento de cômodo.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pending = .room
        return .result()
    }
}

struct ScanLidarIntent: AppIntent {
    static var title: LocalizedStringResource = "Escanear com LiDAR"
    static var description = IntentDescription("Abre o ScanFusion direto na malha e nuvem de pontos.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pending = .lidar
        return .result()
    }
}

struct MeasureIntent: AppIntent {
    static var title: LocalizedStringResource = "Medir com a trena"
    static var description = IntentDescription("Abre o ScanFusion direto na trena LiDAR.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pending = .measure
        return .result()
    }
}

struct ScanFusionShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanObjectIntent(),
            phrases: ["Escanear objeto no \(.applicationName)", "Abrir captura do \(.applicationName)"],
            shortTitle: "Escanear objeto",
            systemImageName: "cube.transparent"
        )
        AppShortcut(
            intent: ScanRoomIntent(),
            phrases: ["Escanear ambiente no \(.applicationName)"],
            shortTitle: "Escanear ambiente",
            systemImageName: "square.split.bottomrightquarter"
        )
        AppShortcut(
            intent: ScanLidarIntent(),
            phrases: ["Escanear com LiDAR no \(.applicationName)"],
            shortTitle: "Malha LiDAR",
            systemImageName: "circle.grid.cross"
        )
        AppShortcut(
            intent: MeasureIntent(),
            phrases: ["Medir com o \(.applicationName)"],
            shortTitle: "Trena",
            systemImageName: "ruler"
        )
    }
}
