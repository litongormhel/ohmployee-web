#!/usr/bin/env node
/**
 * OHMployee Ecosystem — Read-Only Production vs Staging Migration Checker
 * File: scripts/check-migrations.mjs
 *
 * Compares migration metadata between Staging (qqiiznmqxfoamqytjica)
 * and Production (rwxelulyapjgaarlwkus) via read-only Supabase Management API.
 */

import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, "..");
const MIGRATIONS_DIR = path.join(ROOT, "supabase", "migrations");

const STAGING_REF = "qqiiznmqxfoamqytjica";
const PROD_REF = "rwxelulyapjgaarlwkus";

async function getAccessToken() {
  if (process.env.SUPABASE_ACCESS_TOKEN) {
    return process.env.SUPABASE_ACCESS_TOKEN;
  }
  // 1. macOS Keychain
  if (process.platform === "darwin") {
    try {
      const raw = execSync('security find-generic-password -s "Supabase CLI" -w 2>/dev/null', {
        encoding: "utf8",
      }).trim();
      if (raw.startsWith("go-keyring-base64:")) {
        return Buffer.from(raw.replace("go-keyring-base64:", ""), "base64").toString("utf8");
      }
      if (raw) return raw;
    } catch {}
  }

  // 2. Windows Credential Manager
  if (process.platform === "win32") {
    try {
      const psScriptPath = path.join(ROOT, "scripts", "get-token.ps1");
      const winRaw = execSync(`powershell -NoProfile -ExecutionPolicy Bypass -File "${psScriptPath}"`, {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }).trim();
      if (winRaw) return winRaw;
    } catch {}
  }

  return null;
}

async function queryRemoteVersions(projectRef, token) {
  const url = `https://api.supabase.com/v1/projects/${projectRef}/database/query`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query: "SELECT version FROM supabase_migrations.schema_migrations ORDER BY version;",
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Failed to query migrations for ${projectRef} (${res.status}): ${errText}`);
  }

  const rows = await res.json();
  return new Set(rows.map((r) => String(r.version)));
}

async function main() {
  console.log("======================================================");
  console.log("  OHMployee — Migration Status: Staging vs Production");
  console.log("======================================================\n");

  const token = await getAccessToken();
  if (!token) {
    console.error("❌ Unable to retrieve Supabase CLI access token from environment or Keychain.");
    process.exit(1);
  }

  try {
    const [stagingSet, prodSet] = await Promise.all([
      queryRemoteVersions(STAGING_REF, token),
      queryRemoteVersions(PROD_REF, token),
    ]);

    const localFiles = fs
      .readdirSync(MIGRATIONS_DIR)
      .filter((f) => f.endsWith(".sql"))
      .sort();

    const notOnProd = [];
    for (const s of stagingSet) {
      if (!prodSet.has(s)) {
        const match = localFiles.find((f) => f.startsWith(s));
        notOnProd.push(match || s);
      }
    }

    console.log(`prod: ${prodSet.size} migrations`);
    console.log(`staging: ${stagingSet.size} migrations\n`);

    if (notOnProd.length === 0) {
      console.log("✔ Production is fully up to date with Staging (0 pending migrations).");
    } else {
      console.log(`${notOnProd.length} migrations are not on prod:`);
      for (const file of notOnProd) {
        console.log(`- ${file}`);
      }
    }
    console.log("\n======================================================");
  } catch (err) {
    console.error("❌ Error querying migration metadata:", err.message);
    process.exit(1);
  }
}

main();
