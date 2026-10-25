import SwiftUI
import QuickLook

struct LibraryView: View {
    @State private var records: [ScanRecord] = []
    @State private var filter: ScanKind?

    private var filtered: [ScanRecord] {
        guard let filter else { return records }
        return records.filter { $0.kind == filter }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(nil, "Todos")
                        ForEach(ScanKind.allCases, id: \.self) { kind in chip(kind, kind.title) }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            if filtered.isEmpty {
                Text("Nenhum scan ainda.")
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Theme.surface)
            }

            ForEach(filtered) { record in
                NavigationLink {
                    ScanDetailScreen(record: record)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: record.kind.icon).foregroundStyle(Theme.gold)
                            Text(record.name).foregroundStyle(Theme.ivory)
                        }
                        Text(record.date.formatted(date: .abbreviated, time: .shortened) + " · " + record.summary)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.surface)
            }
            .onDelete { offsets in
                for index in offsets { ScanStore.delete(filtered[index]) }
                records = ScanStore.all()
            }
        }
        .scrollContentBackground(.hidden)
        .studioBackground()
        .navigationTitle("Biblioteca")
        .onAppear { records = ScanStore.all() }
    }

    private func chip(_ kind: ScanKind?, _ title: String) -> some View {
        let selected = filter == kind
        return Button {
            filter = kind
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Theme.ink : Theme.goldLight)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(selected ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.surface))
                )
                .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

struct ScanDetailScreen: View {
    @State private var record: ScanRecord
    @State private var preview: URL?

    init(record: ScanRecord) {
        _record = State(initialValue: record)
    }

    var body: some View {
        ScanDetailContent(record: $record, preview: $preview)
            .navigationTitle(record.name)
            .navigationBarTitleDisplayMode(.inline)
            .quickLookPreview($preview)
    }
}
