import Foundation

enum ScanKind: String, Codable, CaseIterable {
    case object, room, lidar, measure

    var title: String {
        switch self {
        case .object: return "Objeto"
        case .room: return "Ambiente"
        case .lidar: return "Malha e nuvem LiDAR"
        case .measure: return "Medições"
        }
    }

    var icon: String {
        switch self {
        case .object: return "cube.transparent"
        case .room: return "square.split.bottomrightquarter"
        case .lidar: return "circle.grid.cross"
        case .measure: return "ruler"
        }
    }
}

struct ScanRecord: Codable, Identifiable, Hashable {
    var folderName: String
    var name: String
    var kind: ScanKind
    var date: Date
    var files: [String]
    var summary: String
    var syncedTo: String?

    var id: String { folderName }
    var folderURL: URL { ScanStore.root.appendingPathComponent(folderName, isDirectory: true) }
    var fileURLs: [URL] { files.map { folderURL.appendingPathComponent($0) } }
}

enum ScanStore {
    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scans", isDirectory: true)
    }

    static func safeName(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? fallback : trimmed
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(base.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    static func newFolder(name: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = root.appendingPathComponent("\(name)-\(formatter.string(from: Date()))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Grava o registro do scan e copia os arquivos para a pasta de sincronização, se houver.
    static func finalize(folder: URL, name: String, kind: ScanKind, files: [URL], summary: String) -> ScanRecord {
        let prefix = folder.standardizedFileURL.path + "/"
        let relative = files.map { $0.standardizedFileURL.path.replacingOccurrences(of: prefix, with: "") }
        var record = ScanRecord(
            folderName: folder.lastPathComponent,
            name: name,
            kind: kind,
            date: Date(),
            files: relative,
            summary: summary,
            syncedTo: nil
        )
        if let target = SyncFolder.copy(files, into: record.folderName) {
            record.syncedTo = target
        }
        save(record)
        sendPhotos(of: record)
        return record
    }

    /// Fotos do modo Objeto vão junto para a pasta de envio (o Estúdio 3D reconstrói em alta no PC).
    /// Em segundo plano: são centenas de MB e não podem travar a tela.
    static func sendPhotos(of record: ScanRecord) {
        let photos = record.folderURL.appendingPathComponent("Fotos", isDirectory: true)
        guard FileManager.default.fileExists(atPath: photos.path) else { return }
        let folder = record.folderName
        Task.detached(priority: .utility) {
            _ = SyncFolder.copy([photos], into: folder)
        }
    }

    static func save(_ record: ScanRecord) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(record) {
            try? data.write(to: record.folderURL.appendingPathComponent("scan.json"), options: .atomic)
        }
    }

    static func all() -> [ScanRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("scan.json")) else { return nil }
            return try? decoder.decode(ScanRecord.self, from: data)
        }
        .sorted { $0.date > $1.date }
    }

    static func delete(_ record: ScanRecord) {
        try? FileManager.default.removeItem(at: record.folderURL)
    }

    static func resync(_ record: ScanRecord) -> ScanRecord {
        var updated = record
        updated.syncedTo = SyncFolder.copy(record.fileURLs, into: record.folderName)
        save(updated)
        sendPhotos(of: updated)
        return updated
    }
}

/// Pasta escolhida pelo usuário (ex.: Google Drive/ScanFusion) para onde cada scan é copiado sozinho.
/// Com o Google Drive (ou o iCloud) para Windows, os arquivos aparecem no PC automaticamente.
enum SyncFolder {
    private static let key = "sync.bookmark"

    static var isConfigured: Bool { UserDefaults.standard.data(forKey: key) != nil }

    static func set(_ url: URL) throws {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale {
            let ok = url.startAccessingSecurityScopedResource()
            if let fresh = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: key)
            }
            if ok { url.stopAccessingSecurityScopedResource() }
        }
        return url
    }

    static var displayName: String? { resolve()?.lastPathComponent }

    /// Retorna o caminho de destino quando a cópia funciona.
    static func copy(_ files: [URL], into subfolder: String) -> String? {
        guard let root = resolve(), !files.isEmpty else { return nil }
        let ok = root.startAccessingSecurityScopedResource()
        defer { if ok { root.stopAccessingSecurityScopedResource() } }
        let dest = root.appendingPathComponent(subfolder, isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            for file in files {
                let target = dest.appendingPathComponent(file.lastPathComponent)
                try? fm.removeItem(at: target)
                try fm.copyItem(at: file, to: target)
            }
            return "\(root.lastPathComponent)/\(subfolder)"
        } catch {
            return nil
        }
    }
}
