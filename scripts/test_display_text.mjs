// scripts/test_display_text.mjs
import { formatDisplayText, formatAccountName, ACRONYM_ALLOWLIST } from "../src/lib/utils/displayText.ts";

const testCases = [
  { input: "SANTOS, JUAN DELA CRUZ", expected: "Santos, Juan Dela Cruz" },
  { input: "PEÑA, MARY JOY F. DELA", expected: "Peña, Mary Joy F. Dela" },
  { input: "DE LA CRUZ, MARIA", expected: "De La Cruz, Maria" },
  { input: "MC DONALD", expected: "Mc Donald" },
  { input: "SM AURORA", expected: "SM Aurora" },
  { input: "VCAG5_0056", expected: "VCAG5_0056" },
  { input: "HRG3", expected: "HRG3" },
  { input: "YES / MARCO/ DERMIS / 3...", expected: "Yes / Marco/ Dermis / 3..." },
  { input: "BEAUTY ADVISOR", expected: "Beauty Advisor" },
  { input: "Moses HQ", expected: "Moses HQ" },
  { input: "O'BRIEN, LIAM", expected: "O'Brien, Liam" },
  { input: "DELA-CRUZ, JANE", expected: "Dela-Cruz, Jane" },
  { input: "HRCO CENTRAL", expected: "HRCO Central" },
  { input: "MFR SUMMARY", expected: "MFR Summary" },
  { input: "SLA COMPLIANT", expected: "SLA Compliant" },
];

console.log("==========================================================================");
console.log("DISPLAY TEXT FORMATTER VERIFICATION SUITE");
console.log("==========================================================================");
console.log("Allowlist:", Array.from(ACRONYM_ALLOWLIST).sort().join(", "));
console.log("--------------------------------------------------------------------------");
console.log(String("INPUT").padEnd(35) + " | " + String("OUTPUT").padEnd(30) + " | STATUS");
console.log("--------------------------------------------------------------------------");

let passed = 0;
for (const tc of testCases) {
  const actual = formatDisplayText(tc.input);
  const ok = actual === tc.expected;
  if (ok) passed++;
  console.log(`${tc.input.padEnd(35)} | ${actual.padEnd(30)} | ${ok ? "PASS" : "FAIL (expected: " + tc.expected + ")"}`);
}

console.log("--------------------------------------------------------------------------");
console.log(`Results: ${passed} / ${testCases.length} tests passed.`);

console.log("\n==========================================================================");
console.log("ACCOUNT NAME CAPSLOCK FORMATTER VERIFICATION SUITE");
console.log("==========================================================================");
const accountTestCases = [
  { input: "Moses HQ", expected: "MOSES HQ" },
  { input: "Actiserve", expected: "ACTISERVE" },
  { input: "actiserve", expected: "ACTISERVE" },
  { input: "Forever Office", expected: "FOREVER OFFICE" },
  { input: "Banko", expected: "BANKO" },
  { input: "Activestyle", expected: "ACTIVESTYLE" },
  { input: "Alturas", expected: "ALTURAS" },
  { input: "All Day G5", expected: "ALL DAY G5" },
  { input: "Apex", expected: "APEX" },
  { input: "Athome Lifestyle", expected: "ATHOME LIFESTYLE" },
  { input: "Backyard", expected: "BACKYARD" },
  { input: "Bancon", expected: "BANCON" },
  { input: "Barrelman", expected: "BARRELMAN" },
  { input: "Bounty", expected: "BOUNTY" },
  { input: "Citrus", expected: "CITRUS" },
  { input: "Condi Davao", expected: "CONDI DAVAO" },
  { input: "Cotton Mountain", expected: "COTTON MOUNTAIN" },
  { input: "Cri", expected: "CRI" },
  { input: "Delta Plantilla", expected: "DELTA PLANTILLA" },
  { input: null, expected: "" },
  { input: undefined, expected: "" },
];

let acctPassed = 0;
for (const tc of accountTestCases) {
  const actual = formatAccountName(tc.input);
  const ok = actual === tc.expected;
  if (ok) acctPassed++;
  console.log(`${String(tc.input).padEnd(35)} | ${actual.padEnd(30)} | ${ok ? "PASS" : "FAIL (expected: " + tc.expected + ")"}`);
}

console.log("--------------------------------------------------------------------------");
console.log(`Account Results: ${acctPassed} / ${accountTestCases.length} tests passed.`);

if (passed !== testCases.length || acctPassed !== accountTestCases.length) {
  process.exit(1);
}
