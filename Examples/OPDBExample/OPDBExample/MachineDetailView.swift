import SwiftUI
import OPDBKit

/// Lädt die Details eines Geräts und zeigt sie tabellarisch an.
struct MachineDetailView: View {
    let opdb: OPDB
    let machineID: String

    @State private var details: MachineDetails?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let details {
                MachineDetailTable(details: details)
            } else if let errorMessage {
                ContentUnavailableView("Fehler", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(details?.machine.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: machineID) {
            do {
                details = try await opdb.details(for: machineID)
                if details == nil { errorMessage = "Eintrag \(machineID) nicht gefunden." }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct MachineDetailTable: View {
    let details: MachineDetails
    private var machine: Machine { details.machine }

    var body: some View {
        List {
            if let url = machine.primaryImage?.largeURL ?? machine.primaryImage?.mediumURL {
                Section {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                }
            }

            Section("Allgemein") {
                row("Name", machine.name)
                row("Kurzname", machine.shortName)
                row("Gebräuchlicher Name", machine.commonName)
                row("Sortiername", machine.nameSort)
                row("Eintragsart", machine.entryType.label)
                row("OPDB-ID", machine.opdbId)
                row("Gruppen-ID", machine.opdbGroup)
                row("Geräte-ID", machine.opdbMachine)
                row("IPDB-ID", machine.ipdbId.map { String($0) })
            }

            Section("Technik") {
                row("Jahr", machine.year.map { String($0) })
                row("Herstellungsdatum", machine.manufactureDateValue?.formatted(date: .long, time: .omitted) ?? machine.manufactureDate)
                row("Bauart", machine.type?.label)
                row("Display", machine.display?.label)
                row("Spieler", machine.playerCount.map { String($0) })
                row("Physisches Gerät", machine.physicalMachine ? "Ja" : "Nein")
            }

            Section("Hersteller") {
                row("Name", machine.manufacturer?.name)
                row("Vollständiger Name", machine.manufacturer?.fullName)
                row("Hersteller-ID", machine.manufacturerId.map { String($0) })
            }

            if let description = machine.description {
                Section("Beschreibung") {
                    Text(description)
                }
            }

            Section("Personen") {
                if machine.people.isEmpty {
                    empty
                } else {
                    ForEach(Array(machine.people.enumerated()), id: \.offset) { _, person in
                        row(person.role?.capitalized ?? "Person", person.name)
                    }
                }
            }

            Section("Features") {
                if machine.features.isEmpty {
                    empty
                } else {
                    ForEach(Array(machine.features.enumerated()), id: \.offset) { _, feature in
                        row(feature.group?.capitalized ?? "Feature", feature.name)
                    }
                }
            }

            Section("Keywords") {
                if machine.keywords.isEmpty {
                    empty
                } else {
                    Text(machine.keywords.joined(separator: ", "))
                }
            }

            Section("Links") {
                link("Rulesheet", machine.rulesheetURL)
                link("Pinball Primer", machine.pinballPrimerURL)
                link("Pinball Cards", machine.pinballCardsURL)
                link("Bob's Guide", machine.bobsGuideURL)
                link("Competition Setup", machine.competitionSetupURL)
                link("Competition Notes", machine.competitionNotesURL)
                link("IPDB", machine.ipdbURL)
                link("OPDB", machine.opdbURL)
            }

            Section("Bilder") {
                if machine.images.isEmpty {
                    empty
                } else {
                    ForEach(Array(machine.images.enumerated()), id: \.offset) { _, image in
                        ImageRow(image: image)
                    }
                }
            }

            if let group = details.group {
                Section("Gruppe") {
                    NavigationLink(value: group.opdbId) {
                        row(group.entryType.label, group.name)
                    }
                }
            }

            if let parent = details.parentMachine {
                Section("Alias von") {
                    NavigationLink(value: parent.opdbId) {
                        row(parent.year.map { String($0) } ?? "–", parent.name)
                    }
                }
            }

            if !details.variants.isEmpty {
                Section("Varianten (\(details.variants.count))") {
                    ForEach(details.variants) { variant in
                        NavigationLink(value: variant.id) {
                            MachineRow(machine: variant)
                        }
                    }
                }
            }

            if !details.aliases.isEmpty {
                Section("Aliase (\(details.aliases.count))") {
                    ForEach(details.aliases) { alias in
                        NavigationLink(value: alias.id) {
                            MachineRow(machine: alias)
                        }
                    }
                }
            }

            Section("Metadaten") {
                row("Erstellt", machine.createdDate?.formatted(date: .abbreviated, time: .shortened) ?? machine.createdAt)
                row("Aktualisiert", machine.updatedDate?.formatted(date: .abbreviated, time: .shortened) ?? machine.updatedAt)
                row("Competition Notes", machine.hasCompetitionNotes ? "Ja" : "Nein")
                row("Competition Setup", machine.hasCompetitionSetup ? "Ja" : "Nein")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ label: String, _ value: String?) -> some View {
        LabeledContent(label) {
            Text(value ?? "–")
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func link(_ label: String, _ url: URL?) -> some View {
        if let url {
            LabeledContent(label) {
                Link(url.host() ?? "Öffnen", destination: url)
            }
        } else {
            row(label, nil)
        }
    }

    private var empty: some View {
        Text("–").foregroundStyle(.secondary)
    }
}

private struct ImageRow: View {
    let image: MachineImage

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: image.smallURL) { loaded in
                loaded.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.1)
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text((image.title ?? image.type ?? "Bild").capitalized)
                    .font(.body)
                if let size = image.sizes?.large {
                    Text("\(size.width) × \(size.height)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if image.primary {
                    Text("Hauptbild")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }

            Spacer()

            if let url = image.largeURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                }
            }
        }
    }
}
