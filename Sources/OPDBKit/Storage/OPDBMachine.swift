import Foundation
import SwiftData

/// SwiftData-Modell eines OPDB-Eintrags.
///
/// Enthält die für Suche, Filter und Listen benötigten Felder als eigene Attribute sowie den
/// vollständigen Eintrag als JSON (`machine`). Kann in SwiftUI direkt mit `@Query` verwendet
/// werden, wenn der `OPDB.modelContainer` in die View-Hierarchie gegeben wird.
///
/// Die Daten werden von OPDBKit verwaltet und bei jedem Update überschrieben –
/// bitte als nur lesbar betrachten.
@Model
public final class OPDBMachine {
    @Attribute(.unique) public var opdbId: String = ""
    public var opdbGroup: String?
    public var opdbMachine: String?
    public var entryTypeRaw: String = EntryType.machine.rawValue
    public var name: String = ""
    public var shortName: String?
    public var commonName: String?
    /// Sortiername (z. B. „Addams Family, The“), fällt auf `name` zurück.
    public var nameSort: String = ""
    public var year: Int?
    public var manufactureDate: String?
    public var typeRaw: String?
    public var displayRaw: String?
    public var playerCount: Int?
    public var physicalMachine: Bool = false
    public var manufacturerId: Int?
    public var manufacturerName: String?
    public var manufacturerFullName: String?
    public var ipdbId: Int?
    public var thumbnailURLString: String?
    public var imageURLString: String?
    /// `updatedAt` aus der OPDB – wird beim Import verglichen, um unveränderte Einträge zu überspringen.
    public var updatedAt: String?

    /// Normalisierter Suchindex (klein, ohne Diakritika, Wörter durch Leerzeichen getrennt).
    var searchText: String = ""
    /// Vollständiger Eintrag als JSON.
    var payload: Data = Data()

    init(machine: Machine, encoder: JSONEncoder) throws {
        try update(from: machine, encoder: encoder)
    }

    func update(from machine: Machine, encoder: JSONEncoder) throws {
        let image = machine.primaryImage
        opdbId = machine.opdbId
        opdbGroup = machine.opdbGroup
        opdbMachine = machine.opdbMachine
        entryTypeRaw = machine.entryType.rawValue
        name = machine.name
        shortName = machine.shortName
        commonName = machine.commonName
        nameSort = machine.nameSort ?? machine.name
        year = machine.year
        manufactureDate = machine.manufactureDate
        typeRaw = machine.type?.rawValue
        displayRaw = machine.display?.rawValue
        playerCount = machine.playerCount
        physicalMachine = machine.physicalMachine
        manufacturerId = machine.manufacturerId
        manufacturerName = machine.manufacturer?.name
        manufacturerFullName = machine.manufacturer?.fullName
        ipdbId = machine.ipdbId
        thumbnailURLString = image?.urls.small
        imageURLString = image?.urls.medium ?? image?.urls.large
        updatedAt = machine.updatedAt
        searchText = SearchText.index(for: machine)
        payload = try encoder.encode(machine)
    }
}

public extension OPDBMachine {
    var entryType: EntryType { EntryType(rawValue: entryTypeRaw) }
    var type: MachineType? { typeRaw.map(MachineType.init(rawValue:)) }
    var display: DisplayType? { displayRaw.map(DisplayType.init(rawValue:)) }
    var thumbnailURL: URL? { thumbnailURLString.flatMap { URL(string: $0) } }
    var imageURL: URL? { imageURLString.flatMap { URL(string: $0) } }
    var displayName: String { commonName ?? name }

    /// Der vollständige Eintrag mit allen Details (Bilder, Personen, Features, Links …).
    var machine: Machine? { try? decodedMachine() }

    /// Kompakte, `Sendable` Darstellung für Listen.
    var summary: MachineSummary {
        MachineSummary(
            id: opdbId,
            groupId: opdbGroup,
            machineId: opdbMachine,
            entryType: entryType,
            name: name,
            shortName: shortName,
            commonName: commonName,
            year: year,
            manufacturerId: manufacturerId,
            manufacturerName: manufacturerName,
            type: type,
            display: display,
            playerCount: playerCount,
            ipdbId: ipdbId,
            thumbnailURL: thumbnailURL,
            imageURL: imageURL
        )
    }
}

extension OPDBMachine {
    func decodedMachine() throws -> Machine {
        try JSONDecoder().decode(Machine.self, from: payload)
    }

    /// Alle Attribute außer `payload` – für Listenabfragen, damit das JSON nicht mitgeladen wird.
    static var listProperties: [PartialKeyPath<OPDBMachine>] {
        [
            \OPDBMachine.opdbId, \OPDBMachine.opdbGroup, \OPDBMachine.opdbMachine, \OPDBMachine.entryTypeRaw,
            \OPDBMachine.name, \OPDBMachine.shortName, \OPDBMachine.commonName, \OPDBMachine.nameSort,
            \OPDBMachine.year, \OPDBMachine.manufactureDate, \OPDBMachine.typeRaw, \OPDBMachine.displayRaw,
            \OPDBMachine.playerCount, \OPDBMachine.physicalMachine, \OPDBMachine.manufacturerId,
            \OPDBMachine.manufacturerName, \OPDBMachine.manufacturerFullName, \OPDBMachine.ipdbId,
            \OPDBMachine.thumbnailURLString, \OPDBMachine.imageURLString, \OPDBMachine.updatedAt,
            \OPDBMachine.searchText
        ]
    }
}

/// Zustand der Synchronisation (ein einziger Datensatz).
@Model
final class OPDBSyncState {
    @Attribute(.unique) var key: String = "default"
    var etag: String?
    var lastModified: String?
    var lastImport: Date?
    var lastCheck: Date?
    var entryCount: Int = 0
    var skippedCount: Int = 0
    var sourceRaw: String?
    /// Version des gespeicherten Formats; weicht sie ab, werden beim nächsten Import alle Einträge neu geschrieben.
    var formatVersion: Int = 0

    init() {}
}

enum StoreFormat {
    /// Erhöhen, wenn sich `searchText` oder das Payload-Format ändert.
    static let version = 1
}

extension ModelContext {
    func syncState() throws -> OPDBSyncState {
        var descriptor = FetchDescriptor<OPDBSyncState>()
        descriptor.fetchLimit = 1
        if let state = try fetch(descriptor).first { return state }
        let state = OPDBSyncState()
        insert(state)
        return state
    }
}
