import Foundation
import SwiftData

/// Zentrale Schnittstelle zur lokalen OPDB-Datenbank (SwiftData).
///
/// ```swift
/// // Öffnen: prüft automatisch auf neue Daten und lädt sie ggf. nach.
/// let opdb = try await OPDB.open()
///
/// // Suchen
/// let hits = try await opdb.search("addams")
///
/// // Alle Details
/// if let details = try await opdb.details(for: hits[0].id) {
///     print(details.machine.manufacturer?.name, details.variants.count)
/// }
/// ```
///
/// Suche und Detailabrufe liefern `Sendable` Werttypen und laufen auf einem Hintergrund-Kontext.
/// Updates werden auf einem eigenen Kontext importiert, sodass die App währenddessen weiter
/// suchen kann. Für SwiftUI steht zusätzlich `modelContainer` für `@Query` zur Verfügung.
public actor OPDB {
    public nonisolated let configuration: OPDBConfiguration
    /// Der SwiftData-Container mit `OPDBMachine`. Kann z. B. per `.modelContainer(opdb.modelContainer)`
    /// an SwiftUI-Views gegeben und dort mit `@Query` abgefragt werden.
    public nonisolated let modelContainer: ModelContainer

    private var store: ReadStore
    private let remote: RemoteSource
    private var runningUpdate: Task<UpdateResult, Error>?
    private var statusContinuations: [UUID: AsyncStream<UpdateStatus>.Continuation] = [:]

    /// Aktueller Update-Status.
    public private(set) var status: UpdateStatus = .idle

    // MARK: - Initialisierung

    private init(configuration: OPDBConfiguration, modelContainer: ModelContainer, store: ReadStore) {
        self.configuration = configuration
        self.modelContainer = modelContainer
        self.store = store
        self.remote = RemoteSource(url: configuration.dataURL,
                                   session: configuration.urlSession,
                                   timeout: configuration.requestTimeout)
    }

    /// Öffnet die Datenbank und prüft (gemäß Konfiguration) auf eine neuere Datenversion.
    ///
    /// - Ist die Datenbank noch leer (erster Start), wird ggf. die `seedFileURL` importiert
    ///   und anschließend auf das Update **gewartet** – danach sind Daten verfügbar.
    ///   Schlägt das bei leerer Datenbank fehl, wird der Fehler geworfen.
    /// - Sind bereits Daten vorhanden, läuft die Prüfung im **Hintergrund**; die Instanz ist
    ///   sofort nutzbar. Fortschritt über `statusUpdates()` beobachtbar.
    public static func open(configuration: OPDBConfiguration = OPDBConfiguration()) async throws -> OPDB {
        let container = try configuration.makeModelContainer()
        let store = await makeReadStore(container)
        let opdb = OPDB(configuration: configuration, modelContainer: container, store: store)
        try await opdb.prepareInitialData()
        return opdb
    }

    /// ModelActors übernehmen die Queue des Threads, auf dem sie erzeugt werden –
    /// daher bewusst in einer losgelösten Task anlegen, damit sie nicht auf dem Main Thread laufen.
    private static func makeReadStore(_ container: ModelContainer) async -> ReadStore {
        await Task.detached(priority: .userInitiated) { ReadStore(modelContainer: container) }.value
    }

    private func prepareInitialData() async throws {
        if try await store.entryCount() == 0, let seed = configuration.seedFileURL {
            setStatus(.importing)
            let summary = try await runImport(fileURL: seed, source: .seed, validators: .init())
            setStatus(.finished(.updated(summary)))
        }

        guard configuration.checkForUpdatesOnOpen else { return }

        if try await store.entryCount() == 0 {
            try await updateIfNeeded(force: true)
        } else {
            Task { [weak self] in
                _ = try? await self?.updateIfNeeded()
            }
        }
    }

    // MARK: - Updates

    /// Prüft, ob eine neuere Version vorliegt, und importiert sie ggf.
    ///
    /// Verwendet einen bedingten GET (`If-None-Match` / `If-Modified-Since`): Ist nichts neu,
    /// antwortet der Server mit 304 und es wird nichts heruntergeladen. Bei einer neuen Version
    /// werden nur neue, geänderte (`updatedAt`) und entfernte Einträge geschrieben.
    /// Parallele Aufrufe teilen sich denselben Update-Lauf.
    ///
    /// - Parameter force: `true` ignoriert `minimumCheckInterval` und lädt die Datei in jedem Fall.
    @discardableResult
    public func updateIfNeeded(force: Bool = false) async throws -> UpdateResult {
        if let runningUpdate {
            return try await runningUpdate.value
        }

        let task = Task { try await self.performUpdate(force: force) }
        runningUpdate = task
        defer { runningUpdate = nil }

        do {
            let result = try await task.value
            setStatus(.finished(result))
            return result
        } catch {
            setStatus(.failed(error.localizedDescription))
            throw error
        }
    }

    /// Prüft per HEAD-Anfrage, ob eine neuere Version verfügbar ist, ohne sie zu laden.
    public func isUpdateAvailable() async throws -> Bool {
        let info = try await store.dataInfo()
        guard info.entryCount > 0, info.source == .remote else { return true }
        return try await remote.hasChanges(comparedTo: .init(etag: info.etag, lastModified: info.lastModified))
    }

    private func performUpdate(force: Bool) async throws -> UpdateResult {
        let info = try await store.dataInfo()
        let hasRemoteData = info.entryCount > 0 && info.source == .remote

        if !force, hasRemoteData, configuration.minimumCheckInterval > 0,
           let lastCheck = info.lastCheck,
           Date().timeIntervalSince(lastCheck) < configuration.minimumCheckInterval {
            return .skipped
        }

        setStatus(.checking)
        let known: RemoteSource.Validators? = (hasRemoteData && !force)
            ? RemoteSource.Validators(etag: info.etag, lastModified: info.lastModified)
            : nil

        setStatus(.downloading)
        switch try await remote.fetch(ifChangedFrom: known) {
        case .notModified:
            try await store.markChecked(at: Date())
            return .upToDate

        case .downloaded(let fileURL, let validators):
            defer { try? FileManager.default.removeItem(at: fileURL) }
            setStatus(.importing)
            let summary = try await runImport(fileURL: fileURL, source: .remote, validators: validators)
            return .updated(summary)
        }
    }

    private func runImport(fileURL: URL, source: DataSource, validators: RemoteSource.Validators) async throws -> ImportSummary {
        let container = modelContainer
        let importer = await Task.detached(priority: .utility) { ImportStore(modelContainer: container) }.value
        let summary = try await importer.importFile(
            at: fileURL,
            source: source,
            etag: validators.etag,
            lastModified: validators.lastModified
        )
        // Frischen Lese-Kontext verwenden, damit keine veralteten Objekte aus dem Cache kommen.
        store = await Self.makeReadStore(container)
        return summary
    }

    // MARK: - Status-Beobachtung

    /// Liefert laufend den Update-Status (beginnend mit dem aktuellen Wert).
    ///
    /// ```swift
    /// for await status in await opdb.statusUpdates() { … }
    /// ```
    public func statusUpdates() -> AsyncStream<UpdateStatus> {
        let id = UUID()
        var captured: AsyncStream<UpdateStatus>.Continuation?
        let stream = AsyncStream<UpdateStatus>(bufferingPolicy: .bufferingNewest(16)) { captured = $0 }
        guard let continuation = captured else { return stream }

        continuation.yield(status)
        statusContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream
    }

    private func removeContinuation(_ id: UUID) {
        statusContinuations[id] = nil
    }

    private func setStatus(_ newStatus: UpdateStatus) {
        status = newStatus
        for continuation in statusContinuations.values {
            continuation.yield(newStatus)
        }
    }

    // MARK: - Suche

    /// Suche über Name, Kurzname (z. B. „TAF“), Hersteller, Personen, Features und IDs.
    ///
    /// Jedes Wort wird als Wortanfang gesucht und alle Wörter müssen vorkommen
    /// („addams fam“ findet „The Addams Family“); ohne Treffer folgt eine Teilstring-Suche.
    /// Groß-/Kleinschreibung und Akzente werden ignoriert. Ein leerer Suchtext liefert
    /// alle Einträge, die zum Filter passen.
    ///
    /// - Parameters:
    ///   - text: Suchtext.
    ///   - filter: Einschränkungen (Standard: nur Geräte und Aliase, keine Gruppen).
    ///   - sort: Sortierung (Standard: Relevanz).
    ///   - limit: Maximale Anzahl Treffer.
    ///   - offset: Für Paging.
    public func search(
        _ text: String,
        filter: SearchFilter = .default,
        sort: SearchSort = .relevance,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [MachineSummary] {
        try await store.search(text: text, filter: filter, sort: sort, limit: limit, offset: offset)
    }

    // MARK: - Details

    /// Vollständiger Eintrag mit allen Feldern (Bilder, Personen, Features, Links …).
    public func machine(id opdbId: String) async throws -> Machine? {
        try await store.machine(id: opdbId)
    }

    /// Eintrag anhand der IPDB-ID (bevorzugt ein konkretes Gerät).
    public func machine(ipdbId: Int) async throws -> Machine? {
        try await store.machine(ipdbId: ipdbId)
    }

    /// Mehrere Einträge in der Reihenfolge der übergebenen IDs (z. B. für die eigene Sammlung).
    public func machines(ids: [String]) async throws -> [Machine] {
        try await store.machines(ids: ids)
    }

    /// Alle Details zu einem Eintrag inklusive Gruppe, Varianten und Aliasen.
    public func details(for opdbId: String) async throws -> MachineDetails? {
        try await store.details(id: opdbId)
    }

    /// Alle Hersteller mit Anzahl ihrer Geräte, alphabetisch sortiert.
    public func manufacturers() async throws -> [ManufacturerInfo] {
        try await store.manufacturers()
    }

    /// Informationen zum lokalen Datenstand (Anzahl, Importzeitpunkt, ETag …).
    public func dataInfo() async throws -> DataInfo {
        try await store.dataInfo()
    }
}
