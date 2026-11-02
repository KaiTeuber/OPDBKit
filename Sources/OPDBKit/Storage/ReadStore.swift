import Foundation
import SwiftData

/// Lesezugriffe auf SwiftData. Läuft auf einem eigenen Hintergrund-Kontext.
@ModelActor
actor ReadStore {

    // MARK: - Einzelabrufe

    func machine(id: String) throws -> Machine? {
        try entity(id: id).map { try $0.decodedMachine() }
    }

    func machine(ipdbId: Int) throws -> Machine? {
        let value: Int? = ipdbId
        let rows = try modelContext.fetch(FetchDescriptor<OPDBMachine>(predicate: #Predicate { $0.ipdbId == value }))
        let best = rows.min { Self.entryTypeRank($0.entryType) < Self.entryTypeRank($1.entryType) }
        return try best.map { try $0.decodedMachine() }
    }

    func machines(ids: [String]) throws -> [Machine] {
        guard !ids.isEmpty else { return [] }
        let rows = try modelContext.fetch(FetchDescriptor<OPDBMachine>(predicate: #Predicate { ids.contains($0.opdbId) }))
        var byID: [String: Machine] = [:]
        for row in rows {
            byID[row.opdbId] = try row.decodedMachine()
        }
        return ids.compactMap { byID[$0] }
    }

    func details(id: String) throws -> MachineDetails? {
        guard let machine = try self.machine(id: id) else { return nil }

        var group: Machine?
        if machine.entryType != .machineGroup, let groupID = machine.opdbGroup, groupID != machine.opdbId {
            group = try self.machine(id: groupID)
        }

        var parent: Machine?
        if machine.entryType == .alias, let parentID = machine.opdbMachine, parentID != machine.opdbId {
            parent = try self.machine(id: parentID)
        }

        let selfID = machine.opdbId
        let groupRaw = EntryType.machineGroup.rawValue
        let aliasRaw = EntryType.alias.rawValue

        var variants: [MachineSummary] = []
        if let groupID = machine.opdbGroup {
            let groupValue: String? = groupID
            var descriptor = FetchDescriptor<OPDBMachine>(predicate: #Predicate {
                $0.opdbGroup == groupValue && $0.entryTypeRaw != groupRaw && $0.opdbId != selfID
            })
            descriptor.propertiesToFetch = OPDBMachine.listProperties
            variants = Self.sorted(try modelContext.fetch(descriptor), by: .yearAscending, terms: []).map(\.summary)
        }

        var aliases: [MachineSummary] = []
        if machine.entryType == .machine {
            let machineValue: String? = selfID
            var descriptor = FetchDescriptor<OPDBMachine>(predicate: #Predicate {
                $0.opdbMachine == machineValue && $0.entryTypeRaw == aliasRaw && $0.opdbId != selfID
            })
            descriptor.propertiesToFetch = OPDBMachine.listProperties
            aliases = Self.sorted(try modelContext.fetch(descriptor), by: .name, terms: []).map(\.summary)
        }

        return MachineDetails(machine: machine, group: group, parentMachine: parent, variants: variants, aliases: aliases)
    }

    // MARK: - Suche

    func search(text: String, filter: SearchFilter, sort: SearchSort, limit: Int, offset: Int) throws -> [MachineSummary] {
        let terms = SearchText.tokens(text)
        let limit = max(limit, 0)
        let offset = max(offset, 0)

        // Schneller Weg: kein Suchtext, nur Eintragsart-Filter, alphabetisch → Paging direkt in der Datenbank.
        if terms.isEmpty, !Self.needsInMemoryFiltering(filter), sort == .name || sort == .relevance {
            var descriptor = Self.descriptor(needle: nil, entryTypes: filter.entryTypes)
            descriptor.sortBy = [SortDescriptor(\OPDBMachine.nameSort, comparator: .localizedStandard)]
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
            return try modelContext.fetch(descriptor).map(\.summary)
        }

        // 1. Wortanfänge („addams fam“), 2. Fallback: beliebige Teilstrings („eatles“).
        var rows = try candidates(terms: terms, wordPrefix: true, filter: filter)
        if rows.isEmpty, !terms.isEmpty, offset == 0 {
            rows = try candidates(terms: terms, wordPrefix: false, filter: filter)
        }

        let sortedRows = Self.sorted(rows, by: sort, terms: terms)
        guard offset < sortedRows.count, limit > 0 else { return [] }
        return sortedRows[offset..<min(sortedRows.count, offset + limit)].map(\.summary)
    }

    private func candidates(terms: [String], wordPrefix: Bool, filter: SearchFilter) throws -> [OPDBMachine] {
        let needles = terms.map { wordPrefix ? " " + $0 : $0 }
        // Der längste Begriff wird in der Datenbank gefiltert, die übrigen im Speicher.
        let longest = needles.max { $0.count < $1.count }
        let rows = try modelContext.fetch(Self.descriptor(needle: longest, entryTypes: filter.entryTypes))
        return rows.filter { row in
            needles.allSatisfy { row.searchText.contains($0) } && Self.matches(row, filter)
        }
    }

    private static func descriptor(needle: String?, entryTypes: Set<EntryType>) -> FetchDescriptor<OPDBMachine> {
        let types = entryTypes.map(\.rawValue)
        var descriptor = FetchDescriptor<OPDBMachine>()
        if let needle {
            if types.isEmpty {
                descriptor.predicate = #Predicate { $0.searchText.contains(needle) }
            } else {
                descriptor.predicate = #Predicate { types.contains($0.entryTypeRaw) && $0.searchText.contains(needle) }
            }
        } else if !types.isEmpty {
            descriptor.predicate = #Predicate { types.contains($0.entryTypeRaw) }
        }
        descriptor.propertiesToFetch = OPDBMachine.listProperties
        return descriptor
    }

    private static func needsInMemoryFiltering(_ filter: SearchFilter) -> Bool {
        !filter.manufacturerIds.isEmpty || filter.years != nil || !filter.types.isEmpty
            || !filter.displays.isEmpty || filter.physicalMachinesOnly
    }

    private static func matches(_ row: OPDBMachine, _ filter: SearchFilter) -> Bool {
        if !filter.manufacturerIds.isEmpty {
            guard let id = row.manufacturerId, filter.manufacturerIds.contains(id) else { return false }
        }
        if let years = filter.years {
            guard let year = row.year, years.contains(year) else { return false }
        }
        if !filter.types.isEmpty {
            guard let type = row.type, filter.types.contains(type) else { return false }
        }
        if !filter.displays.isEmpty {
            guard let display = row.display, filter.displays.contains(display) else { return false }
        }
        if filter.physicalMachinesOnly, !row.physicalMachine {
            return false
        }
        return true
    }

    // MARK: - Sortierung

    static func sorted(_ rows: [OPDBMachine], by sort: SearchSort, terms: [String]) -> [OPDBMachine] {
        func byName(_ a: OPDBMachine, _ b: OPDBMachine) -> Bool {
            a.nameSort.localizedStandardCompare(b.nameSort) == .orderedAscending
        }
        func byYear(_ a: OPDBMachine, _ b: OPDBMachine, ascending: Bool) -> Bool {
            switch (a.year, b.year) {
            case let (x?, y?) where x != y: return ascending ? x < y : x > y
            case (nil, .some): return false
            case (.some, nil): return true
            default: return byName(a, b)
            }
        }

        switch sort {
        case .relevance where !terms.isEmpty:
            let ranked = rows.map { ($0, relevance(of: $0, terms: terms)) }
            return ranked
                .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : byName($0.0, $1.0) }
                .map(\.0)
        case .relevance, .name:
            return rows.sorted(by: byName)
        case .yearAscending:
            return rows.sorted { byYear($0, $1, ascending: true) }
        case .yearDescending:
            return rows.sorted { byYear($0, $1, ascending: false) }
        }
    }

    /// 0 = exakter Treffer auf Name/Kurzname, 1 = Name beginnt mit Suchtext,
    /// 2 = alle Begriffe sind Wortanfänge im Namen, 3 = sonstiger Treffer (Hersteller, Personen …).
    private static func relevance(of row: OPDBMachine, terms: [String]) -> Int {
        let query = terms.joined(separator: " ")
        let name = SearchText.fold(row.name)
        let alternatives = [row.shortName, row.commonName].compactMap { $0.map(SearchText.fold) }
        if name == query || alternatives.contains(query) { return 0 }
        if name.hasPrefix(query) { return 1 }
        let nameTokens = name.split(separator: " ")
        if terms.allSatisfy({ term in nameTokens.contains { $0.hasPrefix(term) } }) { return 2 }
        return 3
    }

    private static func entryTypeRank(_ type: EntryType) -> Int {
        switch type {
        case .machine: return 0
        case .alias: return 1
        default: return 2
        }
    }

    // MARK: - Hersteller & Status

    func manufacturers() throws -> [ManufacturerInfo] {
        let machineRaw = EntryType.machine.rawValue
        var descriptor = FetchDescriptor<OPDBMachine>(predicate: #Predicate {
            $0.entryTypeRaw == machineRaw && $0.manufacturerId != nil
        })
        descriptor.propertiesToFetch = [\OPDBMachine.manufacturerId, \OPDBMachine.manufacturerName, \OPDBMachine.manufacturerFullName]

        var byID: [Int: (name: String, fullName: String?, count: Int)] = [:]
        for row in try modelContext.fetch(descriptor) {
            guard let id = row.manufacturerId else { continue }
            var entry = byID[id] ?? (row.manufacturerName ?? "?", row.manufacturerFullName, 0)
            entry.count += 1
            byID[id] = entry
        }
        return byID
            .map { ManufacturerInfo(manufacturer: Manufacturer(manufacturerId: $0.key, name: $0.value.name, fullName: $0.value.fullName),
                                    machineCount: $0.value.count) }
            .sorted { $0.manufacturer.name.localizedStandardCompare($1.manufacturer.name) == .orderedAscending }
    }

    func entryCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<OPDBMachine>())
    }

    func dataInfo() throws -> DataInfo {
        let state = try modelContext.syncState()
        return DataInfo(
            entryCount: try entryCount(),
            source: state.sourceRaw.flatMap(DataSource.init(rawValue:)),
            etag: state.etag,
            lastModified: state.lastModified,
            lastImport: state.lastImport,
            lastCheck: state.lastCheck
        )
    }

    func markChecked(at date: Date) throws {
        let state = try modelContext.syncState()
        state.lastCheck = date
        try modelContext.save()
    }

    // MARK: - Hilfen

    private func entity(id: String) throws -> OPDBMachine? {
        var descriptor = FetchDescriptor<OPDBMachine>(predicate: #Predicate { $0.opdbId == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
