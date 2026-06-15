# Large Document Roundtrip Boundary

Synthetic WebView roundtrip is green for a 551,429-byte plain Markdown fixture
(`large-doc-roundtrip.log`).

Heavier probes exposed a current limitation rather than a green result:

- `large-doc-roundtrip-3_9mb-timeout.log`: 3,949,125-byte fixture timed out.
- A 1,324,929-byte plain fixture also timed out during local probing.

Disposition for v1 dogfood: ordinary large notes are covered, but multi-megabyte
editor roundtrip is not yet a claimed v1 capability. If Ari hits this in real
use, telemetry plus these artifacts give us the next performance target.
