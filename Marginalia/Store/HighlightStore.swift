import Foundation
import SwiftData

/// All the writes in one place, so importing, pasting, sharing and typing by
/// hand all land in the library the same way.
@MainActor
struct HighlightStore {
    let context: ModelContext

    // MARK: - Books

    func book(title: String, author: String, source: SourceApp) throws -> Book {
        let identity = Book.identity(title: title, author: author)
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.identity == identity })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            // A later import can fill in an author the first one was missing.
            if existing.author.isEmpty && !author.isEmpty {
                existing.author = author
            }
            existing.lastImportedAt = .now
            return existing
        }
        let book = Book(title: title, author: author, source: source)
        context.insert(book)
        return book
    }

    // MARK: - Import

    /// Saves the staged passages the reader ticked, skipping anything already on
    /// the shelf. Returns how many were new and how many were duplicates.
    @discardableResult
    func save(_ staged: [StagedHighlight]) throws -> ImportOutcome {
        var added = 0
        var duplicates = 0

        for item in staged {
            let book = try book(title: item.bookTitle, author: item.bookAuthor, source: item.source)
            let fingerprint = Highlight.fingerprint(text: item.text, bookIdentity: book.identity)

            var descriptor = FetchDescriptor<Highlight>(predicate: #Predicate { $0.fingerprint == fingerprint })
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                // Keep an imported note if we didn't have one before.
                if existing.noteExplanation.isEmpty, let note = item.note, !note.isEmpty {
                    existing.noteExplanation = note
                }
                duplicates += 1
                continue
            }

            let highlight = Highlight(
                text: item.text,
                locationLabel: item.locationLabel,
                highlightedAt: item.highlightedAt,
                source: item.source,
                book: book,
                noteExplanation: item.note ?? "",
                colorIndex: abs(item.text.hashValue) % 5
            )
            highlight.isFavorite = item.markFavorite
            highlight.refreshFingerprint()
            context.insert(highlight)
            added += 1
        }

        try context.save()
        return ImportOutcome(added: added, duplicates: duplicates)
    }

    func ingest(_ items: [InboxItem]) throws -> ImportOutcome {
        let staged = items.map { item in
            StagedHighlight(
                bookTitle: item.bookTitle.isEmpty ? "Shared quotes" : item.bookTitle,
                bookAuthor: item.bookAuthor,
                text: item.text,
                locationLabel: "",
                highlightedAt: item.capturedAt,
                note: nil,
                source: SourceApp(rawValue: item.sourceHint) ?? .other
            )
        }
        return try save(staged)
    }

    // MARK: - Editing

    func delete(_ highlight: Highlight) throws {
        let book = highlight.book
        context.delete(highlight)
        try context.save()
        // A shelf with nothing left on it is just clutter.
        if let book, book.highlights.isEmpty {
            context.delete(book)
            try context.save()
        }
    }

    func delete(_ book: Book) throws {
        context.delete(book)
        try context.save()
    }

    func toggleFavorite(_ highlight: Highlight) {
        highlight.isFavorite.toggle()
        try? context.save()
    }
}

struct ImportOutcome: Equatable, Sendable {
    var added: Int
    var duplicates: Int

    var summary: String {
        switch (added, duplicates) {
        case (0, 0): "Nothing to import."
        case (0, let dupes): "Already on your shelf — \(dupes) \(dupes == 1 ? "quote" : "quotes") skipped."
        case (let new, 0): "Saved \(new) \(new == 1 ? "quote" : "quotes")."
        case (let new, let dupes): "Saved \(new) new, skipped \(dupes) you already had."
        }
    }
}
