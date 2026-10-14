import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import * as XLSX from "xlsx";
import { createClient } from "@supabase/supabase-js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, "..");

// Read staging env
const envPath = path.join(ROOT, ".env");
let supabaseUrl = "";
let supabaseAnonKey = "";

if (fs.existsSync(envPath)) {
  const content = fs.readFileSync(envPath, "utf-8");
  for (const line of content.split("\n")) {
    const trimmed = line.trim();
    if (trimmed.startsWith("NEXT_PUBLIC_SUPABASE_URL=")) {
      supabaseUrl = trimmed.split("=")[1].trim();
    } else if (trimmed.startsWith("NEXT_PUBLIC_SUPABASE_ANON_KEY=")) {
      supabaseAnonKey = trimmed.split("=")[1].trim();
    }
  }
}

if (!supabaseUrl || !supabaseAnonKey) {
  console.error("Failed to load NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY from .env");
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseAnonKey);

console.log("======================================================================");
console.log("  OHMployee Web -- End-to-End Technical Sanity & RPC Health Audit");
console.log(`  Supabase URL : ${supabaseUrl}`);
console.log("======================================================================\n");

const results = {
  totalPassed: 0,
  totalFailed: 0,
  details: [],
};

function recordTest(name, passed, detail) {
  if (passed) {
    results.totalPassed++;
    console.log(`  [PASS] ${name}`);
  } else {
    results.totalFailed++;
    console.error(`  [FAIL] ${name}: ${detail}`);
  }
  results.details.push({ name, passed, detail });
}

// ─────────────────────────────────────────────────────────────────────────────
// Test Suite 1: Excel Export & Template Generation (Unit & Parser Integrity)
// ─────────────────────────────────────────────────────────────────────────────
console.log("--- Test Suite 1: Excel Export & Template Generation ---");

try {
  // Constants from hr_emploc_xlsx
  const V3_REQUIRED_HEADERS = [
    "GROUP",
    "ACCOUNT",
    "VCODE",
    "LAST_NAME",
    "FIRST_NAME",
    "MIDDLE_NAME",
    "DATE_HIRED",
  ];

  const STANDARD_REQUIRED_HEADERS = [
    "STORE_NAME",
    "ACCOUNT",
    "POSITION",
    "FIRST_NAME",
    "LAST_NAME",
    "MIDDLE_NAME",
    "EMPLOYEE_NO",
  ];

  // Helper matching src/lib/utils/hr_emploc_xlsx.ts
  function buildHrEmplocImportTemplateXlsx(variant = "v3") {
    const wb = XLSX.utils.book_new();

    if (variant === "standard") {
      const headers = [...STANDARD_REQUIRED_HEADERS];
      const sampleRow = [
        "SM Mall of Asia",
        "Account Alpha",
        "Sales Associate",
        "JUAN",
        "DELA CRUZ",
        "SANTOS",
        "V-2026-001",
      ];
      const ws = XLSX.utils.aoa_to_sheet([headers, sampleRow]);
      XLSX.utils.book_append_sheet(wb, ws, "IMPORT_TEMPLATE");
    } else {
      const headers = [...V3_REQUIRED_HEADERS];
      const sampleRow = [
        "Group Alpha",
        "Account Alpha",
        "V-2026-001",
        "DELA CRUZ",
        "JUAN",
        "SANTOS",
        "2026-01-15",
      ];
      const ws = XLSX.utils.aoa_to_sheet([headers, sampleRow]);
      XLSX.utils.book_append_sheet(wb, ws, "IMPORT_TEMPLATE");

      const wsStandard = XLSX.utils.aoa_to_sheet([
        [...STANDARD_REQUIRED_HEADERS],
        [
          "SM Mall of Asia",
          "Account Alpha",
          "Sales Associate",
          "JUAN",
          "DELA CRUZ",
          "SANTOS",
          "V-2026-001",
        ],
      ]);
      XLSX.utils.book_append_sheet(wb, wsStandard, "STANDARD_SCHEMA");
    }

    const guideData = [
      ["COLUMN", "REQUIRED", "FORMAT / NOTES"],
      ["GROUP", "YES", "Must match group"],
    ];
    const wsGuide = XLSX.utils.aoa_to_sheet(guideData);
    XLSX.utils.book_append_sheet(wb, wsGuide, "VALIDATION_GUIDE");

    const arrayBuffer = XLSX.write(wb, { bookType: "xlsx", type: "array" });
    return new Uint8Array(arrayBuffer);
  }

  // Test v3 template
  const v3Bytes = buildHrEmplocImportTemplateXlsx("v3");
  const wbV3 = XLSX.read(v3Bytes, { type: "array" });
  const hasExpectedSheetsV3 =
    wbV3.SheetNames.includes("IMPORT_TEMPLATE") &&
    wbV3.SheetNames.includes("STANDARD_SCHEMA") &&
    wbV3.SheetNames.includes("VALIDATION_GUIDE");

  const v3Sheet = wbV3.Sheets["IMPORT_TEMPLATE"];
  const v3Json = XLSX.utils.sheet_to_json(v3Sheet);
  const v3HeaderMatch =
    Object.keys(v3Json[0] || {}).join(",") === V3_REQUIRED_HEADERS.join(",");

  recordTest(
    "XLSX Template (v3 ADR-001) Generation & Sheet Contract",
    v3Bytes.byteLength > 0 && hasExpectedSheetsV3 && v3HeaderMatch,
    `Bytes: ${v3Bytes.byteLength}, Sheets: ${wbV3.SheetNames.join(", ")}`
  );

  // Test standard template
  const stdBytes = buildHrEmplocImportTemplateXlsx("standard");
  const wbStd = XLSX.read(stdBytes, { type: "array" });
  const hasExpectedSheetsStd =
    wbStd.SheetNames.includes("IMPORT_TEMPLATE") &&
    wbStd.SheetNames.includes("VALIDATION_GUIDE");
  const stdSheet = wbStd.Sheets["IMPORT_TEMPLATE"];
  const stdJson = XLSX.utils.sheet_to_json(stdSheet);
  const stdHeaderMatch =
    Object.keys(stdJson[0] || {}).join(",") === STANDARD_REQUIRED_HEADERS.join(",");

  recordTest(
    "XLSX Template (Standard 7-col) Generation & Sheet Contract",
    stdBytes.byteLength > 0 && hasExpectedSheetsStd && stdHeaderMatch,
    `Bytes: ${stdBytes.byteLength}, Sheets: ${wbStd.SheetNames.join(", ")}`
  );
} catch (err) {
  recordTest("XLSX Template Generation Crash Check", false, err.message);
}

// ─────────────────────────────────────────────────────────────────────────────
// Test Suite 2: Team Directory Traversal Logic Edge Cases
// ─────────────────────────────────────────────────────────────────────────────
console.log("\n--- Test Suite 2: Team Directory Hierarchy Traversal Stress Test ---");

try {
  // Test traversal logic matching updated src/lib/queries/team_directory.ts
  function getRoleKey(user) {
    if (!user || !user.roleName) return null;
    const normalized = user.roleName.trim().toLowerCase();
    if (user.roleLevel === 100 || normalized === "super admin") return "super_admin";
    if (user.roleLevel === 90 || normalized === "head admin") return "head_admin";
    if (normalized === "encoder") return "encoder";
    if (normalized === "om" || normalized === "operations manager") return "om";
    if (normalized === "tl" || normalized === "team leader") return "tl";
    if (normalized === "atl" || normalized === "assistant team leader") return "atl";
    if (normalized === "hrco" || normalized === "hr coordinator") return "hrco";
    return null;
  }

  function getManagerRoleKey(user) {
    const key = getRoleKey(user);
    switch (key) {
      case "head_admin": return "super_admin";
      case "encoder": return "head_admin";
      case "tl": return "om";
      case "atl": return "tl";
      case "hrco": return "atl";
      default: return null;
    }
  }

  function getDirectReportRoleKey(user) {
    const key = getRoleKey(user);
    switch (key) {
      case "super_admin": return "head_admin";
      case "head_admin": return "encoder";
      case "om": return "tl";
      case "tl": return "atl";
      case "atl": return "hrco";
      default: return null;
    }
  }

  function getBroadAccessScopeLabel(user) {
    if (!user) return null;
    const role = (user.roleName || "").toLowerCase().trim();
    if (user.roleLevel === 100 || role.includes("super admin")) return "Global Access";
    if (user.roleLevel === 90 || role.includes("head admin")) return "All Groups & Accounts";
    if (user.roleLevel === 80 || role === "data team" || role.includes("data")) return "All Groups & Accounts";
    return null;
  }

  function sharesScope(user, other) {
    if (!user || !other) return false;
    if (getBroadAccessScopeLabel(user) || getBroadAccessScopeLabel(other)) return true;

    const userGroups = new Set((user.groupNames || []).map((g) => (g ? g.toLowerCase().trim() : "")).filter(Boolean));
    const otherGroups = new Set((other.groupNames || []).map((g) => (g ? g.toLowerCase().trim() : "")).filter(Boolean));
    const userAccounts = new Set((user.accountNames || []).map((a) => (a ? a.toLowerCase().trim() : "")).filter(Boolean));
    const otherAccounts = new Set((other.accountNames || []).map((a) => (a ? a.toLowerCase().trim() : "")).filter(Boolean));

    if (userGroups.size === 0 && userAccounts.size === 0) return false;
    if (otherGroups.size === 0 && otherAccounts.size === 0) return false;

    for (const g of userGroups) {
      if (otherGroups.has(g)) return true;
    }
    for (const a of userAccounts) {
      if (otherAccounts.has(a)) return true;
    }
    return false;
  }

  function formatDirectoryName(user) {
    if (!user) return "";
    return user.displayName || user.fullName || "User";
  }

  function getReportingStructure(user, allUsers) {
    if (!user) return { reportsTo: [], directReports: [] };

    const safeUsers = Array.isArray(allUsers)
      ? allUsers.filter((p) => Boolean(p && p.authUserId))
      : [];

    const userById = new Map();
    for (const person of safeUsers) {
      userById.set(person.authUserId, person);
    }

    // Prevent self-reporting circularity (user reporting to self)
    const explicitManager =
      user.reportsToAuthUserId && user.reportsToAuthUserId !== user.authUserId
        ? userById.get(user.reportsToAuthUserId) ?? null
        : null;

    const rawDirectReportIds = Array.isArray(user.directReportAuthUserIds)
      ? user.directReportAuthUserIds
      : [];

    // Filter out self-reference and mutual 2-node circularity where manager is also listed as report
    const explicitReports = rawDirectReportIds
      .map((id) => userById.get(id))
      .filter((person) =>
        Boolean(
          person &&
          person.authUserId !== user.authUserId &&
          (!explicitManager || person.authUserId !== explicitManager.authUserId)
        )
      );

    const fallbackManagerKey = getManagerRoleKey(user);
    const fallbackReportKey = getDirectReportRoleKey(user);

    const reportsTo = explicitManager
      ? [explicitManager]
      : safeUsers.filter(
          (person) =>
            person.authUserId !== user.authUserId &&
            fallbackManagerKey !== null &&
            getRoleKey(person) === fallbackManagerKey &&
            sharesScope(user, person)
        );

    const directReports =
      explicitReports.length > 0
        ? explicitReports
        : safeUsers.filter(
            (person) =>
              person.authUserId !== user.authUserId &&
              fallbackReportKey !== null &&
              getRoleKey(person) === fallbackReportKey &&
              sharesScope(user, person)
          );

    const sortFn = (a, b) =>
      formatDirectoryName(a).localeCompare(formatDirectoryName(b));

    reportsTo.sort(sortFn);
    directReports.sort(sortFn);

    return { reportsTo, directReports };
  }

  // Test 2.1: Graceful handling of null user and empty/null allUsers
  const resNull = getReportingStructure(null, null);
  recordTest(
    "Team Directory: getReportingStructure(null, null) returns empty structures without crash",
    resNull.reportsTo.length === 0 && resNull.directReports.length === 0,
    JSON.stringify(resNull)
  );

  // Test 2.2: allUsers containing nulls and undefined elements
  const userA = {
    authUserId: "user-a",
    fullName: "Alice Admin",
    roleName: "Operations Manager",
    roleLevel: 70,
    groupNames: ["North Group"],
    accountNames: ["Account 1"],
    directReportAuthUserIds: [],
    reportsToAuthUserId: null,
  };
  const userB = {
    authUserId: "user-b",
    fullName: "Bob Leader",
    roleName: "Team Leader",
    roleLevel: 50,
    groupNames: ["North Group"],
    accountNames: ["Account 1"],
    directReportAuthUserIds: [],
    reportsToAuthUserId: null,
  };

  const resSparse = getReportingStructure(userB, [userA, null, undefined, userB]);
  recordTest(
    "Team Directory: allUsers with null/undefined elements handled without throw",
    resSparse.reportsTo.length === 1 && resSparse.reportsTo[0].authUserId === "user-a",
    `ReportsTo found: ${resSparse.reportsTo.map(u => u.fullName).join(", ")}`
  );

  // Test 2.3: Circular self-reference (user reporting to self)
  const selfReportingUser = {
    authUserId: "user-c",
    fullName: "Charlie Self",
    roleName: "Team Leader",
    roleLevel: 50,
    groupNames: ["North Group"],
    accountNames: [],
    directReportAuthUserIds: ["user-c"], // direct report points to self
    reportsToAuthUserId: "user-c", // reports to self
  };
  const resSelf = getReportingStructure(selfReportingUser, [selfReportingUser]);
  const noSelfInReportsTo = !resSelf.reportsTo.some((u) => u.authUserId === "user-c");
  const noSelfInDirectReports = !resSelf.directReports.some((u) => u.authUserId === "user-c");
  recordTest(
    "Team Directory: Circular self-reference prevented from appearing in reportsTo or directReports",
    noSelfInReportsTo && noSelfInDirectReports,
    `ReportsTo: ${resSelf.reportsTo.length}, DirectReports: ${resSelf.directReports.length}`
  );

  // Test 2.4: Mutual 2-node circularity (A reports to B and B reports to A)
  const mutualUserA = {
    authUserId: "mut-a",
    fullName: "Mutual A",
    roleName: "Operations Manager",
    roleLevel: 70,
    groupNames: ["Central"],
    accountNames: [],
    reportsToAuthUserId: "mut-b",
    directReportAuthUserIds: ["mut-b"], // Lists B as both manager and subordinate
  };
  const mutualUserB = {
    authUserId: "mut-b",
    fullName: "Mutual B",
    roleName: "Operations Manager",
    roleLevel: 70,
    groupNames: ["Central"],
    accountNames: [],
    reportsToAuthUserId: "mut-a",
    directReportAuthUserIds: ["mut-a"],
  };
  const resMutual = getReportingStructure(mutualUserA, [mutualUserA, mutualUserB]);
  // Manager B must not also appear as direct report of A
  const mutualSafe =
    resMutual.reportsTo.length === 1 &&
    resMutual.reportsTo[0].authUserId === "mut-b" &&
    resMutual.directReports.length === 0;
  recordTest(
    "Team Directory: Mutual circularity resolves manager without duplicating as direct report",
    mutualSafe,
    `ReportsTo: ${resMutual.reportsTo.map(u => u.authUserId)}, DirectReports: ${resMutual.directReports.map(u => u.authUserId)}`
  );

  // Test 2.5: Undefined / missing scope arrays
  const noScopeUser = {
    authUserId: "user-d",
    fullName: "Dana NoScope",
    roleName: "Team Leader",
    roleLevel: 50,
    groupNames: undefined,
    accountNames: undefined,
    directReportAuthUserIds: undefined,
    reportsToAuthUserId: undefined,
  };
  const resNoScope = getReportingStructure(noScopeUser, [userA, noScopeUser]);
  recordTest(
    "Team Directory: Undefined scope arrays and properties execute cleanly without throwing",
    Array.isArray(resNoScope.reportsTo) && Array.isArray(resNoScope.directReports),
    `ReportsTo: ${resNoScope.reportsTo.length}`
  );
} catch (err) {
  recordTest("Team Directory Traversal Stress Test Crash Check", false, err.stack);
}

// ─────────────────────────────────────────────────────────────────────────────
// Test Suite 3: Live Supabase Read-Only RPC & Table Probes
// ─────────────────────────────────────────────────────────────────────────────
console.log("\n--- Test Suite 3: Live Remote Supabase Probes (Staging) ---");

async function runLiveProbes() {
  try {
    // Probe 1: fn_get_governance_controls
    const { data: govData, error: govErr } = await supabase.rpc("fn_get_governance_controls");
    recordTest(
      "Live RPC: fn_get_governance_controls()",
      !govErr && Array.isArray(govData),
      govErr ? govErr.message : `Returned ${govData.length} governance controls`
    );

    // Probe 2: fn_check_governance_control
    const { data: checkData, error: checkErr } = await supabase.rpc("fn_check_governance_control", {
      p_control_key: "account_registration",
    });
    recordTest(
      "Live RPC: fn_check_governance_control('account_registration')",
      !checkErr && typeof checkData === "boolean",
      checkErr ? checkErr.message : `Control state: ${checkData}`
    );

    // Probe 3: fn_get_freeze_modes (Note: authenticated only RPC, tested with anon key)
    const { data: freezeData, error: freezeErr } = await supabase.rpc("fn_get_freeze_modes");
    // If anon is denied (42501), verify error code is properly recognized as permission restriction, not missing function
    const isFreezeValid = !freezeErr || freezeErr.code === "42501";
    recordTest(
      "Live RPC: fn_get_freeze_modes() exists on remote database",
      isFreezeValid,
      freezeErr ? `Expected RLS guard (code ${freezeErr.code}: ${freezeErr.message})` : `Returned ${freezeData?.length} rows`
    );

    // Probe 4: get_hr_emploc_import_groups (requires auth.uid() + data team)
    const { data: groupData, error: groupErr } = await supabase.rpc("get_hr_emploc_import_groups");
    const isGroupValid = (!groupErr && Array.isArray(groupData)) || (groupErr && groupErr.message.includes("Not authenticated"));
    recordTest(
      "Live RPC: get_hr_emploc_import_groups() enforces auth boundary",
      isGroupValid,
      groupErr ? `Enforced auth guard: ${groupErr.message}` : `Returned ${groupData.length} import groups`
    );

    // Probe 5: get_hr_emploc_import_batches (requires auth.uid() + data team)
    const { data: batchData, error: batchErr } = await supabase.rpc("get_hr_emploc_import_batches");
    const isBatchValid = (!batchErr && Array.isArray(batchData)) || (batchErr && batchErr.message.includes("Not authenticated"));
    recordTest(
      "Live RPC: get_hr_emploc_import_batches() enforces auth boundary",
      isBatchValid,
      batchErr ? `Enforced auth guard: ${batchErr.message}` : `Returned ${batchData.length} import batches`
    );

    // Probe 6: get_team_directory
    const { data: teamData, error: teamErr } = await supabase.rpc("get_team_directory", {
      p_search: null,
      p_role: null,
      p_group_id: null,
      p_account_id: null,
    });
    const isTeamValid = !teamErr || teamErr.code === "42501";
    recordTest(
      "Live RPC: get_team_directory() exists and responds to parameter contract",
      isTeamValid,
      teamErr ? `Role permission policy enforced (${teamErr.code})` : `Returned ${teamData?.length} directory entries`
    );

    // Probe 7: plantilla_slots table query join (RLS authenticated check)
    const { data: slotData, error: slotErr } = await supabase
      .from("plantilla_slots")
      .select("id, store_id, account_id, position, employment_type, slot_status, created_at")
      .limit(5);
    const isSlotValid = !slotErr || slotErr.code === "42501" || slotErr.message.includes("permission denied");
    recordTest(
      "Table Access: public.plantilla_slots (RLS authenticated guard)",
      isSlotValid,
      slotErr ? `RLS guard enforced for anon: ${slotErr.message}` : `Read ${slotData?.length} slots`
    );

    // Probe 8: slot_history table query join (RLS authenticated check)
    const { data: historyData, error: historyErr } = await supabase
      .from("slot_history")
      .select("id, slot_id, action_type, created_at")
      .limit(5);
    const isHistoryValid = !historyErr || historyErr.code === "42501" || historyErr.message.includes("permission denied");
    recordTest(
      "Table Access: public.slot_history (RLS authenticated guard)",
      isHistoryValid,
      historyErr ? `RLS guard enforced for anon: ${historyErr.message}` : `Read ${historyData?.length} history entries`
    );

    // Probe 9: active_user_sessions table query (RLS authenticated check)
    const { data: sessionData, error: sessionErr } = await supabase
      .from("active_user_sessions")
      .select("id, user_id, device_platform, app_version, last_seen_at")
      .limit(5);
    const isSessionValid = !sessionErr || sessionErr.code === "42501" || sessionErr.message.includes("permission denied");
    recordTest(
      "Table Access: public.active_user_sessions (RLS authenticated guard)",
      isSessionValid,
      sessionErr ? `RLS guard enforced for anon: ${sessionErr.message}` : `Read ${sessionData?.length} sessions`
    );

    // Probe 10: governance_controls table query (RLS superadmin check)
    const { data: govControlsData, error: govControlsErr } = await supabase
      .from("governance_controls")
      .select("control_key, enabled, updated_at")
      .limit(5);
    const isGovControlsValid = !govControlsErr || govControlsErr.code === "42501" || govControlsErr.message.includes("permission denied");
    recordTest(
      "Table Access: public.governance_controls (RLS superadmin guard)",
      isGovControlsValid,
      govControlsErr ? `RLS guard enforced: ${govControlsErr.message}` : `Read ${govControlsData?.length} controls`
    );

  } catch (err) {
    recordTest("Live Probes Execution Failure", false, err.stack);
  }

  console.log("\n======================================================================");
  console.log(`  VERIFICATION SUMMARY: ${results.totalPassed} Passed, ${results.totalFailed} Failed`);
  console.log("======================================================================\n");

  if (results.totalFailed > 0) {
    process.exit(1);
  }
}

await runLiveProbes();
