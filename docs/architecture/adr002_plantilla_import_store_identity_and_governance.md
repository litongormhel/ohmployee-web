# ADR-002: Plantilla Import, Store Identity, Headcount Governance & Rollback Architecture

- **Status:** Approved & Locked
- **Date:** 2026-10-23
- **Author:** Antigravity / Engineering & Data Platform
- **Scope:** Plantilla Baseline Import, Store Identity (1 Store = 1 VCODE), Roving Headcount Fractions ($1/N$), Coverage Group Overlay (`CGCODE`), Validation, and Batch Rollback Governance.
- **Supersedes / Amends:**
  - Partially supersedes `plantilla_slot_architecture.md`
  - Partially supersedes `vcode_slot_bridge_redesign.md`
  - Partially supersedes `coverage_group_roving_architecture_plan.md`

---

## Executive Summary

This Architecture Decision Record (ADR-002) establishes the definitive system of record rules for Store Identity, Plantilla Import validation, Headcount computation, and Rollback governance across OHMployee and OHMployee Web. It resolves historical discrepancies between legacy slot assumptions and operational realities by locking in ten core invariants.

---

## The 10 Architectural Invariants

### Invariant 1 — Plantilla as Upstream Source of Truth
Plantilla Baseline Import is the primary upstream origin for stores, slots, and initial employee allocations in the system.
- Batches and rows may be uploaded without an employee (creating vacant baseline slots on fresh VCODEs).
- Downstream imports (`Vacancy Import` and `HR Emploc Import`) must validate that any referenced `VCODE` already exists in Plantilla (`stores` / `plantilla_slots`) before accepting records. Uploading downstream records for unseeded VCODEs is blocked.

### Invariant 2 — Permanent 1 Store Name = 1 VCODE Identity
Within an Account, 1 `STORE_NAME` maps 1:1 to 1 `VCODE`.
- Even if 10 employees are assigned to that store, all employees and slots share the store's single `VCODE` with distinct, sequential `slot_ordinal`s (1..N).
- Same `STORE_NAME` with a different `VCODE` within the Account is hard-blocked.
- Same `VCODE` with a different `STORE_NAME` within the Account is hard-blocked.

### Invariant 3 — `CGCODE` (Coverage Group) Coexistence with Permanent `VCODE`
Every store permanently retains its individual `VCODE` even when grouped into a roving Coverage Group (`CGCODE`).
- A `CGCODE` is a roving group overlay across multiple stores (e.g., 5 stores grouped under 1 unique `CGCODE`).
- The underlying `VCODE`s of those 5 stores are NEVER deleted, mutated, or removed, because any store can revert to `stationary` deployment later on.

### Invariant 4 — Auto-Computed `EMPLOYMENT_TYPE` & Fractional `REQUIRED_HC` ($1/N$)
`EMPLOYMENT_TYPE` and `REQUIRED_HC` are removed from required Excel spreadsheet inputs and are computed directly by the database:
- **Vacant Row** (`EMPLOYEE_NO` blank): Defaults to `stationary` employment type and `1.00` required headcount.
- **Assigned Employee** (`EMPLOYEE_NO` present): Distinct stores ($N$) assigned to that `EMPLOYEE_NO` across the batch and active allocations are evaluated:
  - If $N = 1 \implies$ `stationary` (`1.00` HC).
  - If $N > 1 \implies$ `roving`, and each assigned store is allocated fractional headcount $1 / N$ (e.g., 5 stores $\implies 0.20$ HC per store).
  - Data Team can attach or request a Coverage Group (`CGCODE`) overlay subsequently.

### Invariant 5 — Multi-Batch Existing `VCODE` Rule
When uploading Plantilla batches, if a row's `VCODE` already exists in the database:
- **No Employee** (`EMPLOYEE_NO` is null / blank): The row is marked as **`skipped`** (`validation_status = 'skipped'`, non-blocking, informational message: `"Existing VCODE skipped (vacant row — only fresh VCODEs create new vacant slots)"`). It is ignored during approval commit.
- **Assigned Employee** (`EMPLOYEE_NO` is populated): The row is **allowed**. During commit, it claims and occupies an existing open vacant slot at that `VCODE` or creates an occupied slot ordinal under that store's existing `VCODE`.

### Invariant 6 — `MOTHER_ACCOUNT` Penalty Inheritance
- `MOTHER_ACCOUNT` is a mandatory column in Plantilla Import (positioned immediately following `ACCOUNT_NAME`).
- `WITH_PENALTY` is removed from required Excel spreadsheet input columns and is derived automatically in the database from the `MOTHER_ACCOUNT` configuration. If a mother account record is newly referenced or unconfigured, safe fallback defaults to `false`.

### Invariant 7 — Strict `MIDDLE_NAME` Validation
Whenever `EMPLOYEE_NO` is populated:
- `MIDDLE_NAME` is mandatory.
- Blank, null, or single-character initials (e.g., `"S"` or `"S."`, alpha length $< 2$) are hard-blocked.
- Only full middle names ($\ge 2$ alpha characters) or explicit `"NA"` / `"N/A"` (case-insensitive) are accepted.
- If `EMPLOYEE_NO` is blank, all employee fields (`LAST_NAME`, `FIRST_NAME`, `MIDDLE_NAME`, and `DATE_HIRED`) must also be blank. If any employee detail is provided without `EMPLOYEE_NO`, the row is hard-blocked with `"EMPLOYEE_NO is required when employee details are provided"`.

### Invariant 8 — Schedule Days, Flexible Schedule Time & Dayoff Audit Model
- `SCHEDULE` is replaced by `SCHEDULE_DAYS` (multi-select MON–SUN in Web; preset dropdown + custom comma-separated days in Excel).
- `SCHEDULE_TIME` is added (`text`, optional in Excel, editable in Web by Ops per store allocation for store visit audits). Supports fixed shift windows (e.g., `08:00 AM - 05:00 PM`) and flexible roving visit durations (e.g., `FLEXI (4 HRS)`, `FLEXI (6 HRS)`).
- `DAYOFF` supports multi-select in Web and preset dropdown + custom multi-day values in Excel.

### Invariant 9 — Per-Account `HRCO_EMAIL` Auto-Population & Reactive Backfill
- **On Import**: If `HRCO_EMAIL` is blank in the uploaded spreadsheet, inspect the target Account's assigned HR Coordinator(s):
  - If the Account has **exactly 1 HRCO**, auto-populate that HRCO.
  - If the Account has **0 or $> 1$ HRCOs**, tag the record with `needs_hrco = true` (`"NEEDS HRCO"` tag).
- **Reactive Backfill**: When an HRCO is subsequently assigned or updated on an Account, the database automatically backfills all `plantilla` records under that Account having `needs_hrco = true` to the newly assigned HRCO and clears `needs_hrco = false`.

### Invariant 10 — Rollback Governance (72h Window + Zero-Edit Immutability Lock + History Audit)
- **72-Hour Request Window**: The uploader (Data Team) can request batch rollback within 72 hours of approval. Head Admin (HA) and Super Admin (SA) can approve or reject the rollback request.
- **SA Window Override**: Super Admin can override an expired ($> 72\text{h}$) window **ONLY IF** zero records in the batch were edited after import approval.
- **Strict Zero-Edit Immutability Lock**: If **any** record in the batch was edited in Plantilla or allocations after import approval (e.g., Ops changed `dayoff`, `schedule_days`, `schedule_time`, rate, position, status, etc., causing `updated_at > approved_at`), rollback is **HARD BLOCKED** for all roles (even SA cannot override). The system returns an explicit error naming the exact employee number, employee name, and modification timestamp.
- **Import History Visibility**: Import History must clearly surface Batch # (e.g. `#703cdbc4`), Stores/HC count (e.g. `11/10`), and Approved/Rejected By actor details along with rollback state indicators.
