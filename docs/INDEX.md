# Ouro MD Docs Index

Use this index to find current source-of-truth docs before reading historical
planning artifacts or task bundles.

## Normative Docs

- [README](../README.md): product summary, install/update workflow, release
  process, build/test commands, telemetry summary, and current status.
- [Privacy](../PRIVACY.md): telemetry and privacy contract.
- [Troubleshooting](TROUBLESHOOTING.md): install, launch, update, and runtime
  problem diagnosis.
- [Uninstall / Reset](UNINSTALL_RESET.md): removal and reset procedures.
- [V1 Acceptance](V1_ACCEPTANCE.md): acceptance criteria for the v1 product
  surface.

## Architecture And Shell Boundary

- [AGENTS](../AGENTS.md): repo-specific agent rules, including shared native app
  shell ownership and the `OuroMDShellAdapter` boundary.
- `Sources/OuroMD/OuroMDShellAdapter.swift`: app-specific shared-shell mapping.
- `scripts/check-shell-boundary.sh`: CI/preflight guard for shell ownership.

## Historical And Task Artifacts

Task planning, audit, and doing artifacts live under `worker/tasks/`. Treat them
as provenance unless a current task explicitly cites one.
