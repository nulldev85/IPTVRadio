# Installing the IPA

## Which artifact do I have?

| Artifact | Installable on iPhone? |
| --- | --- |
| `IPTVRadio-unsigned-simulator-build` | **No.** Diagnostic build for the iOS Simulator (Xcode ▸ Devices & Simulators, or `xcrun simctl install`). Cannot be installed on physical devices. |
| `IPTVRadio-signed-ipa` | **Yes**, when installed through a method authorized by its provisioning profile (below). |
| GitHub Release `v*` asset | Same as the IPA above when the release contains a signed IPA; the simulator-only asset is diagnostic. |

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
