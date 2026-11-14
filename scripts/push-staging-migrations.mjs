#!/usr/bin/env node
/**
 * OHMployee Ecosystem — Staging Database Migration Auto-Push Runner
 * File: scripts/push-staging-migrations.mjs
 *
 * Safely synchronizes and pushes pending SQL migrations to the Supabase
 * STAGING database (`qqiiznmqxfoamqytjica`).
 *
 * Mandatory Safety Gates:
 *   1. Hard Production Lock: Strictly forbids execution against Production
 *      (`rwxelulyapjgaarlwkus`). Verifies both `.env` and `supabase/.temp/project-ref`
 *      resolve to Staging (`qqiiznmqxfoamqytjica`).
 *   2. Migration Sync (`scripts/sync-migrations.mjs`): Syncs unique-version
 *      migrations from the sibling Mobile repo before pushing.
 *   3. Unique Version Prefix Gate: Verifies that no two `.sql` files in
 *      `supabase/migrations/` share the same numeric version prefix (`<version>_*.sql`),
 *      preventing `supabase_migrations.schema_migrations` primary key collisions.
 *   4. SQL Contract Gate (`scripts/check-sql-contracts.mjs`): Enforces schema
 *      and cross-module RPC invariants across all migrations before touching Staging.
 *   5. Supabase CLI Push: Executes `npx supabase db push --linked` (or `--dry-run`).
 */

import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, "..");
const MIGRATIONS_DIR = path.join(ROOT, "supabase", "migrations");
const PROJECT_REF_FILE = path.join(ROOT, "supabase", ".temp", "project-ref");
const ENV_FILE = path.join(ROOT, ".env");

const STAGING_REF = "qqiiznmqxfoamqytjica";
const PROD_REF = "rwxelulyapjgaarlwkus";

const isDryRun = process.argv.includes("--dry-run");

function assertStagingEnvironment() {
  // 1. Check .env
  if (fs.existsSync(ENV_FILE)) {
    const envContent = fs.readFileSync(ENV_FILE, "utf8");
    if (envContent.includes(PROD_REF)) {
      console.error(
        `[db:push:staging] ❌ HARD BLOCK: .env points to PRODUCTION (${PROD_REF}). Aborting immediately.`
      );
      process.exit(1);
    }
  }

  // 2. Check supabase/.temp/project-ref
  let linkedRef = "";
  if (fs.existsSync(PROJECT_REF_FILE)) {
    linkedRef = fs.readFileSync(PROJECT_REF_FILE, "utf8").trim();
  }

  if (linkedRef === PROD_REF) {
    console.error(
      `[db:push:staging] ❌ HARD BLOCK: supabase/.temp/project-ref points to PRODUCTION (${PROD_REF}). Aborting immediately.`
    );
    process.exit(1);
  }

  if (linkedRef !== STAGING_REF) {
    console.log(
      `[db:push:staging] Linking workspace to Staging (${STAGING_REF})...`
    );
    execSync(`npx supabase link --project-ref ${STAGING_REF}`, {
      cwd: ROOT,
      stdio: "inherit",
    });
  }

  const verifiedRef = fs.existsSync(PROJECT_REF_FILE)
    ? fs.readFileSync(PROJECT_REF_FILE, "utf8").trim()
    : "";

  if (verifiedRef !== STAGING_REF) {
    console.error(
      `[db:push:staging] ❌ Failed to verify Staging project ref (expected ${STAGING_REF}, got '${verifiedRef}'). Aborting.`
    );
    process.exit(1);
  }

  console.log(
    `[db:push:staging] ✔ Environment verified: STAGING (${STAGING_REF})`
  );
}

function assertUniqueVersionPrefixes() {
  const files = fs
    .readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith(".sql"))
    .sort();

  const byPrefix = new Map();
  for (const file of files) {
    const prefix = file.split("_")[0];
    if (!byPrefix.has(prefix)) byPrefix.set(prefix, []);
    byPrefix.get(prefix).push(file);
  }

  const duplicates = [];
  for (const [prefix, list] of byPrefix.entries()) {
    if (list.length > 1) {
      duplicates.push({ prefix, list });
    }
  }

  if (duplicates.length > 0) {
    console.error(
      "[db:push:staging] ❌ Duplicate migration version prefix(es) detected in supabase/migrations/:"
    );
    for (const d of duplicates) {
      console.error(`  - ${d.prefix}: ${d.list.join(", ")}`);
    }
    console.error(
      "Rename the newer migration file to the next sequential version prefix before pushing."
    );
    process.exit(1);
  }

  console.log(
    `[db:push:staging] ✔ Version prefix uniqueness verified (${files.length} migration files).`
  );
}

function main() {
  console.log("======================================================");
  console.log(
    `  OHMployee Web — Staging Migration Push (${isDryRun ? "DRY RUN" : "LIVE"})`
  );
  console.log("======================================================");

  // Gate 1: Hard Production Lock & Staging Verification
  assertStagingEnvironment();

  // Gate 2: Sync missing unique-version migrations from Mobile repo
  execSync("node scripts/sync-migrations.mjs", {
    cwd: ROOT,
    stdio: "inherit",
  });

  // Gate 3: Ensure no duplicate version prefixes exist locally
  assertUniqueVersionPrefixes();

  // Gate 4: Run SQL Contract Gate
  execSync("node scripts/check-sql-contracts.mjs", {
    cwd: ROOT,
    stdio: "inherit",
  });

  // Gate 5A: Mandatory Pre-Push Dry-Run Validation
  console.log(
    "[db:push:staging] Gate 5A: Running pre-push dry-run validation..."
  );
  const dryRunOut = execSync("npx supabase db push --dry-run --linked", {
    cwd: ROOT,
    encoding: "utf8",
  });
  process.stdout.write(dryRunOut);

  if (!isDryRun) {
    // Parse dry-run JSON line if present to skip live push when already up to date
    const jsonLine = dryRunOut
      .split("\n")
      .find((l) => l.trim().startsWith("{") && l.includes('"upToDate"'));
    let alreadyUpToDate = false;
    if (jsonLine) {
      try {
        const parsed = JSON.parse(jsonLine.trim());
        alreadyUpToDate = parsed.upToDate === true;
      } catch {
        // Proceed with live push if JSON parsing fails
      }
    }

    if (alreadyUpToDate) {
      console.log(
        "[db:push:staging] ✔ Remote Staging database is already up to date (0 pending migrations)."
      );
    } else {
      console.log(
        "[db:push:staging] Gate 5B: Pre-push dry-run clean. Applying migrations to Staging..."
      );
      execSync("npx supabase db push --linked --yes", {
        cwd: ROOT,
        stdio: "inherit",
      });
    }
  }

  console.log("======================================================");
  console.log(
    `  [db:push:staging] ✔ Completed (${isDryRun ? "DRY RUN" : "STAGING UPDATED"})`
  );
  console.log("======================================================");
}

main();
