import SwiftUI
import SwiftData

/// Shows what a parser made of the file before anything is written.
///
/// Clippings files are messy — stray fragments, duplicated passages, the odd
/// bookmark — so nothing goes on the shelf until the reader has looked.
struct ImportPreviewView: View {
    @State private var batch: ImportBatch
    private let onFinish: (ImportOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(batch: ImportBatch, onFinish: @escaping (ImportOutcome) -> Void) {
        self._batch = State(initialValue: batch)
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summary
                }

                if !batch.warnings.isEmpty {
                    Section {
                        ForEach(batch.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ForEach(groupedByBook, id: \.title) { group in
                    Section {
                        ForEach(group.indices, id: \.self) { index in
                            StagedRow(item: $batch.highlights[index])
                        }
                    } header: {
                        HStack {
                            Text(group.title)
                            Spacer()
                            Button(allSelected(in: group.indices) ? "None" : "All") {
                                toggle(group.indices)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Review import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selectedCount == 0 ? "Save" : "Save \(selectedCount)") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedCount == 0 || isSaving)
                }
            }
            .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SourceBadge(source: batch.source)
                if !batch.originLabel.isEmpty {
                    Text(batch.originLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text("\(batch.highlights.count) \(batch.highlights.count == 1 ? "passage" : "passages") across \(batch.bookCount) \(batch.bookCount == 1 ? "book" : "books")")
                .font(.subheadline.weight(.medium))
            Text("Anything you already have is skipped automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var selectedCount: Int {
        batch.highlights.count(where: \.isSelected)
    }

    /// Indices rather than items, so the toggles write straight back into `batch`.
    private var groupedByBook: [(title: String, indices: [Int])] {
        var order: [String] = []
        var map: [String: [Int]] = [:]
        for (index, item) in batch.highlights.enumerated() {
            let key = item.bookAuthor.isEmpty ? item.bookTitle : "\(item.bookTitle) · \(item.bookAuthor)"
            if map[key] == nil {
                map[key] = []
                order.append(key)
            }
            map[key]?.append(index)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private func allSelected(in indices: [Int]) -> Bool {
        indices.allSatisfy { batch.highlights[$0].isSelected }
    }

    private func toggle(_ indices: [Int]) {
        let turnOff = allSelected(in: indices)
        for index in indices {
            batch.highlights[index].isSelected = !turnOff
        }
    }

    private func save() {
        isSaving = true
        let chosen = batch.highlights.filter(\.isSelected)
        do {
            let outcome = try HighlightStore(context: context).save(chosen)
            onFinish(outcome)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}

private struct StagedRow: View {
    @Binding var item: StagedHighlight

    var body: some View {
        Button {
            item.isSelected.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isSelected ? Color.accentColor : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.text)
                        .font(.system(.subheadline, design: .serif))
                        .lineSpacing(3)
                        .lineLimit(5)
                        .foregroundStyle(item.isSelected ? .primary : .secondary)
                    HStack(spacing: 8) {
                        if !item.locationLabel.isEmpty {
                            Text(item.locationLabel)
                        }
                        if let note = item.note, !note.isEmpty {
                            Label("note", systemImage: "square.and.pencil")
                        }
                        if let date = item.highlightedAt {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ImportPreviewView(
        batch: MyClippingsParser.parse("""
        Meditations (Marcus Aurelius)
        - Your Highlight on page 42 | Location 412-413 | Added on Monday, 3 March 2025 10:12:33

        You have power over your mind — not outside events.
        ==========
        """)
    ) { _ in }
    .modelContainer(SampleLibrary.previewContainer)
}
