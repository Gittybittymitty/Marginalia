import Foundation
import SQLite3

/// Reads highlights straight out of `KoboReader.sqlite`, the database a Kobo
/// e-reader keeps in its hidden `.kobo` folder.
///
/// Kobo stores every underline in a `Bookmark` row: `Text` is the passage,
/// `Annotation` is the reader's own note, and `VolumeID` points at the book's
/// row in `content`.
enum KoboImporter {
    static func parse(fileAt url: URL) throws -> ImportBatch {
        // sqlite needs a plain file it can open by path, and wants to touch
        // sidecar journals, so work on a copy in our own temp directory.
        let scratch = URL.temporaryDirectory.appendingPathComponent("kobo-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: scratch) }
        do {
            try FileManager.default.copyItem(at: url, to: scratch)
        } catch {
            throw ImportError.unreadableFile(url.lastPathComponent)
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(scratch.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open the file"
            sqlite3_close(db)
            throw ImportError.databaseFailure(message)
        }
        defer { sqlite3_close(db) }

        var staged: [StagedHighlight] = []
        var warnings: [String] = []

        let joined = """
        SELECT b.Text, b.Annotation, b.DateCreated,
               COALESCE(c.BookTitle, c.Title, b.VolumeID),
               COALESCE(c.Attribution, '')
        FROM Bookmark b
        LEFT JOIN content c ON c.ContentID = b.VolumeID
        WHERE b.Text IS NOT NULL AND TRIM(b.Text) <> ''
        ORDER BY b.DateCreated
        """
        let bare = """
        SELECT Text, Annotation, DateCreated, VolumeID, ''
        FROM Bookmark
        WHERE Text IS NOT NULL AND TRIM(Text) <> ''
        ORDER BY DateCreated
        """

        var rows = try? run(query: joined, on: db)
        if rows == nil {
            // Older firmware and some backups ship without the content table.
            rows = try run(query: bare, on: db)
            warnings.append("This database has no book index, so titles are taken from the file names on the device.")
        }

        for row in rows ?? [] {
            let title = cleanTitle(row.bookTitle)
            staged.append(
                StagedHighlight(
                    bookTitle: title.isEmpty ? "Kobo highlights" : title,
                    bookAuthor: row.author,
                    text: row.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    locationLabel: "",
                    highlightedAt: parseKoboDate(row.dateCreated),
                    note: row.annotation.isEmpty ? nil : row.annotation,
                    source: .kobo
                )
            )
        }

        if staged.isEmpty {
            throw ImportError.nothingFound(url.lastPathComponent)
        }
        return ImportBatch(source: .kobo, highlights: staged, warnings: warnings, originLabel: url.lastPathComponent)
    }

    private struct Row {
        var text: String
        var annotation: String
        var dateCreated: String
        var bookTitle: String
        var author: String
    }

    private static func run(query: String, on db: OpaquePointer) throws -> [Row] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw ImportError.databaseFailure(message)
        }
        defer { sqlite3_finalize(statement) }

        var rows: [Row] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(
                Row(
                    text: column(statement, 0),
                    annotation: column(statement, 1),
                    dateCreated: column(statement, 2),
                    bookTitle: column(statement, 3),
                    author: column(statement, 4)
                )
            )
        }
        return rows
    }

    private static func column(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    /// `VolumeID` is often a file URL, so fall back to a readable file name.
    private static func cleanTitle(_ value: String) -> String {
        guard value.contains("/") || value.lowercased().hasSuffix(".epub") else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let name = URL(fileURLWithPath: value).deletingPathExtension().lastPathComponent
        return name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static func parseKoboDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

/// Side-loaded EPUBs on a Kobo keep their annotations as Adobe Digital Editions
/// `.annot` XML instead of going into the database.
enum AnnotFileParser {
    static func parse(_ xml: String, fileName: String) -> ImportBatch {
        let title = tag("dc:title", in: xml) ?? URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let author = tag("dc:creator", in: xml) ?? ""

        var staged: [StagedHighlight] = []
        for block in blocks(named: "annotation", in: xml) {
            guard let target = innerBlock(named: "target", in: block),
                  let text = tag("text", in: target)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { continue }
            let note = innerBlock(named: "content", in: block).flatMap { tag("text", in: $0) }
            staged.append(
                StagedHighlight(
                    bookTitle: title,
                    bookAuthor: author,
                    text: decodeEntities(text),
                    locationLabel: "",
                    highlightedAt: tag("dc:date", in: block).flatMap(KoboImporter.parseKoboDate),
                    note: note.map(decodeEntities),
                    source: .kobo
                )
            )
        }
        return ImportBatch(source: .kobo, highlights: staged, originLabel: fileName)
    }

    private static func blocks(named name: String, in xml: String) -> [String] {
        matches(in: xml, pattern: "<\(name)\\b[^>]*>([\\s\\S]*?)</\(name)>")
    }

    private static func innerBlock(named name: String, in xml: String) -> String? {
        blocks(named: name, in: xml).first
    }

    private static func tag(_ name: String, in xml: String) -> String? {
        matches(in: xml, pattern: "<\(name)\\b[^>]*>([\\s\\S]*?)</\(name)>").first
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let group = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[group])
        }
    }

    static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&rsquo;", with: "\u{2019}")
            .replacingOccurrences(of: "&lsquo;", with: "\u{2018}")
            .replacingOccurrences(of: "&rdquo;", with: "\u{201D}")
            .replacingOccurrences(of: "&ldquo;", with: "\u{201C}")
            .replacingOccurrences(of: "&mdash;", with: "\u{2014}")
    }
}
