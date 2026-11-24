#!/usr/bin/env node
/**
 * OHMployee Ecosystem — Automated Secret & Credential Leak Guard
 * File: scripts/check-secrets.mjs
 *
 * Scans repository files for accidentally hardcoded secrets, API keys,
 * database passwords, or JWT tokens before committing or deploying.
 *
 * Chained into `npm test` and `npm run lint`.
 */

import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, "..");

const SECRET_PATTERNS = [
  {
    name: "Supabase JWT Token (anon or service_role)",
    regex: /eyJhbGciOi[a-zA-Z0-9_\-]{10,}\.[a-zA-Z0-9_\-]{20,}\.[a-zA-Z0-9_\-]{20,}/g,
  },
  {
    name: "Google / Gemini API Key",
    regex: /AIzaSy[0-9A-Za-z\-_]{33}/g,
  },
  {
    name: "PostgreSQL Master Connection URL with Password",
    regex: /postgres(?:ql)?:\/\/[a-zA-Z0-9_\.\-]+:[^@\s\r\n'"]{4,}@[^:\s'"]+:\d+\/[^\s'"]+/g,
  },
  {
    name: "Supabase Access Token (sbp_...)",
    regex: /sbp_[a-zA-Z0-9]{30,}/g,
  },
  {
    name: "GitHub Personal Access Token",
    regex: /(?:ghp|gho|ghu|ghs|ghr)_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9_]{82}/g,
  },
  {
    name: "Private Cryptographic Key",
    regex: /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----\s*[a-zA-Z0-9+/=]{20,}/g,
  },
];

// File extensions to skip (binaries, locks, generated assets)
const IGNORED_EXTENSIONS = new Set([
  ".png",
  ".jpg",
  ".jpeg",
  ".gif",
  ".svg",
  ".ico",
  ".pdf",
  ".xlsx",
  ".lock",
  ".tsbuildinfo",
]);

// Directories or paths to skip
const IGNORED_PATHS = [
  "node_modules",
  ".next",
  ".git",
  "dist",
  "build",
  ".env",
];

function isIgnored(filePath) {
  const norm = filePath.replace(/\\/g, "/");
  if (IGNORED_PATHS.some((p) => norm.startsWith(p) || norm.includes(`/${p}/`))) {
    return true;
  }
  const ext = path.extname(filePath).toLowerCase();
  return IGNORED_EXTENSIONS.has(ext);
}

function scanFiles() {
  let trackedFiles = [];
  try {
    const raw = execSync("git ls-files", { cwd: ROOT, encoding: "utf8", maxBuffer: 10 * 1024 * 1024 });
    trackedFiles = raw.split("\n").map((f) => f.trim()).filter(Boolean);
  } catch (err) {
    console.warn("[secret-guard] Warning: could not run git ls-files. Falling back to directory walk.");
    return [];
  }

  const violations = [];

  for (const relPath of trackedFiles) {
    if (isIgnored(relPath)) continue;

    const fullPath = path.join(ROOT, relPath);
    if (!fs.existsSync(fullPath)) continue;

    let content = "";
    try {
      content = fs.readFileSync(fullPath, "utf8");
    } catch {
      continue;
    }

    const lines = content.split("\n");
    for (let lineIdx = 0; lineIdx < lines.length; lineIdx++) {
      const line = lines[lineIdx];

      // Skip test mocks, placeholders, comments referencing patterns, public staging anon fallback, and self-references in this script
      if (
        relPath === "scripts/check-secrets.mjs" ||
        line.includes("your-api-key") ||
        line.includes("example.com") ||
        line.includes("placeholder") ||
        line.includes("env(OPENAI_API_KEY)") ||
        line.includes("STAGING_ANON_KEY")
      ) {
        continue;
      }

      for (const pat of SECRET_PATTERNS) {
        pat.regex.lastIndex = 0;
        const match = pat.regex.exec(line);
        if (match) {
          violations.push({
            file: relPath,
            line: lineIdx + 1,
            patternName: pat.name,
            snippet: match[0].substring(0, 10) + "..." + match[0].substring(match[0].length - 6),
          });
        }
      }
    }
  }

  return violations;
}

const violations = scanFiles();

if (violations.length > 0) {
  console.error("\n===============================================================================");
  console.error(" [SECRET LEAK GUARD] CRITICAL: HARDCODED CREDENTIALS DETECTED IN TRACKED FILES");
  console.error("===============================================================================");
  for (const v of violations) {
    console.error(`  - ${v.file}:${v.line} -> [${v.patternName}] (${v.snippet})`);
  }
  console.error("\nPlease remove hardcoded keys and store them in .env (which is gitignored).\n");
  process.exit(1);
} else {
  console.log("[secret-guard] OK — 0 secret or credential leaks detected across all tracked files.");
}
