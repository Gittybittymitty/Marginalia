import Foundation

/// A quote handed over by the share extension.
///
/// Deliberately a plain `Codable` struct rather than a SwiftData model: the
/// extension runs in its own process with a tight memory budget, so it writes a
/// small JSON file and gets out of the way.
struct InboxItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var text: String
    var bookTitle: String
    var bookAuthor: String
    var sourceHint: String
    var capturedAt: Date = .now
}

/// File-backed hand-off between the share extension and the app.
enum SharedInbox {
    static func write(_ item: InboxItem) throws {
        guard let inboxURL = AppGroup.inboxURL else {
            throw InboxError.noAppGroup
        }
        let data = try JSONEncoder().encode(item)
        let url = inboxURL.appendingPathComponent("\(item.id.uuidString).json")
        try data.write(to: url, options: .atomic)
    }

    /// Reads and removes everything waiting. Called when the app comes forward.
    static func drain() -> [InboxItem] {
        guard let inboxURL = AppGroup.inboxURL else { return [] }
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: inboxURL, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        var items: [InboxItem] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let item = try? decoder.decode(InboxItem.self, from: data) {
                items.append(item)
            }
            try? manager.removeItem(at: file)
        }
        return items.sorted { $0.capturedAt < $1.capturedAt }
    }

    enum InboxError: LocalizedError {
        case noAppGroup

        var errorDescription: String? {
            switch self {
            case .noAppGroup:
                "Marginalia's App Group isn't set up yet, so the quote couldn't be saved. Add the \(AppGroup.identifier) group to both targets in Signing & Capabilities."
            }
        }
    }
}
