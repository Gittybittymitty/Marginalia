import SwiftUI
import SwiftData

/// The best-of shelf: the passages you starred, plus the ones Marginalia thinks
/// deserve a look.
struct BestQuotesView: View {
    @Environment(\.modelContext) private var context
    @Query private var highlights: [Highlight]

    @State private var mode: Mode = .starred
    @State private var export: ExportFile?

    enum Mode: String, CaseIterable, Identifiable {
        case starred = "Starred"
        case suggested = "Suggested"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if highlights.isEmpty {
                    EmptyShelf(
                        symbol: "star",
                        title: "No best-of yet",
                        message: "Star a passage anywhere in the app and it shows up here."
                    )
                } else {
                    content
                }
            }
            .navigationTitle("Best quotes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        exportBest()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(shown.isEmpty)
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

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if mode == .suggested {
                    Text("Ranked by what usually marks a keeper: you wrote a note, it's quotable length, and it reads as a complete thought. Star the ones that land.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if shown.isEmpty {
                    EmptyShelf(
                        symbol: "star",
                        title: "Nothing starred yet",
                        message: "Swipe right on any passage, or tap the star while reading one."
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(shown) { highlight in
                        NavigationLink(value: highlight) {
                            BestQuoteCard(highlight: highlight)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var shown: [Highlight] {
        switch mode {
        case .starred:
            highlights.filter(\.isFavorite).sorted { $0.dateForSorting > $1.dateForSorting }
        case .suggested:
            QuoteRanker.best(from: highlights.filter { !$0.isFavorite }, limit: 20)
        }
    }

    private func exportBest() {
        if let url = try? Exporter.temporaryFile(
            named: "best-quotes.md",
            contents: Exporter.markdown(for: shown, title: "Best quotes")
        ) {
            export = ExportFile(url: url)
        }
    }
}

private struct BestQuoteCard: View {
    let highlight: Highlight
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "quote.opening")
                    .font(.title3)
                    .foregroundStyle(Marker.color(highlight.colorIndex))
                Spacer()
                Button {
                    HighlightStore(context: context).toggleFavorite(highlight)
                } label: {
                    Image(systemName: highlight.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(highlight.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            }

            Text(highlight.text)
                .font(.system(.body, design: .serif))
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !highlight.noteSummary.isEmpty {
                Text(highlight.noteSummary)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Divider()
            Provenance(highlight: highlight)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Marker.color(highlight.colorIndex))
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    BestQuotesView()
        .modelContainer(SampleLibrary.previewContainer)
}
