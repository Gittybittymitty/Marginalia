import Foundation

/// The one place the app group identifier is spelled out.
///
/// If you change the bundle identifier, change this to match the App Group you
/// create in Signing & Capabilities — otherwise the share extension has nowhere
/// to leave the quotes it collects.
enum AppGroup {
    static let identifier = "group.com.marginalia.highlights"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Where the share extension drops incoming quotes for the app to pick up.
    static var inboxURL: URL? {
        guard let containerURL else { return nil }
        let inbox = containerURL.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }
}
