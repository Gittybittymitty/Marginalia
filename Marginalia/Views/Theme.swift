import SwiftUI

/// The marker colours. They sit behind the text the way a real highlighter
/// does, so they are kept pale enough for body copy to stay legible in both
/// light and dark appearance.
enum Marker {
    static let palette: [Color] = [
        Color(red: 0.98, green: 0.85, blue: 0.35),
        Color(red: 0.55, green: 0.84, blue: 0.62),
        Color(red: 0.55, green: 0.76, blue: 0.96),
        Color(red: 0.96, green: 0.63, blue: 0.68),
        Color(red: 0.78, green: 0.70, blue: 0.95)
    ]

    static func color(_ index: Int) -> Color {
        palette[((index % palette.count) + palette.count) % palette.count]
    }

    static let names = ["Yellow", "Green", "Blue", "Pink", "Violet"]
}

/// A passage drawn the way it looked in the book: serif, generous leading, and
/// a wash of marker behind it.
struct QuoteText: View {
    let text: String
    var colorIndex: Int = 0
    var font: Font = .system(.title3, design: .serif)
    var lineLimit: Int? = nil

    var body: some View {
        Text(text)
            .font(font)
            .lineSpacing(5)
            .lineLimit(lineLimit)
            .foregroundStyle(.primary)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Marker.color(colorIndex).opacity(0.28),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}

/// The small grey line under a quote: where it came from, where in the book.
struct Provenance: View {
    let highlight: Highlight
    var showsBook = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: highlight.source.symbol)
                .font(.caption2)
                .foregroundStyle(highlight.source.tint)
            if showsBook, let book = highlight.book {
                Text(book.title)
                    .fontWeight(.medium)
                if !book.author.isEmpty {
                    Text("·")
                    Text(book.author)
                }
            }
            if !highlight.locationLabel.isEmpty {
                Text("·")
                Text(highlight.locationLabel)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

struct SourceBadge: View {
    let source: SourceApp

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: source.symbol)
            Text(source.displayName)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(source.tint.opacity(0.16), in: Capsule())
        .foregroundStyle(source.tint)
    }
}

struct EmptyShelf: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
