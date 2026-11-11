import test from "node:test";
import assert from "node:assert/strict";

import {
  collapseAndUppercase,
  canonicalizeMobileNumber,
  normalizeDateToIso,
  normalizePlantillaRow,
  normalizePlantillaRows,
} from "../plantilla_normalization.ts";

import {
  expandScheduleDays,
  resolveDutyAndRestDays,
} from "../schedule_normalizer.ts";

// ============================================================================
// Feature 1: String Pre-Validation Normalization (R1)
// ============================================================================

test("F1 Tier 1.1: collapseAndUppercase trims leading and trailing whitespace", () => {
  assert.equal(collapseAndUppercase("  DELA CRUZ  "), "DELA CRUZ");
  assert.equal(collapseAndUppercase("   JUAN   "), "JUAN");
  assert.equal(collapseAndUppercase("\tSANTOS\t"), "SANTOS");
  assert.equal(collapseAndUppercase("\nMERCHANDISER\n"), "MERCHANDISER");
  assert.equal(collapseAndUppercase("  SINGLE  "), "SINGLE");
});

test("F1 Tier 1.2: collapseAndUppercase collapses consecutive internal spaces, tabs, and newlines to a single space", () => {
  assert.equal(collapseAndUppercase("DELA    CRUZ"), "DELA CRUZ");
  assert.equal(collapseAndUppercase("JUAN   CARLOS   MIGUEL"), "JUAN CARLOS MIGUEL");
  assert.equal(collapseAndUppercase("123\t\tMACARTHUR\t\tHWY"), "123 MACARTHUR HWY");
  assert.equal(collapseAndUppercase("BLOCK 4\n\nLOT 12\n\nPHASE 1"), "BLOCK 4 LOT 12 PHASE 1");
  assert.equal(collapseAndUppercase("SENIOR   OPERATIONS   COORDINATOR"), "SENIOR OPERATIONS COORDINATOR");
});

test("F1 Tier 1.3: collapseAndUppercase converts lowercase and mixed-case to uppercase", () => {
  assert.equal(collapseAndUppercase("dela cruz"), "DELA CRUZ");
  assert.equal(collapseAndUppercase("Juan"), "JUAN");
  assert.equal(collapseAndUppercase("santos"), "SANTOS");
  assert.equal(collapseAndUppercase("merchandiser"), "MERCHANDISER");
  assert.equal(collapseAndUppercase("single"), "SINGLE");
  assert.equal(collapseAndUppercase("san fernando, pampanga"), "SAN FERNANDO, PAMPANGA");
});

test("F1 Tier 1.4: collapseAndUppercase handles combined leading/trailing trim, internal collapse, and uppercase in full names", () => {
  assert.equal(
    collapseAndUppercase("   maria   elena   de   los   reyes   "),
    "MARIA ELENA DE LOS REYES"
  );
  assert.equal(
    collapseAndUppercase("\t  jose   rizal   mercado   y   alonso  \t"),
    "JOSE RIZAL MERCADO Y ALONSO"
  );
});

test("F1 Tier 1.5: collapseAndUppercase converts non-string inputs (numbers, booleans) safely to string", () => {
  assert.equal(collapseAndUppercase(12345), "12345");
  assert.equal(collapseAndUppercase(610.5), "610.5");
  assert.equal(collapseAndUppercase(true), "TRUE");
  assert.equal(collapseAndUppercase(false), "FALSE");
});

test("F1 Tier 2.1 (Boundary): collapseAndUppercase returns empty string for empty string input", () => {
  assert.equal(collapseAndUppercase(""), "");
});

test("F1 Tier 2.2 (Boundary): collapseAndUppercase returns empty string for whitespace-only input", () => {
  assert.equal(collapseAndUppercase(" "), "");
  assert.equal(collapseAndUppercase("     "), "");
  assert.equal(collapseAndUppercase("\t\t\n  \r\n  \t"), "");
});

test("F1 Tier 2.3 (Boundary): collapseAndUppercase returns empty string for null and undefined", () => {
  assert.equal(collapseAndUppercase(null), "");
  assert.equal(collapseAndUppercase(undefined), "");
});

test("F1 Tier 2.4 (Boundary): collapseAndUppercase handles single character and single-letter initials", () => {
  assert.equal(collapseAndUppercase(" a "), "A");
  assert.equal(collapseAndUppercase("s."), "S.");
  assert.equal(collapseAndUppercase("  M.  "), "M.");
  assert.equal(collapseAndUppercase("Z"), "Z");
});

test("F1 Tier 2.5 (Boundary): collapseAndUppercase preserves special characters, punctuation, and accented letters (Ñ, Ç)", () => {
  assert.equal(collapseAndUppercase("  peña,  jr.  "), "PEÑA, JR.");
  assert.equal(collapseAndUppercase("sto. niño st."), "STO. NIÑO ST.");
  assert.equal(collapseAndUppercase("o'connor"), "O'CONNOR");
  assert.equal(collapseAndUppercase("curaçao ave."), "CURAÇAO AVE.");
});

test("F1 Tier 2.6 (Boundary): collapseAndUppercase collapses non-breaking spaces into standard single space", () => {
  // \u00A0 is non-breaking space (often found in copied Excel cells)
  assert.equal(collapseAndUppercase("DELA\u00A0\u00A0CRUZ"), "DELA CRUZ");
  assert.equal(collapseAndUppercase("\u00A0\u00A0JUAN\u00A0SANTOS\u00A0\u00A0"), "JUAN SANTOS");
});

// ============================================================================
// Feature 2: Contact Number Normalization (R1)
// ============================================================================

test("F2 Tier 1.1: canonicalizeMobileNumber strips whitespace, hyphens, parentheses, and dots", () => {
  assert.equal(canonicalizeMobileNumber("0917-123-4567"), "09171234567");
  assert.equal(canonicalizeMobileNumber("(0917) 123 4567"), "09171234567");
  assert.equal(canonicalizeMobileNumber("0917.123.4567"), "09171234567");
  assert.equal(canonicalizeMobileNumber("0917 123 4567"), "09171234567");
});

test("F2 Tier 1.2: canonicalizeMobileNumber converts +639xxxxxxxxx prefix to canonical 11-digit 09xxxxxxxxx", () => {
  assert.equal(canonicalizeMobileNumber("+639171234567"), "09171234567");
  assert.equal(canonicalizeMobileNumber("+63 918 234 5678"), "09182345678");
  assert.equal(canonicalizeMobileNumber("+63 (919) 345-6789"), "09193456789");
  assert.equal(canonicalizeMobileNumber("+63-920-456-7890"), "09204567890");
});

test("F2 Tier 1.3: canonicalizeMobileNumber converts 639xxxxxxxxx prefix to canonical 11-digit 09xxxxxxxxx", () => {
  assert.equal(canonicalizeMobileNumber("639171234567"), "09171234567");
  assert.equal(canonicalizeMobileNumber("63 918 234 5678"), "09182345678");
  assert.equal(canonicalizeMobileNumber("63-922-345-6789"), "09223456789");
  assert.equal(canonicalizeMobileNumber("63(925)4567890"), "09254567890");
});

test("F2 Tier 1.4: canonicalizeMobileNumber converts 10-digit 9xxxxxxxxx to canonical 11-digit 09xxxxxxxxx", () => {
  assert.equal(canonicalizeMobileNumber("9171234567"), "09171234567");
  assert.equal(canonicalizeMobileNumber("918-234-5678"), "09182345678");
  assert.equal(canonicalizeMobileNumber("920 345 6789"), "09203456789");
  assert.equal(canonicalizeMobileNumber("(922) 456-7890"), "09224567890");
});

test("F2 Tier 1.5: canonicalizeMobileNumber preserves already canonical 11-digit 09xxxxxxxxx intact", () => {
  assert.equal(canonicalizeMobileNumber("09171234567"), "09171234567");
  assert.equal(canonicalizeMobileNumber("09987654321"), "09987654321");
  assert.equal(canonicalizeMobileNumber("09123456789"), "09123456789");
});

test("F2 Tier 2.1 (Boundary): canonicalizeMobileNumber returns empty string for empty string input", () => {
  assert.equal(canonicalizeMobileNumber(""), "");
});

test("F2 Tier 2.2 (Boundary): canonicalizeMobileNumber returns empty string for whitespace-only input", () => {
  assert.equal(canonicalizeMobileNumber("   "), "");
  assert.equal(canonicalizeMobileNumber("\t\n"), "");
});

test("F2 Tier 2.3 (Boundary): canonicalizeMobileNumber returns empty string for null and undefined", () => {
  assert.equal(canonicalizeMobileNumber(null), "");
  assert.equal(canonicalizeMobileNumber(undefined), "");
});

test("F2 Tier 2.4 (Boundary): canonicalizeMobileNumber handles complex mixed punctuation formatting", () => {
  assert.equal(canonicalizeMobileNumber("+63- (917) .123. 4567"), "09171234567");
  assert.equal(canonicalizeMobileNumber("  +63 917 123 4567  "), "09171234567");
  assert.equal(canonicalizeMobileNumber("0917--123..4567"), "09171234567");
});

test("F2 Tier 2.5 (Boundary): canonicalizeMobileNumber preserves non-mobile / landline digit sequences without crashing", () => {
  // Landline numbers (7-8 digits)
  assert.equal(canonicalizeMobileNumber("8888-1234"), "88881234");
  assert.equal(canonicalizeMobileNumber("(02) 8123 4567"), "0281234567");
  assert.equal(canonicalizeMobileNumber("(045) 982 1234"), "0459821234");
});

// ============================================================================
// Feature 3: Date Normalization to Strict ISO (YYYY-MM-DD) (R1)
// ============================================================================

test("F3 Tier 1.1: normalizeDateToIso preserves valid ISO YYYY-MM-DD strings untouched", () => {
  assert.equal(normalizeDateToIso("2026-01-15"), "2026-01-15");
  assert.equal(normalizeDateToIso("1995-05-15"), "1995-05-15");
  assert.equal(normalizeDateToIso("2000-12-31"), "2000-12-31");
});

test("F3 Tier 1.2: normalizeDateToIso parses standard US/PH MM/DD/YYYY format into YYYY-MM-DD", () => {
  assert.equal(normalizeDateToIso("01/15/2026"), "2026-01-15");
  assert.equal(normalizeDateToIso("05/15/1995"), "1995-05-15");
  assert.equal(normalizeDateToIso("12/31/2000"), "2000-12-31");
});

test("F3 Tier 1.3: normalizeDateToIso parses single-digit M/D/YYYY format with zero padding", () => {
  assert.equal(normalizeDateToIso("1/5/2026"), "2026-01-05");
  assert.equal(normalizeDateToIso("5/9/1995"), "1995-05-09");
  assert.equal(normalizeDateToIso("9/1/2020"), "2020-09-01");
});

test("F3 Tier 1.4: normalizeDateToIso parses text month format (e.g. 15-Jan-2026 or 15 Jan 2026)", () => {
  assert.equal(normalizeDateToIso("15-Jan-2026"), "2026-01-15");
  assert.equal(normalizeDateToIso("15 Jan 2026"), "2026-01-15");
  assert.equal(normalizeDateToIso("01-Dec-1995"), "1995-12-01");
  assert.equal(normalizeDateToIso("20-August-2004"), "2004-08-20");
});

test("F3 Tier 1.5: normalizeDateToIso parses native JavaScript Date instances to strict ISO YYYY-MM-DD", () => {
  const d1 = new Date(Date.UTC(2026, 0, 15));
  assert.equal(normalizeDateToIso(d1), "2026-01-15");

  const d2 = new Date(Date.UTC(1995, 4, 15));
  assert.equal(normalizeDateToIso(d2), "1995-05-15");
});

test("F3 Tier 2.1 (Boundary): normalizeDateToIso returns empty string for empty string, whitespace, null, and undefined", () => {
  assert.equal(normalizeDateToIso(""), "");
  assert.equal(normalizeDateToIso("   "), "");
  assert.equal(normalizeDateToIso(null), "");
  assert.equal(normalizeDateToIso(undefined), "");
});

test("F3 Tier 2.2 (Boundary): normalizeDateToIso correctly normalizes leap year date (2024-02-29)", () => {
  assert.equal(normalizeDateToIso("2024-02-29"), "2024-02-29");
  assert.equal(normalizeDateToIso("02/29/2024"), "2024-02-29");
  assert.equal(normalizeDateToIso("29-Feb-2024"), "2024-02-29");
});

test("F3 Tier 2.3 (Boundary): normalizeDateToIso correctly normalizes end of February in non-leap year (2025-02-28)", () => {
  assert.equal(normalizeDateToIso("2025-02-28"), "2025-02-28");
  assert.equal(normalizeDateToIso("02/28/2025"), "2025-02-28");
  assert.equal(normalizeDateToIso("28-Feb-2025"), "2025-02-28");
});

test("F3 Tier 2.4 (Boundary): normalizeDateToIso converts Excel numeric serial dates (e.g. 46037) to ISO string", () => {
  // In Excel serial counting (with 1899 epoch):
  // 44941 -> 2023-01-15
  assert.equal(normalizeDateToIso(44941), "2023-01-15");
  // Numeric string "44941"
  assert.equal(normalizeDateToIso("44941"), "2023-01-15");
});

test("F3 Tier 2.5 (Boundary): normalizeDateToIso handles ISO string with timestamp (YYYY-MM-DDTHH:mm:ss)", () => {
  assert.equal(normalizeDateToIso("2026-01-15T00:00:00.000Z"), "2026-01-15");
  assert.equal(normalizeDateToIso("2026-01-15 08:30:00"), "2026-01-15");
});

// ============================================================================
// Feature 4: Schedule Day Range Expansion (R4)
// ============================================================================

test("F4 Tier 1.1: expandScheduleDays expands standard linear range MON-SAT into 6 canonical days", () => {
  const result = expandScheduleDays("MON-SAT");
  assert.deepEqual(result.days, ["MON", "TUE", "WED", "THU", "FRI", "SAT"]);
  assert.equal(result.formatted, "MON, TUE, WED, THU, FRI, SAT");
});

test("F4 Tier 1.2: expandScheduleDays expands linear range MON-FRI into 5 canonical days", () => {
  const result = expandScheduleDays("MON-FRI");
  assert.deepEqual(result.days, ["MON", "TUE", "WED", "THU", "FRI"]);
  assert.equal(result.formatted, "MON, TUE, WED, THU, FRI");
});

test("F4 Tier 1.3: expandScheduleDays expands wrap-around range SAT-TUE into canonically ordered MON, TUE, SAT, SUN", () => {
  // SAT, SUN, MON, TUE re-ordered strictly MON to SUN
  const result = expandScheduleDays("SAT-TUE");
  assert.deepEqual(result.days, ["MON", "TUE", "SAT", "SUN"]);
  assert.equal(result.formatted, "MON, TUE, SAT, SUN");
});

test("F4 Tier 1.4: expandScheduleDays expands hybrid lists with ranges and single days (MON-WED, FRI)", () => {
  const result = expandScheduleDays("MON-WED, FRI");
  assert.deepEqual(result.days, ["MON", "TUE", "WED", "FRI"]);
  assert.equal(result.formatted, "MON, TUE, WED, FRI");

  const result2 = expandScheduleDays("MON-WED; SAT-SUN");
  assert.deepEqual(result2.days, ["MON", "TUE", "WED", "SAT", "SUN"]);
  assert.equal(result2.formatted, "MON, TUE, WED, SAT, SUN");
});

test("F4 Tier 1.5: expandScheduleDays throws error rejecting invalid/unrecognized day tokens", () => {
  assert.throws(
    () => expandScheduleDays("MON-XYZ"),
    /Invalid schedule day range/
  );
  assert.throws(
    () => expandScheduleDays("FOOBAR"),
    /Invalid schedule day token/
  );
  assert.throws(
    () => expandScheduleDays("MON, TUE, INVALID"),
    /Invalid schedule day token/
  );
});

test("F4 Tier 2.1 (Boundary): expandScheduleDays expands single day token (e.g. MON) to single-element array", () => {
  const result = expandScheduleDays("MON");
  assert.deepEqual(result.days, ["MON"]);
  assert.equal(result.formatted, "MON");

  const sun = expandScheduleDays("SUN");
  assert.deepEqual(sun.days, ["SUN"]);
  assert.equal(sun.formatted, "SUN");
});

test("F4 Tier 2.2 (Boundary): expandScheduleDays expands full 7-day range MON-SUN into all 7 days in canonical order", () => {
  const result = expandScheduleDays("MON-SUN");
  assert.deepEqual(result.days, ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]);
  assert.equal(result.formatted, "MON, TUE, WED, THU, FRI, SAT, SUN");
});

test("F4 Tier 2.3 (Boundary): expandScheduleDays expands adjacent wrap-around SUN-MON into MON, SUN in canonical order", () => {
  const result = expandScheduleDays("SUN-MON");
  assert.deepEqual(result.days, ["MON", "SUN"]);
  assert.equal(result.formatted, "MON, SUN");
});

test("F4 Tier 2.4 (Boundary): expandScheduleDays returns empty array and empty formatted string for empty or null input", () => {
  assert.deepEqual(expandScheduleDays(""), { days: [], formatted: "" });
  assert.deepEqual(expandScheduleDays("   "), { days: [], formatted: "" });
  assert.deepEqual(expandScheduleDays(null), { days: [], formatted: "" });
  assert.deepEqual(expandScheduleDays(undefined), { days: [], formatted: "" });
});

test("F4 Tier 2.5 (Boundary): expandScheduleDays handles full day names (e.g. MONDAY-FRIDAY, SUNDAY)", () => {
  const result = expandScheduleDays("MONDAY-FRIDAY");
  assert.deepEqual(result.days, ["MON", "TUE", "WED", "THU", "FRI"]);
  assert.equal(result.formatted, "MON, TUE, WED, THU, FRI");

  const result2 = expandScheduleDays("SATURDAY, SUNDAY");
  assert.deepEqual(result2.days, ["SAT", "SUN"]);
  assert.equal(result2.formatted, "SAT, SUN");
});

test("F4 Tier 2.6 (Boundary): expandScheduleDays deduplicates duplicate day tokens in input preserving order", () => {
  const result = expandScheduleDays("MON, TUE, MON, WED, TUE");
  assert.deepEqual(result.days, ["MON", "TUE", "WED"]);
  assert.equal(result.formatted, "MON, TUE, WED");
});

// ============================================================================
// Feature 5: Duty Days vs Rest Day Mutual Exclusivity (R4)
// ============================================================================

test("F5 Tier 1.1: resolveDutyAndRestDays carves out overlapping rest day from duty days", () => {
  // SCHEDULE_DAYS: MON-SAT, DAYOFF: SAT, SUN -> duty days lose SAT
  const result = resolveDutyAndRestDays("MON-SAT", "SAT, SUN");
  assert.equal(result.scheduleDays, "MON, TUE, WED, THU, FRI");
  assert.equal(result.dayoff, "SAT, SUN");
  assert.deepEqual(result.dutyDays, ["MON", "TUE", "WED", "THU", "FRI"]);
  assert.deepEqual(result.restDays, ["SAT", "SUN"]);
  assert.deepEqual(result.conflictRemoved, ["SAT"]);
  assert.equal(result.error, undefined);
});

test("F5 Tier 1.2: resolveDutyAndRestDays preserves duty days intact when duty and rest days do not overlap", () => {
  // SCHEDULE_DAYS: MON-FRI, DAYOFF: SAT, SUN -> no overlap
  const result = resolveDutyAndRestDays("MON-FRI", "SAT, SUN");
  assert.equal(result.scheduleDays, "MON, TUE, WED, THU, FRI");
  assert.equal(result.dayoff, "SAT, SUN");
  assert.deepEqual(result.conflictRemoved, []);
  assert.equal(result.error, undefined);
});

test("F5 Tier 1.3: resolveDutyAndRestDays carves out single rest day from discrete duty days list", () => {
  const result = resolveDutyAndRestDays("MON, WED, FRI", "WED");
  assert.equal(result.scheduleDays, "MON, FRI");
  assert.equal(result.dayoff, "WED");
  assert.deepEqual(result.conflictRemoved, ["WED"]);
  assert.equal(result.error, undefined);
});

test("F5 Tier 1.4: resolveDutyAndRestDays formats both schedule_days and dayoff as plain Postgres text strings", () => {
  const result = resolveDutyAndRestDays("MON-SAT", "SUN");
  assert.equal(typeof result.scheduleDays, "string");
  assert.equal(typeof result.dayoff, "string");
  assert.equal(result.scheduleDays, "MON, TUE, WED, THU, FRI, SAT");
  assert.equal(result.dayoff, "SUN");
});

test("F5 Tier 1.5: resolveDutyAndRestDays resolves wrap-around duty days with rest day carve-out", () => {
  // SCHEDULE_DAYS: SAT-TUE (MON, TUE, SAT, SUN), DAYOFF: SUN
  const result = resolveDutyAndRestDays("SAT-TUE", "SUN");
  assert.equal(result.scheduleDays, "MON, TUE, SAT");
  assert.equal(result.dayoff, "SUN");
  assert.deepEqual(result.conflictRemoved, ["SUN"]);
});

test("F5 Tier 2.1 (Boundary): resolveDutyAndRestDays returns error when duty days are completely swallowed by rest days", () => {
  const result = resolveDutyAndRestDays("SUN", "SUN");
  assert.equal(result.scheduleDays, "");
  assert.equal(result.dayoff, "SUN");
  assert.deepEqual(result.conflictRemoved, ["SUN"]);
  assert.match(result.error ?? "", /Schedule days cannot be entirely comprised of rest days/);
});

test("F5 Tier 2.2 (Boundary): resolveDutyAndRestDays handles multi-day rest day carve-out from full week schedule", () => {
  const result = resolveDutyAndRestDays("MON-SUN", "SAT, SUN");
  assert.equal(result.scheduleDays, "MON, TUE, WED, THU, FRI");
  assert.equal(result.dayoff, "SAT, SUN");
  assert.deepEqual(result.conflictRemoved, ["SAT", "SUN"]);
});

test("F5 Tier 2.3 (Boundary): resolveDutyAndRestDays handles null or empty DAYOFF preserving SCHEDULE_DAYS", () => {
  const result = resolveDutyAndRestDays("MON-SAT", "");
  assert.equal(result.scheduleDays, "MON, TUE, WED, THU, FRI, SAT");
  assert.equal(result.dayoff, "");
  assert.deepEqual(result.conflictRemoved, []);

  const resultNull = resolveDutyAndRestDays("MON-SAT", null);
  assert.equal(resultNull.scheduleDays, "MON, TUE, WED, THU, FRI, SAT");
  assert.equal(resultNull.dayoff, "");
});

test("F5 Tier 2.4 (Boundary): resolveDutyAndRestDays handles null or empty SCHEDULE_DAYS safely without crash", () => {
  const result = resolveDutyAndRestDays("", "SUN");
  assert.equal(result.scheduleDays, "");
  assert.equal(result.dayoff, "SUN");
  assert.deepEqual(result.conflictRemoved, []);

  const resultNull = resolveDutyAndRestDays(null, "SUN");
  assert.equal(resultNull.scheduleDays, "");
  assert.equal(resultNull.dayoff, "SUN");
});

test("F5 Tier 2.5 (Boundary): resolveDutyAndRestDays handles both empty SCHEDULE_DAYS and empty DAYOFF", () => {
  const result = resolveDutyAndRestDays("", "");
  assert.equal(result.scheduleDays, "");
  assert.equal(result.dayoff, "");
  assert.deepEqual(result.conflictRemoved, []);
  assert.equal(result.error, undefined);
});

// ============================================================================
// Tier 3: Cross-Feature Normalization Pipeline Integration
// ============================================================================

test("Tier 3 Cross-Feature 1: normalizePlantillaRow transforms strings, contact numbers, dates, and schedules concurrently", () => {
  const rawRow = {
    GROUP_NAME: "  GROUP   2  ",
    ACCOUNT_NAME: "  SUPER   8  ",
    MOTHER_ACCOUNT: "SUPER 8",
    VCODE: "pg-dau-001",
    STORE_NAME: "  Super  8   Angeles   Dau  ",
    AREA_PROVINCE: "  pampanga  ",
    AREA_CITY: "  angeles  ",
    POSITION: "  merchandiser  ",
    EMPLOYEE_NO: " emp-2026-001 ",
    LAST_NAME: "  dela    cruz  ",
    FIRST_NAME: "  juan   carlos  ",
    MIDDLE_NAME: "  santos  ",
    DATE_HIRED: "01/15/2026",
    DATE_OF_BIRTH: "15-May-1995",
    CIVIL_STATUS: "  single  ",
    CONTACT_NO: "+63 (917) 123-4567",
    ADDRESS: "  123   macarthur   hwy,   angeles  ",
    SCHEDULE_DAYS: "MON-SAT",
    DAYOFF: "SAT, SUN",
    SCHEDULE_TIME: "  08:00 AM - 05:00 PM  ",
    COORDINATOR: "  operations   coordinator  ",
    HRCO_EMAIL: "  HRCO@OHM.PH  ",
    RATE: " 610.00 ",
  };

  const normalized = normalizePlantillaRow(rawRow);

  // Strings
  assert.equal(normalized.LAST_NAME, "DELA CRUZ");
  assert.equal(normalized.FIRST_NAME, "JUAN CARLOS");
  assert.equal(normalized.MIDDLE_NAME, "SANTOS");
  assert.equal(normalized.POSITION, "MERCHANDISER");
  assert.equal(normalized.CIVIL_STATUS, "SINGLE");
  assert.equal(normalized.ADDRESS, "123 MACARTHUR HWY, ANGELES");

  // Identifiers & Meta
  assert.equal(normalized.EMPLOYEE_NO, "EMP-2026-001");
  assert.equal(normalized.VCODE, "PG-DAU-001");
  assert.equal(normalized.GROUP_NAME, "GROUP 2");
  assert.equal(normalized.ACCOUNT_NAME, "SUPER 8");
  assert.equal(normalized.STORE_NAME, "Super 8 Angeles Dau");
  assert.equal(normalized.AREA_PROVINCE, "pampanga");
  assert.equal(normalized.AREA_CITY, "angeles");
  assert.equal(normalized.COORDINATOR, "operations coordinator");
  assert.equal(normalized.HRCO_EMAIL, "hrco@ohm.ph");
  assert.equal(normalized.RATE, "610.00");
  assert.equal(normalized.SCHEDULE_TIME, "08:00 AM - 05:00 PM");

  // Contact number
  assert.equal(normalized.CONTACT_NO, "09171234567");

  // Dates
  assert.equal(normalized.DATE_HIRED, "2026-01-15");
  assert.equal(normalized.DATE_OF_BIRTH, "1995-05-15");

  // Schedule duty vs rest day carve-out
  assert.equal(normalized.SCHEDULE_DAYS, "MON, TUE, WED, THU, FRI");
  assert.equal(normalized.DAYOFF, "SAT, SUN");
});

test("Tier 3 Cross-Feature 2: normalizePlantillaRows transforms an array of rows while preserving unaffected slot metadata", () => {
  const rows = [
    {
      VCODE: "v-001",
      STORE_NAME: "Store One",
      POSITION: "cashier",
      EMPLOYEE_NO: "emp-1",
      LAST_NAME: "santos",
      FIRST_NAME: "maria",
      MIDDLE_NAME: "cruz",
      DATE_HIRED: "2026-01-01",
      CONTACT_NO: "0917-000-0001",
    },
    {
      VCODE: "v-002",
      STORE_NAME: "Store Two",
      POSITION: "cashier",
      EMPLOYEE_NO: "", // vacant slot
      LAST_NAME: "",
      FIRST_NAME: "",
      MIDDLE_NAME: "",
      DATE_HIRED: "",
      CONTACT_NO: "",
    },
  ];

  const result = normalizePlantillaRows(rows);
  assert.equal(result.length, 2);

  // Row 1 assigned
  assert.equal(result[0].POSITION, "CASHIER");
  assert.equal(result[0].LAST_NAME, "SANTOS");
  assert.equal(result[0].FIRST_NAME, "MARIA");
  assert.equal(result[0].CONTACT_NO, "09170000001");

  // Row 2 vacant slot
  assert.equal(result[1].VCODE, "V-002");
  assert.equal(result[1].POSITION, "CASHIER");
  assert.equal(result[1].EMPLOYEE_NO, "");
  assert.equal(result[1].LAST_NAME, "");
});

test("Tier 3 Cross-Feature 3: normalizePlantillaRow is strictly idempotent across consecutive passes", () => {
  const rawRow = {
    VCODE: "PG-DAU-001",
    STORE_NAME: "Super 8 Angeles Dau",
    POSITION: "merchandiser",
    EMPLOYEE_NO: "emp-2026-001",
    LAST_NAME: "dela cruz",
    FIRST_NAME: "juan",
    MIDDLE_NAME: "santos",
    DATE_HIRED: "01/15/2026",
    DATE_OF_BIRTH: "1995-05-15",
    CONTACT_NO: "+639171234567",
    SCHEDULE_DAYS: "MON-SAT",
    DAYOFF: "SUN",
  };

  const pass1 = normalizePlantillaRow(rawRow);
  const pass2 = normalizePlantillaRow(pass1);

  assert.deepEqual(pass1, pass2);
});

test("Tier 3 Cross-Feature 4: pre-validation normalization canonicalizes heterogeneous contact numbers and names to prevent false intra-batch conflicts", () => {
  // Sibling roving rows entered with different text representations of same identity
  const rowA = {
    EMPLOYEE_NO: "emp-101",
    LAST_NAME: "DELA CRUZ",
    FIRST_NAME: "JUAN",
    MIDDLE_NAME: "SANTOS",
    CONTACT_NO: "+63 917 111 2233",
    DATE_HIRED: "2026-01-15",
  };

  const rowB = {
    EMPLOYEE_NO: "  EMP-101  ",
    LAST_NAME: "dela   cruz",
    FIRST_NAME: "juan",
    MIDDLE_NAME: "santos",
    CONTACT_NO: "0917-111-2233",
    DATE_HIRED: "01/15/2026",
  };

  const normA = normalizePlantillaRow(rowA);
  const normB = normalizePlantillaRow(rowB);

  // Both should evaluate to exact identical strings for core identity and contact
  assert.equal(normA.EMPLOYEE_NO, normB.EMPLOYEE_NO);
  assert.equal(normA.LAST_NAME, normB.LAST_NAME);
  assert.equal(normA.FIRST_NAME, normB.FIRST_NAME);
  assert.equal(normA.MIDDLE_NAME, normB.MIDDLE_NAME);
  assert.equal(normA.DATE_HIRED, normB.DATE_HIRED);
  assert.equal(normA.CONTACT_NO, normB.CONTACT_NO);
});
