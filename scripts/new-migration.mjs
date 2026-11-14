#!/usr/bin/env node
/**
 * OHMployee Ecosystem — Auto-Numbered Migration File Generator
 * File: scripts/new-migration.mjs
 *
 * Usage:
 *   npm run db:new <migration_name>
 *   node scripts/new-migration.mjs <migration_name>
 *
 * Scans both the Web repository (`supabase/migrations/`) and the sibling
 * Mobile repository (`D:\Projects\OHMployee\supabase\migrations`) to determine
 * the highest numeric migration version prefix, increments it by +1, and creates
 * a guaranteed collision-free `.sql` migration file.
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, "..");
const WEB_MIGRATIONS_DIR = path.join(ROOT, "supabase", "migrations");

function resolveMobileMigrationsDir() {
  const candidates = [
    process.env.OHM_MOBILE_REPO
      ? path.join(path.resolve(process.env.OHM_MOBILE_REPO), "supabase", "migrations")
      : null,
    path.resolve(ROOT, "..", "OHMployee", "supabase", "migrations"),
    path.resolve(ROOT, "..", "ohmployee", "supabase", "migrations"),
  ].filter(Boolean);

  for (const dir of candidates) {
    if (fs.existsSync(dir)) return dir;
  }
  return null;
}

function collectAllVersionPrefixes() {
  const dirs = [WEB_MIGRATIONS_DIR, resolveMobileMigrationsDir()].filter(Boolean);
  const prefixes = new Set();

  for (const dir of dirs) {
    if (!fs.existsSync(dir)) continue;
    for (const file of fs.readdirSync(dir)) {
      if (!file.endsWith(".sql")) continue;
      const prefix = file.split("_")[0];
      if (/^\d{14}$/.test(prefix)) {
        prefixes.add(prefix);
      }
    }
  }
  return Array.from(prefixes).sort();
}

function sanitizeSlug(rawInput) {
  return rawInput
    .trim()
    .toLowerCase()
    .replace(/\.sql$/i, "")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function main() {
  const rawName = process.argv.slice(2).join("_");
  const slug = sanitizeSlug(rawName);

  if (!slug) {
    console.error("Usage: npm run db:new <migration_name>");
    console.error("Example: npm run db:new fix_vacancy_status_filter");
    process.exit(1);
  }

  if (!fs.existsSync(WEB_MIGRATIONS_DIR)) {
    fs.mkdirSync(WEB_MIGRATIONS_DIR, { recursive: true });
  }

  const prefixes = collectAllVersionPrefixes();
  const highestPrefix =
    prefixes.length > 0 ? prefixes[prefixes.length - 1] : "20262606000100";

  const nextVersion = (BigInt(highestPrefix) + 1n).toString().padStart(14, "0");
  const fileName = `${nextVersion}_${slug}.sql`;
  const fullPath = path.join(WEB_MIGRATIONS_DIR, fileName);

  if (fs.existsSync(fullPath)) {
    console.error(`[db:new] ❌ File already exists: ${fullPath}`);
    process.exit(1);
  }

  const template = `-- Migration: ${fileName}
-- Created: ${new Date().toISOString()}
-- Description: ${slug.replace(/_/g, " ")}

BEGIN;

-- Write surgical SQL changes here

COMMIT;
`;

  fs.writeFileSync(fullPath, template, "utf8");
  console.log(`[db:new] ✔ Created migration: supabase/migrations/${fileName}`);
}

main();
