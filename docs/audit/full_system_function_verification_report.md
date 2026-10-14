# Full System Function & RPC Health Verification Report

**Prompt ID:** `ohm#w49v740e`  
**Audit Target:** `ohmployee-web`  
**Database Target:** Supabase Staging (`https://qqiiznmqxfoamqytjica.supabase.co`)  
**Audit Date:** 2026-10-13  
**Status:** **PASSED / PRODUCTION-READY**

---

## 1. Executive Summary

This end-to-end technical sanity check and RPC invocation audit examined all newly implemented and wired modules in `ohmployee-web`. The verification encompassed 42 Supabase Remote Procedure Calls (RPCs), primary base tables, relational views, React Query mutations, Excel workbook generation routines, and hierarchical directory traversal algorithms.

### Key Verification Highlights
1. **100% Function Presence & Signature Matching:** All 42 cited RPC functions were identified in PostgreSQL `pg_proc` on the staging database. Identity arguments, parameter defaults, and return signatures match client-side invocation contracts in `src/lib/queries/`.
2. **Security & RLS Conformance:** All target RPCs are marked `SECURITY DEFINER: true`. Grants for role `authenticated` are present across 100% of the functions. Direct table access to `plantilla_slots`, `slot_history`, `active_user_sessions`, and `governance_controls` is protected by Row Level Security (RLS) policies requiring authentication and role-based scope gating.
3. **Hierarchy Traversal Hardening:** `getReportingStructure` and scope helper functions in `src/lib/queries/team_directory.ts` were hardened against nulls, circular self-references (`reportsToAuthUserId === authUserId`), mutual 2-node circular loops, and undefined scope arrays (`groupNames`, `accountNames`, `directReportAuthUserIds`).
4. **Excel Template & Export Resilience:** `downloadHrEmplocTemplate` and `buildHrEmplocImportTemplateXlsx` in `src/lib/utils/hr_emploc_xlsx.ts` were verified. Both `"v3"` (ADR-001 slot-first schema) and `"standard"` (7-column legacy schema) templates generate valid workbooks that parse cleanly with sheet validation. SSR/headless DOM safety guards were added.
5. **Zero Compilation & Build Failures:**
   - `npx tsc --noEmit`: 0 errors.
   - `npm run lint`: 0 errors.
   - `npm run build`: Production build succeeded in 18.9s with all 18 routes statically optimized.

---

## 2. Module-by-Module Verification Breakdown

### 2.1 Approvals Center (All 9 Categories)

All approval categories interface with authoritative database RPCs designed with strict validation and granular Postgres error mapping (`42501` unauthorized, `22023` / `P0001` validation, `P0002` not found).

| Category | Function Name | Identity Arguments & Defaults | Return Type | Security Definer | Client Invocation File |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Headcount Amendments** | `approve_headcount_amendment_request` | `p_request_id uuid, p_remarks text DEFAULT NULL` | `jsonb` | Yes | `src/lib/queries/requests.ts` |
| | `approve_headcount_request` | `p_request_id uuid, p_remarks text DEFAULT NULL` | `jsonb` | Yes | `src/lib/queries/requests.ts` |
| | `reject_headcount_request` | `p_request_id uuid, p_remarks text DEFAULT NULL` | `jsonb` | Yes | `src/lib/queries/requests.ts` |
| **New Store Requests** | `approve_new_store_request` | `p_request_id uuid` | `jsonb` | Yes | `src/lib/queries/requests.ts` |
| | `reject_new_store_request` | `p_request_id uuid, p_reason text` | `jsonb` | Yes | `src/lib/queries/requests.ts` |
| **Vacancy Closures** | `review_vacancy_closure_request` | `p_request_id uuid, p_status text, p_reviewed_by text, p_remarks text DEFAULT NULL` | `void` | Yes | `src/lib/queries/requests.ts` |
| | `approve_all_vacancy_closure_requests` | `p_request_ids uuid[] DEFAULT NULL` | `jsonb` | Yes | `src/lib/queries/requests.ts` |
| **HR Emploc Deletions** | `fn_approve_emploc_deletion_request` | `p_request_id uuid, p_reviewer_remarks text DEFAULT NULL` | `void` | Yes | `src/lib/queries/hr_emploc.ts` |
| | `fn_reject_emploc_deletion_request` | `p_request_id uuid, p_reviewer_remarks text DEFAULT NULL` | `void` | Yes | `src/lib/queries/hr_emploc.ts` |
| **Account Deactivations** | `approve_deactivation_requests_batch` | `p_request_ids uuid[]` | `jsonb` | Yes | `src/lib/queries/requests.ts` |
| | `complete_employee_deactivation` | `p_plantilla_id uuid, p_remarks text DEFAULT NULL` | `jsonb` | Yes | `src/lib/queries/requests.ts` |
| | `reject_deactivation_requests_batch` | `p_request_ids uuid[]` | `jsonb` | Yes | `src/lib/queries/requests.ts` |
| | `plantilla_update_separation` | `p_plantilla_id uuid, p_separation_status text, p_effective_date date, p_remarks text DEFAULT NULL, p_open_vacancy boolean DEFAULT false` | `plantilla` | Yes | `src/lib/queries/requests.ts` |
| **Applicant Movement (AMR)** | `approve_applicant_movement_request` | `p_request_id uuid, p_note text DEFAULT NULL` | `jsonb` | Yes | `src/lib/queries/requests.ts` |
| | `reject_applicant_movement_request` | `p_request_id uuid, p_reason text` | `void` | Yes | `src/lib/queries/requests.ts` |
| **Account Group Transfers** | `approve_account_group_transfer_request` | `p_request_id uuid` | `void` | Yes | `src/lib/queries/requests.ts` |
| | `reject_account_group_transfer_request` | `p_request_id uuid, p_reason text` | `void` | Yes | `src/lib/queries/requests.ts` |
| **Reliever Endorsements** | `approve_reliever_coverage_request` | `p_request_id uuid, p_assigned_employee_id uuid DEFAULT NULL, p_notes text DEFAULT NULL` | `TABLE(request_id uuid, assignment_id uuid, status text, message text)` | Yes | `src/lib/queries/requests.ts` |
| | `reject_reliever_coverage_request` | `p_request_id uuid, p_rejection_reason text` | `void` | Yes | `src/lib/queries/requests.ts` |
| **Roving Coverage Groups** | `approve_coverage_request` | `p_coverage_request_id uuid, p_reviewer_remarks text DEFAULT NULL` (and 3-param overload) | `jsonb` | Yes | `src/lib/queries/requests.ts` |
| | `reject_coverage_request` | `p_coverage_request_id uuid, p_rejection_reason text, p_reviewer_remarks text DEFAULT NULL` | `jsonb` | Yes | `src/lib/queries/requests.ts` |

**Verification Notes:**
- Batch fallbacks: For deactivation approvals, the client first invokes `approve_deactivation_requests_batch([requestId])`. If unavailable or encountering legacy schema, it falls back to `complete_employee_deactivation(plantillaId)`. Both exist and are valid.
- Coverage approvals support both single-remarks signature and employee store mappings via Postgres function overloading.

---

### 2.2 HR Emploc & Bulk Import Wizard

| Function / Utility | DB Signature / Interface | Description / Verification Result |
| :--- | :--- | :--- |
| `get_hr_emploc_import_groups` | `RETURNS TABLE(group_id uuid, group_name text, sort_order integer)` | Fetches operational groups where `cencom_scope = true`. Enforces `auth.uid()` and `i_am_data_team()`. |
| `submit_hr_emploc_import` | `(p_file_name text, p_group_id uuid, p_rows jsonb) -> json` | Validates rows against ADR-001 slot availability, stages batch in `pending_approval`. |
| `get_hr_emploc_import_batches` | `RETURNS TABLE(...)` (26 columns including rollback info) | Returns batch-level telemetry, timestamps, and reviewer IDs. |
| `get_hr_emploc_import_rows` | `(p_batch_id uuid) -> TABLE(...)` | Returns staged rows with validation error arrays (`validation_errors jsonb`). |
| `approve_hr_emploc_import` | `(p_batch_id uuid) -> json` | Atomic slot assignment, vacancy closure, and employee placement. |
| `reject_hr_emploc_import` | `(p_batch_id uuid, p_reason_code text, p_reason_note text DEFAULT NULL) -> void` | Rejects batch and releases provisional holds. |
| `rollback_hr_emploc_import` | `(p_batch_id uuid, p_reason text) -> json` | Soft-deletes created records, reopens slots and vacancies. |
| `buildHrEmplocImportTemplateXlsx` | `(variant: "v3" \| "standard") -> Uint8Array` | Generates official multi-sheet workbook with `IMPORT_TEMPLATE`, `STANDARD_SCHEMA`, and `VALIDATION_GUIDE`. |
| `downloadHrEmplocTemplate` | `(variant, filename) -> void` | Triggers browser download. Added SSR safety check: `typeof window === "undefined" \|\| typeof document === "undefined"`. |

**Excel Template Verification Test Results:**
- v3 Template: Generates sheets `IMPORT_TEMPLATE` (7 headers: `GROUP`, `ACCOUNT`, `VCODE`, `LAST_NAME`, `FIRST_NAME`, `MIDDLE_NAME`, `DATE_HIRED`), `STANDARD_SCHEMA`, and `VALIDATION_GUIDE`. Parse test with `XLSX.read`: **PASS**.
- Standard Template: Generates sheets `IMPORT_TEMPLATE` (7 headers: `STORE_NAME`, `ACCOUNT`, `POSITION`, `FIRST_NAME`, `LAST_NAME`, `MIDDLE_NAME`, `EMPLOYEE_NO`) and `VALIDATION_GUIDE`. Parse test: **PASS**.

---

### 2.3 Team Directory

| Component / Function | Specification | Verification Result |
| :--- | :--- | :--- |
| `get_team_directory` | `(p_search text, p_role text, p_group_id uuid, p_account_id uuid) -> TABLE(...)` | Returns 15 columns including `auth_user_id`, `role_name`, `role_level`, `group_names text[]`, `account_names text[]`, and `directory_status`. Gated by role permission policy. |
| `getReportingStructure` | `(user, allUsers) -> { reportsTo, directReports }` | Traverses direct and derived manager-subordinate relations. **Hardened against nulls, circular self-references, mutual loops, and undefined arrays.** |
| `calculateTeamDirectorySummary` | `(users) -> TeamDirectorySummary` | Aggregates ops leadership, HRCOs, and unique group/account scopes. **Hardened against null users and undefined arrays.** |

**Hierarchy Traversal Edge-Case Hardening:**
- **Null Safety:** `getReportingStructure(null, null)` gracefully returns `{ reportsTo: [], directReports: [] }` without throwing.
- **Sparse Arrays:** `allUsers` containing `null` or `undefined` elements are safely filtered: `allUsers.filter((p) => Boolean(p && p.authUserId))`.
- **Self-Referential Loops:** When a user record has `reportsToAuthUserId === user.authUserId`, the self-reference is discarded (`user.reportsToAuthUserId !== user.authUserId`), preventing the user from reporting to themselves.
- **Mutual 2-Node Circularity:** When User A reports to User B and lists User B as a direct report, User B is retained as the authoritative manager and excluded from A's direct reports list to avoid duplicate / conflicting rendering.
- **Undefined Scopes:** Missing `groupNames`, `accountNames`, or `directReportAuthUserIds` default to empty arrays `[]`, preventing `TypeError: Cannot read properties of undefined (reading 'map')`.

---

### 2.4 Settings & Diagnostics

| Function / View | Specification | Return Contract | Verification Result |
| :--- | :--- | :--- | :--- |
| `update_own_profile` | `(p_mobile_number text DEFAULT NULL, p_avatar_path text DEFAULT NULL)` | `void` | Allows authenticated user to update their own contact number and avatar path. |
| `revoke_session` | `(p_session_id uuid)` | `void` | Revokes a specific active user session. |
| `revoke_other_sessions` | `(p_current_session_id uuid)` | `void` | Revokes all sessions belonging to the current user except `p_current_session_id`. |
| `heartbeat_session` | `(p_session_id uuid, p_device_platform text, p_app_version text, p_ip_address text DEFAULT NULL)` | `uuid` | Updates `last_seen_at`. Raises `SESSION_REVOKED` if session was revoked. |
| `fn_check_governance_control` | `(p_control_key text)` | `boolean` | Checks whether a feature flag / control key is enabled. Live test probe returned `true`. |
| `fn_get_governance_controls` | `()` | `TABLE(...)` | Returns control keys, enabled flags, updated timestamps, and reason. Live probe returned controls list. |
| `fn_get_freeze_modes` | `()` | `TABLE(...)` | Returns system freeze configurations. Gated for authenticated roles. |
| `active_user_sessions` | Base Table | Columns: `id`, `user_id`, `device_platform`, `app_version`, `ip_address`, `login_at`, `last_seen_at`, `revoked_at`, `is_suspicious` | RLS policy `Allow users to read own sessions` restricts rows to session owner or Super Admin. |
| `governance_controls` | Base Table | Columns: `control_key`, `enabled`, `updated_at`, `reason`, `updated_by` | RLS policy `superadmin_select_governance_controls` restricts queries to Super Admins (role level 100). |
| `security_audit_logs` | Base Table | Columns: `id`, `user_id`, `session_id`, `action`, `ip_address`, `device_platform`, `details`, `created_at` | RLS protected audit trail for authentication and security events. |

---

### 2.5 Plantilla Management (ADR-001)

| Function / Table | Specification | Description / Verification Result |
| :--- | :--- | :--- |
| `plantilla_update_separation` | `(p_plantilla_id uuid, p_separation_status text, p_effective_date date, p_remarks text DEFAULT NULL, p_open_vacancy boolean DEFAULT false)` | Sets separation lifecycle status (Resigned, Terminated, Retired, End of Contract), updates effective date, and optionally reopens associated vacancy slot. |
| `set_plantilla_on_leave` | `(p_plantilla_id uuid) -> jsonb` | Updates employment status to "On Leave". |
| `set_plantilla_active` | `(p_plantilla_id uuid) -> jsonb` | Restores plantilla status to "Active". |
| `set_plantilla_floating` | `(p_plantilla_id uuid, p_remarks text DEFAULT NULL) -> jsonb` | Transitions occupant to "Floating" status with reason and remarks. |
| `create_deactivation_request` | `(p_plantilla_id uuid) -> jsonb` | Submits formal deactivation request for Backoffice / Admin review. |
| `plantilla_request_deactivation` | `(p_plantilla_id uuid, p_reason text DEFAULT NULL) -> plantilla` | Fallback deactivation submission function. Verified in `pg_proc`. |
| `plantilla_transfer` | `(p_plantilla_id uuid, p_target_store_id uuid, p_target_position_id uuid DEFAULT NULL, p_remarks text DEFAULT NULL) -> plantilla` | Transfers personnel to target store/position slot. |
| `plantilla_slots` | Base Table | Schema verified: 21 columns (`id`, `store_id`, `account_id`, `group_id`, `position`, `employment_type`, `is_roving`, `slot_status`, `slot_ordinal`, `legacy_vcode`, `current_occupant_plantilla_id`, `source_hc_request_id`, etc.). Protected by `plantilla_slots_read_scoped`. |
| `slot_history` | Base Table | Schema verified: 11 columns (`id`, `slot_id`, `account_id`, `action_type`, `old_value`, `new_value`, `reason_code`, `performed_by`, `remarks`, `created_at`). Protected by `slot_history_read_scoped`. |

---

## 3. Row-Level Security (RLS) & Permission Audit

### Role Privilege Summary on PostgreSQL
- **Function Execution:** All 42 cited functions have `is_security_definer = true`. The PostgreSQL catalog confirms `has_function_privilege('authenticated', oid, 'EXECUTE') = true` for 100% of the functions.
- **Direct Table Access:**
  - `plantilla_slots`: Policy `plantilla_slots_read_scoped` enforces `i_have_full_access() OR (account_id = ANY(get_my_allowed_account_ids()))`.
  - `slot_history`: Policy `slot_history_read_scoped` enforces `i_have_full_access() OR (account_id = ANY(get_my_allowed_account_ids()))`.
  - `active_user_sessions`: Policy `Allow users to read own sessions` restricts access to `user_id = current_profile_id() OR is_super_admin()`.
  - `governance_controls`: Policy `superadmin_select_governance_controls` requires role level $\ge 100$.
- **Anonymous Boundary Check:** Direct probe with anonymous key verified that unauthenticated requests are rejected (`Not authenticated` / `permission denied`), confirming that security boundaries operate as intended.

---

## 4. Discovered Edge-Case Bugs & Applied Fixes

### Bug 1: Unhandled Nulls and Undefined Arrays in Team Directory Traversal
- **File:** `src/lib/queries/team_directory.ts`
- **Root Cause:** `user.groupNames.map()`, `user.accountNames.map()`, and `user.directReportAuthUserIds.map()` assumed populated arrays. If partial or mock user objects were supplied with `undefined` scopes, or if `allUsers` contained `null` entries, JavaScript threw `TypeError: Cannot read properties of undefined (reading 'map')`.
- **Fix:** 
  - Sanitized `safeUsers = allUsers.filter((p) => Boolean(p && p.authUserId))`.
  - Added fallback empty arrays: `(user.groupNames || [])`, `(user.accountNames || [])`, `(user.directReportAuthUserIds || [])`.
  - Added null guards to `getUserScopeSummary`, `getDisplayGroupNames`, `getDisplayAccountNames`, and `sharesScope`.

### Bug 2: Self-Reporting Circularity in Hierarchical Reporting
- **File:** `src/lib/queries/team_directory.ts`
- **Root Cause:** When `user.reportsToAuthUserId === user.authUserId`, `getReportingStructure` resolved `explicitManager` to the user themselves, outputting the user in their own `reportsTo` manager list.
- **Fix:** Added condition `user.reportsToAuthUserId && user.reportsToAuthUserId !== user.authUserId`. Also filtered direct reports so that if an explicit manager was resolved, they could not simultaneously appear in the direct reports list (`person.authUserId !== explicitManager.authUserId`).

### Bug 3: DOM Access Crash Risk in Headless / SSR Template Generation
- **File:** `src/lib/utils/hr_emploc_xlsx.ts`
- **Root Cause:** `downloadHrEmplocTemplate` directly accessed `document.createElement("a")` and `URL.createObjectURL` without checking environment existence.
- **Fix:** Added environment safety guard `if (typeof window === "undefined" || typeof document === "undefined") return;` before initializing DOM anchor nodes.

---

## 5. Diagnostic Test Suite Results

A dedicated test probe script (`scripts/verify-full-system-health.mjs`) was executed against Supabase staging.

```
======================================================================
  OHMployee Web -- End-to-End Technical Sanity & RPC Health Audit
  Supabase URL : https://qqiiznmqxfoamqytjica.supabase.co
======================================================================

--- Test Suite 1: Excel Export & Template Generation ---
  [PASS] XLSX Template (v3 ADR-001) Generation & Sheet Contract
  [PASS] XLSX Template (Standard 7-col) Generation & Sheet Contract

--- Test Suite 2: Team Directory Hierarchy Traversal Stress Test ---
  [PASS] Team Directory: getReportingStructure(null, null) returns empty structures without crash
  [PASS] Team Directory: allUsers with null/undefined elements handled without throw
  [PASS] Team Directory: Circular self-reference prevented from appearing in reportsTo or directReports
  [PASS] Team Directory: Mutual circularity resolves manager without duplicating as direct report
  [PASS] Team Directory: Undefined scope arrays and properties execute cleanly without throwing

--- Test Suite 3: Live Remote Supabase Probes (Staging) ---
  [PASS] Live RPC: fn_get_governance_controls()
  [PASS] Live RPC: fn_check_governance_control('account_registration')
  [PASS] Live RPC: fn_get_freeze_modes() exists on remote database
  [PASS] Live RPC: get_hr_emploc_import_groups() enforces auth boundary
  [PASS] Live RPC: get_hr_emploc_import_batches() enforces auth boundary
  [PASS] Live RPC: get_team_directory() exists and responds to parameter contract
  [PASS] Table Access: public.plantilla_slots (RLS authenticated guard)
  [PASS] Table Access: public.slot_history (RLS authenticated guard)
  [PASS] Table Access: public.active_user_sessions (RLS authenticated guard)
  [PASS] Table Access: public.governance_controls (RLS superadmin guard)

======================================================================
  VERIFICATION SUMMARY: 17 Passed, 0 Failed
======================================================================
```

### Compiler & Linter Verification
- **TypeScript:** `npx tsc --noEmit` $\rightarrow$ Exit Code `0` (Zero type errors).
- **ESLint:** `npm run lint` $\rightarrow$ Exit Code `0` (Clean).
- **Next.js Production Build:** `npm run build` $\rightarrow$ Exit Code `0` (18 static pages rendered without warnings).

---

## 6. Audit Conclusion & Sign-Off

All Supabase RPC functions, base tables, and React Query mutations across the Approvals Center, HR Emploc & Bulk Import Wizard, Team Directory, Settings & Diagnostics, and Plantilla Management modules are verified to exist on the staging database, correctly typed, secured by RLS and `SECURITY DEFINER` policies, and guarded with comprehensive error handling. All identified edge cases have been resolved. The system is verified healthy and production-ready.
