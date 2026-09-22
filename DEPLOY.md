# Shipping EnerVector to TestFlight

Already configured in the project:

- Team `Y9WQTJV82S`, automatic signing, bundle ID `com.apexleadpros.enervector`
- `ITSAppUsesNonExemptEncryption = NO` — export compliance is pre-answered
- `PrivacyInfo.xcprivacy` (UserDefaults, reason CA92.1; no tracking, no data collected)
- Camera / photo library usage strings, 1024 px app icon (no alpha)
- `scripts/testflight.sh` — archives, signs, and uploads in one step

## 1. Create the app record (one time)

[App Store Connect](https://appstoreconnect.apple.com/apps) → **+** → **New App**

| Field | Value |
|---|---|
| Platforms | iOS |
| Name | EnerVector (must be unique on the App Store; try "EnerVector Pro" etc. if taken) |
| Primary language | English (U.S.) |
| Bundle ID | `com.apexleadpros.enervector` |
| SKU | `enervector` |
| User access | Full Access |

If the bundle ID isn't in the dropdown, register it at
[developer.apple.com › Identifiers](https://developer.apple.com/account/resources/identifiers/list) → **+** → App IDs → App → explicit ID `com.apexleadpros.enervector`.

## 2. Build and upload (every release)

```bash
scripts/testflight.sh
```

The build number is a UTC timestamp (`202609221902`), so it always increases. Bump the
marketing version (`MARKETING_VERSION`, currently 1.0) in Xcode when you ship a new version.

The script signs in with the Apple ID in **Xcode › Settings › Accounts**. For CI or
another machine, use an [App Store Connect API key](https://appstoreconnect.apple.com/access/integrations/api)
(role: App Manager) instead:

```bash
export ASC_KEY_PATH=~/private_keys/AuthKey_XXXXXXXXXX.p8
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
scripts/testflight.sh
```

Build products go to `$TMPDIR/enervector-release`, outside the iCloud-synced Documents
folder, whose file attributes make `codesign` fail.

## 3. TestFlight

The build shows *Processing* in **App Store Connect › EnerVector › TestFlight** for ~5–15 min.

- **Internal testers (no review, up to 100):** Users and Access → invite their Apple ID →
  TestFlight → Internal Testing → add them. They install via the TestFlight app.
- **External testers / public link (one-time beta review, ~24 h):** TestFlight → External
  Testing → new group → add the build → fill in *Test Information* (feedback email,
  what to test) → enable the public link.

For external review, mention in *What to Test* that sample data is included and that LiDAR
room scanning needs an iPhone Pro / iPad Pro.
