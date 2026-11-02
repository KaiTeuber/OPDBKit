import Foundation

/// Ein vollständiger OPDB-Eintrag (Gruppe, Gerät oder Alias) mit allen Details.
///
/// Die Struktur entspricht einem Element aus `entries` der Datei `opdb-v2.json`.
/// Das Decoding ist bewusst tolerant: Fehlende oder unerwartet typisierte Felder
/// führen nicht zum Abbruch, sondern werden als `nil` bzw. leere Liste übernommen.
public struct Machine: Codable, Hashable, Sendable, Identifiable {
    public var id: String { opdbId }

    // MARK: Identität
    public let opdbId: String
    public let opdbGroup: String?
    public let opdbMachine: String?
    public let entryType: EntryType

    // MARK: Namen
    public let name: String
    public let shortName: String?
    public let commonName: String?
    public let nameSort: String?

    // MARK: Eckdaten
    public let year: Int?
    /// Herstellungsdatum im Format `yyyy-MM-dd`.
    public let manufactureDate: String?
    public let description: String?
    public let type: MachineType?
    public let display: DisplayType?
    public let playerCount: Int?
    public let physicalMachine: Bool
    public let manufacturerId: Int?
    public let manufacturer: Manufacturer?
    public let ipdbId: Int?

    // MARK: Links
    public let pinballPrimerUrl: String?
    public let pinballRulesUrl: String?
    public let pinballCardsUrl: String?
    public let bobsGuideUrl: String?
    public let competitionSetupUrl: String?
    public let competitionNotesUrl: String?
    public let hasCompetitionNotes: Bool
    public let hasCompetitionSetup: Bool

    // MARK: Zeitstempel (ISO 8601)
    public let createdAt: String?
    public let updatedAt: String?

    // MARK: Beziehungen
    public let people: [Person]
    public let images: [MachineImage]
    public let features: [Feature]
    public let keywords: [String]

    enum CodingKeys: String, CodingKey {
        case opdbId, opdbGroup, opdbMachine, entryType
        case name, shortName, commonName, nameSort
        case year, manufactureDate, description, type, display, playerCount, physicalMachine
        case manufacturerId, manufacturer, ipdbId
        case pinballPrimerUrl, pinballRulesUrl, pinballCardsUrl, bobsGuideUrl
        case competitionSetupUrl, competitionNotesUrl, hasCompetitionNotes, hasCompetitionSetup
        case createdAt, updatedAt
        case people, images, features, keywords
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        opdbId = try c.decode(String.self, forKey: .opdbId)
        name = try c.decode(String.self, forKey: .name)
        opdbGroup = c.lossyString(.opdbGroup).nonEmpty
        opdbMachine = c.lossyString(.opdbMachine).nonEmpty

        if let raw = c.lossyString(.entryType).nonEmpty {
            entryType = EntryType(rawValue: raw)
        } else if opdbMachine == nil {
            entryType = .machineGroup
        } else if opdbMachine != opdbId {
            entryType = .alias
        } else {
            entryType = .machine
        }

        shortName = c.lossyString(.shortName).nonEmpty
        commonName = c.lossyString(.commonName).nonEmpty
        nameSort = c.lossyString(.nameSort).nonEmpty

        year = c.lossyInt(.year)
        manufactureDate = c.lossyString(.manufactureDate).nonEmpty
        description = c.lossyString(.description).nonEmpty
        type = c.lossyString(.type).nonEmpty.map(MachineType.init(rawValue:))
        display = c.lossyString(.display).nonEmpty.map(DisplayType.init(rawValue:))
        playerCount = c.lossyInt(.playerCount)
        physicalMachine = c.lossyBool(.physicalMachine) ?? false

        let decodedManufacturer = c.lossy(Manufacturer.self, .manufacturer)
        manufacturer = decodedManufacturer
        manufacturerId = c.lossyInt(.manufacturerId) ?? decodedManufacturer?.manufacturerId
        ipdbId = c.lossyInt(.ipdbId)

        pinballPrimerUrl = c.lossyString(.pinballPrimerUrl).nonEmpty
        pinballRulesUrl = c.lossyString(.pinballRulesUrl).nonEmpty
        pinballCardsUrl = c.lossyString(.pinballCardsUrl).nonEmpty
        bobsGuideUrl = c.lossyString(.bobsGuideUrl).nonEmpty
        competitionSetupUrl = c.lossyString(.competitionSetupUrl).nonEmpty
        competitionNotesUrl = c.lossyString(.competitionNotesUrl).nonEmpty
        hasCompetitionNotes = c.lossyBool(.hasCompetitionNotes) ?? false
        hasCompetitionSetup = c.lossyBool(.hasCompetitionSetup) ?? false

        createdAt = c.lossyString(.createdAt).nonEmpty
        updatedAt = c.lossyString(.updatedAt).nonEmpty

        people = c.lossyArray(Person.self, .people)
        images = c.lossyArray(MachineImage.self, .images)
        features = c.lossyArray(Feature.self, .features)
        keywords = c.lossyArray(KeywordValue.self, .keywords).compactMap(\.value)
    }
}

// MARK: - Komfort

public extension Machine {
    /// `commonName`, falls vorhanden, sonst `name`.
    var displayName: String { commonName ?? name }

    /// Das als primär markierte Bild, sonst das erste Bild.
    var primaryImage: MachineImage? { images.first(where: \.primary) ?? images.first }

    /// Erstes Bild eines bestimmten Typs, z. B. `"backglass"`, `"playfield"`, `"cabinet"`.
    func image(ofType type: String) -> MachineImage? {
        images.first { $0.type?.caseInsensitiveCompare(type) == .orderedSame }
    }

    var isGroup: Bool { entryType == .machineGroup }
    var isAlias: Bool { entryType == .alias }

    var manufactureDateValue: Date? { OPDBDate.day(manufactureDate) }
    var createdDate: Date? { OPDBDate.timestamp(createdAt) }
    var updatedDate: Date? { OPDBDate.timestamp(updatedAt) }

    var pinballPrimerURL: URL? { pinballPrimerUrl.flatMap(URL.init(string:)) }
    var rulesheetURL: URL? { pinballRulesUrl.flatMap(URL.init(string:)) }
    var pinballCardsURL: URL? { pinballCardsUrl.flatMap(URL.init(string:)) }
    var bobsGuideURL: URL? { bobsGuideUrl.flatMap(URL.init(string:)) }
    var competitionSetupURL: URL? { competitionSetupUrl.flatMap(URL.init(string:)) }
    var competitionNotesURL: URL? { competitionNotesUrl.flatMap(URL.init(string:)) }

    /// Link zur Internet Pinball Database, falls eine IPDB-ID existiert.
    var ipdbURL: URL? { ipdbId.flatMap { URL(string: "https://www.ipdb.org/machine.cgi?id=\($0)") } }

    /// Link zur Seite des Eintrags auf opdb.org.
    var opdbURL: URL? { URL(string: "https://opdb.org/machines/\(opdbId)") }

    /// Personen einer bestimmten Rolle (z. B. `"design"`, `"art"`), in Originalreihenfolge.
    func people(withRole role: String) -> [Person] {
        people.filter { $0.role?.caseInsensitiveCompare(role) == .orderedSame }
    }
}

// MARK: - Verschachtelte Typen

public struct Manufacturer: Codable, Hashable, Sendable, Identifiable {
    public var id: Int { manufacturerId }
    public let manufacturerId: Int
    public let name: String
    public let fullName: String?

    public init(manufacturerId: Int, name: String, fullName: String?) {
        self.manufacturerId = manufacturerId
        self.name = name
        self.fullName = fullName
    }
}

public struct Person: Codable, Hashable, Sendable {
    /// `opdbPersonId` aus den Rohdaten.
    public let id: String?
    public let name: String
    public let role: String?
    public let index: Int?

    enum CodingKeys: String, CodingKey {
        case id = "opdbPersonId"
        case name, role, index
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lossyString(.id)
        name = try c.decode(String.self, forKey: .name)
        role = c.lossyString(.role).nonEmpty
        index = c.lossyInt(.index)
    }
}

public struct Feature: Codable, Hashable, Sendable {
    public let featureId: Int?
    public let name: String
    public let group: String?

    enum CodingKeys: String, CodingKey { case featureId, name, group }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        featureId = c.lossyInt(.featureId)
        name = try c.decode(String.self, forKey: .name)
        group = c.lossyString(.group).nonEmpty
    }
}

public struct MachineImage: Codable, Hashable, Sendable {
    public let group: String?
    public let title: String?
    public let primary: Bool
    /// z. B. `"backglass"`, `"playfield"`, `"cabinet"`.
    public let type: String?
    public let urls: ImageURLs
    public let sizes: ImageSizes?

    enum CodingKeys: String, CodingKey { case group, title, primary, type, urls, sizes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        group = c.lossyString(.group).nonEmpty
        title = c.lossyString(.title).nonEmpty
        primary = c.lossyBool(.primary) ?? false
        type = c.lossyString(.type).nonEmpty
        urls = c.lossy(ImageURLs.self, .urls) ?? ImageURLs(small: nil, medium: nil, large: nil)
        sizes = c.lossy(ImageSizes.self, .sizes)
    }

    public var smallURL: URL? { urls.small.flatMap(URL.init(string:)) }
    public var mediumURL: URL? { urls.medium.flatMap(URL.init(string:)) }
    public var largeURL: URL? { urls.large.flatMap(URL.init(string:)) }
}

public struct ImageURLs: Codable, Hashable, Sendable {
    public let small: String?
    public let medium: String?
    public let large: String?
}

public struct ImageSizes: Codable, Hashable, Sendable {
    public let small: ImageSize?
    public let medium: ImageSize?
    public let large: ImageSize?
}

public struct ImageSize: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int
}

// MARK: - Tolerante String-Enums

/// Art des Eintrags. Unbekannte Werte bleiben als `rawValue` erhalten.
public struct EntryType: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Übergeordnete Gruppe (z. B. „The Addams Family“ über alle Editionen).
    public static let machineGroup = EntryType(rawValue: "machineGroup")
    /// Konkretes Gerät.
    public static let machine = EntryType(rawValue: "machine")
    /// Alias/Variante eines Geräts (z. B. Sondereditionen mit eigenem Namen).
    public static let alias = EntryType(rawValue: "alias")

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// Bauart des Flippers.
public struct MachineType: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Elektromechanisch.
    public static let electroMechanical = MachineType(rawValue: "em")
    /// Solid State (elektronisch).
    public static let solidState = MachineType(rawValue: "ss")
    /// Rein mechanisch.
    public static let pureMechanical = MachineType(rawValue: "me")

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// Art der Anzeige.
public struct DisplayType: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let lights = DisplayType(rawValue: "lights")
    public static let reels = DisplayType(rawValue: "reels")
    public static let alphanumeric = DisplayType(rawValue: "alphanumeric")
    public static let dmd = DisplayType(rawValue: "dmd")
    public static let cga = DisplayType(rawValue: "cga")
    public static let lcd = DisplayType(rawValue: "lcd")

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}
