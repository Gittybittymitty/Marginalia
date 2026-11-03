import Foundation

/// Picks out the passages most worth re-reading.
///
/// There is no machine that knows which quote mattered to you, so this leans on
/// signals that correlate with it: you starred it, you bothered to write a note,
/// it is quotable length rather than a whole paragraph of plot, and it carries
/// the kind of language people underline.
enum QuoteRanker {
    private static let resonantTerms: Set<String> = [
        "always", "never", "must", "because", "truth", "life", "death", "love",
        "fear", "time", "mind", "self", "freedom", "power", "work", "habit",
        "choice", "attention", "meaning", "suffering", "courage", "beauty",
        "nothing", "everything", "only", "begins", "ends", "becomes", "matters"
    ]

    static func score(_ highlight: Highlight) -> Double {
        var score = 0.0

        if highlight.isFavorite { score += 50 }
        if !highlight.noteSummary.isEmpty { score += 18 }
        if !highlight.noteExplanation.isEmpty { score += 14 }
        score += Double(min(highlight.tags.count, 3)) * 4

        // Quotable length peaks around 25 words and falls off either side.
        let words = Double(highlight.wordCount)
        score += max(0, 22 - abs(words - 25) * 0.8)

        let lowercased = highlight.text.lowercased()
        let hits = resonantTerms.filter { lowercased.contains($0) }.count
        score += Double(min(hits, 5)) * 3.5

        // Aphorisms and rhetorical turns.
        if highlight.text.contains(";") || highlight.text.contains("—") { score += 4 }
        if highlight.text.contains("?") { score += 3 }

        // Fragments that were clearly cut mid-sentence read badly out of context.
        if let first = highlight.text.first, first.isLowercase { score -= 6 }
        if words < 5 { score -= 10 }
        if words > 90 { score -= 12 }

        return score
    }

    static func best(from highlights: [Highlight], limit: Int = 12) -> [Highlight] {
        highlights
            .map { (highlight: $0, score: score($0)) }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.highlight)
    }

    /// Stable for a whole day so the quote on the shelf doesn't shuffle on every redraw.
    static func quoteOfTheDay(from highlights: [Highlight], on date: Date = .now) -> Highlight? {
        let pool = highlights.isEmpty ? [] : best(from: highlights, limit: 30)
        guard !pool.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return pool[day % pool.count]
    }
}
