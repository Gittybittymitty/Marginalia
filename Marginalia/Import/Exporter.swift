import Foundation

/// Getting highlights back out again, because a reading archive you can't
/// leave with isn't an archive.
enum Exporter {
    static func markdown(for book: Book) -> String {
        var lines = ["# \(book.title)", ""]
        if !book.author.isEmpty { lines.append("*\(book.author)*") }
        lines.append("Highlighted in \(book.source.displayName) · \(book.highlights.count) \(book.highlights.count == 1 ? "passage" : "passages")")
        lines.append("")

        for highlight in book.highlights.sorted(by: { $0.dateForSorting < $1.dateForSorting }) {
            lines.append(contentsOf: markdownBlock(for: highlight))
        }
        return lines.joined(separator: "\n")
    }

    static func markdown(for highlights: [Highlight], title: String) -> String {
        var lines = ["# \(title)", ""]
        let grouped = Dictionary(grouping: highlights) { $0.book?.title ?? "Unfiled" }
        for key in grouped.keys.sorted() {
            lines.append("## \(key)")
            lines.append("")
            for highlight in grouped[key]!.sorted(by: { $0.dateForSorting < $1.dateForSorting }) {
                lines.append(contentsOf: markdownBlock(for: highlight))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func markdownBlock(for highlight: Highlight) -> [String] {
        var lines: [String] = []
        let quote = highlight.text
            .components(separatedBy: "\n")
            .map { "> \($0)" }
            .joined(separator: "\n> \n")
        lines.append(quote)

        var meta: [String] = []
        if !highlight.locationLabel.isEmpty { meta.append(highlight.locationLabel) }
        if highlight.isFavorite { meta.append("starred") }
        if !highlight.tags.isEmpty { meta.append(highlight.tags.map { "#\($0)" }.joined(separator: " ")) }
        if !meta.isEmpty { lines.append("> \n> — \(meta.joined(separator: " · "))") }

        if !highlight.noteSummary.isEmpty {
            lines.append("")
            lines.append("**\(highlight.noteSummary)**")
        }
        if !highlight.noteExplanation.isEmpty {
            lines.append("")
            lines.append(highlight.noteExplanation)
        }
        lines.append("")
        return lines
    }

    static func csv(for highlights: [Highlight]) -> String {
        var rows = ["Highlight,Book Title,Book Author,Note,Location,Source,Starred,Highlighted at"]
        let formatter = ISO8601DateFormatter()
        for highlight in highlights {
            let note = [highlight.noteSummary, highlight.noteExplanation]
                .filter { !$0.isEmpty }
                .joined(separator: " — ")
            let fields = [
                highlight.text,
                highlight.book?.title ?? "",
                highlight.book?.author ?? "",
                note,
                highlight.locationLabel,
                highlight.source.displayName,
                highlight.isFavorite ? "yes" : "",
                highlight.highlightedAt.map { formatter.string(from: $0) } ?? ""
            ]
            rows.append(fields.map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    /// What goes on the clipboard when you share a single passage.
    static func shareText(for highlight: Highlight) -> String {
        var parts = ["\u{201C}\(highlight.text)\u{201D}"]
        var attribution: [String] = []
        if let book = highlight.book {
            attribution.append(book.title)
            if !book.author.isEmpty { attribution.append(book.author) }
        }
        if !highlight.locationLabel.isEmpty { attribution.append(highlight.locationLabel) }
        if !attribution.isEmpty { parts.append("— " + attribution.joined(separator: ", ")) }
        if !highlight.noteSummary.isEmpty { parts.append("\nMy note: \(highlight.noteSummary)") }
        return parts.joined(separator: "\n")
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// Writes an export into a temporary file so the share sheet can hand it on.
    static func temporaryFile(named name: String, contents: String) throws -> URL {
        let url = URL.temporaryDirectory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
