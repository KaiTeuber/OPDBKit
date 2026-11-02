import Foundation
import SwiftData

/// Einstellungen für `OPDB`.
public struct OPDBConfiguration: Sendable {
    /// Offizielle Quelle der stets aktuellen OPDB-Daten.
    public static let defaultDataURL = URL(string: "https://mp-data.sfo3.cdn.digitaloceanspaces.com/opdb-v2.json")!

    /// Wo der SwiftData-Store liegt.
    public enum StoreLocation: Sendable, Hashable {
        /// `Application Support/OPDBKit/opdb.store` (vom iCloud-Backup ausgeschlossen, da jederzeit neu ladbar).
        case applicationSupport
        /// Eigener Speicherort, z. B. in einer App Group.
        case file(URL)
        /// Nur im Speicher (z. B. für Previews und Tests).
        case inMemory
    }

    /// URL der JSON-Datei.
    public var dataURL: URL
    public var storeLocation: StoreLocation
    /// Beim Öffnen automatisch auf eine neuere Version prüfen.
    public var checkForUpdatesOnOpen: Bool
    /// Mindestabstand zwischen zwei automatischen Prüfungen in Sekunden.
    /// `0` = bei jedem Öffnen prüfen. Die Prüfung ist günstig (HTTP 304 ohne Download).
    public var minimumCheckInterval: TimeInterval
    /// Optional: eine mit der App ausgelieferte `opdb-v2.json`, die beim allerersten Start
    /// importiert wird, damit die App auch offline sofort Daten hat.
    public var seedFileURL: URL?
    /// Timeout für Netzwerkanfragen in Sekunden.
    public var requestTimeout: TimeInterval
    /// URLSession für Netzwerkzugriffe (z. B. für Tests austauschbar).
    public var urlSession: URLSession

    public init(
        dataURL: URL = OPDBConfiguration.defaultDataURL,
        storeLocation: StoreLocation = .applicationSupport,
        checkForUpdatesOnOpen: Bool = true,
        minimumCheckInterval: TimeInterval = 0,
        seedFileURL: URL? = nil,
        requestTimeout: TimeInterval = 120,
        urlSession: URLSession = .shared
    ) {
        self.dataURL = dataURL
        self.storeLocation = storeLocation
        self.checkForUpdatesOnOpen = checkForUpdatesOnOpen
        self.minimumCheckInterval = minimumCheckInterval
        self.seedFileURL = seedFileURL
        self.requestTimeout = requestTimeout
        self.urlSession = urlSession
    }
}

extension OPDBConfiguration {
    static let modelTypes: [any PersistentModel.Type] = [OPDBMachine.self, OPDBSyncState.self]

    /// Erstellt den `ModelContainer`. Ist ein vorhandener Store inkompatibel (z. B. nach einer
    /// Modelländerung), wird er gelöscht und neu angelegt – die Daten werden anschließend neu geladen.
    func makeModelContainer() throws -> ModelContainer {
        let schema = Schema(Self.modelTypes)
        let storeURL = try resolvedStoreURL()

        func makeModelConfiguration() -> ModelConfiguration {
            if let storeURL {
                return ModelConfiguration("OPDBKit", schema: schema, url: storeURL, allowsSave: true, cloudKitDatabase: .none)
            }
            return ModelConfiguration("OPDBKit", schema: schema, isStoredInMemoryOnly: true, allowsSave: true,
                                      groupContainer: .none, cloudKitDatabase: .none)
        }

        do {
            return try ModelContainer(for: schema, configurations: [makeModelConfiguration()])
        } catch {
            guard let storeURL else { throw error }
            Self.removeStore(at: storeURL)
            return try ModelContainer(for: schema, configurations: [makeModelConfiguration()])
        }
    }

    private func resolvedStoreURL() throws -> URL? {
        let fileManager = FileManager.default
        switch storeLocation {
        case .inMemory:
            return nil
        case .file(let url):
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return url
        case .applicationSupport:
            let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            var directory = base.appendingPathComponent("OPDBKit", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? directory.setResourceValues(values)
            return directory.appendingPathComponent("opdb.store")
        }
    }

    private static func removeStore(at url: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }
}
