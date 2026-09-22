# Installing the IPA

## Which artifact do I have?

Every workflow run produces the first two; the third appears only when signing
secrets are configured.

| Artifact | Installable on iPhone? |
| --- | --- |
| `IPTVRadio-unsigned-simulator-build` | **No.** Diagnostic build for the iOS Simulator (Xcode ▸ Devices & Simulators, or `xcrun simctl install`). Cannot be installed on physical devices. |
| `IPTVRadio-unsigned-device-ipa` | **Not directly.** A real arm64 device build (`Payload/IPTVRadio.app`, iphoneos SDK, Release) with signing disabled. iOS refuses unsigned code, so it must be re-signed first — see below. |
| `IPTVRadio-signed-ipa` | **Yes**, when installed through a method authorized by its provisioning profile (below). |
| GitHub Release `v*` asset | Same as the IPA above when the release contains a signed IPA; the simulator-only asset is diagnostic. |

CI can always *build* a device IPA, but it can only *sign* one when the signing
secrets in `docs/SECRETS.md` are present — a signing certificate and provisioning
profile are issued by Apple against a developer account, so no workflow
configuration can substitute for them. Until they are set, `SIGNING_SECRETS_PRESENT`
is `false` in the Package App job log and the signing steps are skipped by design.

## Testing a change without any signing setup

In rough order of least friction:

1. **Build and run from Xcode** (needs a Mac, no paid account). Open
   `IPTVRadio.xcodeproj`, pick your iPhone, set Signing & Capabilities to your
   personal team, and press Cmd+R. Xcode signs it for you with a free Apple ID —
   the provisioning lasts 7 days, which is ample for testing, and you get live
   Console output.
2. **Install the simulator build** (needs a Mac). Real streams play, so playback
   behaviour is exercised; background audio, route changes and on-device CPU cost
   are not representative.
3. **Re-sign the unsigned device IPA** (no Mac required). See below.

## Re-signing the unsigned device IPA

`IPTVRadio-unsigned-device-ipa` is packaged in the layout re-signing tools expect,
so it can be signed with your own Apple ID and installed on your own device. The
app imposes no requirement here, and any third-party tool must be used in line
with its own terms. Two notes specific to this app:

- The default bundle identifier is `com.example.IPTVRadio`. Free Apple ID signing
  needs an identifier unique to you, so override it when re-signing (or build with
  `IPTVRADIO_BUNDLE_IDENTIFIER=com.yourname.IPTVRadio`).
- VLCKit is an embedded framework. Whatever re-signs the app must re-sign embedded
  frameworks too, or the app will crash at launch.

## Install a signed IPA

An installable device IPA requires an **active Apple Developer account**, a **matching
signing certificate**, and a **provisioning profile** containing the intended device (or
a supported distribution method such as App Store/TestFlight/enterprise).

### Ad-hoc profile (your registered test devices)

1. Download the `IPTVRadio-signed-ipa` artifact from the workflow run (or the Release).
2. Unzip it if your browser extracted a `.zip` wrapper; you need the `.ipa`.
3. Install with one of:
   - **Finder (macOS):** connect the iPhone, drag the `.ipa` onto the device in Finder.
   - **Apple Configurator 2:** Devices ▸ Add ▸ Apps… and pick the `.ipa`.
   - **Xcode:** Devices and Simulators ▸ drag the `.ipa` into the Installed Apps list.
   - **MDM or in-house distribution:** ad-hoc IPAs may be distributed through any
     deployment pipeline that honors the profile's device list.
4. On the device: Settings ▸ General ▸ VPN & Device Management ▸ trust the profile.

### Without a Mac

- Use **Apple Configurator for iPhone** (iOS App): copy the `.ipa` from iCloud
  Drive/Files to the app, then install onto a connected device.
- Any third-party sideloading tool must be used in line with its terms; the app itself
  imposes no such requirement.

## TestFlight distribution (up to 10,000 external testers)

1. Configure the three `APP_STORE_CONNECT_API_*` secrets (see `docs/SECRETS.md`).
2. Run the workflow with export method `app-store` (or push a `v*` tag).
3. The final job uploads the IPA to TestFlight. Add build to internal/external testing
   groups in App Store Connect.

## App Store submission

1. Run the workflow with `export_method=app-store` to produce the signed IPA.
2. In Xcode or Transporter, upload the same archive (or use the TestFlight step as a
   staging path), then submit for review in App Store Connect.

## Verifying the IPA

```bash
codesign -dv --verbose=4 Payload/IPTVRadio.app
security cms -D -i embedded.mobileprovision   # inspect profile, devices, expiry
```
