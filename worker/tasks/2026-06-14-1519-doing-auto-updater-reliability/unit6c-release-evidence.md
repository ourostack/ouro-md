# Unit 6c Release Evidence

## Release

- URL: https://github.com/ourostack/ouro-md/releases/tag/v0.9.1
- Tag: `v0.9.1`
- Published: `2026-06-15T00:49:04Z`
- Source commit packaged from main: `e7b03d1cb7e5b495beb28413562b7c09ffc42dc6`

## Assets

- `Ouro-MD-0.9.1.zip`
  - bytes: `7166527`
  - sha256: `a788d90771d7f617f57c18bec951be610589e3ed4c3a1bf5de511c682765769b`
- `Ouro-MD-0.9.1.manifest.json`
  - bundle id: `org.ourostack.ouro-md`
  - version/build: `0.9.1` / `0.9.1`
  - archive: `Ouro-MD-0.9.1.zip`

## Live Smoke

Command:

```sh
tmp="$(mktemp -d)"
curl -fsSL https://ouro.bot/ouro-md-install.sh | OURO_MD_INSTALL_DIR="$tmp" OURO_MD_NO_OPEN=1 bash
```

Result:

- exit: `0`
- installed app: `$tmp/Ouro MD.app`
- installed bundle id: `org.ourostack.ouro-md`
- installed version: `0.9.1`
- codesign verify: `ok`

Full output: `unit6c-live-install-smoke.log`
