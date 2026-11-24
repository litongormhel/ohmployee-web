# Web Auth and RBAC State

## Scope

This document defines the intended OHMployee Web authentication guard and RBAC shell architecture. The lightweight web auth/RBAC shell now calls the backend current-user context RPC without middleware, module business queries, or frontend role rules.

The web app remains an admin-panel presentation layer. Supabase is the authority for session validity, RBAC, RLS, business rules, and data integrity.

## Current Foundation Observed

- `src/lib/supabase/client.ts` creates a browser Supabase client from `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`, with automatic fallback to the Staging project (`qqiiznmqxfoamqytjica.supabase.co`) when hosting environment variables are not explicitly provided.
- `src/app/(auth)/login/page.tsx` signs in with Supabase Auth, redirects successful login to `/vacancy`, redirects already-authenticated visitors away from `/login`, displays the official circular OHMployee transparent emblem (`/images/ohm_logo_transparent.png`, 80×80px), and provides links to "Forgot password?" (`/forgot-password`) and "Request Account" (`/signup`).
- `src/app/(auth)/signup/page.tsx` provides account sign-up / request registration. Gated by real-time governance control `account_registration` (`is_account_signup_enabled`). Sourcing non-admin roles (`role_level < 90`), groups, and accounts via `get_request_account_signup_options()`. Strictly enforces required fields: First Name, Last Name, Middle Name, Mobile Number (`^09\d{9}$`), Work Email, Password, Requested Role, and Assigned Group/Account scopes. Submits user with metadata matching `handle_new_auth_user()` trigger schema, enriches profile via `fn_enrich_account_request`, and signs out immediately into an administrator review confirmation state.
- `src/app/(auth)/forgot-password/page.tsx` allows users to enter their email address to trigger a password reset recovery link via `supabase.auth.resetPasswordForEmail`.
- `src/app/(auth)/reset-password/page.tsx` allows authenticated recovery session visitors to set a new password via `supabase.auth.updateUser({ password })`.
- `src/app/(dashboard)/layout.tsx` delegates the dashboard route group to `src/components/DashboardAuthShell.tsx`.
- `src/components/DashboardAuthShell.tsx` loads the current Supabase Auth session/user on the client, calls `get_web_current_user_context`, redirects missing sessions to `/login`, renders a blocked-access screen for denied authenticated users, redirects hidden direct module routes back to `/vacancy` (or primary visible module), and passes backend-filtered modules into the shell.
- `src/components/Sidebar.tsx` signs out through the browser Supabase client, redirects to `/login`, and renders only backend-visible modules.
- `src/components/AdminTopbar.tsx` renders the active module title and mobile module navigation from backend-visible modules only.
- `src/lib/auth.ts` defines the RPC-backed current-user context loader, fail-closed blocked states, and module visibility helper.
- `src/lib/modules.ts` is the current module registry and now includes stable module keys for future backend capability mapping.
- Most module pages are scaffold-only empty states. `vacancy` has a typed empty query placeholder and client-side table shell, but no real Supabase data contract.
- This repo currently has no local `supabase/migrations` directory. The frontend now expects the `get_web_current_user_context` RPC to exist in the Supabase authority project.

## Recommended Auth/RBAC Architecture

### Session Guard

- Guard the whole dashboard route group at `src/app/(dashboard)/layout.tsx`.
- The first implementation should use a server-capable Supabase session read at the App Router layout boundary.
- If no valid user session exists, redirect to `/login`.
- If a valid user session exists, load the user's safe web context before rendering the shell.
- Do not add module-by-module auth guards until a route-level RBAC contract is explicitly needed.
- Do not use frontend guards as authorization. They prevent confusing UI exposure only; Supabase RLS/RPC policies remain authoritative.

### Current User Context

Web needs one normalized current-user context before rendering dashboard navigation. The current frontend loader calls:

```ts
supabase.rpc("get_web_current_user_context")
```

The backend-backed context includes:

- Supabase Auth user id.
- Profile id and display metadata safe for the admin shell.
- Mobile-equivalent role identifier or role capability set.
- Group scope for modules that are group-limited.
- Account scope for modules that are account-limited.
- Module visibility/capability data derived from existing Mobile RBAC semantics.
- Status flags needed to block missing-profile, inactive, disabled, unauthorized, or failed access checks.

This context is currently fetched once in the dashboard shell wrapper and passed to shell components as presentation data. Client components may consume the already-loaded context, but they should not independently decide authority.

### RBAC Boundary

- Backend/RLS/RPC: authoritative permission checks, record visibility, mutations, workflow rules, and scope filtering.
- Frontend: navigation filtering, empty/blocked module states, labels, and route display decisions.
- Module pages: presentation only until their Supabase contracts and RLS are approved.
- Module visibility: driven by the existing `webModules` registry plus backend-provided capabilities, not by hardcoded role names in components.

## Required Backend Contracts

Required safe contract:

- A safe current-user profile/scope RPC named `get_web_current_user_context` that returns only the authenticated user's web-safe context.
- An optional `security_invoker` view can expose the same current-user context for read/query ergonomics after the RPC is in place, but the RPC should remain the canonical contract for shell bootstrap and fail-closed status handling.
- The contract must map the Supabase Auth user to the OHMployee profile/account identity used by Mobile.
- The contract must expose the existing Mobile role semantics without inventing web-only roles.
- The contract must expose group scope and account scope in the same shape Mobile uses, or in a documented web-safe projection.
- The contract must expose allowed module keys and capabilities so web does not duplicate role rules.
- The contract must fail closed for missing profiles, inactive accounts, disabled users, or unauthorized admin-panel access.

Recommended response shape for documentation and future typing:

```ts
type WebCurrentUserContext = {
  authUserId: string;
  profileId: string | null;
  displayName: string | null;
  email: string | null;
  role: {
    key: string | null;
    name: string | null;
  };
  active: boolean;
  status:
    | "active"
    | "authenticated_profile_missing"
    | "inactive"
    | "disabled"
    | "unauthorized_web";
  groupScope: {
    mode: "all" | "scoped" | "none";
    ids: string[];
  };
  accountScope: {
    mode: "all" | "scoped" | "none";
    ids: string[];
  };
  allowedModules: string[];
  capabilities: Record<string, string[]>;
};
```

This is a web projection shape, not a new database role model.

The current frontend accepts `access_status = "allowed"` as the only renderable shell state. It reads `allowed_module_keys` for navigation visibility and `module_capabilities` for sidebar/topbar display metadata only. If `access_status` is anything else, the dashboard route group stays blocked for the authenticated user.

Recommended database shape:

```sql
-- Canonical shell bootstrap contract.
select *
from public.get_web_current_user_context();

-- Optional read convenience once the RPC exists.
select *
from public.web_current_user_context;
```

The RPC/view should return exactly one row for an authenticated request. If the Auth user has no linked profile, is inactive/disabled, or is not authorized for web, the row should still identify the Auth user but return `active = false`, empty scopes, empty modules, empty capabilities, and the appropriate non-active `status`. For unauthenticated requests, the RPC should either return no rows or raise an unauthenticated error; the web shell treats both as `login`.

Recommended flattened SQL columns:

| Column | Type | Notes |
| --- | --- | --- |
| `auth_user_id` | `uuid` | Must equal `auth.uid()`. Never accept this as a caller argument. |
| `profile_id` | `uuid null` | Existing Mobile profile/user identity, if linked. |
| `full_name` | `text null` | Web-safe display name from existing profile semantics. |
| `email` | `text null` | Web-safe email, usually Auth email or approved profile email. |
| `role_key` | `text null` | Existing Mobile role key only. Do not create web-only roles. |
| `role_name` | `text null` | Existing Mobile display name only. |
| `active` | `boolean` | True only for valid, enabled, web-authorized users. |
| `status` | `text` | One of `active`, `authenticated_profile_missing`, `inactive`, `disabled`, `unauthorized_web`. |
| `group_scope_mode` | `text` | `all`, `scoped`, or `none`, derived from Mobile RBAC. |
| `group_scope_ids` | `uuid[]` | Empty unless scoped. |
| `account_scope_mode` | `text` | `all`, `scoped`, or `none`, derived from Mobile RBAC. |
| `account_scope_ids` | `uuid[]` | Empty unless scoped. |
| `allowed_module_keys` | `text[]` | Stable keys matching `src/lib/modules.ts`. |
| `capabilities` | `jsonb` | Object keyed by module key, each value an array of capability/action keys. |

Stable web module keys currently expected by the presentation layer:

`dashboard`, `cencom`, `vacancy`, `hr_emploc`, `plantilla`, `approvals`, `users`, `team_directory`, `notifications`, `reports`, `settings`, `more`.

Dashboard shell visibility must still be backend-authorized. If the backend chooses to allow a blocked shell for missing/inactive profiles, it should return no real modules and no capabilities; the frontend may show only a blocked shell or minimal dashboard route with no data widgets.

## RPC vs View Recommendation

Use both, but in this order:

1. Implement an RPC first as the canonical contract.
2. Add a `security_invoker = true` view only if web or future module queries benefit from selecting the same context shape.

The RPC is preferred for shell bootstrap because it can produce one normalized status row, centralize fail-closed behavior, avoid caller-provided user ids, and hide join complexity behind a stable function signature. It may use `security definer` only when required to bridge private RBAC/profile tables, and then only with a locked `search_path`, explicit `auth.uid()` checks, strict grants to `authenticated`, and no service-role exposure.

The view is useful for composable read access, but it must be `security_invoker` so RLS continues to apply as the authenticated user. The view should not become a bypass around Mobile RBAC tables. If the same table access cannot be made safe under invoker semantics, skip the view and keep the RPC as the only contract.

## Fail-Closed Behavior

- Unauthenticated: web redirects to `/login`; backend should return no context or an unauthenticated error.
- Authenticated but no linked profile: return `access_status = authenticated_profile_missing` or equivalent missing-profile status, no scopes, no modules, and no capabilities.
- Inactive profile/account: return `access_status = inactive`, no scopes, no modules, and no capabilities.
- Disabled user: return `access_status = disabled`, no scopes, no modules, and no capabilities.
- Authenticated and active but not web-authorized: return `access_status = unauthorized_web` or `unauthorized_role`, no scopes, no modules, and no capabilities.
- RPC failure, malformed payloads, missing module arrays, missing capability objects, and unknown statuses block the shell.
- Active and web-authorized: return `access_status = allowed`, Mobile-derived role, Mobile-derived scopes, `allowed_module_keys`, and `module_capabilities`.
- If an allowed user has an empty `allowed_module_keys` array, the frontend renders a dashboard-only shell. Missing or malformed module data is blocked.

The web app must treat unknown statuses, unknown roles, missing arrays, malformed capabilities, and hidden module keys as blocked. Frontend filtering is display-only; RLS/RPC checks still enforce authorization on every data query and mutation.

## Security Notes

- Do not expose service-role credentials or service-role-only tables to the browser.
- Do not accept `auth_user_id`, `profile_id`, `role_key`, group ids, or account ids as RPC arguments for current-user context.
- Derive the user exclusively from `auth.uid()`.
- Mirror existing Mobile RBAC semantics and authority tables; do not invent web-only roles or broader web scopes.
- Return only web-safe display fields and capability keys. Do not return policy internals, secret claims, raw permission rows, or unrelated user records.
- Keep group/account scope as filters for module data contracts. Scope visibility in the shell is not enough.
- Preserve RLS as the data access authority. A `security definer` RPC must be tightly scoped to this projection and should not expose generic table access.

## Module Visibility Matrix Draft

Visibility must be resolved from existing Mobile RBAC semantics and backend-provided capabilities. The frontend now filters navigation from backend `allowed_module_keys`; `module_capabilities` may be shown as display metadata only and must not become action authority. This is navigation/display filtering only and is not an authorization claim.

| Module | Route | Visibility rule draft | Scope input | Notes |
| --- | --- | --- | --- | --- |
| Dashboard | `/dashboard` | Visible to authenticated users who are authorized for the web admin panel. | Profile, role, group, account | Command-center shell only until summaries are contracted. |
| CENCOM | `/cencom` | Visible when backend exposes the CENCOM module capability. | Group/account as defined by Mobile | No business workflow yet. |
| Vacancy | `/vacancy` | Visible when backend exposes the Vacancy module capability. | Group/account as defined by Mobile | Current table query is placeholder-only and must remain RLS-backed when implemented. |
| HR Emploc | `/hr-emploc` | Visible when backend exposes the HR Emploc module capability. | Group/account as defined by Mobile | Scope must mirror Mobile. |
| Plantilla | `/plantilla` | Visible when backend exposes the Plantilla module capability. | Group/account as defined by Mobile | Position/staffing authority belongs in Supabase. |
| Approvals | `/approvals` | Visible when backend exposes the Approvals module capability. | Approval scope from backend | Approval routing must be backend-driven. |
| User Management | `/users` | Visible when backend exposes account/user administration capability. | Account scope | Web must not broaden account administration beyond backend scope. |
| Team Directory | `/team-directory` | Visible when backend exposes Team Directory capability. | Group/account as defined by Mobile | Directory record visibility must be RLS-filtered. |
| Notifications | `/notifications` | Visible when backend exposes Notifications capability. | User/profile scope | Delivery/read state remains backend-owned. |
| Reports | `/reports` | Visible when backend exposes Reports capability. | Group/account/report scope | Export/report access must be enforced server-side. |
| Settings | `/settings` | Visible when backend exposes Settings capability. | Account/admin scope | Configuration mutations require backend authority. |
| More | `/more` | Visible when at least one overflow module is visible or the shell needs an overflow landing. Data Control (`tab=data_control`) organizes tools into `Operations & Governance` and `Batch Imports` sub-tabs with URL sync (`subtab=batch_imports`). | Derived from visible module set | Should not reveal hidden modules. |

## Implementation Phases

1. Confirm Mobile RBAC contract names and scope semantics in Supabase.
2. Add a server-capable Supabase helper for App Router session reads once an SSR cookie adapter/package is approved.
3. Dashboard layout session guard and unauthenticated redirect to `/login` are implemented in the client auth shell.
4. Typed current-user context loading now calls `get_web_current_user_context`.
5. Stable module keys have been added to `webModules`; align them with backend capability keys when the contract is confirmed.
6. `Sidebar` and `AdminTopbar` now filter navigation from resolved module visibility.
7. Direct navigation to hidden modules redirects back to `/vacancy` (or authorized primary module) in the client shell.
8. Replace placeholder module queries only after each module's data contract and RLS policy are approved.

## Exact Next Implementation Prompt

ID: OHM2026_1072-IMPL-1

Implement the safe Supabase current-user context backend contract for OHMployee Web.

Read only:
- `docs/state/web_auth_rbac_state.md`
- `docs/state/web_foundation_state.md`
- `.ai/current_state.md`
- `.ai/handoff.md`
- `src/lib/auth.ts`
- `src/lib/modules.ts`
- Existing Supabase migrations and Mobile RBAC schema/policy files in the authoritative Supabase repo.

Tasks:
1. Add a migration that creates the canonical current-user context RPC, preferably `public.get_web_current_user_context()`.
2. Derive the caller only from `auth.uid()`; do not accept caller-controlled user/profile/role/scope arguments.
3. Return one web-safe context row with:
   - `auth_user_id uuid`
   - `profile_id uuid null`
   - `full_name text null`
   - `email text null`
   - `role_key text null`
   - `role_name text null`
   - `active boolean`
   - `status text`
   - `group_scope_mode text`
   - `group_scope_ids uuid[]`
   - `account_scope_mode text`
   - `account_scope_ids uuid[]`
   - `allowed_module_keys text[]`
   - `capabilities jsonb`
4. Map role, active/disabled state, group scope, account scope, modules, and capabilities from the existing Mobile RBAC authority model.
5. Fail closed:
   - unauthenticated returns no row or an unauthenticated error;
   - missing profile returns `authenticated_profile_missing`, `active = false`, empty scopes/modules/capabilities unless dashboard blocked shell is explicitly backend-approved;
   - inactive returns `inactive`, `active = false`, empty scopes/modules/capabilities;
   - disabled returns `disabled`, `active = false`, empty scopes/modules/capabilities;
   - not web-authorized returns `unauthorized_web`, `active = false`, empty scopes/modules/capabilities.
6. Grant execution only to the authenticated role and keep anonymous callers blocked.
7. If useful after the RPC is safe, add `public.web_current_user_context` as a `security_invoker = true` view with the same shape.
8. Add migration comments/tests or SQL assertions that prove the contract does not expose other users, does not require service role, and preserves RLS/RBAC authority.

Constraints:
- Keep web as a thin admin-panel presentation layer.
- Keep Supabase/RLS/RPC as the authority.
- Do not invent new roles.
- Do not weaken RLS.
- Do not expose service-role credentials or service-role-only data.
- Do not implement frontend UI changes or module business features.
- Do not broaden module access beyond existing Mobile RBAC semantics.

Validation:
- Run the Supabase migration validation/test workflow available in the authoritative backend repo.
- Verify authenticated active users receive only their own context.
- Verify unauthenticated, missing-profile, inactive, disabled, and unauthorized-web cases fail closed.
- Update `docs/state/web_auth_rbac_state.md`, `docs/state/web_foundation_state.md`, `.ai/handoff.md`, and `.ai/current_state.md` with the final RPC/view names and status semantics after implementation.

---

## QA Center & 6-Role Workflow Relay Contract

### `public.qa_run_scenario(p_scenario_code text)`
- **Purpose**: Executes automated QA role workflow scenarios (`VAC_ARCHIVE_001`, `PLANTILLA_001`, `HR_EMPLOC_001`, `CENCOM_001`, `AUTH_MATRIX_001`, `FULL_E2E_RELAY`) in an isolated sandbox with zero production data commitment.
- **Security & Authorization Guard**:
  - `SECURITY DEFINER`, `search_path = public`.
  - Enforces `public.i_have_full_access() OR public.get_my_role_level() >= 90`. Non-admin callers are strictly rejected with an exception.
- **Rollback Sandbox Pattern**:
  - Entire simulation sequence executes inside a PL/pgSQL subtransaction terminated with `RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS'`.
  - Guarantees 100% rollback of test entities across `vacancies`, `plantilla`, `applicants`, and `hr_emploc`.
- **Role Impersonation & Negative Barrier Verification**:
  - Impersonates contexts for all 6 roles (Head Admin, Encoder, Recruitment, HRCO/Ops, HR Personnel, Back Office) via `request.jwt.claims`.
  - Caches caller's original JWT claims and restores them unconditionally upon function exit.
  - Negative barrier probe: verifies that Back Office role cannot execute Head Admin actions; unauthorized leaks trigger critical severity findings.
- **Telemetry Persistence**:
  - Runs registered in `public.qa_agent_runs` (`qa_start_detection_run`, `qa_complete_detection_run`).
  - Findings persisted in `public.qa_agent_findings` (`qa_log_detection_finding`).

---

## 55-Item Drawer Actions & Mutations RBAC Matrix

### Matrix Architecture & Hierarchy
The authoritative 55-item matrix governs operational drawer actions, mutations, and approval queues across all 11 role levels:
- **100: Super Admin** (Owner recovery, full system edit lock, overrides, sessions, archives)
- **90: Head Admin** (Data team leader, all approvals except owner recovery, bulk import)
- **70: Operations Manager (OM)** (Ops team lead, pipeline management, deficiency reviews, schedule/pool mutations)
- **45: HRCO** (Ops coordinator, vacancy lifecycle, applicant movements, pool conversions)
- **42: ATL** (Assistant Team Leader, ops field action execution)
- **41: TL** (Team Leader, ops field action execution)
- **30: Encoder** (Data team operator, bulk imports, MIKA trigger, applicant movements, relievers, headcount approvals)
- **25: HR Personnel** (HR Emploc deficiency correction approval/revert)
- **20: Recruitment** (Applicant profile single edits, applicant movement requests)
- **15: Backoffice** (Deactivation processing)
- **10: Viewer** (Read-only presentation)

### Implementation Artifacts
- **Database Migration:** 
  - `supabase/migrations/20261026000001_update_drawer_actions_rbac.sql`
  - `supabase/migrations/20261111000001_enable_rls_role_permission_definitions_compat.sql`
  - `supabase/migrations/20262606000118_reset_permission_overrides_rpc.sql`
  - `supabase/migrations/20262606000125_rbac_page_batch_matrix_rpc.sql` (`get_all_roles_effective_permission_matrix()`)
  - Upserts definitions into `public.role_permission_definitions_compat` with Row Level Security (RLS) enabled, `anon` access revoked, and authenticated `SELECT` policy (`rpd_compat_read_authenticated`).
  - Registers definition catalog in `public.role_permission_definitions` (`module_key`, `resource_key`, `action_key`).
  - Ensures deny-fill in `public.role_permission_matrix`.
  - Added atomic `public.reset_permission_overrides(p_role_name, p_module_key, p_resource_key, p_action_key, p_reason)` allowing Super Admin to clear active overrides (individually or per-role) and revert permissions to base system defaults with full audit logging.
  - Added batch effective permission matrix RPC `public.get_all_roles_effective_permission_matrix()` returning all 11 roles × 58 permission definitions in a single optimized Security Definer call guarded by `public.is_super_admin()`.
- **Independent RBAC Management Page (`/rbac`):** `src/app/(dashboard)/rbac/page.tsx`
  - Dedicated full-page matrix view (not a modal) accessible exclusively to Super Admin (`roleLevel >= 100`).
  - Hierarchical Module / Route / Roles layout: top-level collapsible module sections with route badges (e.g., `Vacancy` • `/vacancy`), expanding to show individual drawer permissions and resource actions.
  - 11 Role columns with sticky left column for Module/Action names. Super Admin is permanently locked ON (`SA_PROTECTED`).
  - Role grouping filter pills (`All Roles (11)`, `Operations`, `Data Team`, `HR & Recruitment`, `Viewer`) and instant search across module names, action labels, resource keys, and route paths.
  - Staged changes bar at bottom with commit count, "Discard", and "Review & Save Changes" modal requiring mandatory audit reason for compliance tracking.
  - Multi-level reset functionality: per-cell inline revert for active overrides, per-role column header reset (`↺ Reset Role`), and global toolbar reset (`↺ Reset All Overrides`).
- **TypeScript Types & Constants:** `src/types/rbac.ts`
  - `DrawerActionItem`: union of all 33 drawer action strings
  - `RolePermissionRule`, `RoleLevel`, `DrawerActionModule`
- **Web Evaluation & Helpers:** `src/lib/rbac.ts`
  - `DRAWER_ACTION_RULES`: Record mapping each action to allowed numeric levels
  - `canPerformDrawerAction(action, userOrRole)`
  - Individual action helper functions: `canEditHiredDate`, `canReopenVacancySlot`, `canRequestApplicantMovement`, `canExportVacancyDataset`, `canApproveDeficiencyCorrection`, `canRevertDeficiencyCorrection`, `canRollbackImportBatch`, `canUpdateEmploymentLifecycleStatus`, `canUpdateWorkSchedule`, `canRequestPoolConversion`, `canRequestRelieverCoverage`, `canSubmitNewStoreRequest`, `canArchiveUserAccount`, etc.
  - Reconciled `getAllowedApprovalCategories(userOrRole)` matching matrix item 35-42
- **Authoritative Sanity Test Suite:** `src/lib/utils/__tests__/rbac_sanity.test.mjs`
  - Automated unit test suite verifying all 11 system roles across 7 test suites (249 total assertions):
    1. Role Normalization & Level Mapping: verifies canonical `AppRole` normalization, numeric level assignments (10-100), and case/whitespace tolerance for all 11 roles and synonyms (including `Recruitment Specialist`, `Back Office`, `Management Viewer`).
    2. Role Grouping Invariants: evaluates strict exclusivity for `isOwner`, `hasFullAccess`, `isDataTeam`, `isOpsTeam`, and `isEncoder`.
    3. Module Access Gatekeeper (`isModuleAllowedForUser` & individual getters): verifies permissions across all 13 modules (dashboard, vacancy, plantilla, hr_emploc, cencom, approvals, users, reports, notifications, settings, team_directory, more, rbac) confirming `/rbac` is locked exclusively to Super Admin (`level 100`).
    4. Authoritative Drawer Actions (`canPerformDrawerAction`): verifies all 11 roles × 33 drawer actions (363 combinations) with Head Admin immunity and Super Admin ownership.
    5. Action Helper Invariants: confirms 1:1 behavioral parity between `canPerformDrawerAction` and all 33 convenience wrapper functions.
    6. Specialized Pipeline & Quota Invariants: tests `canAddApplicant`, `canManageApplicantPipeline`, `canEditApplicantProfile`, `canReviewVacancyClosures`, `canRequestVacancyClosure`, `canRequestHeadcountAdjustment`, and `canReviseHeadcountQuota`.
    7. Approvals Review Queue Scoping: tests `getAllowedApprovalCategories` across all roles, confirming only SA (13), HA (11), Encoder (6), and Backoffice (2) receive actionable queues while all other 7 roles receive empty lists.
- **Hook & Guard Component:** `src/hooks/useRolePermissions.tsx`
  - `useRolePermissions()`: exposes `canPerformAction`, `roleLevel`, `role`, and groupings
  - `<RoleGuard action="..." minLevel={...} fallback={...}>`: declarative UI barrier

---

## User Management Scope Assignment & Error Mapping

### `friendlyUserError` Mapping
- In `src/lib/queries/users.ts`, `friendlyUserError` maps database exception codes and messages to human-readable UI notices.
- Specific check: only messages containing `"last active super admin"` map to `"This action is blocked because at least one active Super Admin must remain."`. Generic Postgres SQLSTATE `22023` (`invalid_parameter_value`) is no longer hijacked for Super Admin blocking.
- Messages containing `"do not belong to selected groups"` map to `"One or more selected accounts do not belong to the selected groups."`.
- Messages containing `"cannot change your own active status"` map to `"You cannot change your own active status."`.

### Account Scope Synchronization on Group Deselection
- In `src/components/users/UserDetailDrawer.tsx` and `src/components/users/CreateUserModal.tsx`, an `accountGroupRef` (`Map<string, string>`) tracks account-to-group associations across initial user scopes and live query fetches.
- When a group is toggled off, `selectedAccountIds` immediately prunes accounts mapped to the deselected group.
- Prior to submission in `handleSave` or `handleSubmit`, `accountIds` is sanitized to ensure only accounts belonging to active `selectedGroupIds` are passed to `upsert_user_profile_and_scopes`, preventing database Guard (c) violations.

---

## User Management Layout, Density & Activity Audit Standard (ohm#u3s8m2ql)

### 1. Dashboard Layout & Filters
- **Natural Document Scrolling:** Removed fixed `h-screen` or locked vertical overflow constraints, permitting natural page scrolling.
- **Header Tabs (Compact KPIs):** Large metric cards replaced with unified `SegmentedTabs` displaying `All Users (${totalCount})` | `Active (${activeCount})` | `Inactive (${inactiveCount})`.
- **Action Button Hierarchy:** Primary "Create User" (brand fill, SA only), accompanied by deprioritized secondary outlined actions: "Temporary Overrides" (with active badge) and "Account Requests".
- **Unified Filter Bar:** Single horizontal filter row pairing search query, **Role Dropdown**, and **Group Dropdown** (`useGroupsQuery`) directly above the table with filter-change page resets.

### 2. Data Table Specifications
- **Header Structure:** `User` | `Role` | `Group` | `Account` | `Actions`.
- **Density:** Compact row spacing (`px-4 py-2.5`).
- **Cells:**
  - `User`: Circular avatar with initials + Full Name formatted as "Last, First" (`formatPersonName`) with email below.
  - `Role`: Pill tag with italicized `scoped` (or `global`) subtext.
  - `Group` & `Account`: Plain text displaying assigned group/account name(s).
  - `Actions`: Kebab menu (`...`) offering "Deactivate user" / "Activate user", "Reset password", and "Archive user" with modal confirmation gates.
  - `Pagination`: Standard bottom `TablePagination` with rows-per-page selector (10, 25, 50).

### 3. User Detail Drawer & Activity Log
- **Overview Tab Role Assignment:** Read-only role display paired with "Edit Role" button restricted to SA and HA. Triggers an explicit `EditRoleConfirmationModal` with diff preview (`Current ➔ New`) before saving.
- **Danger Zone Actions:** Matches table kebab menu items with status toggle, password reset, and soft archival.
- **Activity Log Conversational Translation:** Raw action blocks (e.g. `UPDATE_USER_ROLE`, `TOGGLE_USER_STATUS`) translated into conversational sentences answering *what, who, and when* with circular initials avatar (e.g. *Avatar* `Litong, Ohm (Super Admin) changed the user's role from HR Personnel to HRCO on Nov 9, 2026 at 09:38 AM.`).

---

## Hard Admin Immunity Bypass across Web & Mobile (ohm#rbac-admin-immunity-bypass-web-mobile)

Expanded universal administrative immunity to eliminate false-negative restriction gates across Web and Mobile:
1. **Web RBAC Action Matrix (`src/lib/rbac.ts`)**:
   - `canPerformDrawerAction`: Super Admin (`roleLevel >= 100` / `isOwner`) unconditionally bypasses all drawer mutation checks. Head Admin (`roleLevel >= 90`) unconditionally bypasses all operational, plantilla, vacancy, data control, and approval actions (excluding root owner controls).
   - `canViewHrEmploc`: Evaluates `if (hasFullAccess(userOrRole)) return true;` as first line.
2. **Web Dashboard Shell (`src/components/DashboardAuthShell.tsx`)**:
   - `canViewActiveModule`: Immediate bypass for `hasFullAccess(currentUser) || isOwner(currentUser) || getRoleLevel(currentUser) >= 90`, ensuring admins are never redirected away from valid module routes.
3. **Mobile Core Auth & Navigation (`OHMployee`)**:
   - `lib/core/auth/auth_service.dart`: `canSeeHREmploc`, `canEndorseToOps`, `canConfirmOnboard`, and `canAddApplicant` fortified with `hasFullAccess` bypass.
   - `lib/core/auth/module_visibility.dart`: `roleDefault` and `canViewModule` grant unconditional view access for `hasFullAccess || roleLevel >= 90`, overriding any database deny mutations.
   - `lib/features/more/more_screen.dart`: `_canSeeItem` grants unconditional visibility for `hasFullAccess || roleLevel >= 90`, guaranteeing admins access to all request centers and review queues.

---

## RBAC Matrix Lock Bleed Resolution (`ohm#fix-rbac-matrix-lock-bleed`)

Resolved bug causing 100% of sub-action toggle switches across all operational roles on the dedicated `/rbac` page to be falsely disabled (`disabled:opacity-40 disabled:cursor-not-allowed`) and marked with a `Locked` badge:
1. **Database Migration (`supabase/migrations/20262606000152_fix_rbac_matrix_system_locked_rpc.sql`)**:
   - Updated `public.get_all_roles_effective_permission_matrix` to return `d.is_system_locked` directly instead of overloading it with `CASE WHEN r.role_name = 'Super Admin' THEN true ELSE d.is_system_locked END`.
   - Pushed live to Staging (`qqiiznmqxfoamqytjica`) with zero errors and live `pg_get_functiondef` parity.
2. **Frontend Matrix Deduplication Guard (`src/app/(dashboard)/rbac/page.tsx`)**:
   - In `distinctDefinitions`, fortified `defMap` population to prefer non-locked row values (`if (!existing || (existing.isSystemLocked && !r.isSystemLocked))`) so Super Admin's role-level immunity does not bleed into the definition-level catalog.
   - In `ModuleGroupRows`, updated cell evaluation to `const isLocked = (role.level >= 100) || (row?.isSystemLocked ?? def.isSystemLocked)`, ensuring Super Admin remains permanently protected while the 38 operational permissions are interactive and editable for operational roles (Head Admin, OM, HRCO, ATL, TL, Encoder, etc.).

---

---

## Data Team & HR Personnel Deficiency Review RBAC Alignment (`ohm#restrict-deficiency-review-to-hr-personnel`)

Refined HR Emploc Deficiency Review actions to be strictly restricted to **Super Admin (100)** and **HR Personnel (25)** only:
1. **Approve Deficiency Correction Review**: Restricted strictly to Super Admin (100) and HR Personnel (25). Denied for all Ops team members (OM 70, HRCO 45, ATL 42, TL 41) and Data Team (Head Admin 90, Encoder 30).
2. **Revert / Reject Deficiency Correction Review**: Restricted strictly to Super Admin (100) and HR Personnel (25). Denied for all Ops team members and Data Team.
3. **Web Authoritative Matrix (`src/lib/rbac.ts`)**:
   - Updated `DRAWER_ACTION_RULES["Approve Deficiency Correction Review"]` to `[100, 25]`.
   - Updated `DRAWER_ACTION_RULES["Revert / Reject Deficiency Correction Review"]` to `[100, 25]`.
4. **Database Migration (`supabase/migrations/20262606000154_restrict_deficiency_review_to_hr_personnel.sql`)**:
   - Synchronized `role_permission_definitions_compat` and base matrix table `role_permission_matrix` on Staging (`qqiiznmqxfoamqytjica`) to deny OM, HRCO, ATL, and TL while preserving allowances for Super Admin and HR Personnel.


Enforced strict role-level alignment for the Data Team (Head Admin L90 and Encoder L30) across drawer actions, mutations, approval queues, and database permission catalogs:
1. **HR Emploc Deficiency Reviews**:
   - **Approve Deficiency Correction Review**: Strictly **DENIED** for Head Admin (90) and Encoder (30) (restricted to Ops and HR Personnel 25, plus SA 100).
   - **Revert / Reject Deficiency Correction Review**: Strictly **DENIED** for Head Admin (90) and Encoder (30).
2. **Plantilla Employment Lifecycle Status**:
   - **Update Employment Lifecycle Status**: Strictly **DENIED** for Head Admin (90) and Encoder (30) (restricted to Ops: OM 70, HRCO 45, ATL 42, TL 41, plus SA 100).
3. **Users Management**:
   - **Deactivate / Reactivate User Account**: **ALLOWED** for Head Admin (90), **DENIED** for Encoder (30) (restricted to SA 100 and HA 90).
4. **Vacancy Management**:
   - **Edit Hired Date**: Strictly **DENIED** for both Head Admin (90) and Encoder (30) (restricted to Ops: OM 70, HRCO 45, ATL 42, TL 41, plus SA 100).
5. **Approvals Hub Queues**:
   - **Employee Deactivations Queue**: Strictly **DENIED** for Head Admin (90) and Encoder (30) in `getAllowedApprovalCategories` (restricted to Super Admin 100 and Backoffice Personnel 15).
   - **Batch Rollback Requests (`rollbacks`)**: **ALLOWED** for Head Admin (90) and Super Admin (100), strictly **DENIED** for Encoder (30).
6. **Web RBAC Action Matrix Evaluator (`src/lib/rbac.ts`)**:
   - Removed blanket `level >= 90` bypass inside `canPerformDrawerAction`, ensuring `DRAWER_ACTION_RULES[actionItem]` remains the authoritative source of truth for allowed role levels. Super Admin (`level >= 100` / `isOwner`) retains administrative universal immunity.
   - Updated `DRAWER_ACTION_RULES` entries for `"Edit Hired Date"`, `"Approve Deficiency Correction Review"`, `"Revert / Reject Deficiency Correction Review"`, and `"Rollback / Reject Import Batch"`.
7. **Database Migration (`supabase/migrations/20262606000153_align_data_team_rbac_permissions.sql`)**:
   - Synchronized `role_permission_definitions_compat` and base matrix table `role_permission_matrix` on Staging (`qqiiznmqxfoamqytjica`) for all 6 affected definitions across Head Admin and Encoder roles.


