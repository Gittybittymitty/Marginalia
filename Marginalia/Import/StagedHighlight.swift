import Foundation

/// A passage that has been parsed but not yet saved, so the reader can look it
/// over and untick anything they don't want on the shelf.
struct StagedHighlight: Identifiable, Hashable {
    var id = UUID()
    var bookTitle: String
    var bookAuthor: String
    var text: String
    var locationLabel: String
    var highlightedAt: Date?
    var note: String?
    var source: SourceApp
    /// Some exports carry the reader's own "this one matters" flag — Amazon's
    /// starred column, for one. That is exactly what this app's star means.
    var markFavorite: Bool = false
    var isSelected: Bool = true
}

/// The result of reading one file or one pasteboard, plus anything the parser
/// wants to warn about.
struct ImportBatch {
    var source: SourceApp
    var highlights: [StagedHighlight]
    var warnings: [String] = []
    var originLabel: String = ""

    var isEmpty: Bool { highlights.isEmpty }

    var bookCount: Int {
        Set(highlights.map { Book.identity(title: $0.bookTitle, author: $0.bookAuthor) }).count
    }
}

enum ImportError: LocalizedError {
    case unreadableFile(String)
    case unrecognizedFormat(String)
    case nothingFound(String)
    case databaseFailure(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let name):
            "Couldn't open \(name). If it came off an e-reader, copy it to Files first and try again."
        case .unrecognizedFormat(let name):
            "\(name) isn't a format Marginalia recognises. It reads My Clippings.txt, KoboReader.sqlite, .annot, .csv, .json, .html and plain text."
        case .nothingFound(let name):
            "No highlights in \(name) — the file parsed, but there was nothing underlined in it."
        case .databaseFailure(let detail):
            "Couldn't read the Kobo database: \(detail)"
        }
    }
}
