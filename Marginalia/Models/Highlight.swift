import Foundation
import SwiftData

@Model
final class Highlight {
    /// Hash of book + passage, so importing the same clippings file twice is a no-op.
    @Attribute(.unique) var fingerprint: String
    var text: String
    var locationLabel: String
    /// When the passage was highlighted in the original app, when that app tells us.
    var highlightedAt: Date?
    var importedAt: Date
    var isFavorite: Bool
    /// The reader's own one-line restatement of the passage.
    var noteSummary: String
    /// The longer "why this matters" note.
    var noteExplanation: String
    var tags: [String]
    var sourceRaw: String
    var colorIndex: Int

    var book: Book?

    init(
        text: String,
        locationLabel: String = "",
        highlightedAt: Date? = nil,
        source: SourceApp,
        book: Book? = nil,
        noteSummary: String = "",
        noteExplanation: String = "",
        tags: [String] = [],
        colorIndex: Int = 0
    ) {
        self.fingerprint = Highlight.fingerprint(text: text, bookIdentity: book?.identity ?? "")
        self.text = text
        self.locationLabel = locationLabel
        self.highlightedAt = highlightedAt
        self.importedAt = .now
        self.isFavorite = false
        self.noteSummary = noteSummary
        self.noteExplanation = noteExplanation
        self.tags = tags
        self.sourceRaw = source.rawValue
        self.colorIndex = colorIndex
        self.book = book
    }

    var source: SourceApp {
        get { SourceApp(rawValue: sourceRaw) ?? .other }
        set { sourceRaw = newValue.rawValue }
    }

    var hasNote: Bool {
        !noteSummary.isEmpty || !noteExplanation.isEmpty
    }

    var wordCount: Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    var dateForSorting: Date {
        highlightedAt ?? importedAt
    }

    /// One-line preview for dense lists.
    var condensed: String {
        text.replacingOccurrences(of: "\n", with: " ")
    }

    func refreshFingerprint() {
        fingerprint = Highlight.fingerprint(text: text, bookIdentity: book?.identity ?? "")
    }

    static func fingerprint(text: String, bookIdentity: String) -> String {
        let normalized = text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return "\(bookIdentity)#\(normalized.hashValue)#\(normalized.count)"
    }
}
