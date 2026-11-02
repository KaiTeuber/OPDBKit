import Foundation
import SwiftData

/// Importiert eine `opdb-v2.json` in SwiftData – auf einem eigenen Hintergrund-Kontext.
///
/// Der Import ist inkrementell: Einträge werden über `opdbId` abgeglichen, und nur neue,
/// geänderte (anderes `updatedAt`) oder entfernte Einträge werden geschrieben bzw. gelöscht.
/// Alles wird mit einem einzigen `save()` übernommen; bei einem Fehler wird zurückgerollt
/// und der bisherige Stand bleibt erhalten.
@ModelActor
actor ImportStore {

    func importFile(at fileURL: URL, source: DataSource, etag: String?, lastModified: String?) throws -> ImportSummary {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let (machines, skipped) = try EntryDecoder.decode(from: data)
        guard !machines.isEmpty else { throw OPDBError.emptyDataset }

        let context = modelContext
        context.autosaveEnabled = false
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            let state = try context.syncState()
            let rewriteAll = state.formatVersion != StoreFormat.version

            var existingDescriptor = FetchDescriptor<OPDBMachine>()
            existingDescriptor.propertiesToFetch = [\OPDBMachine.opdbId, \OPDBMachine.updatedAt]
            var existing: [String: OPDBMachine] = [:]
            for row in try context.fetch(existingDescriptor) {
                if existing[row.opdbId] == nil {
                    existing[row.opdbId] = row
                } else {
                    context.delete(row)
                }
            }

            var inserted = 0
            var updated = 0
            var unchanged = 0
            for machine in machines {
                if let row = existing.removeValue(forKey: machine.opdbId) {
                    if rewriteAll || machine.updatedAt == nil || row.updatedAt != machine.updatedAt {
                        try row.update(from: machine, encoder: encoder)
                        updated += 1
                    } else {
                        unchanged += 1
                    }
                } else {
                    context.insert(try OPDBMachine(machine: machine, encoder: encoder))
                    inserted += 1
                }
            }

            let deleted = existing.count
            for row in existing.values {
                context.delete(row)
            }

            let now = Date()
            state.etag = etag
            state.lastModified = lastModified
            state.sourceRaw = source.rawValue
            state.entryCount = machines.count
            state.skippedCount = skipped
            state.lastImport = now
            state.lastCheck = now
            state.formatVersion = StoreFormat.version

            try context.save()

            return ImportSummary(
                importedCount: machines.count,
                insertedCount: inserted,
                updatedCount: updated,
                deletedCount: deleted,
                unchangedCount: unchanged,
                skippedCount: skipped,
                etag: etag,
                lastModified: lastModified,
                source: source
            )
        } catch {
            context.rollback()
            throw error
        }
    }
}
