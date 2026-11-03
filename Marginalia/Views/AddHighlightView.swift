import SwiftUI
import SwiftData

/// Typing a passage in by hand, for paper books and anything that can't export.
struct AddHighlightView: View {
    let onSaved: (ImportOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.lastImportedAt, order: .reverse) private var books: [Book]

    @State private var text = ""
    @State private var title = ""
    @State private var author = ""
    @State private var location = ""
    @State private var summary = ""
    @State private var source: SourceApp = .manual
    @FocusState private var textFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("The passage") {
                    TextEditor(text: $text)
                        .frame(minHeight: 130)
                        .font(.system(.body, design: .serif))
                        .focused($textFocused)
                }

                Section("Book") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                    TextField("Author", text: $author)
                        .textInputAutocapitalization(.words)
                    TextField("Page or location (optional)", text: $location)
                    Picker("Read in", selection: $source) {
                        ForEach(SourceApp.allCases) { option in
                            Label(option.displayName, systemImage: option.symbol).tag(option)
                        }
                    }
                }

                if !recentTitles.isEmpty && title.isEmpty {
                    Section("Recently added") {
                        ForEach(recentTitles, id: \.identity) { book in
                            Button {
                                title = book.title
                                author = book.author
                                source = book.source
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(book.title)
                                    Text(book.displayAuthor)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    TextField("Say it in one line", text: $summary, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Note")
                } footer: {
                    Text("Optional now — you can always add it later from the passage itself.")
                }
            }
            .navigationTitle("Add a quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear { textFocused = true }
        }
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var recentTitles: [Book] {
        Array(books.prefix(5))
    }

    private func save() {
        let staged = StagedHighlight(
            bookTitle: title.trimmingCharacters(in: .whitespacesAndNewlines),
            bookAuthor: author.trimmingCharacters(in: .whitespacesAndNewlines),
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            locationLabel: location.trimmingCharacters(in: .whitespacesAndNewlines),
            highlightedAt: .now,
            note: nil,
            source: source
        )
        let store = HighlightStore(context: context)
        do {
            let outcome = try store.save([staged])
            // Attach the one-liner to the passage we just created.
            let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSummary.isEmpty {
                let fingerprint = Highlight.fingerprint(
                    text: staged.text,
                    bookIdentity: Book.identity(title: staged.bookTitle, author: staged.bookAuthor)
                )
                var descriptor = FetchDescriptor<Highlight>(predicate: #Predicate { $0.fingerprint == fingerprint })
                descriptor.fetchLimit = 1
                if let highlight = try context.fetch(descriptor).first {
                    highlight.noteSummary = trimmedSummary
                    try context.save()
                }
            }
            onSaved(outcome)
            dismiss()
        } catch {
            // Nothing destructive happened; leave the sheet up so the text isn't lost.
        }
    }
}

#Preview {
    AddHighlightView { _ in }
        .modelContainer(SampleLibrary.previewContainer)
}
