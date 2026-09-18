import SwiftUI

/// Settings: account, playback options, filtering rules, cache and privacy.
struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var playback: PlaybackEngine

    @State private var confirmSignOut = false
    @State private var cacheCleared = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                playbackSection
                filteringSection
                cacheSection
                privacySection
            }
            .navigationTitle("Settings")
            .alert("Sign out?", isPresented: $confirmSignOut) {
                Button("Sign Out", role: .destructive) {
                    playback.stop()
                    auth.signOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Credentials are removed from the Keychain and cached data is cleared.")
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if let session = activeSessionDescription {
                LabeledContent("Status", value: session.status)
                if let expiry = session.expiry {
                    LabeledContent("Subscription expires", value: expiry)
                }
            } else {
                LabeledContent("Status", value: "Signed in")
            }
            if let warning = auth.insecureEndpointWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
            Button("Sign Out", role: .destructive) {
                confirmSignOut = true
            }
            .accessibilityIdentifier("settings.signOut")
        }
    }

    private var playbackSection: some View {
        Section {
            Toggle("Allow cellular streaming", isOn: $settings.cellularAllowed)
                .accessibilityIdentifier("settings.cellular")
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Stream timeout")
                    Spacer()
                    Text("\(Int(settings.streamTimeout)) s")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.streamTimeout, in: 5...60, step: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Stream timeout")
            .accessibilityValue("\(Int(settings.streamTimeout)) seconds")
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Auto-retry attempts")
                    Spacer()
                    Text("\(settings.retryLimit)")
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(settings.retryLimit) },
                    set: { settings.retryLimit = Int($0) }
                ), in: 0...5, step: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Auto-retry attempts")
            .accessibilityValue("\(settings.retryLimit) attempts")
            SleepTimerStatusRow()
            Toggle("Prefer audio-only stream", isOn: $settings.preferAudioOnlyRendition)
                .accessibilityIdentifier("settings.audioOnly")
            Toggle("Look up song artwork online", isOn: $settings.lookupSongArtwork)
                .accessibilityIdentifier("settings.artworkLookup")
            Picker("Stream format", selection: $settings.streamFormatPreference) {
                ForEach(StreamFormatPreference.allCases) { preference in
                    Text(preference.label).tag(preference)
                }
            }
            .accessibilityIdentifier("settings.streamFormat")
            NavigationLink("Stream diagnostics") {
                StreamDiagnosticsView()
            }
            .accessibilityIdentifier("settings.streamDiagnostics")
        } header: {
            Text("Playback")
        } footer: {
            Text("Background audio, lock-screen controls and automatic reconnection are always active.\n\n“Prefer audio-only stream” plays a channel's dedicated audio track when its HLS manifest offers one — better quality for radio and much less data than downloading its video variant.\n\n“Look up song artwork online” sends the current song's artist and title to Apple's public catalog to fetch album art when the stream itself carries none. No account or tracking is involved; disable it for fully offline metadata.")
        }
    }

    private var filteringSection: some View {
        Section {
            Toggle("Show only SiriusXM-labelled stations", isOn: $settings.siriusOnly)
                .accessibilityIdentifier("settings.siriusOnly")
            Toggle("Show all detected radio stations", isOn: $settings.showAllStations)
                .accessibilityIdentifier("settings.showAll")
            NavigationLink("Detection rules") {
                DetectionRulesEditorView()
            }
        } header: {
            Text("Station filtering")
        } footer: {
            Text("Providers label channels differently. Tune the keyword rules if stations are missing or misclassified.")
        }
    }

    private var cacheSection: some View {
        Section("Data") {
            LabeledContent("Cached data size", value: ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file))
            Button("Clear station cache") {
                library.clearCacheData()
                cacheCleared = true
            }
            .alert("Cache cleared", isPresented: $cacheCleared) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Cached stations were removed. A refresh will re-download your lineup.")
            }
        }
    }

    private var privacySection: some View {
        Section {
            NavigationLink("Privacy & authorization") {
                PrivacyNoticeView()
            }
        } footer: {
            Text("No analytics, no tracking. Credentials are stored only in the Keychain and never logged.")
        }
    }

    private var cacheSize: Int {
        JSONFileStore().totalBytes
    }

    private var activeSessionDescription: (status: String, expiry: String?)? {
        guard case let .active(session) = auth.authState else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return (
            session.status ?? (session.isExpired ? "Expired" : "Active"),
            session.expiryDate.map { formatter.string(from: $0) }
        )
    }
}

/// Shows the sleep timer countdown when active.
struct SleepTimerStatusRow: View {
    @EnvironmentObject private var playback: PlaybackEngine

    var body: some View {
        if let deadline = playback.sleepTimerDeadline {
            let remaining = max(0, deadline.timeIntervalSinceNow)
            let minutes = Int(remaining / 60)
            let seconds = Int(remaining.truncatingRemainder(dividingBy: 60))
            LabeledContent("Sleep timer", value: String(format: "%d:%02d", minutes, seconds))
        } else {
            LabeledContent("Sleep timer", value: "Off")
        }
    }
}

/// Editor for the configurable detection rules.
struct DetectionRulesEditorView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var radioGroupText = ""
    @State private var radioNameText = ""
    @State private var siriusText = ""
    @State private var videoGroupText = ""

    var body: some View {
        Form {
            Section {
                TextEditor(text: $siriusText)
                    .frame(minHeight: 60)
                    .accessibilityLabel("Sirius keywords, one per line")
            } header: {
                Text("SiriusXM keywords")
            } footer: {
                Text("Case-insensitive. Matched against station names, groups and EPG ids. One keyword per line.")
            }

            Section {
                TextEditor(text: $radioGroupText)
                    .frame(minHeight: 80)
                    .accessibilityLabel("Radio group keywords, one per line")
            } header: {
                Text("Radio group keywords")
            } footer: {
                Text("Group titles (categories) that indicate audio stations, one per line.")
            }

            Section {
                TextEditor(text: $radioNameText)
                    .frame(minHeight: 100)
                    .accessibilityLabel("Radio name keywords, one per line")
            } header: {
                Text("Radio name keywords")
            } footer: {
                Text("Channel-name keywords that indicate audio, one per line.")
            }

            Section {
                TextEditor(text: $videoGroupText)
                    .frame(minHeight: 60)
                    .accessibilityLabel("Video group keywords, one per line")
            } header: {
                Text("Video group keywords")
            } footer: {
                Text("Group titles that indicate video channels, which are excluded, one per line.")
            }

            Section {
                Button("Reset to defaults") {
                    settings.resetDetectionRules()
                    loadFields()
                }
            }
        }
        .navigationTitle("Detection rules")
        .onAppear { loadFields() }
        .onDisappear { saveFields() }
    }

    private func loadFields() {
        siriusText = settings.detectionRules.siriusKeywords.joined(separator: "\n")
        radioGroupText = settings.detectionRules.radioGroupKeywords.joined(separator: "\n")
        radioNameText = settings.detectionRules.radioNameKeywords.joined(separator: "\n")
        videoGroupText = settings.detectionRules.videoGroupKeywords.joined(separator: "\n")
    }

    private func saveFields() {
        var rules = settings.detectionRules
        rules.siriusKeywords = lines(siriusText)
        rules.radioGroupKeywords = lines(radioGroupText)
        rules.radioNameKeywords = lines(radioNameText)
        rules.videoGroupKeywords = lines(videoGroupText)
        settings.detectionRules = rules
    }

    private func lines(_ text: String) -> [String] {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// The required authorization/privacy notice.
struct PrivacyNoticeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)

                Text("Privacy & Authorization")
                    .font(.title2.weight(.semibold))

                Text("Authorization requirement")
                    .font(.headline)
                Text("You must hold valid authorization from your provider to access the streams you configure in this app. This app is a client for your own subscription only. It does not bundle, scrape, redistribute, or provide access to any channels, and it does not attempt to bypass DRM, authentication, geographic restrictions, or provider limitations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Your data")
                    .font(.headline)
                Text("Credentials (server URL, username, password or playlist URL) are stored exclusively in the iOS Keychain. Station lists and preferences stay on your device. Nothing is uploaded anywhere by this app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("No tracking")
                    .font(.headline)
                Text("This app contains no analytics, advertising, or third-party tracking SDKs. Logs are scrubbed of usernames, passwords and credential-bearing URLs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Secure connections")
                    .font(.headline)
                Text("HTTPS is preferred. If your provider only offers an unencrypted HTTP endpoint, the app clearly warns you before you continue. Because providers differ, connections to provider-supplied HTTP endpoints (including artwork servers) are allowed; the app still warns you whenever an insecure portal is detected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
