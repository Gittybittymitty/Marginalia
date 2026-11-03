import SwiftUI
import SwiftData

/// The note editor — the reason to keep highlights at all.
///
/// Two fields rather than one free-text box, because they ask different
/// questions: the one-liner forces you to restate the idea in your own words,
/// and the longer field is where you argue with it.
struct NoteEditorView: View {
    let highlight: Highlight

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var summary = ""
    @State private var explanation = ""
    @State private var tagInput = ""
    @State private var tags: [String] = []
    @FocusState private var focus: Field?

    private enum Field { case summary, explanation, tags }

    /// Prompts to break a blank page. Tapping one drops it in as a heading you
    /// then answer, rather than generating anything on your behalf.
    private let prompts = [
        "The core idea is…",
        "This matters because…",
        "It connects to…",
        "I disagree because…",
        "I could use this when…",
        "In plain words:"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    QuoteText(
                        text: highlight.text,
                        colorIndex: highlight.colorIndex,
                        font: .system(.callout, design: .serif),
                        lineLimit: 6
                    )
                    if let book = highlight.book {
                        Text("\(book.title) · \(book.displayAuthor)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("Say it in one sentence", text: $summary, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($focus, equals: .summary)
                        .submitLabel(.next)
                } header: {
                    Text("Summary")
                } footer: {
                    Text("Restating it in your own words is the part that makes it stick. This line is what shows up in lists.")
                }

                Section {
                    TextEditor(text: $explanation)
                        .frame(minHeight: 150)
                        .focused($focus, equals: .explanation)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(prompts, id: \.self) { prompt in
                                Button(prompt) { insert(prompt) }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollClipDisabled()
                } header: {
                    Text("What it means")
                } footer: {
                    Text("The longer explanation: context, why you underlined it, what you'd do with it.")
                }

                Section {
                    HStack {
                        TextField("Add a tag", text: $tagInput)
                            .focused($focus, equals: .tags)
                            .submitLabel(.done)
                            .onSubmit(commitTag)
                        Button("Add", action: commitTag)
                            .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
                            .font(.subheadline)
                    }
                    if !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(tags, id: \.self) { tag in
                                    Button {
                                        tags.removeAll { $0 == tag }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(tag)
                                            Image(systemName: "xmark")
                                                .font(.caption2)
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.quaternary, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollClipDisabled()
                    }
                } header: {
                    Text("Tags")
                }
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                summary = highlight.noteSummary
                explanation = highlight.noteExplanation
                tags = highlight.tags
                if summary.isEmpty { focus = .summary }
            }
        }
    }

    private func insert(_ prompt: String) {
        if explanation.isEmpty {
            explanation = "\(prompt) "
        } else {
            if !explanation.hasSuffix("\n") { explanation += "\n\n" }
            explanation += "\(prompt) "
        }
        focus = .explanation
    }

    private func commitTag() {
        let candidate = tagInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard !candidate.isEmpty, !tags.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) else {
            tagInput = ""
            return
        }
        tags.append(candidate)
        tagInput = ""
    }

    private func save() {
        commitTag()
        highlight.noteSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        highlight.noteExplanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        highlight.tags = tags
        // A passage you bothered to explain is, almost by definition, one of the
        // good ones — so it joins the starred list unless you say otherwise.
        if highlight.hasNote && !highlight.isFavorite {
            highlight.isFavorite = true
        }
        try? context.save()
        dismiss()
    }
}

#Preview {
    NoteEditorView(
        highlight: try! SampleLibrary.previewContainer.mainContext.fetch(FetchDescriptor<Highlight>()).first!
    )
    .modelContainer(SampleLibrary.previewContainer)
}
