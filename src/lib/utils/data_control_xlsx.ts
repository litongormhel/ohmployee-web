import * as XLSX from "xlsx";

// ============================================================================
// 1. Plantilla Bulk Import Templates & Parser
// ============================================================================

export const PLANTILLA_REQUIRED_HEADERS = [
  "GROUP_NAME",
  "ACCOUNT_NAME",
  "VCODE",
  "STORE_NAME",
  "AREA_PROVINCE",
  "AREA_CITY",
  "POSITION",
  "EMPLOYMENT_TYPE",
  "REQUIRED_HC",
  "WITH_PENALTY",
  "EMPLOYEE_NO",
  "LAST_NAME",
  "FIRST_NAME",
  "MIDDLE_NAME",
  "DATE_HIRED",
] as const;

export const PLANTILLA_OPTIONAL_HEADERS = [
  "CIVIL_STATUS",
  "RATE",
  "DATE_OF_BIRTH",
  "CONTACT_NO",
  "ADDRESS",
  "SCHEDULE",
  "DAYOFF",
  "COORDINATOR",
  "HRCO_EMAIL",
] as const;

export const PLANTILLA_SAMPLE_ROW = [
  "GROUP 2",
  "SUPER 8",
  "SLOT-SAMPLE-001",
  "Super 8 Sample Branch",
  "Pampanga",
  "Angeles",
  "Merchandiser",
  "stationary",
  "1",
  "yes",
  "EMP-SAMPLE-001",
  "DELA CRUZ",
  "JUAN",
  "SANTOS",
  "2026-01-15",
  "SINGLE",
  "600.00",
  "1995-05-15",
  "09171234567",
  "123 Sample St Brgy Example",
  "MON-SAT",
  "SUN",
  "Operations Coordinator",
  "",
];

export function downloadPlantillaImportTemplate(): void {
  if (typeof window === "undefined" || typeof document === "undefined") return;

  const wb = XLSX.utils.book_new();

  // Template Sheet
  const headers = [...PLANTILLA_REQUIRED_HEADERS, ...PLANTILLA_OPTIONAL_HEADERS];
  const wsTemplate = XLSX.utils.aoa_to_sheet([headers, PLANTILLA_SAMPLE_ROW]);
  XLSX.utils.book_append_sheet(wb, wsTemplate, "IMPORT_TEMPLATE");

  // Guide Sheet
  const guideData = [
    ["COLUMN", "REQUIRED", "DESCRIPTION / FORMAT"],
    ["GROUP_NAME", "YES", "Group scope (e.g. GROUP 2). Must match selected group context."],
    ["ACCOUNT_NAME", "YES", "Account name under the selected group (e.g. SUPER 8)."],
    ["VCODE", "YES", "Unique store vacancy slot code (e.g. PG-DAU-001)."],
    ["STORE_NAME", "YES", "Official store branch name."],
    ["AREA_PROVINCE", "YES", "Store province."],
    ["AREA_CITY", "YES", "Store city or municipality."],
    ["POSITION", "YES", "Target position designation (e.g. Merchandiser)."],
    ["EMPLOYMENT_TYPE", "YES", "stationary or roving."],
    ["REQUIRED_HC", "YES", "Integer required headcount (typically 1)."],
    ["WITH_PENALTY", "YES", "yes or no (determines vacancy penalty)."],
    ["EMPLOYEE_NO", "YES", "Unique company employee ID."],
    ["LAST_NAME", "YES", "Employee surname."],
    ["FIRST_NAME", "YES", "Employee given name."],
    ["MIDDLE_NAME", "YES", "Employee middle name or NA."],
    ["DATE_HIRED", "YES", "Hiring date in YYYY-MM-DD format."],
    ["CIVIL_STATUS", "NO", "SINGLE, MARRIED, WIDOWED, etc."],
    ["RATE", "NO", "Daily wage rate (decimal number)."],
    ["DATE_OF_BIRTH", "NO", "Birth date in YYYY-MM-DD format."],
    ["CONTACT_NO", "NO", "Mobile contact number (10-11 digits)."],
    ["ADDRESS", "NO", "Full residential address."],
    ["SCHEDULE", "NO", "Work week schedule (e.g. MON-SAT)."],
    ["DAYOFF", "NO", "Designated day off (e.g. SUN)."],
    ["COORDINATOR", "NO", "Designated Operations Coordinator."],
    ["HRCO_EMAIL", "NO", "Assigned HR Coordinator email (optional)."],
  ];
  const wsGuide = XLSX.utils.aoa_to_sheet(guideData);
  XLSX.utils.book_append_sheet(wb, wsGuide, "VALIDATION_GUIDE");

  const arrayBuffer = XLSX.write(wb, { bookType: "xlsx", type: "array" });
  triggerBrowserDownload(new Uint8Array(arrayBuffer), "plantilla_import_template.xlsx");
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
