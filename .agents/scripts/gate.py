#!/usr/bin/env python3
"""
OHMployee Web Closed Loop Mechanical Gate.
Enforces:
1. Auto-derivation of touched modules via git diff (working tree, staged, or HEAD~1).
   If TOUCHED_MODULES env var is explicitly provided, it uses that target list.
2. Global file check: if src/components/shared/ or src/app/globals.css changed,
   the gate always runs the full build/typecheck regardless of touched modules.
3. ESLint (`npm run lint`): 0 errors required.
4. Next.js Build / Typecheck:
   Runs `npm run build`. If `next build` fails solely due to sandboxed Google Fonts network fetch,
   falls back to `npx tsc --noEmit` and explicitly notes the fallback. Blocks on any real build or type failure.
5. Color Literal Zero-Tolerance Gate for all touched modules.
"""

import json
import os
import re
import subprocess
import sys

COLOR_PATTERN = re.compile(
    r'\b(?:bg|text|border)-(?:slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-[0-9]{2,3}\b|#[0-9a-fA-F]{3,8}'
)

ALLOWLIST_FILES = {
    "src/app/globals.css",
    "docs/state/web_design_tokens.md",
}

IGNORED_MODULE_DIRS = {"shared", "ui", "modals"}

def get_git_touched_files():
    touched = set()
    # 1. Working tree + staged diff against HEAD
    try:
        res = subprocess.run(["git", "diff", "--name-only", "HEAD"], capture_output=True, text=True)
        if res.returncode == 0:
            touched.update(line.strip() for line in res.stdout.splitlines() if line.strip())
    except Exception:
        pass

    # 2. Untracked files
    try:
        res = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True)
        if res.returncode == 0:
            for line in res.stdout.splitlines():
                if line.startswith("??"):
                    touched.add(line[3:].strip())
    except Exception:
        pass

    # 3. If working tree is clean or to capture latest commit changes
    try:
        res = subprocess.run(["git", "diff", "--name-only", "HEAD~1..HEAD"], capture_output=True, text=True)
        if res.returncode == 0:
            touched.update(line.strip() for line in res.stdout.splitlines() if line.strip())
    except Exception:
        pass

    return touched

def derive_touched_modules(touched_files):
    # Check if global shared files were touched in git diff
    global_touched = any(
        path.startswith("src/components/shared/") or path == "src/app/globals.css"
        for path in touched_files
    )

    env_modules = os.environ.get("TOUCHED_MODULES", "").strip()
    if env_modules:
        modules = {m.strip() for m in env_modules.split(",") if m.strip()}
        return sorted(list(modules)), global_touched

    modules = set()
    for path in touched_files:
        m_app = re.match(r"^src/app/\(dashboard\)/([^/]+)/", path)
        if m_app:
            mod = m_app.group(1)
            if mod not in IGNORED_MODULE_DIRS:
                modules.add(mod)

        m_comp = re.match(r"^src/components/([^/]+)/", path)
        if m_comp:
            mod = m_comp.group(1)
            if mod not in IGNORED_MODULE_DIRS:
                modules.add(mod)

    return sorted(list(modules)), global_touched

def check_lint():
    result = subprocess.run(["npm", "run", "lint"], capture_output=True, text=True)
    if result.returncode != 0:
        return False, f"ESLint failed:\n{result.stderr or result.stdout}"
    return True, ""

def check_build():
    # Attempt real next build
    result = subprocess.run(["npm", "run", "build"], capture_output=True, text=True)
    if result.returncode == 0:
        return True, "'npm run build' completed successfully (0 errors)."

    output = (result.stderr or "") + "\n" + (result.stdout or "")

    # Check if failure is exclusively caused by sandbox offline font-fetching
    font_fetch_signatures = [
        "Failed to fetch `DM Mono`",
        "Failed to fetch `DM Sans`",
        "next/font: error:",
        "There was an issue establishing a connection while requesting https://fonts.googleapis.com",
    ]
    is_font_fetch_only = any(sig in output for sig in font_fetch_signatures) and "Failed to type check" not in output and "Type error:" not in output

    if is_font_fetch_only:
        # Fallback to full TypeScript typecheck
        tsc_res = subprocess.run(["npx", "tsc", "--noEmit"], capture_output=True, text=True)
        if tsc_res.returncode != 0:
            tsc_output = (tsc_res.stderr or "") + "\n" + (tsc_res.stdout or "")
            return False, f"TypeScript typecheck failed (tsc --noEmit):\n{tsc_output.strip()}"

        fallback_msg = (
            "NOTICE (tsc fallback used): 'next build' font-fetch blocked by sandbox offline policy. "
            "'npx tsc --noEmit' executed and passed with 0 errors. "
            "(Ohm runs full 'npm run build' locally before merge)."
        )
        return True, fallback_msg

    # Any other compilation or type error is a hard failure
    return False, f"Build failed with errors:\n{output.strip()}"

def check_color_literals(touched_modules):
    if not touched_modules:
        return True, ""

    violations = []
    for mod in touched_modules:
        if mod == "hr-emploc-5a":
            dirs_to_check = [
                os.path.join("src/app/(dashboard)", "hr-emploc"),
                os.path.join("src/components", "hr-emploc"),
            ]
        elif mod == "hr-emploc-5b":
            dirs_to_check = [
                os.path.join("src/components", "hr-emploc", "import"),
            ]
        else:
            dirs_to_check = [
                os.path.join("src/app/(dashboard)", mod),
                os.path.join("src/components", mod),
            ]

        for d in dirs_to_check:
            if not os.path.exists(d):
                continue
            for root, dirs, files in os.walk(d):
                if mod == "hr-emploc-5a" and "import" in dirs:
                    dirs.remove("import")
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
    touched_files = get_git_touched_files()
    touched_modules, global_touched = derive_touched_modules(touched_files)

    notes = []
    if global_touched:
        notes.append("Global shared components or styles touched; running unconditional full build/typecheck.")

    # 1. Color Literals Gate for touched modules
    color_ok, color_msg = check_color_literals(touched_modules)
    if not color_ok:
        print(json.dumps({
            "decision": "continue",
            "reason": f"Verification gate FAILED (Color Literals):\n{color_msg}",
            "touched_modules": touched_modules
        }))
        sys.exit(0)

    # 2. Lint Gate
    lint_ok, lint_msg = check_lint()
    if not lint_ok:
        print(json.dumps({
            "decision": "continue",
            "reason": f"Verification gate FAILED (Lint):\n{lint_msg}",
            "touched_modules": touched_modules
        }))
        sys.exit(0)

    # 3. Build Gate
    build_ok, build_msg = check_build()
    if not build_ok:
        print(json.dumps({
            "decision": "continue",
            "reason": f"Verification gate FAILED (Build):\n{build_msg}",
            "touched_modules": touched_modules
        }))
        sys.exit(0)

    notes.append(build_msg)

    # Gate Allow
    print(json.dumps({
        "decision": "allow",
        "touched_modules": touched_modules,
        "notes": notes
    }))
    sys.exit(0)

if __name__ == "__main__":
    main()
