import test from "node:test";
import assert from "node:assert/strict";
import ExcelJS from "exceljs";
import {
  PLANTILLA_BASELINE_STORE_HEADERS,
  PLANTILLA_EMPLOYEE_HEADERS,
  PLANTILLA_REQUIRED_HEADERS,
  PLANTILLA_OPTIONAL_HEADERS,
  PLANTILLA_SAMPLE_ROW,
  validateSpreadsheetScopeContext,
  VACANCY_REQUIRED_HEADERS,
  VACANCY_OPTIONAL_HEADERS,
  VACANCY_SAMPLE_ROW,
  PAYROLL_REQUIRED_HEADERS,
  parseSpreadsheetToRows,
} from "../data_control_xlsx.ts";
import {
  V3_REQUIRED_HEADERS,
  STANDARD_REQUIRED_HEADERS,
  buildHrEmplocImportTemplateXlsx,
  xlsxToHrEmplocRows,
  normalizeMiddleName,
  buildParsePreview,
} from "../hr_emploc_xlsx.ts";
import {
  reconcilePayroll,
} from "../payroll_reconciliation.ts";

// Helper to create in-memory File from array-of-arrays
async function createMockXlsxFile(sheetName, aoa, fileName = "import_test.xlsx") {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet(sheetName);
  for (const row of aoa) ws.addRow(row);
  const buffer = await wb.xlsx.writeBuffer();
  return new File([buffer], fileName, {
    type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  });
}

// ============================================================================
// 1. Plantilla Import Sanity Checks
// ============================================================================

test("1. Plantilla Import: parseSpreadsheetToRows parses store & employee rows cleanly", async () => {
  const allHeaders = [
    ...PLANTILLA_BASELINE_STORE_HEADERS,
    ...PLANTILLA_EMPLOYEE_HEADERS,
    ...PLANTILLA_OPTIONAL_HEADERS,
  ];

  const file = await createMockXlsxFile("IMPORT_TEMPLATE", [
    allHeaders,
    PLANTILLA_SAMPLE_ROW,
    // Add a blank row to verify blank row resilience
    ["", "", "", "", "", "", "", "", "", "", "", "", ""],
  ]);

  const { headers, rows } = await parseSpreadsheetToRows(file);
  assert.equal(headers.length, allHeaders.length, "Should parse all headers");
  assert.equal(rows.length, 1, "Should filter out completely blank row");
  assert.equal(rows[0].VCODE, "PG-DAU-001");
  assert.equal(rows[0].ACCOUNT_NAME, "SUPER 8");
  assert.equal(rows[0].EMPLOYEE_NO, "EMP-2026-001");
  assert.equal(rows[0].LAST_NAME, "DELA CRUZ");
  assert.equal(rows[0].MIDDLE_NAME, "SANTOS");
});

test("1. Plantilla Import: Detects missing required store headers", async () => {
  const incompleteHeaders = ["GROUP_NAME", "ACCOUNT_NAME", "VCODE"]; // Missing STORE_NAME, AREA_PROVINCE, AREA_CITY, POSITION, etc.
  const file = await createMockXlsxFile("IMPORT_TEMPLATE", [
    incompleteHeaders,
    ["GROUP 2", "SUPER 8", "PG-DAU-001"],
  ]);

  const { headers } = await parseSpreadsheetToRows(file);
  const upperHeaders = new Set(headers.map((h) => h.toUpperCase()));
  const missing = PLANTILLA_REQUIRED_HEADERS.filter((req) => !upperHeaders.has(req));

  assert.ok(missing.length > 0, "Should detect missing required columns");
  assert.ok(missing.includes("STORE_NAME"));
  assert.ok(missing.includes("POSITION"));
  assert.ok(missing.includes("AREA_PROVINCE"));
});

test("1. Plantilla Import: validateSpreadsheetScopeContext enforces group and account matching", () => {
  const matchingRows = [
    { GROUP_NAME: "GROUP 2", ACCOUNT_NAME: "SUPER 8", VCODE: "PG-001" },
    { GROUP_NAME: "group 2", ACCOUNT_NAME: "super 8", VCODE: "PG-002" },
  ];
  const matchResult = validateSpreadsheetScopeContext(matchingRows, "GROUP 2", "SUPER 8");
  assert.equal(matchResult.valid, true, "Matching scope should be valid");
  assert.equal(matchResult.errors.length, 0);

  const mismatchRows = [
    { GROUP_NAME: "GROUP 3", ACCOUNT_NAME: "SAVEMORE", VCODE: "PG-001" },
  ];
  const mismatchResult = validateSpreadsheetScopeContext(mismatchRows, "GROUP 2", "SUPER 8");
  assert.equal(mismatchResult.valid, false, "Mismatched scope should be invalid");
  assert.ok(mismatchResult.errors.some((e) => e.includes("GROUP_NAME")));
  assert.ok(mismatchResult.errors.some((e) => e.includes("ACCOUNT_NAME")));
});

// ============================================================================
// 2. HR Emploc Import Sanity Checks
// ============================================================================

test("2. HR Emploc Import: Template generation produces valid XLSX for both v3 and standard", async () => {
  assert.equal(V3_REQUIRED_HEADERS.length, 7, "v3 schema should require exactly 7 columns");
  assert.equal(STANDARD_REQUIRED_HEADERS.length, 7, "standard schema should require exactly 7 columns");

  const v3Bytes = await buildHrEmplocImportTemplateXlsx("v3");
  assert.ok(v3Bytes.length > 0, "v3 template should have content");
  const v3Rows = await xlsxToHrEmplocRows(v3Bytes);
  assert.ok(v3Rows.length > 0, "Should parse sample row from v3 template");
  assert.ok("VCODE" in v3Rows[0] || "GROUP" in v3Rows[0], "v3 should contain v3 headers");

  const stdBytes = await buildHrEmplocImportTemplateXlsx("standard");
  assert.ok(stdBytes.length > 0, "standard template should have content");
  const stdRows = await xlsxToHrEmplocRows(stdBytes);
  assert.ok(stdRows.length > 0, "Should parse sample row from standard template");
  assert.ok("STORE_NAME" in stdRows[0] || "EMPLOYEE_NO" in stdRows[0]);
});

test("2. HR Emploc Import: normalizeMiddleName enforces mobile parity and character validity", () => {
  // Blank middle name
  assert.equal(normalizeMiddleName("").error !== undefined, true, "Blank should produce error");

  // N/A slash pattern
  const naSlash = normalizeMiddleName("N/A");
  assert.equal(naSlash.normalized, "NA", "N/A should normalize to NA");
  assert.ok(naSlash.error?.includes("NA"), "Should warn to use NA");

  // Exact NA
  const exactNa = normalizeMiddleName("NA");
  assert.equal(exactNa.normalized, "NA");
  assert.equal(exactNa.error, undefined);

  // Single letter initials rejected
  const initial = normalizeMiddleName("S");
  assert.ok(initial.error?.includes("at least two characters"));

  const dottedInitial = normalizeMiddleName("S.");
  assert.ok(dottedInitial.error?.includes("at least two characters"));

  // Valid middle name with trailing dot stripped
  const validWithDot = normalizeMiddleName("Santos.");
  assert.equal(validWithDot.normalized, "Santos");
  assert.equal(validWithDot.error, undefined);

  // Multi-word middle name
  const multiWord = normalizeMiddleName("De La Cruz");
  assert.equal(multiWord.normalized, "De La Cruz");
  assert.equal(multiWord.error, undefined);

  // Invalid characters
  const invalidChars = normalizeMiddleName("Santos#1");
  assert.ok(invalidChars.error?.includes("invalid characters"));
});

test("2. HR Emploc Import: buildParsePreview validates required fields & duplicate detection", () => {
  const sampleRows = [
    {
      GROUP: "Group Alpha",
      ACCOUNT: "Super 8",
      VCODE: "V-2026-001",
      LAST_NAME: "DELA CRUZ",
      FIRST_NAME: "JUAN",
      MIDDLE_NAME: "SANTOS",
      DATE_HIRED: "2026-01-15",
    },
    // Duplicate VCODE row
    {
      GROUP: "Group Alpha",
      ACCOUNT: "Super 8",
      VCODE: "V-2026-001",
      LAST_NAME: "REYES",
      FIRST_NAME: "MARIA",
      MIDDLE_NAME: "NA",
      DATE_HIRED: "2026-01-15",
    },
  ];

  const preview = buildParsePreview(sampleRows, "Group Alpha");
  assert.equal(preview.totalRows, 2);
  assert.equal(preview.clientValidRows, 1, "First row should be valid");
  assert.equal(preview.clientInvalidRows, 1, "Second row should be flagged for duplicate VCode");
  assert.ok(preview.previews[1].clientErrors.some((e) => e.includes("Duplicate VCode")));
});

// ============================================================================
// 3. Vacancy Import Sanity Checks
// ============================================================================

test("3. Vacancy Import: parseSpreadsheetToRows parses all 12 required vacancy headers", async () => {
  const allHeaders = [...VACANCY_REQUIRED_HEADERS, ...VACANCY_OPTIONAL_HEADERS];
  const file = await createMockXlsxFile("IMPORT_TEMPLATE", [allHeaders, VACANCY_SAMPLE_ROW]);

  const { headers, rows } = await parseSpreadsheetToRows(file);
  const upperHeaders = new Set(headers.map((h) => h.toUpperCase()));

  for (const req of VACANCY_REQUIRED_HEADERS) {
    assert.ok(upperHeaders.has(req), `Header ${req} must be present`);
  }

  assert.equal(rows.length, 1);
  assert.equal(rows[0].VCODE, "VAC-MNL-001");
  assert.equal(rows[0].STORE_NAME, "Super 8 Dau");
  assert.equal(rows[0].HC, "1");
  assert.equal(rows[0].EMPLOYMENT_TYPE, "stationary");
  assert.equal(rows[0].REQUEST_TYPE, "Replacement");
  assert.equal(rows[0].APPLICANT_LAST_NAME, "DELA CRUZ");
  assert.equal(rows[0].APPLICANT_STATUS, "For Interview / Intro");
});

test("3. Vacancy Import: Detects missing required vacancy headers", async () => {
  // Omit CITY, HC, and REQUEST_TYPE
  const partialHeaders = ["VCODE", "GROUP_NAME", "CHAIN", "ACCOUNT_NAME", "STORE_NAME", "POSITION", "PROVINCE"];
  const file = await createMockXlsxFile("IMPORT_TEMPLATE", [
    partialHeaders,
    ["VAC-001", "GROUP 2", "CHAIN", "SUPER 8", "Store", "Merchandiser", "Pampanga"],
  ]);

  const { headers } = await parseSpreadsheetToRows(file);
  const upperHeaders = new Set(headers.map((h) => h.toUpperCase()));
  const missing = VACANCY_REQUIRED_HEADERS.filter((req) => !upperHeaders.has(req));

  assert.ok(missing.length > 0, "Should detect missing columns");
  assert.ok(missing.includes("HC"));
  assert.ok(missing.includes("CITY"));
  assert.ok(missing.includes("REQUEST_TYPE"));
});

// ============================================================================
// 4. Payroll Reconciliation Import Sanity Checks
// ============================================================================

test("4. Payroll Import: Header alias resolution recognizes diverse payroll formats", async () => {
  assert.equal(PAYROLL_REQUIRED_HEADERS.length, 3, "Payroll required headers should have 3 columns");
  const aliasHeaders = ["EMPLOYEE NO.", "FULLNAME", "ACCOUNT GROUP"];
  const file = await createMockXlsxFile("PAYROLL", [
    aliasHeaders,
    ["10001", "DELA CRUZ, JUAN SANTOS", "SUPER 8 / GROUP 2"],
  ]);

  const { headers, rows } = await parseSpreadsheetToRows(file);
  const upperHeaders = new Set(headers.map((h) => h.toUpperCase()));

  const hasEmpNo =
    upperHeaders.has("EMPLOYEE_NUMBER") ||
    upperHeaders.has("EMPLOYEE NUMBER") ||
    upperHeaders.has("EMPLOYEE NO.") ||
    upperHeaders.has("EMPLOYEE NO");
  const hasName =
    upperHeaders.has("FULL_NAME") ||
    upperHeaders.has("FULLNAME") ||
    upperHeaders.has("FULL NAME");
  const hasAccount =
    upperHeaders.has("ACCOUNT_GROUP") ||
    upperHeaders.has("ACCOUNT GROUP") ||
    upperHeaders.has("ACCOUNT");

  assert.ok(hasEmpNo, "Should resolve EMPLOYEE NO. alias");
  assert.ok(hasName, "Should resolve FULLNAME alias");
  assert.ok(hasAccount, "Should resolve ACCOUNT GROUP alias");
  assert.equal(rows.length, 1);
});

test("4. Payroll Import: reconcilePayroll executes 6-category classification matrix", () => {
  const plantillaRows = [
    // 1. Clean match
    {
      plantillaId: "p1",
      employeeNo: "10001",
      lastName: "DELA CRUZ",
      firstName: "JUAN",
      middleName: "SANTOS",
      accountName: "SUPER 8",
      groupName: "GROUP 2",
      isActive: true,
    },
    // 2. Active in Plantilla but will be omitted from payroll -> missingInPayroll
    {
      plantillaId: "p2",
      employeeNo: "10002",
      lastName: "REYES",
      firstName: "MARIA",
      middleName: "",
      accountName: "SAVEMORE",
      groupName: "GROUP 3",
      isActive: true,
    },
    // 3. Inactive in Plantilla (Resigned/Terminated) but in payroll -> paidInactive
    {
      plantillaId: "p3",
      employeeNo: "10003",
      lastName: "SANTOS",
      firstName: "PEDRO",
      middleName: "L.",
      accountName: "SUPER 8",
      groupName: "GROUP 2",
      isActive: false,
    },
    // 4. Name/Account Mismatch
    {
      plantillaId: "p4",
      employeeNo: "10004",
      lastName: "GARCIA",
      firstName: "ANA",
      middleName: "MARIE",
      accountName: "SUPER 8",
      groupName: "GROUP 2",
      isActive: true,
    },
  ];

  const payrollRows = [
    // Clean
    { rowNumber: 1, employeeNumber: "10001", fullName: "DELA CRUZ, JUAN SANTOS", accountGroup: "SUPER 8 / GROUP 2" },
    // Paid Inactive (Employee 10003 is inactive in Plantilla)
    { rowNumber: 2, employeeNumber: "10003", fullName: "SANTOS, PEDRO L.", accountGroup: "SUPER 8 / GROUP 2" },
    // Mismatch (Employee 10004 has wrong account in payroll)
    { rowNumber: 3, employeeNumber: "10004", fullName: "GARCIA, ANA MARIE", accountGroup: "ROBINSONS / GROUP 1" },
    // Missing in Plantilla (Employee 99999 does not exist in Plantilla)
    { rowNumber: 4, employeeNumber: "99999", fullName: "UNKNOWN, GHOST", accountGroup: "SUPER 8 / GROUP 2" },
    // Duplicates (Employee 10005 appears twice in payroll upload)
    { rowNumber: 5, employeeNumber: "10005", fullName: "DUPLICATE, EMP ONE", accountGroup: "SUPER 8 / GROUP 2" },
    { rowNumber: 6, employeeNumber: "10005", fullName: "DUPLICATE, EMP TWO", accountGroup: "SUPER 8 / GROUP 2" },
  ];

  const result = reconcilePayroll(payrollRows, plantillaRows);

  assert.equal(result.clean.length, 1, "Should identify 1 clean record");
  assert.equal(result.clean[0].employeeNumber, "10001");

  assert.equal(result.missingInPayroll.length, 1, "Should identify 1 missing in payroll (10002)");
  assert.equal(result.missingInPayroll[0].employeeNumber, "10002");

  assert.equal(result.missingInPlantilla.length, 1, "Should identify 1 missing in plantilla (99999)");
  assert.equal(result.missingInPlantilla[0].employeeNumber, "99999");

  assert.equal(result.paidInactive.length, 1, "Should identify 1 paid inactive (10003)");
  assert.equal(result.paidInactive[0].employeeNumber, "10003");

  assert.equal(result.mismatch.length, 1, "Should identify 1 mismatch (10004)");
  assert.equal(result.mismatch[0].employeeNumber, "10004");

  assert.equal(result.duplicates.length, 2, "Should identify 2 duplicate entries for 10005");
  assert.equal(result.duplicates[0].employeeNumber, "10005");
});
