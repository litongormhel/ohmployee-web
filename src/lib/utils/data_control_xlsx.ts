import * as XLSX from "xlsx";
import ExcelJS from "exceljs";

// ============================================================================
// 1. Plantilla Bulk Import Templates & Parser (ADR-002 Compliant)
// ============================================================================

// 8 Always Required Store Headers (ADR-002 Invariants 1, 2, 6)
// Note: EMPLOYMENT_TYPE, REQUIRED_HC, and WITH_PENALTY are removed from required
// input and auto-computed by the database.
export const PLANTILLA_BASELINE_STORE_HEADERS = [
  "GROUP_NAME",
  "ACCOUNT_NAME",
  "MOTHER_ACCOUNT",
  "VCODE",
  "STORE_NAME",
  "AREA_PROVINCE",
  "AREA_CITY",
  "POSITION",
] as const;

// 5 Conditionally Required Employee Headers (ADR-002 Invariants 5, 7)
// If EMPLOYEE_NO is provided, all 5 are required (with strict MIDDLE_NAME check).
// If EMPLOYEE_NO is blank, all 5 must be blank (creates vacant store slot).
export const PLANTILLA_EMPLOYEE_HEADERS = [
  "EMPLOYEE_NO",
  "LAST_NAME",
  "FIRST_NAME",
  "MIDDLE_NAME",
  "DATE_HIRED",
] as const;

// The baseline required headers in any uploaded spreadsheet are the 8 store/slot columns.
export const PLANTILLA_REQUIRED_HEADERS = PLANTILLA_BASELINE_STORE_HEADERS;

// Optional Headers (ADR-002 Invariant 8: SCHEDULE_DAYS, SCHEDULE_TIME, DAYOFF)
export const PLANTILLA_OPTIONAL_HEADERS = [
  "CIVIL_STATUS",
  "RATE",
  "DATE_OF_BIRTH",
  "CONTACT_NO",
  "ADDRESS",
  "SCHEDULE_DAYS",
  "SCHEDULE_TIME",
  "DAYOFF",
  "COORDINATOR",
  "HRCO_EMAIL",
] as const;

// Legacy headers accepted for backward compatibility
export const PLANTILLA_LEGACY_HEADERS = [
  "EMPLOYMENT_TYPE",
  "REQUIRED_HC",
  "WITH_PENALTY",
  "SCHEDULE",
] as const;

export const PLANTILLA_SAMPLE_ROW = [
  "GROUP 2",
  "SUPER 8",
  "SUPER 8",
  "PG-DAU-001",
  "Super 8 Angeles Dau",
  "Pampanga",
  "Angeles",
  "Merchandiser",
  "EMP-2026-001",
  "DELA CRUZ",
  "JUAN",
  "SANTOS",
  "2026-01-15",
  "SINGLE",
  "610.00",
  "1995-05-15",
  "09171234567",
  "123 MacArthur Hwy Angeles",
  "MON-SAT",
  "08:00 AM - 05:00 PM",
  "SUN",
  "Operations Coordinator",
  "",
];

export async function downloadPlantillaImportTemplate(): Promise<void> {
  if (typeof window === "undefined" || typeof document === "undefined") return;

  const workbook = new ExcelJS.Workbook();
  workbook.creator = "OHMployee Web";
  workbook.lastModifiedBy = "OHMployee Web";
  workbook.created = new Date();
  workbook.modified = new Date();

  // --------------------------------------------------------------------------
  // 1. Template Sheet (IMPORT_TEMPLATE)
  // --------------------------------------------------------------------------
  const wsTemplate = workbook.addWorksheet("IMPORT_TEMPLATE", {
    views: [{ showGridLines: true }],
  });

  const allHeaders = [
    ...PLANTILLA_BASELINE_STORE_HEADERS, // 8 Always Required
    ...PLANTILLA_EMPLOYEE_HEADERS,       // 5 Conditionally Required
    ...PLANTILLA_OPTIONAL_HEADERS,       // 10 Optional
  ];

  // Configure column keys and optimal widths
  wsTemplate.columns = allHeaders.map((header) => {
    let width = 18;
    if (["GROUP_NAME", "ACCOUNT_NAME", "MOTHER_ACCOUNT", "VCODE", "STORE_NAME"].includes(header)) {
      width = 24;
    } else if (["AREA_PROVINCE", "AREA_CITY", "POSITION", "ADDRESS"].includes(header)) {
      width = 22;
    } else if (["SCHEDULE_DAYS", "SCHEDULE_TIME", "DAYOFF"].includes(header)) {
      width = 24;
    } else if (["HRCO_EMAIL", "COORDINATOR"].includes(header)) {
      width = 26;
    }
    return { header, key: header, width };
  });

  // Style Header Row (Row 1)
  const headerRow = wsTemplate.getRow(1);
  headerRow.height = 28;

  // First 13 columns are Required (8 Store) + Conditionally Required (5 Employee)
  const requiredHeaderCount = PLANTILLA_BASELINE_STORE_HEADERS.length + PLANTILLA_EMPLOYEE_HEADERS.length; // 13

  headerRow.eachCell((cell, colNumber) => {
    const isRequiredOrConditional = colNumber <= requiredHeaderCount;

    if (isRequiredOrConditional) {
      // Required/Conditional: Soft red fill background (#FFC7CE), bold dark red font (#9C0006)
      cell.fill = {
        type: "pattern",
        pattern: "solid",
        fgColor: { argb: "FFFFC7CE" },
      };
      cell.font = {
        name: "Calibri",
        size: 11,
        bold: true,
        color: { argb: "FF9C0006" },
      };
    } else {
      // Optional headers: subtle neutral fill (#F3F4F6), bold dark slate font (#374151)
      cell.fill = {
        type: "pattern",
        pattern: "solid",
        fgColor: { argb: "FFF3F4F6" },
      };
      cell.font = {
        name: "Calibri",
        size: 11,
        bold: true,
        color: { argb: "FF374151" },
      };
    }

    cell.alignment = {
      vertical: "middle",
      horizontal: "center",
      wrapText: true,
    };

    cell.border = {
      top: { style: "thin", color: { argb: "FFD1D5DB" } },
      left: { style: "thin", color: { argb: "FFD1D5DB" } },
      bottom: { style: "thin", color: { argb: "FF9CA3AF" } },
      right: { style: "thin", color: { argb: "FFD1D5DB" } },
    };
  });

  // Add Sample Row
  const sampleRow = wsTemplate.addRow(PLANTILLA_SAMPLE_ROW);
  sampleRow.height = 20;
  sampleRow.eachCell((cell) => {
    cell.font = { name: "Calibri", size: 10 };
    cell.alignment = { vertical: "middle" };
    cell.border = {
      top: { style: "thin", color: { argb: "FFE5E7EB" } },
      left: { style: "thin", color: { argb: "FFE5E7EB" } },
      bottom: { style: "thin", color: { argb: "FFE5E7EB" } },
      right: { style: "thin", color: { argb: "FFE5E7EB" } },
    };
  });

  // Native Excel Data Validation Dropdowns (Rows 2..500)
  // Column S (19): SCHEDULE_DAYS
  // Column T (20): SCHEDULE_TIME
  // Column U (21): DAYOFF
  const scheduleDaysValidation: ExcelJS.DataValidation = {
    type: "list",
    allowBlank: true,
    formulae: ['"MON-SAT,MON-FRI,TUE-SUN,MON,WED,FRI,TUE,THU,SAT,FLEXI"'],
    showErrorMessage: false,
    errorStyle: "warning",
    errorTitle: "Schedule Days Preset",
    error: "Select a standard schedule preset or enter comma-separated days.",
  };

  const scheduleTimeValidation: ExcelJS.DataValidation = {
    type: "list",
    allowBlank: true,
    formulae: ['"08:00 AM - 05:00 PM,09:00 AM - 06:00 PM,FLEXI (4 HRS),FLEXI (6 HRS)"'],
    showErrorMessage: false,
    errorStyle: "information",
    errorTitle: "Schedule Time Preset",
    error: "Select a standard shift window or enter a custom duration/time.",
  };

  const dayoffValidation: ExcelJS.DataValidation = {
    type: "list",
    allowBlank: true,
    formulae: ['"SUN,SAT,SUN,MON,TUE,WED,THU,FRI,SAT"'],
    showErrorMessage: false,
    errorStyle: "information",
    errorTitle: "Dayoff Preset",
    error: "Select a standard day off or enter custom comma-separated days.",
  };

  for (let rowIdx = 2; rowIdx <= 500; rowIdx++) {
    wsTemplate.getCell(`S${rowIdx}`).dataValidation = scheduleDaysValidation;
    wsTemplate.getCell(`T${rowIdx}`).dataValidation = scheduleTimeValidation;
    wsTemplate.getCell(`U${rowIdx}`).dataValidation = dayoffValidation;
  }

  // --------------------------------------------------------------------------
  // 2. Guide Sheet (VALIDATION_GUIDE — 15-Point ADR-002 Operational Guide)
  // --------------------------------------------------------------------------
  const wsGuide = workbook.addWorksheet("VALIDATION_GUIDE", {
    views: [{ showGridLines: true }],
  });

  wsGuide.columns = [
    { header: "COLUMN / RULE", key: "col", width: 38 },
    { header: "REQUIRED / TYPE", key: "req", width: 26 },
    { header: "DESCRIPTION / FORMAT / ADR-002 INVARIANT", key: "desc", width: 75 },
  ];

  const guideHeaderRow = wsGuide.getRow(1);
  guideHeaderRow.height = 26;
  guideHeaderRow.eachCell((cell) => {
    cell.fill = {
      type: "pattern",
      pattern: "solid",
      fgColor: { argb: "FF4F46E5" }, // Indigo
    };
    cell.font = {
      name: "Calibri",
      size: 11,
      bold: true,
      color: { argb: "FFFFFFFF" },
    };
    cell.alignment = { vertical: "middle", horizontal: "center" };
    cell.border = {
      top: { style: "thin", color: { argb: "FF3730A3" } },
      left: { style: "thin", color: { argb: "FF3730A3" } },
      bottom: { style: "medium", color: { argb: "FF1E1B4B" } },
      right: { style: "thin", color: { argb: "FF3730A3" } },
    };
  });

  const guideData = [
    ["GROUP_NAME", "YES", "Group scope (e.g. GROUP 2). Must match selected group context."],
    ["ACCOUNT_NAME", "YES", "Account client name under selected group (e.g. SUPER 8)."],
    ["MOTHER_ACCOUNT", "YES", "Mother billing entity (e.g. SUPER 8). Penalty rules derive automatically from this configuration."],
    ["VCODE", "YES", "Permanent store vacancy code (e.g. PG-DAU-001). 1 Store Name = 1 VCODE in Account."],
    ["STORE_NAME", "YES", "Official store branch name. Must map 1:1 with VCODE within the Account."],
    ["AREA_PROVINCE", "YES", "Store province (e.g. Pampanga)."],
    ["AREA_CITY", "YES", "Store city or municipality (e.g. Angeles)."],
    ["POSITION", "YES", "Target position designation (e.g. Merchandiser)."],
    ["EMPLOYEE_NO", "CONDITIONAL (BLANK = VACANT)", "Company employee ID. Blank row creates a vacant baseline slot."],
    ["LAST_NAME", "CONDITIONAL", "Required if EMPLOYEE_NO is provided; blank for vacant slots."],
    ["FIRST_NAME", "CONDITIONAL", "Required if EMPLOYEE_NO is provided; blank for vacant slots."],
    ["MIDDLE_NAME", "CONDITIONAL (STRICT)", "Required if EMPLOYEE_NO is provided. >= 2 letters or explicit NA/N/A. Initials like 'S' or 'S.' are rejected."],
    ["DATE_HIRED", "CONDITIONAL", "Hiring date in YYYY-MM-DD. Required if EMPLOYEE_NO is provided; blank for vacant slots."],
    ["CIVIL_STATUS", "NO", "SINGLE, MARRIED, WIDOWED, etc."],
    ["RATE", "NO", "Daily wage rate (decimal number, e.g. 610.00)."],
    ["DATE_OF_BIRTH", "NO", "Birth date in YYYY-MM-DD format."],
    ["CONTACT_NO", "NO", "Mobile contact number (10-11 digits)."],
    ["ADDRESS", "NO", "Full residential address."],
    ["SCHEDULE_DAYS", "NO", "Work week schedule days (e.g. MON-SAT, MON-FRI, or comma-separated MON,TUE,WED)."],
    ["SCHEDULE_TIME", "NO", "Shift window (e.g. 08:00 AM - 05:00 PM) or roving visit duration (e.g. FLEXI (4 HRS))."],
    ["DAYOFF", "NO", "Designated day(s) off (e.g. SUN, SAT,SUN, or MON,TUE)."],
    ["COORDINATOR", "NO", "Designated Operations Coordinator."],
    ["HRCO_EMAIL", "NO", "Assigned HR Coordinator email. If blank, auto-assigned if Account has exactly 1 HRCO."],
    ["", "", ""],
    ["ADR-002 ARCHITECTURAL INVARIANTS & RULES", "", ""],
    ["1. Plantilla Upstream Origin", "RULE", "Plantilla Baseline Import is the upstream source of truth for stores and slots. Vacant slots are valid."],
    ["2. Permanent 1 Store Name = 1 VCODE", "RULE", "Within an Account, 1 Store maps 1:1 to 1 VCODE across all slots and headcount."],
    ["3. Coverage Group (CGCODE) Coexistence", "RULE", "Stores grouped under a roving CGCODE permanently retain their individual store VCODEs."],
    ["4. Auto-Computed Employment Type", "RULE", "Vacant = stationary. Assigned: 1 store = stationary; >1 distinct stores in batch = roving."],
    ["5. Fractional Headcount (1/N)", "RULE", "Roving employees across N stores receive fractional 1/N headcount per store (e.g. 5 stores = 0.20 HC)."],
    ["6. Multi-Batch Existing VCODE Rule", "RULE", "Vacant row on existing VCODE is SKIPPED (non-blocking). Employee row on existing VCODE occupies open slot or adds ordinal."],
    ["7. Mother Account Penalty Derivation", "RULE", "MOTHER_ACCOUNT is required; WITH_PENALTY is derived from mother account setup automatically."],
    ["8. Strict Middle Name Validation", "RULE", "Single-letter initials rejected. Only full middle names (>=2 alpha chars) or explicit 'NA'/'N/A' accepted."],
    ["9. Partial Employee Block", "RULE", "If employee fields (names, date hired) are provided without EMPLOYEE_NO, row is blocked."],
    ["10. Schedule Days & Time Model", "RULE", "SCHEDULE_DAYS and DAYOFF support multi-day schedules; SCHEDULE_TIME supports shifts and roving flexi hours."],
    ["11. Per-Account HRCO Auto-Population", "RULE", "1 HRCO on Account -> auto-populated; 0 or >1 -> flagged with NEEDS HRCO for coordinator review."],
    ["12. Reactive HRCO Backfill", "RULE", "When an HRCO is assigned to an Account, pending NEEDS HRCO plantilla rows backfill automatically."],
    ["13. Rollback Governance (72h Window)", "RULE", "Data Team uploader can request rollback within 72h of approval; HA and SA can approve or reject."],
    ["14. Strict Zero-Edit Immutability Lock", "RULE", "If any record was modified in Plantilla post-approval, rollback is HARD BLOCKED for all roles."],
    ["15. Downstream VCODE Enforcement", "RULE", "Vacancy and HR Emploc imports reject any VCODE not already established in Plantilla."],
  ];

  for (const r of guideData) {
    const isSectionHeader = r[0].startsWith("ADR-002");
    const addedRow = wsGuide.addRow(r);
    addedRow.height = isSectionHeader ? 22 : 19;

    addedRow.eachCell((cell) => {
      if (isSectionHeader) {
        cell.fill = {
          type: "pattern",
          pattern: "solid",
          fgColor: { argb: "FFF3E8FF" }, // Soft purple
        };
        cell.font = { name: "Calibri", size: 10, bold: true, color: { argb: "FF6B21A8" } };
      } else {
        cell.font = { name: "Calibri", size: 10 };
      }
      cell.alignment = { vertical: "middle" };
      cell.border = {
        top: { style: "thin", color: { argb: "FFE5E7EB" } },
        left: { style: "thin", color: { argb: "FFE5E7EB" } },
        bottom: { style: "thin", color: { argb: "FFE5E7EB" } },
        right: { style: "thin", color: { argb: "FFE5E7EB" } },
      };
    });
  }

  const buffer = await workbook.xlsx.writeBuffer();
  triggerBrowserDownload(new Uint8Array(buffer), "plantilla_import_template.xlsx");
}

export interface ScopeContextValidationResult {
  valid: boolean;
  errors: string[];
}

export function validateSpreadsheetScopeContext(
  rows: Record<string, string>[],
  expectedGroupName?: string,
  expectedAccountName?: string
): ScopeContextValidationResult {
  const errors: string[] = [];
  if (!rows || rows.length === 0) return { valid: true, errors };

  const norm = (s?: string) => (s ?? "").trim().toUpperCase();
  const expectedGroupNorm = norm(expectedGroupName);
  const expectedAccountNorm = norm(expectedAccountName);

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const rowNum = i + 2; // 1-based index, row 1 is header
    const rowGroup = norm(row.GROUP_NAME);
    const rowAccount = norm(row.ACCOUNT_NAME);

    if (expectedGroupNorm && rowGroup && rowGroup !== expectedGroupNorm) {
      if (errors.length < 5) {
        errors.push(
          `Row #${rowNum}: GROUP_NAME "${row.GROUP_NAME}" does not match selected group "${expectedGroupName}".`
        );
      }
    }

    if (expectedAccountNorm && rowAccount && rowAccount !== expectedAccountNorm) {
      if (errors.length < 5) {
        errors.push(
          `Row #${rowNum}: ACCOUNT_NAME "${row.ACCOUNT_NAME}" does not match selected account "${expectedAccountName}".`
        );
      }
    }
  }

  if (errors.length >= 5) {
    errors.push("Additional scope mismatch rows truncated...");
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

// ============================================================================
// 2. Vacancy Bulk Import Templates & Parser
// ============================================================================

export const VACANCY_REQUIRED_HEADERS = [
  "VCODE",
  "GROUP_NAME",
  "CHAIN",
  "ACCOUNT_NAME",
  "STORE_NAME",
  "POSITION",
  "HC",
  "EMPLOYMENT_TYPE",
  "REQUEST_TYPE",
  "VACANT_DATE",
  "PROVINCE",
  "CITY",
] as const;

export const VACANCY_OPTIONAL_HEADERS = [
  "TARGET_FILL_DATE",
  "HRCO",
  "CONTACT_NUMBER",
  "WITH_PENALTY",
  "APPLICANT_LAST_NAME",
  "APPLICANT_FIRST_NAME",
  "APPLICANT_MIDDLE_NAME",
  "APPLICANT_STATUS",
  "APPLICANT_SOURCE",
  "MIGRATION_SOURCE",
  "MIGRATION_NOTES",
] as const;

export const VACANCY_SAMPLE_ROW = [
  "VAC-MNL-001",
  "GROUP 2",
  "SUPER 8",
  "SUPER 8",
  "Super 8 Dau",
  "Merchandiser",
  "1",
  "stationary",
  "Replacement",
  "2026-05-01",
  "Pampanga",
  "Angeles",
  "2026-05-15",
  "Juan Coordinator",
  "09171234567",
  "no",
  "DELA CRUZ",
  "JUAN",
  "SANTOS",
  "For Interview / Intro",
  "facebook",
  "Google Sheets",
  "Imported from legacy tracker",
];

export function downloadVacancyImportTemplate(): void {
  if (typeof window === "undefined" || typeof document === "undefined") return;

  const wb = XLSX.utils.book_new();
  const headers = [...VACANCY_REQUIRED_HEADERS, ...VACANCY_OPTIONAL_HEADERS];
  const wsTemplate = XLSX.utils.aoa_to_sheet([headers, VACANCY_SAMPLE_ROW]);
  XLSX.utils.book_append_sheet(wb, wsTemplate, "IMPORT_TEMPLATE");

  const guideData = [
    ["COLUMN", "REQUIRED", "DESCRIPTION / FORMAT"],
    ["VCODE", "YES", "Unique vacancy code or requisition identifier."],
    ["GROUP_NAME", "YES", "Target operational group."],
    ["CHAIN", "YES", "Store chain name."],
    ["ACCOUNT_NAME", "YES", "Account client name."],
    ["STORE_NAME", "YES", "Store branch name."],
    ["POSITION", "YES", "Designation/job role."],
    ["HC", "YES", "Headcount demand (integer)."],
    ["EMPLOYMENT_TYPE", "YES", "stationary or roving."],
    ["REQUEST_TYPE", "YES", "Replacement, Additional, or New."],
    ["VACANT_DATE", "YES", "Requisition date in YYYY-MM-DD."],
    ["PROVINCE", "YES", "Store branch province."],
    ["CITY", "YES", "Store branch city."],
    ["TARGET_FILL_DATE", "NO", "Target fulfillment date in YYYY-MM-DD."],
    ["HRCO", "NO", "HR coordinator name."],
    ["CONTACT_NUMBER", "NO", "Applicant contact number."],
    ["WITH_PENALTY", "NO", "yes or no."],
    ["APPLICANT_LAST_NAME", "NO", "Candidate surname."],
    ["APPLICANT_FIRST_NAME", "NO", "Candidate first name."],
    ["APPLICANT_MIDDLE_NAME", "NO", "Candidate middle name."],
    ["APPLICANT_STATUS", "NO", "Current pipeline status."],
    ["APPLICANT_SOURCE", "NO", "Candidate sourcing channel."],
    ["MIGRATION_SOURCE", "NO", "Google Sheets, Excel, or Legacy."],
    ["MIGRATION_NOTES", "NO", "Administrative migration notes."],
  ];
  const wsGuide = XLSX.utils.aoa_to_sheet(guideData);
  XLSX.utils.book_append_sheet(wb, wsGuide, "VALIDATION_GUIDE");

  const arrayBuffer = XLSX.write(wb, { bookType: "xlsx", type: "array" });
  triggerBrowserDownload(new Uint8Array(arrayBuffer), "vacancy_import_template.xlsx");
}

// ============================================================================
// 3. MIKA Attendance & Biometric Template
// ============================================================================

export const MIKA_REQUIRED_HEADERS = [
  "Employee No.",
  "Fullname",
  "Account",
] as const;

export const MIKA_OPTIONAL_HEADERS = [
  "Store Name",
  "Position",
  "Birth Date",
  "Civil Status",
  "Address",
  "Contact No.",
  "Date Hired",
  "SSS",
  "PhilHealth",
  "Pag-IBIG",
  "TIN",
  "ATM No.",
] as const;

export const MIKA_SAMPLE_ROW = [
  "10001",
  "DELA CRUZ, JUAN SANTOS",
  "SUPER 8",
  "Super 8 Dau",
  "Merchandiser",
  "1990-05-15",
  "SINGLE",
  "123 Sample St Brgy Example",
  "09171234567",
  "2020-01-15",
  "33-1234567-8",
  "03-1234567-8",
  "1012-3456-7890",
  "123-456-789-000",
  "1234567890",
];

export function downloadMikaImportTemplate(): void {
  if (typeof window === "undefined" || typeof document === "undefined") return;

  const wb = XLSX.utils.book_new();
  const headers = [...MIKA_REQUIRED_HEADERS, ...MIKA_OPTIONAL_HEADERS];
  const wsTemplate = XLSX.utils.aoa_to_sheet([headers, MIKA_SAMPLE_ROW]);
  XLSX.utils.book_append_sheet(wb, wsTemplate, "IMPORT_TEMPLATE");

  const guideData = [
    ["COLUMN", "REQUIRED", "DESCRIPTION / FORMAT"],
    ["Employee No.", "YES", "Employee identifier (matching Plantilla)."],
    ["Fullname", "YES", "Format: LASTNAME, FIRSTNAME MIDDLE or LASTNAME, FIRSTNAME."],
    ["Account", "YES", "Operational account name."],
    ["Store Name", "NO", "Primary store assignment."],
    ["Position", "NO", "Role designation."],
    ["Birth Date", "NO", "Birthdate in YYYY-MM-DD or Excel serial."],
    ["Civil Status", "NO", "SINGLE, MARRIED, etc."],
    ["Address", "NO", "Residential address."],
    ["Contact No.", "NO", "10-11 digit contact number."],
    ["Date Hired", "NO", "Hiring date in YYYY-MM-DD."],
    ["SSS", "NO", "Social Security System number."],
    ["PhilHealth", "NO", "PhilHealth ID number."],
    ["Pag-IBIG", "NO", "Pag-IBIG MID number."],
    ["TIN", "NO", "Tax Identification Number."],
    ["ATM No.", "NO", "Payroll ATM account number."],
  ];
  const wsGuide = XLSX.utils.aoa_to_sheet(guideData);
  XLSX.utils.book_append_sheet(wb, wsGuide, "VALIDATION_GUIDE");

  const arrayBuffer = XLSX.write(wb, { bookType: "xlsx", type: "array" });
  triggerBrowserDownload(new Uint8Array(arrayBuffer), "mika_import_template.xlsx");
}

// ============================================================================
// 4. Payroll Reconciliation Template
// ============================================================================

export const PAYROLL_REQUIRED_HEADERS = [
  "EMPLOYEE_NUMBER",
  "FULL_NAME",
  "ACCOUNT_GROUP",
] as const;

export const PAYROLL_SAMPLE_ROWS = [
  ["10001", "DELA CRUZ, JUAN SANTOS", "GROUP 2 / SUPER 8"],
  ["10002", "REYES, MARIA ANA", "GROUP 3 / SAVEMORE"],
];

export function downloadPayrollCheckTemplate(): void {
  if (typeof window === "undefined" || typeof document === "undefined") return;

  const wb = XLSX.utils.book_new();
  const wsTemplate = XLSX.utils.aoa_to_sheet([
    [...PAYROLL_REQUIRED_HEADERS],
    ...PAYROLL_SAMPLE_ROWS,
  ]);
  XLSX.utils.book_append_sheet(wb, wsTemplate, "PAYROLL_TEMPLATE");

  const guideData = [
    ["COLUMN", "REQUIRED", "DESCRIPTION / FORMAT"],
    ["EMPLOYEE_NUMBER", "YES", "Primary match key. Must be unique per row. No blanks."],
    ["FULL_NAME", "YES", "Display field. Format: LASTNAME, FIRSTNAME or FIRSTNAME LASTNAME."],
    ["ACCOUNT_GROUP", "YES", "Combined Account / Group context (e.g. 'GROUP 2 / SUPER 8')."],
    ["", "", ""],
    ["RECONCILIATION RULES", "", ""],
    ["1. Missing in Payroll: Active Plantilla employees not appearing in payroll file."],
    ["2. Missing in Plantilla: Payroll rows with no matching Employee Number in active Plantilla."],
    ["3. Paid Inactive: Employees marked inactive/terminated in Plantilla but paid in payroll."],
    ["4. Mismatch: Name or Account mismatch between payroll file and Plantilla profile."],
    ["5. Duplicates: Multiple payroll entries with identical Employee Number in same upload."],
  ];
  const wsGuide = XLSX.utils.aoa_to_sheet(guideData);
  XLSX.utils.book_append_sheet(wb, wsGuide, "GUIDE");

  const arrayBuffer = XLSX.write(wb, { bookType: "xlsx", type: "array" });
  triggerBrowserDownload(new Uint8Array(arrayBuffer), "OHMployee_Payroll_Template.xlsx");
}

// ============================================================================
// Generic Parsing Helper
// ============================================================================

export async function parseSpreadsheetToRows(
  file: File,
): Promise<{ headers: string[]; rows: Record<string, string>[] }> {
  const buffer = await file.arrayBuffer();
  const wb = XLSX.read(buffer, { type: "array", cellDates: true });

  const firstSheetName = wb.SheetNames[0];
  if (!firstSheetName) {
    throw new Error("Spreadsheet contains no sheets.");
  }

  const sheet = wb.Sheets[firstSheetName];
  const rawMatrix = XLSX.utils.sheet_to_json<unknown[]>(sheet, {
    header: 1,
    defval: "",
    raw: false,
  });

  if (!rawMatrix || rawMatrix.length === 0) {
    throw new Error("Spreadsheet sheet is empty.");
  }

  const rawHeaders = (rawMatrix[0] as unknown[]).map((c) =>
    String(c ?? "").trim(),
  );

  const rows: Record<string, string>[] = [];
  for (let r = 1; r < rawMatrix.length; r++) {
    const rawRow = rawMatrix[r] as unknown[];
    if (!rawRow || rawRow.length === 0) continue;

    // Check if entire row is blank
    const hasValue = rawRow.some((val) => String(val ?? "").trim() !== "");
    if (!hasValue) continue;

    const rowObj: Record<string, string> = {};
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

function triggerBrowserDownload(bytes: Uint8Array, filename: string): void {
  const blob = new Blob([bytes as unknown as BlobPart], {
    type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
