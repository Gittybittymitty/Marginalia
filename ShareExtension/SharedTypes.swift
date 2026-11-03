import Foundation

// These two types are deliberately duplicated from the app target.
//
// A share extension is a separate process with its own tight memory budget, and
// the app's copies pull in SwiftData and SwiftUI. Keeping a plain Codable
// mirror here means the extension links almost nothing. If you change the
// shape, change `Marginalia/Store/SharedInbox.swift` to match.

enum AppGroup {
    static let identifier = "group.com.marginalia.highlights"

    static var inboxURL: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            return nil
        }
        let inbox = container.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }
}

struct InboxItem: Codable {
    var id: UUID = UUID()
    var text: String
    var bookTitle: String
    var bookAuthor: String
    var sourceHint: String
    var capturedAt: Date = .now
}

enum SharedInbox {
    static func write(_ item: InboxItem) throws {
        guard let inboxURL = AppGroup.inboxURL else { throw InboxError.noAppGroup }
        let data = try JSONEncoder().encode(item)
        try data.write(to: inboxURL.appendingPathComponent("\(item.id.uuidString).json"), options: .atomic)
    }

    enum InboxError: LocalizedError {
        case noAppGroup

        var errorDescription: String? {
            "Marginalia's App Group isn't set up. Add \(AppGroup.identifier) to both targets in Signing & Capabilities."
        }
    }
}
