import SwiftUI
import SwiftData

/// One passage in a list. Compact, but it still shows the marker colour, the
/// star, and whether there's a note waiting underneath.
struct HighlightRow: View {
    let highlight: Highlight
    var showsBook = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(Marker.color(highlight.colorIndex))
                .frame(width: 4)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(highlight.condensed)
                    .font(.system(.subheadline, design: .serif))
                    .lineSpacing(3)
                    .lineLimit(4)

                if !highlight.noteSummary.isEmpty {
                    Text(highlight.noteSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Provenance(highlight: highlight, showsBook: showsBook)
                    if highlight.hasNote {
                        Image(systemName: "square.and.pencil")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(highlight.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }

            if highlight.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Swipe actions shared by every list of passages.
struct HighlightRowActions: ViewModifier {
    let highlight: Highlight
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    HighlightStore(context: context).toggleFavorite(highlight)
                } label: {
                    Label(
                        highlight.isFavorite ? "Unstar" : "Star",
                        systemImage: highlight.isFavorite ? "star.slash" : "star"
                    )
                }
                .tint(.yellow)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    try? HighlightStore(context: context).delete(highlight)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}

extension View {
    func highlightRowActions(for highlight: Highlight) -> some View {
        modifier(HighlightRowActions(highlight: highlight))
    }
}
