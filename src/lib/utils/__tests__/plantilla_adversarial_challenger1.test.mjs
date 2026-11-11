import test from "node:test";
import assert from "node:assert/strict";

import {
  collapseAndUppercase,
  canonicalizeMobileNumber,
  normalizeDateToIso,
  computeAgeAtHire,
  normalizePlantillaRow,
  coalescePlantillaBatch,
} from "../plantilla_normalization.ts";

import {
  expandScheduleDays,
  resolveDutyAndRestDays,
} from "../schedule_normalizer.ts";

// ============================================================================
// SUITE 1: SCHEDULE RANGE EXPANSION ADVERSARIAL STRESS TESTS
// ============================================================================

test("ADV-SCHED-01: Wrap-around ranges (SUN-THU, FRI-MON, SAT-WED, TUE-MON)", () => {
  // SUN-THU: SUN, MON, TUE, WED, THU -> strictly ordered MON, TUE, WED, THU, SUN
  const sunThu = expandScheduleDays("SUN-THU");
  assert.deepEqual(sunThu.days, ["MON", "TUE", "WED", "THU", "SUN"]);
  assert.equal(sunThu.formatted, "MON, TUE, WED, THU, SUN");

  // FRI-MON: FRI, SAT, SUN, MON -> strictly ordered MON, FRI, SAT, SUN
  const friMon = expandScheduleDays("FRI-MON");
  assert.deepEqual(friMon.days, ["MON", "FRI", "SAT", "SUN"]);
  assert.equal(friMon.formatted, "MON, FRI, SAT, SUN");

  // SAT-WED: SAT, SUN, MON, TUE, WED -> strictly ordered MON, TUE, WED, SAT, SUN
  const satWed = expandScheduleDays("SAT-WED");
  assert.deepEqual(satWed.days, ["MON", "TUE", "WED", "SAT", "SUN"]);
  assert.equal(satWed.formatted, "MON, TUE, WED, SAT, SUN");

  // TUE-MON: Full week wrap-around from Tuesday to Monday
  const tueMon = expandScheduleDays("TUE-MON");
  assert.deepEqual(tueMon.days, ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]);
  assert.equal(tueMon.formatted, "MON, TUE, WED, THU, FRI, SAT, SUN");
});

test("ADV-SCHED-02: Single-day wrap boundaries and same-day ranges", () => {
  // SUN-MON boundary
  const sunMon = expandScheduleDays("SUN-MON");
  assert.deepEqual(sunMon.days, ["MON", "SUN"]);

  // Same day ranges: MON-MON, SUN-SUN, WED-WED
  const monMon = expandScheduleDays("MON-MON");
  assert.deepEqual(monMon.days, ["MON"]);

  const sunSun = expandScheduleDays("SUN-SUN");
  assert.deepEqual(sunSun.days, ["SUN"]);

  const wedWed = expandScheduleDays("WED-WED");
  assert.deepEqual(wedWed.days, ["WED"]);
});

test("ADV-SCHED-03: Complex hybrid lists and heterogeneous separators", () => {
  // TUE-THU, SAT-SUN
  const res1 = expandScheduleDays("TUE-THU, SAT-SUN");
  assert.deepEqual(res1.days, ["TUE", "WED", "THU", "SAT", "SUN"]);

  // Mixed semicolons, slashes, ampersands
  const res2 = expandScheduleDays("MON-WED; FRI/SAT & SUN");
  assert.deepEqual(res2.days, ["MON", "TUE", "WED", "FRI", "SAT", "SUN"]);

  // Irregular spacing with empty tokens
  const res3 = expandScheduleDays("  MON - WED  ,  ,  FRI ,  SAT - SUN  ");
  assert.deepEqual(res3.days, ["MON", "TUE", "WED", "FRI", "SAT", "SUN"]);
});

test("ADV-SCHED-04: Unicode whitespace and case variations in schedule days", () => {
  // Non-breaking spaces (\u00A0) around hyphens
  const nbsp = expandScheduleDays("MON\u00A0-\u00A0FRI");
  assert.deepEqual(nbsp.days, ["MON", "TUE", "WED", "THU", "FRI"]);

  // Multi-tabs and newlines
  const tabNewline = expandScheduleDays("MON\t-\tWED\n,\nSAT");
  assert.deepEqual(tabNewline.days, ["MON", "TUE", "WED", "SAT"]);

  // Lowercase / mixed case
  const mixed = expandScheduleDays("mon-wed, Fri, sAtUrDaY");
  assert.deepEqual(mixed.days, ["MON", "TUE", "WED", "FRI", "SAT"]);
});

test("ADV-SCHED-05: Unrecognized day tokens and malformed range syntax", () => {
  // Unrecognized tokens throw
  assert.throws(() => expandScheduleDays("FOO"), /Invalid schedule day token: "FOO"/);
  assert.throws(() => expandScheduleDays("MON-XYZ"), /Invalid schedule day range: "MON-XYZ"/);
  assert.throws(() => expandScheduleDays("XYZ-MON"), /Invalid schedule day range: "XYZ-MON"/);

  // Missing or excessive hyphens
  assert.throws(() => expandScheduleDays("MON--FRI"), /Invalid schedule day token/);
  assert.throws(() => expandScheduleDays("MON-WED-FRI"), /Invalid schedule day token/);
  assert.throws(() => expandScheduleDays("MON-"), /Invalid schedule day token/);
  assert.throws(() => expandScheduleDays("-FRI"), /Invalid schedule day token/);

  // Common shorthand "WEDS" is not recognized
  assert.throws(() => expandScheduleDays("WEDS"), /Invalid schedule day token: "WEDS"/);
});

test("ADV-SCHED-06: Non-string and boundary inputs to expandScheduleDays", () => {
  assert.deepEqual(expandScheduleDays(""), { days: [], formatted: "" });
  assert.deepEqual(expandScheduleDays("   "), { days: [], formatted: "" });
  assert.deepEqual(expandScheduleDays(null), { days: [], formatted: "" });
  assert.deepEqual(expandScheduleDays(undefined), { days: [], formatted: "" });

  // TypeError when numeric Excel cell is passed without string conversion
  assert.throws(() => expandScheduleDays(123), TypeError);
});

// ============================================================================
// SUITE 2: REST-DAY CARVE-OUT & CONFLICT RESOLUTION
// ============================================================================

test("ADV-REST-01: Total Conflict (all duty days swallowed by rest days)", () => {
  // Duty SUN, Rest SUN
  const res1 = resolveDutyAndRestDays("SUN", "SUN");
  assert.equal(res1.scheduleDays, "");
  assert.equal(res1.dayoff, "SUN");
  assert.deepEqual(res1.dutyDays, []);
  assert.deepEqual(res1.conflictRemoved, ["SUN"]);
  assert.match(res1.error ?? "", /Schedule days cannot be entirely comprised of rest days/);

  // Duty SAT-SUN, Rest SAT, SUN
  const res2 = resolveDutyAndRestDays("SAT-SUN", "SAT, SUN");
  assert.equal(res2.scheduleDays, "");
  assert.deepEqual(res2.dutyDays, []);
  assert.deepEqual(res2.conflictRemoved, ["SAT", "SUN"]);
  assert.match(res2.error ?? "", /Schedule days cannot be entirely comprised of rest days/);

  // Duty wrap-around SAT-TUE, Rest MON, TUE, SAT, SUN
  const res3 = resolveDutyAndRestDays("SAT-TUE", "MON, TUE, SAT, SUN");
  assert.equal(res3.scheduleDays, "");
  assert.deepEqual(res3.dutyDays, []);
  assert.deepEqual(res3.conflictRemoved, ["MON", "TUE", "SAT", "SUN"]);
  assert.match(res3.error ?? "", /Schedule days cannot be entirely comprised of rest days/);
});

test("ADV-REST-02: Partial overlap and rest day subsets", () => {
  // Duty MON-SAT, Rest SAT, SUN -> SAT carved out, SUN retained in restDays
  const res1 = resolveDutyAndRestDays("MON-SAT", "SAT, SUN");
  assert.equal(res1.scheduleDays, "MON, TUE, WED, THU, FRI");
  assert.equal(res1.dayoff, "SAT, SUN");
  assert.deepEqual(res1.conflictRemoved, ["SAT"]);
  assert.equal(res1.error, undefined);

  // Duty SAT-TUE (MON, TUE, SAT, SUN), Rest SUN -> SUN carved out
  const res2 = resolveDutyAndRestDays("SAT-TUE", "SUN");
  assert.equal(res2.scheduleDays, "MON, TUE, SAT");
  assert.equal(res2.dayoff, "SUN");
  assert.deepEqual(res2.conflictRemoved, ["SUN"]);
  assert.equal(res2.error, undefined);

  // Rest days with no overlap: Duty MON-WED, Rest THU-SUN
  const res3 = resolveDutyAndRestDays("MON-WED", "THU-SUN");
  assert.equal(res3.scheduleDays, "MON, TUE, WED");
  assert.equal(res3.dayoff, "THU, FRI, SAT, SUN");
  assert.deepEqual(res3.conflictRemoved, []);
  assert.equal(res3.error, undefined);
});

test("ADV-REST-03: Invalid tokens in duty or rest days returns structured error", () => {
  // Invalid duty
  const res1 = resolveDutyAndRestDays("MON-XYZ", "SUN");
  assert.equal(res1.scheduleDays, "MON-XYZ");
  assert.equal(res1.dayoff, "SUN");
  assert.match(res1.error ?? "", /Invalid schedule day range: "MON-XYZ"/);

  // Invalid rest day
  const res2 = resolveDutyAndRestDays("MON-FRI", "FOOBAR");
  assert.equal(res2.scheduleDays, "MON-FRI");
  assert.equal(res2.dayoff, "FOOBAR");
  assert.match(res2.error ?? "", /Invalid schedule day token: "FOOBAR"/);

  // Both invalid
  const res3 = resolveDutyAndRestDays("INVALID_DUTY", "INVALID_REST");
  assert.match(res3.error ?? "", /Invalid schedule day token: "INVALID_DUTY"/);
});

test("ADV-REST-04 [REMEDIATED]: normalizePlantillaRow and coalescePlantillaBatch surface resolveDutyAndRestDays errors", () => {
  const rowWithInvalidSched = {
    EMPLOYEE_NO: "EMP-001",
    POSITION: "Merchandiser",
    SCHEDULE_DAYS: "MON-XYZ",
    DAYOFF: "SUN",
  };

  const normalized = normalizePlantillaRow(rowWithInvalidSched);
  assert.equal(normalized.SCHEDULE_DAYS, "MON-XYZ");
  assert.ok(normalized.__scheduleError);

  // coalescePlantillaBatch rejects invalid schedule day tokens as validation error per R4:
  const batchResult = coalescePlantillaBatch([rowWithInvalidSched]);
  const schedErrors = batchResult.errors.filter((e) => e.field === "SCHEDULE_DAYS" || e.msg.includes("schedule"));
  assert.equal(schedErrors.length, 1, "Unrecognized day token is rejected as a validation error per R4");
  assert.equal(schedErrors[0].conflictType, "invalid_schedule_days");
});

test("ADV-REST-05 [REMEDIATED]: 100% swallowed duty days surfaces validation error", () => {
  const rowWithTotalConflict = {
    EMPLOYEE_NO: "EMP-002",
    POSITION: "Merchandiser",
    SCHEDULE_DAYS: "SUN",
    DAYOFF: "SUN",
  };

  const normalized = normalizePlantillaRow(rowWithTotalConflict);
  assert.equal(normalized.SCHEDULE_DAYS, "");
  assert.equal(normalized.DAYOFF, "SUN");
  assert.match(normalized.__scheduleError ?? "", /Schedule days cannot be entirely comprised of rest days/);

  const batchResult = coalescePlantillaBatch([rowWithTotalConflict]);
  assert.equal(batchResult.errors.length, 1, "Swallowed duty days triggers validation error");
  assert.equal(batchResult.errors[0].conflictType, "invalid_schedule_days");
});

// ============================================================================
// SUITE 3: STRING NORMALIZATION & UNICODE EDGE CASES
// ============================================================================

test("ADV-STR-01: Consecutive tabs, carriage returns, newlines, and form feeds", () => {
  assert.equal(collapseAndUppercase("DELA\t\t\tCRUZ"), "DELA CRUZ");
  assert.equal(collapseAndUppercase("JUAN\r\n\r\nCARLOS"), "JUAN CARLOS");
  assert.equal(collapseAndUppercase("  \t\r\n  SINGLE  \t\r\n  "), "SINGLE");
  assert.equal(collapseAndUppercase("\u00A0\u00A0NON-BREAKING\u00A0\u00A0SPACE\u00A0\u00A0"), "NON-BREAKING SPACE");
});

test("ADV-STR-02: Diacritics, Spanish/Filipino names, and accented characters", () => {
  assert.equal(collapseAndUppercase("peña"), "PEÑA");
  assert.equal(collapseAndUppercase("sto. niño"), "STO. NIÑO");
  assert.equal(collapseAndUppercase("san josé"), "SAN JOSÉ");
  assert.equal(collapseAndUppercase("curaçao"), "CURAÇAO");
});

test("ADV-STR-03 [CAVEAT]: Unicode NFD (decomposed) vs NFC (composed) diacritics identity matching", () => {
  // NFD: "PEN\u0303A" (N + combining tilde) vs NFC: "PEÑA" (precomposed \u00D1)
  const nfd = "PEN\u0303A";
  const nfc = "PEÑA";
  const normNfd = collapseAndUppercase(nfd);
  const normNfc = collapseAndUppercase(nfc);

  // In JavaScript, "PEN\u0303A" !== "PEÑA" without .normalize("NFC"):
  assert.notEqual(normNfd, normNfc);
  assert.equal(normNfd.normalize("NFC"), normNfc);

  // If two rows for the same employee have NFD and NFC representations:
  const batch = [
    { EMPLOYEE_NO: "EMP-001", LAST_NAME: nfc, FIRST_NAME: "JUAN", MIDDLE_NAME: "SANTOS", DATE_HIRED: "2026-01-15", POSITION: "Helper" },
    { EMPLOYEE_NO: "EMP-001", LAST_NAME: nfd, FIRST_NAME: "JUAN", MIDDLE_NAME: "SANTOS", DATE_HIRED: "2026-01-15", POSITION: "Helper" },
  ];
  const result = coalescePlantillaBatch(batch);
  // Triggers false-positive core_identity_mismatch_in_batch because of un-normalized Unicode!
  const mismatch = result.errors.find((e) => e.conflictType === "core_identity_mismatch_in_batch");
  assert.ok(mismatch);
});

test("ADV-STR-04: Non-string and boundary inputs to collapseAndUppercase", () => {
  assert.equal(collapseAndUppercase(null), "");
  assert.equal(collapseAndUppercase(undefined), "");
  assert.equal(collapseAndUppercase(""), "");
  assert.equal(collapseAndUppercase("   "), "");
  assert.equal(collapseAndUppercase(0), "0");
  assert.equal(collapseAndUppercase(false), "FALSE");
  assert.equal(collapseAndUppercase(true), "TRUE");
  assert.equal(collapseAndUppercase(NaN), "NAN");
});

// ============================================================================
// SUITE 4: CONTACT NUMBER CANONICALIZATION
// ============================================================================

test("ADV-PHONE-01: Canonical PH mobile prefix variations", () => {
  assert.equal(canonicalizeMobileNumber("+639171234567"), "09171234567");
  assert.equal(canonicalizeMobileNumber("639181234567"), "09181234567");
  assert.equal(canonicalizeMobileNumber("9201234567"), "09201234567");
  assert.equal(canonicalizeMobileNumber("09221234567"), "09221234567");
});

test("ADV-PHONE-02: Heavy formatting punctuation and spacing", () => {
  assert.equal(canonicalizeMobileNumber("+63 (917) 123-4567"), "09171234567");
  assert.equal(canonicalizeMobileNumber("+63-917-123-4567"), "09171234567");
  assert.equal(canonicalizeMobileNumber("+63.917.123.4567"), "09171234567");
  assert.equal(canonicalizeMobileNumber("  +63  917  123  4567  "), "09171234567");
  assert.equal(canonicalizeMobileNumber("0917--123..4567"), "09171234567");
});

test("ADV-PHONE-03: Landline, international, and abnormal phone inputs", () => {
  assert.equal(canonicalizeMobileNumber("(02) 8888-1234"), "0288881234");
  assert.equal(canonicalizeMobileNumber("(045) 982-1234"), "0459821234");
  assert.equal(canonicalizeMobileNumber("+63 0917 123 4567"), "+6309171234567");
  assert.equal(canonicalizeMobileNumber("N/A"), "N/A");
  assert.equal(canonicalizeMobileNumber("NONE"), "NONE");
  assert.equal(canonicalizeMobileNumber(9171234567), "09171234567");
});

// ============================================================================
// SUITE 5: DATE NORMALIZATION AND LEAP YEARS
// ============================================================================

test("ADV-DATE-01: Standard date formats (ISO, MM/DD/YYYY, Text month)", () => {
  assert.equal(normalizeDateToIso("2026-01-15"), "2026-01-15");
  assert.equal(normalizeDateToIso("01/15/2026"), "2026-01-15");
  assert.equal(normalizeDateToIso("1/5/2026"), "2026-01-05");
  assert.equal(normalizeDateToIso("15-Jan-2026"), "2026-01-15");
  assert.equal(normalizeDateToIso("15 January 2026"), "2026-01-15");
});

test("ADV-DATE-02 [REMEDIATED]: MM-DD-YYYY date parses cleanly without timezone corruption", () => {
  const actual = normalizeDateToIso("01-15-2026");
  assert.equal(actual, "2026-01-15", "01-15-2026 normalizes strictly to 2026-01-15 across all timezones");
});

test("ADV-DATE-03: Leap year dates and boundaries", () => {
  // Valid leap day: 2024-02-29
  assert.equal(normalizeDateToIso("2024-02-29"), "2024-02-29");
  assert.equal(normalizeDateToIso("02/29/2024"), "2024-02-29");
  assert.equal(normalizeDateToIso("29-Feb-2024"), "2024-02-29");

  // Non-leap year Feb 28: 2025-02-28
  assert.equal(normalizeDateToIso("2025-02-28"), "2025-02-28");
  assert.equal(normalizeDateToIso("02/28/2025"), "2025-02-28");
  assert.equal(normalizeDateToIso("28-Feb-2025"), "2025-02-28");

  // Century leap year: 2000-02-29
  assert.equal(normalizeDateToIso("2000-02-29"), "2000-02-29");
});

test("ADV-DATE-04: Excel numeric serial dates", () => {
  // 44941 is 2023-01-15
  assert.equal(normalizeDateToIso(44941), "2023-01-15");
  assert.equal(normalizeDateToIso("44941"), "2023-01-15");
});

test("ADV-DATE-05 [VULNERABILITY]: Impossible calendar dates pass regex without calendar validation", () => {
  // "2026-02-31" (Feb 31 does not exist) matches isoMatch and is returned as "2026-02-31"
  assert.equal(normalizeDateToIso("2026-02-31"), "2026-02-31");
  // "02/31/2026" matches slashMatch and is returned as "2026-02-31"
  assert.equal(normalizeDateToIso("02/31/2026"), "2026-02-31");
  // "2026-02-29" (2026 is not a leap year) is returned as "2026-02-29"
  assert.equal(normalizeDateToIso("2026-02-29"), "2026-02-29");
});

// ============================================================================
// SUITE 6: AGE INVARIANT CALCULATION (18+ AT HIRE)
// ============================================================================

test("ADV-AGE-01: Exact birthday boundaries relative to hire date", () => {
  assert.equal(computeAgeAtHire("2008-01-15", "2026-01-15"), 18);
  assert.equal(computeAgeAtHire("2008-01-16", "2026-01-15"), 17);
  assert.equal(computeAgeAtHire("2008-01-14", "2026-01-15"), 18);
});

test("ADV-AGE-02: Leap day birthday age calculation", () => {
  // Aligned with PostgreSQL ('2004-02-29'::date + INTERVAL '18 years' = '2022-02-28')
  assert.equal(computeAgeAtHire("2004-02-29", "2022-02-27"), 17);
  assert.equal(computeAgeAtHire("2004-02-29", "2022-02-28"), 18);
  assert.equal(computeAgeAtHire("2004-02-29", "2022-03-01"), 18);
});

test("ADV-AGE-03: Negative age or future birthdate", () => {
  assert.equal(computeAgeAtHire("2026-05-01", "2026-01-15"), -1);
});

test("ADV-AGE-04: Invalid or missing dates return null", () => {
  assert.equal(computeAgeAtHire(null, "2026-01-15"), null);
  assert.equal(computeAgeAtHire("", "2026-01-15"), null);
  assert.equal(computeAgeAtHire("NOT_A_DATE", "2026-01-15"), null);
});
