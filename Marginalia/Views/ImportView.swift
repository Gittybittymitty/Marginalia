import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Where every reading app gets connected.
///
/// It's worth being straight about why this screen exists rather than a single
/// "Connect Kindle" button: iOS gives no app access to another app's library,
/// and neither Amazon nor Rakuten offers a highlights API. What they do give you
/// is a file, or the share sheet — so this screen makes both of those one tap.
struct ImportView: View {
    @Binding var banner: Banner?

    @Environment(\.modelContext) private var context
    @State private var isPickingFile = false
    @State private var isPasting = false
    @State private var isAddingByHand = false
    @State private var pendingBatch: ImportBatch?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isPickingFile = true
                    } label: {
                        ActionRow(
                            symbol: "folder",
                            title: "Import a file",
                            detail: "My Clippings.txt · KoboReader.sqlite · .csv · .annot · .html · .json"
                        )
                    }
                    Button {
                        isPasting = true
                    } label: {
                        ActionRow(
                            symbol: "doc.on.clipboard",
                            title: "Paste text",
                            detail: "Apple Books, Play Books, or anything you've copied"
                        )
                    }
                    Button {
                        isAddingByHand = true
                    } label: {
                        ActionRow(
                            symbol: "pencil.and.scribble",
                            title: "Add by hand",
                            detail: "Paper books, library copies, lectures"
                        )
                    }
                } header: {
                    Text("Bring highlights in")
                }

                Section {
                    ShareSheetExplainer()
                } header: {
                    Text("From inside any reading app")
                }

                Section {
                    ForEach(SourceApp.importable) { source in
                        NavigationLink {
                            SourceGuideView(source: source) {
                                isPickingFile = true
                            } onPaste: {
                                isPasting = true
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: source.symbol)
                                    .font(.title3)
                                    .foregroundStyle(source.tint)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.displayName)
                                        .font(.body.weight(.medium))
                                    Text(source.importRecipe.headline)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("How to get your highlights out")
                } footer: {
                    Text("No app on iOS can read another app's library directly, and neither Amazon nor Kobo publishes a highlights API. Everything here uses a route they do support: an export file, or the share sheet.")
                }
            }
            .navigationTitle("Import")
            .fileImporter(
                isPresented: $isPickingFile,
                allowedContentTypes: allowedTypes,
                allowsMultipleSelection: false
            ) { result in
                handle(result)
            }
            .sheet(isPresented: $isPasting) {
                PasteImportView { batch in
                    pendingBatch = batch
                }
            }
            .sheet(isPresented: $isAddingByHand) {
                AddHighlightView { outcome in
                    banner = Banner(text: outcome.summary, isError: false)
                }
            }
            .sheet(item: $pendingBatch) { batch in
                ImportPreviewView(batch: batch) { outcome in
                    banner = Banner(text: outcome.summary, isError: false)
                }
            }
            .alert("Import failed", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var allowedTypes: [UTType] {
        var types: [UTType] = [.plainText, .commaSeparatedText, .json, .html, .text, .data]
        for extensionName in ["sqlite", "annot", "tsv", "md"] {
            if let type = UTType(filenameExtension: extensionName) {
                types.append(type)
            }
        }
        return types
    }

    private func handle(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                pendingBatch = try HighlightImporter.load(from: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

extension ImportBatch: Identifiable {
    var id: String { "\(originLabel)-\(highlights.count)-\(highlights.first?.id.uuidString ?? "")" }
}

private struct ActionRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct ShareSheetExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.bold))
                        .frame(width: 18, height: 18)
                        .background(Color.accentColor.opacity(0.18), in: Circle())
                    Text(step)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Works in Kindle, Apple Books, Play Books, Safari, Files — anything with a Share button.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private let steps = [
        "Select the passage you want to keep.",
        "Tap Share.",
        "Choose Save to Marginalia — it lands here next time you open the app."
    ]
}

/// The per-app instructions, written out so nobody has to go hunting for where
/// Kobo hides its database.
private struct SourceGuideView: View {
    let source: SourceApp
    var onPickFile: () -> Void
    var onPaste: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: source.symbol)
                        .font(.largeTitle)
                        .foregroundStyle(source.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.displayName)
                            .font(.title3.weight(.semibold))
                        Text(source.importRecipe.headline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Steps") {
                ForEach(Array(source.importRecipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption2.weight(.bold))
                            .frame(width: 18, height: 18)
                            .background(source.tint.opacity(0.18), in: Circle())
                        Text(LocalizedStringKey(step))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }

            if let hint = source.importRecipe.fileHint {
                Section("What to look for") {
                    Text(hint)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    dismiss()
                    onPickFile()
                } label: {
                    Label("Import a file", systemImage: "folder")
                }
                Button {
                    dismiss()
                    onPaste()
                } label: {
                    Label("Paste text instead", systemImage: "doc.on.clipboard")
                }
            }
        }
        .navigationTitle(source.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ImportView(banner: .constant(nil))
        .modelContainer(SampleLibrary.previewContainer)
}
