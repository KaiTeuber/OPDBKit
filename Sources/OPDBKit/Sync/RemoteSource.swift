import Foundation

/// Netzwerkzugriff auf die OPDB-Datei mit bedingten Anfragen (ETag / Last-Modified).
struct RemoteSource: Sendable {
    let url: URL
    let session: URLSession
    let timeout: TimeInterval

    struct Validators: Sendable, Equatable {
        var etag: String?
        var lastModified: String?

        var isEmpty: Bool { etag == nil && lastModified == nil }
    }

    enum FetchResult: Sendable {
        case notModified
        case downloaded(fileURL: URL, validators: Validators)
    }

    /// Prüft per HEAD-Anfrage, ob sich die Datei gegenüber `known` geändert hat – ohne sie zu laden.
    func hasChanges(comparedTo known: Validators) async throws -> Bool {
        var request = makeRequest(conditional: known)
        request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        let http = try httpResponse(response)
        if http.statusCode == 304 { return false }
        guard (200..<300).contains(http.statusCode) else { throw OPDBError.httpStatus(http.statusCode) }
        let remote = validators(from: http)
        if remote.isEmpty || known.isEmpty { return true }
        if let etag = remote.etag, let knownETag = known.etag { return etag != knownETag }
        return remote.lastModified != known.lastModified
    }

    /// Lädt die Datei, sofern sie sich gegenüber `known` geändert hat (bedingter GET).
    /// Die Datei wird in ein eigenes Verzeichnis verschoben; der Aufrufer löscht sie nach dem Import.
    func fetch(ifChangedFrom known: Validators?) async throws -> FetchResult {
        let request = makeRequest(conditional: known)
        let (temporaryURL, response) = try await session.download(for: request)
        let http = try httpResponse(response)

        if http.statusCode == 304 {
            try? FileManager.default.removeItem(at: temporaryURL)
            return .notModified
        }
        guard (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw OPDBError.httpStatus(http.statusCode)
        }

        let remote = validators(from: http)
        // Fallback, falls der Server bedingte Header ignoriert: gleiche ETag ⇒ unverändert.
        if let known, let etag = remote.etag, etag == known.etag {
            try? FileManager.default.removeItem(at: temporaryURL)
            return .notModified
        }

        let staged = try Self.stagingDirectory().appendingPathComponent("opdb-\(UUID().uuidString).json")
        try FileManager.default.moveItem(at: temporaryURL, to: staged)
        return .downloaded(fileURL: staged, validators: remote)
    }

    private func makeRequest(conditional known: Validators?) -> URLRequest {
        // Lokalen HTTP-Cache umgehen, damit ein 304 des Servers nicht in eine
        // (veraltete) 200-Antwort aus dem Cache umgewandelt wird.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        if let known {
            if let etag = known.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let lastModified = known.lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        }
        return request
    }

    private func httpResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw OPDBError.invalidResponse }
        return http
    }

    private func validators(from response: HTTPURLResponse) -> Validators {
        Validators(
            etag: response.value(forHTTPHeaderField: "ETag"),
            lastModified: response.value(forHTTPHeaderField: "Last-Modified")
        )
    }

    static func stagingDirectory() throws -> URL {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = caches.appendingPathComponent("OPDBKit", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
