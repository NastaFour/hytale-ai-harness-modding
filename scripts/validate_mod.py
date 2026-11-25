#!/usr/bin/env python3
"""Offline static validator for Hytale 2026 server plugins and content packs."""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import struct
import sys
import tempfile
import zlib
from dataclasses import dataclass
from pathlib import Path

FORBIDDEN_DESCRIPTORS = ("plugin.yml", "fabric.mod.json", "neoforge.mods.toml")
PASCAL_CASE_RE = re.compile(r"^[A-Z][A-Za-z0-9]*$")
SEMVER_RANGE_RE = re.compile(r"[><=^~\s]")
UI_APPEND_RE = re.compile(r'\.append\(\s*"([^"]+\.ui)"\s*\)')
THIRTY_TWO_PX_DIRS = ("Blocks", "Characters", "Items", "NPC")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


@dataclass
class Issue:
    severity: str  # "ERROR" | "WARN"
    message: str


def read_png_dimensions(path: Path) -> tuple[int, int]:
    """Read width and height from a PNG IHDR chunk using stdlib only."""
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != PNG_SIGNATURE or data[12:16] != b"IHDR":
        raise ValueError("Not a valid PNG file")
    width, height = struct.unpack(">II", data[16:24])
    return width, height


def detect_layout(project_dir: Path) -> tuple[str | None, Path | None, Path | None]:
    """Detect whether project_dir uses a Gradle plugin layout or a Pure Asset Pack layout."""
    gradle_resources = project_dir / "src" / "main" / "resources"
    if (gradle_resources / "manifest.json").is_file():
        java_root = project_dir / "src" / "main" / "java"
        return "gradle", gradle_resources, (java_root if java_root.is_dir() else None)
    if (project_dir / "manifest.json").is_file():
        return "asset_pack", project_dir, None
    return None, None, None


def validate_manifest(
    manifest_path: Path,
    mode: str,
    resources_root: Path,
    expected_server_version: str | None,
    issues: list[Issue],
) -> None:
    """Validate manifest.json PascalCase keys, required fields, ServerVersion, and IncludesAssetPack."""
    try:
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        issues.append(Issue("ERROR", f"Invalid JSON in {manifest_path}: {exc}"))
        return

    if not isinstance(data, dict):
        issues.append(Issue("ERROR", f"{manifest_path} root must be a JSON object."))
        return

    for key in data.keys():
        if not PASCAL_CASE_RE.match(key):
            issues.append(Issue("ERROR", f"Non-PascalCase manifest key '{key}' in {manifest_path}."))

    name = data.get("Name")
    if not isinstance(name, str) or not name.strip():
        issues.append(Issue("ERROR", f"Missing required PascalCase 'Name' in {manifest_path}."))

    if mode == "gradle":
        main_cls = data.get("Main")
        if not isinstance(main_cls, str) or not main_cls.strip():
            issues.append(Issue("ERROR", f"Gradle Java plugin requires 'Main' in {manifest_path}."))

    srv_ver = data.get("ServerVersion")
    if srv_ver is not None:
        if not isinstance(srv_ver, str) or not srv_ver.strip():
            issues.append(Issue("ERROR", "'ServerVersion' must be a non-empty string."))
        elif srv_ver.strip() == "*" or SEMVER_RANGE_RE.search(srv_ver.strip()):
            issues.append(
                Issue(
                    "ERROR",
                    f"'ServerVersion' value '{srv_ver}' is forbidden; use exact server version string.",
                )
            )
        elif expected_server_version and srv_ver.strip() != expected_server_version:
            issues.append(
                Issue(
                    "ERROR",
                    f"'ServerVersion' '{srv_ver}' does not match target '{expected_server_version}'.",
                )
            )
    elif expected_server_version:
        issues.append(
            Issue(
                "ERROR",
                f"Missing 'ServerVersion' (expected exact match '{expected_server_version}').",
            )
        )

    if not expected_server_version:
        issues.append(Issue("WARN", "--server-version omitted; exact ServerVersion equality not checked."))

    has_assets = (resources_root / "Common").is_dir() or (resources_root / "Server").is_dir()
    if mode == "gradle" and has_assets and data.get("IncludesAssetPack") is not True:
        issues.append(
            Issue(
                "ERROR",
                "Bundled Common/ or Server/ assets require '\"IncludesAssetPack\": true' in manifest.json.",
            )
        )


def validate_project(
    project_dir: Path,
    server_version: str | None = None,
    schemas_dir: Path | None = None,
) -> list[Issue]:
    """Run all static checks on a Hytale plugin or content pack directory."""
    issues: list[Issue] = []

    mode, resources_root, java_root = detect_layout(project_dir)

    # Check forbidden Minecraft descriptors regardless of layout detection
    search_roots = {project_dir}
    if resources_root:
        search_roots.add(resources_root)
    candidate_resources = project_dir / "src" / "main" / "resources"
    if candidate_resources.is_dir():
        search_roots.add(candidate_resources)

    for root in search_roots:
        for fname in FORBIDDEN_DESCRIPTORS:
            if (root / fname).is_file():
                issues.append(Issue("ERROR", f"Forbidden Minecraft descriptor found: {root / fname}"))

    if mode is None or resources_root is None:
        issues.append(
            Issue(
                "ERROR",
                f"No Hytale manifest.json found under '{project_dir / 'src/main/resources'}' or '{project_dir}'.",
            )
        )
        return issues

    validate_manifest(resources_root / "manifest.json", mode, resources_root, server_version, issues)

    # Validate JSON syntax under Server/
    server_dir = resources_root / "Server"
    if server_dir.is_dir():
        for json_file in server_dir.rglob("*.json"):
            try:
                json.loads(json_file.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as exc:
                issues.append(Issue("ERROR", f"Invalid JSON in {json_file}: {exc}"))

    if schemas_dir is None or not schemas_dir.is_dir() or not any(schemas_dir.glob("*.json")):
        issues.append(
            Issue(
                "WARN",
                "Schemas directory missing or empty; JSON Schema validation skipped (JSON syntax checked).",
            )
        )
    elif importlib.util.find_spec("jsonschema") is None:
        issues.append(
            Issue(
                "WARN",
                "Python 'jsonschema' package not installed; JSON Schema validation skipped (JSON syntax checked).",
            )
        )

    # Cross-check Java .ui append() references against Common/UI/Custom/
    ui_root = resources_root / "Common" / "UI" / "Custom"
    if java_root and java_root.is_dir():
        for java_file in java_root.rglob("*.java"):
            try:
                text = java_file.read_text(encoding="utf-8")
            except OSError as exc:
                issues.append(Issue("ERROR", f"Could not read {java_file}: {exc}"))
                continue
            for ui_ref in UI_APPEND_RE.findall(text):
                rel = ui_ref.lstrip("/\\")
                target_ui = ui_root / rel
                if not target_ui.is_file():
                    issues.append(
                        Issue(
                            "ERROR",
                            f"Java file {java_file.name} references missing UI template '{ui_ref}' (expected {target_ui}).",
                        )
                    )

    # Check 32px-multiple PNG dimensions strictly under 3D asset directories (explicitly excluding Common/UI)
    common_dir = resources_root / "Common"
    if common_dir.is_dir():
        for subdir in THIRTY_TWO_PX_DIRS:
            asset_dir = common_dir / subdir
            if not asset_dir.is_dir():
                continue
            for png_file in asset_dir.rglob("*.png"):
                try:
                    w, h = read_png_dimensions(png_file)
                except (OSError, ValueError) as exc:
                    issues.append(Issue("ERROR", f"Invalid PNG '{png_file}': {exc}"))
                    continue
                if w <= 0 or h <= 0 or (w % 32) != 0 or (h % 32) != 0:
                    issues.append(
                        Issue(
                            "ERROR",
                            f"3D texture '{png_file}' has size {w}x{h}; Hytale requires multiples of 32px.",
                        )
                    )

    return issues


def _make_png(path: Path, width: int, height: int) -> None:
    """Write a minimal valid PNG header+IHDR for self-test fixtures."""
    path.parent.mkdir(parents=True, exist_ok=True)
    ihdr_data = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    ihdr_crc = struct.pack(">I", zlib.crc32(b"IHDR" + ihdr_data) & 0xFFFFFFFF)
    ihdr = struct.pack(">I", len(ihdr_data)) + b"IHDR" + ihdr_data + ihdr_crc
    iend_crc = struct.pack(">I", zlib.crc32(b"IEND") & 0xFFFFFFFF)
    iend = struct.pack(">I", 0) + b"IEND" + iend_crc
    path.write_bytes(PNG_SIGNATURE + ihdr + iend)


def run_self_test() -> int:
    """Run deterministic self-tests covering Gradle, Asset Pack, UI exemption, and failure modes."""
    tests_run = 0
    with tempfile.TemporaryDirectory(prefix="hytale_val_test_") as tmp:
        root = Path(tmp)

        # 1. Valid Gradle plugin + UI non-32px texture (should pass with 0 errors)
        g_dir = root / "valid_gradle"
        (g_dir / "src/main/resources/Common/UI/Custom").mkdir(parents=True)
        (g_dir / "src/main/resources/Common/UI/Custom/Menu.ui").write_text("Group {}", encoding="utf-8")
        _make_png(g_dir / "src/main/resources/Common/UI/Custom/Btn.png", 17, 23)
        _make_png(g_dir / "src/main/resources/Common/Blocks/Stone.png", 64, 32)
        (g_dir / "src/main/resources/Server/Item/Items").mkdir(parents=True)
        (g_dir / "src/main/resources/Server/Item/Items/Test.json").write_text('{"Id":"Test"}', encoding="utf-8")
        (g_dir / "src/main/resources/manifest.json").write_text(
            json.dumps(
                {
                    "Name": "ValidMod",
                    "Group": "com.example",
                    "Version": "1.0.0",
                    "Main": "com.example.ValidMod",
                    "ServerVersion": "2026.02.19-1a311a592",
                    "IncludesAssetPack": True,
                }
            ),
            encoding="utf-8",
        )
        (g_dir / "src/main/java/com/example").mkdir(parents=True)
        (g_dir / "src/main/java/com/example/ValidPage.java").write_text(
            'class ValidPage { void build() { commands.append("Menu.ui"); } }', encoding="utf-8"
        )
        issues = validate_project(g_dir, server_version="2026.02.19-1a311a592")
        assert not [i for i in issues if i.severity == "ERROR"], f"Test 1 failed: {issues}"
        tests_run += 1

        # 2. Valid Pure Asset Pack (no Main required)
        a_dir = root / "valid_pack"
        (a_dir / "Server/Drops").mkdir(parents=True)
        (a_dir / "Server/Drops/Loot.json").write_text('{"Entries":[]}', encoding="utf-8")
        (a_dir / "manifest.json").write_text(
            json.dumps({"Name": "ValidPack", "ServerVersion": "2026.02.19-1a311a592"}), encoding="utf-8"
        )
        issues = validate_project(a_dir, server_version="2026.02.19-1a311a592")
        assert not [i for i in issues if i.severity == "ERROR"], f"Test 2 failed: {issues}"
        tests_run += 1

        # 3. camelCase manifest + ServerVersion "*" must fail
        bad_manifest = root / "bad_manifest"
        bad_manifest.mkdir(parents=True)
        (bad_manifest / "manifest.json").write_text(
            json.dumps({"name": "bad", "ServerVersion": "*"}), encoding="utf-8"
        )
        errs = [i.message for i in validate_project(bad_manifest, server_version="2026.02.19-1a311a592") if i.severity == "ERROR"]
        assert len(errs) >= 3, f"Test 3 failed: {errs}"
        tests_run += 1

        # 4. Gradle plugin bundling Server/ without IncludesAssetPack: true must fail
        no_pack = root / "missing_includes_asset_pack"
        (no_pack / "src/main/resources/Server").mkdir(parents=True)
        (no_pack / "src/main/resources/manifest.json").write_text(
            json.dumps({"Name": "NoPack", "Main": "com.example.NoPack", "ServerVersion": "2026.02.19-1a311a592"}),
            encoding="utf-8",
        )
        errs = [i.message for i in validate_project(no_pack, server_version="2026.02.19-1a311a592") if i.severity == "ERROR"]
        assert any("IncludesAssetPack" in e for e in errs), f"Test 4 failed: {errs}"
        tests_run += 1

        # 5. Non-32px PNG in Common/Blocks/ must fail
        bad_png = root / "bad_block_png"
        _make_png(bad_png / "Common/Blocks/Bad.png", 48, 32)
        (bad_png / "manifest.json").write_text(
            json.dumps({"Name": "BadPng", "ServerVersion": "2026.02.19-1a311a592"}), encoding="utf-8"
        )
        errs = [i.message for i in validate_project(bad_png, server_version="2026.02.19-1a311a592") if i.severity == "ERROR"]
        assert any("32px" in e for e in errs), f"Test 5 failed: {errs}"
        tests_run += 1

        # 6. Broken .ui append() reference in Java must fail
        bad_ui = root / "bad_ui_ref"
        (bad_ui / "src/main/resources/Common/UI/Custom").mkdir(parents=True)
        (bad_ui / "src/main/resources/manifest.json").write_text(
            json.dumps(
                {
                    "Name": "BadUi",
                    "Main": "com.example.BadUi",
                    "ServerVersion": "2026.02.19-1a311a592",
                    "IncludesAssetPack": True,
                }
            ),
            encoding="utf-8",
        )
        (bad_ui / "src/main/java/com/example").mkdir(parents=True)
        (bad_ui / "src/main/java/com/example/Page.java").write_text(
            'class Page { void b() { commands.append("Missing.ui"); } }', encoding="utf-8"
        )
        errs = [i.message for i in validate_project(bad_ui, server_version="2026.02.19-1a311a592") if i.severity == "ERROR"]
        assert any("Missing.ui" in e for e in errs), f"Test 6 failed: {errs}"
        tests_run += 1

    print(f"validate_mod.py self-test PASSED ({tests_run}/{tests_run} cases).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Offline static validator for Hytale 2026 mods.")
    parser.add_argument("project_dir", nargs="?", help="Path to mod or content pack directory")
    parser.add_argument("--self-test", action="store_true", help="Run built-in validation self-tests")
    parser.add_argument("--server-version", help="Expected exact Hytale ServerVersion string")
    parser.add_argument("--schemas-dir", help="Path to extracted JSON Schemas directory")
    parser.add_argument("--strict", action="store_true", help="Treat warnings as failures")
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    if not args.project_dir:
        parser.error("project_dir is required unless --self-test is passed.")
        return 2

    project_path = Path(args.project_dir).resolve()
    if not project_path.is_dir():
        print(f"[ERROR] project_dir is not a directory: {project_path}", file=sys.stderr)
        return 2

    schemas_path = Path(args.schemas_dir).resolve() if args.schemas_dir else None
    issues = validate_project(project_path, server_version=args.server_version, schemas_dir=schemas_path)

    errors = [i for i in issues if i.severity == "ERROR"]
    warnings = [i for i in issues if i.severity == "WARN"]

    for issue in issues:
        print(f"[{issue.severity}] {issue.message}")

    if errors or (args.strict and warnings):
        print(f"Validation FAILED: {len(errors)} error(s), {len(warnings)} warning(s).")
        return 1

    print(f"Validation PASSED: 0 error(s), {len(warnings)} warning(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
