import Foundation

/// Kompaktes Suchergebnis – genug für Listen und Zellen, ohne den kompletten Eintrag zu laden.
/// Für alle Details `OPDB.machine(id:)` oder `OPDB.details(for:)` verwenden.
public struct MachineSummary: Hashable, Sendable, Identifiable {
    public let id: String
    public let groupId: String?
    public let machineId: String?
    public let entryType: EntryType
    public let name: String
    public let shortName: String?
    public let commonName: String?
    public let year: Int?
    public let manufacturerId: Int?
    public let manufacturerName: String?
    public let type: MachineType?
    public let display: DisplayType?
    public let playerCount: Int?
    public let ipdbId: Int?
    /// Kleines Vorschaubild (primäres Bild, Größe „small“).
    public let thumbnailURL: URL?
    /// Mittelgroßes Bild (primäres Bild, Größe „medium“).
    public let imageURL: URL?

    public var displayName: String { commonName ?? name }
}

/// Alle Details zu einem Eintrag inklusive verwandter Einträge.
public struct MachineDetails: Hashable, Sendable {
    /// Der angefragte Eintrag mit sämtlichen Feldern.
    public let machine: Machine
    /// Die übergeordnete Gruppe (nil, wenn der Eintrag selbst eine Gruppe ist).
    public let group: Machine?
    /// Bei einem Alias: das Gerät, auf das der Alias verweist.
    public let parentMachine: Machine?
    /// Alle anderen Geräte/Aliase derselben Gruppe (z. B. Pro/Premium/LE).
    public let variants: [MachineSummary]
    /// Aliase, die direkt auf diesen Eintrag verweisen.
    public let aliases: [MachineSummary]
}

/// Hersteller mit Anzahl der zugeordneten Geräte – z. B. für Filter-UIs.
public struct ManufacturerInfo: Hashable, Sendable, Identifiable {
    public var id: Int { manufacturer.manufacturerId }
    public let manufacturer: Manufacturer
    public let machineCount: Int
}

/// Filter für die Suche. Leere Mengen bedeuten „kein Filter“.
public struct SearchFilter: Hashable, Sendable {
    /// Standard: nur konkrete Geräte und Aliase (keine Gruppen-Einträge).
    public var entryTypes: Set<EntryType>
    public var manufacturerIds: Set<Int>
    public var years: ClosedRange<Int>?
    public var types: Set<MachineType>
    public var displays: Set<DisplayType>
    /// Nur Einträge mit `physicalMachine == true`.
    public var physicalMachinesOnly: Bool

    public init(
        entryTypes: Set<EntryType> = [.machine, .alias],
        manufacturerIds: Set<Int> = [],
        years: ClosedRange<Int>? = nil,
        types: Set<MachineType> = [],
        displays: Set<DisplayType> = [],
        physicalMachinesOnly: Bool = false
    ) {
        self.entryTypes = entryTypes
        self.manufacturerIds = manufacturerIds
        self.years = years
        self.types = types
        self.displays = displays
        self.physicalMachinesOnly = physicalMachinesOnly
    }

    /// Geräte und Aliase, ohne weitere Einschränkung.
    public static let `default` = SearchFilter()
    /// Alle Eintragsarten inklusive Gruppen.
    public static let all = SearchFilter(entryTypes: [])
    /// Nur Gruppen (ein Treffer pro Titel, unabhängig von Editionen).
    public static let groupsOnly = SearchFilter(entryTypes: [.machineGroup])
}

public enum SearchSort: Sendable, Hashable {
    /// Beste Übereinstimmung zuerst (bei leerem Suchtext: alphabetisch).
    case relevance
    case name
    case yearAscending
    case yearDescending
}

/// Herkunft des aktuell importierten Datenbestands.
public enum DataSource: String, Sendable, Hashable {
    case remote
    case seed
}

/// Ergebnis eines Imports.
public struct ImportSummary: Sendable, Hashable {
    /// Anzahl gültiger Einträge in der geladenen Datei.
    public let importedCount: Int
    /// Neu hinzugekommene Einträge.
    public let insertedCount: Int
    /// Geänderte Einträge (anderes `updatedAt`).
    public let updatedCount: Int
    /// Einträge, die in der neuen Datei nicht mehr enthalten sind und gelöscht wurden.
    public let deletedCount: Int
    /// Unveränderte Einträge (nicht neu geschrieben).
    public let unchangedCount: Int
    /// Einträge, die wegen fehlerhafter Daten übersprungen wurden.
    public let skippedCount: Int
    public let etag: String?
    public let lastModified: String?
    public let source: DataSource
}

/// Ergebnis eines Update-Laufs.
public enum UpdateResult: Sendable, Hashable {
    /// Server meldet keine neuere Version (HTTP 304 bzw. gleiche ETag).
    case upToDate
    /// Neue Version wurde geladen und importiert.
    case updated(ImportSummary)
    /// Nicht geprüft, weil die letzte Prüfung jünger als `minimumCheckInterval` ist.
    case skipped
}

/// Fortschritt der Aktualisierung, z. B. für eine Statusanzeige.
public enum UpdateStatus: Sendable, Hashable {
    case idle
    case checking
    case downloading
    case importing
    case finished(UpdateResult)
    case failed(String)
}

/// Informationen über den lokalen Datenbestand.
public struct DataInfo: Sendable, Hashable {
    public let entryCount: Int
    public let source: DataSource?
    public let etag: String?
    public let lastModified: String?
    public let lastImport: Date?
    public let lastCheck: Date?
}

public enum OPDBError: Error, LocalizedError, Sendable {
    case database(String)
    case invalidResponse
    case httpStatus(Int)
    case decoding(String)
    case emptyDataset

    public var errorDescription: String? {
        switch self {
        case .database(let message):
            return String(localized: "Database error: \(message)", bundle: .module)
        case .invalidResponse:
            return String(localized: "Invalid server response.", bundle: .module)
        case .httpStatus(let code):
            // Als String übergeben, damit der Statuscode nicht als Zahl formatiert wird.
            return String(localized: "Server responded with HTTP \(String(code)).", bundle: .module)
        case .decoding(let message):
            return String(localized: "The data could not be read: \(message)", bundle: .module)
        case .emptyDataset:
            return String(localized: "The downloaded data contains no entries.", bundle: .module)
        }
    }
}
