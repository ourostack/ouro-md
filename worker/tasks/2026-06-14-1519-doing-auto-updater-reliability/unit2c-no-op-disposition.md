# Unit 2c No-Op Disposition

The installer/stager's injected seams are covered directly:

- Injected `dataLoader` success, generic failure wrapping as `.download`, and pre-existing `InstallError` pass-through are covered by `OuroMDUpdateInstallerTests`.
- Injected `processRunner` success, unzip failure, codesign failure, and command argument shape are covered by `OuroMDUpdateInstallerTests`.
- The generated apply-helper shell is covered by string/order assertions and by executing the script against temporary directories for no-nested-app, rollback, stale-backup restoration, and cleanup behavior.

The following lines intentionally remain outside direct unit execution because they cross real network/process/app lifecycle boundaries:

- `OuroMDUpdateInstaller.applyAndRelaunch` / `applyOnQuit`: spawns `/bin/sh` detached from the running app. Direct unit execution would fork a real update helper. Its generated script is covered as described above, and the final release flow exercises the consuming install surface with a live installer smoke.
- `OuroMDUpdateInstaller.defaultData`: uses live `URLSession` for release asset download. Request construction for GitHub release checks is covered with `URLProtocol`; stager network behavior is covered through injected `dataLoader` success and failure paths. Live asset download is exercised by final packaging/live installer smoke.
- `OuroMDUpdateInstaller.defaultProcessRunner`: launches system processes. Stager process arguments and status handling are covered through injected `processRunner`; the final package/live smoke exercises real archive/install boundaries where safe.
