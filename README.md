# IPTV Radio (iOS)

A native iOS app (Swift + SwiftUI) that plays **radio/audio stations from the user's own
legitimate IPTV subscription** via the Xtream Codes API or an imported M3U playlist.
The app is a client only: it bundles, scrapes, and redistributes **no channels** and does
not bypass DRM, authentication, or geographic restrictions. Users must hold valid
authorization from their provider for every stream they configure.

## Features

- Xtream Codes sign-in (portal URL + username + password) and M3U/M3U8 playlist import
- Secure credential storage in the iOS Keychain (never UserDefaults, never logs)
- Automatic radio/audio station detection with **user-configurable** keyword rules
- SiriusXM-focused prioritization (configurable keywords: `siriusxm`, `sxm`, …)
- Optional full list of all detected radio stations
- Radio only: video/TV categories are never shown; search by station, genre, or metadata
- Prefers a stream's dedicated audio-only rendition when offered (better quality, far less data than video variants)
- Favorites tab (persisted locally; recent-play history is still recorded on device)
- Full now-playing screen, mini player, sleep timer, retry/stop controls
- Background audio, lock-screen & Control Center controls, now-playing metadata + artwork
- Headphone/Bluetooth/AirPlay route changes, call/Siri interruption handling
- Automatic reconnection with exponential backoff; configurable stream timeout
- Cellular-streaming opt-in setting; pull-to-refresh and manual refresh
- Loading / empty / offline / expired-session / malformed-playlist states
- Dark Mode, Dynamic Type, VoiceOver labels, iPhone and iPad layouts
- Account management, filter-rule editor, cache clearing, and logout in Settings

## Project layout

```
IPTVRadio.xcodeproj/          Xcode project (Xcode 16+ synchronized groups)
IPTVRadio/
  App/                        DI container, UI-test support
  Core/
    Models/                   Domain models (stations, credentials, session)
    Networking/               Xtream/M3U clients over an injectable HTTPClient
    Parsing/                  M3U/M3U8 parser, Xtream JSON decoding
    Detection/                Radio heuristics, SiriusXM matcher, deduplication
    Persistence/              Favorites, history, cache, settings (JSON files + UserDefaults)
    Keychain/                 Keychain wrapper + credential store
    Connectivity/             Network path monitor
    Library/                  Refresh orchestration and caching
  Playback/                   AVPlayer engine, audio session, remote commands, now playing
  Features/                   SwiftUI screens (auth, radio, search, library, settings, now playing)
IPTVRadioTests/               Unit tests with embedded fixtures + mocked networking
IPTVRadioUITests/             UI tests using the app's mock mode (no network)
scripts/                      CI helpers (Xcode selection, signing import/cleanup, IPA export)
.github/workflows/ios.yml     GitHub Actions: test, security scan, package, release, TestFlight
docs/                         Setup, secrets, installation instructions
```

## Quick start (developers)

Open `IPTVRadio.xcodeproj` in Xcode 16 or newer and press Cmd+R. No extra setup is
required; there are no third-party dependencies.

- Bundle ID: configurable via the `IPTVRADIO_BUNDLE_IDENTIFIER` build setting
  (default `com.example.IPTVRadio`). Override from the CLI with
  `xcodebuild ... IPTVRADIO_BUNDLE_IDENTIFIER=com.yourco.IPTVRadio`.
- Deployment target: iOS 17.0, SDK: latest Xcode.

## CI/CD

`.github/workflows/ios.yml` runs on `macos-15` GitHub-hosted runners:

1. **test** — builds the app and runs unit + UI tests on an iPhone 16 simulator,
   uploading `.xcresult` summaries and logs.
2. **security-scan** — fails the build if signing material is committed or the
   networking layer logs URLs.
3. **build** — always produces an **unsigned simulator build** artifact; when signing
   secrets are configured it also archives with `xcodebuild` and exports a **signed,
   installable IPA**, then optionally publishes a GitHub Release (on `v*` tags) and
   uploads to TestFlight.

Manual runs via `workflow_dispatch` allow choosing the export method
(`ad-hoc`, `app-store`, `development`, `enterprise`).

See `docs/SECRETS.md` for the full list of required secrets and step-by-step
certificate/profile/API-key setup, and `docs/INSTALL.md` for installing the IPA.

## Third-party components

- **Playback engine:** [VLCKit](https://code.videolan.org/videolan/VLCKit) (LGPL-2.1), bundled as an optional
  compatibility engine (`Settings ▸ Playback ▸ Playback engine`). It plays provider stream formats that
  Apple's AVPlayer refuses, such as raw MPEG-TS and redirecting audio-only endpoints. The app defaults to
  the compatibility engine and can switch to AVPlayer at any time.

## Privacy & authorization

- Credentials are stored only in the Keychain; all logging is scrubbed of usernames,
  passwords, and credential-bearing URLs (see `IPTVRadio/Core/Logging.swift`).
- HTTPS is the default; clear warnings appear when a provider endpoint is plain HTTP.
- No analytics or tracking SDKs of any kind.
- The in-app authorization notice (login screen + Settings ▸ Privacy) states that users
  must have authorization to access the streams they configure.

## Known limitations

- Live EPG "show" metadata is not displayed; search covers names, groups, and EPG ids.
- Xtream providers vary wildly; unusual deployments may need keyword tuning in Settings.
- A signed device IPA requires an Apple Developer account with a matching certificate
  and provisioning profile; without them CI produces the clearly-labeled unsigned
  simulator diagnostic build only.
