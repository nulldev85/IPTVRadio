# GitHub Actions secrets

Create these under **Repository ▸ Settings ▸ Secrets and variables ▸ Actions**.
Never commit certificate files, profiles, keys, passwords, or IPTV credentials to the
repository — everything below is read from secrets at runtime.

## Signing (required only for a signed, installable IPA)

| Secret | Description |
| --- | --- |
| `IOS_BUNDLE_IDENTIFIER` | Final bundle ID, e.g. `com.yourcompany.IPTVRadio`. Overrides the default `com.example.IPTVRadio` for both archive and export. |
| `IOS_TEAM_ID` | Your 10-character Apple Developer Team ID (Apple Developer ▸ Membership details). |
| `IOS_EXPORT_METHOD` | Default export method: `ad-hoc`, `app-store`, `development`, or `enterprise` (default `ad-hoc`). |
| `APPLE_CERT_P12_BASE64` | Base64 of your signing certificate `.p12` (Apple Distribution recommended). |
| `APPLE_CERT_P12_PASSWORD` | The password you set when exporting the `.p12`. |
| `APPLE_PROVISIONING_PROFILE_BASE64` | Base64 of the provisioning profile `.mobileprovision` that includes your devices (ad-hoc/development) or is a store profile (app-store). |
| `IOS_PROVISIONING_PROFILE_NAME` | The *name* of the provisioning profile as shown in the Apple Developer portal (used for `PROVISIONING_PROFILE_SPECIFIER`). |
| `IOS_SIGNING_CERTIFICATE_IDENTITY` | Optional; defaults to `Apple Distribution`. |
| `KEYCHAIN_PASSWORD` | Optional; a random one is generated per run if unset. |

## TestFlight upload (optional)

| Secret | Description |
| --- | --- |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API key ID (ASC ▸ Users and Access ▸ Integrations ▸ App Store Connect API). |
| `APP_STORE_CONNECT_API_ISSUER_ID` | The issuer ID shown on the same page. |
| `APP_STORE_CONNECT_API_KEY_P8_BASE64` | Base64 of the `.p8` private key file. |

## Step-by-step setup

1. **Create a bundle identifier**
   - App Store Connect ▸ Certificates, Identifiers & Profiles ▸ Identifiers ▸ `+`
   - App IDs ▸ App; description `IPTV Radio`; explicit ID `com.yourcompany.IPTVRadio`.
   - Background Modes capability is declared by the app itself (`UIBackgroundModes: audio`);
     no special entitlements are needed.

2. **Create a signing certificate (Apple Distribution)**
   - Keychain Access on a Mac ▸ Certificate Assistant ▸ Request a Certificate From a
     Certificate Authority (save a CSR `.certSigningRequest`).
   - Developer portal ▸ Certificates ▸ `+` ▸ Apple Distribution; upload the CSR; download
     the `.cer`; double-click it in Keychain Access.
   - Export from Keychain Access: select the certificate *with its private key* ▸
     File ▸ Export Items ▸ `.p12`; set a strong export password.
   - Base64 the file: `base64 -i Certificates.p12 | pbcopy` (macOS) or
     `certutil -encode Certificates.p12 out.txt` (Windows) and paste the payload
     (without headers) into `APPLE_CERT_P12_BASE64`.

3. **Create a provisioning profile**
   - Ad-hoc distribution: Developer portal ▸ Profiles ▸ `+` ▸ Ad hoc; select the App ID,
     the Apple Distribution certificate, and the device UDIDs you will install on.
   - App Store distribution: choose App Store instead (no devices needed; requires
     uploading via TestFlight/App Store).
   - Download the `.mobileprovision`, base64 it the same way into
     `APPLE_PROVISIONING_PROFILE_BASE64`, and put its display name into
     `IOS_PROVISIONING_PROFILE_NAME`.

4. **App Store Connect API key (TestFlight only)**
   - ASC ▸ Users and Access ▸ Integrations ▸ App Store Connect API ▸ `+`
   - Role: App Manager (or Admin); download the `.p8`; note Key ID and Issuer ID.
   - Base64 the `.p8` into `APP_STORE_CONNECT_API_KEY_P8_BASE64`.

5. **Team ID**
   - Developer portal ▸ Membership details ▸ Team ID (10 chars) → `IOS_TEAM_ID`.

## Required workflow inputs vs secrets

The bundle identifier, team ID, export method, profile name, scheme, and project path
are **never hardcoded**: `PROJECT_PATH`/`SCHEME` live in the workflow's `env`, while the
sensitive ones come exclusively from secrets (see table above).
