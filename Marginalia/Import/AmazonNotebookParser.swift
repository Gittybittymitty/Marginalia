import Foundation

/// Reads a saved copy of read.amazon.com/notebook — the page that shows every
/// highlight from a Kindle book in a browser.
///
/// Amazon's markup is not a documented format, so this matches the handful of
/// element ids and class names that page has used for years, and degrades to a
/// best effort rather than failing outright.
enum AmazonNotebookParser {
    static func looksLikeNotebook(_ html: String) -> Bool {
        html.contains("kp-notebook") || html.contains("kp-annotation")
    }

    static func parse(_ html: String, fileName: String) throws -> ImportBatch {
        let title = firstGroup(in: html, pattern: "<h3[^>]*class=\"[^\"]*kp-notebook-metadata[^\"]*\"[^>]*>([\\s\\S]*?)</h3>")
            .map(clean)
            ?? firstGroup(in: html, pattern: "<title>([\\s\\S]*?)</title>").map(clean)
            ?? "Kindle highlights"

        let author = firstGroup(in: html, pattern: "<p[^>]*class=\"[^\"]*kp-notebook-metadata[^\"]*\"[^>]*>([\\s\\S]*?)</p>")
            .map(clean)
            .map { $0.hasPrefix("By ") || $0.hasPrefix("by ") ? String($0.dropFirst(3)) : $0 }
            ?? ""

        // Each highlight and its note sit in the same container, in page order.
        let highlightTexts = groups(in: html, pattern: "id=\"highlight-[^\"]*\"[^>]*>([\\s\\S]*?)</span>")
        let fallbackTexts = groups(in: html, pattern: "class=\"[^\"]*kp-notebook-highlight[^\"]*\"[^>]*>([\\s\\S]*?)</div>")
        let texts = (highlightTexts.isEmpty ? fallbackTexts : highlightTexts).map(clean).filter { !$0.isEmpty }

        let notes = groups(in: html, pattern: "id=\"note-[^\"]*\"[^>]*>([\\s\\S]*?)</span>").map(clean)
        let locations = groups(in: html, pattern: "id=\"kp-annotation-location\"[^>]*value=\"([0-9]+)\"")

        guard !texts.isEmpty else { throw ImportError.nothingFound(fileName) }

        var staged: [StagedHighlight] = []
        for (index, text) in texts.enumerated() {
            let note = notes.indices.contains(index) ? notes[index] : ""
            let location = locations.indices.contains(index) ? locations[index] : ""
            staged.append(
                StagedHighlight(
                    bookTitle: title,
                    bookAuthor: author,
                    text: text,
                    locationLabel: location.isEmpty ? "" : "Location \(location)",
                    highlightedAt: nil,
                    note: note.isEmpty ? nil : note,
                    source: .kindle
                )
            )
        }

        var warnings: [String] = []
        if !notes.isEmpty && notes.count != texts.count {
            warnings.append("Amazon's page didn't pair every note with a passage, so check the notes after importing.")
        }
        return ImportBatch(source: .kindle, highlights: staged, warnings: warnings, originLabel: fileName)
    }

    private static func clean(_ value: String) -> String {
        AnnotFileParser.decodeEntities(
            value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        )
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstGroup(in text: String, pattern: String) -> String? {
        groups(in: text, pattern: pattern).first
    }

    private static func groups(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let group = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[group])
        }
    }
}
