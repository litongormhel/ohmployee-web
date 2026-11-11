import { test } from "node:test";
import assert from "node:assert/strict";
import {
  coalescePlantillaBatch,
  computeAgeAtHire,
} from "../plantilla_normalization.ts";
import {
  PLANTILLA_SAMPLE_ROW,
  PLANTILLA_SAMPLE_ROW_2,
  PLANTILLA_SAMPLE_ROWS,
} from "../data_control_xlsx.ts";

test("R2 Multi-Row Core Identity: identical identity across roving rows passes cleanly", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-001",
      STORE_NAME: "Store One",
      POSITION: "Merchandiser",
      RATE: "610.00",
      DATE_OF_BIRTH: "1995-05-15",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-002",
      STORE_NAME: "Store Two",
      POSITION: "Merchandiser",
      RATE: "610.00",
      DATE_OF_BIRTH: "1995-05-15",
    },
  ];

  const result = coalescePlantillaBatch(batch);
  assert.equal(result.errors.length, 0);
  assert.equal(result.flags.length, 0);
  assert.equal(result.coalescedRows.length, 2);
});

test("R2 Multi-Row Core Identity: mismatch in LAST_NAME or DATE_HIRED triggers hard-block errors", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-001",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA ROSA", // Mismatched surname
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-02-01", // Mismatched date hired
      VCODE: "STORE-002",
      POSITION: "Merchandiser",
    },
  ];

  const result = coalescePlantillaBatch(batch);
  const lastNameErrors = result.errors.filter((e) => e.field === "LAST_NAME");
  const dateHiredErrors = result.errors.filter((e) => e.field === "DATE_HIRED");

  assert.ok(lastNameErrors.length > 0);
  assert.equal(lastNameErrors[0].conflictType, "core_identity_mismatch_in_batch");
  assert.ok(dateHiredErrors.length > 0);
  assert.equal(dateHiredErrors[0].conflictType, "core_identity_mismatch_in_batch");
});

test("R2 Coalescing: blank demographic, rate, and rest day fields silently auto-fill from sibling rows", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-ROVING-1",
      LAST_NAME: "AQUINO",
      FIRST_NAME: "CORAZON",
      MIDDLE_NAME: "COJUANGCO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-001",
      POSITION: "Supervisor",
      CIVIL_STATUS: "MARRIED",
      RATE: "750.00",
      DATE_OF_BIRTH: "1985-01-25",
      CONTACT_NO: "09181234567",
      ADDRESS: "Tarlac City",
      DAYOFF: "SUN",
    },
    {
      EMPLOYEE_NO: "EMP-ROVING-1",
      LAST_NAME: "AQUINO",
      FIRST_NAME: "CORAZON",
      MIDDLE_NAME: "COJUANGCO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-002",
      // Position and all demographics left blank on row 2
      POSITION: "",
      CIVIL_STATUS: "",
      RATE: "",
      DATE_OF_BIRTH: "",
      CONTACT_NO: "",
      ADDRESS: "",
      DAYOFF: "",
    },
  ];

  const result = coalescePlantillaBatch(batch);
  assert.equal(result.errors.length, 0);
  assert.equal(result.flags.length, 0);

  const row2 = result.coalescedRows[1];
  assert.equal(row2.POSITION, "SUPERVISOR");
  assert.equal(row2.CIVIL_STATUS, "MARRIED");
  assert.equal(row2.RATE, "750.00");
  assert.equal(row2.DATE_OF_BIRTH, "1985-01-25");
  assert.equal(row2.CONTACT_NO, "09181234567");
  assert.equal(row2.ADDRESS, "TARLAC CITY");
  assert.equal(row2.DAYOFF, "SUN");
});

test("R2 Coalescing: conflicting demographic or rate values emit warning flags and apply last-row-wins", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-ROVING-2",
      LAST_NAME: "RAMOS",
      FIRST_NAME: "FIDEL",
      MIDDLE_NAME: "VALDEZ",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-001",
      POSITION: "Lead Merchandiser",
      RATE: "610.00",
      CIVIL_STATUS: "SINGLE",
      DAYOFF: "SUN",
    },
    {
      EMPLOYEE_NO: "EMP-ROVING-2",
      LAST_NAME: "RAMOS",
      FIRST_NAME: "FIDEL",
      MIDDLE_NAME: "VALDEZ",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-002",
      POSITION: "Senior Lead",
      RATE: "650.00", // Conflicting rate
      CIVIL_STATUS: "MARRIED", // Conflicting civil status
      DAYOFF: "SAT, SUN", // Conflicting dayoff
    },
  ];

  const result = coalescePlantillaBatch(batch);
  assert.equal(result.errors.length, 0); // Non-blocking!

  // Warning flags emitted for conflicting fields
  const rateFlag = result.flags.find((f) => f.flag === "conflict_rate");
  const civilFlag = result.flags.find((f) => f.flag === "conflict_civil_status");
  const dayoffFlag = result.flags.find((f) => f.flag === "conflict_dayoff");
  assert.ok(rateFlag);
  assert.ok(civilFlag);
  assert.ok(dayoffFlag);

  // Both rows updated with last-row-wins values
  assert.equal(result.coalescedRows[0].RATE, "650.00");
  assert.equal(result.coalescedRows[1].RATE, "650.00");
  assert.equal(result.coalescedRows[0].CIVIL_STATUS, "MARRIED");
  assert.equal(result.coalescedRows[1].CIVIL_STATUS, "MARRIED");
  assert.equal(result.coalescedRows[0].DAYOFF, "SAT, SUN");
  assert.equal(result.coalescedRows[1].DAYOFF, "SAT, SUN");
});

test("R2 Position Invariant: blank POSITION across all rows for an employee produces hard-block error", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-NO-POS",
      LAST_NAME: "GARCIA",
      FIRST_NAME: "CARLOS",
      MIDDLE_NAME: "POLICARPIO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-001",
      POSITION: "  ", // blank on row 1
    },
    {
      EMPLOYEE_NO: "EMP-NO-POS",
      LAST_NAME: "GARCIA",
      FIRST_NAME: "CARLOS",
      MIDDLE_NAME: "POLICARPIO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-002",
      POSITION: "", // blank on row 2
    },
  ];

  const result = coalescePlantillaBatch(batch);
  const posErrors = result.errors.filter((e) => e.field === "POSITION");
  assert.ok(posErrors.length > 0);
  assert.equal(posErrors[0].conflictType, "position_required");
});

test("R3 Minimum Age Invariant: computed age under 18 years old triggers hard-block error", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-UNDERAGE",
      LAST_NAME: "BONIFACIO",
      FIRST_NAME: "ANDRES",
      MIDDLE_NAME: "DECASTRO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-001",
      POSITION: "Helper",
      // Born 2009-05-10 -> age 16 as of 2026-01-15
      DATE_OF_BIRTH: "2009-05-10",
    },
  ];

  const result = coalescePlantillaBatch(batch);
  const ageErrors = result.errors.filter((e) => e.conflictType === "underage_employee_under_18");
  assert.ok(ageErrors.length > 0);
  assert.match(ageErrors[0].msg, /under 18 years old/);
});

test("R3 Minimum Age Invariant: DOB on row 1 propagates to row 2 and blocks both if underage", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-UNDERAGE-ROVING",
      LAST_NAME: "SILANG",
      FIRST_NAME: "DIEGO",
      MIDDLE_NAME: "ANDAYA",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-001",
      POSITION: "Merchandiser",
      DATE_OF_BIRTH: "2008-08-01", // Age 17 as of hire date
    },
    {
      EMPLOYEE_NO: "EMP-UNDERAGE-ROVING",
      LAST_NAME: "SILANG",
      FIRST_NAME: "DIEGO",
      MIDDLE_NAME: "ANDAYA",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-002",
      POSITION: "Merchandiser",
      DATE_OF_BIRTH: "", // blank on row 2, coalesces from row 1
    },
  ];

  const result = coalescePlantillaBatch(batch);
  const ageErrors = result.errors.filter((e) => e.conflictType === "underage_employee_under_18");
  // Both rows are hard-blocked because age is evaluated after coalescing
  assert.equal(ageErrors.length, 2);
});

test("R5 Template Invariant: sample row 2050-00002 has a valid 18+ birth date", () => {
  assert.ok(Array.isArray(PLANTILLA_SAMPLE_ROW_2));
  assert.ok(PLANTILLA_SAMPLE_ROWS.length >= 2);

  // Index 8 is EMPLOYEE_NO, index 12 is DATE_HIRED, index 15 is DATE_OF_BIRTH
  const empNo = PLANTILLA_SAMPLE_ROW_2[8];
  const dateHired = PLANTILLA_SAMPLE_ROW_2[12];
  const dob = PLANTILLA_SAMPLE_ROW_2[15];

  assert.equal(empNo, "2050-00002");
  assert.equal(dateHired, "2026-01-15");
  assert.equal(dob, "1998-08-20");

  const age = computeAgeAtHire(dob, dateHired);
  assert.ok(age !== null);
  assert.ok(age >= 18, `Expected age >= 18, but got ${age}`);
  assert.equal(age, 27);
});

test("R5 Template Invariant: sample row EMP-2026-001 also has valid 18+ birth date", () => {
  const dateHired = PLANTILLA_SAMPLE_ROW[12];
  const dob = PLANTILLA_SAMPLE_ROW[15];
  const age = computeAgeAtHire(dob, dateHired);
  assert.ok(age !== null);
  assert.ok(age >= 18, `Expected age >= 18, but got ${age}`);
});
