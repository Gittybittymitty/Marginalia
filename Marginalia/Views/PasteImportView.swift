import SwiftUI

/// Paste in whatever you copied. The parser works out which app it came from.
struct PasteImportView: View {
    let onParsed: (ImportBatch) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var title = ""
    @State private var author = ""
    @State private var detected: SourceApp?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .font(.system(.callout, design: .serif))
                        .onChange(of: text) { _, _ in detect() }
                    if text.isEmpty {
                        Button {
                            text = UIPasteboard.general.string ?? ""
                            detect()
                        } label: {
                            Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                        }
                    }
                } header: {
                    Text("Paste your highlights")
                } footer: {
                    if let detected {
                        Label("Looks like \(detected.displayName)", systemImage: detected.symbol)
                            .font(.caption)
                            .foregroundStyle(detected.tint)
                    } else {
                        Text("Apple Books and Play Books include the book details when you share. For plain text, blank lines separate one passage from the next.")
                    }
                }

                if detected == nil || detected == .other || detected == .pdf {
                    Section("Which book?") {
                        TextField("Title", text: $title)
                        TextField("Author", text: $author)
                    }
                }
            }
            .navigationTitle("Paste text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", action: parse)
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func detect() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 20 else {
            detected = nil
            return
        }
        detected = PlainTextParser.parse(trimmed).source
    }

    private func parse() {
        var batch = PlainTextParser.parse(
            text,
            defaultTitle: title.trimmingCharacters(in: .whitespacesAndNewlines),
            source: detected ?? .other
        )
        // A title typed here wins over whatever the parser guessed.
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for index in batch.highlights.indices {
                batch.highlights[index].bookTitle = title
                if !author.isEmpty { batch.highlights[index].bookAuthor = author }
            }
        }
        guard !batch.isEmpty else { return }
        onParsed(batch)
        dismiss()
    }
}

#Preview {
    PasteImportView { _ in }
}
