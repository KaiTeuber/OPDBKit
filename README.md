# OPDBKit

A Swift package that downloads the data of the [Open Pinball Database (OPDB)](https://opdb.org), stores it
locally with **SwiftData**, and provides a search and detail API.

Data source: `https://mp-data.sfo3.cdn.digitaloceanspaces.com/opdb-v2.json`

- **No dependencies** – just Foundation and SwiftData.
- **Automatic update on open** via conditional HTTP requests (`ETag` / `Last-Modified`).
  If nothing has changed, the server responds with `304` and nothing is downloaded.
- **Incremental import** – entries are matched by `opdbId`; only new, changed
  (`updatedAt`) and removed entries are written. Everything is committed with a single `save()`;
  if an error occurs, the previous state is kept.
- **Background contexts** (`@ModelActor`) for reading and importing – the app can keep searching during an update.
- **SwiftUI-ready** – `opdb.modelContainer` can be used directly with `@Query`.
- **Lenient decoding** – malformed individual entries are skipped instead of aborting the import.
- iOS 17+ / macOS 14+, Swift 5.9+ (Xcode 15+).

## Installation

In Xcode: *File → Add Package Dependencies…*, enter the URL `https://github.com/KaiTeuber/OPDBKit.git`
and add `OPDBKit` to your app target.

In another Swift package via `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/KaiTeuber/OPDBKit.git", from: "0.1.0")
],
targets: [
    .target(name: "MyTarget", dependencies: ["OPDBKit"])
]
```

## Usage

```swift
import OPDBKit

// Open – automatically checks for a new version.
// First launch (empty database): waits for the download. Afterwards: the check runs in the background.
let opdb = try await OPDB.open()

// Search (prefix search across name, short name, manufacturer, people, features, IPDB ID …)
let hits = try await opdb.search("addams fam")
for hit in hits {
    print(hit.name, hit.year ?? 0, hit.manufacturerName ?? "")
}

// Search with filter & sorting
let nineties = try await opdb.search(
    "",
    filter: SearchFilter(manufacturerIds: [12], years: 1990...1999),
    sort: .yearAscending,
    limit: 100
)

// All details of a machine
if let details = try await opdb.details(for: "G0l8P-M85d9") {
    let machine = details.machine
    print(machine.name, machine.manufacturer?.fullName ?? "")
    print(machine.primaryImage?.largeURL as Any)
    print(machine.people.map(\.name), machine.features.map(\.name))
    print("Group:", details.group?.name ?? "–")
    print("Variants:", details.variants.map(\.name))
    print("Aliases:", details.aliases.map(\.name))
}

// More lookups
let machine = try await opdb.machine(id: "G0l2e-Mp4Oz")
let byIPDB = try await opdb.machine(ipdbId: 2619)
let collection = try await opdb.machines(ids: myCollectionIDs)
let manufacturers = try await opdb.manufacturers()      // for filter UIs
let info = try await opdb.dataInfo()                    // count, import date, ETag …
```

### Triggering and observing updates manually

```swift
let result = try await opdb.updateIfNeeded()            // .upToDate / .updated(summary) / .skipped
let forced = try await opdb.updateIfNeeded(force: true) // always reload
let available = try await opdb.isUpdateAvailable()      // check only (HEAD), download nothing

Task {
    for await status in await opdb.statusUpdates() {
        // .idle, .checking, .downloading, .importing, .finished(result), .failed(message)
    }
}
```

### Configuration

```swift
let configuration = OPDBConfiguration(
    storeLocation: .applicationSupport, // or .file(url) / .inMemory (previews)
    checkForUpdatesOnOpen: true,
    minimumCheckInterval: 60 * 60,    // check at most once per hour (default: 0 = on every open)
    seedFileURL: Bundle.main.url(forResource: "opdb-v2", withExtension: "json") // optional offline seed data
)
let opdb = try await OPDB.open(configuration: configuration)
```

### SwiftUI with `@Query`

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

Note: the container holds only the OPDB models. Your app's own SwiftData models (e.g. a
collection) belong in a separate container and reference machines by their `opdbId`.
The `OPDB` API is meant for ranked search and details; `@Query` is suited for simple lists.

## Data model

| Type | Contents |
|---|---|
| `OPDBMachine` | SwiftData `@Model` with the search/list fields and the complete entry (`.machine`) |
| `Machine` | Complete entry: IDs, names, year, manufacture date, type (EM/SS), display, player count, manufacturer, IPDB ID, links (rulesheet, Pinball Cards, competition notes …), images, people, features, keywords |
| `MachineSummary` | Compact search result incl. thumbnail URL |
| `MachineDetails` | `Machine` + group, parent machine (for aliases), variants, aliases |
| `EntryType` | `.machineGroup` (title across all editions), `.machine` (specific machine), `.alias` (variant with its own name) |

By default, search returns only `.machine` and `.alias` – so a title doesn't appear twice as both group
and machine. Use `SearchFilter.groupsOnly` or `.all` to change this.

## Localization

The package is localized in English (source language) and German; the strings live in
`Sources/OPDBKit/Resources/Localizable.xcstrings`.

- Error messages from `OPDBError` (`error.localizedDescription`) appear in the app's language.
- `MachineType`, `DisplayType` and `EntryType` provide a human-readable label via `localizedName`,
  e.g. `machine.type?.localizedName` → “Electro-mechanical” or „Elektromechanisch“.

The database content itself (names, descriptions, features) comes unchanged from opdb.org
and is in English.

## Technical details

- `OPDBMachine` stores filter/sort fields as attributes and the complete entry as JSON.
  List queries don't load the JSON (`propertiesToFetch`).
- Search: normalized search index (lowercased, without diacritics). The longest search term is filtered in
  the database via `#Predicate`, the remaining terms and filters in memory; then results are ranked
  (exact name/short name → name starts with … → word prefixes in the name → other matches).
  If there are no matches, a substring search follows. Alphabetical browsing without search text runs entirely in the database.
- If the store becomes incompatible after a model change, it is deleted, recreated and reloaded.
- No CloudKit sync (`cloudKitDatabase: .none`); the store lives in *Application Support* and is excluded
  from iCloud backup.

## Example app

`Examples/OPDBExample/OPDBExample.xcodeproj` contains an Xcode project with a small SwiftUI app (iOS 17+) that:

- loads the current machine list on launch (first launch: download, afterwards update check in the background),
- shows all machines with thumbnail, manufacturer and year,
- filters the list via the search field at the top,
- shows all information for a machine in a table when tapped (general, technical, manufacturer,
  people, features, links, images, group/variants/aliases, metadata),
- checks for a new data version on pull-to-refresh.

To run it: open `Examples/OPDBExample/OPDBExample.xcodeproj` in Xcode (15+), choose an iOS simulator and
run (⌘R). For a real device, select a team under *Signing & Capabilities*.
OPDBKit is included as a local package (`../..`) – changes to the package take effect immediately.
(Don't open the main package in a second Xcode window at the same time.)

```
Examples/OPDBExample/
├── OPDBExample.xcodeproj
└── OPDBExample/
    ├── OPDBExampleApp.swift      App entry point
    ├── MachineListModel.swift    Loading, search, update status (@Observable)
    ├── MachineListView.swift     List with search field
    ├── MachineDetailView.swift   Tabular detail view
    ├── Labels.swift              German labels for OPDB codes
    └── Assets.xcassets
```

## Tests

```bash
swift test
```

The tests run against a mock network and a small fixture file (no real downloads).

## Data license

The OPDB data comes from opdb.org. Please respect their terms of use and credit the source in your app.

## License

The OPDBKit code is released under the [MIT License](LICENSE). The OPDB data is subject to the terms of opdb.org (see above).
