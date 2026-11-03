import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// "Save to Marginalia" in the share sheet.
///
/// This is the one route that works from inside every reading app: Kindle,
/// Apple Books, Play Books, Safari, Files. The extension doesn't touch the
/// library itself — it drops a small JSON file in the App Group and the app
/// files it properly the next time it comes forward.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        Task { @MainActor in
            let capture = await readSharedItem()
            present(capture: capture)
        }
    }

    private func present(capture: Capture) {
        let composer = ShareComposer(
            capture: capture,
            onSave: { [weak self] item in
                do {
                    try SharedInbox.write(item)
                    self?.finish()
                } catch {
                    self?.fail(with: error)
                }
            },
            onCancel: { [weak self] in self?.finish() }
        )

        let host = UIHostingController(rootView: composer)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    /// Pulls the passage out of whatever the host app handed over. Apple Books
    /// sends text with its own attribution block; Safari sends a URL; most
    /// readers send plain text.
    private func readSharedItem() async -> Capture {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return Capture(text: "")
        }

        var text = ""
        var link: URL?

        for item in items {
            if let title = item.attributedContentText?.string, !title.isEmpty, text.isEmpty {
                text = title
            }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                       !value.isEmpty {
                        text = value
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let value = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                        link = value
                    }
                }
            }
        }

        return Capture(text: text, link: link)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func fail(with error: Error) {
        let alert = UIAlertController(
            title: "Couldn't save",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.finish() })
        present(alert, animated: true)
    }
}

struct Capture {
    var text: String
    var link: URL?
}

/// The sheet the reader sees: the quote, and which book to file it under.
struct ShareComposer: View {
    let capture: Capture
    let onSave: (InboxItem) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @State private var title: String
    @State private var author: String
    @State private var source: String

    init(capture: Capture, onSave: @escaping (InboxItem) -> Void, onCancel: @escaping () -> Void) {
        self.capture = capture
        self.onSave = onSave
        self.onCancel = onCancel

        let parsed = SharedTextReader.parse(capture.text, link: capture.link)
        _text = State(initialValue: parsed.quote)
        _title = State(initialValue: parsed.title)
        _author = State(initialValue: parsed.author)
        _source = State(initialValue: parsed.source)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("The passage") {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .serif))
                        .frame(minHeight: 120)
                }
                Section("Book") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                    TextField("Author", text: $author)
                        .textInputAutocapitalization(.words)
                }
                Section {
                    Text("Saved to Marginalia the next time you open it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Save to Marginalia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            InboxItem(
                                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                bookTitle: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                bookAuthor: author.trimmingCharacters(in: .whitespacesAndNewlines),
                                sourceHint: source
                            )
                        )
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

/// A trimmed-down version of the app's plain-text parser: enough to recognise
/// the two boilerplate shapes readers hit most often.
enum SharedTextReader {
    struct Parsed {
        var quote: String
        var title: String
        var author: String
        var source: String
    }

    static func parse(_ raw: String, link: URL?) -> Parsed {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Apple Books: quote, then "Excerpt From", title, author.
        if let range = text.range(of: "Excerpt From", options: .caseInsensitive) {
            let quote = stripQuotes(String(text[text.startIndex..<range.lowerBound]))
            let lines = String(text[range.upperBound...])
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.lowercased().contains("protected by copyright") }
            return Parsed(
                quote: quote,
                title: lines.first ?? "",
                author: lines.count > 1 ? lines[1] : "",
                source: "appleBooks"
            )
        }

        // Google Play Books: quote, then "Title by Author", then a store link.
        if text.contains("play.google.com/books") {
            var quoteLines: [String] = []
            var title = ""
            var author = ""
            for line in text.components(separatedBy: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
                if line.hasPrefix("http") { continue }
                if !quoteLines.isEmpty, let by = line.range(of: " by ", options: .backwards) {
                    title = String(line[line.startIndex..<by.lowerBound])
                    author = String(line[by.upperBound...])
                    continue
                }
                quoteLines.append(line)
            }
            return Parsed(
                quote: stripQuotes(quoteLines.joined(separator: "\n")),
                title: title,
                author: author,
                source: "googlePlayBooks"
            )
        }

        // A shared link: file it under the site it came from.
        if let link, text.isEmpty || text == link.absoluteString {
            return Parsed(
                quote: "",
                title: link.host ?? "Web",
                author: "",
                source: "web"
            )
        }

        return Parsed(
            quote: stripQuotes(text),
            title: link?.host ?? "",
            author: "",
            source: link == nil ? "other" : "web"
        )
    }

    private static func stripQuotes(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(Character, Character)] = [("\u{201C}", "\u{201D}"), ("\"", "\""), ("\u{2018}", "\u{2019}")]
        for (open, close) in pairs where trimmed.count > 2 && trimmed.first == open && trimmed.last == close {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return trimmed
    }
}
