import Foundation
import SwiftData

/// A small shelf so a fresh install isn't an empty screen, and so the
/// SwiftUI previews have something to draw.
enum SampleLibrary {
    struct Seed {
        var title: String
        var author: String
        var source: SourceApp
        var quotes: [(String, String, String)] // text, location, note summary
    }

    static let seeds: [Seed] = [
        Seed(
            title: "Meditations",
            author: "Marcus Aurelius",
            source: .kindle,
            quotes: [
                ("You have power over your mind — not outside events. Realize this, and you will find strength.",
                 "Location 412",
                 "The only reliable lever is attention."),
                ("Waste no more time arguing about what a good man should be. Be one.",
                 "Location 1180",
                 ""),
                ("The impediment to action advances action. What stands in the way becomes the way.",
                 "Location 903",
                 "Obstacles are information, not insults.")
            ]
        ),
        Seed(
            title: "Deep Work",
            author: "Cal Newport",
            source: .kobo,
            quotes: [
                ("Human beings, it seems, are at their best when immersed deeply in something challenging.",
                 "Page 86",
                 ""),
                ("Clarity about what matters provides clarity about what does not.",
                 "Page 59",
                 "A filter, not a to-do list.")
            ]
        ),
        Seed(
            title: "The Three-Body Problem",
            author: "Liu Cixin",
            source: .appleBooks,
            quotes: [
                ("In the long history of humankind, countless lucky coincidences had to occur for us to exist.",
                 "Chapter 12",
                 ""),
                ("Weakness and ignorance are not barriers to survival, but arrogance is.",
                 "Chapter 34",
                 "")
            ]
        ),
        Seed(
            title: "Thinking, Fast and Slow",
            author: "Daniel Kahneman",
            source: .googlePlayBooks,
            quotes: [
                ("Nothing in life is as important as you think it is while you are thinking about it.",
                 "Location 5021",
                 "Focusing illusion — the reason plans overpromise.")
            ]
        )
    ]

    @MainActor
    static func seedIfEmpty(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Book>())) ?? 0
        guard count == 0 else { return }

        let store = HighlightStore(context: context)
        var staged: [StagedHighlight] = []
        var daysAgo = 2

        for seed in seeds {
            for quote in seed.quotes {
                staged.append(
                    StagedHighlight(
                        bookTitle: seed.title,
                        bookAuthor: seed.author,
                        text: quote.0,
                        locationLabel: quote.1,
                        highlightedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now),
                        note: nil,
                        source: seed.source
                    )
                )
                daysAgo += 3
            }
        }

        _ = try? store.save(staged)

        // Give a couple of them the treatment a real reader would: a star and a note.
        if let highlights = try? context.fetch(FetchDescriptor<Highlight>()) {
            for highlight in highlights {
                guard let seed = seeds.first(where: { $0.title == highlight.book?.title }),
                      let match = seed.quotes.first(where: { $0.0 == highlight.text }),
                      !match.2.isEmpty
                else { continue }
                highlight.noteSummary = match.2
                highlight.isFavorite = true
            }
            try? context.save()
        }
    }

    /// In-memory container for previews.
    @MainActor
    static var previewContainer: ModelContainer = {
        let container = try! ModelContainer(
            for: Book.self, Highlight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        seedIfEmpty(container.mainContext)
        return container
    }()
}
