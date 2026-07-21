#!/usr/bin/env python3
"""
Rewrite pubspec.yaml with pinned versions from pubspec.lock.

Rules:
- For hosted packages (name only): replace version constraint with the
  exact version from pubspec.lock.
- Git packages are LEFT UNTOUCHED. Their `ref:` (branch/tag) cannot be
  rewritten to a commit SHA because other git packages may reference
  them by ref name (e.g. audio_service depends on audio_session at
  br_v0.2.2_ohos). Rewriting breaks pub's version solving.
- Commented-out lines are left untouched.
- Packages declared with `sdk: flutter` are left untouched.
- The version of the root package itself (top-level `version:`) is
  left untouched.
- `any` constraints on direct deps (vector_math, fixnum, etc.) are
  replaced with the exact version from the lock.
"""

import re
import sys
from collections import defaultdict
from pathlib import Path

import yaml

ROOT = Path("/workspace")
LOCK_PATH = ROOT / "pubspec.lock"
YAML_PATH = ROOT / "pubspec.yaml"


def parse_lock():
    """Return dict: package_name -> {version, git_info}."""
    with open(LOCK_PATH, "r", encoding="utf-8") as f:
        lock = yaml.safe_load(f)
    pkgs = {}
    for name, info in (lock.get("packages") or {}).items():
        entry = {
            "version": info.get("version"),
            "source": info.get("source"),
            "dependency": info.get("dependency"),
        }
        desc = info.get("description") or {}
        if info.get("source") == "git":
            entry["url"] = desc.get("url")
            entry["path"] = desc.get("path")
            entry["ref"] = desc.get("ref")
            entry["resolved_ref"] = desc.get("resolved-ref")
        pkgs[name] = entry
    return pkgs


def main():
    lock = parse_lock()
    text = YAML_PATH.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)

    # Build a per-line transformation. We need to track context (which
    # package block we're inside, whether it's a git block, etc.) by
    # scanning top to bottom.

    out = []
    i = 0
    n = len(lines)
    # current package name we are inside (most recent top-level dep name)
    # tracked at indentation level 2 under dependencies: / dependency_overrides:
    current_pkg = None
    current_section = None  # 'dependencies', 'dependency_overrides', 'dev_dependencies'
    in_git_block = False  # True if current_pkg is declared as a git map
    git_block_indent = None

    def is_comment(line):
        s = line.lstrip()
        return s.startswith("#")

    while i < n:
        line = lines[i]
        stripped = line.lstrip()

        # Detect section headers. Match either deps sections (where we
        # rewrite versions) or any other top-level mapping (where we
        # stop rewriting). A top-level key has no leading indentation
        # and ends with ':'.
        m_section = re.match(r"^([A-Za-z0-9_]+):\s*$", line)
        if m_section:
            sec = m_section.group(1)
            if sec in ("dependencies", "dependency_overrides", "dev_dependencies"):
                current_section = sec
            else:
                # Leaving deps sections (e.g. flutter_launcher_icons,
                # flutter_native_splash, flutter:)
                current_section = None
            current_pkg = None
            in_git_block = False
            out.append(line)
            i += 1
            continue

        # If we're not in a deps section, just pass through
        if current_section is None:
            out.append(line)
            i += 1
            continue

        # Blank line resets git block tracking
        if stripped == "" or stripped == "\n":
            in_git_block = False
            out.append(line)
            i += 1
            continue

        # Top-level dep entry: "  name: ..." (indent 2)
        m_dep = re.match(r"^( {2})([A-Za-z0-9_]+):\s*(.*)$", line)
        if m_dep:
            indent, name, rest = m_dep.groups()
            current_pkg = name
            in_git_block = False
            git_block_indent = None
            info = lock.get(name)

            if rest == "" or rest == "#":
                # Either a git block header (name: with nothing after),
                # or section end. We'll detect git block by looking ahead.
                # Pass through; the git block handling below will rewrite ref.
                out.append(line)
                i += 1
                continue

            # Inline value cases:
            # - sdk: flutter
            # - ^1.2.3
            # - 1.2.3
            # - any
            # - ^1.2.3 # comment
            rest_stripped = rest.strip()

            # sdk: flutter
            if rest_stripped.startswith("sdk:"):
                out.append(line)
                i += 1
                continue

            # Extract optional inline comment
            # Split on first ' #' that's not in a string
            code_part = rest_stripped
            comment_part = ""
            # only treat # as comment if preceded by space or at start
            hash_idx = rest.find("#")
            if hash_idx != -1:
                # check there is content (or space) before
                if hash_idx == 0 or rest[hash_idx - 1] == " ":
                    code_part = rest[:hash_idx].rstrip()
                    comment_part = rest[hash_idx:]

            # Now code_part is the version constraint (possibly with trailing space)
            code_part = code_part.strip()

            if info is None:
                # Not in lock (shouldn't happen for direct deps); leave as-is
                out.append(line)
                i += 1
                continue

            if code_part == "any":
                # Replace with exact version
                ver = info.get("version")
                if ver:
                    new_rest = f"{ver}"
                    if comment_part:
                        new_rest = f"{new_rest} {comment_part}"
                    out.append(f"{indent}{name}: {new_rest}\n")
                else:
                    out.append(line)
                i += 1
                continue

            # version constraint like ^1.2.3 or 1.2.3 or >=1.0.0 <2.0.0
            # Replace with exact version from lock
            ver = info.get("version")
            if ver and info.get("source") == "hosted":
                # Pin to exact version
                new_rest = f"{ver}"
                if comment_part:
                    new_rest = f"{new_rest} {comment_part}"
                out.append(f"{indent}{name}: {new_rest}\n")
                i += 1
                continue

            # Otherwise (e.g. git inline? unlikely) leave as-is
            out.append(line)
            i += 1
            continue

        # Inside a git block: lines like "      url: ...", "      ref: ...", "      path: ..."
        # Git packages are left untouched (see module docstring).
        m_git_kv = re.match(r"^( {4,})(url|ref|path):\s*(.*)$", line)
        if m_git_kv and current_pkg is not None:
            out.append(line)
            i += 1
            continue

        # Default: pass through
        out.append(line)
        i += 1

    new_text = "".join(out)
    YAML_PATH.write_text(new_text, encoding="utf-8")
    print("pubspec.yaml updated with pinned versions (git refs untouched).")


if __name__ == "__main__":
    main()
