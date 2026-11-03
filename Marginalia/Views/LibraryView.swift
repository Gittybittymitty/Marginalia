import SwiftUI
import SwiftData

/// The shelf: every book you've pulled highlights out of, whichever app they
/// came from, with one quote raised to the top of the screen each day.
struct LibraryView: View {
    @Binding var banner: Banner?

    @Environment(\.modelContext) private var context
    @Query(sort: \Book.lastImportedAt, order: .reverse) private var books: [Book]
    @Query private var allHighlights: [Highlight]

    @State private var searchText = ""
    @State private var isAddingByHand = false

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    EmptyShelf(
                        symbol: "books.vertical",
                        title: "Nothing on the shelf yet",
                        message: "Bring in your Kindle clippings, your Kobo database, or share a quote from any reading app.",
                        actionTitle: "Add one by hand",
                        action: { isAddingByHand = true }
                    )
                } else {
                    shelf
                }
            }
            .navigationTitle("Shelf")
            .searchable(text: $searchText, prompt: "Books, authors, passages")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingByHand = true
                    } label: {
                        Label("Add a quote", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingByHand) {
                AddHighlightView { outcome in
                    banner = Banner(text: outcome.summary, isError: false)
                }
            }
        }
    }

    private var shelf: some View {
        List {
            if searchText.isEmpty, let quote = QuoteRanker.quoteOfTheDay(from: allHighlights) {
                Section {
                    NavigationLink(value: Route.highlight(quote.persistentModelID)) {
                        QuoteOfTheDayCard(highlight: quote)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Today's passage")
                }
            }

            if searchText.isEmpty {
                Section {
                    StatsRow(books: books.count, highlights: allHighlights.count, favorites: allHighlights.count(where: \.isFavorite), notes: allHighlights.count(where: \.hasNote))
                }
            }

            ForEach(groupedBooks, id: \.source) { group in
                Section {
                    ForEach(group.books) { book in
                        NavigationLink(value: Route.book(book.persistentModelID)) {
                            BookRow(book: book, searchText: searchText)
                        }
                    }
                    .onDelete { offsets in
                        delete(at: offsets, in: group.books)
                    }
                } header: {
                    HStack {
                        Image(systemName: group.source.symbol)
                            .foregroundStyle(group.source.tint)
                        Text(group.source.displayName)
                    }
                }
            }

            if !searchText.isEmpty && matchingHighlights.isEmpty && groupedBooks.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }

            if !searchText.isEmpty && !matchingHighlights.isEmpty {
                Section("Passages") {
                    ForEach(matchingHighlights) { highlight in
                        NavigationLink(value: Route.highlight(highlight.persistentModelID)) {
                            HighlightRow(highlight: highlight)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: Route.self) { route in
            route.destination(books: books, highlights: allHighlights)
        }
    }

    private var filteredBooks: [Book] {
        guard !searchText.isEmpty else { return books }
        return books.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.author.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var matchingHighlights: [Highlight] {
        guard searchText.count > 1 else { return [] }
        return allHighlights
            .filter { $0.text.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.dateForSorting > $1.dateForSorting }
            .prefix(20)
            .map { $0 }
    }

    private var groupedBooks: [(source: SourceApp, books: [Book])] {
        let grouped = Dictionary(grouping: filteredBooks, by: \.source)
        return SourceApp.allCases.compactMap { source in
            guard let group = grouped[source], !group.isEmpty else { return nil }
            return (source, group.sorted { $0.lastImportedAt > $1.lastImportedAt })
        }
    }

    private func delete(at offsets: IndexSet, in group: [Book]) {
        let store = HighlightStore(context: context)
        for index in offsets {
            try? store.delete(group[index])
        }
    }
}

/// Routes are carried as model ids rather than objects so a deleted book can't
/// strand the navigation stack on a dangling reference.
enum Route: Hashable {
    case book(PersistentIdentifier)
    case highlight(PersistentIdentifier)

    @ViewBuilder
    func destination(books: [Book], highlights: [Highlight]) -> some View {
        switch self {
        case .book(let id):
            if let book = books.first(where: { $0.persistentModelID == id }) {
                BookDetailView(book: book)
            } else {
                ContentUnavailableView("This book is no longer on the shelf", systemImage: "book.closed")
            }
        case .highlight(let id):
            if let highlight = highlights.first(where: { $0.persistentModelID == id }) {
                HighlightDetailView(highlight: highlight)
            } else {
                ContentUnavailableView("This passage has been removed", systemImage: "quote.closing")
            }
        }
    }
}

private struct QuoteOfTheDayCard: View {
    let highlight: Highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuoteText(text: highlight.text, colorIndex: highlight.colorIndex, lineLimit: 6)
            Provenance(highlight: highlight)
            if !highlight.noteSummary.isEmpty {
                Label(highlight.noteSummary, systemImage: "text.quote")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct StatsRow: View {
    let books: Int
    let highlights: Int
    let favorites: Int
    let notes: Int

    var body: some View {
        HStack(spacing: 0) {
            stat(value: books, label: books == 1 ? "book" : "books", symbol: "book.closed")
            Divider()
            stat(value: highlights, label: "passages", symbol: "quote.opening")
            Divider()
            stat(value: favorites, label: "starred", symbol: "star.fill")
            Divider()
            stat(value: notes, label: "with notes", symbol: "square.and.pencil")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func stat(value: Int, label: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BookRow: View {
    let book: Book
    var searchText: String = ""

    var body: some View {
        HStack(spacing: 12) {
            Spine(book: book)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(book.displayAuthor)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Label("\(book.highlights.count)", systemImage: "quote.opening")
                    if book.favoriteCount > 0 {
                        Label("\(book.favoriteCount)", systemImage: "star.fill")
                    }
                    if book.annotatedCount > 0 {
                        Label("\(book.annotatedCount)", systemImage: "square.and.pencil")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A stand-in for a cover: the spine colour comes from the book's own title, so
/// the same book always looks the same without downloading any artwork.
private struct Spine: View {
    let book: Book

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [book.source.tint.opacity(0.95), book.source.tint.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 36, height: 52)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.black.opacity(0.18))
                    .frame(width: 4)
            }
            .overlay {
                Text(initials)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.leading, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var initials: String {
        let words = book.title.split(whereSeparator: \.isWhitespace).prefix(2)
        return words.compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

#Preview {
    LibraryView(banner: .constant(nil))
        .modelContainer(SampleLibrary.previewContainer)
}
