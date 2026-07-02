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

Recommended privacy answers for the App Store build:

- Tracking: no
- Third-party advertising: no
- Analytics/data collection: yes, if the build embeds the PostHog key; disclose product-interaction analytics and diagnostics only
- User accounts: no
- User-generated content/social features: no
- Encryption/export compliance: uses only standard Apple/platform encryption unless a future networking change adds custom cryptography

## Build package

Set the signing identities exposed by Keychain:

```sh
export OURO_APP_STORE_APP_IDENTITY="Apple Distribution: ..."
export OURO_APP_STORE_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: ..."
```

If App Store Connect requires a provisioning profile:

```sh
export OURO_APP_STORE_PROVISIONING_PROFILE="/path/to/profile.provisionprofile"
```

Build the package:

```sh
./scripts/package-app-store.sh
```

Validate without upload:

```sh
APP_STORE_CONNECT_API_KEY_ID=... \
APP_STORE_CONNECT_API_ISSUER_ID=... \
./scripts/package-app-store.sh --validate
```

Upload after validation:

```sh
APP_STORE_CONNECT_API_KEY_ID=... \
APP_STORE_CONNECT_API_ISSUER_ID=... \
./scripts/package-app-store.sh --upload
```

The package lands at `dist/app-store/Ouro-MD-<version>-app-store.pkg`.

## Behavior differences

The App Store package sets `OuroMDDistributionChannel=app-store` in `Info.plist`.
That disables direct GitHub update checks and hides the direct-update menu items.
Telemetry follows the normal release packaging contract: it is content-free, can
be disabled with `OURO_MD_TELEMETRY_DISABLED=1`, and must be disclosed in App
Store privacy answers when enabled.
The sandbox entitlement file grants user-selected file/folder read-write access
and network client access for that disclosed telemetry endpoint.

The direct-download package keeps `OuroMDDistributionChannel=developer-id`, includes the direct updater, and may include anonymous telemetry when release secrets configure it.
