import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case account = "Account"
    case stations = "Stations"
    case playback = "Playback"
    case app = "App"

    var id: String { rawValue }
}

/// Settings: account, playback options, filtering rules, cache and privacy.
struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var playback: PlaybackEngine

    @State private var confirmSignOut = false
    @State private var cacheCleared = false
    @State private var selectedCategory: SettingsCategory = .account

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Settings")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AetherTheme.primaryText)
                        .padding(.horizontal, 20)
                    categoryBar
                }
                .padding(.top, 12)

                AetherTheme.border.opacity(0.65)
                    .frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch selectedCategory {
                        case .account:
                            accountSection
                        case .stations:
                            filteringSection
                        case .playback:
                            playbackSection
                        case .app:
                            appearanceSection
                            cacheSection
                            privacySection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 32 + flatControlsClearance)
                }
                .scrollIndicators(.hidden)
                .id(selectedCategory)
            }
            .background(AetherTheme.background.ignoresSafeArea())
            .toggleStyle(AetherSettingsToggleStyle())
            .toolbar(.hidden, for: .navigationBar)
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

    private var categoryBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsCategory.allCases) { category in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = category
                    }
                } label: {
                    VStack(spacing: 10) {
                        Text(category.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedCategory == category
                                ? AetherTheme.primaryText : AetherTheme.mutedIcon)
                        Capsule()
                            .fill(selectedCategory == category ? AetherTheme.coral : .clear)
                            .frame(height: 3)
                            .padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.category.\(category.rawValue.lowercased())")
                .accessibilityValue(selectedCategory == category ? "Selected" : "")
            }
        }
        .padding(.horizontal, 12)
    }

    private var flatControlsClearance: CGFloat {
        guard !settings.liquidGlassEnabled else { return 0 }
        return 61 + (playback.state.station == nil ? 0 : 60)
    }

    private var appearanceSection: some View {
        settingsGroup("Appearance", systemImage: "paintbrush.pointed") {
            Toggle("Liquid Glass navigation", isOn: $settings.liquidGlassEnabled)
                .accessibilityIdentifier("settings.liquidGlass")
                .aetherSettingsRow()
            settingsFooter("Turn off for a flat, full-width tab bar. The change takes effect immediately.")
        }
    }

    private var accountSection: some View {
        settingsGroup("Account", systemImage: "person.crop.circle") {
            if let session = activeSessionDescription {
                LabeledContent("Status", value: session.status)
                    .aetherSettingsRow()
                if let expiry = session.expiry {
                    settingsDivider
                    LabeledContent("Subscription expires", value: expiry)
                        .aetherSettingsRow()
                }
            } else {
                LabeledContent("Status", value: "Signed in")
                    .aetherSettingsRow()
            }
            if let warning = auth.insecureEndpointWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
                    .aetherSettingsRow()
            }
            settingsDivider
            Button("Sign Out", role: .destructive) {
                confirmSignOut = true
            }
            .foregroundStyle(AetherTheme.coral)
            .accessibilityIdentifier("settings.signOut")
            .aetherSettingsRow()
        }
    }

    private var playbackSection: some View {
        VStack(spacing: 24) {
            settingsGroup("Streaming", systemImage: "antenna.radiowaves.left.and.right") {
                Toggle("Allow cellular streaming", isOn: $settings.cellularAllowed)
                    .accessibilityIdentifier("settings.cellular")
                    .aetherSettingsRow()
                settingsDivider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Stream timeout")
                        Spacer()
                        Text("\(Int(settings.streamTimeout)) s")
                            .foregroundStyle(AetherTheme.secondaryText)
                    }
                    Slider(value: $settings.streamTimeout, in: 5...60, step: 1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Stream timeout")
                .accessibilityValue("\(Int(settings.streamTimeout)) seconds")
                .aetherSettingsRow()
                settingsDivider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Auto-retry attempts")
                        Spacer()
                        Text("\(settings.retryLimit)")
                            .foregroundStyle(AetherTheme.secondaryText)
                    }
                    Slider(value: Binding(
                        get: { Double(settings.retryLimit) },
                        set: { settings.retryLimit = Int($0) }
                    ), in: 0...5, step: 1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Auto-retry attempts")
                .accessibilityValue("\(settings.retryLimit) attempts")
                .aetherSettingsRow()
                settingsDivider
                SleepTimerStatusRow()
                    .aetherSettingsRow()
                settingsDivider
                Toggle("Prefer audio-only stream", isOn: $settings.preferAudioOnlyRendition)
                    .accessibilityIdentifier("settings.audioOnly")
                    .aetherSettingsRow()
                settingsFooter("Uses a dedicated audio track when an HLS stream offers one.")
            }
            settingsGroup("Song information", systemImage: "music.note") {
                Toggle("Look up song artwork online", isOn: $settings.lookupSongArtwork)
                    .accessibilityIdentifier("settings.artworkLookup")
                    .aetherSettingsRow()
                settingsDivider
                NavigationLink {
                    StreamDiagnosticsView()
                        .toolbar(.visible, for: .navigationBar)
                } label: {
                    settingsNavigationLabel("Stream diagnostics")
                }
                .accessibilityIdentifier("settings.streamDiagnostics")
                .aetherSettingsRow()
                settingsFooter("When the stream has no artwork, Aether can look up the current song in Apple's public catalog. No account or tracking is involved; turn this off for fully offline metadata.")
            }
        }
    }

    private var filteringSection: some View {
        VStack(spacing: 24) {
            settingsGroup("Station filtering", systemImage: "line.3.horizontal.decrease") {
                Toggle("Show only SiriusXM-labelled stations", isOn: $settings.siriusOnly)
                    .accessibilityIdentifier("settings.siriusOnly")
                    .aetherSettingsRow()
                settingsDivider
                Toggle("Show all detected radio stations", isOn: $settings.showAllStations)
                    .accessibilityIdentifier("settings.showAll")
                    .aetherSettingsRow()
            }
            settingsGroup("Detection rules", systemImage: "slider.horizontal.3") {
                NavigationLink {
                    DetectionRulesEditorView()
                        .toolbar(.visible, for: .navigationBar)
                } label: {
                    settingsNavigationLabel("Edit detection rules")
                }
                .aetherSettingsRow()
                settingsFooter("Tune the keyword rules if a provider misclassifies a station.")
            }
        }
    }

    private var cacheSection: some View {
        settingsGroup("Data", systemImage: "externaldrive") {
            LabeledContent("Cached data size", value: ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file))
                .aetherSettingsRow()
            settingsDivider
            Button("Clear station cache") {
                library.clearCacheData()
                cacheCleared = true
            }
            .alert("Cache cleared", isPresented: $cacheCleared) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Cached stations were removed. A refresh will re-download your lineup.")
            }
            .aetherSettingsRow()
        }
    }

    private var privacySection: some View {
        settingsGroup("Privacy", systemImage: "lock.shield") {
            NavigationLink {
                PrivacyNoticeView()
                    .toolbar(.visible, for: .navigationBar)
            } label: {
                settingsNavigationLabel("Privacy & authorization")
            }
            .aetherSettingsRow()
            settingsFooter("No analytics, no tracking. Credentials are stored only in the Keychain and never logged.")
        }
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AetherTheme.coral)
                    .frame(width: 28, height: 28)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AetherTheme.primaryText)
            }
            .padding(.bottom, 10)

            content()
        }
        .foregroundStyle(AetherTheme.secondaryText)
        .tint(AetherTheme.coral)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsDivider: some View {
        AetherTheme.border.opacity(0.55)
            .frame(height: 1)
    }

    private func settingsFooter(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(AetherTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
    }

    private func settingsNavigationLabel(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AetherTheme.mutedIcon)
        }
        .foregroundStyle(AetherTheme.secondaryText)
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

private extension View {
    func aetherSettingsRow() -> some View {
        frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.vertical, 6)
    }
}

/// Coral matches the Favorites stars; the thumb position and brightness show
/// whether a setting is enabled without reverting to the system's white track.
private struct AetherSettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 8)
                Capsule()
                    .fill(AetherTheme.coral.opacity(configuration.isOn ? 0.35 : 0.17))
                    .frame(width: 54, height: 30)
                    .overlay {
                        Capsule()
                            .strokeBorder(AetherTheme.coral.opacity(0.45), lineWidth: 1)
                    }
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(AetherTheme.coral.opacity(configuration.isOn ? 1 : 0.72))
                            .frame(width: 26, height: 26)
                            .padding(2)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
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
        .scrollContentBackground(.hidden)
        .background(AetherTheme.background.ignoresSafeArea())
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
                    .foregroundStyle(AetherTheme.secondaryText)

                Text("Your data")
                    .font(.headline)
                Text("Credentials (server URL, username, password or playlist URL) are stored exclusively in the iOS Keychain. Station lists and preferences stay on your device. Nothing is uploaded anywhere by this app.")
                    .font(.subheadline)
                    .foregroundStyle(AetherTheme.secondaryText)

                Text("No tracking")
                    .font(.headline)
                Text("This app contains no analytics, advertising, or third-party tracking SDKs. Logs are scrubbed of usernames, passwords and credential-bearing URLs.")
                    .font(.subheadline)
                    .foregroundStyle(AetherTheme.secondaryText)

                Text("Secure connections")
                    .font(.headline)
                Text("HTTPS is preferred. If your provider only offers an unencrypted HTTP endpoint, the app clearly warns you before you continue. Because providers differ, connections to provider-supplied HTTP endpoints (including artwork servers) are allowed; the app still warns you whenever an insecure portal is detected.")
                    .font(.subheadline)
                    .foregroundStyle(AetherTheme.secondaryText)
            }
            .padding()
        }
        .background(AetherTheme.background.ignoresSafeArea())
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
