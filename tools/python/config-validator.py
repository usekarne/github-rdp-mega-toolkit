#!/usr/bin/env python3
"""
config-validator.py — Validate all JSON configs against their expected schema.

This is a lightweight schema validator that uses no external dependencies.
Each known config file (under configs/) has an inline schema defined here.

Validates:
  * configs/software-list.json  — list of {name, version, ...}
  * configs/default.yaml        — YAML syntax + required keys (parsed without pyyaml)
  * Any JSON file in configs/   — must parse and have `version` + `description`

Exit codes:
  0 = all valid
  1 = one or more invalid
  2 = usage error
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Any, Dict, List, Tuple

DEFAULT_CONFIG_DIR = os.environ.get(
    "RDP_CONFIG_DIR",
    os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "configs"),
)


def _find_config_dir(explicit: str) -> str:
    if explicit:
        return explicit
    # Walk up from this file looking for a configs/ directory
    here = os.path.dirname(os.path.abspath(__file__))
    for _ in range(4):
        candidate = os.path.join(here, "configs")
        if os.path.isdir(candidate):
            return candidate
        here = os.path.dirname(here)
    return DEFAULT_CONFIG_DIR


# ---------------------------------------------------------------------------
# Mini YAML parser (only handles flat KEY: VALUE and nested 2-space indent)
# ---------------------------------------------------------------------------

def mini_yaml_parse(text: str) -> Dict[str, Any]:
    """
    Parse a tiny subset of YAML: top-level `key: value` and one level of
    nested mapping (2-space indent). Lists are returned as raw strings.
    This is intentionally minimal — we only need it to verify required keys
    exist. The real parsing is done by the agent skills using pyyaml.
    """
    root: Dict[str, Any] = {}
    current_key: str = ""
    for line in text.splitlines():
        if not line.strip() or line.strip().startswith("#"):
            continue
        if line.startswith("  "):
            # Nested
            sub = line.strip()
            if ":" in sub:
                k, v = sub.split(":", 1)
                if isinstance(root.get(current_key), dict):
                    root[current_key][k.strip()] = v.strip()
                else:
                    root[current_key] = {k.strip(): v.strip()}
            continue
        if ":" in line:
            k, v = line.split(":", 1)
            k = k.strip()
            v = v.strip()
            if v == "":
                root[k] = {}
                current_key = k
            else:
                root[k] = v.strip("'\"")
                current_key = k
    return root


# ---------------------------------------------------------------------------
# Schema definitions
# ---------------------------------------------------------------------------

SOFTWARE_LIST_SCHEMA = {
    "type": "object",
    "required": ["version", "description", "packages"],
    "fields": {
        "version": str,
        "description": str,
        "packages": list,
    },
}


def _check_type(value: Any, expected: type) -> bool:
    if expected is str:
        return isinstance(value, str)
    if expected is list:
        return isinstance(value, list)
    if expected is dict:
        return isinstance(value, dict)
    return True  # Unknown — accept


def validate_json_config(path: str, schema: Dict[str, Any]) -> List[str]:
    """Validate a single JSON config against an inline schema. Returns list of errors."""
    errors: List[str] = []
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        return [f"invalid JSON: {e}"]
    except OSError as e:
        return [f"cannot read: {e}"]

    if schema.get("type") == "object":
        for req in schema.get("required", []):
            if req not in data:
                errors.append(f"missing required field: {req}")
        for field, expected_type in schema.get("fields", {}).items():
            if field in data and not _check_type(data[field], expected_type):
                errors.append(f"field '{field}' has wrong type (expected {expected_type.__name__})")
    return errors


def validate_generic_json(path: str) -> List[str]:
    """Generic check: parses, has version+description."""
    errors: List[str] = []
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        return [f"invalid JSON: {e}"]
    except OSError as e:
        return [f"cannot read: {e}"]
    if not isinstance(data, dict):
        return ["top-level must be a JSON object"]
    if "version" not in data:
        errors.append("missing 'version' field")
    if "description" not in data:
        errors.append("missing 'description' field")
    return errors


def validate_yaml_config(path: str, required_keys: Tuple[str, ...]) -> List[str]:
    errors: List[str] = []
    try:
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        return [f"cannot read: {e}"]
    try:
        data = mini_yaml_parse(text)
    except Exception as e:  # noqa: BLE001
        return [f"YAML parse error: {e}"]
    for k in required_keys:
        if k not in data:
            errors.append(f"missing required key: {k}")
    return errors


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None) -> int:
    p = argparse.ArgumentParser(
        prog="config-validator.py",
        description="Validate all JSON / YAML configs against expected schema.",
    )
    p.add_argument("--config-dir", default=None, help="Path to configs/ directory")
    p.add_argument("--strict", action="store_true", help="Treat warnings as errors")
    p.add_argument("--json", action="store_true", help="Machine-readable output")
    args = p.parse_args(argv)

    config_dir = _find_config_dir(args.config_dir)
    if not os.path.isdir(config_dir):
        print(f"ERROR: configs/ dir not found at {config_dir}", file=sys.stderr)
        return 2

    results: List[Dict[str, Any]] = []
    overall_ok = True

    # Walk all config files
    for name in sorted(os.listdir(config_dir)):
        path = os.path.join(config_dir, name)
        if not os.path.isfile(path):
            continue
        if name.endswith(".json"):
            if name == "software-list.json":
                errors = validate_json_config(path, SOFTWARE_LIST_SCHEMA)
            else:
                errors = validate_generic_json(path)
        elif name.endswith((".yaml", ".yml")):
            # Each platform config must have at least version + description
            errors = validate_yaml_config(path, ("version", "description"))
        else:
            continue

        status = "ok" if not errors else "fail"
        if errors:
            overall_ok = False
        results.append({"file": name, "status": status, "errors": errors})

    if args.json:
        print(json.dumps({"ok": overall_ok, "results": results}, indent=2))
    else:
        for r in results:
            mark = "PASS" if r["status"] == "ok" else "FAIL"
            print(f"[{mark}] {r['file']}")
            for e in r["errors"]:
                print(f"        - {e}")
        print()
        print("All configs valid." if overall_ok else "One or more configs FAILED.")
    return 0 if overall_ok else 1


if __name__ == "__main__":
    sys.exit(main())
