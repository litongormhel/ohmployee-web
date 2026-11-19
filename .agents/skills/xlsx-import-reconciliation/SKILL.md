---
name: xlsx-import-reconciliation
description: >
  Standards and safeguards for spreadsheet batch imports (.xlsx / .csv), data
  reconciliation engines, and CSV exports in OHMployee Web (Plantilla Baseline,
  HR Emploc v3 Slot-First, Vacancy Import, Payroll Reconciliation, and MIKA
  Biometrics / Ghost Detection). Activate whenever creating, modifying, or
  debugging spreadsheet parsers, column header aliases, preview validators,
  batch rollback windows, or CSV download utilities.
license: MIT
---

# Spreadsheet Batch Import, Reconciliation & CSV Export Skill (`ohmployee-web`)

Governs all 5 spreadsheet batch ingestion channels and all CSV/Excel exports in `d:\Projects\ohmployee-web`.

## 1. The 5 Batch Import & Reconciliation Channels

| Channel | Core Utility / Module | Architectural Contract |
|---|---|---|
| **1. Plantilla Baseline Import (ADR-002)** | `src/lib/utils/plantilla_xlsx.ts` / Operations Hub (`/more`) | Enforces 8 store columns + 5 employee columns, blank row filtering, and scope matching (`validateSpreadsheetScopeContext`). **1 Store Name = 1 Permanent VCODE** within an Account. Vacant baseline rows (`employee_name` empty) are permitted. Middle name must be $\ge 2$ alpha chars or `'NA'` (single initials with trailing dots like `"S."` are stripped before length check). 72-hour rollback window with Zero-Edit Immutability Lock. |
| **2. HR Emploc Import v3 (Slot-First, ADR-001)** | `src/lib/utils/hr_emploc_xlsx.ts` (`xlsxToHrEmplocRows`, `buildParsePreview`) | Supports v3 slot-first and standard 7-column schema. Resolves header aliases, detects duplicate VCodes and duplicate candidate identities (`last_name + first_name + birth_date`), and transitions slots (`open` $\to$ `hr_processing` $\to$ `pipeline`) exclusively via `fn_set_slot_status`. |
| **3. Vacancy Batch Import** | Vacancy Import parser & validator | Strictly enforces 12 required headers and preserves existing applicant pipeline rows without clobbering active `plantilla_slots`. |
| **4. Payroll Reconciliation** | `src/lib/utils/payroll_reconciliation.ts` & `src/lib/queries/dataControl.ts` | Pure reconciliation engine classifying records into the 6-finding matrix: `clean`, `missingInPayroll`, `missingInPlantilla`, `paidInactive`, `mismatch`, and `duplicates`. Keep pure logic in `src/lib/utils/` free of circular dependencies. |
| **5. MIKA Biometric Import & Ghost Detection** | Operations Hub (`/more`) / `GhostDetectionCenterModal.tsx` | Dual anomaly classification: **Type A (Unregistered in Plantilla)** vs **Type B (Inactive Anomaly — clocking in while Separated/Inactive)**. Preserves weekly upload case continuity, 1-week SLA escalation (`48h HA` $\to$ `72h SA` $\to$ `>7d Breached`), coalesced statutory benefits hydration (never overwrites non-null benefits), and auto-resolution via `trg_ghost_resolve_on_plantilla_active`. |

## 2. Mandatory Parsing & Validation Rules

Whenever editing or adding an import parser in `src/lib/utils/`:

1. **Header Alias Normalization**:
   - Normalize raw spreadsheet headers by trimming whitespace, collapsing multiple spaces, converting to lowercase, and stripping punctuation before matching against canonical header alias maps.
   - Always return an explicit list of `missingColumns` when required headers are absent so the UI can display actionable feedback before hitting any Supabase RPC.
2. **Blank & Ghost Row Filtering**:
   - Excel files frequently contain trailing rows with empty cells or whitespace-only formatting. Filter out completely blank rows *before* running row-level validation or counting total rows.
3. **Middle Name & Identity Sanitization (ADR-002 Invariant)**:
   - Strip trailing periods (`.`) and surrounding spaces before checking middle name length.
   - Reject single-character initials (e.g., `"S"` or `"S."`); require either a full middle name ($\ge 2$ alphabetic characters) or the literal `'NA'` if the employee has no middle name.
4. **Scope & Island Group Guard**:
   - Verify that imported rows belong to the selected Account/Group scope (`validateSpreadsheetScopeContext`).
   - Never infer `province`, `city`, or `island_group` from free-text store names; `stores` Master (`fn_derive_island_group()`) is the sole authority.

## 3. CSV & Spreadsheet Export Security (Formula Injection Lock)

All CSV/Excel export generators (such as `src/lib/queries/hr_emploc.ts`, `src/lib/queries/vacancy/vacancyExport.ts`, `src/components/cencom/CencomDeploymentActivityTab.tsx`, and any new export utility) **MUST** neutralize CSV Formula Injection (CWE-1236):

1. **Sanitize Leading Formula Triggers**:
   - If a string cell begins with `=`, `+`, `-`, `@`, `\t` (`0x09`), or `\r` (`0x0D`) (including after leading whitespace if Excel could interpret it as a formula), prefix the value with a single quote (`'`) before RFC 4180 quote-escaping:
     ```ts
     function sanitizeCsvCell(raw: unknown): string {
       const str = String(raw ?? '');
       const safe = /^[=+\-@\t\r]/.test(str.trimStart()) ? `'${str}` : str;
       return `"${safe.replace(/"/g, '""')}"`;
     }
     ```
2. **Never Bypass Unit Test Coverage**:
   - Every change to an import parser or reconciliation engine must be verified against `src/lib/utils/__tests__/all_imports_sanity.test.mjs` via `npm test`.
