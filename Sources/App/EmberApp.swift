import SwiftUI

@main
struct EmberApp: App {
    private let dependencies: AppDependencies
    @State private var settings: SettingsStore
    @State private var bookmarks: BookmarkStore
    @State private var readStore: ReadStore
    @State private var linkOpener = LinkOpener()

    init() {
        let dependencies = AppDependencies.resolve()
        self.dependencies = dependencies
        _settings = State(initialValue: dependencies.settings)
        _bookmarks = State(initialValue: dependencies.bookmarks)
        _readStore = State(initialValue: dependencies.readStore)
    }

    var body: some Scene {
        WindowGroup {
            RootView(service: dependencies.service, cache: dependencies.cache)
                .environment(settings)
                .environment(bookmarks)
                .environment(readStore)
                .environment(linkOpener)
        }
    }
}
