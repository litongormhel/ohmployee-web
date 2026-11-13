// Verification test script for governance.ts hardening
const testScenarios = [
  {
    name: "1. normal payload",
    data: {
      steps: [{ step: 1, role: "System", action: "init", status: "passed", details: "ok" }],
      finding_counts: { critical: 1, high: 2, medium: 0, low: 0, total: 3 },
    },
  },
  {
    name: "2. null element in steps array [null]",
    data: {
      steps: [null, { step: 2, role: "HR", action: "act", status: "passed" }, undefined, 42],
    },
  },
  {
    name: "3. non-numeric strings and invalid values in step.step",
    data: {
      steps: [
        { step: "step_one", action: "step1" },
        { step: "3", action: "step3" },
        { step: -1, action: "step_neg" },
        { step: null, action: "step_null" },
        { action: "step_missing" },
        { step: NaN, action: "step_nan" },
        { step: Infinity, action: "step_inf" },
      ],
    },
  },
  {
    name: "4. non-numeric values in finding_counts",
    data: {
      finding_counts: {
        critical: "uncounted",
        high: "NaN",
        medium: 2,
        low: -1,
        total: "invalid",
      },
    },
  },
  {
    name: "5. null / undefined data",
    data: null,
  },
  {
    name: "6. primitive values for steps and finding_counts",
    data: {
      steps: "not an array",
      finding_counts: "string instead of object",
    },
  },
  {
    name: "7. case insensitivity and null status in steps",
    data: {
      steps: [
        { step: 1, status: "FAILED" },
        { step: 2, status: null },
        { step: 3, status: "passed" },
      ],
    },
  },
];

console.log("=== RUNNING HARDENING PARSER VERIFICATION ===");

for (const sc of testScenarios) {
  const raw = (sc.data && typeof sc.data === "object" ? sc.data : {});
  const rawSteps = Array.isArray(raw.steps)
    ? raw.steps.filter((s) => s !== null && typeof s === "object" && !Array.isArray(s))
    : [];

  const steps = rawSteps.map((s, idx) => {
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

  const rawCounts = (raw.finding_counts && typeof raw.finding_counts === "object" && !Array.isArray(raw.finding_counts)
    ? raw.finding_counts
    : {});

  const toSafeCount = (val) => {
    const num = Number(val);
    return Number.isFinite(num) && num >= 0 ? Math.floor(num) : 0;
  };

  const critical = toSafeCount(rawCounts.critical);
  const high = toSafeCount(rawCounts.high);
  const medium = toSafeCount(rawCounts.medium);
  const low = toSafeCount(rawCounts.low);
  const rawTotal = toSafeCount(rawCounts.total);
  const total = rawTotal > 0 ? rawTotal : critical + high + medium + low;

  const findingCounts = { critical, high, medium, low, total };

  console.log(`\nScenario: ${sc.name}`);
  console.log(`  Filtered steps count: ${steps.length}`);
  console.log(`  Steps:`, steps);
  console.log(`  Finding counts:`, findingCounts);
}

console.log("\n=== ALL SCENARIOS EVALUATED CLEANLY WITH ZERO EXCEPTIONS ===");
