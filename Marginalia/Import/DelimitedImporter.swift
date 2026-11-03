import Foundation

/// Reads the spreadsheet exports: Amazon's "Export notebook" CSV, Readwise's
/// CSV archive, and anything else with a column of quotes in it.
enum DelimitedImporter {
    static func parse(_ raw: String, fileName: String) throws -> ImportBatch {
        let rows = CSVReader.rows(from: raw)
        guard !rows.isEmpty else { throw ImportError.nothingFound(fileName) }

        if let batch = parseKindleNotebook(rows: rows, fileName: fileName) {
            return batch
        }
        return try parseGeneric(rows: rows, fileName: fileName)
    }

    // MARK: - Amazon Kindle notebook export

    /// Amazon's CSV opens with a short preamble — the book title, the author on
    /// a `by …` line — and only then a real header row.
    private static func parseKindleNotebook(rows: [[String]], fileName: String) -> ImportBatch? {
        guard let headerIndex = rows.firstIndex(where: { row in
            row.contains { $0.caseInsensitiveCompare("Annotation Type") == .orderedSame }
        }) else { return nil }

        let header = rows[headerIndex].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let typeColumn = header.firstIndex(of: "annotation type") ?? 0
        let locationColumn = header.firstIndex(of: "location")
        let starredColumn = header.firstIndex(of: "starred?")
        let bodyColumn = header.firstIndex(of: "annotation") ?? header.count - 1

        var title = "Kindle highlights"
        var author = ""
        for row in rows.prefix(headerIndex) {
            guard let first = row.first?.trimmingCharacters(in: .whitespaces), !first.isEmpty else { continue }
            if first.lowercased().hasPrefix("your kindle notes for") { continue }
            if first.lowercased().hasPrefix("by ") {
                author = String(first.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if first.lowercased().hasPrefix("free kindle") {
                continue
            } else if first.range(of: "highlight(s)", options: .caseInsensitive) != nil {
                continue
            } else if title == "Kindle highlights" {
                title = first
            }
        }

        var staged: [StagedHighlight] = []
        for row in rows.dropFirst(headerIndex + 1).map({ fold($0, into: header.count) }) {
            guard row.count > bodyColumn else { continue }
            let body = row[bodyColumn].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            let kind = row.indices.contains(typeColumn) ? row[typeColumn].lowercased() : ""

            if kind.contains("note") && !kind.contains("highlight") {
                // Amazon writes a note as its own row, right after its passage.
                if let index = staged.indices.last {
                    staged[index].note = body
                }
                continue
            }
            if kind.contains("bookmark") { continue }

            let location = locationColumn.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? ""
            var item = StagedHighlight(
                bookTitle: title,
                bookAuthor: author,
                text: body,
                locationLabel: location.isEmpty ? "" : "Location \(location)",
                highlightedAt: nil,
                note: nil,
                source: .kindle
            )
            if let starredColumn, row.indices.contains(starredColumn),
               !row[starredColumn].trimmingCharacters(in: .whitespaces).isEmpty {
                item.markFavorite = true
            }
            staged.append(item)
        }

        guard !staged.isEmpty else { return nil }
        return ImportBatch(source: .kindle, highlights: staged, originLabel: fileName)
    }

    // MARK: - Readwise and friends

    private static let textAliases = ["highlight", "text", "quote", "annotation", "passage", "content", "highlighted text"]
    private static let titleAliases = ["book title", "title", "book", "document", "source", "book name"]
    private static let authorAliases = ["book author", "author", "creator", "writer", "authors"]
    private static let noteAliases = ["note", "notes", "comment", "annotation note", "my note"]
    private static let locationAliases = ["location", "page", "position", "page number", "location number"]
    private static let dateAliases = ["highlighted at", "date", "added on", "created", "timestamp", "date added"]

    private static func parseGeneric(rows: [[String]], fileName: String) throws -> ImportBatch {
        guard let headerIndex = rows.firstIndex(where: { row in
            row.contains { textAliases.contains($0.lowercased().trimmingCharacters(in: .whitespaces)) }
        }) else {
            throw ImportError.unrecognizedFormat(fileName)
        }

        let header = rows[headerIndex].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func column(_ aliases: [String]) -> Int? {
            for alias in aliases {
                if let index = header.firstIndex(of: alias) { return index }
            }
            return nil
        }

        guard let textColumn = column(textAliases) else {
            throw ImportError.unrecognizedFormat(fileName)
        }
        let titleColumn = column(titleAliases)
        let authorColumn = column(authorAliases)
        let noteColumn = column(noteAliases)
        let locationColumn = column(locationAliases)
        let dateColumn = column(dateAliases)

        let isReadwise = header.contains("book title") && header.contains("highlight")
        let source: SourceApp = isReadwise ? .readwise : .other

        var staged: [StagedHighlight] = []
        var warnings: [String] = []

        for row in rows.dropFirst(headerIndex + 1).map({ fold($0, into: header.count) }) {
            func value(_ index: Int?) -> String {
                guard let index, row.indices.contains(index) else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let body = value(textColumn)
            guard !body.isEmpty else { continue }
            let note = value(noteColumn)
            let location = value(locationColumn)
            let title = value(titleColumn)

            staged.append(
                StagedHighlight(
                    bookTitle: title.isEmpty ? URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent : title,
                    bookAuthor: value(authorColumn),
                    text: body,
                    locationLabel: location.isEmpty ? "" : (Int(location) != nil ? "Location \(location)" : location),
                    highlightedAt: ISO8601DateFormatter().date(from: value(dateColumn)),
                    note: note.isEmpty ? nil : note,
                    source: source
                )
            )
        }

        if staged.isEmpty { throw ImportError.nothingFound(fileName) }
        if titleColumn == nil {
            warnings.append("No book column in this file, so everything went onto one shelf named after the file.")
        }
        return ImportBatch(source: source, highlights: staged, warnings: warnings, originLabel: fileName)
    }
}

/// An unquoted comma inside a note splits it across columns. The header says
/// how many there should be, so anything past that belongs to the last one.
private func fold(_ row: [String], into width: Int) -> [String] {
    guard width > 0, row.count > width else { return row }
    var folded = Array(row.prefix(width - 1))
    folded.append(row.dropFirst(width - 1).joined(separator: ","))
    return folded
}

/// A small RFC 4180 reader — quoted fields, escaped quotes, newlines inside
/// cells. Kindle and Readwise exports all contain quotes with commas in them,
/// so splitting on commas is not an option.
enum CSVReader {
    static func rows(from raw: String) -> [[String]] {
        let delimiter: Character = detectDelimiter(in: raw)
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var insideQuotes = false
        var iterator = raw.replacingOccurrences(of: "\r\n", with: "\n").makeIterator()
        var pending: Character?

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty) {
                rows.append(row)
            }
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            if insideQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            insideQuotes = false
                            pending = next
                        }
                    } else {
                        insideQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"": insideQuotes = true
                case delimiter: endField()
                case "\n", "\r": endRow()
                default: field.append(character)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    private static func detectDelimiter(in raw: String) -> Character {
        let sample = raw.prefix(4000)
        let tabs = sample.count(where: { $0 == "\t" })
        let commas = sample.count(where: { $0 == "," })
        let semicolons = sample.count(where: { $0 == ";" })
        if tabs > commas && tabs > semicolons { return "\t" }
        if semicolons > commas { return ";" }
        return ","
    }
}
