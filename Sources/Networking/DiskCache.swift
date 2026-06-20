import Foundation

/// A small JSON disk cache used to make recently-viewed content available
/// offline. Lives in the Caches directory and is bounded so it can't grow
/// without limit.
actor DiskCache {
    static let shared = DiskCache()

    private let directory: URL
    private let fileManager: FileManager
    private let maxFiles: Int
    private var storesSincePrune = 0

    init(
        maxFiles: Int = 1_500,
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.maxFiles = maxFiles
        self.fileManager = fileManager
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? caches.appendingPathComponent("HNContentCache", isDirectory: true)
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func url(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent(safe).appendingPathExtension("json")
    }

    func store<T: Encodable>(_ value: T, for key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(for: key), options: .atomic)
        storesSincePrune += 1
        if storesSincePrune >= 64 {
            storesSincePrune = 0
            pruneIfNeeded()
        }
    }

    func load<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func clear() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Approximate on-disk size in bytes.
    func sizeInBytes() -> Int {
        let files = (try? fileManager.contentsOfDirectory(at: directory,
                                                          includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Evict the oldest entries when the file count exceeds the cap.
    private func pruneIfNeeded() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ), files.count > maxFiles else { return }

        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }
        for file in sorted.prefix(files.count - maxFiles) {
            try? fileManager.removeItem(at: file)
        }
    }
}
