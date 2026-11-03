import SwiftUI
import SwiftData

struct RootView: View {
    var storeFailure: String? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var banner: Banner?
    @State private var showingStoreWarning = false

    var body: some View {
        TabView {
            Tab("Shelf", systemImage: "books.vertical") {
                LibraryView(banner: $banner)
            }
            Tab("Quotes", systemImage: "quote.opening") {
                QuotesView()
            }
            Tab("Best", systemImage: "star") {
                BestQuotesView()
            }
            Tab("Import", systemImage: "square.and.arrow.down") {
                ImportView(banner: $banner)
            }
        }
        .task {
            SampleLibrary.seedIfEmpty(context)
            collectSharedQuotes()
        }
        .onChange(of: scenePhase) { _, phase in
            // Quotes sent over from other apps are waiting in the App Group.
            if phase == .active { collectSharedQuotes() }
        }
        .overlay(alignment: .top) {
            if let banner {
                BannerView(banner: banner)
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: banner)
        .onAppear { showingStoreWarning = storeFailure != nil }
        .alert("Your library couldn't be opened", isPresented: $showingStoreWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Marginalia is running on a temporary library, so nothing you add now will be kept.\n\n\(storeFailure ?? "")")
        }
    }

    private func collectSharedQuotes() {
        let items = SharedInbox.drain()
        guard !items.isEmpty else { return }
        do {
            let outcome = try HighlightStore(context: context).ingest(items)
            show(Banner(text: "From the share sheet — \(outcome.summary)", isError: false))
        } catch {
            show(Banner(text: error.localizedDescription, isError: true))
        }
    }

    private func show(_ banner: Banner) {
        self.banner = banner
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            if self.banner == banner { self.banner = nil }
        }
    }
}

struct Banner: Equatable {
    var text: String
    var isError: Bool
}

struct BannerView: View {
    let banner: Banner

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            Text(banner.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(banner.isError ? Color.red : Color.accentColor)
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 12, y: 4)
    }
}

#Preview {
    RootView()
        .modelContainer(SampleLibrary.previewContainer)
}
