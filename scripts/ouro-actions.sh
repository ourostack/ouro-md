#!/usr/bin/env bash
# Ouro MD's actions come from one declaration (actions/document.actions.mts) through Ouro UI's generator, which is
# vendored from an ouro-ui-core release by hash. Needs Node 22.18 or later.
#
#   scripts/ouro-actions.sh vendor <tag>      take the generator and its claims from that ouro-ui-core release
#   scripts/ouro-actions.sh generate          write every door from the declaration
#   scripts/ouro-actions.sh check             the vendored files match the release's hashes, and nothing generated has drifted
#   scripts/ouro-actions.sh compare-mcp <app-or-binary>   a running `ouro-md --mcp` lists exactly the declared tools
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DIR=tools/ouro-actions
GEN="$DIR/ouro-actions.mts"
DECLARATIONS=actions/document.actions.mts
OUT=Sources/OuroMD/Generated

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
want() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["files"][sys.argv[2]])' "$DIR/dist-manifest.json" "$1"; }

verify_vendored() {
  local tag file
  tag="$(python3 -I -c 'import json; print(json.load(open("'"$DIR"'/dist-manifest.json"))["coreTag"])')"
  for pair in "ouro-actions.mts:dist/actions/ouro-actions.mts" "actions.claims.json:dist/ax/actions.claims.json"; do
    file="${pair%%:*}"
    [[ "$(sha "$DIR/$file")" == "$(want "${pair#*:}")" ]] || {
      echo "error: $DIR/$file isn't the file in ouro-ui-core $tag. Fix: never edit it; run scripts/ouro-actions.sh vendor $tag." >&2
      exit 1
    }
  done
  echo "ok    $DIR matches ouro-ui-core $tag"
}

case "${1:-}" in
  vendor)
    tag="${2:?usage: scripts/ouro-actions.sh vendor <tag>}"
    gh release download "$tag" --repo ourostack/ouro-ui-core --pattern ouro-actions.mts --pattern actions.claims.json --pattern dist-manifest.json --dir "$DIR" --clobber
    verify_vendored
    ;;
  generate)
    node "$GEN" generate "$DECLARATIONS" "$OUT"
    ;;
  check)
    verify_vendored
    node "$GEN" check "$DECLARATIONS" "$OUT"
    ;;
  compare-mcp)
    app="${2:?usage: scripts/ouro-actions.sh compare-mcp <OuroMD.app or the ouro-md binary>}"
    [[ -d "$app" ]] && app="$app/Contents/MacOS/ouro-md"
    scratch="$(mktemp -d)"
    trap 'mv "$scratch" ~/.Trash/ 2>/dev/null || true' EXIT
    printf '%s\n' \
      '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
      '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
      | "$app" --mcp --root "$scratch" \
      | python3 -I -c 'import json,sys; [print(json.dumps(m["result"])) for m in map(json.loads, sys.stdin) if m.get("id") == 2]' > "$scratch/tools.json"
    node "$GEN" compare-mcp "$DECLARATIONS" "$scratch/tools.json"
    ;;
  *)
    sed -n '2,9p' "$0" >&2
    exit 2
    ;;
esac
