/**
 * Plantilla Import Pre-Validation Normalization Pipeline (ADR-002 Addendum R1 & R4)
 *
 * Enforces pure, functional pre-validation transformations on raw spreadsheet cell values
 * before any intra-batch or database cross-checks:
 * - String collapsing & uppercase conversion (LAST_NAME, FIRST_NAME, MIDDLE_NAME, ADDRESS, POSITION, CIVIL_STATUS)
 * - Mobile number canonicalization (+639 / 639 / 9 / 09 -> canonical 11-digit 09xxxxxxxxx)
 * - Date parsing to strict ISO (YYYY-MM-DD)
 * - Schedule days range expansion and rest-day carve-out
 */

import {
  DAYS_OF_WEEK,
  DAY_ALIAS_MAP,
  type DayCode,
  expandScheduleDays,
  resolveDutyAndRestDays,
  type ResolveDutyAndRestDaysResult,
} from "./schedule_normalizer.ts";

export {
  DAYS_OF_WEEK,
  DAY_ALIAS_MAP,
  type DayCode,
  expandScheduleDays,
  resolveDutyAndRestDays,
  type ResolveDutyAndRestDaysResult,
};

/**
 * Trims leading/trailing whitespace, collapses consecutive internal whitespace
 * into a single space, and converts the string to uppercase.
 */
export function collapseAndUppercase(val: unknown): string {
  if (val === null || val === undefined) return "";
  const str = String(val).trim();
  if (!str) return "";
  return str.replace(/\s+/g, " ").toUpperCase();
}

/**
 * Canonicalizes Philippine mobile numbers:
 * Strips whitespace, hyphens, parentheses, and dots.
 * Normalizes prefixes (+639xxxxxxxxx, 639xxxxxxxxx, 9xxxxxxxxx, 09xxxxxxxxx)
 * to standard 11-digit format: 09xxxxxxxxx.
 */
export function canonicalizeMobileNumber(raw: unknown): string {
  if (raw === null || raw === undefined) return "";
  const cleaned = String(raw).trim().replace(/[\s\-().]/g, "");
  if (!cleaned) return "";

  // +639XXXXXXXXX (13 chars) -> 09XXXXXXXXX
  if (/^\+639\d{9}$/.test(cleaned)) {
    return "0" + cleaned.slice(3);
  }

  // 639XXXXXXXXX (12 chars) -> 09XXXXXXXXX
  if (/^639\d{9}$/.test(cleaned)) {
    return "0" + cleaned.slice(2);
  }

  // 9XXXXXXXXX (10 chars) -> 09XXXXXXXXX
  if (/^9\d{9}$/.test(cleaned)) {
    return "0" + cleaned;
  }

  // 09XXXXXXXXX (11 chars) -> already canonical
  if (/^09\d{9}$/.test(cleaned)) {
    return cleaned;
  }

  // Fallback: return stripped digits/characters
  return cleaned;
}

const MONTH_NAME_MAP: Record<string, string> = {
  JAN: "01",
  JANUARY: "01",
  FEB: "02",
  FEBRUARY: "02",
  MAR: "03",
  MARCH: "03",
  APR: "04",
  APRIL: "04",
  MAY: "05",
  JUN: "06",
  JUNE: "06",
  JUL: "07",
  JULY: "07",
  AUG: "08",
  AUGUST: "08",
  SEP: "09",
  SEPT: "09",
  SEPTEMBER: "09",
  OCT: "10",
  OCTOBER: "10",
  NOV: "11",
  NOVEMBER: "11",
  DEC: "12",
  DECEMBER: "12",
};

/**
 * Parses and normalizes various date representations into strict ISO YYYY-MM-DD.
 * Handles:
 * - ISO strings (YYYY-MM-DD, YYYY-MM-DDTHH:mm:ss)
 * - Standard US/PH spreadsheet formats (MM/DD/YYYY, M/D/YYYY)
 * - Dash separated formats (MM-DD-YYYY, DD-MMM-YYYY)
 * - Excel serial date numbers (e.g. 44941)
 * - JS Date instances
 */
export function normalizeDateToIso(raw: unknown): string {
  if (raw === null || raw === undefined) return "";

  // Handle Date instances directly
  if (raw instanceof Date) {
    if (isNaN(raw.getTime())) return "";
    const y = raw.getFullYear();
    const m = String(raw.getMonth() + 1).padStart(2, "0");
    const d = String(raw.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }

  // Handle Excel serial date numbers
  if (typeof raw === "number" && !isNaN(raw)) {
    if (raw > 10000 && raw < 80000) {
      // Excel epoch: Dec 30, 1899 (accounting for 1900 leap year bug)
      const excelEpoch = new Date(Date.UTC(1899, 11, 30));
      const targetDate = new Date(excelEpoch.getTime() + raw * 86400000);
      const y = targetDate.getUTCFullYear();
      const m = String(targetDate.getUTCMonth() + 1).padStart(2, "0");
      const d = String(targetDate.getUTCDate()).padStart(2, "0");
      return `${y}-${m}-${d}`;
    }
  }

  const str = String(raw).trim();
  if (!str) return "";

  // Numeric string Excel serial (e.g. "44941")
  if (/^\d{5}$/.test(str)) {
    const num = Number(str);
    if (num > 10000 && num < 80000) {
      return normalizeDateToIso(num);
    }
  }

  // ISO Format YYYY-MM-DD or YYYY-M-D
  const isoMatch = str.match(/^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T\s].*)?$/);
  if (isoMatch) {
    const y = isoMatch[1];
    const m = isoMatch[2].padStart(2, "0");
    const d = isoMatch[3].padStart(2, "0");
    return `${y}-${m}-${d}`;
  }

  // Standard MM/DD/YYYY or M/D/YYYY
  const slashMatch = str.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (slashMatch) {
    const m = slashMatch[1].padStart(2, "0");
    const d = slashMatch[2].padStart(2, "0");
    const y = slashMatch[3];
    return `${y}-${m}-${d}`;
  }

  // MM-DD-YYYY or M-D-YYYY
  const dashMatch = str.match(/^(\d{1,2})-(\d{1,2})-(\d{4})$/);
  if (dashMatch) {
    const m = dashMatch[1].padStart(2, "0");
    const d = dashMatch[2].padStart(2, "0");
    const y = dashMatch[3];
    return `${y}-${m}-${d}`;
  }

  // Text month format (e.g. 15-Jan-2026 or 15 Jan 2026)
  const textMonthMatch = str.match(/^(\d{1,2})[-/\s]+([A-Za-z]+)[-/\s]+(\d{4})$/);
  if (textMonthMatch) {
    const d = textMonthMatch[1].padStart(2, "0");
    const monthKey = textMonthMatch[2].toUpperCase();
    const m = MONTH_NAME_MAP[monthKey];
    const y = textMonthMatch[3];
    if (m) {
      return `${y}-${m}-${d}`;
    }
  }

  // Fallback attempt with Date.parse
  const parsed = new Date(str);
  if (!isNaN(parsed.getTime())) {
    const y = parsed.getFullYear();
    const m = String(parsed.getMonth() + 1).padStart(2, "0");
    const d = String(parsed.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }

  return str;
}

/**
 * Computes exact employee age in full calendar years as of dateHired (or today).
 * Returns null if dates are invalid or unparseable.
 */
export function computeAgeAtHire(dateOfBirth: unknown, dateHired?: unknown): number | null {
  if (!dateOfBirth) return null;
  const dobIso = normalizeDateToIso(dateOfBirth);
  if (!dobIso || !/^\d{4}-\d{2}-\d{2}$/.test(dobIso)) return null;

  let targetDateStr = "";
  if (dateHired !== undefined && dateHired !== null && String(dateHired).trim() !== "") {
    const hiredIso = normalizeDateToIso(dateHired);
    if (!hiredIso || !/^\d{4}-\d{2}-\d{2}$/.test(hiredIso)) return null;
    targetDateStr = hiredIso;
  } else {
    targetDateStr = new Date().toISOString().slice(0, 10);
  }

  const [bYear, bMonth, bDay] = dobIso.split("-").map(Number);
  const [tYear, tMonth, tDay] = targetDateStr.split("-").map(Number);

  // In non-leap years, Feb 29 anniversary aligns on Feb 28 per Philippine Civil Code
  // and PostgreSQL interval arithmetic ('YYYY-02-29'::date + INTERVAL 'N years' = 'YYYY+N-02-28')
  const isLeapYear = (y: number) => (y % 4 === 0 && y % 100 !== 0) || (y % 400 === 0);
  const effectiveBDay = (!isLeapYear(tYear) && bMonth === 2 && bDay === 29) ? 28 : bDay;

  let age = tYear - bYear;
  const monthDiff = tMonth - bMonth;
  if (monthDiff < 0 || (monthDiff === 0 && tDay < effectiveBDay)) {
    age--;
  }

  return age;
}

/**
 * Normalizes a single Plantilla import row before dry-run or submission validation.
 */
export function normalizePlantillaRow(row: Record<string, string>): Record<string, string> {
  const normalized: Record<string, string> = { ...row };

  // 1. Strings: trim, collapse internal whitespace, convert to uppercase
  if ("LAST_NAME" in normalized) {
    normalized.LAST_NAME = collapseAndUppercase(normalized.LAST_NAME);
  }
  if ("FIRST_NAME" in normalized) {
    normalized.FIRST_NAME = collapseAndUppercase(normalized.FIRST_NAME);
  }
  if ("MIDDLE_NAME" in normalized) {
    normalized.MIDDLE_NAME = collapseAndUppercase(normalized.MIDDLE_NAME);
  }
  if ("ADDRESS" in normalized) {
    normalized.ADDRESS = collapseAndUppercase(normalized.ADDRESS);
  }
  if ("POSITION" in normalized) {
    normalized.POSITION = collapseAndUppercase(normalized.POSITION);
  }
  if ("CIVIL_STATUS" in normalized) {
    normalized.CIVIL_STATUS = collapseAndUppercase(normalized.CIVIL_STATUS);
  }

  // 2. Identifiers & Store metadata: trim and collapse spaces
  if ("EMPLOYEE_NO" in normalized) {
    normalized.EMPLOYEE_NO = (normalized.EMPLOYEE_NO ?? "").trim().toUpperCase();
  }
  if ("VCODE" in normalized) {
    normalized.VCODE = (normalized.VCODE ?? "").trim().toUpperCase();
  }
  if ("GROUP_NAME" in normalized) {
    normalized.GROUP_NAME = (normalized.GROUP_NAME ?? "").trim().replace(/\s+/g, " ");
  }
  if ("ACCOUNT_NAME" in normalized) {
    normalized.ACCOUNT_NAME = (normalized.ACCOUNT_NAME ?? "").trim().replace(/\s+/g, " ");
  }
  if ("MOTHER_ACCOUNT" in normalized) {
    normalized.MOTHER_ACCOUNT = (normalized.MOTHER_ACCOUNT ?? "").trim().replace(/\s+/g, " ");
  }
  if ("STORE_NAME" in normalized) {
    normalized.STORE_NAME = (normalized.STORE_NAME ?? "").trim().replace(/\s+/g, " ");
  }
  if ("AREA_PROVINCE" in normalized) {
    normalized.AREA_PROVINCE = (normalized.AREA_PROVINCE ?? "").trim().replace(/\s+/g, " ");
  }
  if ("AREA_CITY" in normalized) {
    normalized.AREA_CITY = (normalized.AREA_CITY ?? "").trim().replace(/\s+/g, " ");
  }
  if ("COORDINATOR" in normalized) {
    normalized.COORDINATOR = (normalized.COORDINATOR ?? "").trim().replace(/\s+/g, " ");
  }
  if ("HRCO_EMAIL" in normalized) {
    normalized.HRCO_EMAIL = (normalized.HRCO_EMAIL ?? "").trim().toLowerCase();
  }
  if ("RATE" in normalized) {
    normalized.RATE = (normalized.RATE ?? "").trim();
  }

  // 3. Contact Numbers: canonicalize to 09xxxxxxxxx
  if ("CONTACT_NO" in normalized) {
    normalized.CONTACT_NO = canonicalizeMobileNumber(normalized.CONTACT_NO);
  }
  if ("CONTACT" in normalized) {
    normalized.CONTACT = canonicalizeMobileNumber(normalized.CONTACT);
  }

  // 4. Dates: parse to ISO YYYY-MM-DD
  if ("DATE_HIRED" in normalized) {
    normalized.DATE_HIRED = normalizeDateToIso(normalized.DATE_HIRED);
  }
  if ("DATE_OF_BIRTH" in normalized) {
    normalized.DATE_OF_BIRTH = normalizeDateToIso(normalized.DATE_OF_BIRTH);
  }
  if ("BIRTHDATE" in normalized) {
    normalized.BIRTHDATE = normalizeDateToIso(normalized.BIRTHDATE);
  }

  // 5. Schedule Days & Dayoff: expand ranges and carve out rest days
  const schedRaw = normalized.SCHEDULE_DAYS ?? normalized.SCHEDULE ?? "";
  const dayoffRaw = normalized.DAYOFF ?? "";
  if (schedRaw || dayoffRaw) {
    const schedResult = resolveDutyAndRestDays(schedRaw, dayoffRaw);
    if ("SCHEDULE_DAYS" in normalized || schedRaw) {
      normalized.SCHEDULE_DAYS = schedResult.scheduleDays;
    }
    if ("SCHEDULE" in normalized) {
      normalized.SCHEDULE = schedResult.scheduleDays;
    }
    if ("DAYOFF" in normalized || dayoffRaw) {
      normalized.DAYOFF = schedResult.dayoff;
    }
    if (schedResult.error) {
      normalized.__scheduleError = schedResult.error;
    }
  }

  if ("SCHEDULE_TIME" in normalized) {
    normalized.SCHEDULE_TIME = (normalized.SCHEDULE_TIME ?? "").trim();
  }

  return normalized;
}

export interface PlantillaBatchValidationIssue {
  rowNumber: number;
  field?: string;
  conflictType?: string;
  flag?: string;
  msg: string;
}

export interface CoalescePlantillaBatchResult {
  coalescedRows: Record<string, string>[];
  errors: PlantillaBatchValidationIssue[];
  flags: PlantillaBatchValidationIssue[];
}

/**
 * Executes multi-row coalescing and intra-batch invariants across an import batch (R2 & R3):
 * - Groups rows by EMPLOYEE_NO.
 * - Hard-blocks intra-batch core identity mismatches (LAST_NAME, FIRST_NAME, MIDDLE_NAME, DATE_HIRED).
 * - Hard-blocks if POSITION is blank across all rows for an EMPLOYEE_NO.
 * - Coalesces demographic (CIVIL_STATUS, DATE_OF_BIRTH, CONTACT_NO, ADDRESS), RATE, DAYOFF, and POSITION
 *   across blank rows, emitting warning flags on conflicting non-blank values and applying last-row-wins.
 * - Enforces 18+ Minimum Age Invariant as of DATE_HIRED (or reference date).
 */
export function coalescePlantillaBatch(rawRows: Record<string, string>[]): CoalescePlantillaBatchResult {
  const normalizedRows = rawRows.map(normalizePlantillaRow);
  const coalescedRows = normalizedRows.map((r) => ({ ...r }));
  const errors: PlantillaBatchValidationIssue[] = [];
  const flags: PlantillaBatchValidationIssue[] = [];

  // 0. Schedule Normalization Errors (unrecognized day tokens, rest-day exhaustion)
  coalescedRows.forEach((row, idx) => {
    if (row.__scheduleError) {
      errors.push({
        rowNumber: idx + 1,
        field: "SCHEDULE_DAYS",
        conflictType: "invalid_schedule_days",
        msg: row.__scheduleError,
      });
    }
  });

  const empGroups = new Map<string, number[]>();
  coalescedRows.forEach((row, idx) => {
    const empNo = (row.EMPLOYEE_NO ?? "").trim().toUpperCase();
    if (empNo) {
      if (!empGroups.has(empNo)) empGroups.set(empNo, []);
      empGroups.get(empNo)!.push(idx);
    }
  });

  for (const [empNo, indices] of empGroups.entries()) {
    // 1. Core Identity Invariants: LAST_NAME, FIRST_NAME, MIDDLE_NAME, DATE_HIRED
    const lastNames = new Set(indices.map((i) => coalescedRows[i].LAST_NAME).filter(Boolean));
    const firstNames = new Set(indices.map((i) => coalescedRows[i].FIRST_NAME).filter(Boolean));
    const middleNames = new Set(indices.map((i) => coalescedRows[i].MIDDLE_NAME).filter(Boolean));
    const datesHired = new Set(indices.map((i) => coalescedRows[i].DATE_HIRED).filter(Boolean));

    if (lastNames.size > 1) {
      for (const i of indices) {
        errors.push({
          rowNumber: i + 1,
          field: "LAST_NAME",
          conflictType: "core_identity_mismatch_in_batch",
          msg: `Core identity mismatch across rows for EMPLOYEE_NO ${empNo}: distinct LAST_NAME values in batch`,
        });
      }
    }
    if (firstNames.size > 1) {
      for (const i of indices) {
        errors.push({
          rowNumber: i + 1,
          field: "FIRST_NAME",
          conflictType: "core_identity_mismatch_in_batch",
          msg: `Core identity mismatch across rows for EMPLOYEE_NO ${empNo}: distinct FIRST_NAME values in batch`,
        });
      }
    }
    if (middleNames.size > 1) {
      for (const i of indices) {
        errors.push({
          rowNumber: i + 1,
          field: "MIDDLE_NAME",
          conflictType: "core_identity_mismatch_in_batch",
          msg: `Core identity mismatch across rows for EMPLOYEE_NO ${empNo}: distinct MIDDLE_NAME values in batch`,
        });
      }
    }
    if (datesHired.size > 1) {
      for (const i of indices) {
        errors.push({
          rowNumber: i + 1,
          field: "DATE_HIRED",
          conflictType: "core_identity_mismatch_in_batch",
          msg: `Core identity mismatch across rows for EMPLOYEE_NO ${empNo}: distinct DATE_HIRED values in batch`,
        });
      }
    }

    // 2. Role / POSITION check: hard-block if blank across all rows
    const positions = indices.map((i) => coalescedRows[i].POSITION).filter(Boolean);
    if (positions.length === 0) {
      for (const i of indices) {
        errors.push({
          rowNumber: i + 1,
          field: "POSITION",
          conflictType: "position_required",
          msg: `POSITION is blank across all rows for EMPLOYEE_NO ${empNo}`,
        });
      }
    }

    // 3. Demographics, Rate, Rest Day & Position Coalescing
    const COALESCE_FIELDS = [
      "CIVIL_STATUS",
      "RATE",
      "DATE_OF_BIRTH",
      "CONTACT_NO",
      "ADDRESS",
      "DAYOFF",
      "POSITION",
    ] as const;

    for (const field of COALESCE_FIELDS) {
      const getFieldVal = (r: Record<string, string>): string => {
        if (field === "DATE_OF_BIRTH") {
          return (r.DATE_OF_BIRTH || r.BIRTHDATE || "").trim();
        }
        if (field === "CONTACT_NO") {
          return (r.CONTACT_NO || r.CONTACT || "").trim();
        }
        return (r[field] || "").trim();
      };

      const nonBlankVals = indices
        .map((i) => getFieldVal(coalescedRows[i]))
        .filter((v) => v !== "");

      if (nonBlankVals.length > 0) {
        const lastVal = nonBlankVals[nonBlankVals.length - 1];
        const distinctVals = new Set(nonBlankVals);

        if (distinctVals.size > 1) {
          for (const i of indices) {
            flags.push({
              rowNumber: i + 1,
              flag: `conflict_${field.toLowerCase()}`,
              msg: `Conflicting ${field} in batch for employee ${empNo}; last row value "${lastVal}" will be used`,
            });
          }
        }

        // Auto-fill blank rows in the group, and enforce last-row-wins on conflict
        for (const i of indices) {
          const currentVal = getFieldVal(coalescedRows[i]);
          if (distinctVals.size > 1 || !currentVal) {
            if (field === "DATE_OF_BIRTH") {
              coalescedRows[i].DATE_OF_BIRTH = lastVal;
              coalescedRows[i].BIRTHDATE = lastVal;
            } else if (field === "CONTACT_NO") {
              coalescedRows[i].CONTACT_NO = lastVal;
              coalescedRows[i].CONTACT = lastVal;
            } else {
              coalescedRows[i][field] = lastVal;
            }
          }
        }
      }
    }

    // 4. Minimum Age (18+) Invariant relative to DATE_HIRED
    for (const i of indices) {
      const row = coalescedRows[i];
      const dob = row.DATE_OF_BIRTH || row.BIRTHDATE;
      if (dob && dob.trim() !== "") {
        const age = computeAgeAtHire(dob, row.DATE_HIRED);
        if (age !== null && age < 18) {
          errors.push({
            rowNumber: i + 1,
            field: "DATE_OF_BIRTH",
            conflictType: "underage_employee_under_18",
            msg: `Underage employee: computed age as of DATE_HIRED (${row.DATE_HIRED}) is under 18 years old (DOB: ${dob}, age: ${age}). Minimum legal working age is 18.`,
          });
        }
      }
    }
  }

  return { coalescedRows, errors, flags };
}

/**
 * Normalizes an array of Plantilla import rows using row-level pre-validation normalization.
 */
export function normalizePlantillaRows(rows: Record<string, string>[]): Record<string, string>[] {
  return rows.map(normalizePlantillaRow);
}
