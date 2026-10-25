#!/usr/bin/env python3
"""
OHMployee Web Closed Loop Mechanical Gate.
Enforces:
1. ESLint (`npm run lint`): 0 errors required.
2. Next.js Build (`npm run build`): No new errors beyond the documented baseline
   pre-existing missing node_modules (exceljs / xlsx) and sandboxed font fetch.
3. Color Literal Zero-Tolerance Gate for touched modules.
"""

import json
import os
import re
import subprocess
import sys

# Baseline known pre-existing build error signatures on clean main
KNOWN_BASELINE_BUILD_ERRORS = [
    "Can't resolve 'exceljs'",
    "Can't resolve 'xlsx'",
    "Failed to fetch `DM Mono`",
    "Failed to fetch `DM Sans`",
    "next/font: error:",
    "There was an issue establishing a connection while requesting",
    "Turbopack build failed with",
]

COLOR_PATTERN = re.compile(
    r'\b(?:bg|text|border)-(?:slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-[0-9]{2,3}\b|#[0-9a-fA-F]{3,8}'
)

# Files allowed to declare raw colors (e.g., globals.css, theme definitions, legacy non-UI scripts)
ALLOWLIST_FILES = {
    "src/app/globals.css",
    "docs/state/web_design_tokens.md",
}

def check_lint():
    result = subprocess.run(["npm", "run", "lint"], capture_output=True, text=True)
    if result.returncode != 0:
        return False, f"ESLint failed:\n{result.stderr or result.stdout}"
    return True, ""

def check_build():
    result = subprocess.run(["npm", "run", "build"], capture_output=True, text=True)
    if result.returncode != 0:
        output = (result.stderr or "") + "\n" + (result.stdout or "")
        lines = output.splitlines()
        # Find module resolution or compilation error lines
        issue_lines = [
            l.strip() for l in lines
            if ("Module not found:" in l or "error:" in l.lower() or "Failed to compile" in l)
            and not any(known in l for known in KNOWN_BASELINE_BUILD_ERRORS)
        ]
        if issue_lines:
            return False, f"New unexpected build error introduced:\n" + "\n".join(issue_lines[:5])
    return True, ""

def check_color_literals(touched_modules):
    if not touched_modules:
        return True, ""

    violations = []
    for mod in touched_modules:
        dirs_to_check = [
            os.path.join("src/app/(dashboard)", mod),
            os.path.join("src/components", mod),
        ]
        for d in dirs_to_check:
            if not os.path.exists(d):
                continue
            for root, _, files in os.walk(d):
                for f in files:
                    if f.endswith((".tsx", ".ts")):
                        rel_path = os.path.relpath(os.path.join(root, f))
                        if rel_path in ALLOWLIST_FILES:
                            continue
                        with open(os.path.join(root, f), "r", errors="ignore") as fp:
                            content = fp.read()
                            matches = COLOR_PATTERN.findall(content)
                            if matches:
                                violations.append(f"{rel_path}: {len(matches)} color literals found (e.g. {matches[:3]})")

    if violations:
        return False, f"Color literal gate FAILED (must be 0 for touched modules):\n" + "\n".join(violations)
    return True, ""

def main():
    # 1. Color Literals Gate (fast fail)
    touched_env = os.environ.get("TOUCHED_MODULES", "").strip()
    touched_modules = [m.strip() for m in touched_env.split(",") if m.strip()]
    color_ok, color_msg = check_color_literals(touched_modules)
    if not color_ok:
        print(json.dumps({"decision": "continue", "reason": f"Verification gate FAILED (Color Literals):\n{color_msg}"}))
        sys.exit(0)

    # 2. Lint Gate
    lint_ok, lint_msg = check_lint()
    if not lint_ok:
        print(json.dumps({"decision": "continue", "reason": f"Verification gate FAILED (Lint):\n{lint_msg}"}))
        sys.exit(0)

    # 3. Build Gate
    build_ok, build_msg = check_build()
    if not build_ok:
        print(json.dumps({"decision": "continue", "reason": f"Verification gate FAILED (Build):\n{build_msg}"}))
        sys.exit(0)

    # Green: allow stop
    print(json.dumps({"decision": "allow"}))
    sys.exit(0)

if __name__ == "__main__":
    main()
