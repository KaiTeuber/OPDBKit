# OPDBKit

Swift Package, das die Daten der [Open Pinball Database (OPDB)](https://opdb.org) lädt, lokal mit
**SwiftData** speichert und eine Such- und Detail-API bereitstellt.

Datenquelle: `https://mp-data.sfo3.cdn.digitaloceanspaces.com/opdb-v2.json`

- **Keine Abhängigkeiten** – nur Foundation und SwiftData.
- **Automatisches Update beim Öffnen** über bedingte HTTP-Anfragen (`ETag` / `Last-Modified`).
  Ist nichts neu, antwortet der Server mit `304` und es wird nichts heruntergeladen.
- **Inkrementeller Import** – Einträge werden per `opdbId` abgeglichen; nur neue, geänderte
  (`updatedAt`) und entfernte Einträge werden geschrieben. Alles wird mit einem einzigen `save()`
  übernommen; bei einem Fehler bleibt der alte Stand erhalten.
- **Hintergrund-Kontexte** (`@ModelActor`) für Lesen und Import – die App kann während eines Updates weiter suchen.
- **SwiftUI-tauglich** – `opdb.modelContainer` lässt sich direkt für `@Query` verwenden.
- **Tolerantes Decoding** – fehlerhafte Einzeleinträge werden übersprungen statt den Import abzubrechen.
- iOS 17+ / macOS 14+, Swift 5.9+ (Xcode 15+).

## Einbinden

In Xcode: *File → Add Package Dependencies…*, die URL `https://github.com/KaiTeuber/OPDBKit.git`
eingeben und `OPDBKit` zum App-Target hinzufügen.

In einem anderen Swift Package über `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/KaiTeuber/OPDBKit.git", from: "0.1.0")
],
targets: [
    .target(name: "MyTarget", dependencies: ["OPDBKit"])
]
```

## Verwendung

```swift
import OPDBKit

// Öffnen – prüft automatisch auf eine neue Version.
// Erster Start (leere DB): wartet auf den Download. Danach: Prüfung läuft im Hintergrund.
let opdb = try await OPDB.open()

// Suche (Präfixsuche über Name, Kurzname, Hersteller, Personen, Features, IPDB-ID …)
let hits = try await opdb.search("addams fam")
for hit in hits {
    print(hit.name, hit.year ?? 0, hit.manufacturerName ?? "")
}

// Suche mit Filter & Sortierung
let nineties = try await opdb.search(
    "",
    filter: SearchFilter(manufacturerIds: [12], years: 1990...1999),
    sort: .yearAscending,
    limit: 100
)

// Alle Details eines Geräts
if let details = try await opdb.details(for: "G0l8P-M85d9") {
    let machine = details.machine
    print(machine.name, machine.manufacturer?.fullName ?? "")
    print(machine.primaryImage?.largeURL as Any)
    print(machine.people.map(\.name), machine.features.map(\.name))
    print("Gruppe:", details.group?.name ?? "–")
    print("Varianten:", details.variants.map(\.name))
    print("Aliase:", details.aliases.map(\.name))
}

// Weitere Abrufe
let machine = try await opdb.machine(id: "G0l2e-Mp4Oz")
let byIPDB = try await opdb.machine(ipdbId: 2619)
let collection = try await opdb.machines(ids: myCollectionIDs)
let manufacturers = try await opdb.manufacturers()      // für Filter-UIs
let info = try await opdb.dataInfo()                    // Anzahl, Importzeitpunkt, ETag …
```

### Updates manuell auslösen / beobachten

```swift
let result = try await opdb.updateIfNeeded()            // .upToDate / .updated(summary) / .skipped
let forced = try await opdb.updateIfNeeded(force: true) // immer neu laden
let available = try await opdb.isUpdateAvailable()      // nur prüfen (HEAD), nichts laden

Task {
    for await status in await opdb.statusUpdates() {
        // .idle, .checking, .downloading, .importing, .finished(result), .failed(message)
    }
}
```

### Konfiguration

```swift
let configuration = OPDBConfiguration(
    storeLocation: .applicationSupport, // oder .file(url) / .inMemory (Previews)
    checkForUpdatesOnOpen: true,
    minimumCheckInterval: 60 * 60,    // höchstens stündlich prüfen (Standard: 0 = bei jedem Öffnen)
    seedFileURL: Bundle.main.url(forResource: "opdb-v2", withExtension: "json") // optionaler Offline-Startbestand
)
let opdb = try await OPDB.open(configuration: configuration)
```

### SwiftUI mit `@Query`

```swift
@main
struct PinPitchApp: App {
    @State private var opdb: OPDB?

    var body: some Scene {
        WindowGroup {
            if let opdb {
                MachineList().modelContainer(opdb.modelContainer)
            } else {
                ProgressView().task { opdb = try? await OPDB.open() }
            }
        }
    }
}

struct MachineList: View {
    @Query(filter: #Predicate<OPDBMachine> { $0.entryTypeRaw == "machine" },
           sort: \OPDBMachine.nameSort)
    private var machines: [OPDBMachine]

    var body: some View {
        List(machines) { Text($0.name) }
    }
}
```

Hinweis: Der Container enthält nur die OPDB-Modelle. Eigene SwiftData-Modelle der App (z. B. die
Sammlung) gehören in einen eigenen Container und referenzieren Geräte über die `opdbId`.
Für Suche mit Ranking und Details ist die `OPDB`-API gedacht; `@Query` eignet sich für einfache Listen.

## Datenmodell

| Typ | Inhalt |
|---|---|
| `OPDBMachine` | SwiftData-`@Model` mit den Such-/Listenfeldern und dem vollständigen Eintrag (`.machine`) |
| `Machine` | Vollständiger Eintrag: IDs, Namen, Jahr, Herstellungsdatum, Typ (EM/SS), Display, Spielerzahl, Hersteller, IPDB-ID, Links (Rulesheet, Pinball Cards, Competition Notes …), Bilder, Personen, Features, Keywords |
| `MachineSummary` | Kompaktes Suchergebnis inkl. Vorschaubild-URL |
| `MachineDetails` | `Machine` + Gruppe, Eltern-Gerät (bei Alias), Varianten, Aliase |
| `EntryType` | `.machineGroup` (Titel über alle Editionen), `.machine` (konkretes Gerät), `.alias` (Variante mit eigenem Namen) |

Standardmäßig liefert die Suche nur `.machine` und `.alias` – ein Titel erscheint dadurch nicht doppelt als Gruppe
und Gerät. Mit `SearchFilter.groupsOnly` bzw. `.all` lässt sich das ändern.

## Lokalisierung

Das Package ist auf Englisch (Ausgangssprache) und Deutsch lokalisiert; die Texte liegen in
`Sources/OPDBKit/Resources/Localizable.xcstrings`.

- Fehlermeldungen von `OPDBError` (`error.localizedDescription`) erscheinen in der Sprache der App.
- `MachineType`, `DisplayType` und `EntryType` liefern über `localizedName` eine lesbare Bezeichnung,
  z. B. `machine.type?.localizedName` → „Elektromechanisch“ bzw. “Electro-mechanical”.

Die Inhalte der Datenbank selbst (Namen, Beschreibungen, Features) kommen unverändert von opdb.org
und sind englisch.

## Technische Details

- `OPDBMachine` speichert Filter-/Sortierfelder als Attribute und den kompletten Eintrag als JSON.
  Listenabfragen laden das JSON nicht mit (`propertiesToFetch`).
- Suche: normalisierter Suchindex (klein, ohne Akzente). Der längste Suchbegriff wird per `#Predicate`
  in der Datenbank gefiltert, die übrigen Begriffe und Filter im Speicher; danach Ranking
  (exakter Name/Kurzname → Name beginnt mit … → Wortanfänge im Namen → sonstige Treffer).
  Ohne Treffer folgt eine Teilstring-Suche. Alphabetisches Blättern ohne Suchtext läuft komplett in der Datenbank.
- Ist der Store nach einer Modelländerung inkompatibel, wird er gelöscht, neu angelegt und neu geladen.
- Kein CloudKit-Sync (`cloudKitDatabase: .none`); der Store liegt in *Application Support* und ist vom
  iCloud-Backup ausgeschlossen.

## Beispiel-App

Unter `Examples/OPDBExample/OPDBExample.xcodeproj` liegt ein Xcode-Projekt mit einer kleinen SwiftUI-App (iOS 17+):

- lädt beim Start die aktuelle Geräteliste (erster Start: Download, danach Update-Prüfung im Hintergrund),
- zeigt alle Geräte mit Vorschaubild, Hersteller und Jahr,
- filtert die Liste über das Suchfeld oben,
- zeigt beim Antippen eines Geräts alle Informationen tabellarisch (Allgemein, Technik, Hersteller,
  Personen, Features, Links, Bilder, Gruppe/Varianten/Aliase, Metadaten),
- Pull-to-Refresh prüft auf eine neue Datenversion.

Starten: `Examples/OPDBExample/OPDBExample.xcodeproj` in Xcode (15+) öffnen, einen iOS-Simulator wählen und
ausführen (⌘R). Für ein echtes Gerät unter *Signing & Capabilities* ein Team wählen.
OPDBKit ist als lokales Package (`../..`) eingebunden – Änderungen am Package wirken sich sofort aus.
(Das Haupt-Package nicht gleichzeitig in einem zweiten Xcode-Fenster öffnen.)

```
Examples/OPDBExample/
├── OPDBExample.xcodeproj
└── OPDBExample/
    ├── OPDBExampleApp.swift      App-Einstieg
    ├── MachineListModel.swift    Laden, Suche, Update-Status (@Observable)
    ├── MachineListView.swift     Liste mit Suchfeld
    ├── MachineDetailView.swift   Tabellarische Detailansicht
    ├── Labels.swift              Deutsche Bezeichnungen für OPDB-Codes
    └── Assets.xcassets
```

## Tests

```bash
swift test
```

Die Tests laufen mit einem Mock-Netzwerk und einer kleinen Fixture-Datei (keine echten Downloads).

## Lizenz der Daten

Die OPDB-Daten stammen von opdb.org. Bitte die dortigen Nutzungsbedingungen beachten und die Quelle in der App nennen.

## Lizenz

Der Code von OPDBKit steht unter der [MIT-Lizenz](LICENSE). Für die OPDB-Daten gelten die Bedingungen von opdb.org (siehe oben).
