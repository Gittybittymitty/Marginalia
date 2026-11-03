# Marginalia

An iPhone app that collects the passages you underline in Kindle, Kobo, Apple
Books, Google Play Books and anything else you read on — and then asks you to
say what they actually mean.

Swift 5 / SwiftUI / SwiftData, iOS 18+, built and run with Xcode 26.

## Open it

```bash
open Marginalia.xcodeproj
```

Pick the **Marginalia** scheme and an iPhone simulator, then ⌘R.

## What it does

- **Shelf** — every book you've pulled highlights from, grouped by the app they
  came from, with one passage raised to the top of the screen each day.
- **Quotes** — all of them in one stream, searchable across passages, notes,
  tags, titles and authors, filterable by source and by whether you've written
  a note yet.
- **Best quotes** — the ones you starred, plus a *Suggested* list that ranks the
  rest by the signals that usually mark a keeper.
- **The note** — the point of the whole thing. One line to restate the passage
  in your own words, a longer field for what it means and why it matters, and
  tags. Writing a note stars the passage automatically.
- **Import** — files, pasted text, typing by hand, and a share extension.
- **Export** — Markdown, CSV and JSON, per book or for the whole library.

## About "integrating all the ebook apps"

It's worth being straight about this, because it shapes the whole design.

**No iPhone app can read another app's highlights directly.** iOS sandboxes
every app's storage, and neither Amazon nor Rakuten Kobo publishes a public
highlights API. Readwise, the best-known app in this category, works the same
way this one does. Anything that claims otherwise is either asking for your
Amazon password or scraping a web page on a server.

So Marginalia uses the routes those apps *do* support:

| Source | How highlights get in |
| --- | --- |
| Kindle (e-reader) | `documents/My Clippings.txt` over USB → **Import a file** |
| Kindle (notebook) | read.amazon.com/notebook → Export → the emailed `.csv`, or a saved `.html` |
| Kindle (iOS app) | select text → Share → **Save to Marginalia** |
| Kobo | `.kobo/KoboReader.sqlite` over USB — read straight out of the `Bookmark` table, notes included |
| Kobo (side-loaded) | `.annot` files in `Digital Editions/Annotations` |
| Apple Books | long-press a highlight → Share → **Save to Marginalia**, or paste your notes |
| Google Play Books | Export notes to Drive → paste, or Share a single quote |
| Readwise | Export → CSV |
| PDFs, Safari, anything | select → Share → **Save to Marginalia** |
| Paper books | **Add by hand** |

Every importer deduplicates, so re-importing the same clippings file is a no-op.

## Before you run it on a real phone

Two things need your own Apple developer account:

1. **Signing.** Select the project → both targets → Signing & Capabilities →
   set your Team. Change `PRODUCT_BUNDLE_IDENTIFIER` from
   `com.marginalia.highlights` to something of yours if that one is taken.
2. **The App Group.** The share extension hands quotes to the app through an
   App Group container. Add the *App Groups* capability to **both** targets and
   create a group, then change `AppGroup.identifier` in
   `Marginalia/Store/AppGroup.swift` and the two files in `Config/` to match.
   Without it the app still works; only the share sheet route goes quiet, and
   it tells you so rather than failing silently.

## Layout

```
Marginalia/
  Marginalia/
    MarginaliaApp.swift        the app entry point and the SwiftData container
    Models/                    Book, Highlight, SourceApp, QuoteRanker
    Store/                     writes, the App Group, the share-sheet inbox, sample data
    Import/                    one file per format, plus the dispatcher and exporter
    Views/                     the four tabs and the screens under them
  ShareExtension/              "Save to Marginalia" in the iOS share sheet
  Config/                      Info.plist and entitlements for the extension
  Fixtures/                    a real My Clippings.txt and KoboReader.sqlite to test against
```

`HighlightImporter.load(from:)` is the single door every file goes through. It
sniffs the contents rather than trusting the extension, because people rename
these files constantly.

## Testing the parsers

The parsers are plain Foundation code with no UI, so they compile and run on the
Mac directly against the files in `Fixtures/`:

```bash
swiftc -target arm64-apple-macos14.0 Marginalia/Models/SourceApp.swift Marginalia/Models/Book.swift Marginalia/Models/Highlight.swift Marginalia/Import/*.swift main.swift -o parsertest && ./parsertest Fixtures
```

(Write a `main.swift` that calls `HighlightImporter.load(from:)` on each fixture;
this is how the Kindle, Kobo, CSV, `.annot` and share-text paths were checked.)

## Known limits

- Amazon's notebook HTML is scraped with regular expressions against class names
  Amazon can change at any time. The CSV export is the stable route.
- `My Clippings.txt` is localised by Kindle. The parser matches on shape and
  digits where it can and handles English, German, Spanish and French markers;
  other languages will import the passages but may miss page numbers or dates.
- There is no sync between devices. Export to JSON and import on the other one.
