import SwiftUI
import SwiftData

struct BookDetailView: View {
    let book: Book

    @Environment(\.modelContext) private var context
    @State private var sort: SortOrder = .book
    @State private var onlyStarred = false
    @State private var export: ExportFile?

    enum SortOrder: String, CaseIterable, Identifiable {
        case book = "In book order"
        case newest = "Newest first"
        case best = "Most quotable"

        var id: String { rawValue }
    }

    var body: some View {
        List {
            Section {
                header
            }

            Section {
                if visibleHighlights.isEmpty {
                    Text(onlyStarred ? "Nothing starred in this book yet." : "No passages here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleHighlights) { highlight in
                        NavigationLink {
                            HighlightDetailView(highlight: highlight)
                        } label: {
                            HighlightRow(highlight: highlight, showsBook: false)
                        }
                        .highlightRowActions(for: highlight)
                    }
                }
            } header: {
                HStack {
                    Text("\(visibleHighlights.count) \(visibleHighlights.count == 1 ? "passage" : "passages")")
                    Spacer()
                    Toggle(isOn: $onlyStarred) {
                        Image(systemName: "star.fill")
                    }
                    .toggleStyle(.button)
                    .font(.caption)
                }
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Order", selection: $sort) {
                        ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Divider()
                    Button {
                        exportMarkdown()
                    } label: {
                        Label("Export as Markdown", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $export) { file in
            ShareSheet(items: [file.url])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(book.title)
                .font(.title2.weight(.semibold))
            Text(book.displayAuthor)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SourceBadge(source: book.source)
                if book.favoriteCount > 0 {
                    Label("\(book.favoriteCount) starred", systemImage: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var visibleHighlights: [Highlight] {
        var items = book.highlights
        if onlyStarred { items = items.filter(\.isFavorite) }
        switch sort {
        case .book:
            return items.sorted { lhs, rhs in
                let left = leadingNumber(in: lhs.locationLabel)
                let right = leadingNumber(in: rhs.locationLabel)
                if left != right { return left < right }
                return lhs.dateForSorting < rhs.dateForSorting
            }
        case .newest:
            return items.sorted { $0.dateForSorting > $1.dateForSorting }
        case .best:
            return QuoteRanker.best(from: items, limit: items.count)
        }
    }

    /// "Page 42 · Location 603" sorts by its first number, with unlabelled
    /// passages dropping to the end rather than to the top.
    private func leadingNumber(in label: String) -> Int {
        let digits = label.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty }
        return digits.flatMap(Int.init) ?? Int.max
    }

    private func exportMarkdown() {
        let safeName = book.title.replacingOccurrences(of: "/", with: "-")
        if let url = try? Exporter.temporaryFile(
            named: "\(safeName).md",
            contents: Exporter.markdown(for: book)
        ) {
            export = ExportFile(url: url)
        }
    }
}

/// `URL` isn't `Identifiable`, and the share sheet is presented by item.
struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// A thin wrapper so SwiftUI can present the system share sheet for exports.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        BookDetailView(book: try! SampleLibrary.previewContainer.mainContext.fetch(FetchDescriptor<Book>()).first!)
    }
    .modelContainer(SampleLibrary.previewContainer)
}
