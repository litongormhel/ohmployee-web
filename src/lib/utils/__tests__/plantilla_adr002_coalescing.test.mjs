import test from "node:test";
import assert from "node:assert/strict";

import {
  computeAgeAtHire,
  normalizePlantillaRow,
} from "../plantilla_normalization.ts";

import {
  PLANTILLA_BASELINE_STORE_HEADERS,
  PLANTILLA_EMPLOYEE_HEADERS,
  PLANTILLA_OPTIONAL_HEADERS,
  PLANTILLA_SAMPLE_ROW,
  PLANTILLA_SAMPLE_ROW_2,
} from "../data_control_xlsx.ts";

import fs from "node:fs";
import path from "node:path";

// ============================================================================
// Authoritative ADR-002 Addendum Coalescing & Invariant Evaluation Oracle
// Derived strictly from ORIGINAL_REQUEST.md (§R2, §R3) and PROJECT.md (§Interface Contracts)
// ============================================================================

/**
 * Authoritative reference evaluator executing the ADR-002 Addendum multi-row
 * coalescing, identity verification, and 18+ invariant checks matching the
 * PostgreSQL _evaluate_plantilla_import_rows specification.
 */
function evaluatePlantillaBatchSpec(rawRows, dbMasterRecords = {}) {
  // Step 1: Pre-validation row-level normalization
  const normalizedRows = rawRows.map(normalizePlantillaRow);

  const rowsOut = [];
  const empGroups = {};

  // Group by EMPLOYEE_NO
  normalizedRows.forEach((row, idx) => {
    const rowNum = idx + 1;
    const empNo = (row.EMPLOYEE_NO ?? "").trim().toUpperCase();
    if (empNo) {
      if (!empGroups[empNo]) empGroups[empNo] = [];
      empGroups[empNo].push({ row, rowNum });
    }
  });

  // Evaluate each row
  normalizedRows.forEach((row, idx) => {
    const rowNum = idx + 1;
    const empNo = (row.EMPLOYEE_NO ?? "").trim().toUpperCase();
    const errors = [];
    const flags = [];
    const coalesced = { ...row };

    if (!empNo) {
      // Vacant store slot: verify required position
      if (!row.POSITION || !row.POSITION.trim()) {
        errors.push({
          field: "POSITION",
          conflictType: "missing_position",
          msg: "Position is required for store slot.",
        });
      }
      rowsOut.push({
        rowNumber: rowNum,
        employeeNo: "",
        validationStatus: errors.length > 0 ? "blocked" : "valid",
        validationErrors: errors,
        validationFlags: flags,
        coalesced,
      });
      return;
    }

    const group = empGroups[empNo] ?? [];

    // Rule 1: All occupied rows must have core identity populated
    const coreMissing = [];
    if (!row.LAST_NAME?.trim()) coreMissing.push("LAST_NAME");
    if (!row.FIRST_NAME?.trim()) coreMissing.push("FIRST_NAME");
    if (!row.MIDDLE_NAME?.trim()) coreMissing.push("MIDDLE_NAME");
    if (!row.DATE_HIRED?.trim()) coreMissing.push("DATE_HIRED");

    if (coreMissing.length > 0) {
      errors.push({
        field: "CORE_IDENTITY",
        conflictType: "missing_core_identity",
        msg: `Core identity fields missing for employee ${empNo}: ${coreMissing.join(", ")}`,
      });
    }

    // Rule 2: Intra-file core identity mismatch across rows
    const distinctLast = new Set(group.map((g) => g.row.LAST_NAME?.trim()).filter(Boolean));
    const distinctFirst = new Set(group.map((g) => g.row.FIRST_NAME?.trim()).filter(Boolean));
    const distinctMiddle = new Set(group.map((g) => g.row.MIDDLE_NAME?.trim()).filter(Boolean));
    const distinctHired = new Set(group.map((g) => g.row.DATE_HIRED?.trim()).filter(Boolean));

    if (
      distinctLast.size > 1 ||
      distinctFirst.size > 1 ||
      distinctMiddle.size > 1 ||
      distinctHired.size > 1
    ) {
      errors.push({
        field: "CORE_IDENTITY",
        conflictType: "intra_file_identity_mismatch",
        msg: `Core identity mismatch across rows for EMPLOYEE_NO ${empNo}. All rows must have identical names and hire date.`,
      });
    }

    // Rule 3: DB Master cross-check
    const dbRecord = dbMasterRecords[empNo];
    if (dbRecord) {
      if (
        dbRecord.status === "Inactive" ||
        dbRecord.status === "Rejected Deactivation"
      ) {
        errors.push({
          field: "EMPLOYEE_NO",
          conflictType: "inactive_or_archived_existing_record",
          msg: `Employee ${empNo} exists in DB with inactive/archived status (${dbRecord.status}). Import blocked.`,
        });
      } else {
        const dbLast = (dbRecord.last_name ?? "").trim().toUpperCase();
        const dbFirst = (dbRecord.first_name ?? "").trim().toUpperCase();
        const dbMiddle = (dbRecord.middle_name ?? "").trim().toUpperCase();
        const dbHired = (dbRecord.date_hired ?? "").trim();

        if (
          (row.LAST_NAME && row.LAST_NAME !== dbLast) ||
          (row.FIRST_NAME && row.FIRST_NAME !== dbFirst) ||
          (row.MIDDLE_NAME && row.MIDDLE_NAME !== dbMiddle) ||
          (row.DATE_HIRED && row.DATE_HIRED !== dbHired)
        ) {
          errors.push({
            field: "CORE_IDENTITY",
            conflictType: "db_master_identity_mismatch",
            msg: `Core identity mismatch against DB master record for EMPLOYEE_NO ${empNo}.`,
          });
        }
      }
    }

    // Rule 4: Employee Demographics, Compensation & Rest Day Coalescing
    const coalesceFields = [
      "CIVIL_STATUS",
      "DATE_OF_BIRTH",
      "CONTACT_NO",
      "ADDRESS",
      "RATE",
      "DAYOFF",
    ];

    coalesceFields.forEach((field) => {
      const nonBlankVals = group
        .map((g) => g.row[field]?.trim())
        .filter((v) => Boolean(v));

      const distinctVals = Array.from(new Set(nonBlankVals));
      if (distinctVals.length === 1) {
        // Silent auto-fill across blank rows
        coalesced[field] = distinctVals[0];
      } else if (distinctVals.length > 1) {
        // Conflicting non-blank values: last-row-wins + warning flag
        const lastVal = nonBlankVals[nonBlankVals.length - 1];
        coalesced[field] = lastVal;
        flags.push({
          flag: `conflict_${field.toLowerCase()}`,
          conflictType: `conflict_${field.toLowerCase()}`,
          msg: `Conflicting ${field} in batch for ${empNo}; last non-blank value "${lastVal}" will be used.`,
        });
      }
    });

    // Rule 5: Role & Position Invariant
    const positions = group
      .map((g) => g.row.POSITION?.trim())
      .filter((v) => Boolean(v));
    const distinctPos = Array.from(new Set(positions));

    if (distinctPos.length === 0) {
      errors.push({
        field: "POSITION",
        conflictType: "missing_position",
        msg: `POSITION is blank across all rows for employee ${empNo}.`,
      });
    } else if (distinctPos.length === 1) {
      coalesced.POSITION = distinctPos[0];
    } else {
      const lastPos = positions[positions.length - 1];
      coalesced.POSITION = lastPos;
      flags.push({
        flag: "conflict_position",
        conflictType: "conflict_position",
        msg: `Conflicting POSITION in batch for ${empNo}; last value "${lastPos}" will be used.`,
      });
    }

    // Rule 6: 18+ Minimum Age Invariant Relative to DATE_HIRED
    const dob = coalesced.DATE_OF_BIRTH;
    const hired = coalesced.DATE_HIRED;
    if (dob && hired) {
      const age = computeAgeAtHire(dob, hired);
      if (age !== null && age < 18) {
        errors.push({
          field: "DATE_OF_BIRTH",
          conflictType: "underage_employee_under_18",
          msg: `Underage employee ${empNo}: computed age as of DATE_HIRED (${hired}) is ${age} years old (DOB: ${dob}). Minimum legal working age is 18.`,
        });
      }
    }

    const validationStatus =
      errors.length > 0 ? "blocked" : flags.length > 0 ? "flagged" : "valid";

    rowsOut.push({
      rowNumber: rowNum,
      employeeNo: empNo,
      validationStatus,
      validationErrors: errors,
      validationFlags: flags,
      coalesced,
    });
  });

  // Calculate final persisted employee-level records using last-row-wins aggregation
  const persistedEmployees = {};
  Object.entries(empGroups).forEach(([empNo, group]) => {
    // Phase B loop uses ORDER BY row_number DESC [1]
    const sortedDesc = [...group].sort((a, b) => b.rowNum - a.rowNum);

    const pickLastNonBlank = (field) => {
      for (const item of sortedDesc) {
        const val = item.row[field]?.trim();
        if (val) return val;
      }
      return "";
    };

    persistedEmployees[empNo] = {
      employee_no: empNo,
      last_name: pickLastNonBlank("LAST_NAME"),
      first_name: pickLastNonBlank("FIRST_NAME"),
      middle_name: pickLastNonBlank("MIDDLE_NAME"),
      date_hired: pickLastNonBlank("DATE_HIRED"),
      civil_status: pickLastNonBlank("CIVIL_STATUS"),
      birthdate: pickLastNonBlank("DATE_OF_BIRTH"),
      contact_number: pickLastNonBlank("CONTACT_NO"),
      address: pickLastNonBlank("ADDRESS"),
      position: pickLastNonBlank("POSITION"),
      rate: pickLastNonBlank("RATE"),
      dayoff: pickLastNonBlank("DAYOFF"),
    };
  });

  const blockedRows = rowsOut.filter((r) => r.validationStatus === "blocked").length;
  const flaggedRows = rowsOut.filter((r) => r.validationStatus === "flagged").length;
  const validRows = rowsOut.filter((r) => r.validationStatus === "valid").length;

  return {
    blockedRows,
    flaggedRows,
    validRows,
    rows: rowsOut,
    persistedEmployees,
  };
}

// ============================================================================
// Feature 6: Core Identity Strict Matching (Intra-File & DB Master) (R2)
// ============================================================================

test("F6 Tier 1.1: Intra-file mismatch in LAST_NAME across rows for same EMPLOYEE_NO hard-blocks batch", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA ROSA", // Mismatched LAST_NAME
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 2);
  assert.equal(result.rows[0].validationStatus, "blocked");
  assert.equal(result.rows[1].validationStatus, "blocked");
  assert.match(result.rows[0].validationErrors[0].conflictType ?? "", /intra_file_identity_mismatch/);
});

test("F6 Tier 1.2: Intra-file mismatch in FIRST_NAME across rows for same EMPLOYEE_NO hard-blocks batch", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "PEDRO", // Mismatched FIRST_NAME
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 2);
  assert.match(result.rows[0].validationErrors[0].conflictType ?? "", /intra_file_identity_mismatch/);
});

test("F6 Tier 1.3: Intra-file mismatch in MIDDLE_NAME across rows for same EMPLOYEE_NO hard-blocks batch", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "GARCIA", // Mismatched MIDDLE_NAME
      DATE_HIRED: "2026-01-15",
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 2);
  assert.match(result.rows[0].validationErrors[0].conflictType ?? "", /intra_file_identity_mismatch/);
});

test("F6 Tier 1.4: Intra-file mismatch in DATE_HIRED across rows for same EMPLOYEE_NO hard-blocks batch", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-02-01", // Mismatched DATE_HIRED
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 2);
  assert.match(result.rows[0].validationErrors[0].conflictType ?? "", /intra_file_identity_mismatch/);
});

test("F6 Tier 1.5: Matching core identity across multiple store rows passes validation without errors", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.validRows, 2);
  assert.equal(result.rows[0].validationStatus, "valid");
  assert.equal(result.rows[1].validationStatus, "valid");
});

test("F6 Tier 2.1 (Boundary): Missing core identity on one row of multi-row roving employee hard-blocks batch", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "", // Blank LAST_NAME on occupied row
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.ok(result.blockedRows >= 1);
  assert.equal(result.rows[1].validationStatus, "blocked");
  assert.match(result.rows[1].validationErrors[0].conflictType ?? "", /missing_core_identity/);
});

test("F6 Tier 2.2 (Boundary): DB Master mismatch against active plantilla record hard-blocks with db_master_identity_mismatch", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
  ];

  const dbMaster = {
    "EMP-001": {
      employee_no: "EMP-001",
      last_name: "DELA CRUZ",
      first_name: "JUANITO", // DB has JUANITO, import has JUAN
      middle_name: "SANTOS",
      date_hired: "2026-01-15",
      status: "Active",
    },
  };

  const result = evaluatePlantillaBatchSpec(rows, dbMaster);
  assert.equal(result.blockedRows, 1);
  assert.match(result.rows[0].validationErrors[0].conflictType ?? "", /db_master_identity_mismatch/);
});

test("F6 Tier 2.3 (Boundary): DB Master match against active record passes validation cleanly", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
  ];

  const dbMaster = {
    "EMP-001": {
      employee_no: "EMP-001",
      last_name: "DELA CRUZ",
      first_name: "JUAN",
      middle_name: "SANTOS",
      date_hired: "2026-01-15",
      status: "Active",
    },
  };

  const result = evaluatePlantillaBatchSpec(rows, dbMaster);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.validRows, 1);
});

test("F6 Tier 2.4 (Boundary): Existing DB record with Inactive status hard-blocks with inactive_or_archived_existing_record", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
  ];

  const dbMaster = {
    "EMP-001": {
      employee_no: "EMP-001",
      last_name: "DELA CRUZ",
      first_name: "JUAN",
      middle_name: "SANTOS",
      date_hired: "2026-01-15",
      status: "Inactive", // Inactive status
    },
  };

  const result = evaluatePlantillaBatchSpec(rows, dbMaster);
  assert.equal(result.blockedRows, 1);
  assert.match(
    result.rows[0].validationErrors[0].conflictType ?? "",
    /inactive_or_archived_existing_record/
  );
});

test("F6 Tier 2.5 (Boundary): Existing DB record with Rejected Deactivation status hard-blocks", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
  ];

  const dbMaster = {
    "EMP-001": {
      employee_no: "EMP-001",
      last_name: "DELA CRUZ",
      first_name: "JUAN",
      middle_name: "SANTOS",
      date_hired: "2026-01-15",
      status: "Rejected Deactivation",
    },
  };

  const result = evaluatePlantillaBatchSpec(rows, dbMaster);
  assert.equal(result.blockedRows, 1);
  assert.match(
    result.rows[0].validationErrors[0].conflictType ?? "",
    /inactive_or_archived_existing_record/
  );
});

test("F6 Tier 2.6 (Boundary): Multiple employees with independent IDs evaluated independently without crosstalk", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-002",
      LAST_NAME: "RAMOS",
      FIRST_NAME: "MARIA",
      MIDDLE_NAME: "GARCIA",
      DATE_HIRED: "2026-02-01",
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Cashier",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.validRows, 2);
});

// ============================================================================
// Feature 7: Demographics & Rate Coalescing Matrix (R2)
// ============================================================================

test("F7 Tier 1.1: Silent auto-fill of blank CIVIL_STATUS from non-blank sibling row without warning", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      CIVIL_STATUS: "SINGLE", // Provided on row 1
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      CIVIL_STATUS: "", // Blank on row 2
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.flaggedRows, 0);
  assert.equal(result.rows[1].coalesced.CIVIL_STATUS, "SINGLE");
  assert.equal(result.persistedEmployees["EMP-001"].civil_status, "SINGLE");
});

test("F7 Tier 1.2: Silent auto-fill of blank RATE from non-blank sibling row without warning", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      RATE: "610.00",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      RATE: "",
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.flaggedRows, 0);
  assert.equal(result.rows[1].coalesced.RATE, "610.00");
  assert.equal(result.persistedEmployees["EMP-001"].rate, "610.00");
});

test("F7 Tier 1.3: Silent auto-fill of blank DAYOFF from non-blank sibling row without warning", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      DAYOFF: "SUN",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      DAYOFF: "",
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.flaggedRows, 0);
  assert.equal(result.rows[1].coalesced.DAYOFF, "SUN");
  assert.equal(result.persistedEmployees["EMP-001"].dayoff, "SUN");
});

test("F7 Tier 1.4: Silent auto-fill of blank CONTACT_NO and ADDRESS across blank sibling rows", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      CONTACT_NO: "09171234567",
      ADDRESS: "123 MacArthur Hwy Angeles",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      CONTACT_NO: "",
      ADDRESS: "",
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.rows[1].coalesced.CONTACT_NO, "09171234567");
  assert.equal(result.rows[1].coalesced.ADDRESS, "123 MACARTHUR HWY ANGELES");
});

test("F7 Tier 1.5: Conflicting non-blank RATE across rows emits warning flag conflict_rate and resolves last-row-wins", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      RATE: "610.00", // Row 1 rate
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      RATE: "650.00", // Row 2 rate (conflict!)
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0); // Non-blocking!
  assert.equal(result.flaggedRows, 2);
  assert.equal(result.rows[0].validationStatus, "flagged");
  assert.equal(result.rows[1].validationStatus, "flagged");
  assert.match(result.rows[0].validationFlags[0].flag ?? "", /conflict_rate/);
  // Last row value wins
  assert.equal(result.rows[0].coalesced.RATE, "650.00");
  assert.equal(result.rows[1].coalesced.RATE, "650.00");
  assert.equal(result.persistedEmployees["EMP-001"].rate, "650.00");
});

test("F7 Tier 2.1 (Boundary): Conflicting non-blank CIVIL_STATUS emits warning flag conflict_civil_status and resolves last-row-wins", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      CIVIL_STATUS: "SINGLE",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      CIVIL_STATUS: "MARRIED", // Conflict!
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.match(result.rows[0].validationFlags[0].flag ?? "", /conflict_civil_status/);
  assert.equal(result.persistedEmployees["EMP-001"].civil_status, "MARRIED");
});

test("F7 Tier 2.2 (Boundary): Conflicting non-blank DAYOFF emits warning flag conflict_dayoff and resolves last-row-wins", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      DAYOFF: "SUN",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      DAYOFF: "SAT, SUN", // Conflict!
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.match(result.rows[0].validationFlags[0].flag ?? "", /conflict_dayoff/);
  assert.equal(result.persistedEmployees["EMP-001"].dayoff, "SAT, SUN");
});

test("F7 Tier 2.3 (Boundary): 3-row roving employee (Row 1 value A, Row 2 blank, Row 3 value B) resolves to B with conflict warning", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      RATE: "610.00", // Value A
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      RATE: "", // Blank
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      RATE: "675.00", // Value B (last non-blank!)
      VCODE: "V-003",
      STORE_NAME: "Store C",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.flaggedRows, 3);
  assert.equal(result.persistedEmployees["EMP-001"].rate, "675.00");
});

test("F7 Tier 2.4 (Boundary): Identical non-blank demographic values across all rows emit NO conflict warning", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      CIVIL_STATUS: "SINGLE",
      RATE: "610.00",
      DAYOFF: "SUN",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      CIVIL_STATUS: "SINGLE",
      RATE: "610.00",
      DAYOFF: "SUN",
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.flaggedRows, 0);
  assert.equal(result.validRows, 2);
});

test("F7 Tier 2.5 (Boundary): Completely blank demographic values across all rows remain empty without error", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      CIVIL_STATUS: "",
      DATE_OF_BIRTH: "",
      CONTACT_NO: "",
      ADDRESS: "",
      RATE: "",
      DAYOFF: "",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.validRows, 1);
  assert.equal(result.persistedEmployees["EMP-001"].civil_status, "");
  assert.equal(result.persistedEmployees["EMP-001"].rate, "");
});

// ============================================================================
// Feature 8: Position Validation & Role Invariant (R2)
// ============================================================================

test("F8 Tier 1.1: Valid POSITION on all rows passes validation", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.validRows, 1);
});

test("F8 Tier 1.2: Hard-block when POSITION is blank across ALL rows for an employee", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "", // Blank on row 1
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "", // Blank on row 2
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 2);
  assert.match(result.rows[0].validationErrors[0].conflictType ?? "", /missing_position/);
});

test("F8 Tier 1.3: Silent auto-fill of POSITION across blank sibling rows when 1 row is populated", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser", // Populated
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "", // Blank, will auto-fill
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.validRows, 2);
  assert.equal(result.rows[1].coalesced.POSITION, "MERCHANDISER");
  assert.equal(result.persistedEmployees["EMP-001"].position, "MERCHANDISER");
});

test("F8 Tier 1.4: Conflicting POSITION across rows emits warning flag conflict_position and resolves last-row-wins", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Promodiser", // Conflicting position
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.flaggedRows, 2);
  assert.match(result.rows[0].validationFlags[0].flag ?? "", /conflict_position/);
  assert.equal(result.persistedEmployees["EMP-001"].position, "PROMODISER");
});

test("F8 Tier 1.5: Vacant store slot (blank EMPLOYEE_NO) with non-blank POSITION passes validation", () => {
  const rows = [
    {
      EMPLOYEE_NO: "",
      LAST_NAME: "",
      FIRST_NAME: "",
      MIDDLE_NAME: "",
      DATE_HIRED: "",
      VCODE: "V-VACANT-001",
      STORE_NAME: "Store Vacant",
      POSITION: "Cashier",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.validRows, 1);
});

test("F8 Tier 2.1 (Boundary): Whitespace-only POSITION across all rows is treated as blank and hard-blocks", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "   \t  ",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 1);
  assert.match(result.rows[0].validationErrors[0].conflictType ?? "", /missing_position/);
});

test("F8 Tier 2.2 (Boundary): Blank RATE across all rows passes validation (rate is optional)", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
      RATE: "",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.validRows, 1);
});

test("F8 Tier 2.3 (Boundary): Simultaneous auto-fill of POSITION and RATE across blank store rows", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
      RATE: "610.00",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "", // Blank position
      RATE: "", // Blank rate
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.validRows, 2);
  assert.equal(result.rows[1].coalesced.POSITION, "MERCHANDISER");
  assert.equal(result.rows[1].coalesced.RATE, "610.00");
});

test("F8 Tier 2.4 (Boundary): Roving employee across 4 stores with position on only 1 store auto-fills all 4 allocations", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store 1",
      POSITION: "Senior Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-002",
      STORE_NAME: "Store 2",
      POSITION: "",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-003",
      STORE_NAME: "Store 3",
      POSITION: "",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-004",
      STORE_NAME: "Store 4",
      POSITION: "",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.validRows, 4);
  assert.equal(result.rows[1].coalesced.POSITION, "SENIOR MERCHANDISER");
  assert.equal(result.rows[2].coalesced.POSITION, "SENIOR MERCHANDISER");
  assert.equal(result.rows[3].coalesced.POSITION, "SENIOR MERCHANDISER");
});

test("F8 Tier 2.5 (Boundary): Normalization ensures case variations in POSITION do not cause spurious conflicts", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-001",
      STORE_NAME: "Store 1",
      POSITION: "merchandiser", // Lowercase
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      VCODE: "V-002",
      STORE_NAME: "Store 2",
      POSITION: "  MERCHANDISER  ", // Uppercase with whitespace
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.flaggedRows, 0); // No spurious conflict flag!
  assert.equal(result.validRows, 2);
});

// ============================================================================
// Feature 9: Minimum Age (18+) Invariant Relative to DATE_HIRED (R3)
// ============================================================================

test("F9 Tier 1.1: Employee aged 25 on hire date passes validation", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      DATE_OF_BIRTH: "2001-01-15", // Exactly 25 years old
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.validRows, 1);
});

test("F9 Tier 1.2: Underage employee (age 17 on hire date) hard-blocks with underage_employee_under_18", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      DATE_OF_BIRTH: "2009-01-15", // 17 years old
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 1);
  assert.equal(result.rows[0].validationStatus, "blocked");
  assert.match(
    result.rows[0].validationErrors[0].conflictType ?? "",
    /underage_employee_under_18/
  );
});

test("F9 Tier 1.3: Coalesced birth date on row 1 evaluated for 18+ check on all sibling rows", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      DATE_OF_BIRTH: "1995-05-15", // Adult DOB on row 1
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      DATE_OF_BIRTH: "", // Blank on row 2, will coalesce 1995-05-15
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.validRows, 2);
  assert.equal(result.rows[1].coalesced.DATE_OF_BIRTH, "1995-05-15");
});

test("F9 Tier 1.4: Coalesced underage birth date on row 1 hard-blocks ALL rows for that employee", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      DATE_OF_BIRTH: "2010-06-20", // 15 years old!
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      DATE_OF_BIRTH: "", // Blank on row 2
      VCODE: "V-002",
      STORE_NAME: "Store B",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 2);
  assert.equal(result.rows[0].validationStatus, "blocked");
  assert.equal(result.rows[1].validationStatus, "blocked");
  assert.match(
    result.rows[0].validationErrors[0].conflictType ?? "",
    /underage_employee_under_18/
  );
  assert.match(
    result.rows[1].validationErrors[0].conflictType ?? "",
    /underage_employee_under_18/
  );
});

test("F9 Tier 1.5: Blank DATE_OF_BIRTH across all rows skips 18+ check without error", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      DATE_OF_BIRTH: "", // Blank DOB (optional field)
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.validRows, 1);
});

test("F9 Tier 2.1 (Boundary): Exact 18th birthday on hire date (DOB 2008-01-15, Hire 2026-01-15) passes validation", () => {
  const age = computeAgeAtHire("2008-01-15", "2026-01-15");
  assert.equal(age, 18);

  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      DATE_OF_BIRTH: "2008-01-15", // Exactly 18 years old
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.validRows, 1);
});

test("F9 Tier 2.2 (Boundary): 1 day short of 18th birthday (DOB 2008-01-16, Hire 2026-01-15) hard-blocks as underage", () => {
  const age = computeAgeAtHire("2008-01-16", "2026-01-15");
  assert.equal(age, 17);

  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
      DATE_OF_BIRTH: "2008-01-16", // 17 years 364 days old
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 1);
  assert.match(
    result.rows[0].validationErrors[0].conflictType ?? "",
    /underage_employee_under_18/
  );
});

test("F9 Tier 2.3 (Boundary): Leap day birth date (2004-02-29) evaluated on 2022-02-27 (day before 18th anniversary) hard-blocks", () => {
  const age = computeAgeAtHire("2004-02-29", "2022-02-27");
  assert.equal(age, 17);

  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2022-02-27",
      DATE_OF_BIRTH: "2004-02-29",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 1);
  assert.match(
    result.rows[0].validationErrors[0].conflictType ?? "",
    /underage_employee_under_18/
  );
});

test("F9 Tier 2.4 (Boundary): Leap day birth date (2004-02-29) evaluated on 2022-03-01 (18 years) passes", () => {
  const age = computeAgeAtHire("2004-02-29", "2022-03-01");
  assert.equal(age, 18);

  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2022-03-01",
      DATE_OF_BIRTH: "2004-02-29",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.validRows, 1);
});

test("F9 Tier 2.5 (Boundary): Leap day birth date in leap year (2004-02-29) evaluated on 2024-02-29 (20 years) passes", () => {
  const age = computeAgeAtHire("2004-02-29", "2024-02-29");
  assert.equal(age, 20);

  const rows = [
    {
      EMPLOYEE_NO: "EMP-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2024-02-29",
      DATE_OF_BIRTH: "2004-02-29",
      VCODE: "V-001",
      STORE_NAME: "Store A",
      POSITION: "Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  assert.equal(result.blockedRows, 0);
  assert.equal(result.validRows, 1);
});

test("F9 Tier 2.6 (Boundary): computeAgeAtHire handles invalid or unparseable dates safely returning null", () => {
  assert.equal(computeAgeAtHire("", "2026-01-15"), null);
  assert.equal(computeAgeAtHire("invalid-date", "2026-01-15"), null);
  assert.equal(computeAgeAtHire(null, "2026-01-15"), null);
});

// ============================================================================
// Feature 11: Template Updates & Invariant Documentation (R5)
// ============================================================================

test("F11 Tier 1.1: data_control_xlsx defines PLANTILLA_BASELINE_STORE_HEADERS with 8 required headers", () => {
  assert.equal(PLANTILLA_BASELINE_STORE_HEADERS.length, 8);
  assert.deepEqual([...PLANTILLA_BASELINE_STORE_HEADERS], [
    "GROUP_NAME",
    "ACCOUNT_NAME",
    "MOTHER_ACCOUNT",
    "VCODE",
    "STORE_NAME",
    "AREA_PROVINCE",
    "AREA_CITY",
    "POSITION",
  ]);
});

test("F11 Tier 1.2: data_control_xlsx defines PLANTILLA_EMPLOYEE_HEADERS with 5 conditional identity headers", () => {
  assert.equal(PLANTILLA_EMPLOYEE_HEADERS.length, 5);
  assert.deepEqual([...PLANTILLA_EMPLOYEE_HEADERS], [
    "EMPLOYEE_NO",
    "LAST_NAME",
    "FIRST_NAME",
    "MIDDLE_NAME",
    "DATE_HIRED",
  ]);
});

test("F11 Tier 1.3: data_control_xlsx defines PLANTILLA_OPTIONAL_HEADERS with 10 optional headers", () => {
  assert.equal(PLANTILLA_OPTIONAL_HEADERS.length, 10);
  assert.ok(PLANTILLA_OPTIONAL_HEADERS.includes("CIVIL_STATUS"));
  assert.ok(PLANTILLA_OPTIONAL_HEADERS.includes("RATE"));
  assert.ok(PLANTILLA_OPTIONAL_HEADERS.includes("DATE_OF_BIRTH"));
  assert.ok(PLANTILLA_OPTIONAL_HEADERS.includes("CONTACT_NO"));
  assert.ok(PLANTILLA_OPTIONAL_HEADERS.includes("ADDRESS"));
  assert.ok(PLANTILLA_OPTIONAL_HEADERS.includes("SCHEDULE_DAYS"));
  assert.ok(PLANTILLA_OPTIONAL_HEADERS.includes("SCHEDULE_TIME"));
  assert.ok(PLANTILLA_OPTIONAL_HEADERS.includes("DAYOFF"));
});

test("F11 Tier 1.4: PLANTILLA_SAMPLE_ROW has valid 18+ birthdate relative to hire date", () => {
  // Index 12: DATE_HIRED ("2026-01-15"), Index 15: DATE_OF_BIRTH ("1995-05-15")
  const hired = PLANTILLA_SAMPLE_ROW[12];
  const dob = PLANTILLA_SAMPLE_ROW[15];
  const age = computeAgeAtHire(dob, hired);
  assert.ok(age !== null && age >= 18, `Sample row age ${age} must be >= 18`);
});

test("F11 Tier 1.5: PLANTILLA_SAMPLE_ROW_2 (2050-00002) has valid 18+ birthdate relative to hire date", () => {
  assert.ok(PLANTILLA_SAMPLE_ROW_2, "PLANTILLA_SAMPLE_ROW_2 must be defined");
  // Index 8: EMPLOYEE_NO ("2050-00002"), Index 12: DATE_HIRED ("2026-01-15"), Index 15: DATE_OF_BIRTH ("1998-08-20")
  assert.equal(PLANTILLA_SAMPLE_ROW_2[8], "2050-00002");
  const hired = PLANTILLA_SAMPLE_ROW_2[12];
  const dob = PLANTILLA_SAMPLE_ROW_2[15];
  const age = computeAgeAtHire(dob, hired);
  assert.ok(age !== null && age >= 18, `Sample row 2 age ${age} must be >= 18`);
});

test("F11 Tier 2.1 (Boundary): Invariant Rule #16 (Multi-Row Identity Invariant) is documented in data_control_xlsx", () => {
  const filePath = path.resolve("src/lib/utils/data_control_xlsx.ts");
  const content = fs.readFileSync(filePath, "utf-8");
  assert.ok(
    content.includes("16. Multi-Row Identity Invariant"),
    "VALIDATION_GUIDE must document Rule #16 (Multi-Row Identity Invariant)"
  );
});

test("F11 Tier 2.2 (Boundary): Invariant Rule #17 (Employee-Level Coalescing & Conflict Flag) is documented in data_control_xlsx", () => {
  const filePath = path.resolve("src/lib/utils/data_control_xlsx.ts");
  const content = fs.readFileSync(filePath, "utf-8");
  assert.ok(
    content.includes("17. Employee-Level Coalescing & Conflict Flag"),
    "VALIDATION_GUIDE must document Rule #17 (Employee-Level Coalescing & Conflict Flag)"
  );
});

test("F11 Tier 2.3 (Boundary): Invariant Rule #18 (Minimum Age Enforcement 18+) is documented in data_control_xlsx", () => {
  const filePath = path.resolve("src/lib/utils/data_control_xlsx.ts");
  const content = fs.readFileSync(filePath, "utf-8");
  assert.ok(
    content.includes("18. Minimum Age Enforcement (18+)"),
    "VALIDATION_GUIDE must document Rule #18 (Minimum Age Enforcement 18+)"
  );
});

test("F11 Tier 2.4 (Boundary): Invariant Rule #19 (Canonical Schedule Day Expansion) is documented in data_control_xlsx", () => {
  const filePath = path.resolve("src/lib/utils/data_control_xlsx.ts");
  const content = fs.readFileSync(filePath, "utf-8");
  assert.ok(
    content.includes("19. Canonical Schedule Day Expansion"),
    "VALIDATION_GUIDE must document Rule #19 (Canonical Schedule Day Expansion)"
  );
});

// ============================================================================
// Tier 3: Cross-Feature Combinations
// ============================================================================

test("Tier 3 Cross-Feature 1: Multi-row roving employee with differing rates, duty days overlapping dayoff, and coalesced birth date evaluated for 18+ check", () => {
  const rows = [
    {
      EMPLOYEE_NO: "ROV-001",
      LAST_NAME: "SANTOS",
      FIRST_NAME: "MARIA",
      MIDDLE_NAME: "DELA CRUZ",
      DATE_HIRED: "2026-01-15",
      DATE_OF_BIRTH: "1998-05-15", // Adult (27yo) provided on store 1
      RATE: "610.00",
      SCHEDULE_DAYS: "MON-SAT",
      DAYOFF: "SAT, SUN", // Overlaps with duty days
      VCODE: "STORE-01",
      STORE_NAME: "Store One",
      POSITION: "Roving Merchandiser",
    },
    {
      EMPLOYEE_NO: "ROV-001",
      LAST_NAME: "SANTOS",
      FIRST_NAME: "MARIA",
      MIDDLE_NAME: "DELA CRUZ",
      DATE_HIRED: "2026-01-15",
      DATE_OF_BIRTH: "", // Coalesces from store 1
      RATE: "640.00", // Differing rate on store 2 (conflict warning!)
      SCHEDULE_DAYS: "MON-FRI",
      DAYOFF: "SUN",
      VCODE: "STORE-02",
      STORE_NAME: "Store Two",
      POSITION: "Roving Merchandiser",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);

  // No hard blocks!
  assert.equal(result.blockedRows, 0);
  assert.equal(result.flaggedRows, 2);

  // Rate conflict flag emitted
  assert.match(result.rows[0].validationFlags[0].flag ?? "", /conflict_rate/);

  // Last-row rate wins
  assert.equal(result.persistedEmployees["ROV-001"].rate, "640.00");

  // Birth date coalesced
  assert.equal(result.persistedEmployees["ROV-001"].birthdate, "1998-05-15");

  // Store 1 schedule has SAT carved out from duty days; dayoff coalesces to last row's SUN
  assert.equal(result.rows[0].coalesced.SCHEDULE_DAYS, "MON, TUE, WED, THU, FRI");
  assert.equal(result.rows[0].coalesced.DAYOFF, "SUN");

  // Store 2 schedule preserved
  assert.equal(result.rows[1].coalesced.SCHEDULE_DAYS, "MON, TUE, WED, THU, FRI");
  assert.equal(result.rows[1].coalesced.DAYOFF, "SUN");
});

test("Tier 3 Cross-Feature 2: Roving employee with unnormalized strings, phone with punctuation, and dates: normalization prevents false identity/contact conflicts", () => {
  const rows = [
    {
      EMPLOYEE_NO: "rov-999",
      LAST_NAME: "  santos  ",
      FIRST_NAME: "  maria  ",
      MIDDLE_NAME: "  dela   cruz  ",
      DATE_HIRED: "01/15/2026",
      CONTACT_NO: "+63 (917) 111-2222",
      VCODE: "V-101",
      STORE_NAME: "Store Alpha",
      POSITION: "merchandiser",
    },
    {
      EMPLOYEE_NO: "ROV-999",
      LAST_NAME: "SANTOS",
      FIRST_NAME: "MARIA",
      MIDDLE_NAME: "DELA CRUZ",
      DATE_HIRED: "2026-01-15",
      CONTACT_NO: "0917-111-2222",
      VCODE: "V-102",
      STORE_NAME: "Store Beta",
      POSITION: "MERCHANDISER",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  // Zero errors, zero flags!
  assert.equal(result.blockedRows, 0);
  assert.equal(result.flaggedRows, 0);
  assert.equal(result.validRows, 2);
  assert.equal(result.persistedEmployees["ROV-999"].contact_number, "09171112222");
});

test("Tier 3 Cross-Feature 3: Batch Approval persistence simulation verifies that last-row-wins values are committed to public.plantilla", () => {
  const rows = [
    {
      EMPLOYEE_NO: "EMP-PERSIST",
      LAST_NAME: "GARCIA",
      FIRST_NAME: "ROBERTO",
      MIDDLE_NAME: "CRUZ",
      DATE_HIRED: "2026-01-15",
      CIVIL_STATUS: "SINGLE",
      RATE: "600.00",
      DAYOFF: "SUN",
      VCODE: "V-A",
      STORE_NAME: "Store A",
      POSITION: "Associate",
    },
    {
      EMPLOYEE_NO: "EMP-PERSIST",
      LAST_NAME: "GARCIA",
      FIRST_NAME: "ROBERTO",
      MIDDLE_NAME: "CRUZ",
      DATE_HIRED: "2026-01-15",
      CIVIL_STATUS: "MARRIED",
      RATE: "650.00",
      DAYOFF: "SAT, SUN",
      VCODE: "V-B",
      STORE_NAME: "Store B",
      POSITION: "Lead Associate",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rows);
  const persisted = result.persistedEmployees["EMP-PERSIST"];

  // Last row must win across all employee-level fields
  assert.equal(persisted.civil_status, "MARRIED");
  assert.equal(persisted.rate, "650.00");
  assert.equal(persisted.dayoff, "SAT, SUN");
  assert.equal(persisted.position, "LEAD ASSOCIATE");
});

// ============================================================================
// Tier 4: Real-World Application Scenarios
// ============================================================================

test("Tier 4 Scenario A: 3-Store Roving Merchandiser across Metro Manila (clean operational file, silent auto-fill, distinct schedules, zero errors)", () => {
  const rovingBatch = [
    {
      GROUP_NAME: "GROUP 1",
      ACCOUNT_NAME: "SM RETAIL",
      MOTHER_ACCOUNT: "SM RETAIL",
      VCODE: "SM-MEGA-001",
      STORE_NAME: "SM Megamall",
      AREA_PROVINCE: "Metro Manila",
      AREA_CITY: "Mandaluyong",
      POSITION: "Roving Merchandiser",
      EMPLOYEE_NO: "EMP-2026-088",
      LAST_NAME: "MAGTANGGOL",
      FIRST_NAME: "ANDRES",
      MIDDLE_NAME: "BONIFACIO",
      DATE_HIRED: "2026-01-15",
      CIVIL_STATUS: "MARRIED",
      RATE: "650.00",
      DATE_OF_BIRTH: "1994-11-30",
      CONTACT_NO: "0917-888-9999",
      ADDRESS: "1896 Pugad Lawin St Caloocan",
      SCHEDULE_DAYS: "MON, WED",
      SCHEDULE_TIME: "08:00 AM - 05:00 PM",
      DAYOFF: "SUN",
    },
    {
      GROUP_NAME: "GROUP 1",
      ACCOUNT_NAME: "SM RETAIL",
      MOTHER_ACCOUNT: "SM RETAIL",
      VCODE: "SM-NORTH-002",
      STORE_NAME: "SM North EDSA",
      AREA_PROVINCE: "Metro Manila",
      AREA_CITY: "Quezon City",
      POSITION: "", // Blank on row 2, will auto-fill
      EMPLOYEE_NO: "EMP-2026-088",
      LAST_NAME: "MAGTANGGOL",
      FIRST_NAME: "ANDRES",
      MIDDLE_NAME: "BONIFACIO",
      DATE_HIRED: "2026-01-15",
      CIVIL_STATUS: "", // Blank on row 2, will auto-fill
      RATE: "", // Blank on row 2, will auto-fill
      DATE_OF_BIRTH: "", // Blank on row 2, will auto-fill
      CONTACT_NO: "", // Blank on row 2, will auto-fill
      ADDRESS: "", // Blank on row 2, will auto-fill
      SCHEDULE_DAYS: "TUE, THU", // Store-specific schedule
      SCHEDULE_TIME: "08:00 AM - 05:00 PM",
      DAYOFF: "", // Blank on row 2, will auto-fill
    },
    {
      GROUP_NAME: "GROUP 1",
      ACCOUNT_NAME: "SM RETAIL",
      MOTHER_ACCOUNT: "SM RETAIL",
      VCODE: "ROB-GAL-003",
      STORE_NAME: "Robinsons Galleria",
      AREA_PROVINCE: "Metro Manila",
      AREA_CITY: "Quezon City",
      POSITION: "",
      EMPLOYEE_NO: "EMP-2026-088",
      LAST_NAME: "MAGTANGGOL",
      FIRST_NAME: "ANDRES",
      MIDDLE_NAME: "BONIFACIO",
      DATE_HIRED: "2026-01-15",
      CIVIL_STATUS: "",
      RATE: "",
      DATE_OF_BIRTH: "",
      CONTACT_NO: "",
      ADDRESS: "",
      SCHEDULE_DAYS: "FRI, SAT", // Store-specific schedule
      SCHEDULE_TIME: "08:00 AM - 05:00 PM",
      DAYOFF: "",
    },
  ];

  const result = evaluatePlantillaBatchSpec(rovingBatch);

  assert.equal(result.blockedRows, 0);
  assert.equal(result.flaggedRows, 0);
  assert.equal(result.validRows, 3);

  // Verify per-store schedules preserved
  assert.equal(result.rows[0].coalesced.SCHEDULE_DAYS, "MON, WED");
  assert.equal(result.rows[1].coalesced.SCHEDULE_DAYS, "TUE, THU");
  assert.equal(result.rows[2].coalesced.SCHEDULE_DAYS, "FRI, SAT");

  // Verify auto-filled demographics
  assert.equal(result.rows[1].coalesced.CIVIL_STATUS, "MARRIED");
  assert.equal(result.rows[2].coalesced.RATE, "650.00");
  assert.equal(result.rows[1].coalesced.CONTACT_NO, "09178889999");
  assert.equal(result.rows[2].coalesced.DAYOFF, "SUN");

  // Verify aggregated master record
  const emp = result.persistedEmployees["EMP-2026-088"];
  assert.equal(emp.last_name, "MAGTANGGOL");
  assert.equal(emp.first_name, "ANDRES");
  assert.equal(emp.middle_name, "BONIFACIO");
  assert.equal(emp.date_hired, "2026-01-15");
  assert.equal(emp.birthdate, "1994-11-30");
  assert.equal(emp.rate, "650.00");
});

test("Tier 4 Scenario B: Roving Promodiser with Rate Adjustment (warning flag emitted, last-row rate committed)", () => {
  const batch = [
    {
      VCODE: "V-STORE-1",
      STORE_NAME: "Store Alpha",
      POSITION: "Promodiser",
      EMPLOYEE_NO: "PROMO-001",
      LAST_NAME: "SILANG",
      FIRST_NAME: "GABRIELA",
      MIDDLE_NAME: "CARIÑO",
      DATE_HIRED: "2026-01-15",
      RATE: "610.00", // Initial rate
    },
    {
      VCODE: "V-STORE-2",
      STORE_NAME: "Store Beta",
      POSITION: "Promodiser",
      EMPLOYEE_NO: "PROMO-001",
      LAST_NAME: "SILANG",
      FIRST_NAME: "GABRIELA",
      MIDDLE_NAME: "CARIÑO",
      DATE_HIRED: "2026-01-15",
      RATE: "645.00", // Adjusted rate in second store assignment
    },
  ];

  const result = evaluatePlantillaBatchSpec(batch);

  // Batch remains valid/submittable (flagged only)
  assert.equal(result.blockedRows, 0);
  assert.equal(result.flaggedRows, 2);
  assert.match(result.rows[0].validationFlags[0].msg, /Conflicting RATE in batch/);

  // Persisted rate is 645.00
  assert.equal(result.persistedEmployees["PROMO-001"].rate, "645.00");
});

test("Tier 4 Scenario C: Corrupted Multi-Store Upload (two workers sharing same employee ID -> hard block)", () => {
  const corruptedBatch = [
    {
      VCODE: "V-STORE-1",
      STORE_NAME: "Store Alpha",
      POSITION: "Cashier",
      EMPLOYEE_NO: "EMP-COLLISION",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
    },
    {
      VCODE: "V-STORE-2",
      STORE_NAME: "Store Beta",
      POSITION: "Cashier",
      EMPLOYEE_NO: "EMP-COLLISION",
      LAST_NAME: "DELOS REYES", // Completely different person uploaded with same ID
      FIRST_NAME: "CARLOS",
      MIDDLE_NAME: "RAMIREZ",
      DATE_HIRED: "2026-01-15",
    },
  ];

  const result = evaluatePlantillaBatchSpec(corruptedBatch);

  assert.equal(result.blockedRows, 2);
  assert.equal(result.validRows, 0);
  assert.match(
    result.rows[0].validationErrors[0].conflictType ?? "",
    /intra_file_identity_mismatch/
  );
  assert.match(
    result.rows[1].validationErrors[0].conflictType ?? "",
    /intra_file_identity_mismatch/
  );
});

test("Tier 4 Scenario D: Underage Roving Student Intern (17yo roving across 2 stores -> hard-block on all rows with clear message)", () => {
  const internBatch = [
    {
      VCODE: "V-STORE-1",
      STORE_NAME: "Store Alpha",
      POSITION: "Student Intern",
      EMPLOYEE_NO: "INTERN-2026-001",
      LAST_NAME: "AQUINO",
      FIRST_NAME: "BENIGNO",
      MIDDLE_NAME: "COJUANGCO",
      DATE_HIRED: "2026-02-01",
      DATE_OF_BIRTH: "2008-08-15", // Hired 2026-02-01 -> Age is 17 years 5 months (< 18)
    },
    {
      VCODE: "V-STORE-2",
      STORE_NAME: "Store Beta",
      POSITION: "Student Intern",
      EMPLOYEE_NO: "INTERN-2026-001",
      LAST_NAME: "AQUINO",
      FIRST_NAME: "BENIGNO",
      MIDDLE_NAME: "COJUANGCO",
      DATE_HIRED: "2026-02-01",
      DATE_OF_BIRTH: "", // Coalesces from row 1
    },
  ];

  const result = evaluatePlantillaBatchSpec(internBatch);

  assert.equal(result.blockedRows, 2);
  assert.equal(result.validRows, 0);
  assert.match(
    result.rows[0].validationErrors[0].conflictType ?? "",
    /underage_employee_under_18/
  );
  assert.match(
    result.rows[1].validationErrors[0].conflictType ?? "",
    /underage_employee_under_18/
  );
  assert.match(
    result.rows[0].validationErrors[0].msg,
    /Minimum legal working age is 18/
  );
});
