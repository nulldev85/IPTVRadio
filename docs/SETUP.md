# Setup guide

## Prerequisites

- Xcode 16 or newer (macOS) to develop locally.
- A GitHub repository with Actions enabled (macOS runners are used automatically).

## Local development

1. Clone the repository.
2. Open `IPTVRadio.xcodeproj` in Xcode.
3. Select the `IPTVRadio` scheme and an iPhone simulator, then Cmd+R.
4. Enter your own Xtream provider credentials (portal URL, username, password) or an
   M3U playlist URL on the sign-in screen.

There are no third-party package dependencies, so nothing to resolve.

## Tests

- Unit tests: `xcodebuild test -project IPTVRadio.xcodeproj -scheme IPTVRadio
  -destination 'platform=iOS Simulator,name=iPhone 16'`
- All fixtures are embedded in the test target; no network access or real credentials
  are needed.

## CI behavior

| Trigger | What runs |
| --- | --- |
| Pull request | `test` + `security-scan` (compile and test validation) |
| Push to `main` | `test` + `security-scan` + `build` (unsigned simulator artifact; signed IPA when secrets configured) |
| Tag `v*` | Same as push, plus a GitHub Release that attaches the IPA (or clearly-labeled unsigned simulator build) |
| `workflow_dispatch` | Manual run; choose export method and whether to attempt signing |

## Making the signed IPA work end-to-end

1. Add every secret listed in `docs/SECRETS.md`.
2. Make sure the provisioning profile's bundle ID matches `IOS_BUNDLE_IDENTIFIER`.
3. Push a `v1.0.0` tag or run the workflow manually with `attempt_signed_build=true`.
4. Download the `IPTVRadio-signed-ipa` artifact.

If signing secrets are absent, the pipeline still compiles and tests the app and
uploads the **unsigned simulator build**, which is only usable in the iOS Simulator —
it cannot be installed on an iPhone.

## Changing app identity

- Bundle ID: secret `IOS_BUNDLE_IDENTIFIER` (or build setting `IPTVRADIO_BUNDLE_IDENTIFIER`).
- Team: secret `IOS_TEAM_ID` (applied by the archive step).
- Profile name: secret `IOS_PROVISIONING_PROFILE_NAME`.
- Export method: workflow input or secret `IOS_EXPORT_METHOD`.
- Scheme/project: workflow `env` block (`SCHEME`, `PROJECT_PATH`).
