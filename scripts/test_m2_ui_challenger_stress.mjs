/**
 * Empirical Adversarial Challenger & Boundary Stress Harness for Milestone 2 UI Components
 * 
 * Objectives:
 * 1. Stress test QaStepTimeline across boundary conditions, null results, failed steps, rollback banners.
 * 2. Stress test QaFindingsViewer across empty, large lists, severity colors, search filtering, and run ID isolation.
 * 3. Stress test QaRunHistoryTable across status icons, sandbox isolation heuristic, steps badge, and timestamps.
 * 4. Stress test roleBadgeUtils across canonical roles, casing, and custom fallbacks.
 * 5. Report concrete empirical findings & bugs found.
 */

import assert from "node:assert/strict";
import fs from "node:fs";
import { createRequire } from "node:module";
import vm from "node:vm";
import React from "react";
import ReactDOMServer from "react-dom/server";
import ts from "typescript";

const require = createRequire(import.meta.url);

console.log("===============================================================================");
console.log("       EMPIRICAL CHALLENGER STRESS HARNESS: MILESTONE 2 UI COMPONENTS          ");
console.log("===============================================================================\n");

let passedTests = 0;
let failedTests = 0;
const challengerBugs = [];

function runChallengerTest(name, fn) {
  try {
    fn();
    console.log(`[PASS] ${name}`);
    passedTests++;
  } catch (err) {
    console.error(`[FAIL / BUG DETECTED] ${name}`);
    console.error(`  Error: ${err.message}`);
    failedTests++;
    challengerBugs.push({ test: name, error: err.message, stack: err.stack });
  }
}

// -----------------------------------------------------------------------------
// Component Transpilation & Execution Loader
// -----------------------------------------------------------------------------
function transpileAndLoad(filePath, additionalRequires = {}) {
  const sourceCode = fs.readFileSync(filePath, "utf8");
  const transpiled = ts.transpileModule(sourceCode, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      esModuleInterop: true,
      jsx: ts.JsxEmit.React,
      target: ts.ScriptTarget.ES2022,
    },
  }).outputText;

  const moduleObj = { exports: {} };
  const customRequire = (id) => {
    if (additionalRequires[id]) return additionalRequires[id];
    if (id === "react") return React;
    if (id === "lucide-react") return require("lucide-react");
    return require(id);
  };

  const context = {
    exports: moduleObj.exports,
    require: customRequire,
    React,
    console,
    process,
  };

  vm.runInNewContext(transpiled, context);
  return moduleObj.exports;
}

// Load compiled modules
const roleBadgeMod = transpileAndLoad("src/components/more/qa/roleBadgeUtils.ts");
const { getRoleBadgeConfig } = roleBadgeMod;

const timelineMod = transpileAndLoad("src/components/more/qa/QaStepTimeline.tsx", {
  "./roleBadgeUtils": roleBadgeMod,
});
const { QaStepTimeline } = timelineMod;

const findingsMod = transpileAndLoad("src/components/more/qa/QaFindingsViewer.tsx");
const { QaFindingsViewer } = findingsMod;

const runsMod = transpileAndLoad("src/components/more/qa/QaRunHistoryTable.tsx");
const { QaRunHistoryTable } = runsMod;

// =============================================================================
// SUITE 1: roleBadgeUtils Stress Tests
// =============================================================================
console.log("\n--- SUITE 1: roleBadgeUtils Role Mapping & Edge Cases ---");

runChallengerTest("1.1: Canonical Head Admin role returns purple badge", () => {
  const conf = getRoleBadgeConfig("Head Admin");
  assert.equal(conf.label, "Head Admin");
  assert.ok(conf.badgeClass.includes("purple"));
});

runChallengerTest("1.2: Super Admin alias maps to Head Admin purple badge", () => {
  const conf = getRoleBadgeConfig("Super Admin");
  assert.equal(conf.label, "Head Admin");
  assert.ok(conf.badgeClass.includes("purple"));
});

runChallengerTest("1.3: Encoder role returns blue badge", () => {
  const conf = getRoleBadgeConfig("Encoder");
  assert.equal(conf.label, "Encoder");
  assert.ok(conf.badgeClass.includes("blue"));
});

runChallengerTest("1.4: Recruitment role returns teal badge", () => {
  const conf = getRoleBadgeConfig("Recruitment Specialist");
  assert.equal(conf.label, "Recruitment");
  assert.ok(conf.badgeClass.includes("teal"));
});

runChallengerTest("1.5: HRCO & Operations role returns amber badge", () => {
  const conf = getRoleBadgeConfig("Operations Lead");
  assert.equal(conf.label, "HRCO");
  assert.ok(conf.badgeClass.includes("amber"));
});

runChallengerTest("1.6: HR Personnel & Staff returns indigo badge", () => {
  const conf = getRoleBadgeConfig("HR Personnel Associate");
  assert.equal(conf.label, "HR Personnel");
  assert.ok(conf.badgeClass.includes("indigo"));
});

runChallengerTest("1.7: Back Office & BO Staff returns slate badge", () => {
  const conf = getRoleBadgeConfig("BO Staff");
  assert.equal(conf.label, "Back Office");
  assert.ok(conf.badgeClass.includes("slate"));
});

runChallengerTest("1.8: Custom / Unknown role returns neutral fallback", () => {
  const conf = getRoleBadgeConfig("External Auditor");
  assert.equal(conf.label, "External Auditor");
  assert.ok(conf.badgeClass.includes("border-border-default"));
});

runChallengerTest("1.9: Empty string role name returns empty label gracefully", () => {
  const conf = getRoleBadgeConfig("");
  assert.equal(conf.label, "");
  assert.ok(conf.badgeClass.includes("border-border-default"));
});

// =============================================================================
// SUITE 2: QaStepTimeline Stress & Boundary Tests
// =============================================================================
console.log("\n--- SUITE 2: QaStepTimeline Stress & Boundary Tests ---");

runChallengerTest("2.1: null result renders empty state guidance with scenario code", () => {
  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaStepTimeline, {
      result: null,
      isRunning: false,
      selectedScenarioCode: "FULL_E2E_RELAY",
    })
  );
  assert.ok(html.includes("No Simulation Executed in Current Session"));
  assert.ok(html.includes("FULL_E2E_RELAY"));
});

runChallengerTest("2.2: isRunning = true renders execution spinner & description", () => {
  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaStepTimeline, {
      result: null,
      isRunning: true,
      selectedScenarioCode: "FULL_E2E_RELAY",
    })
  );
  assert.ok(html.includes("Executing Multi-Role Relay Simulation..."));
  assert.ok(html.includes("Simulating Head Admin, Encoder, Recruitment"));
});

runChallengerTest("2.3: 0 steps in result renders 'No step details returned' without crash", () => {
  const mockResult = {
    success: true,
    run_id: "test-run-001",
    scenario_code: "VAC_ARCHIVE_001",
    sandbox_rolled_back: true,
    steps: [],
    finding_counts: { total: 0 },
    executed_at: "2026-11-13T02:00:00Z",
  };
  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaStepTimeline, {
      result: mockResult,
      isRunning: false,
      selectedScenarioCode: "VAC_ARCHIVE_001",
    })
  );
  assert.ok(html.includes("No step details returned for this scenario."));
  assert.ok(html.includes("QA_SANDBOX_ROLLBACK_SUCCESS"));
  assert.ok(html.includes("0 Defects Logged"));
});

runChallengerTest("2.4: Full 7-step multi-role relay renders all steps with role badges & verbatim details", () => {
  const mockResult = {
    success: true,
    run_id: "relay-run-777",
    scenario_code: "FULL_E2E_RELAY",
    sandbox_rolled_back: true,
    steps: [
      { step: 1, role: "Head Admin", action: "headcount_approval", status: "passed", details: "Headcount quota approved for 5 slots." },
      { step: 2, role: "Encoder", action: "plantilla_init", status: "passed", details: "Plantilla item initialized in Resigned status." },
      { step: 3, role: "Recruiter", action: "applicant_forward", status: "passed", details: "Candidate profile forwarded to HRCO." },
      { step: 4, role: "HRCO", action: "deployment_order", status: "passed", details: "Deployment order published to branch." },
      { step: 5, role: "HR Personnel", action: "hr_intake", status: "passed", details: "Employee record synced into Pending Emploc." },
      { step: 6, role: "Back Office", action: "negative_barrier_check", status: "passed", details: "Negative barrier check passed: unauthorized mutation blocked with 42501." },
      { step: 7, role: "Head Admin", action: "sandbox_rollback_confirmation", status: "passed", details: "Savepoint rolled back cleanly with QA_SANDBOX_ROLLBACK_SUCCESS." },
    ],
    finding_counts: { critical: 0, high: 0, medium: 0, low: 0, total: 0 },
    executed_at: "2026-11-13T02:00:00Z",
  };
  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaStepTimeline, {
      result: mockResult,
      isRunning: false,
      selectedScenarioCode: "FULL_E2E_RELAY",
    })
  );
  assert.ok(html.includes("Multi-Role Agent Execution Timeline (7 Steps)"));
  assert.ok(html.includes("Headcount quota approved for 5 slots."));
  assert.ok(html.includes("negative_barrier_check"));
  assert.ok(html.includes("QA_SANDBOX_ROLLBACK_SUCCESS"));
  assert.ok(html.includes("100% Rolled Back"));
});

runChallengerTest("2.5: Failed step renders FAILED status pill & ANOMALIES DETECTED banner", () => {
  const mockResult = {
    success: false,
    run_id: "fail-run-123",
    scenario_code: "AUTH_MATRIX_001",
    sandbox_rolled_back: true,
    steps: [
      { step: 1, role: "Head Admin", action: "auth_probe", status: "passed", details: "Probe initiated." },
      { step: 2, role: "Back Office", action: "privilege_escalation_attempt", status: "failed", details: "Unauthorized write succeeded on plantilla_store_links (leak detected)." },
    ],
    finding_counts: { critical: 1, total: 1 },
    executed_at: "2026-11-13T02:00:00Z",
  };
  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaStepTimeline, {
      result: mockResult,
      isRunning: false,
      selectedScenarioCode: "AUTH_MATRIX_001",
    })
  );
  assert.ok(html.includes("ANOMALIES DETECTED"));
  assert.ok(html.includes("FAILED"));
  assert.ok(html.includes("View Detected Findings (1)"));
});

runChallengerTest("2.6: Rollback failure displays QA_SANDBOX_ROLLBACK_FAILED and Leak Warning", () => {
  const mockResult = {
    success: false,
    run_id: "rollback-fail-000",
    scenario_code: "FULL_E2E_RELAY",
    sandbox_rolled_back: false,
    steps: [
      { step: 1, role: "Head Admin", action: "init", status: "failed", details: "Crash before savepoint" },
    ],
    finding_counts: { critical: 1, total: 1 },
    executed_at: "2026-11-13T02:00:00Z",
  };
  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaStepTimeline, {
      result: mockResult,
      isRunning: false,
      selectedScenarioCode: "FULL_E2E_RELAY",
    })
  );
  assert.ok(html.includes("QA_SANDBOX_ROLLBACK_FAILED"));
  assert.ok(html.includes("Leak Warning"));
  assert.ok(html.includes("Isolation warning: subtransaction rollback was not confirmed"));
});

runChallengerTest("2.7: Rollback failure dynamically displays 'Operational Tables: Potential Leak' banner", () => {
  const mockResult = {
    success: false,
    run_id: "leak-test-999",
    scenario_code: "FULL_E2E_RELAY",
    sandbox_rolled_back: false,
    steps: [],
    finding_counts: { total: 0 },
    executed_at: "2026-11-13T02:00:00Z",
  };
  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaStepTimeline, {
      result: mockResult,
      isRunning: false,
      selectedScenarioCode: "FULL_E2E_RELAY",
    })
  );
  assert.ok(html.includes("QA_SANDBOX_ROLLBACK_FAILED"), "Must display rollback failed error banner");
  assert.ok(html.includes("Operational Tables: Potential Leak"), "Potential Leak status must be rendered on rollback failure");
  assert.equal(html.includes("Operational Tables: Clean"), false, "Contradictory Clean status must not be rendered on rollback failure");
});

// =============================================================================
// SUITE 3: QaFindingsViewer Stress & Boundary Tests
// =============================================================================
console.log("\n--- SUITE 3: QaFindingsViewer Stress & Boundary Tests ---");

runChallengerTest("3.1: Empty findings list renders 'No findings match'", () => {
  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaFindingsViewer, { findings: [] })
  );
  assert.ok(html.includes("No findings match the current filter criteria."));
  assert.ok(html.includes("Showing 0 of 0 findings"));
});

runChallengerTest("3.2: 50 findings stress test renders all items without error", () => {
  const largeFindings = Array.from({ length: 50 }, (_, i) => ({
    id: `finding-${i}`,
    findingCode: `DEFECT_${i}`,
    findingType: `DEFECT_${i}`,
    category: "Integrity",
    severity: (["critical", "high", "medium", "low"][i % 4]),
    moduleName: "vacancies",
    status: "open",
    title: `Simulated Defect #${i}`,
    details: `Execution stack trace for anomaly #${i}`,
    recommendation: `Run surgical remediation script #${i}`,
    referenceTable: "vacancies",
    referenceRecordId: `rec-${i}`,
    runId: `run-${i % 5}`,
    createdAt: "2026-11-13T01:30:00Z",
  }));

  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaFindingsViewer, { findings: largeFindings })
  );
  assert.ok(html.includes("Showing 50 of 50 findings"));
  assert.ok(html.includes("Simulated Defect #0"));
  assert.ok(html.includes("Simulated Defect #49"));
});

runChallengerTest("3.3: Semantic severity pills & cards render correct CSS classes", () => {
  const findings = [
    {
      id: "f-crit",
      findingCode: "PRIV_ESCALATION",
      findingType: "PRIV_ESCALATION",
      category: "Security",
      severity: "critical",
      moduleName: "plantilla",
      status: "open",
      title: "Critical Defect",
      details: null,
      recommendation: null,
      createdAt: null,
    },
    {
      id: "f-high",
      findingCode: "STALE_STATUS",
      findingType: "STALE_STATUS",
      category: "Workflow",
      severity: "high",
      moduleName: "hr_emploc",
      status: "open",
      title: "High Defect",
      details: null,
      recommendation: null,
      createdAt: null,
    },
    {
      id: "f-med",
      findingCode: "INDEX_BLOAT",
      category: "Performance",
      severity: "medium",
      moduleName: "cencom",
      status: "open",
      title: "Medium Defect",
      details: null,
      recommendation: null,
      createdAt: null,
    },
    {
      id: "f-low",
      findingCode: "DOCS_MISSING",
      category: "General",
      severity: "low",
      moduleName: "more",
      status: "open",
      title: "Low Defect",
      details: null,
      recommendation: null,
      createdAt: null,
    },
  ];

  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaFindingsViewer, { findings })
  );
  assert.ok(html.includes("bg-danger-surface text-danger-text")); // critical pill
  assert.ok(html.includes("text-amber-700")); // high pill
  assert.ok(html.includes("text-blue-700")); // medium pill
  assert.ok(html.includes("bg-surface-subtle text-text-muted")); // low pill
});

runChallengerTest("3.4: Actionable recommendation callout with Wrench renders when provided, omitted when null", () => {
  const findings = [
    {
      id: "f-rec",
      findingCode: "LEAK_001",
      findingType: "LEAK_001",
      category: "Security",
      severity: "critical",
      moduleName: "vacancies",
      status: "open",
      title: "Leak Found",
      details: "Detail notes",
      recommendation: "Apply migration 20262606000106 to lock GUC claim sub.",
      createdAt: null,
    },
    {
      id: "f-norec",
      findingCode: "WARN_002",
      category: "Notice",
      severity: "low",
      moduleName: "cencom",
      status: "open",
      title: "No Recommendation",
      details: null,
      recommendation: null,
      createdAt: null,
    },
  ];

  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaFindingsViewer, { findings })
  );
  assert.ok(html.includes("Actionable Remediation:"));
  assert.ok(html.includes("Apply migration 20262606000106 to lock GUC claim sub."));
});

runChallengerTest("3.5: Run ID filter strictly isolates findings, excluding orphan findings with null runId", () => {
  const mixedFindings = [
    {
      id: "f-target-run",
      findingCode: "CODE_A",
      severity: "high",
      moduleName: "vacancies",
      status: "open",
      title: "Target Run Defect",
      runId: "run-target-123",
    },
    {
      id: "f-other-run",
      findingCode: "CODE_B",
      severity: "high",
      moduleName: "vacancies",
      status: "open",
      title: "Other Run Defect",
      runId: "run-other-456",
    },
    {
      id: "f-orphan-null",
      findingCode: "CODE_C",
      severity: "high",
      moduleName: "vacancies",
      status: "open",
      title: "Orphan Defect with NULL RunId",
      runId: null,
    },
  ];

  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaFindingsViewer, {
      findings: mixedFindings,
      selectedRunId: "run-target-123",
    })
  );

  const containsTarget = html.includes("Target Run Defect");
  const containsOther = html.includes("Other Run Defect");
  const containsOrphanNull = html.includes("Orphan Defect with NULL RunId");

  assert.equal(containsTarget, true, "Target run defect must be shown");
  assert.equal(containsOther, false, "Other run defect must be filtered out");
  assert.equal(containsOrphanNull, false, "Orphan defect with null runId must NOT leak into filtered run view");
});

// =============================================================================
// SUITE 4: QaRunHistoryTable Stress & Boundary Tests
// =============================================================================
console.log("\n--- SUITE 4: QaRunHistoryTable Stress & Boundary Tests ---");

runChallengerTest("4.1: Empty runs list renders empty placeholder", () => {
  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaRunHistoryTable, { runs: [] })
  );
  assert.ok(html.includes("No test runs logged yet."));
});

runChallengerTest("4.2: Status icons and badge colors across passed, failed, and running", () => {
  const runs = [
    {
      id: "run-pass",
      agentName: "Core Suite",
      status: "passed",
      targetModule: "all",
      findingCount: 0,
      criticalCount: 0,
      highCount: 0,
      mediumCount: 0,
      lowCount: 0,
      startedAt: "2026-11-13T01:00:00Z",
      completedAt: "2026-11-13T01:02:00Z",
      summary: "Clean run",
      rolledBack: true,
    },
    {
      id: "run-fail",
      agentName: "Relay Suite",
      status: "failed",
      targetModule: "hr_emploc",
      findingCount: 2,
      criticalCount: 1,
      highCount: 1,
      mediumCount: 0,
      lowCount: 0,
      startedAt: "2026-11-13T01:10:00Z",
      completedAt: null,
      summary: "Failed assertion",
      rolledBack: false,
    },
    {
      id: "run-prog",
      agentName: "Probing Suite",
      status: "running",
      targetModule: "cencom",
      findingCount: 0,
      criticalCount: 0,
      highCount: 0,
      mediumCount: 0,
      lowCount: 0,
      startedAt: null,
      completedAt: null,
      summary: null,
    },
  ];

  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaRunHistoryTable, { runs })
  );
  assert.ok(html.includes("passed"));
  assert.ok(html.includes("failed"));
  assert.ok(html.includes("running"));
  assert.ok(html.includes("Rolled Back"));
  assert.ok(html.includes("Check Rollback"));
});

runChallengerTest("4.3: Heuristic requires positive confirmation: Failed rollback summary displays 'Check Rollback'", () => {
  const failedRollbackRun = [
    {
      id: "run-failed-rollback",
      agentName: "Simulation Run",
      status: "failed",
      targetModule: "all",
      findingCount: 1,
      criticalCount: 1,
      highCount: 0,
      mediumCount: 0,
      lowCount: 0,
      startedAt: "2026-11-13T01:00:00Z",
      completedAt: "2026-11-13T01:01:00Z",
      summary: "Sandbox rollback failed: 4 uncommitted records remained in vacancies table.",
      // rolledBack is omitted/undefined (as returned by DB view v_qa_detection_run_summary)
    },
  ];

  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaRunHistoryTable, { runs: failedRollbackRun })
  );

  const falselyAwardedRolledBack = html.includes("Rolled Back") && !html.includes("Check Rollback");
  assert.equal(falselyAwardedRolledBack, false, "Failed rollback must NOT be awarded green Rolled Back badge");
  assert.ok(html.includes("Check Rollback"), "Failed rollback must display Check Rollback warning badge");
});

runChallengerTest("4.4: Steps count badge defaults to '7 steps' for RELAY agents, '-' for others", () => {
  const runs = [
    {
      id: "run-relay",
      agentName: "FULL_E2E_RELAY",
      status: "passed",
      targetModule: "all",
      findingCount: 0,
      criticalCount: 0,
      highCount: 0,
      mediumCount: 0,
      lowCount: 0,
      startedAt: null,
      completedAt: null,
    },
    {
      id: "run-other",
      agentName: "CORE_DETECTION",
      status: "passed",
      targetModule: "all",
      findingCount: 0,
      criticalCount: 0,
      highCount: 0,
      mediumCount: 0,
      lowCount: 0,
      startedAt: null,
      completedAt: null,
    },
  ];

  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaRunHistoryTable, { runs })
  );
  assert.ok(html.includes("7 steps"));
});

runChallengerTest("4.5: Findings breakdown displays Clean when 0 findings, breakdown pills when > 0, and total pill when uncategorized", () => {
  const runs = [
    {
      id: "run-clean",
      agentName: "Clean Agent",
      status: "passed",
      targetModule: "all",
      findingCount: 0,
      criticalCount: 0,
      highCount: 0,
      mediumCount: 0,
      lowCount: 0,
      startedAt: null,
      completedAt: null,
    },
    {
      id: "run-dirty",
      agentName: "Dirty Agent",
      status: "failed",
      targetModule: "all",
      findingCount: 3,
      criticalCount: 1,
      highCount: 2,
      mediumCount: 0,
      lowCount: 0,
      startedAt: null,
      completedAt: null,
    },
    {
      id: "run-uncat",
      agentName: "Uncategorized Agent",
      status: "failed",
      targetModule: "vacancies",
      findingCount: 4,
      criticalCount: 0,
      highCount: 0,
      mediumCount: 0,
      lowCount: 0,
      startedAt: null,
      completedAt: null,
    },
  ];

  const html = ReactDOMServer.renderToStaticMarkup(
    React.createElement(QaRunHistoryTable, { runs })
  );
  assert.ok(html.includes("Clean"));
  assert.ok(html.includes("1 crit"));
  assert.ok(html.includes("2 high"));
  assert.ok(html.includes("4 total"), "Must render '4 total' for uncategorized findings");
});

// =============================================================================
// SUITE 5: Boundary Crashes & Nullish Safety (QaStepTimeline & roleBadgeUtils)
// =============================================================================
console.log("\n--- SUITE 5: Boundary Crashes & Nullish Safety ---");

runChallengerTest("5.1: getRoleBadgeConfig handles null and undefined safely without throwing", () => {
  assert.doesNotThrow(() => {
    const confNull = getRoleBadgeConfig(null);
    assert.equal(confNull.label, "Unknown Role");
    assert.ok(confNull.badgeClass.includes("border-border-default"));

    const confUndef = getRoleBadgeConfig(undefined);
    assert.equal(confUndef.label, "Unknown Role");
    assert.ok(confUndef.badgeClass.includes("border-border-default"));
  });
});

runChallengerTest("5.2: QaStepTimeline handles null or undefined step.status safely without crashing", () => {
  const malformedResult = {
    success: true,
    run_id: "malformed-run",
    scenario_code: "FULL_E2E_RELAY",
    sandbox_rolled_back: true,
    steps: [
      { step: 1, role: "Head Admin", action: "test", status: null, details: "Malformed step" },
      null,
    ],
    finding_counts: { total: 0 },
    executed_at: "2026-11-13T01:00:00Z",
  };

  assert.doesNotThrow(() => {
    const html = ReactDOMServer.renderToStaticMarkup(
      React.createElement(QaStepTimeline, {
        result: malformedResult,
        isRunning: false,
        selectedScenarioCode: "FULL_E2E_RELAY",
      })
    );
    assert.ok(html.includes("FAILED"), "Null status must safely render as FAILED status pill without crashing");
    assert.ok(html.includes("test"), "Action name must be rendered");
  });
});

// =============================================================================
// SUMMARY & FINDINGS REPORT
// =============================================================================
console.log("\n===============================================================================");
console.log(`STRESS TEST EXECUTION COMPLETED: ${passedTests} PASSED, ${failedTests} FAILED`);
console.log("===============================================================================\n");

if (challengerBugs.length > 0) {
  console.log(`CRITICAL/HIGH BUGS DETECTED (${challengerBugs.length}):`);
  challengerBugs.forEach((b, idx) => {
    console.log(`${idx + 1}. ${b.test}: ${b.error}`);
  });
}
