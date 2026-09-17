import SwiftUI

/// Sign-in screen supporting Xtream Codes credentials and M3U playlist import.
/// Includes the authorization notice required by the app's terms of use.
struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthViewModel

    @State private var mode: SettingsStore.AuthMode = .xtream
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var playlistURL = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    Picker("Sign-in method", selection: $mode) {
                        Text("Xtream Codes").tag(SettingsStore.AuthMode.xtream)
                        Text("M3U Playlist").tag(SettingsStore.AuthMode.m3u)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("login.methodPicker")

                    if mode == .xtream {
                        xtreamForm
                    } else {
                        m3uForm
                    }

                    if let warning = auth.insecureEndpointWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("login.insecureWarning")
                    }

                    if let error = errorMessage {
                        Label(error, systemImage: "xmark.octagon.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("login.error")
                    }

                    signInButton

                    authorizationNotice
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sign In")
            .onAppear {
                mode = environment.settings.authMode
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Radio for your IPTV subscription")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Sign in with your own provider account. This app does not provide any channels itself.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    private var xtreamForm: some View {
        VStack(spacing: 12) {
            TextField("Server / portal URL (e.g. https://host:port)", text: $server)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("login.server")
                .accessibilityLabel(Text("Server or portal URL"))
            TextField("Username", text: $username)
                .textContentType(.username)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("login.username")
            SecureField("Password", text: $password)
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit(signIn)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("login.password")
        }
    }

    private var m3uForm: some View {
        VStack(spacing: 12) {
            TextField("M3U / M3U8 playlist URL", text: $playlistURL)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("login.playlistURL")
            Text("The playlist is downloaded from your own provider. URLs containing embedded credentials are stored only in the Keychain and never logged.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var signInButton: some View {
        Button {
            signIn()
        } label: {
            Group {
                if isSigningIn {
                    ProgressView().tint(.white)
                } else {
                    Text("Sign In").font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .background(Color.accentColor)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(isSigningIn)
        .accessibilityIdentifier("login.submit")
    }

    private var authorizationNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Authorization notice", systemImage: "checkmark.shield")
                .font(.footnote.weight(.semibold))
            Text("You must have valid authorization from your provider to access the streams you use with this app. This app is a client for your own subscription only; it does not bundle, scrape, or redistribute channels and does not bypass DRM or access restrictions.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func signIn() {
        errorMessage = nil
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            switch mode {
            case .xtream:
                let credentials = XtreamCredentials(
                    serverInput: server,
                    username: username,
                    password: password
                )
                let result = await auth.signIn(xtream: credentials, httpClient: environment.httpClient)
                if case let .failure(error) = result {
                    errorMessage = error.errorDescription
                }
            case .m3u:
                guard let url = URL(string: playlistURL.trimmingCharacters(in: .whitespaces)),
                      url.scheme != nil, url.host != nil else {
                    errorMessage = ProviderError.invalidServerURL.errorDescription
                    return
                }
                _ = await auth.signIn(m3u: url)
            }
        }
    }
}
