#!/usr/bin/env python3
import json
import pathlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "config" / "ouro-app-control-deck.json"
PACKAGE = ROOT / "Package.swift"


PACKAGE_RE = re.compile(
    r"\.package\(\s*url:\s*\"(?P<url>[^\"]+)\"\s*,\s*(?P<kind>branch|revision|from|exact):\s*\"(?P<value>[^\"]+)\"",
    re.S,
)


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def identity_from_url(url: str) -> str:
    name = url.rstrip("/").rsplit("/", 1)[-1]
    return name.removesuffix(".git").lower()


def load_control_deck(path: pathlib.Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing app control deck: {path}")
    if data.get("schema_version") != 1:
        fail("control deck schema_version must be 1")
    for key in ("app", "shell", "dependency_policy"):
        if not isinstance(data.get(key), dict):
            fail(f"control deck missing object: {key}")
    return data


def direct_dependencies(package_path: pathlib.Path) -> list[dict]:
    text = package_path.read_text(encoding="utf-8")
    deps = []
    for match in PACKAGE_RE.finditer(text):
        url = match.group("url")
        deps.append(
            {
                "url": url,
                "identity": identity_from_url(url),
                "kind": match.group("kind"),
                "value": match.group("value"),
            }
        )
    return deps


def validate(root: pathlib.Path, manifest_path: pathlib.Path, package_path: pathlib.Path) -> None:
    deck = load_control_deck(manifest_path)
    allowed_branch = {
        (entry.get("identity", "").lower(), entry.get("url"), entry.get("branch"))
        for entry in deck["dependency_policy"].get("branch_dependencies", [])
    }
    shell = deck["shell"]
    for guard_key in ("freshness_guard", "boundary_guard"):
        guard = root / shell.get(guard_key, "")
        if not guard.is_file():
            fail(f"shell {guard_key} is missing: {guard}")

    deps = direct_dependencies(package_path)
    if not deps:
        fail(f"no direct package dependencies found in {package_path}")

    for dep in deps:
        if dep["kind"] == "branch":
            key = (dep["identity"], dep["url"], dep["value"])
            if key not in allowed_branch:
                fail(
                    "direct branch dependency is not allowed by control deck: "
                    f"{dep['identity']} {dep['url']} branch {dep['value']}"
                )

    shell_key = (shell["package_identity"], shell["url"], shell["branch"])
    if shell_key not in allowed_branch:
        fail("shell branch dependency policy is not declared")

    print("app control deck ok")


def selftest() -> None:
    with tempfile.TemporaryDirectory(prefix="ouro-md-control-deck-") as raw:
        tmp = pathlib.Path(raw)
        shutil.copytree(ROOT / "config", tmp / "config")
        (tmp / "scripts").mkdir()
        for script in ("check-shell-dependency.sh", "check-shell-boundary.sh"):
            path = tmp / "scripts" / script
            path.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
        package = tmp / "Package.swift"
        package.write_text(
            'let package = Package(dependencies: [\n'
            '  .package(url: "https://github.com/ourostack/ouro-native-apple-app-shell.git", branch: "main"),\n'
            '  .package(url: "https://example.com/floating.git", branch: "main")\n'
            '])\n',
            encoding="utf-8",
        )
        script = pathlib.Path(__file__).resolve()
        result = subprocess.run(
            [
                sys.executable,
                str(script),
                "--root",
                str(tmp),
                "--manifest",
                str(tmp / "config" / "ouro-app-control-deck.json"),
                "--package",
                str(package),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode == 0:
            fail("selftest expected undeclared non-shell branch dependency to fail")
        if "direct branch dependency is not allowed" not in result.stderr:
            fail(f"selftest saw unexpected stderr: {result.stderr}")
    print("app control deck selftest ok")


def main(argv: list[str]) -> None:
    root = ROOT
    manifest = DEFAULT_MANIFEST
    package = PACKAGE
    if "--selftest" in argv:
        selftest()
        return
    args = iter(argv)
    for arg in args:
        if arg == "--root":
            root = pathlib.Path(next(args)).resolve()
        elif arg == "--manifest":
            manifest = pathlib.Path(next(args)).resolve()
        elif arg == "--package":
            package = pathlib.Path(next(args)).resolve()
        else:
            fail(f"unknown argument: {arg}")
    validate(root, manifest, package)


if __name__ == "__main__":
    main(sys.argv[1:])
