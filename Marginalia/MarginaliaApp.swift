import SwiftUI
import SwiftData

@main
struct MarginaliaApp: App {
    private let container: ModelContainer
    /// Set when the on-disk store couldn't be opened, so the UI can say so
    /// instead of silently losing the reader's library.
    private let storeFailure: String?

    init() {
        let schema = Schema([Book.self, Highlight.self])
        var failure: String?
        var resolved: ModelContainer?

        // The store lives in the App Group so the share extension writes to the
        // same place; without the entitlement we fall back to the app's own
        // container and the extension hands over through a file instead.
        let configuration: ModelConfiguration = {
            if let groupURL = AppGroup.containerURL {
                return ModelConfiguration(schema: schema, url: groupURL.appendingPathComponent("Marginalia.store"))
            }
            return ModelConfiguration(schema: schema)
        }()

        do {
            resolved = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            failure = error.localizedDescription
            resolved = try? ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        }

        guard let resolved else {
            fatalError("Marginalia could not create a data store at all: \(failure ?? "unknown error")")
        }
        container = resolved
        storeFailure = failure
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeFailure: storeFailure)
        }
        .modelContainer(container)
    }
}
