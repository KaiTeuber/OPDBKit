import Foundation

/// Dekodiert `opdb-v2.json` tolerant: fehlerhafte Einträge und doppelte IDs werden übersprungen.
enum EntryDecoder {
    private struct EntriesContainer: Decodable {
        let entries: [Lossy<Machine>]
    }

    static func decode(from data: Data) throws -> (machines: [Machine], skipped: Int) {
        let decoder = JSONDecoder()
        let lossy: [Lossy<Machine>]
        do {
            lossy = try decoder.decode(EntriesContainer.self, from: data).entries
        } catch let containerError {
            // Fallback, falls die Datei künftig direkt ein Array liefert.
            guard let array = try? decoder.decode([Lossy<Machine>].self, from: data) else {
                throw OPDBError.decoding(String(describing: containerError))
            }
            lossy = array
        }

        var seen = Set<String>()
        var machines: [Machine] = []
        machines.reserveCapacity(lossy.count)
        var skipped = 0
        for item in lossy {
            guard let machine = item.value, seen.insert(machine.opdbId).inserted else {
                skipped += 1
                continue
            }
            machines.append(machine)
        }
        return (machines, skipped)
    }
}
