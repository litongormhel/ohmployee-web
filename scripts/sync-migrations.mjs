#!/usr/bin/env node
/**
 * OHMployee Ecosystem — Migration Directory Synchronizer
 * File: scripts/sync-migrations.mjs
 *
 * Ensures `supabase/migrations/` in the Web repository contains all `.sql`
 * migration versions from the sibling Mobile repository (`D:\Projects\OHMployee`
 * or `OHM_MOBILE_REPO`) whose numeric version prefix is not already present in Web.
 *
 * Safety invariants:
 * - strictly copy-only (never deletes or overwrites existing files in Web)
 * - prevents duplicate numeric version prefix collisions in `supabase_migrations.schema_migrations`
 * - strictly read-only against the Mobile repository
 * - skips cleanly in CI/Vercel if the sibling Mobile repository is absent
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, "..");
const WEB_MIGRATIONS_DIR = path.join(ROOT, "supabase", "migrations");

const mode = process.argv[2] || "sync"; // "sync" | "check"

function getVersionPrefix(filename) {
  return filename.split("_")[0];
}

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

function main() {
  if (!fs.existsSync(WEB_MIGRATIONS_DIR)) {
    fs.mkdirSync(WEB_MIGRATIONS_DIR, { recursive: true });
  }

  const mobileMigrationsDir = resolveMobileMigrationsDir();
  if (!mobileMigrationsDir) {
    console.log(
      "[migrations-sync] Sibling Mobile repo not found (CI/standalone mode). Using local supabase/migrations/."
    );
    process.exit(0);
  }

  const webFiles = fs.readdirSync(WEB_MIGRATIONS_DIR).filter((f) => f.endsWith(".sql"));
  const webFileSet = new Set(webFiles);
  const webVersionSet = new Set(webFiles.map(getVersionPrefix));

  const mobileFiles = fs
    .readdirSync(mobileMigrationsDir)
    .filter((f) => f.endsWith(".sql"))
    .sort();

  const missingInWeb = [];
  const skippedPrefixCollisions = [];

  for (const file of mobileFiles) {
    if (webFileSet.has(file)) continue;
    const ver = getVersionPrefix(file);
    if (webVersionSet.has(ver)) {
      skippedPrefixCollisions.push(file);
      continue;
    }
    missingInWeb.push(file);
  }

  if (mode === "check") {
    if (missingInWeb.length === 0) {
      console.log(
        `[migrations-sync] MIGRATIONS_SYNC_STATUS: FRESH (${webFiles.length} migrations in Web repo, ${skippedPrefixCollisions.length} historical prefix collisions safely isolated)`
      );
    } else {
      console.warn(
        `[migrations-sync] MIGRATIONS_SYNC_STATUS: MISSING_${missingInWeb.length} — run 'npm run sync:migrations'`
      );
    }
    process.exit(0);
  }

  let copiedCount = 0;
  for (const file of missingInWeb) {
    const src = path.join(mobileMigrationsDir, file);
    const dest = path.join(WEB_MIGRATIONS_DIR, file);
    const ver = getVersionPrefix(file);
    if (!fs.existsSync(dest) && !webVersionSet.has(ver)) {
      fs.copyFileSync(src, dest, fs.constants.COPYFILE_EXCL);
      webVersionSet.add(ver);
      copiedCount++;
    }
  }

  const finalWebCount = fs
    .readdirSync(WEB_MIGRATIONS_DIR)
    .filter((f) => f.endsWith(".sql")).length;

  console.log(
    `[migrations-sync] Synced ${copiedCount} unique-version migration(s) from Mobile repo (${skippedPrefixCollisions.length} historical prefix collision(s) safely isolated). Total Web migrations: ${finalWebCount}.`
  );
}

main();
