import Foundation

/// Works out what a dropped file actually is and hands it to the right parser.
///
/// Readers rename these files all the time, so the extension is only a hint:
/// the contents get the final say.
enum HighlightImporter {
    static func load(from url: URL) throws -> ImportBatch {
        let name = url.lastPathComponent
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let extensionName = url.pathExtension.lowercased()

        // Kobo's database is binary, so sniff it before trying to read text.
        if extensionName == "sqlite" || extensionName == "sqlite3" || extensionName == "db" || isSQLite(url) {
            return try KoboImporter.parse(fileAt: url)
        }

        guard let text = readText(at: url) else {
            throw ImportError.unreadableFile(name)
        }

        switch extensionName {
        case "annot":
            let batch = AnnotFileParser.parse(text, fileName: name)
            if batch.isEmpty { throw ImportError.nothingFound(name) }
            return batch
        case "csv", "tsv":
            return try DelimitedImporter.parse(text, fileName: name)
        case "json":
            return try BackupArchive.parse(text, fileName: name)
        case "html", "htm":
            return try AmazonNotebookParser.parse(text, fileName: name)
        default:
            break
        }

        // Fall back to shape detection.
        if text.contains("<annotationSet") || text.contains("<annotation") {
            return AnnotFileParser.parse(text, fileName: name)
        }
        if AmazonNotebookParser.looksLikeNotebook(text) {
            return try AmazonNotebookParser.parse(text, fileName: name)
        }
        if text.contains("==========") || name.localizedCaseInsensitiveContains("clipping") {
            let batch = MyClippingsParser.parse(text)
            if batch.isEmpty { throw ImportError.nothingFound(name) }
            return batch
        }
        if text.hasPrefix("{") || text.hasPrefix("[") {
            return try BackupArchive.parse(text, fileName: name)
        }

        let title = url.deletingPathExtension().lastPathComponent
        let batch = PlainTextParser.parse(text, defaultTitle: title, source: .pdf)
        if batch.isEmpty { throw ImportError.nothingFound(name) }
        return batch
    }

    private static func readText(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .isoLatin1, .windowsCP1252] {
            if let text = String(data: data, encoding: encoding), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private static func isSQLite(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 16) else { return false }
        return String(data: header, encoding: .ascii)?.hasPrefix("SQLite format 3") ?? false
    }
}

/// Marginalia's own export format, so a library can move between devices
/// without going back through Kindle or Kobo.
enum BackupArchive {
    struct Payload: Codable {
        struct Entry: Codable {
            var text: String
            var bookTitle: String
            var bookAuthor: String
            var location: String?
            var noteSummary: String?
            var noteExplanation: String?
            var tags: [String]?
            var source: String?
            var isFavorite: Bool?
            var highlightedAt: Date?
        }
        var version: Int = 1
        var exportedAt: Date = .now
        var highlights: [Entry]
    }

    static func parse(_ raw: String, fileName: String) throws -> ImportBatch {
        guard let data = raw.data(using: .utf8) else { throw ImportError.unreadableFile(fileName) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let entries: [Payload.Entry]
        if let payload = try? decoder.decode(Payload.self, from: data) {
            entries = payload.highlights
        } else if let bare = try? decoder.decode([Payload.Entry].self, from: data) {
            entries = bare
        } else {
            throw ImportError.unrecognizedFormat(fileName)
        }

        let staged = entries.compactMap { entry -> StagedHighlight? in
            let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let note = [entry.noteSummary, entry.noteExplanation]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            return StagedHighlight(
                bookTitle: entry.bookTitle.isEmpty ? "Imported quotes" : entry.bookTitle,
                bookAuthor: entry.bookAuthor,
                text: text,
                locationLabel: entry.location ?? "",
                highlightedAt: entry.highlightedAt,
                note: note.isEmpty ? nil : note,
                source: entry.source.flatMap(SourceApp.init(rawValue:)) ?? .other
            )
        }

        if staged.isEmpty { throw ImportError.nothingFound(fileName) }
        return ImportBatch(source: .other, highlights: staged, originLabel: fileName)
    }

    static func encode(_ highlights: [Highlight]) throws -> Data {
        let entries = highlights.map { highlight in
            Payload.Entry(
                text: highlight.text,
                bookTitle: highlight.book?.title ?? "",
                bookAuthor: highlight.book?.author ?? "",
                location: highlight.locationLabel,
                noteSummary: highlight.noteSummary,
                noteExplanation: highlight.noteExplanation,
                tags: highlight.tags,
                source: highlight.sourceRaw,
                isFavorite: highlight.isFavorite,
                highlightedAt: highlight.highlightedAt
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Payload(highlights: entries))
    }
}
