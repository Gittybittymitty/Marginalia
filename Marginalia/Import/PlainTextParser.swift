import Foundation

/// The catch-all: whatever lands on the clipboard or comes through the share
/// sheet. Apple Books and Google Play Books both wrap a quote in their own
/// boilerplate, and this strips it back down to the passage plus its book.
enum PlainTextParser {
    private static let boilerplate = [
        "this material may be protected by copyright",
        "excerpt from",
        "all rights reserved"
    ]

    static func parse(_ raw: String, defaultTitle: String = "", source: SourceApp = .other) -> ImportBatch {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ImportBatch(source: source, highlights: []) }

        if text.range(of: "Excerpt From", options: .caseInsensitive) != nil {
            return parseAppleBooks(text)
        }
        if text.contains("play.google.com/books") {
            return parsePlayBooks(text)
        }
        if MyClippingsParser.parse(text).highlights.count > 1 || text.contains("==========") {
            return MyClippingsParser.parse(text)
        }
        return parseLoose(text, defaultTitle: defaultTitle, source: source)
    }

    /// Apple Books shares a quote followed by `Excerpt From`, the title, and the author.
    private static func parseAppleBooks(_ text: String) -> ImportBatch {
        var staged: [StagedHighlight] = []
        let chunks = text.components(separatedBy: "Excerpt From")

        // The quote precedes the marker, the attribution follows it.
        for index in 0..<max(chunks.count - 1, 0) {
            let quote = stripQuotes(dropBoilerplate(chunks[index]))
            let attributionLines = chunks[index + 1]
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { line in
                    !line.isEmpty && !boilerplate.contains { line.lowercased().contains($0) }
                }
            guard !quote.isEmpty else { continue }
            let title = attributionLines.first ?? "Apple Books"
            let author = attributionLines.count > 1 ? attributionLines[1] : ""
            staged.append(
                StagedHighlight(
                    bookTitle: title,
                    bookAuthor: author,
                    text: quote,
                    locationLabel: "",
                    highlightedAt: .now,
                    note: nil,
                    source: .appleBooks
                )
            )
        }

        if staged.isEmpty {
            return parseLoose(text, defaultTitle: "Apple Books", source: .appleBooks)
        }
        return ImportBatch(source: .appleBooks, highlights: staged, originLabel: "Apple Books")
    }

    /// Play Books shares `“quote”` then `Title by Author` then a store link.
    private static func parsePlayBooks(_ text: String) -> ImportBatch {
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var quoteLines: [String] = []
        var title = "Google Play Books"
        var author = ""

        for line in lines {
            if line.hasPrefix("http") { continue }
            if let range = line.range(of: " by ", options: .backwards), quoteLines.isEmpty == false {
                title = String(line[line.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                author = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                continue
            }
            quoteLines.append(line)
        }

        let quote = stripQuotes(quoteLines.joined(separator: "\n"))
        guard !quote.isEmpty else { return ImportBatch(source: .googlePlayBooks, highlights: []) }
        return ImportBatch(
            source: .googlePlayBooks,
            highlights: [
                StagedHighlight(
                    bookTitle: title,
                    bookAuthor: author,
                    text: quote,
                    locationLabel: "",
                    highlightedAt: .now,
                    note: nil,
                    source: .googlePlayBooks
                )
            ],
            originLabel: "Google Play Books"
        )
    }

    /// Anything else: blank lines separate passages, one quote per paragraph.
    private static func parseLoose(_ text: String, defaultTitle: String, source: SourceApp) -> ImportBatch {
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { dropBoilerplate($0) }
            .map { stripQuotes($0) }
            .filter { $0.count > 2 }

        let title = defaultTitle.isEmpty ? "Unfiled quotes" : defaultTitle
        let staged = paragraphs.map { paragraph in
            StagedHighlight(
                bookTitle: title,
                bookAuthor: "",
                text: paragraph,
                locationLabel: "",
                highlightedAt: .now,
                note: nil,
                source: source
            )
        }
        var warnings: [String] = []
        if staged.count > 1 {
            warnings.append("Split into \(staged.count) passages on the blank lines. Untick anything that shouldn't be its own quote.")
        }
        return ImportBatch(source: source, highlights: staged, warnings: warnings, originLabel: title)
    }

    private static func dropBoilerplate(_ value: String) -> String {
        value.components(separatedBy: "\n")
            .filter { line in
                let lowered = line.lowercased().trimmingCharacters(in: .whitespaces)
                return !boilerplate.contains { lowered.contains($0) }
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sharing a quote almost always wraps it in smart quotes.
    static func stripQuotes(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(Character, Character)] = [("\u{201C}", "\u{201D}"), ("\"", "\""), ("\u{2018}", "\u{2019}"), ("'", "'")]
        for (open, close) in pairs {
            if trimmed.count > 2, trimmed.first == open, trimmed.last == close {
                trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return trimmed
    }
}
