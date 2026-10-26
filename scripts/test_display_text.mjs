// scripts/test_display_text.mjs
import { formatDisplayText, ACRONYM_ALLOWLIST } from "../src/lib/utils/displayText.ts";

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

if (passed !== testCases.length) {
  process.exit(1);
}
