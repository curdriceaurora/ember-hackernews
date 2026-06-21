import Foundation

/// Immutable dependency graph resolved once when the app process starts.
struct AppDependencies {
    let service: any HNServicing
    let settings: SettingsStore
    let bookmarks: BookmarkStore
    let readStore: ReadStore
    let cache: DiskCache

    static func resolve() -> AppDependencies {
        #if DEBUG
        if LaunchArgs.uiTesting {
            return uiTesting()
        }
        #endif

        let cache = DiskCache.shared
        return AppDependencies(
            service: LiveHNService(cache: cache),
            settings: SettingsStore(),
            bookmarks: BookmarkStore(),
            readStore: ReadStore(),
            cache: cache
        )
    }

    #if DEBUG
    private static func uiTesting() -> AppDependencies {
        let namespace = LaunchArgs.uiStateNamespace ?? UUID().uuidString
        let suiteName = "com.datanoise.ember.uitests.\(namespace)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmberUITests", isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true)

        if !LaunchArgs.uiPreserveState {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let cache = DiskCache(directory: root.appendingPathComponent("cache", isDirectory: true))
        let settings = SettingsStore(defaults: defaults)
        if LaunchArgs.uiSkipOnboarding {
            settings.hasCompletedOnboarding = true
        }
        return AppDependencies(
            service: MockHNService(scenario: LaunchArgs.uiScenario),
            settings: settings,
            bookmarks: BookmarkStore(fileURL: root.appendingPathComponent("bookmarks.json")),
            readStore: ReadStore(defaults: defaults),
            cache: cache
        )
    }
    #endif
}
