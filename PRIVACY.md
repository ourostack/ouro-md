# Ouro MD Privacy

Ouro MD is a local-first Markdown editor. Your documents stay on your Mac.

## Telemetry

Release builds may send anonymous product telemetry to PostHog when a PostHog
project key is embedded by the release package.

Ouro MD may send:

- App launch events.
- Update check, stage, install, cancel, and failure status events.
- Document create/open events with coarse file-type flags.
- Document save/open/rename/reload success or failure events with coarse codes
  such as `manual`, `autosave`, `write_failed`, `editor_not_ready`,
  `collision`, or `keep_edits`.
- Folder open events.
- Export success/failure events with the export format.
- Editor web-view crash recovery events.
- App version, bundle id, macOS version, architecture, and an anonymous install
  id stored in local preferences.

Ouro MD does not send:

- Document contents.
- Filenames.
- Folder paths.
- Search queries.
- Clipboard contents.
- Raw error messages.
- PostHog session replay or autocapture data.
- Personal profile data; events set `$process_person_profile` to `false`.

## Opt Out

Open **Ouro MD -> Settings -> Telemetry** and turn off
**Share anonymous usage telemetry**.

Telemetry is also disabled when the app has no embedded PostHog key, which is
the default for local development builds.

## Notes For Maintainers

`make-app.sh` can embed telemetry configuration from `OURO_MD_POSTHOG_KEY` /
`OURO_MD_POSTHOG_HOST`, or Spoonjoy-style `VITE_POSTHOG_KEY` /
`VITE_POSTHOG_HOST`. These values are release-time inputs and are not committed
to the repository.

Runtime ambient PostHog environment variables do not enable telemetry.
