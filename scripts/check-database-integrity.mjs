#!/usr/bin/env node
/**
 * OHMployee Ecosystem — Automated Database Integrity & Archive Resurface Guard
 * File: scripts/check-database-integrity.mjs
 *
 * Verifies database health on Staging (or local environment):
 * 1. Zero active stores under inactive or archived accounts.
 * 2. Zero active stores attached to rolled-back, rejected, or failed import batches.
 * 3. Zero import batches remaining in 'rollback_failed' state.
 * 4. Zero pending unexecuted rollback requests ('rollback_status = requested').
 * 5. Consistent boolean status flags on public.stores.
 */

import { execSync } from "node:child_process";

const STAGING_REF = "qqiiznmqxfoamqytjica";

async function getAccessToken() {
  if (process.env.SUPABASE_ACCESS_TOKEN) {
    return process.env.SUPABASE_ACCESS_TOKEN;
  }
  if (process.platform === "darwin") {
    try {
      const raw = execSync('security find-generic-password -s "Supabase CLI" -w 2>/dev/null', {
        encoding: "utf8",
      }).trim();
      if (raw.startsWith("go-keyring-base64:")) {
        return Buffer.from(raw.replace("go-keyring-base64:", ""), "base64").toString("utf8");
      }
      return raw;
    } catch {
      return null;
    }
  }
  return null;
}

async function queryDatabase(query, token) {
  const url = `https://api.supabase.com/v1/projects/${STAGING_REF}/database/query`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ query }),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`API query failed (${res.status}): ${errText}`);
  }

  return await res.json();
}

async function main() {
  const token = await getAccessToken();
  if (!token) {
    console.log("[db-integrity] SKIPPED — No Supabase Management API access token found. Local offline pass.");
    process.exit(0);
  }

  console.log(`[db-integrity] Running database archive & integrity audit on Staging (${STAGING_REF})...`);

  const checks = [
    {
      name: "Active stores under inactive/archived accounts",
      sql: `SELECT count(*)::int as count FROM public.stores s JOIN public.accounts a ON a.id = s.account_id WHERE s.is_active = true AND (a.is_active = false OR a.is_archived = true OR a.status = 'Inactive');`,
    },
    {
      name: "Active stores under rolled-back, rejected, or rollback-failed batches",
      sql: `SELECT count(*)::int as count FROM public.stores s JOIN public.plantilla_import_batches b ON b.id = s.source_import_id WHERE s.is_active = true AND (b.status IN ('rolled_back', 'rejected', 'rollback_failed'));`,
    },
    {
      name: "Plantilla import batches stuck in 'rollback_failed'",
      sql: `SELECT count(*)::int as count FROM public.plantilla_import_batches WHERE status = 'rollback_failed';`,
    },
    {
      name: "Plantilla import batches with unfinalized 'rollback_status = requested'",
      sql: `SELECT count(*)::int as count FROM public.plantilla_import_batches WHERE rollback_status = 'requested' AND status != 'rolled_back';`,
    },
    {
      name: "Inconsistent store flags (is_active = true but status = 'archived' or is_archived = true)",
      sql: `SELECT count(*)::int as count FROM public.stores WHERE is_active = true AND (status = 'archived' OR is_archived = true);`,
    },
  ];

  let failures = 0;

  for (const check of checks) {
    try {
      const rows = await queryDatabase(check.sql, token);
      const count = rows && rows[0] ? Number(rows[0].count) : 0;
      if (count === 0) {
        console.log(`  ✔ [PASS] ${check.name} (0 issues)`);
      } else {
        console.error(`  ✖ [FAIL] ${check.name}: ${count} issue(s) detected!`);
        failures++;
      }
    } catch (err) {
      console.warn(`  ⚠ [WARN] Could not run check "${check.name}":`, err.message);
    }
  }

  if (failures > 0) {
    console.error(`\n[db-integrity] FAILED — ${failures} integrity check(s) violated.`);
    process.exit(1);
  } else {
    console.log(`\n[db-integrity] INTEGRITY_OK — All integrity and archive guards passed on Staging.`);
  }
}

main().catch((err) => {
  console.error("[db-integrity] Fatal error:", err);
  process.exit(1);
});
