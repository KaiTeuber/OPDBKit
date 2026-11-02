import SwiftUI
import OPDBKit

struct MachineListView: View {
    @Bindable var model: MachineListModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Flipper")
                .navigationDestination(for: String.self) { machineID in
                    if let opdb = model.opdb {
                        MachineDetailView(opdb: opdb, machineID: machineID)
                    }
                }
                .searchable(text: $model.searchText, prompt: "Name, Hersteller, Designer …")
                .autocorrectionDisabled()
                .task { await model.start() }
                .task(id: model.searchText) {
                    // Kurz warten, damit nicht bei jedem Tastendruck gesucht wird.
                    if !model.searchText.isEmpty {
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                    guard !Task.isCancelled else { return }
                    await model.reload()
                }
                .refreshable { await model.refresh() }
                .safeAreaInset(edge: .bottom) { footer }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.opdb == nil {
            if let error = model.errorMessage {
                ContentUnavailableView {
                    Label("Laden fehlgeschlagen", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Erneut versuchen") { Task { await model.start() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView("Lade aktuelle Gerätedaten …")
            }
        } else if model.machines.isEmpty && !model.searchText.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            List(model.machines) { machine in
                NavigationLink(value: machine.id) {
                    MachineRow(machine: machine)
                }
            }
            .listStyle(.plain)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.isBusy {
                ProgressView().controlSize(.small)
            }
            Text(footerText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var footerText: String {
        var parts: [String] = []
        if model.opdb != nil {
            parts.append("\(model.machines.count.formatted()) Einträge")
        }
        if let lastImport = model.info?.lastImport {
            parts.append("Stand \(lastImport.formatted(date: .abbreviated, time: .shortened))")
        }
        if !model.statusText.isEmpty {
            parts.append(model.statusText)
        }
        return parts.joined(separator: " · ")
    }
}

struct MachineRow: View {
    let machine: MachineSummary

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: machine.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 48, height: 48)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(machine.displayName)
                    .font(.headline)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var subtitle: String {
        [
            machine.manufacturerName,
            machine.year.map { String($0) },
            machine.type?.label,
            machine.entryType == .alias ? "Alias" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
