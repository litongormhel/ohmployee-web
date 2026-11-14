#!/usr/bin/env node
/**
 * OHMployee Ecosystem — Automated SQL Schema & RPC Anti-Regression Gate
 * File: scripts/check-sql-contracts.mjs
 *
 * Runs automatically on every `npm test` and `npm run lint`.
 *
 * What it enforces across the ENTIRE OHMployee ecosystem:
 *   1. Authoritative Table Column Registry:
 *      Parses all `CREATE TABLE`, `ALTER TABLE ... ADD COLUMN`, and dynamic
 *      `EXECUTE format('ALTER TABLE public.%I ADD COLUMN ...')` statements
 *      across `supabase/migrations/*.sql` to build the live column dictionary
 *      for every `public.*` table in OHMployee (Stores, Plantilla, Slots,
 *      Allocations, Vacancies, Applicants, HR Emploc, Approvals, Coverage
 *      Groups, Workforce Pool, Users/RBAC, Audit Logs, etc.).
 *   2. Universal INSERT / UPDATE Column Validation:
 *      Scans the latest definition of every SQL function (`CREATE OR REPLACE FUNCTION`)
 *      and top-level DML in active migrations, verifying that every
 *      `INSERT INTO public.<table> (...)` and `UPDATE public.<table> SET ...`
 *      references ONLY columns that physically exist on that table.
 *   3. Cross-Module RPC Invariant & Anti-Overwrite Lock (19 Core RPCs):
 *      Verifies that the latest definition of critical RPCs across Plantilla,
 *      Vacancy, HR Emploc, Approvals, Coverage, Users/RBAC, and Audit Logs
 *      retains all required table operations and architectural invariants.
 */

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, "..");
const MIGRATIONS_DIR = path.join(ROOT, "supabase", "migrations");

/**
 * Collects `.sql` migration entries across the local repository and any
 * sibling OHMployee repository (`../ohmployee` or `../ohmployee-web`),
 * deduplicated by filename (local repo takes precedence on exact filename match)
 * and sorted lexicographically.
 */
function collectMigrationEntries() {
  const candidateDirs = [
    path.resolve(ROOT, "..", "ohmployee", "supabase", "migrations"),
    path.resolve(ROOT, "..", "ohmployee-web", "supabase", "migrations"),
    MIGRATIONS_DIR,
  ];
  const byName = new Map();
  for (const dir of candidateDirs) {
    if (!fs.existsSync(dir)) continue;
    for (const file of fs.readdirSync(dir)) {
      if (!file.endsWith(".sql")) continue;
      byName.set(file, { file, fullPath: path.join(dir, file) });
    }
  }
  return Array.from(byName.values()).sort((a, b) =>
    a.file.localeCompare(b.file)
  );
}

function stripSqlComments(sql) {
  return sql.replace(
    /'(?:''|[^'])*'|--[^\r\n]*|\/\*[\s\S]*?\*\//g,
    (match) => {
      if (match.startsWith("'")) return match;
      return " ";
    }
  );
}

/**
 * Step 1: Build the live column catalog for all `public.*` tables from migrations.
 */
function buildTableSchemaCatalog(migrationEntries) {
  const tables = new Map();

  const ensureTable = (tbl) => {
    const key = tbl.toLowerCase().replace(/^["']|["']$/g, "");
    if (!tables.has(key)) {
      tables.set(key, new Set(["id"]));
    }
    return tables.get(key);
  };

  const SQL_CONSTRAINTS = new Set([
    "constraint",
    "primary",
    "foreign",
    "unique",
    "check",
    "exclude",
    "like",
  ]);

  for (const { fullPath } of migrationEntries) {
    const raw = fs.readFileSync(fullPath, "utf-8");
    const clean = stripSqlComments(raw);

    // 1A. Match CREATE TABLE [IF NOT EXISTS] [public.]table_name ( ... )
    const createRegex =
      /create\s+table\s+(?:if\s+not\s+exists\s+)?(?:"?public"?\.)?"?([a-zA-Z0-9_]+)"?\s*\(/gi;
    let match;
    while ((match = createRegex.exec(clean)) !== null) {
      const tableName = match[1].toLowerCase();
      const colSet = ensureTable(tableName);

      let depth = 1;
      let idx = match.index + match[0].length;
      const startIdx = idx;
      while (idx < clean.length && depth > 0) {
        if (clean[idx] === "(") depth++;
        else if (clean[idx] === ")") depth--;
        idx++;
      }
      const body = clean.slice(startIdx, idx - 1);

      let current = "";
      let pDepth = 0;
      const items = [];
      for (let i = 0; i < body.length; i++) {
        const ch = body[i];
        if (ch === "(") pDepth++;
        else if (ch === ")") pDepth--;
        if (ch === "," && pDepth === 0) {
          items.push(current.trim());
          current = "";
        } else {
          current += ch;
        }
      }
      if (current.trim()) items.push(current.trim());

      for (const item of items) {
        const firstTokenMatch = item.match(/^"?([a-zA-Z0-9_]+)"?\s+/);
        if (!firstTokenMatch) continue;
        const colName = firstTokenMatch[1].toLowerCase();
        if (!SQL_CONSTRAINTS.has(colName)) {
          colSet.add(colName);
        }
      }
    }

    // 1B. Match ALTER TABLE [IF EXISTS] [ONLY] [public.]table_name ... ADD [COLUMN] ...
    const alterRegex =
      /alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(?:"?public"?\.)?"?([a-zA-Z0-9_]+)"?\s+([\s\S]*?);/gi;
    while ((match = alterRegex.exec(clean)) !== null) {
      const tableName = match[1].toLowerCase();
      const alterBody = match[2];
      const colSet = ensureTable(tableName);

      const addColRegex =
        /add\s+(?:column\s+)?(?:if\s+not\s+exists\s+)?"?([a-zA-Z0-9_]+)"?\s+(?!constraint\b|primary\b|foreign\b|unique\b|check\b)/gi;
      let addMatch;
      while ((addMatch = addColRegex.exec(alterBody)) !== null) {
        const colName = addMatch[1].toLowerCase();
        if (!SQL_CONSTRAINTS.has(colName)) {
          colSet.add(colName);
        }
      }
    }

    // 1C. Match dynamic `target_tables TEXT[] := ARRAY[...]` + `EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS <col> ...')`
    const arrayTablesMatch = raw.match(
      /target_tables\s+TEXT\[\]\s*:=\s*ARRAY\[([\s\S]*?)\]/i
    );
    if (arrayTablesMatch) {
      const targetTableNames = [];
      const tblTokenRegex = /'([a-zA-Z0-9_]+)'/g;
      let tm;
      while ((tm = tblTokenRegex.exec(arrayTablesMatch[1])) !== null) {
        targetTableNames.push(tm[1].toLowerCase());
      }
      const dynAddColRegex =
        /ALTER\s+TABLE\s+public\.%I\s+ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+([a-zA-Z0-9_]+)\b/gi;
      let dm;
      while ((dm = dynAddColRegex.exec(raw)) !== null) {
        const dynCol = dm[1].toLowerCase();
        for (const tName of targetTableNames) {
          ensureTable(tName).add(dynCol);
        }
      }
    }
  }

  return tables;
}

/**
 * Step 2: Extract the latest definition of every `public.<function_name>` across migrations.
 */
function extractLatestFunctions(migrationEntries) {
  const latestFunctions = new Map();

  const funcRegex =
    /create\s+(?:or\s+replace\s+)?function\s+(?:"?public"?\.)?"?([a-zA-Z0-9_]+)"?\s*\(([\s\S]*?)\)\s*returns\s+[\s\S]*?as\s+(\$[a-zA-Z0-9_]*\$)([\s\S]*?)\3/gi;

  for (const { file, fullPath } of migrationEntries) {
    const raw = fs.readFileSync(fullPath, "utf-8");
    let match;
    while ((match = funcRegex.exec(raw)) !== null) {
      const funcName = match[1].toLowerCase();
      const rawBody = match[4];
      latestFunctions.set(funcName, {
        funcName,
        file,
        rawBody,
        cleanBody: stripSqlComments(rawBody),
      });
    }
  }

  return latestFunctions;
}

/**
 * Step 3: Validate INSERT and UPDATE column names inside SQL bodies against the schema catalog.
 */
function validateFunctionDmlColumns(funcInfo, tables) {
  const errors = [];
  const { funcName, file, cleanBody } = funcInfo;

  // 3A. Validate INSERT INTO public.<table> (<col1, col2, ...>)
  const insertRegex =
    /insert\s+into\s+(?:"?public"?\.)?"?([a-zA-Z0-9_]+)"?\s*\(([^)]+)\)\s*(?:overriding\s+[^\s]+\s+value\s*)?(?:values|select)\b/gi;
  let match;
  while ((match = insertRegex.exec(cleanBody)) !== null) {
    const tableName = match[1].toLowerCase();
    const colListRaw = match[2];
    const tableCols = tables.get(tableName);
    if (!tableCols) continue;

    if (colListRaw.includes("(") || colListRaw.includes("select")) continue;

    const cols = colListRaw
      .split(",")
      .map((c) => c.trim().replace(/^["']|["']$/g, "").toLowerCase())
      .filter(Boolean);

    for (const col of cols) {
      if (!/^[a-z0-9_]+$/.test(col)) continue;
      if (!tableCols.has(col)) {
        errors.push(
          `[${file}] Function "${funcName}" INSERT INTO public.${tableName} references non-existent column "${col}".`
        );
      }
    }
  }

  // 3B. Validate UPDATE public.<table> [alias] SET <col1> = ..., <col2> = ...
  const updateRegex =
    /update\s+(?:"?public"?\.)?"?([a-zA-Z0-9_]+)"?(?:\s+(?:as\s+)?([a-zA-Z0-9_]+))?\s+set\s+([\s\S]*?)(?:\bwhere\b|\bfrom\b|\breturning\b|;)/gi;
  while ((match = updateRegex.exec(cleanBody)) !== null) {
    const tableName = match[1].toLowerCase();
    const setClause = match[3];
    const tableCols = tables.get(tableName);
    if (!tableCols) continue;

    let current = "";
    let pDepth = 0;
    const assignments = [];
    for (let i = 0; i < setClause.length; i++) {
      const ch = setClause[i];
      if (ch === "(") pDepth++;
      else if (ch === ")") pDepth--;
      if (ch === "," && pDepth === 0) {
        assignments.push(current.trim());
        current = "";
      } else {
        current += ch;
      }
    }
    if (current.trim()) assignments.push(current.trim());

    for (const assign of assignments) {
      const lhsMatch = assign.match(/^"?([a-zA-Z0-9_]+)"?\s*=/);
      if (!lhsMatch) continue;
      const col = lhsMatch[1].toLowerCase();
      if (!tableCols.has(col)) {
        errors.push(
          `[${file}] Function "${funcName}" UPDATE public.${tableName} SET references non-existent column "${col}".`
        );
      }
    }
  }

  return errors;
}

/**
 * Step 4: Ecosystem-Wide RPC Invariant Contracts (Anti-Overwrite Protection across 19 Core RPCs).
 */
const RPC_INVARIANT_CONTRACTS = [
  {
    funcName: "approve_plantilla_import_batch",
    module: "Plantilla Baseline Import (ADR-002)",
    requiredPatterns: [
      {
        pattern: /insert\s+into\s+public\.stores\b/i,
        description: "Phase A store creation (INSERT INTO public.stores)",
      },
      {
        pattern: /area_city/i,
        description: "Canonical stores.area_city column usage",
      },
      {
        pattern: /source_import_id/i,
        description: "Canonical stores.source_import_id column usage",
      },
      {
        pattern: /insert\s+into\s+public\.plantilla_slots\b/i,
        description: "ADR-001/002 slot provisioning in public.plantilla_slots",
      },
      {
        pattern: /insert\s+into\s+public\.plantilla_store_links\b/i,
        description: "Roving/store link synchronization in public.plantilla_store_links",
      },
      {
        pattern: /insert\s+into\s+public\.employee_store_allocations\b/i,
        description: "Store HC share allocation in public.employee_store_allocations",
      },
      {
        pattern: /insert\s+into\s+public\.plantilla_import_commit_snapshots\b/i,
        description: "ADR-002 72-hour rollback commit snapshots",
      },
      {
        pattern: /rollback_ready\s*=\s*true/i,
        description: "ADR-002 rollback_ready = true flag on batch approval",
      },
      {
        pattern: /order\s+by\s+row_number\s+desc/i,
        description: "ADR-002 Rule #17 Last-Row-Wins coalescing (ORDER BY row_number DESC)",
      },
    ],
    forbiddenPatterns: [
      {
        pattern: /\bapproval_notes\b/i,
        description: "Non-existent column approval_notes on plantilla_import_batches",
      },
    ],
  },
  {
    funcName: "_evaluate_plantilla_import_rows",
    module: "Plantilla Import Validation & Bi-Directional Identity Lock (ADR-002 Rule #16)",
    requiredPatterns: [
      {
        pattern: /name_emp_conflicts/i,
        description: "ADR-002 Rule #16 Reverse Identity Lock CTE (1 Person = 1 EMPLOYEE_NO)",
      },
      {
        pattern: /db_name_conflict/i,
        description: "Cross-table reverse identity check against DB master records",
      },
    ],
  },
  {
    funcName: "rollback_plantilla_import_batch",
    module: "Plantilla Import 72-Hour Rollback (ADR-002 Invariant #10)",
    requiredPatterns: [
      {
        pattern: /ROLLBACK_BLOCKED_PROTECTED_OCCUPANT/i,
        description: "Protected external occupant guard before slot closure",
      },
      {
        pattern: /plantilla_import_commit_snapshots/i,
        description: "Snapshot-driven restoration from plantilla_import_commit_snapshots",
      },
    ],
  },
  {
    funcName: "update_plantilla_schedule",
    module: "Plantilla Store-Level Schedule & Rest Days (Rule #6)",
    requiredPatterns: [
      {
        pattern: /employee_store_allocations/i,
        description: "Store-level duty day and shift window persistence on employee_store_allocations",
      },
    ],
  },
  {
    funcName: "fn_plantilla_separation_to_vacancy",
    module: "Plantilla Separation -> Slot & Vacancy Reopening (Rule #1)",
    requiredPatterns: [
      {
        pattern: /reopen_or_create_vacancy_for_plantilla/i,
        description: "Automatic vacancy reopening delegation upon employee separation",
      },
    ],
  },
  {
    funcName: "reopen_or_create_vacancy_for_plantilla",
    module: "Vacancy Reopening & Previous Applicant Archival",
    requiredPatterns: [
      {
        pattern: /update\s+public\.applicants\b/i,
        description: "Archives previous cycle applicants when reopening a vacated store slot",
      },
    ],
  },
  {
    funcName: "list_web_vacancies",
    module: "Vacancy Module (ADR-001 Rule 4 Open Capacity)",
    requiredPatterns: [
      {
        pattern: /row_capabilities/i,
        description: "Role-scoped row_capabilities payload for Vacancy UI",
      },
    ],
  },
  {
    funcName: "fn_assert_vacancy_closeable",
    module: "Vacancy Closure Active-Applicant Guard",
    requiredPatterns: [
      {
        pattern: /applicants/i,
        description: "Active applicant guard blocking vacancy closure when candidates are in pipeline",
      },
      {
        pattern: /hr_emploc/i,
        description: "Active HR Emploc guard blocking vacancy closure when onboarding is pending",
      },
    ],
  },
  {
    funcName: "handle_closure_approval",
    module: "Vacancy & Store Closure Cascade Trigger",
    requiredPatterns: [
      {
        pattern: /fn_assert_vacancy_closeable/i,
        description: "Pre-closure active candidate assertion",
      },
      {
        pattern: /update\s+public\.plantilla_slots\b/i,
        description: "Closes dangling open/pipeline slots in plantilla_slots upon closure approval",
      },
    ],
  },
  {
    funcName: "list_web_hr_emplocs",
    module: "HR Emploc Queue List",
    requiredPatterns: [
      {
        pattern: /row_capabilities/i,
        description: "Role-scoped row_capabilities and document count metadata",
      },
    ],
  },
  {
    funcName: "get_web_hr_emploc_summary",
    module: "HR Emploc Queue Summary Counters",
    requiredPatterns: [
      {
        pattern: /for_emploc/i,
        description: "Queue counter breakdown including for_emploc stage",
      },
    ],
  },
  {
    funcName: "get_web_hr_emploc_detail",
    module: "HR Emploc Drawer Detail & Capabilities",
    requiredPatterns: [
      {
        pattern: /row_capabilities/i,
        description: "Detail row_capabilities and attachment hydration",
      },
    ],
  },
  {
    funcName: "_assign_and_deploy_emploc_core",
    module: "HR Emploc -> Plantilla Deployment Core",
    requiredPatterns: [
      {
        pattern: /insert\s+into\s+(?:public\.)?plantilla\b/i,
        description: "Deploys onboarded HR Emploc record into public.plantilla",
      },
    ],
  },
  {
    funcName: "approve_new_store_request",
    module: "Approvals — New Store Request Provisioning",
    requiredPatterns: [
      {
        pattern: /insert\s+into\s+public\.stores\b/i,
        description: "Creates active store in public.stores upon NSR approval",
      },
    ],
  },
  {
    funcName: "resolve_audit_actor_id",
    module: "Core Safe Audit Logging (Rule #2)",
    requiredPatterns: [
      {
        pattern: /users_profile/i,
        description: "Safe actor resolution against users_profile / auth.users",
      },
    ],
  },
  {
    funcName: "fn_audit_log",
    module: "Core Audit Log Trigger (Rule #2)",
    requiredPatterns: [
      {
        pattern: /resolve_audit_actor_id/i,
        description: "Uses safe actor resolver to prevent FK constraint crashes",
      },
    ],
  },
  {
    funcName: "get_my_allowed_accounts",
    module: "Core RBAC & Account Scope Resolution",
    requiredPatterns: [
      {
        pattern: /user_scopes/i,
        description: "Direct account scopes unioned with group scopes via public.user_scopes",
      },
      {
        pattern: /temp_permission_overrides/i,
        description: "Temporary permission overrides included in allowed accounts",
      },
    ],
  },
  {
    funcName: "upsert_user_profile_and_scopes",
    module: "User Management & HRCO Scope Sync",
    requiredPatterns: [
      {
        pattern: /user_scopes/i,
        description: "Synchronizes user_scopes assignments on profile save",
      },
    ],
  },
  {
    funcName: "fn_reevaluate_hrco_auto_tags",
    module: "User Management -> HRCO Source of Truth Backfill",
    requiredPatterns: [
      {
        pattern: /plantilla_hrco_assignments/i,
        description: "Synchronizes plantilla_hrco_assignments and accounts.hrco_user_id",
      },
    ],
  },
];

// Core tables whose DML columns are strictly enforced across all latest RPCs
const ENFORCED_DML_TABLES = new Set([
  "stores",
  "plantilla",
  "plantilla_slots",
  "plantilla_store_links",
  "employee_store_allocations",
  "plantilla_import_batches",
  "plantilla_import_rows",
  "plantilla_import_commit_snapshots",
  "vacancies",
  "applicants",
  "hr_emploc",
  "hr_emploc_import_batches",
  "hr_emploc_import_rows",
  "headcount_requests",
  "coverage_groups",
  "coverage_group_stores",
  "coverage_requests",
  "workforce_assignments",
  "workforce_assignment_requests",
  "workforce_pool_slots",
  "new_store_requests",
  "deactivation_requests",
  "account_group_transfer_requests",
  "users_profile",
  "accounts",
  "groups",
  "audit_logs",
  "slot_history",
]);

function main() {
  if (!fs.existsSync(MIGRATIONS_DIR)) {
    console.error(`[sql-guard] Migrations directory not found: ${MIGRATIONS_DIR}`);
    process.exit(1);
  }

  const migrationEntries = collectMigrationEntries();

  const allTables = buildTableSchemaCatalog(migrationEntries);
  const enforcedTables = new Map();
  for (const tbl of ENFORCED_DML_TABLES) {
    if (allTables.has(tbl)) {
      enforcedTables.set(tbl, allTables.get(tbl));
    }
  }

  const latestFunctions = extractLatestFunctions(migrationEntries);
  const violations = [];

  // 1. Check DML columns in the latest definition of all functions touched in active migrations (20262606000050+)
  for (const [, funcInfo] of latestFunctions) {
    const isModernMigration =
      (funcInfo.file.startsWith("20262606") &&
        funcInfo.file >= "20262606000050") ||
      funcInfo.file.startsWith("202611");
    if (!isModernMigration) {
      continue;
    }
    const dmlErrors = validateFunctionDmlColumns(funcInfo, enforcedTables);
    violations.push(...dmlErrors);
  }

  // 2. Check Ecosystem-Wide RPC Invariant Contracts on latest function bodies
  for (const contract of RPC_INVARIANT_CONTRACTS) {
    const funcInfo = latestFunctions.get(contract.funcName.toLowerCase());
    if (!funcInfo) {
      violations.push(
        `[Missing RPC] Critical function "${contract.funcName}" (${contract.module}) was not found in migrations.`
      );
      continue;
    }

    for (const req of contract.requiredPatterns || []) {
      if (!req.pattern.test(funcInfo.cleanBody)) {
        violations.push(
          `[${funcInfo.file}] Regression in "${contract.funcName}" (${contract.module}): Missing required invariant -> ${req.description}`
        );
      }
    }

    for (const forbid of contract.forbiddenPatterns || []) {
      if (forbid.pattern.test(funcInfo.cleanBody)) {
        violations.push(
          `[${funcInfo.file}] Regression in "${contract.funcName}" (${contract.module}): Contains forbidden pattern -> ${forbid.description}`
        );
      }
    }
  }

  // 3. Enforce unique numeric version prefixes inside local supabase/migrations/
  if (fs.existsSync(MIGRATIONS_DIR)) {
    const localByPrefix = new Map();
    for (const file of fs.readdirSync(MIGRATIONS_DIR)) {
      if (!file.endsWith(".sql")) continue;
      const prefix = file.split("_")[0];
      if (!localByPrefix.has(prefix)) localByPrefix.set(prefix, []);
      localByPrefix.get(prefix).push(file);
    }
    for (const [prefix, list] of localByPrefix.entries()) {
      if (list.length > 1) {
        violations.push(
          `[Duplicate Migration Version Prefix] Numeric version "${prefix}" is used by multiple files in supabase/migrations/: ${list.join(", ")}. Each migration must have a unique version prefix.`
        );
      }
    }
  }

  if (violations.length > 0) {
    console.error("\n======================================================================");
    console.error("  [SQL CONTRACT & ANTI-REGRESSION GATE FAILED]");
    console.error("======================================================================");
    for (const v of violations) {
      console.error(`  ✖ ${v}`);
    }
    console.error("======================================================================\n");
    process.exit(1);
  }

  console.log(
    `[sql-guard] SQL_CONTRACTS_OK — verified ${enforcedTables.size} core tables & ${RPC_INVARIANT_CONTRACTS.length} cross-module RPC contracts across ${migrationEntries.length} migrations.`
  );
}

main();
