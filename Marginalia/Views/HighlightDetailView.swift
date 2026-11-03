import SwiftUI
import SwiftData

/// One passage, full size, with the note underneath it.
///
/// This is the screen the whole app is for: read the quote back, then write
/// down what it actually means to you while it's still fresh.
struct HighlightDetailView: View {
    @Bindable var highlight: Highlight

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isEditingNote = false
    @State private var isEditingText = false
    @State private var showingDeleteConfirmation = false
    @State private var export: ExportFile?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                QuoteText(text: highlight.text, colorIndex: highlight.colorIndex)

                provenance
                markerPicker
                noteSection
                tagSection
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(highlight.book?.title ?? "Passage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    HighlightStore(context: context).toggleFavorite(highlight)
                } label: {
                    Label(
                        highlight.isFavorite ? "Starred" : "Star this",
                        systemImage: highlight.isFavorite ? "star.fill" : "star"
                    )
                }
                .tint(highlight.isFavorite ? .yellow : .accentColor)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        UIPasteboard.general.string = Exporter.shareText(for: highlight)
                    } label: {
                        Label("Copy quote", systemImage: "doc.on.doc")
                    }
                    Button {
                        shareQuote()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        isEditingText = true
                    } label: {
                        Label("Fix the text", systemImage: "character.cursor.ibeam")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete passage", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditingNote) {
            NoteEditorView(highlight: highlight)
        }
        .sheet(isPresented: $isEditingText) {
            QuoteTextEditorView(highlight: highlight)
        }
        .sheet(item: $export) { file in
            ShareSheet(items: [file.url])
        }
        .confirmationDialog("Delete this passage?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                try? HighlightStore(context: context).delete(highlight)
                dismiss()
            }
        } message: {
            Text("The note you wrote goes with it. This can't be undone.")
        }
    }

    private var provenance: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let book = highlight.book {
                Text(book.title)
                    .font(.headline)
                Text(book.displayAuthor)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                SourceBadge(source: highlight.source)
                if !highlight.locationLabel.isEmpty {
                    Text(highlight.locationLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(dateLine)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var dateLine: String {
        if let highlighted = highlight.highlightedAt {
            return "Highlighted \(highlighted.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Added \(highlight.importedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private var markerPicker: some View {
        HStack(spacing: 10) {
            ForEach(Marker.palette.indices, id: \.self) { index in
                Button {
                    highlight.colorIndex = index
                    try? context.save()
                } label: {
                    Circle()
                        .fill(Marker.color(index))
                        .frame(width: 26, height: 26)
                        .overlay {
                            Circle()
                                .strokeBorder(.primary.opacity(highlight.colorIndex == index ? 0.7 : 0.12), lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Marker.names[index]) marker")
            }
            Spacer()
        }
    }

    // MARK: - The note

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("My note", systemImage: "square.and.pencil")
                    .font(.headline)
                Spacer()
                Button(highlight.hasNote ? "Edit" : "Add note") {
                    isEditingNote = true
                }
                .font(.subheadline.weight(.medium))
            }

            if highlight.hasNote {
                VStack(alignment: .leading, spacing: 12) {
                    if !highlight.noteSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("In one line")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(highlight.noteSummary)
                                .font(.body.weight(.medium))
                        }
                    }
                    if !highlight.noteExplanation.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("What it means")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(highlight.noteExplanation)
                                .font(.body)
                                .lineSpacing(3)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Button {
                    isEditingNote = true
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Say what this passage actually means")
                            .font(.subheadline.weight(.medium))
                        Text("A one-line summary and a longer explanation. Writing it down is what makes a highlight worth keeping.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !highlight.tags.isEmpty {
                Label("Tags", systemImage: "tag")
                    .font(.headline)
                HStack(spacing: 6) {
                    ForEach(highlight.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
    }

    private func shareQuote() {
        if let url = try? Exporter.temporaryFile(
            named: "quote.txt",
            contents: Exporter.shareText(for: highlight)
        ) {
            export = ExportFile(url: url)
        }
    }
}

/// OCR and clippings files both produce the occasional broken line, so the text
/// itself has to be fixable.
struct QuoteTextEditorView: View {
    let highlight: Highlight
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var draft: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("The passage") {
                    TextEditor(text: $draft)
                        .font(.system(.body, design: .serif))
                        .frame(minHeight: 180)
                }
                Section {
                    Text("Tidying the text keeps the duplicate check working, so importing the same file again won't add it twice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Fix the text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        highlight.text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        highlight.refreshFingerprint()
                        try? context.save()
                        dismiss()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { draft = highlight.text }
        }
    }
}

#Preview {
    NavigationStack {
        HighlightDetailView(
            highlight: try! SampleLibrary.previewContainer.mainContext.fetch(FetchDescriptor<Highlight>()).first!
        )
    }
    .modelContainer(SampleLibrary.previewContainer)
}
