import SwiftUI
import SwiftData

/// Every passage from every app in one stream, which is the view that only
/// exists because the highlights were pulled out of their separate silos.
struct QuotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Highlight.importedAt, order: .reverse) private var highlights: [Highlight]

    @State private var searchText = ""
    @State private var sourceFilter: SourceApp?
    @State private var noteFilter: NoteFilter = .all
    @State private var export: ExportFile?

    enum NoteFilter: String, CaseIterable, Identifiable {
        case all = "Everything"
        case annotated = "With a note"
        case bare = "Still unexplained"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if highlights.isEmpty {
                    EmptyShelf(
                        symbol: "quote.opening",
                        title: "No passages yet",
                        message: "Everything you import from Kindle, Kobo, Apple Books or the share sheet collects here."
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Quotes")
            .searchable(text: $searchText, prompt: "Search passages, notes, tags")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Source", selection: $sourceFilter) {
                            Text("Every app").tag(SourceApp?.none)
                            ForEach(presentSources) { source in
                                Label(source.displayName, systemImage: source.symbol)
                                    .tag(SourceApp?.some(source))
                            }
                        }
                        Divider()
                        Picker("Notes", selection: $noteFilter) {
                            ForEach(NoteFilter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Divider()
                        Button {
                            exportAll()
                        } label: {
                            Label("Export everything", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Label("Filter", systemImage: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(item: $export) { file in
                ShareSheet(items: [file.url])
            }
            .navigationDestination(for: Highlight.self) { highlight in
                HighlightDetailView(highlight: highlight)
            }
        }
    }

    private var list: some View {
        List {
            if isFiltering || !searchText.isEmpty {
                Section {
                    Text("\(visible.count) of \(highlights.count) \(highlights.count == 1 ? "passage" : "passages")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if visible.isEmpty {
                ContentUnavailableView(
                    "Nothing matches",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Try a different app or clear the filter.")
                )
            } else {
                ForEach(groupedByDay, id: \.day) { group in
                    Section(group.label) {
                        ForEach(group.highlights) { highlight in
                            NavigationLink(value: highlight) {
                                HighlightRow(highlight: highlight)
                            }
                            .highlightRowActions(for: highlight)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var presentSources: [SourceApp] {
        let present = Set(highlights.map(\.source))
        return SourceApp.allCases.filter { present.contains($0) }
    }

    private var isFiltering: Bool {
        sourceFilter != nil || noteFilter != .all
    }

    private var visible: [Highlight] {
        highlights.filter { highlight in
            if let sourceFilter, highlight.source != sourceFilter { return false }
            switch noteFilter {
            case .all: break
            case .annotated: if !highlight.hasNote { return false }
            case .bare: if highlight.hasNote { return false }
            }
            guard !searchText.isEmpty else { return true }
            return highlight.text.localizedCaseInsensitiveContains(searchText)
                || highlight.noteSummary.localizedCaseInsensitiveContains(searchText)
                || highlight.noteExplanation.localizedCaseInsensitiveContains(searchText)
                || highlight.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
                || (highlight.book?.title.localizedCaseInsensitiveContains(searchText) ?? false)
                || (highlight.book?.author.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var groupedByDay: [(day: Date, label: String, highlights: [Highlight])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visible) { calendar.startOfDay(for: $0.dateForSorting) }
        return grouped.keys.sorted(by: >).map { day in
            (day, day.formatted(.dateTime.weekday(.wide).day().month(.wide)), grouped[day]!.sorted { $0.dateForSorting > $1.dateForSorting })
        }
    }

    private func exportAll() {
        if let url = try? Exporter.temporaryFile(
            named: "marginalia-highlights.md",
            contents: Exporter.markdown(for: visible, title: "My highlights")
        ) {
            export = ExportFile(url: url)
        }
    }
}

#Preview {
    QuotesView()
        .modelContainer(SampleLibrary.previewContainer)
}
