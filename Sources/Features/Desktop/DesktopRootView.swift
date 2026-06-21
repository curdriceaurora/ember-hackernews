import SwiftUI

/// Three-pane desktop / large-iPad layout: a source-list sidebar (feeds +
/// library), a story list, and the discussion detail. Reuses the same rows,
/// detail view, and view models as the iPhone layout.
struct DesktopRootView: View {
    let service: any HNServicing
    let cache: DiskCache

    @Environment(SettingsStore.self) private var settings
    @Environment(ReadStore.self) private var readStore
    @Environment(BookmarkStore.self) private var bookmarks

    // Optional so the single-selection `List(selection:)` resolves to the
    // iOS/Catalyst-available initializer.
    @State private var section: DesktopSection? = .feed(.top)
    @State private var selectedStory: HNItem?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showSettings = false
    @State private var didInit = false

    enum DesktopSection: Hashable {
        case feed(Feed)
        case search
        case saved
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } content: {
            middleColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 920, minHeight: 600)
        #endif
        .sheet(isPresented: $showSettings) {
            SettingsView(cache: cache)
                .frame(minWidth: 440, minHeight: 620)
                .environment(settings)
                .environment(readStore)
                .environment(bookmarks)
        }
        .onAppear {
            guard !didInit else { return }
            didInit = true
            section = .feed(settings.defaultFeed)
            #if DEBUG
            switch LaunchArgs.initialTab {
            case "search": section = .search
            case "saved": section = .saved
            default: break
            }
            if LaunchArgs.uiOpenSettings {
                showSettings = true
            }
            #endif
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $section) {
            Section("Feeds") {
                ForEach(Feed.allCases) { feed in
                    Label(feed.title, systemImage: feed.systemImage)
                        .tag(DesktopSection.feed(feed))
                        .accessibilityIdentifier("sidebar.feed.\(feed.rawValue)")
                }
            }
            Section("Library") {
                Label("Search", systemImage: "magnifyingglass")
                    .tag(DesktopSection.search)
                    .accessibilityIdentifier("sidebar.search")
                Label("Saved", systemImage: "bookmark")
                    .tag(DesktopSection.saved)
                    .accessibilityIdentifier("sidebar.saved")
            }
        }
        .navigationTitle("Ember")
        .navigationSplitViewColumnWidth(min: 208, ideal: 240, max: 300)
        .toolbar {
            ToolbarItem {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("settings.open")
            }
        }
    }

    // MARK: Middle column (story list)

    @ViewBuilder private var middleColumn: some View {
        Group {
            switch section {
            case .feed(let feed):
                DesktopFeedColumn(feed: feed, selection: $selectedStory, service: service)
                    .id(feed)
            case .search:
                DesktopSearchColumn(selection: $selectedStory, service: service)
            case .saved:
                DesktopSavedColumn(selection: $selectedStory)
            case .none:
                DesktopFeedColumn(feed: .top, selection: $selectedStory, service: service)
            }
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
    }

    // MARK: Detail column (discussion)

    @ViewBuilder private var detailColumn: some View {
        if let story = selectedStory {
            NavigationStack {
                StoryDetailView(item: story, service: service)
                    .navigationDestination(for: UserRoute.self) {
                        UserView(username: $0.username, service: service)
                    }
                    .navigationDestination(for: HNItem.self) {
                        StoryDetailView(item: $0, service: service)
                    }
            }
            .id(story.id)
        } else {
            ContentUnavailableView {
                Label("Select a story", systemImage: "text.bubble")
            } description: {
                Text("Choose a story from the list to read the discussion.")
            }
            .background(Theme.background)
        }
    }
}
