import Foundation

/// Reads Kindle's `My Clippings.txt`, the file an e-reader writes to its own
/// storage every time you underline something.
///
/// Each record looks like this, separated by a row of equals signs:
///
///     Meditations (Marcus Aurelius)
///     - Your Highlight on page 42 | Location 412-413 | Added on Monday, 3 March 2025 10:12:33
///
///     You have power over your mind — not outside events.
///     ==========
///
/// Kindles localise that middle line, so the parser matches on shape and digits
/// rather than on the English words wherever it can.
enum MyClippingsParser {
    private static let separator = "=========="

    private static let noteMarkers = [
        "your note", "note", "notiz", "ihre notiz", "nota", "votre note", "uw notitie", "メモ"
    ]
    private static let bookmarkMarkers = [
        "your bookmark", "bookmark", "lesezeichen", "marcador", "signet", "ブックマーク"
    ]

    static func parse(_ raw: String, fallbackTitle: String = "Kindle highlights") -> ImportBatch {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))

        var staged: [StagedHighlight] = []
        var warnings: [String] = []
        var skippedBookmarks = 0
        var orphanNotes = 0

        for record in text.components(separatedBy: separator) {
            let lines = record.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let meaningful = lines.filter { !$0.isEmpty }
            guard meaningful.count >= 2 else { continue }

            let (title, author) = splitTitleAndAuthor(meaningful[0], fallback: fallbackTitle)
            let metaLine = meaningful[1]
            let body = meaningful.dropFirst(2).joined(separator: "\n")

            let lowered = metaLine.lowercased()
            let isBookmark = bookmarkMarkers.contains { lowered.contains($0) } && body.isEmpty
            if isBookmark {
                skippedBookmarks += 1
                continue
            }
            guard !body.isEmpty else { continue }

            let isNote = noteMarkers.contains { lowered.contains("- \($0)") || lowered.hasPrefix("- \($0)") }
                && !lowered.contains("highlight")

            if isNote {
                // Kindle writes a note as its own record, right after the passage
                // it belongs to. Attach it to that passage when we can.
                if let index = staged.lastIndex(where: { $0.bookTitle == title }) {
                    let existing = staged[index].note
                    staged[index].note = [existing, body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
                } else {
                    orphanNotes += 1
                }
                continue
            }

            staged.append(
                StagedHighlight(
                    bookTitle: title,
                    bookAuthor: author,
                    text: body,
                    locationLabel: locationLabel(from: metaLine),
                    highlightedAt: date(from: metaLine),
                    note: nil,
                    source: .kindle
                )
            )
        }

        if skippedBookmarks > 0 {
            warnings.append("Skipped \(skippedBookmarks) \(skippedBookmarks == 1 ? "bookmark" : "bookmarks") — they hold a position, not a passage.")
        }
        if orphanNotes > 0 {
            warnings.append("\(orphanNotes) \(orphanNotes == 1 ? "note" : "notes") had no highlight to attach to and were left out.")
        }

        return ImportBatch(source: .kindle, highlights: staged, warnings: warnings, originLabel: "My Clippings.txt")
    }

    /// `Meditations (Marcus Aurelius)` → title and author. Titles containing
    /// their own parentheses are common, so only a trailing group counts.
    static func splitTitleAndAuthor(_ line: String, fallback: String) -> (String, String) {
        var working = line.trimmingCharacters(in: .whitespacesAndNewlines)
        working = working.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        guard working.hasSuffix(")"), let open = working.lastIndex(of: "(") else {
            return (working.isEmpty ? fallback : working, "")
        }
        let author = String(working[working.index(after: open)..<working.index(before: working.endIndex)])
        let title = String(working[working.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        if title.isEmpty { return (working, "") }
        return (title, author.trimmingCharacters(in: .whitespaces))
    }

    static func locationLabel(from metaLine: String) -> String {
        var parts: [String] = []
        if let page = firstMatch(in: metaLine, pattern: "(?:page|seite|página|pagina)\\s+([0-9ivxlcIVXLC\\-]+)") {
            parts.append("Page \(page)")
        }
        if let location = firstMatch(in: metaLine, pattern: "(?:location|position|posición|emplacement)\\s+([0-9\\-]+)") {
            parts.append("Location \(location)")
        }
        return parts.joined(separator: " · ")
    }

    static func date(from metaLine: String) -> Date? {
        guard let range = metaLine.range(of: "|", options: .backwards) else { return nil }
        var tail = String(metaLine[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        for prefix in ["Added on ", "Hinzugefügt am ", "Añadido el ", "Ajouté le "] {
            if tail.hasPrefix(prefix) { tail = String(tail.dropFirst(prefix.count)) }
        }
        let formats = [
            "EEEE, d MMMM yyyy HH:mm:ss",
            "EEEE, MMMM d, yyyy h:mm:ss a",
            "EEEE, d MMMM yyyy h:mm:ss a",
            "EEEE d MMMM yyyy HH:mm:ss",
            "d MMMM yyyy HH:mm:ss",
            "MMMM d, yyyy h:mm:ss a"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: tail) { return date }
        }
        // Last resort: let the system try with the user's own locale.
        let loose = DateFormatter()
        loose.dateStyle = .full
        loose.timeStyle = .medium
        return loose.date(from: tail)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let group = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[group])
    }
}
