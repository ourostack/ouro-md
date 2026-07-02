# Mac App Store lane

Ouro MD has two macOS distribution lanes:

- **Developer ID direct download:** signed, notarized zip for in-app updates plus a DMG for human installs.
- **Mac App Store:** sandboxed, privacy-disclosed package uploaded through App Store Connect, with direct updates disabled because the store owns updates.

The App Store build is intentionally not the same artifact as the direct-download build. The store owns updates, privacy answers, review metadata, and distribution.

## App Store Connect setup

Create or confirm the app record before uploading:

- Name: `Ouro MD`
- Subtitle: `The Markdown App`
- Bundle ID: `bot.ouro.md`
- SKU: `bot-ouro-md-macos`
- Platform: macOS
- Category: Developer Tools
- Price: Free
- Support URL: `https://ouro.bot/apps/ouro-md/`
- Marketing URL: `https://ouro.bot/apps/ouro-md/`
- Privacy Policy URL: `https://ouro.bot/privacy/`

Recommended privacy answers for the App Store build:

- Tracking: no
- Third-party advertising: no
- Analytics/data collection: no by default. `scripts/package-app-store.sh` forces telemetry off unless `OURO_MD_APP_STORE_ENABLE_TELEMETRY=1` is set.
- If telemetry is intentionally enabled later, disclose product-interaction analytics and diagnostics only.
- User accounts: no
- User-generated content/social features: no
- Encryption/export compliance: no non-exempt encryption. App packages set `ITSAppUsesNonExemptEncryption=false`; revisit this if a future networking change adds custom cryptography.

Recommended app/version metadata:

- Primary language: English (U.S.)
- Age rating: 4+
- Content rights: Ouro MD owns or has rights to all included content
- License agreement: Apple's standard license agreement
- Copyright: `Copyright © 2026 Ari Mendelow`
- Description: `A quiet Markdown editor for macOS, built for writing, reading, and keeping your document in focus.`
- Keywords: `markdown, editor, notes, writing, documents`
- Review notes: `Ouro MD is a local document editor. No account or sample login is required. Open or create a Markdown file, edit it, switch themes from the app menu, and export from the File menu.`
- Screenshots: capture the real app editing and previewing Markdown, including at least one wide-table document and one clean writing view.
- App previews: optional for the first submission.
- Version release notes: use `OuroMDRelease.releaseHighlights` for the submitted version.

Apple-side assets needed before the first upload:

- Certificates:
  - `Apple Distribution: Ari Mendelow (743GT2AJ24)`
  - `3rd Party Mac Developer Installer: Ari Mendelow (743GT2AJ24)`
- App Store Connect API key with access to apps/build upload, saved as an
  `AuthKey_<key-id>.p8` file. Keep the key id and issuer id with the signing
  secrets; do not commit the key file.
- Bundle ID `bot.ouro.md` registered for macOS with sandbox-compatible
  capabilities. The current App Store entitlements are in
  `config/app-store-entitlements.plist`.

## Build package

Set the signing identities exposed by Keychain:

```sh
export OURO_APP_STORE_APP_IDENTITY="Apple Distribution: ..."
export OURO_APP_STORE_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: ..."
```

Set App Store Connect auth for validation/upload:

```sh
export APP_STORE_CONNECT_API_KEY_ID="..."
export APP_STORE_CONNECT_API_ISSUER_ID="..."
export APP_STORE_CONNECT_API_KEY_PATH="/path/to/AuthKey_....p8"
```

Alternative auth for local validation/upload:

```sh
export APPLE_ID="..."
export APPLE_APP_SPECIFIC_PASSWORD="..."
```

If the Apple account has multiple providers, also set:

```sh
export APP_STORE_CONNECT_PROVIDER_PUBLIC_ID="..."
```

If App Store Connect requires a provisioning profile:

```sh
export OURO_APP_STORE_PROVISIONING_PROFILE="/path/to/profile.provisionprofile"
```

Check local readiness:

```sh
./scripts/package-app-store.sh --readiness
```

Build the package:

```sh
./scripts/package-app-store.sh
```

Validate without upload:

```sh
APP_STORE_CONNECT_API_KEY_ID=... \
APP_STORE_CONNECT_API_ISSUER_ID=... \
APP_STORE_CONNECT_API_KEY_PATH=/path/to/AuthKey_....p8 \
./scripts/package-app-store.sh --validate
```

Upload after validation:

```sh
APP_STORE_CONNECT_API_KEY_ID=... \
APP_STORE_CONNECT_API_ISSUER_ID=... \
APP_STORE_CONNECT_API_KEY_PATH=/path/to/AuthKey_....p8 \
./scripts/package-app-store.sh --upload
```

The package lands at `dist/app-store/Ouro-MD-<version>-app-store.pkg`.

## Behavior differences

The App Store package sets `OuroMDDistributionChannel=app-store` in `Info.plist`.
That disables direct GitHub update checks and hides the direct-update menu items.
Telemetry is off by default for App Store packages. To intentionally ship
telemetry later, set `OURO_MD_APP_STORE_ENABLE_TELEMETRY=1` plus the PostHog
key/host env and update the App Store privacy answers before uploading.
The sandbox entitlement file grants user-selected file/folder read-write access
and network client access so a telemetry-enabled build can reach the disclosed
analytics endpoint without changing entitlements.

The direct-download package keeps `OuroMDDistributionChannel=developer-id`, includes the direct updater, and may include anonymous telemetry when release secrets configure it.
