import Foundation
import Testing
@testable import Ember

@Suite("Disk cache", .serialized)
struct DiskCacheTests {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmberDiskCacheTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("Stores, loads, measures, and clears values")
    func lifecycle() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DiskCache(directory: directory)

        await cache.store(["one", "two"], for: "feed/top")
        let value = await cache.load([String].self, for: "feed/top")
        #expect(value == ["one", "two"])
        #expect(await cache.sizeInBytes() > 0)
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("feed_top.json").path
        ))

        await cache.clear()
        #expect(await cache.load([String].self, for: "feed/top") == nil)
        #expect(await cache.sizeInBytes() == 0)
    }

    @Test("Invalid JSON is treated as a cache miss")
    func invalidFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not-json".utf8).write(to: directory.appendingPathComponent("broken.json"))
        let cache = DiskCache(directory: directory)

        let value = await cache.load([Int].self, for: "broken")
        #expect(value == nil)
    }

    @Test("Prunes oldest entries after the bounded write interval")
    func pruning() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DiskCache(maxFiles: 3, directory: directory)

        for index in 0..<64 {
            await cache.store(index, for: "entry.\(index)")
        }

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.count == 3)
        #expect(await cache.load(Int.self, for: "entry.63") == 63)
    }
}
