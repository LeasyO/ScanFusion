# ScanFusion — contexto para o Claude Code

App iOS (SwiftUI, iOS 17+) para escanear em 3D com o LiDAR do iPhone 15 Pro Max e exportar para
Fusion, Revit e AutoCAD. Interface e textos em **português do Brasil**.

## Restrição principal: não há Mac
O usuário só tem **Windows**. Não existe Xcode local, `swift` nem `xcodebuild` aqui.
- A compilação acontece **só no GitHub Actions** (`.github/workflows/build.yml`, runner `macos-latest`).
- O projeto Xcode **não fica no repositório**: é gerado na nuvem pelo XcodeGen a partir do `project.yml`.
  Arquivo `.swift` novo dentro de `ScanFusion/` entra no build sozinho; não edite `.xcodeproj`.
- Linguagem Swift 5 (`SWIFT_VERSION: 5.0`) para evitar erros de concorrência estrita do Swift 6.

## Ciclo de trabalho
1. Editar o código.
2. `git add -A && git commit -m "..." && git push`
3. Acompanhar: `gh run watch` (ou `gh run list --limit 3`)
4. Se falhar: `gh run view --log-failed` e procurar linhas `error:`; corrigir e repetir.
5. Quando passa, a Release `latest` recebe o `ScanFusion.ipa` (versão 2.0.<número do run>). A instalação
   no iPhone é pelo iloader (Import IPA), com cabo; o SideStore não loga desde out/2026 (erro -80045).
   Workflow só roda sozinho em push na `main`; numa branch: `gh workflow run build.yml --ref <branch>`.

Como não há compilador local, revise com cuidado assinaturas de APIs da Apple (ARKit, RealityKit,
RoomPlan, ModelIO, Object Capture) antes de enviar.

## Estrutura
- `ScanFusion/Core/` — Theme (preto + dourado, único lugar das cores), Settings (UserDefaults),
  Mesh (MeshData, leitura ARKit/USDZ, simplificação, escritores STL/OBJ/PLY/PTS, DXFWriter),
  ScanStore (Documents/Scans/<nome-data>/scan.json) e SyncFolder (pasta do iCloud Drive via bookmark),
  Exporter.
- `ScanFusion/Modes/` — ObjectCaptureMode (Object Capture + PhotogrammetrySession),
  RoomMode (RoomPlan → planta DXF em mm), LidarMode (malha + nuvem de pontos), MeasureMode (trena).
- `ScanFusion/UI/` — HomeView (+ AppRouter), LibraryView, SettingsView, Common (ModeIntro,
  WorkingView, ErrorView, ScanResultView).
- `ScanFusionApp.swift` — App + App Intents (Siri / Botão de Ação).
- `Support/` — Info.plist e PrivacyInfo.xcprivacy. `scripts/make_source.py` — fonte do SideStore.

## Convenções
- Exportação padrão: milímetros, Z para cima (`ExportOptions.current`).
- Coordenadas internas: metros, Y para cima (padrão ARKit); converter só na exportação (`Geometry.convert`).
- Cada fluxo termina em `ScanStore.finalize(...)`, que salva o registro e copia para a pasta de sync.
- Distribuição: iloader com conta Apple grátis (7 dias) ou TestFlight (job opcional com segredos ASC_*).
- Alta precisão no PC: as fotos do modo Objeto (`Scans/<pasta>/Fotos`, HEIC com profundidade) são puxadas
  pelo cabo e processadas pela aba Scanner do Estúdio 3D (`C:\Users\rafas\Documents\Claude\Tripo3D\scanner`):
  COLMAP na GPU, escala pela folha de marcadores ArUco ou pelo LiDAR. Por isso o over-capture fica ligado.
