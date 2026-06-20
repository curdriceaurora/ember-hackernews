import SwiftUI

/// A single feed rendered as a selectable list for the desktop middle column.
struct DesktopFeedColumn: View {
    let feed: Feed
    @Binding var selection: HNItem?
    @State private var vm: FeedViewModel

    init(feed: Feed, selection: Binding<HNItem?>, service: any HNServicing) {
        self.feed = feed
        _selection = selection
        _vm = State(initialValue: FeedViewModel(feed: feed, service: service))
    }

    var body: some View {
        Group {
            switch vm.phase {
            case .loading where vm.stories.isEmpty:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message) where vm.stories.isEmpty:
                ErrorStateView(message: message) { Task { await vm.reload() } }
            case .loaded where vm.stories.isEmpty:
                EmptyStateView(
                    systemImage: "newspaper",
                    title: "No stories",
                    message: "There are no stories in this feed right now."
                )
            default:
                list
            }
        }
        .navigationTitle(feed.title)
        .background(Theme.background)
        .task {
            await vm.startIfNeeded()
            #if DEBUG
            if LaunchArgs.autoOpenFirst, selection == nil {
                selection = vm.stories.first
            }
            #endif
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(Array(vm.stories.enumerated()), id: \.element.id) { index, story in
                Button {
                    selection = story
                } label: {
                    StoryRow(item: story, rank: index + 1)
                }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("desktop.story.row.\(story.id)")
                    .accessibilityLabel(story.displayTitle)
                    .tag(story)
                    .listRowSeparatorTint(Theme.separator)
                    .task {
                        if vm.shouldLoadMore(at: story) { await vm.loadNextPage() }
                    }
            }
            if vm.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .refreshable { await vm.reload() }
    }
}

/// Saved stories for the desktop middle column.
struct DesktopSavedColumn: View {
    @Environment(BookmarkStore.self) private var bookmarks
    @Binding var selection: HNItem?

    var body: some View {
        Group {
            if bookmarks.items.isEmpty {
                ContentUnavailableView {
                    Label("Nothing saved", systemImage: "bookmark")
                } description: {
                    Text("Stories you save will appear here.")
                }
            } else {
                List(selection: $selection) {
                    ForEach(bookmarks.items) { story in
                        Button {
                            selection = story
                        } label: {
                            StoryRow(item: story)
                        }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("desktop.story.row.\(story.id)")
                            .accessibilityLabel(story.displayTitle)
                            .tag(story)
                            .listRowSeparatorTint(Theme.separator)
                            .swipeActions {
                                Button(role: .destructive) {
                                    bookmarks.remove(story.id)
                                } label: {
                                    Label("Remove", systemImage: "bookmark.slash.fill")
                                }
                            }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
            }
        }
        .navigationTitle("Saved")
        .background(Theme.background)
    }
}

/// Search for the desktop middle column.
struct DesktopSearchColumn: View {
    @State private var vm: SearchViewModel
    @Binding var selection: HNItem?

    init(selection: Binding<HNItem?>, service: any HNServicing) {
        _selection = selection
        _vm = State(initialValue: SearchViewModel(service: service))
    }

    private var searchKey: String { "\(vm.query)|\(vm.mode.rawValue)" }

    var body: some View {
        Group {
            switch vm.phase {
            case .idle:
                ContentUnavailableView {
                    Label("Search Hacker News", systemImage: "magnifyingglass")
                } description: {
                    Text("Find stories and discussions by keyword.")
                }
            case .searching:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                ContentUnavailableView.search(text: vm.query)
            case .failed(let message):
                ErrorStateView(message: message) { Task { await vm.runSearch() } }
            case .results:
                List(selection: $selection) {
                    ForEach(vm.results) { story in
                        Button {
                            selection = story
                        } label: {
                            StoryRow(item: story)
                        }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("desktop.story.row.\(story.id)")
                            .accessibilityLabel(story.displayTitle)
                            .tag(story)
                            .listRowSeparatorTint(Theme.separator)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .safeAreaInset(edge: .top) {
                    Picker("Sort", selection: Binding(
                        get: { vm.mode },
                        set: { newValue in Task { await vm.setMode(newValue) } }
                    )) {
                        ForEach(SearchMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(Spacing.s)
                    .background(.bar)
                }
            }
        }
        .navigationTitle("Search")
        .background(Theme.background)
        .searchable(text: $vm.query, prompt: "Search stories")
        .task(id: searchKey) {
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            await vm.runSearch()
        }
    }
}
