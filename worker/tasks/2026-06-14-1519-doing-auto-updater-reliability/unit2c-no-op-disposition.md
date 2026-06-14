# Unit 2c No-Op Disposition

The following installer lines intentionally remain outside direct unit execution because they are external-process, network, or real app-swap boundaries:

- `OuroMDUpdateInstaller.applyAndRelaunch` / `applyOnQuit`: spawns `/bin/sh` detached from the running app. Direct unit execution would fork a real helper. The generated script is covered by string assertions and by executing the script against temporary directories, including backup, rollback, and no-nested-app behavior.
- `OuroMDUpdateInstaller.defaultData`: uses live `URLSession` for release asset download. Release-update request shape is covered with `URLProtocol`; stager download behavior is covered through injected `dataLoader` success and failure paths. Live asset download is exercised by final packaging/live installer smoke.
- `OuroMDUpdateInstaller.defaultProcessRunner`: launches system processes. Stager process arguments and status handling are covered through injected `processRunner`; the final package/live smoke exercises real `ditto`/codesign-style boundaries where safe.
