import { test } from "node:test";
import assert from "node:assert/strict";
import {
  collapseAndUppercase,
  canonicalizeMobileNumber,
  normalizeDateToIso,
  computeAgeAtHire,
  normalizePlantillaRow,
  normalizePlantillaRows,
  coalescePlantillaBatch,
} from "../plantilla_normalization.ts";
import {
  expandScheduleDays,
  resolveDutyAndRestDays,
} from "../schedule_normalizer.ts";

test("R1 Normalization: collapseAndUppercase trims, collapses spaces, and uppercases", () => {
  assert.equal(collapseAndUppercase("  dela   cruz  "), "DELA CRUZ");
  assert.equal(collapseAndUppercase("juan\t\n  carlos "), "JUAN CARLOS");
  assert.equal(collapseAndUppercase("single"), "SINGLE");
  assert.equal(collapseAndUppercase("   merchandiser   specialist   "), "MERCHANDISER SPECIALIST");
  assert.equal(collapseAndUppercase(null), "");
  assert.equal(collapseAndUppercase(undefined), "");
  assert.equal(collapseAndUppercase(""), "");
});

test("R1 Normalization: canonicalizeMobileNumber normalizes PH prefixes to 09xxxxxxxxx", () => {
  // Standard +639 format
  assert.equal(canonicalizeMobileNumber("+639171234567"), "09171234567");
  // With formatting punctuation
  assert.equal(canonicalizeMobileNumber("+63 (917) 123-4567"), "09171234567");
  assert.equal(canonicalizeMobileNumber("+63 917 123 4567"), "09171234567");
  // 639 format
  assert.equal(canonicalizeMobileNumber("639181234567"), "09181234567");
  // 10-digit 9xxxxxxxxx format
  assert.equal(canonicalizeMobileNumber("9201234567"), "09201234567");
  // 11-digit 09xxxxxxxxx format
  assert.equal(canonicalizeMobileNumber("09191234567"), "09191234567");
  assert.equal(canonicalizeMobileNumber("0919-123-4567"), "09191234567");
  // Edge cases
  assert.equal(canonicalizeMobileNumber(null), "");
  assert.equal(canonicalizeMobileNumber(undefined), "");
  assert.equal(canonicalizeMobileNumber("   "), "");
});

test("R1 Normalization: normalizeDateToIso converts formats to strict YYYY-MM-DD", () => {
  // Already ISO
  assert.equal(normalizeDateToIso("2026-01-15"), "2026-01-15");
  assert.equal(normalizeDateToIso("2026-1-5"), "2026-01-05");
  assert.equal(normalizeDateToIso("2026-01-15T08:30:00Z"), "2026-01-15");
  // MM/DD/YYYY standard
  assert.equal(normalizeDateToIso("01/15/2026"), "2026-01-15");
  assert.equal(normalizeDateToIso("1/5/2026"), "2026-01-05");
  assert.equal(normalizeDateToIso("12/31/1995"), "1995-12-31");
  // MM-DD-YYYY hyphenated (no 1-day timezone rollback)
  assert.equal(normalizeDateToIso("01-15-2026"), "2026-01-15");
  assert.equal(normalizeDateToIso("1-5-2026"), "2026-01-05");
  // Text month (15-Jan-2026)
  assert.equal(normalizeDateToIso("15-Jan-2026"), "2026-01-15");
  assert.equal(normalizeDateToIso("15-JAN-2026"), "2026-01-15");
  // JS Date instance
  assert.equal(normalizeDateToIso(new Date(Date.UTC(2026, 0, 15))), "2026-01-15");
  // Excel serial number (44941 is 2023-01-15)
  assert.equal(normalizeDateToIso(44941), "2023-01-15");
  assert.equal(normalizeDateToIso("44941"), "2023-01-15");
  // Blank inputs
  assert.equal(normalizeDateToIso(null), "");
  assert.equal(normalizeDateToIso(undefined), "");
  assert.equal(normalizeDateToIso(""), "");
});

test("R3 Age Invariant: computeAgeAtHire calculates accurate age and handles edge cases", () => {
  // 18th birthday on the exact date of hire -> age 18
  assert.equal(computeAgeAtHire("2008-01-15", "2026-01-15"), 18);
  // 1 day before 18th birthday -> age 17
  assert.equal(computeAgeAtHire("2008-01-16", "2026-01-15"), 17);
  // Over 18
  assert.equal(computeAgeAtHire("1995-05-15", "2026-01-15"), 30);
  // Leap day birth (Feb 29, 2004) -> aligned with PostgreSQL INTERVAL '18 years'
  assert.equal(computeAgeAtHire("2004-02-29", "2022-02-27"), 17);
  assert.equal(computeAgeAtHire("2004-02-29", "2022-02-28"), 18);
  assert.equal(computeAgeAtHire("2004-02-29", "2022-03-01"), 18);
  // Leap day birth in 2008 evaluated in 2026 common year
  assert.equal(computeAgeAtHire("2008-02-29", "2026-02-27"), 17);
  assert.equal(computeAgeAtHire("2008-02-29", "2026-02-28"), 18);
  // Invalid inputs
  assert.equal(computeAgeAtHire("invalid", "2026-01-15"), null);
});

test("R4 Schedule Normalizer: expandScheduleDays handles linear ranges, wrap-around, and hybrid lists", () => {
  // Linear ranges
  const monSat = expandScheduleDays("MON-SAT");
  assert.deepEqual(monSat.days, ["MON", "TUE", "WED", "THU", "FRI", "SAT"]);
  assert.equal(monSat.formatted, "MON, TUE, WED, THU, FRI, SAT");

  const monFri = expandScheduleDays("MON-FRI");
  assert.deepEqual(monFri.days, ["MON", "TUE", "WED", "THU", "FRI"]);

  const thuSat = expandScheduleDays("THU-SAT");
  assert.deepEqual(thuSat.days, ["THU", "FRI", "SAT"]);

  // Wrap-around range SAT-TUE -> SAT, SUN, MON, TUE -> ordered MON, TUE, SAT, SUN
  const satTue = expandScheduleDays("SAT-TUE");
  assert.deepEqual(satTue.days, ["MON", "TUE", "SAT", "SUN"]);
  assert.equal(satTue.formatted, "MON, TUE, SAT, SUN");

  // Hybrid list MON-WED,FRI
  const hybrid = expandScheduleDays("MON-WED,FRI");
  assert.deepEqual(hybrid.days, ["MON", "TUE", "WED", "FRI"]);
  assert.equal(hybrid.formatted, "MON, TUE, WED, FRI");

  // Full day names
  const fullNames = expandScheduleDays("MONDAY - WEDNESDAY, FRIDAY");
  assert.deepEqual(fullNames.days, ["MON", "TUE", "WED", "FRI"]);

  // Abbreviation dots (e.g. MON., WED., FRI.)
  const withDots = expandScheduleDays("MON., WED., FRI.");
  assert.deepEqual(withDots.days, ["MON", "WED", "FRI"]);
  assert.equal(withDots.formatted, "MON, WED, FRI");

  // Unrecognized token throws Error
  assert.throws(() => expandScheduleDays("MON-XYZ"), /Invalid schedule day range/);
  assert.throws(() => expandScheduleDays("FOOBAR"), /Invalid schedule day token/);
});

test("R4 Schedule Normalizer: resolveDutyAndRestDays carves out rest days and maintains mutual exclusivity", () => {
  // Standard duty MON-SAT with SUN off (no overlap)
  const res1 = resolveDutyAndRestDays("MON-SAT", "SUN");
  assert.equal(res1.scheduleDays, "MON, TUE, WED, THU, FRI, SAT");
  assert.equal(res1.dayoff, "SUN");
  assert.deepEqual(res1.conflictRemoved, []);
  assert.equal(res1.error, undefined);

  // Overlapping duty MON-SAT with SAT, SUN off -> carves out SAT
  const res2 = resolveDutyAndRestDays("MON-SAT", "SAT, SUN");
  assert.equal(res2.scheduleDays, "MON, TUE, WED, THU, FRI");
  assert.equal(res2.dayoff, "SAT, SUN");
  assert.deepEqual(res2.conflictRemoved, ["SAT"]);
  assert.equal(res2.error, undefined);

  // Duty days entirely comprised of rest days
  const res3 = resolveDutyAndRestDays("SUN", "SUN");
  assert.equal(res3.error, "Schedule days cannot be entirely comprised of rest days.");
  assert.deepEqual(res3.conflictRemoved, ["SUN"]);
});

test("R1 & R4 Integration: normalizePlantillaRow transforms all row fields", () => {
  const rawRow = {
    GROUP_NAME: "  GROUP   2 ",
    ACCOUNT_NAME: " SUPER  8 ",
    MOTHER_ACCOUNT: "SUPER   8",
    VCODE: " pg-dau-001 ",
    STORE_NAME: "  Super 8   Angeles Dau ",
    AREA_PROVINCE: "  Pampanga ",
    AREA_CITY: " Angeles  ",
    POSITION: " merchandiser   lead ",
    EMPLOYEE_NO: " emp-2026-001 ",
    LAST_NAME: " dela   cruz ",
    FIRST_NAME: " juan   carlos ",
    MIDDLE_NAME: " santos ",
    DATE_HIRED: " 01/15/2026 ",
    CIVIL_STATUS: " single ",
    RATE: " 610.00 ",
    DATE_OF_BIRTH: " 05/15/1995 ",
    CONTACT_NO: " +63 (917) 123-4567 ",
    ADDRESS: " 123 macarthur   hwy angeles ",
    SCHEDULE_DAYS: " MON-SAT ",
    SCHEDULE_TIME: " 08:00 AM - 05:00 PM ",
    DAYOFF: " SAT, SUN ",
    COORDINATOR: " Ops   Coordinator ",
    HRCO_EMAIL: " HRCO@ACTISERVE.COM ",
  };

  const normalized = normalizePlantillaRow(rawRow);

  assert.equal(normalized.GROUP_NAME, "GROUP 2");
  assert.equal(normalized.ACCOUNT_NAME, "SUPER 8");
  assert.equal(normalized.MOTHER_ACCOUNT, "SUPER 8");
  assert.equal(normalized.VCODE, "PG-DAU-001");
  assert.equal(normalized.STORE_NAME, "Super 8 Angeles Dau");
  assert.equal(normalized.AREA_PROVINCE, "Pampanga");
  assert.equal(normalized.AREA_CITY, "Angeles");
  assert.equal(normalized.POSITION, "MERCHANDISER LEAD");
  assert.equal(normalized.EMPLOYEE_NO, "EMP-2026-001");
  assert.equal(normalized.LAST_NAME, "DELA CRUZ");
  assert.equal(normalized.FIRST_NAME, "JUAN CARLOS");
  assert.equal(normalized.MIDDLE_NAME, "SANTOS");
  assert.equal(normalized.DATE_HIRED, "2026-01-15");
  assert.equal(normalized.CIVIL_STATUS, "SINGLE");
  assert.equal(normalized.RATE, "610.00");
  assert.equal(normalized.DATE_OF_BIRTH, "1995-05-15");
  assert.equal(normalized.CONTACT_NO, "09171234567");
  assert.equal(normalized.ADDRESS, "123 MACARTHUR HWY ANGELES");
  // Notice rest day SAT was carved out of MON-SAT:
  assert.equal(normalized.SCHEDULE_DAYS, "MON, TUE, WED, THU, FRI");
  assert.equal(normalized.SCHEDULE_TIME, "08:00 AM - 05:00 PM");
  assert.equal(normalized.DAYOFF, "SAT, SUN");
  assert.equal(normalized.COORDINATOR, "Ops Coordinator");
  assert.equal(normalized.HRCO_EMAIL, "hrco@actiserve.com");

  // normalizePlantillaRows array wrapper
  const batch = normalizePlantillaRows([rawRow]);
  assert.equal(batch.length, 1);
  assert.equal(batch[0].LAST_NAME, "DELA CRUZ");
});

test("R4 Schedule Normalizer: surfaces invalid schedule tokens and rest-day exhaustion errors", () => {
  // Row with invalid token attaches __scheduleError
  const rowInvalid = normalizePlantillaRow({
    EMPLOYEE_NO: "EMP-001",
    POSITION: "Merchandiser",
    SCHEDULE_DAYS: "MON-XYZ",
    DAYOFF: "SUN",
  });
  assert.equal(rowInvalid.SCHEDULE_DAYS, "MON-XYZ");
  assert.ok(rowInvalid.__scheduleError);
  assert.match(rowInvalid.__scheduleError, /Invalid schedule day range/);

  // coalescePlantillaBatch surfaces as validation error
  const resInvalid = coalescePlantillaBatch([rowInvalid]);
  assert.equal(resInvalid.errors.length, 1);
  assert.equal(resInvalid.errors[0].conflictType, "invalid_schedule_days");

  // Row with 100% swallowed duty days surfaces error
  const rowSwallowed = normalizePlantillaRow({
    EMPLOYEE_NO: "EMP-002",
    POSITION: "Merchandiser",
    SCHEDULE_DAYS: "SUN",
    DAYOFF: "SUN",
  });
  assert.equal(rowSwallowed.SCHEDULE_DAYS, "");
  assert.ok(rowSwallowed.__scheduleError);
  assert.match(rowSwallowed.__scheduleError, /Schedule days cannot be entirely comprised of rest days/);

  const resSwallowed = coalescePlantillaBatch([rowSwallowed]);
  assert.equal(resSwallowed.errors.length, 1);
  assert.equal(resSwallowed.errors[0].conflictType, "invalid_schedule_days");
});
