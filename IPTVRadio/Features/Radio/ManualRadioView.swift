import SwiftUI

/// Personal stations entered by the listener, separate from the IPTV lineup.
struct ManualRadioView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var manualStations: ManualStationStore

    @State private var editor: EditorTarget?
    @State private var errorMessage: String?
    @State private var isReordering = false

    private struct EditorTarget: Identifiable {
        let id: String
        let entry: ManualStationEntry?

        init(entry: ManualStationEntry? = nil) {
            self.entry = entry
            id = entry?.id ?? "new"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if manualStations.entries.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(manualStations.entries) { entry in
                                let index = manualStations.entries.firstIndex(where: { $0.id == entry.id }) ?? 0
                                HStack(spacing: 4) {
                                    StationRow(station: entry.station)
                                    if isReordering {
                                        ReorderButtons(
                                            name: entry.name,
                                            canMoveUp: index > 0,
                                            canMoveDown: index < manualStations.entries.count - 1,
                                            moveUp: { manualStations.move(id: entry.id, by: -1) },
                                            moveDown: { manualStations.move(id: entry.id, by: 1) }
                                        )
                                    }
                                }
                                    .swipeActions(edge: .trailing) {
                                        Button("Delete", role: .destructive) { delete(entry) }
                                        Button("Edit") { editor = EditorTarget(entry: entry) }
                                            .tint(AetherTheme.mutedIcon)
                                    }
                                    .contextMenu {
                                        Button {
                                            editor = EditorTarget(entry: entry)
                                        } label: {
                                            Label("Edit Station", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            delete(entry)
                                        } label: {
                                            Label("Delete Station", systemImage: "trash")
                                        }
                                    }
                            }
                        } footer: {
                            Text(isReordering
                                 ? "Use the arrows to place stations in your preferred order."
                                 : "Swipe left on a station to edit or delete it.")
                                .foregroundStyle(AetherTheme.secondaryText)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Radio")
            .background(AetherTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        if manualStations.entries.count > 1 || isReordering {
                            Button {
                                isReordering.toggle()
                            } label: {
                                if isReordering {
                                    Text("Done")
                                } else {
                                    Image(systemName: "arrow.up.arrow.down")
                                }
                            }
                            .accessibilityLabel(isReordering ? "Done reordering" : "Reorder stations")
                            .accessibilityIdentifier("manual.reorder")
                        }
                        Button {
                            editor = EditorTarget()
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(AetherTheme.primaryText)
                        }
                        .accessibilityLabel("Add station")
                        .accessibilityIdentifier("manual.add")
                    }
                }
            }
            .sheet(item: $editor) { target in
                ManualStationEditorView(entry: target.entry)
                    .environmentObject(environment)
                    .environmentObject(manualStations)
            }
            .alert("Couldn't update Radio", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 42))
                .foregroundStyle(AetherTheme.mutedIcon)
            Text("Your Radio stations")
                .font(.title3.weight(.semibold))
            Text("Add a stream link to listen here. MP3, AAC, HLS, M3U and PLS links are supported.")
                .font(.subheadline)
                .foregroundStyle(AetherTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                editor = EditorTarget()
            } label: {
                Label("Add Station", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(AetherTheme.coral)
            .accessibilityIdentifier("manual.addEmpty")
            .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: 420, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
    }

    private func delete(_ entry: ManualStationEntry) {
        do {
            try manualStations.remove(id: entry.id)
            environment.favorites.remove(entry.station)
        } catch {
            errorMessage = (error as? ManualStationError)?.errorDescription
                ?? "The station could not be removed. Try again."
        }
    }
}

private struct ManualStationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var manualStations: ManualStationStore

    let entry: ManualStationEntry?
    @State private var name: String
    @State private var streamURL: String
    @State private var logoURL: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(entry: ManualStationEntry?) {
        self.entry = entry
        _name = State(initialValue: entry?.name ?? "")
        _streamURL = State(initialValue: entry?.streamURL.absoluteString ?? "")
        _logoURL = State(initialValue: entry?.logoURL?.absoluteString ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Station name", text: $name)
                        .textContentType(.name)
                        .accessibilityIdentifier("manual.name")
                    TextField("Stream URL", text: $streamURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("manual.url")
                } header: {
                    Text("Station")
                } footer: {
                    Text("Use a direct MP3, AAC, AAC+, Ogg, Opus, FLAC or HLS (.m3u8) link, or an M3U/PLS station playlist. HTTP and HTTPS are supported.")
                }
                Section("Optional") {
                    TextField("Logo URL", text: $logoURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("manual.artwork")
                    Text("We'll look for the station logo automatically. Paste a logo URL to choose your own.")
                        .font(.caption)
                        .foregroundStyle(AetherTheme.secondaryText)
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(AetherTheme.coral)
                            .accessibilityIdentifier("manual.error")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AetherTheme.background.ignoresSafeArea())
            .navigationTitle(entry == nil ? "Add Station" : "Edit Station")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                        .accessibilityIdentifier("manual.save")
                }
            }
        }
        .tint(AetherTheme.coral)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        let input = ManualStationInput(name: name, streamURL: streamURL, logoURL: logoURL)
        Task {
            defer { isSaving = false }
            do {
                let station = try await manualStations.save(
                    input,
                    editing: entry?.id,
                    httpClient: environment.httpClient
                )
                environment.favorites.replace(station)
                environment.history.replace(station)
                dismiss()
            } catch {
                errorMessage = (error as? ManualStationError)?.errorDescription
                    ?? "The station could not be saved. Try again."
            }
        }
    }
}
