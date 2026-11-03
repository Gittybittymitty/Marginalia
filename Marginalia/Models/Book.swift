import Foundation
import SwiftData

@Model
final class Book {
    /// Stable key used to merge repeat imports of the same book.
    @Attribute(.unique) var identity: String
    var title: String
    var author: String
    var sourceRaw: String
    var addedAt: Date
    var lastImportedAt: Date
    var isPinned: Bool

    @Relationship(deleteRule: .cascade, inverse: \Highlight.book)
    var highlights: [Highlight] = []

    init(title: String, author: String, source: SourceApp, addedAt: Date = .now) {
        self.identity = Book.identity(title: title, author: author)
        self.title = title
        self.author = author
        self.sourceRaw = source.rawValue
        self.addedAt = addedAt
        self.lastImportedAt = addedAt
        self.isPinned = false
    }

    var source: SourceApp {
        get { SourceApp(rawValue: sourceRaw) ?? .other }
        set { sourceRaw = newValue.rawValue }
    }

    var displayAuthor: String {
        author.isEmpty ? "Unknown author" : author
    }

    var favoriteCount: Int {
        highlights.count(where: \.isFavorite)
    }

    var annotatedCount: Int {
        highlights.count(where: \.hasNote)
    }

    /// Case- and punctuation-insensitive so "Meditations" and "meditations."
    /// don't become two shelves.
    static func identity(title: String, author: String) -> String {
        let normalize = { (value: String) -> String in
            value.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        return "\(normalize(title))|\(normalize(author))"
    }
}
