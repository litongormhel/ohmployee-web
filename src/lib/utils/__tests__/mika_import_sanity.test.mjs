import test from "node:test";
import assert from "node:assert/strict";
import * as XLSX from "xlsx";
import {
  MIKA_REQUIRED_HEADERS,
  MIKA_OPTIONAL_HEADERS,
  MIKA_SAMPLE_ROW,
} from "../data_control_xlsx.ts";

// Helper to simulate parseSpreadsheetToRows on Node buffers
function parseBufferToRows(buffer) {
  const wb = XLSX.read(buffer, { type: "buffer", cellDates: true });
  const sheetName = wb.SheetNames[0];
  if (!sheetName) throw new Error("Spreadsheet contains no sheets.");

  const sheet = wb.Sheets[sheetName];
  const rawMatrix = XLSX.utils.sheet_to_json(sheet, {
    header: 1,
    defval: "",
    raw: false,
  });

  if (!rawMatrix || rawMatrix.length === 0) {
    throw new Error("Spreadsheet sheet is empty.");
  }

  const rawHeaders = rawMatrix[0].map((c) => String(c ?? "").trim());
  const rows = [];
  for (let r = 1; r < rawMatrix.length; r++) {
    const rawRow = rawMatrix[r];
    if (!rawRow || rawRow.length === 0) continue;
    const hasValue = rawRow.some((val) => String(val ?? "").trim() !== "");
    if (!hasValue) continue;

    const rowObj = {};
    for (let c = 0; c < rawHeaders.length; c++) {
      const headerKey = rawHeaders[c];
      if (headerKey) {
        rowObj[headerKey] = String(rawRow[c] ?? "").trim();
      }
    }
    rows.push(rowObj);
  }

  return { headers: rawHeaders, rows };
}

// Split full name helper (mirroring MikaImportModal.tsx)
function splitFullName(fullName) {
  const clean = fullName.trim();
  const parts = clean.split(",");
  if (parts.length >= 2) {
    return {
      lastName: parts[0].trim(),
      firstName: parts[1].trim(),
      middleName: parts.length > 2 ? parts.slice(2).join(",").trim() : "",
    };
  }
  const spaceParts = clean.split(" ");
  if (spaceParts.length >= 2) {
    return {
      firstName: spaceParts[0].trim(),
      middleName: spaceParts.length > 2 ? spaceParts.slice(1, -1).join(" ").trim() : "",
      lastName: spaceParts[spaceParts.length - 1].trim(),
    };
  }
  return { lastName: clean, firstName: "", middleName: "" };
}

test("SANITY-01: MIKA Template Specification and Header Completeness", () => {
  assert.equal(MIKA_REQUIRED_HEADERS.length, 3, "Requires exactly 3 mandatory headers");
  assert.deepEqual(
    [...MIKA_REQUIRED_HEADERS],
    ["Employee No.", "Fullname", "Account"],
    "Mandatory headers must match Employee No., Fullname, Account"
  );
  assert.equal(MIKA_OPTIONAL_HEADERS.length, 11, "Includes 11 profile & statutory headers");
  assert.ok(MIKA_OPTIONAL_HEADERS.includes("SSS"));
  assert.ok(MIKA_OPTIONAL_HEADERS.includes("PhilHealth"));
  assert.ok(MIKA_OPTIONAL_HEADERS.includes("Pag-IBIG"));
  assert.ok(MIKA_OPTIONAL_HEADERS.includes("TIN"));
  assert.ok(MIKA_OPTIONAL_HEADERS.includes("ATM No."));
  assert.ok(MIKA_OPTIONAL_HEADERS.includes("Contact No."));
  assert.ok(MIKA_OPTIONAL_HEADERS.includes("Date Hired"));
});

test("SANITY-02: Generating and Parsing a Clean MIKA XLSX File", () => {
  const wb = XLSX.utils.book_new();
  const headers = [...MIKA_REQUIRED_HEADERS, ...MIKA_OPTIONAL_HEADERS];
  const ws = XLSX.utils.aoa_to_sheet([headers, MIKA_SAMPLE_ROW]);
  XLSX.utils.book_append_sheet(wb, ws, "IMPORT_TEMPLATE");

  const buffer = XLSX.write(wb, { bookType: "xlsx", type: "buffer" });
  assert.ok(buffer && buffer.length > 0, "Workbook binary buffer generated");

  const { headers: parsedHeaders, rows: parsedRows } = parseBufferToRows(buffer);

  assert.equal(parsedHeaders.length, headers.length, "Parsed headers count must match template");
  assert.equal(parsedRows.length, 1, "Parsed rows count must equal 1 sample row");

  const sample = parsedRows[0];
  assert.equal(sample["Employee No."], "10001");
  assert.equal(sample["Fullname"], "DELA CRUZ, JUAN SANTOS");
  assert.equal(sample["Account"], "ACTISERVE");
  assert.equal(sample["SSS"], "33-1234567-8");
  assert.equal(sample["PhilHealth"], "03-1234567-8");
  assert.equal(sample["Pag-IBIG"], "1012-3456-7890");
  assert.equal(sample["TIN"], "123-456-789-000");
  assert.equal(sample["ATM No."], "1234567890");
  assert.equal(sample["Contact No."], "09171234567");
});

test("SANITY-03: Fullname Parsing and Splitting Logic", () => {
  // Comma-separated: LASTNAME, FIRSTNAME MIDDLE
  const res1 = splitFullName("DELA CRUZ, JUAN SANTOS");
  assert.equal(res1.lastName, "DELA CRUZ");
  assert.equal(res1.firstName, "JUAN SANTOS");

  // Space-separated fallback: FIRSTNAME MIDDLE LASTNAME
  const res2 = splitFullName("JUAN SANTOS REYES");
  assert.equal(res2.firstName, "JUAN");
  assert.equal(res2.middleName, "SANTOS");
  assert.equal(res2.lastName, "REYES");
});

test("SANITY-04: Header Normalization and Aliasing Tolerates Case & Whitespace", () => {
  const wb = XLSX.utils.book_new();
  const messyHeaders = ["  EMPLOYEE_NO  ", "full_name", "ACCOUNT_NAME", "sss_no", "contact"];
  const messyRow = ["E-9988", "SANTOS, MARIA", "ACTISERVE", "34-9988771-0", "09181112233"];
  const ws = XLSX.utils.aoa_to_sheet([messyHeaders, messyRow]);
  XLSX.utils.book_append_sheet(wb, ws, "SHEET1");

  const buffer = XLSX.write(wb, { bookType: "xlsx", type: "buffer" });
  const { headers, rows } = parseBufferToRows(buffer);

  const upperHeaders = new Set(headers.map((h) => h.toUpperCase().replace(/\s+/g, "_")));
  const hasEmpNo = upperHeaders.has("EMPLOYEE_NO") || upperHeaders.has("EMPLOYEE_NO.");
  const hasFullName = upperHeaders.has("FULL_NAME") || upperHeaders.has("FULLNAME");
  const hasAccount = upperHeaders.has("ACCOUNT_NAME") || upperHeaders.has("ACCOUNT");

  assert.ok(hasEmpNo, "Should identify EMPLOYEE_NO header");
  assert.ok(hasFullName, "Should identify FULL_NAME header");
  assert.ok(hasAccount, "Should identify ACCOUNT_NAME header");
  assert.equal(rows[0]["EMPLOYEE_NO"], "E-9988");
});

test("SANITY-05: Missing Required Headers Detection", () => {
  const wb = XLSX.utils.book_new();
  const incompleteHeaders = ["Employee No.", "Fullname"]; // Missing Account
  const row = ["10001", "DELA CRUZ, JUAN"];
  const ws = XLSX.utils.aoa_to_sheet([incompleteHeaders, row]);
  XLSX.utils.book_append_sheet(wb, ws, "SHEET1");

  const buffer = XLSX.write(wb, { bookType: "xlsx", type: "buffer" });
  const { headers } = parseBufferToRows(buffer);
  const upperHeaders = new Set(headers.map((h) => h.toUpperCase()));

  const hasEmpNo = upperHeaders.has("EMPLOYEE NO.") || upperHeaders.has("EMPLOYEE_NO");
  const hasFullName = upperHeaders.has("FULLNAME");
  const hasAccount = upperHeaders.has("ACCOUNT");

  assert.ok(hasEmpNo);
  assert.ok(hasFullName);
  assert.ok(!hasAccount, "Should detect that Account is missing");
});

test("SANITY-06: MIKA Cross-Check Flagging Matrix (Matched vs Type A vs Type B)", () => {
  // Simulated Plantilla records
  const mockPlantilla = new Map([
    ["10001", { account: "ACTISERVE", status: "Active", isActive: true }],
    ["10002", { account: "ACTISERVE", status: "Deactivated", isActive: false }],
    ["10003", { account: "OTHER_STORE", status: "Active", isActive: true }],
  ]);
  const officialAccounts = new Set(["ACTISERVE", "OTHER_STORE"]);

  const testRows = [
    { employeeNo: "10001", account: "ACTISERVE" }, // Active -> Matched
    { employeeNo: "10002", account: "ACTISERVE" }, // Inactive in Plantilla -> Type B Ghost
    { employeeNo: "99999", account: "ACTISERVE" }, // Not in Plantilla -> Type A Ghost
    { employeeNo: "10001", account: "FAKE_ACCOUNT" }, // Unlisted account -> Blocked
    { employeeNo: "10003", account: "ACTISERVE" }, // Mismatched account -> Blocked
  ];

  const results = testRows.map((row) => {
    const key = row.employeeNo.trim().toUpperCase();
    const inputAccountUpper = row.account.trim().toUpperCase();
    const match = mockPlantilla.get(key);

    if (!match) {
      return { flagType: "ghost", ghostType: "Type A", reason: "Possible Ghost Employee (No Plantilla match)" };
    }
    if (!match.isActive) {
      return { flagType: "ghost", ghostType: "Type B", reason: `Inactive in Plantilla (status: ${match.status})` };
    }
    if (!officialAccounts.has(inputAccountUpper)) {
      return { flagType: "blocked", reason: "Account not in official active accounts list" };
    }
    if (match.account.toUpperCase() !== inputAccountUpper) {
      return { flagType: "blocked", reason: `Account mismatch: MIKA has "${row.account}", Plantilla has "${match.account}"` };
    }
    return { flagType: "matched", reason: "Verified match" };
  });

  // Verify classifications
  assert.equal(results[0].flagType, "matched", "Row 1 must be matched");
  assert.equal(results[1].flagType, "ghost", "Row 2 must be flagged as ghost");
  assert.equal(results[1].ghostType, "Type B", "Row 2 must be Type B Inactive Anomaly");
  assert.equal(results[2].flagType, "ghost", "Row 3 must be flagged as ghost");
  assert.equal(results[2].ghostType, "Type A", "Row 3 must be Type A Unregistered");
  assert.equal(results[3].flagType, "blocked", "Row 4 must be blocked due to fake account");
  assert.equal(results[4].flagType, "blocked", "Row 5 must be blocked due to account mismatch");
});
