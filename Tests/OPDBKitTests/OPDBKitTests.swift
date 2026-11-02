import XCTest
@testable import OPDBKit

final class OPDBKitTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.requests = []
        super.tearDown()
    }

    // MARK: - Laden & Suchen

    func testOpenLoadsDataOnFirstStart() async throws {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 200, etag: "\"v1\""), try Fixture.data())
        }

        let opdb = try await OPDB.open(configuration: makeConfiguration())
        let info = try await opdb.dataInfo()

        XCTAssertEqual(info.entryCount, 7)
        XCTAssertEqual(info.etag, "\"v1\"")
        XCTAssertEqual(info.source, .remote)
        XCTAssertNotNil(info.lastImport)
    }

    func testSearch() async throws {
        let opdb = try await openWithFixture()

        let trade = try await opdb.search("trade")
        XCTAssertEqual(trade.map(\.id), ["G0l2e-Mp4Oz"], "Standardfilter ohne Gruppen")
        XCTAssertEqual(trade.first?.manufacturerName, "Genco")
        XCTAssertNotNil(trade.first?.thumbnailURL)

        let tradeAll = try await opdb.search("trade", filter: .all)
        XCTAssertEqual(tradeAll.count, 2)

        let platinum = try await opdb.search("beatles plat")
        XCTAssertEqual(platinum.map(\.id), ["G0l8P-M85d9-A1ZNY"])

        let stern = try await opdb.search("stern")
        XCTAssertEqual(Set(stern.map(\.id)), ["G0l8P-M85d9", "G0l8P-M85d9-A1ZNY"])

        let shortName = try await opdb.search("HST")
        XCTAssertEqual(shortName.first?.id, "G18pJ-Mz2bl")

        let person = try await opdb.search("testperson")
        XCTAssertEqual(person.map(\.id), ["G18pJ-Mz2bl"])

        let byIPDB = try await opdb.search("6561")
        XCTAssertEqual(byIPDB.map(\.id), ["G0l8P-M85d9"])

        let infix = try await opdb.search("eatles")
        XCTAssertFalse(infix.isEmpty, "Fallback auf Teilstring-Suche")

        let nothing = try await opdb.search("xyzzy")
        XCTAssertTrue(nothing.isEmpty)
    }

    func testSearchFiltersAndSorting() async throws {
        let opdb = try await openWithFixture()

        let modern = try await opdb.search("", filter: SearchFilter(years: 2019...2021))
        XCTAssertEqual(modern.map(\.id), ["G18pJ-Mz2bl"])

        let sternOnly = try await opdb.search("", filter: SearchFilter(manufacturerIds: [12]))
        XCTAssertEqual(sternOnly.count, 2)

        let em = try await opdb.search("", filter: SearchFilter(types: [.electroMechanical]))
        XCTAssertEqual(em.map(\.id), ["G0l2e-Mp4Oz"])

        let groups = try await opdb.search("", filter: .groupsOnly, sort: .name)
        XCTAssertEqual(groups.map(\.name), ["Beatles", "Heist", "Trade Winds"])

        let newestFirst = try await opdb.search("", sort: .yearDescending, limit: 1)
        XCTAssertEqual(newestFirst.first?.id, "G18pJ-Mz2bl")

        let page2 = try await opdb.search("", sort: .name, limit: 2, offset: 2)
        XCTAssertEqual(page2.count, 2)
    }

    // MARK: - Details

    func testDetails() async throws {
        let opdb = try await openWithFixture()

        let gold = try await opdb.details(for: "G0l8P-M85d9")
        XCTAssertEqual(gold?.machine.name, "The Beatles (Gold)")
        XCTAssertEqual(gold?.machine.manufacturer?.fullName, "Stern Pinball, Inc.")
        XCTAssertEqual(gold?.machine.features.first?.name, "Pro edition")
        XCTAssertEqual(gold?.machine.type, .solidState)
        XCTAssertEqual(gold?.machine.display, .lcd)
        XCTAssertEqual(gold?.group?.opdbId, "G0l8P")
        XCTAssertEqual(gold?.aliases.map(\.id), ["G0l8P-M85d9-A1ZNY"])
        XCTAssertEqual(gold?.machine.ipdbURL?.absoluteString, "https://www.ipdb.org/machine.cgi?id=6561")

        let alias = try await opdb.details(for: "G0l8P-M85d9-A1ZNY")
        XCTAssertEqual(alias?.machine.entryType, .alias)
        XCTAssertEqual(alias?.parentMachine?.opdbId, "G0l8P-M85d9")
        XCTAssertTrue(alias?.variants.contains { $0.id == "G0l8P-M85d9" } ?? false)

        let group = try await opdb.details(for: "G0l8P")
        XCTAssertNil(group?.group)
        XCTAssertEqual(group?.variants.count, 2)

        let heist = try await opdb.machine(id: "G18pJ-Mz2bl")
        XCTAssertEqual(heist?.people.first?.name, "Testperson Designer")
        XCTAssertEqual(heist?.people.first?.role, "design")
        XCTAssertNotNil(heist?.rulesheetURL)
        XCTAssertNotNil(heist?.createdDate)
        XCTAssertNotNil(heist?.manufactureDateValue)

        let tradeWinds = try await opdb.machine(ipdbId: 2619)
        XCTAssertEqual(tradeWinds?.opdbId, "G0l2e-Mp4Oz")
        XCTAssertEqual(tradeWinds?.primaryImage?.type, "backglass")
        XCTAssertEqual(tradeWinds?.primaryImage?.sizes?.large?.width, 652)
        XCTAssertNil(tradeWinds?.description, "Leerer String wird zu nil")

        let collection = try await opdb.machines(ids: ["G18pJ-Mz2bl", "unknown", "G0l2e-Mp4Oz"])
        XCTAssertEqual(collection.map(\.opdbId), ["G18pJ-Mz2bl", "G0l2e-Mp4Oz"])

        let missing = try await opdb.details(for: "does-not-exist")
        XCTAssertNil(missing)

        let manufacturers = try await opdb.manufacturers()
        XCTAssertEqual(manufacturers.map(\.manufacturer.name), ["Genco", "Multimorphic", "Stern"])
    }

    // MARK: - Updates

    func testConditionalRequestReturnsUpToDate() async throws {
        let opdb = try await openWithFixture()

        MockURLProtocol.handler = { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"" {
                return (Self.response(for: request, status: 304, etag: "\"v1\""), Data())
            }
            return (Self.response(for: request, status: 200, etag: "\"v1\""), try Fixture.data())
        }

        let result = try await opdb.updateIfNeeded()
        XCTAssertEqual(result, .upToDate)
        let status = await opdb.status
        XCTAssertEqual(status, .finished(.upToDate))

        let available = try await opdb.isUpdateAvailable()
        XCTAssertFalse(available)
        XCTAssertEqual(MockURLProtocol.requests.last?.httpMethod, "HEAD")
    }

    func testNewVersionIsImported() async throws {
        let opdb = try await openWithFixture()

        let reduced = try Fixture.data(removingIDs: ["G18pJ", "G18pJ-Mz2bl"])
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 200, etag: "\"v2\""), reduced)
        }

        let available = try await opdb.isUpdateAvailable()
        XCTAssertTrue(available)

        let result = try await opdb.updateIfNeeded()
        guard case .updated(let summary) = result else {
            return XCTFail("Erwartet: .updated, erhalten: \(result)")
        }
        XCTAssertEqual(summary.importedCount, 5)
        XCTAssertEqual(summary.deletedCount, 2)
        XCTAssertEqual(summary.insertedCount, 0)
        XCTAssertEqual(summary.unchangedCount, 5)
        XCTAssertEqual(summary.skippedCount, 1)
        XCTAssertEqual(summary.etag, "\"v2\"")

        let heist = try await opdb.search("heist")
        XCTAssertTrue(heist.isEmpty)
        let info = try await opdb.dataInfo()
        XCTAssertEqual(info.entryCount, 5)
    }

    func testIncrementalUpdateOnlyWritesChangedEntries() async throws {
        let opdb = try await openWithFixture()

        let changed = try Fixture.data(modifying: "G18pJ-Mz2bl") { entry in
            entry["name"] = "Heist Deluxe"
            entry["updatedAt"] = "2026-09-30T10:00:00.000000Z"
        }
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 200, etag: "\"v3\""), changed)
        }

        let result = try await opdb.updateIfNeeded()
        guard case .updated(let summary) = result else {
            return XCTFail("Erwartet: .updated, erhalten: \(result)")
        }
        XCTAssertEqual(summary.updatedCount, 1)
        XCTAssertEqual(summary.unchangedCount, 6)
        XCTAssertEqual(summary.insertedCount, 0)
        XCTAssertEqual(summary.deletedCount, 0)

        let hits = try await opdb.search("deluxe")
        XCTAssertEqual(hits.map(\.id), ["G18pJ-Mz2bl"])
        let machine = try await opdb.machine(id: "G18pJ-Mz2bl")
        XCTAssertEqual(machine?.name, "Heist Deluxe")
    }

    func testMinimumCheckIntervalSkipsCheck() async throws {
        let opdb = try await openWithFixture(minimumCheckInterval: 3600)
        let count = MockURLProtocol.requests.count

        let result = try await opdb.updateIfNeeded()
        XCTAssertEqual(result, .skipped)
        XCTAssertEqual(MockURLProtocol.requests.count, count, "Keine Netzwerkanfrage")
    }

    func testFailedFirstLoadThrows() async throws {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 500, etag: nil), Data())
        }
        do {
            _ = try await OPDB.open(configuration: makeConfiguration())
            XCTFail("Erwartet: Fehler")
        } catch OPDBError.httpStatus(let code) {
            XCTAssertEqual(code, 500)
        }
    }

    func testSeedFileIsUsedOnFirstStart() async throws {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 500, etag: nil), Data())
        }
        var configuration = makeConfiguration()
        configuration.seedFileURL = try Fixture.url()
        configuration.checkForUpdatesOnOpen = false

        let opdb = try await OPDB.open(configuration: configuration)
        let info = try await opdb.dataInfo()
        XCTAssertEqual(info.entryCount, 7)
        XCTAssertEqual(info.source, .seed)
    }

    // MARK: - Einzelteile

    func testSearchTextNormalization() {
        XCTAssertEqual(SearchText.tokens("Addams-Fam"), ["addams", "fam"])
        XCTAssertEqual(SearchText.tokens("AC/DC \"Pro\""), ["ac", "dc", "pro"])
        XCTAssertEqual(SearchText.fold("Pokémon Über"), "pokemon uber")
        XCTAssertTrue(SearchText.tokens("  -- ").isEmpty)
    }

    func testLossyDecoding() throws {
        let (machines, skipped) = try EntryDecoder.decode(from: try Fixture.data())
        XCTAssertEqual(machines.count, 7)
        XCTAssertEqual(skipped, 1)
    }

    // MARK: - Hilfen

    private func makeConfiguration(minimumCheckInterval: TimeInterval = 0) -> OPDBConfiguration {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockURLProtocol.self]
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OPDBKitTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("opdb.store")
        return OPDBConfiguration(
            storeLocation: .file(storeURL),
            minimumCheckInterval: minimumCheckInterval,
            urlSession: URLSession(configuration: sessionConfiguration)
        )
    }

    private func openWithFixture(minimumCheckInterval: TimeInterval = 0) async throws -> OPDB {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 200, etag: "\"v1\""), try Fixture.data())
        }
        return try await OPDB.open(configuration: makeConfiguration(minimumCheckInterval: minimumCheckInterval))
    }

    static func response(for request: URLRequest, status: Int, etag: String?) -> HTTPURLResponse {
        var headers = ["Content-Type": "application/json"]
        if let etag { headers["ETag"] = etag }
        return HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}

// MARK: - Fixture

enum Fixture {
    static func url() throws -> URL {
        guard let url = Bundle.module.url(forResource: "opdb-fixture", withExtension: "json", subdirectory: "Fixtures") else {
            throw URLError(.fileDoesNotExist)
        }
        return url
    }

    static func data() throws -> Data {
        try Data(contentsOf: url())
    }

    static func data(modifying id: String, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: data()) as! [String: Any]
        var entries = object["entries"] as! [[String: Any]]
        for index in entries.indices where entries[index]["opdbId"] as? String == id {
            change(&entries[index])
        }
        object["entries"] = entries
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func data(removingIDs ids: Set<String>) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: data()) as! [String: Any]
        let entries = object["entries"] as! [[String: Any]]
        object["entries"] = entries.filter { !ids.contains($0["opdbId"] as? String ?? "") }
        return try JSONSerialization.data(withJSONObject: object)
    }
}

// MARK: - Mock-Netzwerk

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
