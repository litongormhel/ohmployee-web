#!/usr/bin/env python3
"""
scripts/audit_component_contrast.py

Scans globals.css and shared components in src/components/shared/ and src/components/ui/
to report every `bg-* text-*` pair used together with computed WCAG contrast ratios
for both Light and Dark themes.
"""

import os
import re
import sys
from collections import defaultdict

def hex_to_rgb(hex_str):
    hex_str = hex_str.strip().lstrip('#')
    if len(hex_str) == 3:
        hex_str = ''.join(c * 2 for c in hex_str)
    return tuple(int(hex_str[i:i+2], 16) for i in (0, 2, 4))

def parse_rgba(rgba_str):
    m = re.match(r'rgba?\s*\(\s*([\d\.]+)\s*,\s*([\d\.]+)\s*,\s*([\d\.]+)(?:\s*,\s*([\d\.]+))?\s*\)', rgba_str)
    if m:
        r, g, b = float(m.group(1)), float(m.group(2)), float(m.group(3))
        a = float(m.group(4)) if m.group(4) is not None else 1.0
        return (r, g, b, a)
    return None

def blend_rgba_over_bg(fg_rgba, bg_rgb):
    r, g, b, a = fg_rgba
    br, bg_, bb = bg_rgb
    out_r = (1 - a) * br + a * r
    out_g = (1 - a) * bg_ + a * g
    out_b = (1 - a) * bb + a * b
    return (out_r, out_g, out_b)

def srgb_to_lin(c):
    c = c / 255.0
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4

def relative_luminance(rgb):
    r, g, b = rgb
    return 0.2126 * srgb_to_lin(r) + 0.7152 * srgb_to_lin(g) + 0.0722 * srgb_to_lin(b)

def contrast_ratio(rgb1, rgb2):
    l1 = relative_luminance(rgb1)
    l2 = relative_luminance(rgb2)
    lighter = max(l1, l2)
    darker = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)

def parse_globals_css(globals_path):
    with open(globals_path, 'r', encoding='utf-8') as f:
        content = f.read()

    light_vars = {}
    dark_vars = {}

    root_match = re.search(r':root\s*\{(.*?)\}\s*:root\[data-theme="light"\]', content, re.DOTALL)
    if root_match:
        for line in root_match.group(1).splitlines():
            line = line.strip()
            m = re.match(r'--([a-zA-Z0-9_\-]+)\s*:\s*([^;]+);', line)
            if m:
                light_vars[m.group(1)] = m.group(2).strip()

    dark_match = re.search(r':root\[data-theme="dark"\],\s*:root\.dark\s*\{(.*?)\}\s*@media', content, re.DOTALL)
    if dark_match:
        for line in dark_match.group(1).splitlines():
            line = line.strip()
            m = re.match(r'--([a-zA-Z0-9_\-]+)\s*:\s*([^;]+);', line)
            if m:
                dark_vars[m.group(1)] = m.group(2).strip()

    def resolve_raw(val, vars_map, default_bg):
        resolved = val
        for _ in range(5):
            var_m = re.search(r'var\(--([a-zA-Z0-9_\-]+)\)', resolved)
            if not var_m:
                break
            vname = var_m.group(1)
            resolved = resolved.replace(f"var(--{vname})", vars_map.get(vname, "#ffffff"))

        if resolved.startswith('#'):
            return hex_to_rgb(resolved.split()[0])
        elif resolved.startswith('rgb'):
            rgba = parse_rgba(resolved)
            if rgba:
                if len(rgba) == 4 and rgba[3] < 1.0:
                    return blend_rgba_over_bg(rgba, default_bg)
                return (rgba[0], rgba[1], rgba[2])
        return None

    light_bg = hex_to_rgb(light_vars.get("bg", "#ffffff"))
    dark_bg = hex_to_rgb(dark_vars.get("bg", "#0c1017"))

    light_colors = {
        "white": (255, 255, 255),
        "black": (0, 0, 0),
    }
    dark_colors = {
        "white": (255, 255, 255),
        "black": (0, 0, 0),
    }

    for k, v in light_vars.items():
        rgb = resolve_raw(v, light_vars, light_bg)
        if rgb:
            light_colors[k] = rgb

    for k, v in dark_vars.items():
        rgb = resolve_raw(v, dark_vars, dark_bg)
        if rgb:
            dark_colors[k] = rgb

    light_colors["surface-subtle"] = light_colors.get("surface-muted", (244, 244, 246))
    dark_colors["surface-subtle"] = dark_colors.get("surface-muted", (19, 25, 36))

    return light_colors, dark_colors

def extract_pairs_from_string(s):
    tokens = s.split()
    bgs = []
    texts = []
    for t in tokens:
        if ':' in t:
            continue
        if t.startswith('bg-') and not t.startswith('bg-gradient') and not t.startswith('bg-opacity'):
            bg_name = t[3:]
            bgs.append(bg_name)
        elif t.startswith('text-') and not t.startswith('text-xs') and not t.startswith('text-sm') and not t.startswith('text-base') and not t.startswith('text-lg') and not t.startswith('text-xl') and not t.startswith('text-2xl') and not t.startswith('text-center') and not t.startswith('text-left') and not t.startswith('text-right') and not t.startswith('text-opacity'):
            text_name = t[5:]
            texts.append(text_name)
    pairs = []
    if bgs and texts:
        for b in bgs:
            for tx in texts:
                pairs.append((b, tx))
    return pairs

def find_bg_text_pairs(file_path):
    pairs = []
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find literal strings inside className="..." or className={`...`}
    # Break down template literals by string segments (avoiding ternary crosses)
    class_matches = re.findall(r'className=(?:["\'](.*?)["\']|{`([^`]*)`})', content)
    for m in class_matches:
        if m[0]:
            pairs.extend(extract_pairs_from_string(m[0]))
        elif m[1]:
            # Split template literal by expressions ${...}
            raw_tmpl = m[1]
            # Also extract quoted strings inside expressions
            expr_strings = re.findall(r'["\']([^"\']+)["\']', raw_tmpl)
            for es in expr_strings:
                pairs.extend(extract_pairs_from_string(es))
            # And static parts outside ${...}
            static_parts = re.split(r'\$\{[^}]*\}', raw_tmpl)
            for sp in static_parts:
                pairs.extend(extract_pairs_from_string(sp))
    return pairs

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    globals_path = os.path.join(base_dir, "src/app/globals.css")
    light_colors, dark_colors = parse_globals_css(globals_path)

    shared_dirs = [
        "src/components/shared",
        "src/components/ui",
    ]

    all_pairs = defaultdict(list)

    for d in shared_dirs:
        dir_path = os.path.join(base_dir, d)
        if not os.path.isdir(dir_path):
            continue
        for root, _, files in os.walk(dir_path):
            for file in files:
                if file.endswith(('.tsx', '.jsx', '.ts', '.js')):
                    full_p = os.path.join(root, file)
                    rel_p = os.path.relpath(full_p, base_dir)
                    found = find_bg_text_pairs(full_p)
                    for bg, tx in found:
                        all_pairs[(bg, tx)].append(rel_p)

    print(f"{'BG Class':<24} | {'Text Class':<24} | {'Light Ratio':<12} | {'Dark Ratio':<12} | {'WCAG AA (4.5:1)':<16} | Usages")
    print("-" * 105)

    evaluated = 0
    passed = 0

    sorted_pairs = sorted(all_pairs.items(), key=lambda x: len(x[1]), reverse=True)

    for (bg, tx), files in sorted_pairs:
        l_bg = light_colors.get(bg)
        l_tx = light_colors.get(tx)
        d_bg = dark_colors.get(bg)
        d_tx = dark_colors.get(tx)

        if l_bg and l_tx and d_bg and d_tx:
            l_ratio = contrast_ratio(l_bg, l_tx)
            d_ratio = contrast_ratio(d_bg, d_tx)
            evaluated += 1

            l_pass = l_ratio >= 4.5
            d_pass = d_ratio >= 4.5
            status = "PASS BOTH" if (l_pass and d_pass) else ("PASS L ONLY" if l_pass else ("PASS D ONLY" if d_pass else "FAIL BOTH"))
            if l_pass and d_pass:
                passed += 1

            unique_files = sorted(list(set([os.path.basename(f) for f in files])))
            print(f"bg-{bg:<21} | text-{tx:<19} | {l_ratio:6.2f}:1 ({'P' if l_pass else 'F'}) | {d_ratio:6.2f}:1 ({'P' if d_pass else 'F'}) | {status:<16} | {len(files)} files ({', '.join(unique_files)})")

    print("-" * 105)
    print(f"Total evaluated pairs in shared components: {evaluated} | Both themes pass >= 4.5:1: {passed}")

if __name__ == "__main__":
    main()
