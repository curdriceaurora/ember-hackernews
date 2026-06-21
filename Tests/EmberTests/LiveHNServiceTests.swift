import Foundation
import Testing
@testable import Ember

@Suite("Live service with URLProtocol", .serialized)
struct LiveHNServiceTests {
    private func service() throws -> (LiveHNService, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmberLiveServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return (
            LiveHNService(
                session: URLSession(configuration: configuration),
                cache: DiskCache(directory: directory)
            ),
            directory
        )
    }

    @Test("Builds Firebase URLs and decodes feed, item, and user payloads")
    func firebaseRequests() async throws {
        let (service, directory) = try service()
        defer { try? FileManager.default.removeItem(at: directory) }
        StubURLProtocol.handler = { request in
            let path = try #require(request.url?.path)
            switch path {
            case "/v0/topstories.json":
                return Self.response(request, json: "[3,2,1]")
            case "/v0/item/3.json":
                return Self.response(request, json: Self.itemJSON(id: 3))
            case "/v0/user/pg.json":
                return Self.response(request, json: #"{"id":"pg","created":1160418092,"karma":1}"#)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        #expect(try await service.storyIDs(for: .top) == [3, 2, 1])
        #expect(try await service.item(3).id == 3)
        #expect(try await service.user("pg").id == "pg")
    }

    @Test("Builds encoded Algolia search queries and decodes hits")
    func searchRequest() async throws {
        let (service, directory) = try service()
        defer { try? FileManager.default.removeItem(at: directory) }
        StubURLProtocol.handler = { request in
            let url = try #require(request.url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(components.path == "/api/v1/search_by_date")
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            #expect(query["query"] == "swift concurrency")
            #expect(query["tags"] == "story")
            #expect(query["page"] == "2")
            #expect(query["hitsPerPage"] == "30")
            return Self.response(
                request,
                json: #"{"hits":[{"objectID":"42","title":"Swift","author":"tester","points":5,"num_comments":2,"created_at_i":1700000000}]}"#
            )
        }

        let hits = try await service.search("swift concurrency", mode: .recent, page: 2)
        #expect(hits.map(\.objectID) == ["42"])
    }

    @Test("Decodes Algolia discussion trees")
    func commentTree() async throws {
        let (service, directory) = try service()
        defer { try? FileManager.default.removeItem(at: directory) }
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/v1/items/42")
            return Self.response(
                request,
                json: #"{"id":42,"created_at_i":1700000000,"type":"story","author":"tester","children":[{"id":43,"created_at_i":1700000001,"type":"comment","author":"reply","parent_id":42,"children":[]}]}"#
            )
        }

        let tree = try await service.commentTree(for: 42)
        #expect(tree.id == 42)
        #expect((tree.children ?? []).map(\.id) == [43])
    }

    @Test("Surfaces HTTP, decoding, and transport failures")
    func errors() async throws {
        let (service, directory) = try service()
        defer { try? FileManager.default.removeItem(at: directory) }

        StubURLProtocol.handler = { request in Self.response(request, status: 503, json: "{}") }
        await #expect(throws: HNError.self) { try await service.user("status") }

        StubURLProtocol.handler = { request in Self.response(request, json: "{") }
        await #expect(throws: HNError.self) { try await service.user("decode") }

        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: HNError.self) { try await service.user("transport") }
    }

    @Test("Preserves requested item order and drops individual failures")
    func concurrentItems() async throws {
        let (service, directory) = try service()
        defer { try? FileManager.default.removeItem(at: directory) }
        StubURLProtocol.handler = { request in
            let id = try #require(request.url?.deletingPathExtension().lastPathComponent)
            if id == "2" { throw URLError(.cannotDecodeContentData) }
            return Self.response(request, json: Self.itemJSON(id: Int(id)!))
        }

        let items = try await service.items([3, 2, 1])
        #expect(items.map(\.id) == [3, 1])
    }

    @Test("Falls back to isolated cache after feed, item, and tree failures")
    func cacheFallback() async throws {
        let (service, directory) = try service()
        defer { try? FileManager.default.removeItem(at: directory) }
        StubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v0/topstories.json":
                return Self.response(request, json: "[42]")
            case "/v0/item/42.json":
                return Self.response(request, json: Self.itemJSON(id: 42))
            case "/api/v1/items/42":
                return Self.response(request, json: #"{"id":42,"type":"story","children":[]}"#)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        _ = try await service.storyIDs(for: .top)
        _ = try await service.item(42)
        _ = try await service.commentTree(for: 42)
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        #expect(try await service.storyIDs(for: .top) == [42])
        #expect(try await service.item(42).id == 42)
        #expect(try await service.commentTree(for: 42).id == 42)
    }

    private static func response(
        _ request: URLRequest,
        status: Int = 200,
        json: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(json.utf8)
        )
    }

    private static func itemJSON(id: Int) -> String {
        #"{"id":\#(id),"type":"story","by":"tester","time":1700000000,"score":10,"title":"Story \#(id)","descendants":2}"#
    }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try #require(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
