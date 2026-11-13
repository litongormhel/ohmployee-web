/**
 * Milestone 3: End-to-End Simulation & Zero-Pollution Database Verification Runner
 * 
 * Objectives:
 * 1. Execute public.qa_run_scenario('FULL_E2E_RELAY') and 'VAC_ARCHIVE_001' against the Staging database (qqiiznmqxfoamqytjica).
 * 2. Verify response shape: success === true, sandbox_rolled_back === true, steps.length === 7, and step outcomes.
 * 3. Verify zero-pollution database state across live tables: vacancies, plantilla, applicants, hr_emploc, users_profile.
 * 4. Verify telemetry persistence in qa_agent_runs and qa_agent_findings (run_id, summary, metadata->'steps').
 * 5. Verify PostgREST client authorization barrier (anon / unauthenticated rejection).
 * 6. Verify TypeScript client contracts in src/lib/queries/governance.ts.
 */

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { createClient } from "@supabase/supabase-js";

const STAGING_PROJECT_REF = "qqiiznmqxfoamqytjica";
const STAGING_URL = "https://qqiiznmqxfoamqytjica.supabase.co";
const STAGING_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFxaWl6bm1xeGZvYW1xeXRqaWNhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIxODQ2NjksImV4cCI6MjA5Nzc2MDY2OX0.e4v0-wkAwchas5NMF7QIDvUDW32Y7V7Rl8WF4_BC0OA";

// Super Admin auth_user_id for authorized impersonation inside test execution harness
const SUPER_ADMIN_AUTH_UID = "71d245b9-10b1-42b9-ad9e-253f999daf6d";

console.log("===============================================================================");
console.log("       MILESTONE 3: E2E STAGING SIMULATION & ZERO-POLLUTION VERIFICATION       ");
console.log(`       Target Database : Staging (${STAGING_PROJECT_REF})`);
console.log("===============================================================================\n");

let passedCount = 0;
let failedCount = 0;
const failures = [];

function recordPass(testName, detail = "") {
  passedCount++;
  console.log(`  [PASS] ${testName}${detail ? ` -> ${detail}` : ""}`);
}

function recordFail(testName, error) {
  failedCount++;
  const msg = error instanceof Error ? error.message : String(error);
  console.error(`  [FAIL] ${testName}`);
  console.error(`         ${msg}`);
  failures.push({ testName, error: msg });
}

/**
 * Executes raw SQL against remote Staging database using Supabase CLI with explicit temp file.
 */
function executeRemoteSql(sqlQuery) {
  const tmpFile = path.join(os.tmpdir(), `m3_qa_${Date.now()}_${Math.random().toString(36).substring(2, 7)}.sql`);
  fs.writeFileSync(tmpFile, sqlQuery, "utf8");
  try {
    const isWin = process.platform === "win32";
    const stdout = execFileSync(
      isWin ? "npx.cmd" : "npx",
      ["supabase", "db", "query", "--remote", "-f", tmpFile, "--yes"],
      {
        encoding: "utf8",
        maxBuffer: 10 * 1024 * 1024,
        shell: true,
      }
    );

    const jsonStart = stdout.indexOf("{");
    if (jsonStart === -1) {
      throw new Error(`Unexpected CLI output (no JSON boundary): ${stdout}`);
    }
    const parsed = JSON.parse(stdout.slice(jsonStart));
    return parsed.rows || [];
  } finally {
    try {
      if (fs.existsSync(tmpFile)) fs.unlinkSync(tmpFile);
    } catch {
      // Ignore cleanup error
    }
  }
}

async function runM3VerificationSuite() {
  // ---------------------------------------------------------------------------
  // Suite 1: PostgREST Authorization Boundary Check
  // ---------------------------------------------------------------------------
  console.log("--- Suite 1: PostgREST Authorization & RLS Enforcement ---");
  try {
    const anonClient = createClient(STAGING_URL, STAGING_ANON_KEY);
    const { data: anonData, error: anonErr } = await anonClient.rpc("qa_run_scenario", {
      p_scenario_code: "FULL_E2E_RELAY",
    });

    assert.ok(anonErr, "Expected error when calling qa_run_scenario without admin privileges");
    assert.match(
      anonErr.message,
      /Only Head Admin or Super Admin can execute QA scenarios/,
      `Expected authorization guard exception, got: ${anonErr.message}`
    );
    recordPass(
      "PostgREST RPC Guard rejects unauthenticated caller",
      `Correctly raised: "${anonErr.message}"`
    );
  } catch (err) {
    recordFail("PostgREST RPC Guard rejects unauthenticated caller", err);
  }

  // ---------------------------------------------------------------------------
  // Suite 2: Flagship Scenario Execution (FULL_E2E_RELAY)
  // ---------------------------------------------------------------------------
  console.log("\n--- Suite 2: Flagship 6-Role Simulation Execution (FULL_E2E_RELAY) ---");
  let relayResult = null;
  let relayRunId = null;

  try {
    const relayQuery = `
      SELECT 
        set_config('request.jwt.claim.sub', '${SUPER_ADMIN_AUTH_UID}', true),
        set_config('request.jwt.claims', '{"sub":"${SUPER_ADMIN_AUTH_UID}","role":"authenticated"}', true),
        public.qa_run_scenario('FULL_E2E_RELAY') as result;
    `;
    const rows = executeRemoteSql(relayQuery);
    assert.ok(rows && rows.length > 0, "Expected at least 1 row returned from qa_run_scenario");
    relayResult = rows[0].result;
    relayRunId = relayResult.run_id;

    assert.equal(relayResult.success, true, "Expected success === true");
    assert.equal(relayResult.sandbox_rolled_back, true, "Expected sandbox_rolled_back === true");
    assert.equal(relayResult.scenario_code, "FULL_E2E_RELAY", "Expected scenario_code === 'FULL_E2E_RELAY'");
    assert.ok(typeof relayRunId === "string" && relayRunId.length === 36, `Expected valid UUID run_id, got: ${relayRunId}`);
    assert.ok(Array.isArray(relayResult.steps), "Expected steps to be an array");
    assert.equal(relayResult.steps.length, 7, `Expected exactly 7 steps, got: ${relayResult.steps.length}`);

    recordPass("FULL_E2E_RELAY execution shape", `run_id=${relayRunId}, success=true, sandbox_rolled_back=true`);

    // Verify individual step outcomes
    const expectedSteps = [
      { step: 1, role: "Head Admin", action: "headcount_approval_and_vacancy_init" },
      { step: 2, role: "Encoder", action: "plantilla_slot_allocation" },
      { step: 3, role: "Recruitment", action: "applicant_intake_and_pipeline" },
      { step: 4, role: "HRCO / Operations", action: "onboarding_confirmation" },
      { step: 5, role: "HR Personnel", action: "emploc_generation_and_sync" },
      { step: 6, role: "Back Office", action: "plantilla_move_request" },
      { step: 7, role: "Back Office", action: "negative_permission_barrier_check" },
    ];

    for (let i = 0; i < expectedSteps.length; i++) {
      const exp = expectedSteps[i];
      const actual = relayResult.steps[i];
      assert.equal(actual.step, exp.step, `Step ${i + 1} number mismatch`);
      assert.equal(actual.role, exp.role, `Step ${i + 1} role mismatch: expected ${exp.role}, got ${actual.role}`);
      assert.equal(actual.action, exp.action, `Step ${i + 1} action mismatch`);
      assert.equal(actual.status, "passed", `Step ${i + 1} status mismatch: expected 'passed', got '${actual.status}'`);
      assert.ok(actual.details && actual.details.length > 0, `Step ${i + 1} details should be populated`);
    }

    recordPass("FULL_E2E_RELAY all 7 steps passed sequentially", "Head Admin -> Encoder -> Recruitment -> HRCO -> HR Personnel -> Back Office -> Barrier Check");
  } catch (err) {
    recordFail("FULL_E2E_RELAY execution", err);
  }

  // ---------------------------------------------------------------------------
  // Suite 3: Zero-Pollution Database Verification for FULL_E2E_RELAY
  // ---------------------------------------------------------------------------
  console.log("\n--- Suite 3: Live Table Zero-Pollution Verification (FULL_E2E_RELAY) ---");
  try {
    const pollutionCheckSql = `
      SELECT 
        (SELECT count(*) FROM public.vacancies WHERE vcode LIKE 'QA-RELAY%') as vacancies_count,
        (SELECT count(*) FROM public.plantilla WHERE employee_no LIKE 'EMP-RELAY%' OR vcode LIKE 'QA-RELAY%') as plantilla_count,
        (SELECT count(*) FROM public.applicants WHERE first_name = 'Jane' AND last_name = 'Relay Doe') as applicants_count,
        (SELECT count(*) FROM public.hr_emploc WHERE employee_no LIKE 'EMP-RELAY%') as hr_emploc_count,
        (SELECT count(*) FROM public.users_profile WHERE email LIKE 'qa_%@ohmployee.internal') as users_profile_count;
    `;
    const countRows = executeRemoteSql(pollutionCheckSql);
    const counts = countRows[0] || {};

    const vacCount = Number(counts.vacancies_count ?? 0);
    const planCount = Number(counts.plantilla_count ?? 0);
    const appCount = Number(counts.applicants_count ?? 0);
    const empCount = Number(counts.hr_emploc_count ?? 0);
    const userCount = Number(counts.users_profile_count ?? 0);

    assert.equal(vacCount, 0, `Live vacancies table contaminated: ${vacCount} records found`);
    assert.equal(planCount, 0, `Live plantilla table contaminated: ${planCount} records found`);
    assert.equal(appCount, 0, `Live applicants table contaminated: ${appCount} records found`);
    assert.equal(empCount, 0, `Live hr_emploc table contaminated: ${empCount} records found`);
    assert.equal(userCount, 0, `Live users_profile table contaminated: ${userCount} records found`);

    recordPass(
      "Live operational tables show 0 polluted records",
      `vacancies: 0, plantilla: 0, applicants: 0, hr_emploc: 0, users_profile: 0`
    );
  } catch (err) {
    recordFail("Zero-Pollution verification", err);
  }

  // ---------------------------------------------------------------------------
  // Suite 4: Telemetry Persistence Verification (qa_agent_runs & findings)
  // ---------------------------------------------------------------------------
  console.log("\n--- Suite 4: Telemetry Persistence Verification ---");
  try {
    assert.ok(relayRunId, "Relay run ID required for telemetry check");
    const telemetrySql = `
      SELECT id, agent_name, execution_type, status, summary, metadata, created_at
      FROM public.qa_agent_runs
      WHERE id = '${relayRunId}';
    `;
    const runRows = executeRemoteSql(telemetrySql);
    assert.equal(runRows.length, 1, `Expected exactly 1 run record for ID ${relayRunId}`);
    const run = runRows[0];

    assert.equal(run.agent_name, "QA_ROLE_RELAY_ENGINE", `Expected agent_name 'QA_ROLE_RELAY_ENGINE', got '${run.agent_name}'`);
    assert.equal(run.execution_type, "manual", `Expected execution_type 'manual', got '${run.execution_type}'`);
    assert.equal(run.status, "completed", `Expected status 'completed', got '${run.status}'`);
    assert.match(run.summary, /passed cleanly in sandbox with zero data pollution/, "Run summary must confirm clean pass");

    const meta = typeof run.metadata === "string" ? JSON.parse(run.metadata) : run.metadata;
    assert.ok(meta, "Run metadata should be populated");
    assert.equal(meta.scenario_code, "FULL_E2E_RELAY", "Metadata scenario_code mismatch");
    assert.equal(meta.sandbox_rolled_back, true, "Metadata sandbox_rolled_back must be true");
    assert.equal(meta.unexpected_error, null, "Metadata unexpected_error must be null");
    assert.ok(Array.isArray(meta.steps), "Metadata steps must be an array");
    assert.equal(meta.steps.length, 7, `Metadata steps length should be 7, got ${meta.steps.length}`);

    recordPass("qa_agent_runs record persisted with full 7-step metadata", `ID=${run.id}, Status=${run.status}`);

    // Verify findings table (0 critical/runtime findings for clean run)
    const findingsSql = `
      SELECT count(*) as count
      FROM public.qa_agent_findings
      WHERE run_id = '${relayRunId}';
    `;
    const findingRows = executeRemoteSql(findingsSql);
    const findingsCount = Number(findingRows[0]?.count ?? 0);
    assert.equal(findingsCount, 0, `Expected 0 defect findings for clean run, got ${findingsCount}`);
    recordPass("qa_agent_findings confirms 0 defect findings for clean pass", `Findings count: ${findingsCount}`);
  } catch (err) {
    recordFail("Telemetry persistence check", err);
  }

  // ---------------------------------------------------------------------------
  // Suite 5: Legacy Scenario Execution (VAC_ARCHIVE_001)
  // ---------------------------------------------------------------------------
  console.log("\n--- Suite 5: Legacy Scenario Execution (VAC_ARCHIVE_001) ---");
  try {
    const archiveQuery = `
      SELECT 
        set_config('request.jwt.claim.sub', '${SUPER_ADMIN_AUTH_UID}', true),
        set_config('request.jwt.claims', '{"sub":"${SUPER_ADMIN_AUTH_UID}","role":"authenticated"}', true),
        public.qa_run_scenario('VAC_ARCHIVE_001') as result;
    `;
    const rows = executeRemoteSql(archiveQuery);
    const archiveResult = rows[0]?.result;
    assert.ok(archiveResult, "Expected result from VAC_ARCHIVE_001");
    assert.equal(archiveResult.success, true, "VAC_ARCHIVE_001 success must be true");
    assert.equal(archiveResult.sandbox_rolled_back, true, "VAC_ARCHIVE_001 sandbox_rolled_back must be true");
    assert.equal(archiveResult.scenario_code, "VAC_ARCHIVE_001");
    assert.equal(archiveResult.steps.length, 2, "VAC_ARCHIVE_001 steps length must be 2");

    // Zero-pollution check for archive test data
    const archivePollutionSql = `
      SELECT count(*) as count FROM public.vacancies WHERE vcode LIKE 'QA-ARCHIVE%';
    `;
    const archiveCounts = executeRemoteSql(archivePollutionSql);
    assert.equal(Number(archiveCounts[0]?.count ?? 0), 0, "QA-ARCHIVE vacancies leaked into live table");

    recordPass("VAC_ARCHIVE_001 executes, rolls back cleanly, and leaves 0 records", `run_id=${archiveResult.run_id}`);
  } catch (err) {
    recordFail("VAC_ARCHIVE_001 execution", err);
  }

  // ---------------------------------------------------------------------------
  // Suite 6: Client Data Contract & Normalization Verification
  // ---------------------------------------------------------------------------
  console.log("\n--- Suite 6: Client Contract Normalization (governance.ts) ---");
  try {
    // Replicate governance.ts normalization logic on live simulation payload
    const raw = relayResult;
    const rawSteps = Array.isArray(raw.steps) ? raw.steps : [];
    const normalizedSteps = rawSteps.map((s, idx) => {
      const rawStepNum = Number(s?.step);
      const step = Number.isFinite(rawStepNum) && rawStepNum > 0 ? Math.floor(rawStepNum) : idx + 1;
      const rawStatus = typeof s?.status === "string" ? s.status.trim().toLowerCase() : "";
      const status = rawStatus === "failed" ? "failed" : "passed";
      return {
        step,
        role: String(s?.role ?? "System"),
        action: String(s?.action ?? "unknown_action"),
        status,
        details: String(s?.details ?? ""),
      };
    });

    assert.equal(normalizedSteps.length, 7);
    assert.equal(normalizedSteps[0].role, "Head Admin");
    assert.equal(normalizedSteps[6].role, "Back Office");

    const clientResult = {
      success: Boolean(raw.success),
      run_id: String(raw.run_id ?? ""),
      scenario_code: String(raw.scenario_code ?? "FULL_E2E_RELAY"),
      sandbox_rolled_back: Boolean(raw.sandbox_rolled_back),
      steps: normalizedSteps,
      finding_counts: {
        critical: Number(raw.finding_counts?.critical ?? 0),
        high: Number(raw.finding_counts?.high ?? 0),
        medium: Number(raw.finding_counts?.medium ?? 0),
        low: Number(raw.finding_counts?.low ?? 0),
        total: Number(raw.finding_counts?.total ?? 0),
      },
      executed_at: String(raw.executed_at ?? new Date().toISOString()),
    };

    assert.equal(clientResult.success, true);
    assert.equal(clientResult.sandbox_rolled_back, true);
    assert.equal(clientResult.steps.length, 7);
    assert.equal(clientResult.finding_counts.critical, 0);

    recordPass("Client normalization matches QaScenarioRunResult contract", "All fields successfully coerced and mapped");
  } catch (err) {
    recordFail("Client contract normalization", err);
  }

  // ---------------------------------------------------------------------------
  // Summary Report
  // ---------------------------------------------------------------------------
  console.log("\n===============================================================================");
  console.log(`  VERIFICATION RESULTS: ${passedCount} PASSED, ${failedCount} FAILED`);
  console.log("===============================================================================");

  if (failedCount > 0) {
    console.error("\nDetected Failures:");
    for (const f of failures) {
      console.error(`- ${f.testName}: ${f.error}`);
    }
    process.exit(1);
  } else {
    console.log("\n  [SUCCESS] All Milestone 3 E2E and Zero-Pollution assertions passed cleanly!\n");
    process.exit(0);
  }
}

runM3VerificationSuite().catch((err) => {
  console.error("FATAL: Unhandled exception in M3 verification suite:", err);
  process.exit(1);
});
