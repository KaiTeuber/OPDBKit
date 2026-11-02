import Foundation
import Observation
import OPDBKit

/// Lädt die Datenbank, beobachtet Updates und liefert die (gefilterte) Geräteliste.
@MainActor
@Observable
final class MachineListModel {
    private(set) var opdb: OPDB?
    private(set) var machines: [MachineSummary] = []
    private(set) var status: UpdateStatus = .idle
    private(set) var info: DataInfo?
    private(set) var errorMessage: String?
    private(set) var isOpening = false

    var searchText = ""

    /// Öffnet OPDBKit. Beim ersten Start wird die aktuelle Liste heruntergeladen,
    /// danach prüft OPDBKit im Hintergrund auf eine neuere Version.
    func start() async {
        guard opdb == nil, !isOpening else { return }
        isOpening = true
        errorMessage = nil
        defer { isOpening = false }

        do {
            let opdb = try await OPDB.open()
            self.opdb = opdb
            observeStatus(of: opdb)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Liste neu laden – mit aktuellem Suchtext.
    func reload() async {
        guard let opdb else { return }
        let text = searchText
        do {
            let result = try await opdb.search(
                text,
                sort: text.isEmpty ? .name : .relevance,
                limit: 100_000
            )
            // Nur übernehmen, wenn sich der Suchtext inzwischen nicht geändert hat.
            guard text == searchText else { return }
            machines = result
            info = try await opdb.dataInfo()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Pull-to-Refresh: auf eine neuere Version prüfen.
    func refresh() async {
        guard let opdb else {
            await start()
            return
        }
        do {
            try await opdb.updateIfNeeded(force: false)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func observeStatus(of opdb: OPDB) {
        Task { [weak self] in
            for await status in await opdb.statusUpdates() {
                guard let self else { return }
                self.status = status
                // Nach einem Hintergrund-Update die Liste aktualisieren.
                if case .finished(.updated) = status {
                    await self.reload()
                }
            }
        }
    }

    var statusText: String {
        switch status {
        case .idle: return ""
        case .checking: return "Prüfe auf Updates …"
        case .downloading: return "Lade Daten …"
        case .importing: return "Importiere …"
        case .finished(.upToDate): return "Daten sind aktuell"
        case .finished(.skipped): return ""
        case .finished(.updated(let summary)):
            return "Aktualisiert: \(summary.insertedCount) neu, \(summary.updatedCount) geändert, \(summary.deletedCount) entfernt"
        case .failed(let message): return "Update fehlgeschlagen: \(message)"
        }
    }

    var isBusy: Bool {
        switch status {
        case .checking, .downloading, .importing: return true
        default: return false
        }
    }
}
