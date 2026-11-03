import SwiftUI

/// Every reading app Marginalia knows how to pull highlights out of.
///
/// iOS sandboxing means no third-party app can reach into Kindle's or Kobo's
/// private storage, so each case documents the route that *does* work: a file
/// the app exports, or the system share sheet.
enum SourceApp: String, Codable, CaseIterable, Identifiable, Sendable {
    case kindle
    case kobo
    case appleBooks
    case googlePlayBooks
    case readwise
    case pdf
    case web
    case manual
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kindle: "Kindle"
        case .kobo: "Kobo"
        case .appleBooks: "Apple Books"
        case .googlePlayBooks: "Google Play Books"
        case .readwise: "Readwise"
        case .pdf: "PDF / Documents"
        case .web: "Web & Articles"
        case .manual: "Typed by hand"
        case .other: "Other app"
        }
    }

    var symbol: String {
        switch self {
        case .kindle: "book.closed.fill"
        case .kobo: "books.vertical.fill"
        case .appleBooks: "book.fill"
        case .googlePlayBooks: "play.rectangle.fill"
        case .readwise: "arrow.triangle.2.circlepath"
        case .pdf: "doc.richtext.fill"
        case .web: "globe"
        case .manual: "pencil.and.scribble"
        case .other: "square.and.arrow.down.fill"
        }
    }

    var tint: Color {
        switch self {
        case .kindle: Color(red: 0.07, green: 0.47, blue: 0.69)
        case .kobo: Color(red: 0.69, green: 0.18, blue: 0.21)
        case .appleBooks: Color(red: 0.95, green: 0.55, blue: 0.14)
        case .googlePlayBooks: Color(red: 0.17, green: 0.47, blue: 0.93)
        case .readwise: Color(red: 0.35, green: 0.35, blue: 0.85)
        case .pdf: Color(red: 0.55, green: 0.24, blue: 0.70)
        case .web: Color(red: 0.16, green: 0.60, blue: 0.47)
        case .manual: Color(red: 0.45, green: 0.45, blue: 0.50)
        case .other: Color(red: 0.40, green: 0.40, blue: 0.45)
        }
    }

    /// Shown on the Import screen so the reader knows exactly what to tap in the
    /// other app. These are the only routes iOS actually allows.
    var importRecipe: ImportRecipe {
        switch self {
        case .kindle:
            ImportRecipe(
                headline: "Two ways in",
                steps: [
                    "Plug your Kindle e-reader into a Mac or PC and copy `documents/My Clippings.txt` — drop it into Marginalia with Import a file.",
                    "Or open read.amazon.com/notebook in Safari, pick a book, tap Export, and share the emailed CSV to Marginalia.",
                    "Reading in the Kindle iOS app? Select text, tap Share, then Save to Marginalia."
                ],
                fileHint: "My Clippings.txt · Kindle notebook .csv or .html"
            )
        case .kobo:
            ImportRecipe(
                headline: "Copy one database file",
                steps: [
                    "Connect your Kobo by USB. In the hidden `.kobo` folder, copy `KoboReader.sqlite`.",
                    "Import it here — Marginalia reads the Bookmark table directly, notes included.",
                    "Side-loaded EPUBs instead store `.annot` files in `Digital Editions/Annotations`; those import too."
                ],
                fileHint: "KoboReader.sqlite · .annot"
            )
        case .appleBooks:
            ImportRecipe(
                headline: "Use the share sheet",
                steps: [
                    "In Apple Books, long-press a highlight and choose Share.",
                    "Pick Save to Marginalia. The book title and author come across automatically.",
                    "For a whole book, open Books on a Mac, select your notes, and share or paste them here."
                ],
                fileHint: "Shared text · pasted notes"
            )
        case .googlePlayBooks:
            ImportRecipe(
                headline: "Export notes to Drive",
                steps: [
                    "In Play Books, open a book's menu and tap Export notes — it lands in Google Drive.",
                    "Open the doc, copy everything, and use Paste text here.",
                    "Single quotes can also be sent straight over with Share."
                ],
                fileHint: "Pasted text · shared quote"
            )
        case .readwise:
            ImportRecipe(
                headline: "Bring your archive",
                steps: [
                    "In Readwise, go to Export → CSV and download the file.",
                    "Import it here; book, author, note and location all map over."
                ],
                fileHint: "readwise.csv"
            )
        case .pdf:
            ImportRecipe(
                headline: "From any document",
                steps: [
                    "Select text in Files, Preview, or any PDF reader and tap Share.",
                    "Choose Save to Marginalia and give it a book title."
                ],
                fileHint: "Shared text"
            )
        case .web:
            ImportRecipe(
                headline: "Articles and newsletters",
                steps: [
                    "Select a passage in Safari and tap Share → Save to Marginalia.",
                    "The page title becomes the source so you can find it later."
                ],
                fileHint: "Shared text · URL"
            )
        case .manual:
            ImportRecipe(
                headline: "Paper books count too",
                steps: [
                    "Tap Add by hand and type the passage.",
                    "Works for library books, borrowed copies, and lecture notes."
                ],
                fileHint: nil
            )
        case .other:
            ImportRecipe(
                headline: "Anything that can share text",
                steps: [
                    "Any reading app with a Share button works: select, share, Save to Marginalia.",
                    "Or export plain text, Markdown, CSV, or JSON and import the file."
                ],
                fileHint: ".txt · .md · .csv · .json"
            )
        }
    }

    /// Sources worth showing on the Import screen, in the order readers expect.
    static var importable: [SourceApp] {
        [.kindle, .kobo, .appleBooks, .googlePlayBooks, .readwise, .pdf, .web, .manual]
    }
}

struct ImportRecipe: Sendable {
    var headline: String
    var steps: [String]
    var fileHint: String?
}
