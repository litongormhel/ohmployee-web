import { test } from "node:test";
import assert from "node:assert/strict";
import {
  coalescePlantillaBatch,
  computeAgeAtHire,
} from "../plantilla_normalization.ts";

// ============================================================================
// ADVERSARIAL STRESS TEST SUITE: Challenger 2
// Target: Multi-Row Coalescing, 18+ Age Invariants, and Last-Row-Wins Persistence
// ============================================================================

// ----------------------------------------------------------------------------
// 1. Multi-Row Coalescing Permutations (5+ row roving employees)
// ----------------------------------------------------------------------------

test("Adversarial 1.1: 5-row roving employee with interleaved blanks & conflicting values across all fields", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-ROV-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-101",
      STORE_NAME: "Branch 101",
      POSITION: "Cashier",
      RATE: "500.00",
      CIVIL_STATUS: "SINGLE",
      CONTACT_NO: "09171111111",
      ADDRESS: "Manila",
      DAYOFF: "MON",
      DATE_OF_BIRTH: "1995-05-15",
    },
    {
      EMPLOYEE_NO: "EMP-ROV-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-102",
      STORE_NAME: "Branch 102",
      POSITION: "", // blank
      RATE: "", // blank
      CIVIL_STATUS: "", // blank
      CONTACT_NO: "", // blank
      ADDRESS: "", // blank
      DAYOFF: "", // blank
      DATE_OF_BIRTH: "", // blank
    },
    {
      EMPLOYEE_NO: "EMP-ROV-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-103",
      STORE_NAME: "Branch 103",
      POSITION: "",
      RATE: "550.00", // conflicting rate
      CIVIL_STATUS: "",
      CONTACT_NO: "09172222222", // conflicting contact
      ADDRESS: "",
      DAYOFF: "TUE", // conflicting dayoff
      DATE_OF_BIRTH: "",
    },
    {
      EMPLOYEE_NO: "EMP-ROV-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-104",
      STORE_NAME: "Branch 104",
      POSITION: "Lead Cashier", // conflicting position
      RATE: "",
      CIVIL_STATUS: "MARRIED", // conflicting civil status
      CONTACT_NO: "",
      ADDRESS: "Quezon City", // conflicting address
      DAYOFF: "",
      DATE_OF_BIRTH: "",
    },
    {
      EMPLOYEE_NO: "EMP-ROV-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-105",
      STORE_NAME: "Branch 105",
      POSITION: "",
      RATE: "600.00", // final conflicting rate
      CIVIL_STATUS: "", // blank on last row (row 4 was married)
      CONTACT_NO: "", // blank on last row (row 3 was 09172222222)
      ADDRESS: "Makati City", // final conflicting address
      DAYOFF: "WED", // final conflicting dayoff
      DATE_OF_BIRTH: "",
    },
  ];

  const result = coalescePlantillaBatch(batch);

  // 1. Must NOT produce hard-blocking errors
  assert.equal(result.errors.length, 0, `Expected 0 errors, got: ${JSON.stringify(result.errors)}`);

  // 2. Warning flags must be emitted for every conflicting field
  const flagNames = new Set(result.flags.map((f) => f.flag));
  assert.ok(flagNames.has("conflict_rate"), "Expected conflict_rate flag");
  assert.ok(flagNames.has("conflict_civil_status"), "Expected conflict_civil_status flag");
  assert.ok(flagNames.has("conflict_contact_no"), "Expected conflict_contact_no flag");
  assert.ok(flagNames.has("conflict_address"), "Expected conflict_address flag");
  assert.ok(flagNames.has("conflict_dayoff"), "Expected conflict_dayoff flag");
  assert.ok(flagNames.has("conflict_position"), "Expected conflict_position flag");

  // 3. Last non-blank row must deterministically win for every row in the group
  for (let i = 0; i < 5; i++) {
    const row = result.coalescedRows[i];
    assert.equal(row.RATE, "600.00", `Row ${i + 1} RATE mismatch`);
    assert.equal(row.CIVIL_STATUS, "MARRIED", `Row ${i + 1} CIVIL_STATUS mismatch (row 4 value should win over blank row 5)`);
    assert.equal(row.CONTACT_NO, "09172222222", `Row ${i + 1} CONTACT_NO mismatch (row 3 value should win over blank rows 4,5)`);
    assert.equal(row.ADDRESS, "MAKATI CITY", `Row ${i + 1} ADDRESS mismatch`);
    assert.equal(row.DAYOFF, "WED", `Row ${i + 1} DAYOFF mismatch`);
    assert.equal(row.POSITION, "LEAD CASHIER", `Row ${i + 1} POSITION mismatch`);
    assert.equal(row.DATE_OF_BIRTH, "1995-05-15", `Row ${i + 1} DATE_OF_BIRTH mismatch`);
  }
});

test("Adversarial 1.2: 7-row roving employee with trailing blanks on last 4 rows preserves earlier coalesced values", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-ROV-002",
      LAST_NAME: "MAGSAYSAY",
      FIRST_NAME: "RAMON",
      MIDDLE_NAME: "DELFIERRO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-201",
      POSITION: "Technician",
      RATE: "650.00",
      CIVIL_STATUS: "SINGLE",
      DATE_OF_BIRTH: "1990-08-31",
      CONTACT_NO: "09191234567",
      ADDRESS: "Zambales",
      DAYOFF: "SUN",
    },
    {
      EMPLOYEE_NO: "EMP-ROV-002",
      LAST_NAME: "MAGSAYSAY",
      FIRST_NAME: "RAMON",
      MIDDLE_NAME: "DELFIERRO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-202",
      POSITION: "Senior Technician",
      RATE: "700.00",
      CIVIL_STATUS: "MARRIED",
      DAYOFF: "SAT",
    },
    {
      EMPLOYEE_NO: "EMP-ROV-002",
      LAST_NAME: "MAGSAYSAY",
      FIRST_NAME: "RAMON",
      MIDDLE_NAME: "DELFIERRO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-203",
      POSITION: "Lead Tech",
      RATE: "750.00",
      DAYOFF: "FRI",
    },
    // Rows 4 to 7 are completely blank in demographics/rates/positions
    ...[4, 5, 6, 7].map((num) => ({
      EMPLOYEE_NO: "EMP-ROV-002",
      LAST_NAME: "MAGSAYSAY",
      FIRST_NAME: "RAMON",
      MIDDLE_NAME: "DELFIERRO",
      DATE_HIRED: "2026-01-15",
      VCODE: `STORE-20${num}`,
      POSITION: "",
      RATE: "",
      CIVIL_STATUS: "",
      DATE_OF_BIRTH: "",
      CONTACT_NO: "",
      ADDRESS: "",
      DAYOFF: "",
    })),
  ];

  const result = coalescePlantillaBatch(batch);
  assert.equal(result.errors.length, 0);

  // All 7 rows must receive the last non-blank value:
  // POSITION: LEAD TECH (from row 3)
  // RATE: 750.00 (from row 3)
  // CIVIL_STATUS: MARRIED (from row 2)
  // DATE_OF_BIRTH: 1990-08-31 (from row 1)
  // CONTACT_NO: 09191234567 (from row 1)
  // ADDRESS: ZAMBALES (from row 1)
  // DAYOFF: FRI (from row 3)
  for (let idx = 0; idx < 7; idx++) {
    const row = result.coalescedRows[idx];
    assert.equal(row.POSITION, "LEAD TECH", `Row ${idx + 1} position`);
    assert.equal(row.RATE, "750.00", `Row ${idx + 1} rate`);
    assert.equal(row.CIVIL_STATUS, "MARRIED", `Row ${idx + 1} civil status`);
    assert.equal(row.DATE_OF_BIRTH, "1990-08-31", `Row ${idx + 1} dob`);
    assert.equal(row.CONTACT_NO, "09191234567", `Row ${idx + 1} contact`);
    assert.equal(row.ADDRESS, "ZAMBALES", `Row ${idx + 1} address`);
    assert.equal(row.DAYOFF, "FRI", `Row ${idx + 1} dayoff`);
  }
});

test("Adversarial 1.3: Interleaved rows between multiple roving employees prevents cross-contamination", () => {
  const batch = [
    // Emp A - Row 1
    {
      EMPLOYEE_NO: "EMP-ALPHA",
      LAST_NAME: "ALVAREZ",
      FIRST_NAME: "ALEX",
      MIDDLE_NAME: "AQUINO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-A1",
      POSITION: "Staff A",
      RATE: "500.00",
      DATE_OF_BIRTH: "1990-01-01",
    },
    // Emp B - Row 1
    {
      EMPLOYEE_NO: "EMP-BETA",
      LAST_NAME: "BERNARDO",
      FIRST_NAME: "BEN",
      MIDDLE_NAME: "BAUTISTA",
      DATE_HIRED: "2026-02-01",
      VCODE: "STORE-B1",
      POSITION: "Staff B",
      RATE: "800.00",
      DATE_OF_BIRTH: "1992-02-02",
    },
    // Emp A - Row 2 (blank rate, position)
    {
      EMPLOYEE_NO: "EMP-ALPHA",
      LAST_NAME: "ALVAREZ",
      FIRST_NAME: "ALEX",
      MIDDLE_NAME: "AQUINO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-A2",
      POSITION: "",
      RATE: "",
    },
    // Emp B - Row 2 (conflicting rate 850)
    {
      EMPLOYEE_NO: "EMP-BETA",
      LAST_NAME: "BERNARDO",
      FIRST_NAME: "BEN",
      MIDDLE_NAME: "BAUTISTA",
      DATE_HIRED: "2026-02-01",
      VCODE: "STORE-B2",
      POSITION: "Senior B",
      RATE: "850.00",
    },
    // Emp A - Row 3 (conflicting rate 550)
    {
      EMPLOYEE_NO: "EMP-ALPHA",
      LAST_NAME: "ALVAREZ",
      FIRST_NAME: "ALEX",
      MIDDLE_NAME: "AQUINO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-A3",
      POSITION: "",
      RATE: "550.00",
    },
  ];

  const result = coalescePlantillaBatch(batch);
  assert.equal(result.errors.length, 0);

  // Emp A should have RATE 550 and Staff A on all rows
  assert.equal(result.coalescedRows[0].RATE, "550.00");
  assert.equal(result.coalescedRows[0].POSITION, "STAFF A");
  assert.equal(result.coalescedRows[2].RATE, "550.00");
  assert.equal(result.coalescedRows[2].POSITION, "STAFF A");
  assert.equal(result.coalescedRows[4].RATE, "550.00");
  assert.equal(result.coalescedRows[4].POSITION, "STAFF A");

  // Emp B should have RATE 850 and SENIOR B on all rows
  assert.equal(result.coalescedRows[1].RATE, "850.00");
  assert.equal(result.coalescedRows[1].POSITION, "SENIOR B");
  assert.equal(result.coalescedRows[3].RATE, "850.00");
  assert.equal(result.coalescedRows[3].POSITION, "SENIOR B");
});

// ----------------------------------------------------------------------------
// 2. Deterministic Last-Row-Wins Verification
// ----------------------------------------------------------------------------

test("Adversarial 2.1: Last non-blank row wins across conflicting rates regardless of row ordering", () => {
  const batchDescending = [
    {
      EMPLOYEE_NO: "EMP-RATE-1",
      LAST_NAME: "TEST",
      FIRST_NAME: "ONE",
      MIDDLE_NAME: "NA",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-1",
      POSITION: "Crew",
      RATE: "700.00",
    },
    {
      EMPLOYEE_NO: "EMP-RATE-1",
      LAST_NAME: "TEST",
      FIRST_NAME: "ONE",
      MIDDLE_NAME: "NA",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-2",
      POSITION: "Crew",
      RATE: "600.00",
    },
    {
      EMPLOYEE_NO: "EMP-RATE-1",
      LAST_NAME: "TEST",
      FIRST_NAME: "ONE",
      MIDDLE_NAME: "NA",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-3",
      POSITION: "Crew",
      RATE: "650.00", // Row 3 is the last non-blank row
    },
  ];

  const result = coalescePlantillaBatch(batchDescending);
  assert.equal(result.coalescedRows[0].RATE, "650.00");
  assert.equal(result.coalescedRows[1].RATE, "650.00");
  assert.equal(result.coalescedRows[2].RATE, "650.00");
});

test("Adversarial 2.2: Conflicting mobile phone formats normalize and last row wins", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-PHONE",
      LAST_NAME: "CRUZ",
      FIRST_NAME: "ANA",
      MIDDLE_NAME: "MARIA",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-1",
      POSITION: "Cashier",
      CONTACT_NO: "+63 917 111 2222", // normalized to 09171112222
    },
    {
      EMPLOYEE_NO: "EMP-PHONE",
      LAST_NAME: "CRUZ",
      FIRST_NAME: "ANA",
      MIDDLE_NAME: "MARIA",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-2",
      POSITION: "Cashier",
      CONTACT_NO: "0918-333-4444", // normalized to 09183334444
    },
  ];

  const result = coalescePlantillaBatch(batch);
  assert.ok(result.flags.some((f) => f.flag === "conflict_contact_no"));
  assert.equal(result.coalescedRows[0].CONTACT_NO, "09183334444");
  assert.equal(result.coalescedRows[1].CONTACT_NO, "09183334444");
});

// ----------------------------------------------------------------------------
// 3. Core Identity Mismatch Hard-Blocks vs Normalization Invariance
// ----------------------------------------------------------------------------

test("Adversarial 3.1: Subtle whitespace differences in core identity normalize and pass cleanly", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-IDENT-1",
      LAST_NAME: "  DE   LA   PEÑA  ",
      FIRST_NAME: "\tJUAN   CARLOS\t",
      MIDDLE_NAME: "  DEL  ROSARIO ",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-1",
      POSITION: "Supervisor",
    },
    {
      EMPLOYEE_NO: "EMP-IDENT-1",
      LAST_NAME: "DE LA PEÑA",
      FIRST_NAME: "JUAN CARLOS",
      MIDDLE_NAME: "DEL ROSARIO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-2",
      POSITION: "Supervisor",
    },
  ];

  const result = coalescePlantillaBatch(batch);
  assert.equal(result.errors.length, 0, "Whitespace differences should normalize cleanly without errors");
  assert.equal(result.coalescedRows[0].LAST_NAME, "DE LA PEÑA");
  assert.equal(result.coalescedRows[1].LAST_NAME, "DE LA PEÑA");
  assert.equal(result.coalescedRows[0].FIRST_NAME, "JUAN CARLOS");
  assert.equal(result.coalescedRows[1].FIRST_NAME, "JUAN CARLOS");
});

test("Adversarial 3.2: Subtle casing differences in core identity normalize and pass cleanly", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-IDENT-2",
      LAST_NAME: "magsaysay",
      FIRST_NAME: "ramon",
      MIDDLE_NAME: "delfierro",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-1",
      POSITION: "Crew",
    },
    {
      EMPLOYEE_NO: "EMP-IDENT-2",
      LAST_NAME: "MAGSAYSAY",
      FIRST_NAME: "RAMON",
      MIDDLE_NAME: "DELFIERRO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-2",
      POSITION: "Crew",
    },
  ];

  const result = coalescePlantillaBatch(batch);
  assert.equal(result.errors.length, 0, "Casing differences should normalize cleanly to uppercase");
});

test("Adversarial 3.3: Legitimate distinct names (space vs no space) are hard-blocked", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-IDENT-3",
      LAST_NAME: "DELACRUZ", // No space
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-1",
      POSITION: "Crew",
    },
    {
      EMPLOYEE_NO: "EMP-IDENT-3",
      LAST_NAME: "DELA CRUZ", // With space
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-2",
      POSITION: "Crew",
    },
  ];

  const result = coalescePlantillaBatch(batch);
  const err = result.errors.find((e) => e.field === "LAST_NAME");
  assert.ok(err, "Must hard-block distinct names DELACRUZ vs DELA CRUZ");
  assert.equal(err.conflictType, "core_identity_mismatch_in_batch");
});

test("Adversarial 3.4: Date hired format variations normalize and pass without mismatch", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-IDENT-4",
      LAST_NAME: "SANTOS",
      FIRST_NAME: "PEDRO",
      MIDDLE_NAME: "GARCIA",
      DATE_HIRED: "2026-01-15", // ISO
      VCODE: "STORE-1",
      POSITION: "Crew",
    },
    {
      EMPLOYEE_NO: "EMP-IDENT-4",
      LAST_NAME: "SANTOS",
      FIRST_NAME: "PEDRO",
      MIDDLE_NAME: "GARCIA",
      DATE_HIRED: "01/15/2026", // US/PH Slash
      VCODE: "STORE-2",
      POSITION: "Crew",
    },
    {
      EMPLOYEE_NO: "EMP-IDENT-4",
      LAST_NAME: "SANTOS",
      FIRST_NAME: "PEDRO",
      MIDDLE_NAME: "GARCIA",
      DATE_HIRED: "15-Jan-2026", // Text month
      VCODE: "STORE-3",
      POSITION: "Crew",
    },
  ];

  const result = coalescePlantillaBatch(batch);
  assert.equal(result.errors.length, 0, "Dates should normalize to YYYY-MM-DD and not trigger mismatch");
  assert.equal(result.coalescedRows[0].DATE_HIRED, "2026-01-15");
  assert.equal(result.coalescedRows[1].DATE_HIRED, "2026-01-15");
  assert.equal(result.coalescedRows[2].DATE_HIRED, "2026-01-15");
});

test("Adversarial 3.5: Genuinely conflicting DATE_HIRED is hard-blocked", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-IDENT-5",
      LAST_NAME: "SANTOS",
      FIRST_NAME: "PEDRO",
      MIDDLE_NAME: "GARCIA",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-1",
      POSITION: "Crew",
    },
    {
      EMPLOYEE_NO: "EMP-IDENT-5",
      LAST_NAME: "SANTOS",
      FIRST_NAME: "PEDRO",
      MIDDLE_NAME: "GARCIA",
      DATE_HIRED: "2026-01-16", // 1 day difference
      VCODE: "STORE-2",
      POSITION: "Crew",
    },
  ];

  const result = coalescePlantillaBatch(batch);
  const err = result.errors.find((e) => e.field === "DATE_HIRED");
  assert.ok(err, "Must hard-block differing DATE_HIRED");
  assert.equal(err.conflictType, "core_identity_mismatch_in_batch");
});

// ----------------------------------------------------------------------------
// 4. 18+ Age Invariant Boundary & Leap Year Stress Tests
// ----------------------------------------------------------------------------

test("Adversarial 4.1: Exact 18th birthday on hire date satisfies invariant", () => {
  // Born 2008-05-15, Hired 2026-05-15 -> exactly 18 years old
  const age = computeAgeAtHire("2008-05-15", "2026-05-15");
  assert.equal(age, 18);

  const batch = [
    {
      EMPLOYEE_NO: "EMP-AGE-EXACT18",
      LAST_NAME: "RIZAL",
      FIRST_NAME: "JOSE",
      MIDDLE_NAME: "MERCADO",
      DATE_HIRED: "2026-05-15",
      DATE_OF_BIRTH: "2008-05-15",
      VCODE: "STORE-1",
      POSITION: "Intern",
    },
  ];
  const result = coalescePlantillaBatch(batch);
  assert.equal(result.errors.length, 0, "Exact 18th birthday on hire date must pass");
});

test("Adversarial 4.2: 17 years 364 days on hire date (1 day before 18th birthday) hard-blocks", () => {
  // Born 2008-05-15, Hired 2026-05-14 -> 17 years old
  const age = computeAgeAtHire("2008-05-15", "2026-05-14");
  assert.equal(age, 17);

  const batch = [
    {
      EMPLOYEE_NO: "EMP-AGE-17Y364D",
      LAST_NAME: "RIZAL",
      FIRST_NAME: "JOSE",
      MIDDLE_NAME: "MERCADO",
      DATE_HIRED: "2026-05-14",
      DATE_OF_BIRTH: "2008-05-15",
      VCODE: "STORE-1",
      POSITION: "Intern",
    },
  ];
  const result = coalescePlantillaBatch(batch);
  const err = result.errors.find((e) => e.conflictType === "underage_employee_under_18");
  assert.ok(err, "17 years 364 days must be hard-blocked");
  assert.match(err.msg, /age: 17/);
});

test("Adversarial 4.3: 18 years and 1 day on hire date passes cleanly", () => {
  // Born 2008-05-15, Hired 2026-05-16 -> 18 years old
  const age = computeAgeAtHire("2008-05-15", "2026-05-16");
  assert.equal(age, 18);

  const batch = [
    {
      EMPLOYEE_NO: "EMP-AGE-18Y1D",
      LAST_NAME: "RIZAL",
      FIRST_NAME: "JOSE",
      MIDDLE_NAME: "MERCADO",
      DATE_HIRED: "2026-05-16",
      DATE_OF_BIRTH: "2008-05-15",
      VCODE: "STORE-1",
      POSITION: "Intern",
    },
  ];
  const result = coalescePlantillaBatch(batch);
  assert.equal(result.errors.length, 0);
});

test("Adversarial 4.4: Leap year birthdate (2008-02-29) evaluated against non-leap 18th anniversary (2026)", () => {
  // 2008 is a leap year (Feb 29 exists)
  // 2026 is a common year (Feb 28 days)

  // On Feb 27, 2026 (day before anniversary): employee has lived 17 years and 363 days (underage)
  const ageOnFeb27 = computeAgeAtHire("2008-02-29", "2026-02-27");
  assert.equal(ageOnFeb27, 17, "On Feb 27 in common year, person born Feb 29 is 17");

  // On Feb 28, 2026 (anniversary in common year): employee has turned 18 (aligned with PostgreSQL INTERVAL '18 years')
  const ageOnFeb28 = computeAgeAtHire("2008-02-29", "2026-02-28");
  assert.equal(ageOnFeb28, 18, "On Feb 28 in common year, person born Feb 29 is 18");

  // On March 1, 2026: employee is 18
  const ageOnMar01 = computeAgeAtHire("2008-02-29", "2026-03-01");
  assert.equal(ageOnMar01, 18, "On March 1 in common year, person born Feb 29 is 18");

  // Batch testing for Feb 27 (underage)
  const batchFeb27 = [
    {
      EMPLOYEE_NO: "EMP-LEAP-FEB27",
      LAST_NAME: "MABINI",
      FIRST_NAME: "APOLINARIO",
      MIDDLE_NAME: "MARANAN",
      DATE_HIRED: "2026-02-27",
      DATE_OF_BIRTH: "2008-02-29",
      VCODE: "STORE-1",
      POSITION: "Clerk",
    },
  ];
  const resFeb27 = coalescePlantillaBatch(batchFeb27);
  assert.ok(resFeb27.errors.some((e) => e.conflictType === "underage_employee_under_18"));

  // Batch testing for Feb 28 (exact anniversary - passes)
  const batchFeb28 = [
    {
      EMPLOYEE_NO: "EMP-LEAP-FEB28",
      LAST_NAME: "MABINI",
      FIRST_NAME: "APOLINARIO",
      MIDDLE_NAME: "MARANAN",
      DATE_HIRED: "2026-02-28",
      DATE_OF_BIRTH: "2008-02-29",
      VCODE: "STORE-1",
      POSITION: "Clerk",
    },
  ];
  const resFeb28 = coalescePlantillaBatch(batchFeb28);
  assert.equal(resFeb28.errors.length, 0, "Feb 28 hire date satisfies 18+ invariant in common year");

  // Batch testing for March 1 (passes)
  const batchMar01 = [
    {
      EMPLOYEE_NO: "EMP-LEAP-MAR01",
      LAST_NAME: "MABINI",
      FIRST_NAME: "APOLINARIO",
      MIDDLE_NAME: "MARANAN",
      DATE_HIRED: "2026-03-01",
      DATE_OF_BIRTH: "2008-02-29",
      VCODE: "STORE-1",
      POSITION: "Clerk",
    },
  ];
  const resMar01 = coalescePlantillaBatch(batchMar01);
  assert.equal(resMar01.errors.length, 0, "March 1 hire date must pass 18+ invariant");
});

test("Adversarial 4.5: Leap year birthdate (2004-02-29) evaluated against leap year anniversary (2024-02-29)", () => {
  // Born 2004-02-29, evaluated on 2024-02-28 -> age 19
  const ageEve = computeAgeAtHire("2004-02-29", "2024-02-28");
  assert.equal(ageEve, 19);

  // Born 2004-02-29, evaluated on 2024-02-29 -> exact 20th birthday
  const ageLeap = computeAgeAtHire("2004-02-29", "2024-02-29");
  assert.equal(ageLeap, 20);

  // Born 2004-02-29, evaluated on 2024-03-01 -> age 20
  const agePost = computeAgeAtHire("2004-02-29", "2024-03-01");
  assert.equal(agePost, 20);
});

test("Adversarial 4.6: Year-end boundary (Dec 31 vs Jan 01)", () => {
  // Born 2007-12-31, Hired 2025-12-30 -> age 17
  assert.equal(computeAgeAtHire("2007-12-31", "2025-12-30"), 17);
  // Born 2007-12-31, Hired 2025-12-31 -> age 18
  assert.equal(computeAgeAtHire("2007-12-31", "2025-12-31"), 18);

  // Born 2008-01-01, Hired 2025-12-31 -> age 17
  assert.equal(computeAgeAtHire("2008-01-01", "2025-12-31"), 17);
  // Born 2008-01-01, Hired 2026-01-01 -> age 18
  assert.equal(computeAgeAtHire("2008-01-01", "2026-01-01"), 18);
});

test("Adversarial 4.7: Underage birth date on row 3 propagates to rows 1 and 2 and blocks all rows", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-PROPAGATE-UNDERAGE",
      LAST_NAME: "DEL PILAR",
      FIRST_NAME: "GREGORIO",
      MIDDLE_NAME: "SM",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-1",
      POSITION: "Guard",
      DATE_OF_BIRTH: "", // blank
    },
    {
      EMPLOYEE_NO: "EMP-PROPAGATE-UNDERAGE",
      LAST_NAME: "DEL PILAR",
      FIRST_NAME: "GREGORIO",
      MIDDLE_NAME: "SM",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-2",
      POSITION: "Guard",
      DATE_OF_BIRTH: "", // blank
    },
    {
      EMPLOYEE_NO: "EMP-PROPAGATE-UNDERAGE",
      LAST_NAME: "DEL PILAR",
      FIRST_NAME: "GREGORIO",
      MIDDLE_NAME: "SM",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-3",
      POSITION: "Guard",
      DATE_OF_BIRTH: "2009-06-01", // age 16 as of 2026-01-15
    },
  ];

  const result = coalescePlantillaBatch(batch);
  const ageErrors = result.errors.filter((e) => e.conflictType === "underage_employee_under_18");
  // All 3 rows must be blocked because the underage birthdate propagates to the employee group
  assert.equal(ageErrors.length, 3, "All 3 rows of the underage employee must be hard-blocked");
  for (let i = 0; i < 3; i++) {
    assert.equal(result.coalescedRows[i].DATE_OF_BIRTH, "2009-06-01");
  }
});

// ----------------------------------------------------------------------------
// 5. Position Validation & Coalescing Invariants
// ----------------------------------------------------------------------------

test("Adversarial 5.1: Missing POSITION across all 4 rows of an employee hard-blocks all rows", () => {
  const batch = [1, 2, 3, 4].map((num) => ({
    EMPLOYEE_NO: "EMP-NO-POSITION-AT-ALL",
    LAST_NAME: "AGUINALDO",
    FIRST_NAME: "EMILIO",
    MIDDLE_NAME: "FAMY",
    DATE_HIRED: "2026-01-15",
    VCODE: `STORE-${num}`,
    POSITION: num % 2 === 0 ? "" : "   ", // blanks and spaces
  }));

  const result = coalescePlantillaBatch(batch);
  const posErrors = result.errors.filter((e) => e.conflictType === "position_required");
  assert.equal(posErrors.length, 4, "Every row must be hard-blocked when position is blank across all rows");
});

test("Adversarial 5.2: Populated POSITION on only 1 row of a 4-row roving employee coalesces to all rows", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-POS-ROW2",
      LAST_NAME: "LUNA",
      FIRST_NAME: "ANTONIO",
      MIDDLE_NAME: "NOVICIO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-1",
      POSITION: "", // blank
    },
    {
      EMPLOYEE_NO: "EMP-POS-ROW2",
      LAST_NAME: "LUNA",
      FIRST_NAME: "ANTONIO",
      MIDDLE_NAME: "NOVICIO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-2",
      POSITION: "Commanding Officer", // populated on row 2
    },
    {
      EMPLOYEE_NO: "EMP-POS-ROW2",
      LAST_NAME: "LUNA",
      FIRST_NAME: "ANTONIO",
      MIDDLE_NAME: "NOVICIO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-3",
      POSITION: "", // blank
    },
    {
      EMPLOYEE_NO: "EMP-POS-ROW2",
      LAST_NAME: "LUNA",
      FIRST_NAME: "ANTONIO",
      MIDDLE_NAME: "NOVICIO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-4",
      POSITION: "", // blank
    },
  ];

  const result = coalescePlantillaBatch(batch);
  assert.equal(result.errors.length, 0, "Should not error when at least one row has a valid position");

  for (let i = 0; i < 4; i++) {
    assert.equal(result.coalescedRows[i].POSITION, "COMMANDING OFFICER");
  }
});

test("Adversarial 5.3: Conflicting POSITION across rows emits conflict_position warning and last row wins", () => {
  const batch = [
    {
      EMPLOYEE_NO: "EMP-POS-CONFLICT",
      LAST_NAME: "LUNA",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "NOVICIO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-1",
      POSITION: "Junior Artist",
    },
    {
      EMPLOYEE_NO: "EMP-POS-CONFLICT",
      LAST_NAME: "LUNA",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "NOVICIO",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-2",
      POSITION: "Master Painter", // conflicting position
    },
  ];

  const result = coalescePlantillaBatch(batch);
  assert.equal(result.errors.length, 0); // non-blocking

  const posFlag = result.flags.find((f) => f.flag === "conflict_position");
  assert.ok(posFlag, "Warning flag conflict_position must be emitted");
  assert.match(posFlag.msg, /MASTER PAINTER/);

  assert.equal(result.coalescedRows[0].POSITION, "MASTER PAINTER");
  assert.equal(result.coalescedRows[1].POSITION, "MASTER PAINTER");
});


// ----------------------------------------------------------------------------
// 6. Adversarial Vulnerability Reproductions
// ----------------------------------------------------------------------------

test("Adversarial 6.1 [REMEDIATED]: Hyphenated DATE_HIRED normalizes to ISO and avoids false core_identity_mismatch", () => {
  // Hyphenated MM-DD-YYYY matches dashMatch and normalizes cleanly to YYYY-MM-DD
  // without date corruption or false core_identity_mismatch_in_batch.
  const batch = [
    {
      EMPLOYEE_NO: "EMP-VULN-DATE",
      LAST_NAME: "VALENZUELA",
      FIRST_NAME: "PIO",
      MIDDLE_NAME: "ALEJANDRINO",
      DATE_HIRED: "2026-01-15", // ISO
      VCODE: "STORE-1",
      POSITION: "Physician",
    },
    {
      EMPLOYEE_NO: "EMP-VULN-DATE",
      LAST_NAME: "VALENZUELA",
      FIRST_NAME: "PIO",
      MIDDLE_NAME: "ALEJANDRINO",
      DATE_HIRED: "01-15-2026", // Hyphenated MM-DD-YYYY
      VCODE: "STORE-2",
      POSITION: "Physician",
    },
  ];

  const result = coalescePlantillaBatch(batch);
  const err = result.errors.find((e) => e.field === "DATE_HIRED");
  assert.equal(err, undefined, "Hyphenated DATE_HIRED normalizes cleanly without core_identity_mismatch");
  assert.equal(result.errors.length, 0);
  assert.equal(result.coalescedRows[0].DATE_HIRED, "2026-01-15");
  assert.equal(result.coalescedRows[1].DATE_HIRED, "2026-01-15");
});

test("Adversarial 6.2 [REMEDIATED]: BIRTHDATE column alias coalesces cleanly across blank rows", () => {
  // When an uploaded spreadsheet uses header BIRTHDATE (allowed in PLANTILLA_OPTIONAL_HEADERS),
  // blank rows inherit the birth date.
  const batch = [
    {
      EMPLOYEE_NO: "EMP-VULN-BIRTHDATE",
      LAST_NAME: "JACINTO",
      FIRST_NAME: "EMILIO",
      MIDDLE_NAME: "DIZON",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-1",
      POSITION: "Auditor",
      BIRTHDATE: "1995-12-15",
    },
    {
      EMPLOYEE_NO: "EMP-VULN-BIRTHDATE",
      LAST_NAME: "JACINTO",
      FIRST_NAME: "EMILIO",
      MIDDLE_NAME: "DIZON",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-2",
      POSITION: "Auditor",
      BIRTHDATE: "", // blank
    },
  ];

  const result = coalescePlantillaBatch(batch);
  assert.equal(result.coalescedRows[1].BIRTHDATE, "1995-12-15", "BIRTHDATE alias coalesces to blank sibling rows");
  assert.equal(result.coalescedRows[1].DATE_OF_BIRTH, "1995-12-15");
});

test("Adversarial 6.3 [REMEDIATED]: CONTACT column alias coalesces cleanly across blank rows", () => {
  // When an uploaded spreadsheet uses header CONTACT, blank rows inherit the contact number.
  const batch = [
    {
      EMPLOYEE_NO: "EMP-VULN-CONTACT",
      LAST_NAME: "TEODORO",
      FIRST_NAME: "TORIBIO",
      MIDDLE_NAME: "NA",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-1",
      POSITION: "Manager",
      CONTACT: "09179998888",
    },
    {
      EMPLOYEE_NO: "EMP-VULN-CONTACT",
      LAST_NAME: "TEODORO",
      FIRST_NAME: "TORIBIO",
      MIDDLE_NAME: "NA",
      DATE_HIRED: "2026-01-15",
      VCODE: "STORE-2",
      POSITION: "Manager",
      CONTACT: "", // blank
    },
  ];

  const result = coalescePlantillaBatch(batch);
  assert.equal(result.coalescedRows[1].CONTACT, "09179998888", "CONTACT alias coalesces to blank sibling rows");
  assert.equal(result.coalescedRows[1].CONTACT_NO, "09179998888");
});

// ----------------------------------------------------------------------------
// 7. Bi-Directional Identity Invariants (Same Full Name = Same EMPLOYEE_NO)
// ----------------------------------------------------------------------------

test("Adversarial 7.1: Identical full name with differing EMPLOYEE_NO (e.g. 2060-001 vs 2060-005) is hard-blocked", () => {
  // Real user failure case: Gracelyn Benitez Rosales entered on Row 1 as 2060-001
  // and on Row 2 as 2060-005 due to encoder employee number mistype.
  const batch = [
    {
      EMPLOYEE_NO: "2060-001",
      LAST_NAME: "ROSALES",
      FIRST_NAME: "GRACELYN",
      MIDDLE_NAME: "BENITEZ",
      DATE_HIRED: "2026-01-15",
      VCODE: "MADAM001",
      STORE_NAME: "Puregold Marikina",
      POSITION: "Merchandiser",
      RATE: "800",
      CIVIL_STATUS: "SINGLE",
      DATE_OF_BIRTH: "2004-10-10",
      CONTACT_NO: "9632448685",
      ADDRESS: "BLOCK 7 LOT 607 BAGONG SILANG SUCAT MUNTINLUPA",
      SCHEDULE_DAYS: "MON-SAT",
      DAYOFF: "SUN",
    },
    {
      EMPLOYEE_NO: "2060-005", // Mismatched/mistyped employee number for same person
      LAST_NAME: "ROSALES",
      FIRST_NAME: "GRACELYN",
      MIDDLE_NAME: "BENITEZ",
      DATE_HIRED: "2026-01-15",
      VCODE: "MADAM002",
      STORE_NAME: "Puregold Zabarte",
      POSITION: "Merchandiser",
      RATE: "800",
      CIVIL_STATUS: "SINGLE",
      DATE_OF_BIRTH: "2004-10-10",
      CONTACT_NO: "9632448685",
      ADDRESS: "BLOCK 7 LOT 607 BAGONG SILANG SUCAT MUNTINLUPA",
      SCHEDULE_DAYS: "MON-SAT",
      DAYOFF: "SUN",
    },
  ];

  const result = coalescePlantillaBatch(batch);
  const dupErrors = result.errors.filter((e) => e.conflictType === "duplicate_identity_distinct_emp_no");

  assert.equal(dupErrors.length, 2, "Both rows must be flagged with duplicate_identity_distinct_emp_no error");
  assert.equal(dupErrors[0].rowNumber, 1);
  assert.equal(dupErrors[1].rowNumber, 2);
  assert.match(dupErrors[0].msg, /ROSALES, GRACELYN BENITEZ/);
  assert.match(dupErrors[0].msg, /2060-001/);
  assert.match(dupErrors[0].msg, /2060-005/);
});

test("Adversarial 7.2: Legitimate roving employee sharing same EMPLOYEE_NO passes identity checks", () => {
  const batch = [
    {
      EMPLOYEE_NO: "2060-001",
      LAST_NAME: "ROSALES",
      FIRST_NAME: "GRACELYN",
      MIDDLE_NAME: "BENITEZ",
      DATE_HIRED: "2026-01-15",
      VCODE: "MADAM001",
      POSITION: "Merchandiser",
      RATE: "800",
      DATE_OF_BIRTH: "2004-10-10",
    },
    {
      EMPLOYEE_NO: "2060-001", // Correct identical employee number
      LAST_NAME: "ROSALES",
      FIRST_NAME: "GRACELYN",
      MIDDLE_NAME: "BENITEZ",
      DATE_HIRED: "2026-01-15",
      VCODE: "MADAM002",
      POSITION: "Merchandiser",
      RATE: "800",
      DATE_OF_BIRTH: "2004-10-10",
    },
  ];

  const result = coalescePlantillaBatch(batch);
  const dupErrors = result.errors.filter((e) => e.conflictType === "duplicate_identity_distinct_emp_no");
  assert.equal(dupErrors.length, 0, "No duplicate identity error when EMPLOYEE_NO is identical");
  assert.equal(result.errors.length, 0);
});
