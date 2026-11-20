import ExcelJS from "exceljs";

// ─────────────────────────────────────────────────────────────────────────────
// Constants & Types
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Authoritative ADR-001 v3 slot-first schema required by backend RPC.
 */
export const V3_REQUIRED_HEADERS = [
  "GROUP",
  "ACCOUNT",
  "VCODE",
  "LAST_NAME",
  "FIRST_NAME",
  "MIDDLE_NAME",
  "DATE_HIRED",
] as const;

/**
 * Standard schema with Store Name, Position, Employee No.
 */
export const STANDARD_REQUIRED_HEADERS = [
  "STORE_NAME",
  "ACCOUNT",
  "POSITION",
  "FIRST_NAME",
  "LAST_NAME",
  "MIDDLE_NAME",
  "EMPLOYEE_NO",
] as const;

export interface HrEmplocRowPreview {
  rowNum: number;
  passedBasicCheck: boolean;
  lastName: string;
  firstName: string;
  middleName: string;
  vcode: string;
  accountName: string;
  groupName: string;
  dateHired: string;
  storeName?: string;
  positionName?: string;
  clientErrors: string[];
  rawRow: Record<string, string>;
}

export interface HrEmplocParsePreview {
  totalRows: number;
  clientValidRows: number;
  clientInvalidRows: number;
  hasSubmittableRows: boolean;
  previews: HrEmplocRowPreview[];
  submittableRows: Record<string, string>[];
}

const VALID_NAME_CHARS_REGEX = /^[A-Za-z0-9 '.\-Ññ]+$/;
const NA_SLASH_PATTERN = /^N\s*\/\s*A$/i;
const PLACEHOLDERS = new Set(["-", ".", "?"]);

function hasValidNameChars(val: string): boolean {
  return VALID_NAME_CHARS_REGEX.test(val);
}

// ─────────────────────────────────────────────────────────────────────────────
// Template Generator Utility
// ─────────────────────────────────────────────────────────────────────────────

function cellValueToString(val: unknown): string {
  if (val === null || val === undefined) return "";
  if (val instanceof Date) return val.toISOString().slice(0, 10);
  if (typeof val === "object") {
    const obj = val as Record<string, unknown>;
    if ("result" in obj && obj.result !== undefined) return cellValueToString(obj.result);
    if ("richText" in obj && Array.isArray(obj.richText)) {
      return obj.richText.map((r: { text?: string }) => r?.text ?? "").join("").trim();
    }
    if ("text" in obj && typeof obj.text === "string") return obj.text.trim();
  }
  return String(val).trim();
}

/**
 * Generates official Excel workbook with template sheets and validation guidelines.
 */
export async function buildHrEmplocImportTemplateXlsx(
  variant: "v3" | "standard" = "v3",
): Promise<Uint8Array> {
  const wb = new ExcelJS.Workbook();

  if (variant === "standard") {
    const headers = [...STANDARD_REQUIRED_HEADERS];
    const sampleRow = [
      "SM Mall of Asia",
      "Account Alpha",
      "Sales Associate",
      "JUAN",
      "DELA CRUZ",
      "SANTOS",
      "V-2026-001",
    ];
    const ws = wb.addWorksheet("IMPORT_TEMPLATE");
    ws.addRow(headers);
    ws.addRow(sampleRow);
  } else {
    const headers = [...V3_REQUIRED_HEADERS];
    const sampleRow = [
      "Group Alpha",
      "Account Alpha",
      "V-2026-001",
      "DELA CRUZ",
      "JUAN",
      "SANTOS",
      "2026-01-15",
    ];
    const ws = wb.addWorksheet("IMPORT_TEMPLATE");
    ws.addRow(headers);
    ws.addRow(sampleRow);

    const standardHeaders = [...STANDARD_REQUIRED_HEADERS];
    const standardSample = [
      "SM Mall of Asia",
      "Account Alpha",
      "Sales Associate",
      "JUAN",
      "DELA CRUZ",
      "SANTOS",
      "V-2026-001",
    ];
    const wsStandard = wb.addWorksheet("STANDARD_SCHEMA");
    wsStandard.addRow(standardHeaders);
    wsStandard.addRow(standardSample);
  }

  // Validation Guide Sheet
  const guideData = [
    ["COLUMN", "REQUIRED", "FORMAT / NOTES"],
    [
      "GROUP",
      "YES",
      "Must match the operational group selected during upload. One group per file only.",
    ],
    ["ACCOUNT", "YES", "Must match an authorized account in the selected group."],
    [
      "VCODE",
      "YES",
      "Authoritative Plantilla slot reference (e.g. V-2026-001). Store, position, and employment type are resolved directly from the slot.",
    ],
    ["LAST_NAME", "YES", "Surname only. Allowed: letters, spaces, hyphen, apostrophe, period, Ñ/ñ."],
    ["FIRST_NAME", "YES", "Given name. Allowed: letters, spaces, hyphen, apostrophe, period, Ñ/ñ."],
    [
      "MIDDLE_NAME",
      "YES",
      "Middle name. Use 'NA' if none exists. 'N/A' or single letter initials are rejected.",
    ],
    ["DATE_HIRED", "YES", "Date hired in YYYY-MM-DD format (e.g. 2026-01-15)."],
    ["", "", ""],
    ["IMPORTANT RULES", "", ""],
    ["1. All rows must belong to a single operational group.", "", ""],
    [
      "2. VCode must point to an open, valid Plantilla slot. Occupied or closed slots will be blocked.",
      "",
      "",
    ],
    ["3. Duplicate VCodes or identical candidates within the file will be flagged.", "", ""],
    [
      "4. Approval requires Head Admin or Super Admin review. Blocked rows are excluded.",
      "",
      "",
    ],
  ];

  const wsGuide = wb.addWorksheet("VALIDATION_GUIDE");
  for (const row of guideData) {
    wsGuide.addRow(row);
  }

  const arrayBuffer = await wb.xlsx.writeBuffer();
  return new Uint8Array(arrayBuffer);
}

/**
 * Downloads the XLSX template in the browser.
 */
export async function downloadHrEmplocTemplate(
  variant: "v3" | "standard" = "v3",
  filename = "hr_emploc_import_template.xlsx",
): Promise<void> {
  if (typeof window === "undefined" || typeof document === "undefined") {
    return;
  }
  const bytes = await buildHrEmplocImportTemplateXlsx(variant);
  const blob = new Blob([bytes as unknown as BlobPart], {
    type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
  URL.revokeObjectURL(url);
}

// ─────────────────────────────────────────────────────────────────────────────
// File Parsing & Client-Side Validation Utility
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Parses raw ArrayBuffer or Uint8Array of XLSX file into key-value rows.
 */
export async function xlsxToHrEmplocRows(
  buffer: ArrayBuffer | Uint8Array,
): Promise<Record<string, string>[]> {
  try {
    const wb = new ExcelJS.Workbook();
    const rawBuf =
      buffer instanceof Uint8Array
        ? buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength)
        : buffer;
    await wb.xlsx.load(rawBuf as ArrayBuffer);
    if (!wb.worksheets || wb.worksheets.length === 0) return [];

    const ws =
      wb.getWorksheet("IMPORT_TEMPLATE") ?? wb.worksheets[0];
    if (!ws || ws.rowCount < 2) return [];

    const headerRow = ws.getRow(1);
    const headers: string[] = [];
    for (let c = 1; c <= headerRow.cellCount; c++) {
      headers.push(cellValueToString(headerRow.getCell(c).value).toUpperCase());
    }

    const rows: Record<string, string>[] = [];
    for (let r = 2; r <= ws.rowCount; r++) {
      const row = ws.getRow(r);
      const normalized: Record<string, string> = {};
      let hasAnyValue = false;
      for (let c = 0; c < headers.length; c++) {
        const key = headers[c];
        if (!key) continue;
        const val = cellValueToString(row.getCell(c + 1).value);
        if (val !== "") hasAnyValue = true;
        normalized[key] = val;
      }
      if (hasAnyValue) {
        rows.push(normalized);
      }
    }
    return rows;
  } catch (err) {
    console.error("[hr_emploc_xlsx] Error parsing XLSX buffer:", err);
    return [];
  }
}

/**
 * Validates and cleans middle names matching mobile normalization contract.
 */
export function normalizeMiddleName(raw: string): {
  normalized: string;
  error?: string;
} {
  const trimmed = raw.trim();

  if (trimmed.length === 0) {
    return {
      normalized: "",
      error: "Middle Name is required. Use 'NA' if the employee has no middle name.",
    };
  }

  if (NA_SLASH_PATTERN.test(trimmed)) {
    return {
      normalized: "NA",
      error: "Use 'NA' instead of 'N/A' for employees without a middle name.",
    };
  }

  if (PLACEHOLDERS.has(trimmed)) {
    return {
      normalized: "",
      error: "Middle Name is invalid. Use a valid middle name or 'NA' if none exists.",
    };
  }

  if (trimmed.toUpperCase() === "NA") {
    return { normalized: "NA" };
  }

  if (!hasValidNameChars(trimmed)) {
    return {
      normalized: trimmed,
      error:
        "MIDDLE_NAME contains invalid characters. Only letters, spaces, hyphen (-), apostrophe ('), period (.), and Ñ/ñ are allowed.",
    };
  }

  // Remove any trailing dot (e.g. "Del." -> "Del", "S." -> "S")
  const cleaned = trimmed.replace(/\.+$/, "");

  if (cleaned.length < 2) {
    return {
      normalized: cleaned,
      error: "Middle Name must contain at least two characters, or use 'NA' if none exists.",
    };
  }

  return { normalized: cleaned };
}

/**
 * Client-side validation preview before submission.
 * Enforces non-empty required fields, mobile middle name rules,
 * duplicate checks, and cross-group coherence.
 */
export function buildParsePreview(
  rows: Record<string, string>[],
  selectedGroupName: string,
): HrEmplocParsePreview {
  const previews: HrEmplocRowPreview[] = [];
  const submittableRows: Record<string, string>[] = [];
  let clientValid = 0;
  let clientInvalid = 0;

  const seenVcodes = new Set<string>();
  const seenIdentities = new Set<string>();

  for (let i = 0; i < rows.length; i++) {
    const raw = rows[i];
    const clientErrors: string[] = [];

    // Header aliases support (v3 vs Standard)
    const vcode = (raw.VCODE || raw.EMPLOYEE_NO || raw.EMPLOYEE_ID || "").trim();
    const account = (raw.ACCOUNT || raw.ACCOUNT_NAME || "").trim();
    const lastName = (raw.LAST_NAME || raw.SURNAME || "").trim();
    const firstName = (raw.FIRST_NAME || raw.GIVEN_NAME || "").trim();
    const rawMiddle = (raw.MIDDLE_NAME || raw.MIDDLENAME || "").trim();
    let group = (raw.GROUP || raw.GROUP_NAME || "").trim();
    let dateHired = (raw.DATE_HIRED || raw.HIRE_DATE || "").trim();

    const storeName = (raw.STORE_NAME || raw.STORE || "").trim();
    const positionName = (raw.POSITION || raw.POSITION_NAME || "").trim();

    // If group is missing in file but selectedGroupName is given, adopt it
    if (!group && selectedGroupName) {
      group = selectedGroupName;
    }

    // If date hired is missing, format default YYYY-MM-DD
    if (!dateHired) {
      const now = new Date();
      dateHired = now.toISOString().slice(0, 10);
    }

    // Required checks
    if (!group) {
      clientErrors.push("GROUP is required");
    }
    if (!account) {
      clientErrors.push("ACCOUNT is required");
    }
    if (!vcode) {
      clientErrors.push("VCODE / Employee No is required");
    }
    if (!lastName) {
      clientErrors.push("LAST_NAME is required");
    }
    if (!firstName) {
      clientErrors.push("FIRST_NAME is required");
    }

    // Name characters
    if (lastName && !hasValidNameChars(lastName)) {
      clientErrors.push(
        "LAST_NAME contains invalid characters. Only letters, spaces, hyphen (-), apostrophe ('), period (.), and Ñ/ñ are allowed.",
      );
    }
    if (firstName && !hasValidNameChars(firstName)) {
      clientErrors.push(
        "FIRST_NAME contains invalid characters. Only letters, spaces, hyphen (-), apostrophe ('), period (.), and Ñ/ñ are allowed.",
      );
    }

    // Middle name validation
    const middleResult = normalizeMiddleName(rawMiddle);
    if (middleResult.error) {
      clientErrors.push(middleResult.error);
    }
    const cleanMiddle = middleResult.normalized || "NA";

    // Date format check
    if (dateHired && isNaN(Date.parse(dateHired))) {
      clientErrors.push("DATE_HIRED must be a valid date in YYYY-MM-DD format");
    }

    // Cross-group check
    if (
      group &&
      selectedGroupName &&
      group.toUpperCase() !== selectedGroupName.toUpperCase()
    ) {
      clientErrors.push(
        `GROUP "${group}" does not match selected group "${selectedGroupName}"`,
      );
    }

    // In-file duplicate VCode / Employee No
    if (vcode) {
      const upperVcode = vcode.toUpperCase();
      if (seenVcodes.has(upperVcode)) {
        clientErrors.push(`Duplicate VCode "${vcode}" appears more than once in this file`);
      } else {
        seenVcodes.add(upperVcode);
      }
    }

    // In-file duplicate Candidate Identity
    if (lastName && firstName && account) {
      const identity = `${lastName.toUpperCase()}|${firstName.toUpperCase()}|${cleanMiddle.toUpperCase()}|${account.toUpperCase()}|${dateHired}`;
      if (seenIdentities.has(identity)) {
        clientErrors.push("Duplicate candidate within this file (same name, account, and date hired)");
      } else {
        seenIdentities.add(identity);
      }
    }

    const passed = clientErrors.length === 0;
    if (passed) {
      clientValid++;
      submittableRows.push({
        GROUP: group,
        ACCOUNT: account,
        VCODE: vcode,
        LAST_NAME: lastName,
        FIRST_NAME: firstName,
        MIDDLE_NAME: cleanMiddle,
        DATE_HIRED: dateHired,
        STORE_NAME: storeName,
        POSITION: positionName,
      });
    } else {
      clientInvalid++;
    }

    previews.push({
      rowNum: i + 1,
      passedBasicCheck: passed,
      lastName,
      firstName,
      middleName: cleanMiddle,
      vcode,
      accountName: account,
      groupName: group,
      dateHired,
      storeName: storeName || undefined,
      positionName: positionName || undefined,
      clientErrors,
      rawRow: raw,
    });
  }

  return {
    totalRows: rows.length,
    clientValidRows: clientValid,
    clientInvalidRows: clientInvalid,
    hasSubmittableRows: clientValid > 0,
    previews,
    submittableRows,
  };
}
