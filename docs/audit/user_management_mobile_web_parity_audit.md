# User Management Mobile-to-Web Parity Audit & Implementation Specifications

**Audit ID:** `ohm#w26u417b`  
**Date:** 2026-10-10  
**Auditor:** Antigravity (Read-Only Deep Audit Pass)  
**Target Codebases:**
- Mobile Source of Truth: `D:\Projects\OHMployee`
- Web Implementation Target: `D:\Projects\ohmployee-web`

---

## 1. Executive Summary

This audit performs an end-to-end architectural and functional inventory of **User Management** in the mobile Flutter application ([`OHMployee`](file:///D:/Projects/OHMployee)) and contrasts it with the current Next.js 15 App Router web implementation in [`ohmployee-web`](file:///D:/Projects/ohmployee-web).

### Current Status
- **Mobile (`OHMployee`):** Complete, production-hardened administrative suite featuring an Active/Inactive tabbed user directory, 3-tab user inspector & editor (`Overview`, `Scope`, `Activity Log`), atomic per-group and per-account scope assignments (`OHM2026_3003`), role hierarchy guards (Super Admin vs. Head Admin), HRCO Global Visibility controls (`ohm#7gk2d9xq`), soft archiving, and audited password reset dispatching.
- **Web (`ohmployee-web`):** Complete placeholder shell. Route [`src/app/(dashboard)/users/page.tsx`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/users/page.tsx) renders only `<ModuleEmptyState href="/users" />`. No query hooks, components, or mutating mutations exist for User Management on web.

---

## 2. Feature & Action Inventory

### 2.1 Directory, Views & Filtering

| Feature / UI Element | Mobile Implementation (`user_management_screen.dart`) | Current Web (`users/page.tsx`) | Parity Status |
| :--- | :--- | :--- | :--- |
| **Top KPI Metrics Bar** | 3 Metric Cards: Total Users, Active Users, Inactive Users (dynamically calculated from filtered records). | None (`ModuleEmptyState`) | ❌ **Missing on Web** |
| **Directory Tabs** | TabBar with 2 primary tabs: `Active (count)` and `Inactive (count)`. Inactive includes Suspended and Archived. | None | ❌ **Missing on Web** |
| **Search Bar** | Live fuzzy/normalized text search matching: full name, display-normalized name (`Lastname, Firstname Middlename`), email, role name, and group scope label. | None | ❌ **Missing on Web** |
| **Role Filter** | Bottom-sheet/Modal filter with role options extracted dynamically from accessible users (`All`, `Super Admin`, `Head Admin`, `Encoder`, etc.), plus an active dismissible pill chip. | None | ❌ **Missing on Web** |
| **List Cards / Rows** | Cards display: Avatar initials, Normalized Full Name, Role badge, Status badge (`Active` green, `Suspended` orange, `Archived` grey), HRCO Global/Scoped badge, `No login linked` warning badge, and formatted scope summaries (`Group • X Accounts` / `Global HQ • All Accounts`). | None | ❌ **Missing on Web** |

### 2.2 User Details / Edit Inspector (3-Tab Architecture)

When opening an existing user (or tapping Create User for Super Admins), mobile presents a unified modal/detail view with 3 tabs:

#### Tab 1: Overview
1. **Basic Information Card:**
   - **Full Name:** Text input. Read-only for existing users (system-managed); editable only on new user creation.
   - **Email:** Text input. Read-only for existing users; editable on creation.
   - **Role Dropdown:** Single select. Super Admin can assign any role; Head Admin can only assign roles with level `< 90` (cannot assign Super Admin or Head Admin). Locked if the target user is Super Admin or Head Admin.
2. **Permission Summary Card (Live Preview):**
   - Live preview of resolved Role, readable Groups list (`Global HQ / All Groups` or comma-separated group names), and readable Accounts scope (`All Accounts`, `All Accounts (Group Wide)`, or `(X) Account1, Account2, +Y more`).
3. **Danger Zone Card (Admin Lifecycle Actions):**
   - **Activate / Deactivate User:** Toggles between `Active` and `Suspended`. Disabled with explicit reason if viewing own profile (`_isSelf`), or if target is Super Admin and caller is Head Admin.
   - **Reset Password:** Prompts confirmation dialog, executes `fn_log_password_reset_request`, and dispatches Supabase Auth password reset email to target user's email address.
   - **Archive Account:** Soft-archives the account (`fn_archive_user_account`), setting `is_active = false`, `archived_at = NOW()`, and `archived_by = auth.uid()`.

#### Tab 2: Scope
1. **Group Scope Selector:**
   - Multi-select pill chips showing all active groups from `groups` table.
   - Selecting `Global HQ` automatically grants access to all groups and accounts, clearing specific account selections.
   - Group changes dynamically trigger account re-fetching via `fn_get_accounts_by_groups`.
2. **Account Scope Picker:**
   - Collapsed multi-select dropdown field displaying readable summary (e.g., `Select accounts...`, `BACKYARD, JACKPOT, +3 more`, and `Y selected`).
   - Modal picker with search input, `Select All`, `Clear All`, and individual checkboxes.
   - Mutually exclusive semantics: selecting specific accounts under a group restricts user to those accounts; leaving account selection empty implies group-wide access (all accounts in that group).
   - Prunes accounts automatically if their parent group is deselected.
3. **HRCO Global Visibility Card:**
   - Switch toggle visible **only** when target role is `HRCO` (`ohm#7gk2d9xq`).
   - Bypasses per-employee plantilla HRCO assignments, allowing the HRCO to view all employees within their allowed account scopes.

#### Tab 3: Activity Log
- Chronological timeline of audit entries from `audit_logs` where `record_id == user.profile_id`.
- Displays action badge (`CREATE_USER`, `UPDATE_USER_ROLE`, `ACTIVATE_USER`, `DEACTIVATE_USER`, `ARCHIVE_USER`, `RESET_PASSWORD_REQUEST`), timestamp, actor name, and actor role.

### 2.3 Creation & Mutation Lifecycles
- **Create User Button:** Header action in directory, visible and enabled **only** for Super Admin (`role_level >= 100`). Head Admin cannot create users.
- **Save Changes Flow:** Sticky footer button enabled only when editable changes exist (`_hasEditableChanges`) and target is not locked.
- **Diff Confirmation Dialog:** Shows explicit before-and-after comparison rows for Role, Group Scope, Account Scope, Status, and HRCO Visibility before invoking backend RPCs.
- **Re-login Notice:** Confirmation snackbar warns: *"Scope changes take effect after the affected user signs in again."*

---

## 3. Database Schema & RPC Mapping

### 3.1 Tables Involved

```
┌─────────────────────────────────┐           ┌─────────────────────────────────┐
│          auth.users             │           │              roles              │
├─────────────────────────────────┤           ├─────────────────────────────────┤
│ id: uuid (PK)                   │◄───────┐  │ id: uuid (PK)                   │
│ email: varchar                  │        │  │ role_name: varchar              │
│ raw_user_meta_data: jsonb       │        │  │ role_level: int4 (0..100)       │
└─────────────────────────────────┘        │  └─────────────────────────────────┘
                                           │                   ▲
                                           │                   │ role_id
┌──────────────────────────────────────────┴───────────────────┴────────────────┐
│                                 users_profile                                 │
├───────────────────────────────────────────────────────────────────────────────┤
│ id: uuid (PK)                                                                 │
│ auth_user_id: uuid (FK auth.users, nullable - unlinked profiles supported)    │
│ full_name: text (NOT NULL)                                                    │
│ email: text                                                                   │
│ mobile_number: text                                                           │
│ role_id: uuid (FK roles, NOT NULL)                                            │
│ is_active: boolean (DEFAULT true)                                             │
│ hrco_global_visibility: boolean (DEFAULT false)                               │
│ archived_at: timestamptz (DEFAULT NULL)                                       │
│ archived_by: uuid (FK auth.users, DEFAULT NULL)                               │
│ created_at: timestamptz                                                       │
│ updated_at: timestamptz                                                       │
└──────────────────────────────────────┬────────────────────────────────────────┘
                                       │ user_id
                                       ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                                  user_scopes                                  │
├───────────────────────────────────────────────────────────────────────────────┤
│ id: uuid (PK)                                                                 │
│ user_id: uuid (FK users_profile.id, ON DELETE CASCADE)                        │
│ group_id: uuid (FK groups.id, ON DELETE CASCADE)                              │
│ account_id: uuid (FK accounts.id, ON DELETE CASCADE, nullable)                │
│ UNIQUE (user_id, group_id, account_id)                                        │
└───────────────────────────────────────────────────────────────────────────────┘
```

#### Related Reference Tables:
- `groups`: `id (uuid PK)`, `group_name (text)`, `is_active (boolean)`.
- `accounts`: `id (uuid PK)`, `group_id (uuid FK groups)`, `account_name (text)`, `is_active (boolean)`, `status (text)`.
- `audit_logs`: `id (uuid PK)`, `actor_id (uuid)`, `module (text)`, `action (audit_action)`, `record_id (uuid)`, `old_data (jsonb)`, `new_data (jsonb)`, `timestamp (timestamptz)`.

---

### 3.2 Complete RPC Registry & Payload Specifications

#### 1. `get_web_current_user_context()`
- **Type:** `TABLE (...)` (Read, Security Definer)
- **Parameters:** None (`auth.uid()` inferred from Supabase JWT).
- **Purpose:** Verifies current web session, checks if `users` module is in `allowed_module_keys`, and determines caller's `role_level` and full access status.

#### 2. `upsert_user_profile_and_scopes`
- **Type:** `FUNCTION (UUID)` (Security Definer)
- **Signature:**
  ```sql
  upsert_user_profile_and_scopes(
    p_full_name   TEXT,
    p_email       TEXT,
    p_role_id     UUID,
    p_group_ids   UUID[],
    p_account_ids UUID[] DEFAULT '{}',
    p_profile_id  UUID DEFAULT NULL
  ) RETURNS UUID
  ```
- **Payload Parameters:**
  - `p_full_name` (`string`): User full name.
  - `p_email` (`string`): User email address.
  - `p_role_id` (`string` / UUID): Primary role ID.
  - `p_group_ids` (`string[]` / UUID[]): Array of selected group IDs.
  - `p_account_ids` (`string[]` / UUID[]): Array of specific account IDs. If empty, all accounts in the selected groups are granted.
  - `p_profile_id` (`string?` / UUID, nullable): If `null`, performs user creation (Super Admin only); if provided, updates profile and atomically replaces `user_scopes`.
- **Enforcement & Guards:**
  - Caller must have `role_level >= 90`.
  - `p_profile_id IS NULL` requires `role_level >= 100` (Super Admin).
  - Risk control assertion `fn_assert_risk_control_enabled('risk_role_editing')`.
  - Cannot assign role with `role_level >= caller_level` unless caller is Super Admin.
  - Every account in `p_account_ids` must belong to a group in `p_group_ids` (ERRCODE `22023`).
  - Emits audit log: `CREATE_USER` or `UPDATE_USER_ROLE`.

#### 3. `set_user_active`
- **Type:** `FUNCTION (void)` (Security Definer)
- **Signature:**
  ```sql
  set_user_active(
    p_profile_id UUID,
    p_is_active  BOOLEAN
  ) RETURNS void
  ```
- **Payload Parameters:**
  - `p_profile_id` (`string` / UUID): Target profile ID.
  - `p_is_active` (`boolean`): New active status (`true` = Active, `false` = Suspended).
- **Enforcement & Guards:**
  - Caller must have `role_level >= 90`.
  - Self-action blocked (`ERRCODE 42501`).
  - Head Admin cannot deactivate a Super Admin (`ERRCODE 42501`).
  - Blocked if target is the last active Super Admin (`ERRCODE 22023`).
  - Emits audit log: `ACTIVATE_USER` or `DEACTIVATE_USER`.

#### 4. `fn_archive_user_account`
- **Type:** `FUNCTION (void)` (Security Definer)
- **Signature:**
  ```sql
  fn_archive_user_account(
    p_profile_id UUID
  ) RETURNS void
  ```
- **Payload Parameters:**
  - `p_profile_id` (`string` / UUID): Target profile ID.
- **Enforcement & Guards:**
  - Caller must have `role_level >= 90`.
  - Self-archive blocked (`ERRCODE 42501`).
  - Head Admin cannot archive a Super Admin (`ERRCODE 42501`).
  - Soft archive only: sets `is_active = FALSE`, `archived_at = NOW()`, `archived_by = auth.uid()`.
  - Emits audit log: `ARCHIVE_USER`.

#### 5. `fn_log_password_reset_request`
- **Type:** `FUNCTION (text)` (Security Definer)
- **Signature:**
  ```sql
  fn_log_password_reset_request(
    p_profile_id UUID
  ) RETURNS text
  ```
- **Payload Parameters:**
  - `p_profile_id` (`string` / UUID): Target profile ID.
- **Returns:**
  - `email` (`text`): Target user email address for client-side dispatch.
- **Enforcement & Guards:**
  - Caller must have `role_level >= 90`.
  - Self-reset blocked (`ERRCODE 42501`).
  - Head Admin cannot reset a Super Admin (`ERRCODE 42501`).
  - Target must have a non-empty registered email (`ERRCODE 22023`).
  - Emits audit log: `RESET_PASSWORD_REQUEST`.
  - Caller then invokes `supabase.auth.resetPasswordForEmail(email)`.

#### 6. `set_hrco_global_visibility`
- **Type:** `FUNCTION (void)` (Security Definer)
- **Signature:**
  ```sql
  set_hrco_global_visibility(
    p_profile_id UUID,
    p_enabled    BOOLEAN
  ) RETURNS void
  ```
- **Payload Parameters:**
  - `p_profile_id` (`string` / UUID): Target profile ID.
  - `p_enabled` (`boolean`): Whether global visibility is enabled.
- **Enforcement & Guards:**
  - Caller must be Data Team (`role_level >= 90` or Encoder) or Super Admin.
  - Target profile role must be `'HRCO'` (ERRCODE `22023`).
  - Emits audit log: `UPDATE_USER_ROLE`.

#### 7. `fn_get_accounts_by_groups`
- **Type:** `FUNCTION (TABLE(id UUID, account_name TEXT, group_id UUID))` (Security Definer)
- **Signature:**
  ```sql
  fn_get_accounts_by_groups(
    p_group_ids UUID[]
  ) RETURNS TABLE(id UUID, account_name TEXT, group_id UUID)
  ```
- **Payload Parameters:**
  - `p_group_ids` (`string[]` / UUID[]): Selected group IDs.
- **Returns:** Active accounts where `is_active = true AND status = 'Active'` for the given groups.

---

## 4. Parity Gap Analysis

| Area / Capability | Mobile Reference (`OHMployee`) | Current Web (`ohmployee-web`) | Severity | Web Parity Requirement |
| :--- | :--- | :--- | :--- | :--- |
| **Route & Page Entry** | Gated by `isSuperAdmin \|\| isHeadAdmin`. | Renders `<ModuleEmptyState href="/users" />`. | **Critical** | Implement full `UsersPage` with Admin header, KPIs, Tabs, and Table. |
| **User Listing Query** | Query `users_profile` with joins to `roles` and nested `user_scopes(groups, accounts)`. | No queries in `src/lib/queries/` for users. | **Critical** | Create `src/lib/queries/users.ts` with React Query hooks. |
| **Active / Inactive Tabs** | Dual tabs filtering users with counts: `Active (X)`, `Inactive (Y)`. | None | **High** | Add tab switcher matching web design system (`AdminFilterBar` / `Tabs`). |
| **Search & Role Filter** | Name/email/scope search + dynamic role filter modal/pills. | None | **High** | Implement search input and role filter dropdown in `AdminFilterBar`. |
| **User Detail Drawer** | 3-tab slide/push screen (`Overview`, `Scope`, `Activity Log`). | None | **Critical** | Implement `UserDetailDrawer.tsx` with identical 3-tab layout. |
| **User Creation** | Super Admin only modal (`AddEditUserScreen`). | None | **High** | Add `CreateUserModal.tsx` or create mode in `UserDetailDrawer`. |
| **Scope Management** | Group chips + dynamic Account multi-picker with `fn_get_accounts_by_groups`. | None | **Critical** | Implement `GroupScopePicker` and `AccountScopePicker` components. |
| **HRCO Visibility Toggle** | Conditional switch for HRCO role calling `set_hrco_global_visibility`. | None | **Medium** | Add toggle card in Scope tab when `selectedRoleId` resolves to HRCO. |
| **Admin Actions (Danger Zone)** | Activate/Deactivate, Soft-Archive, audited Password Reset. | None | **High** | Implement lifecycle action buttons with confirmation modals. |
| **Activity Log Tab** | Queries `audit_logs` where `record_id == profile_id`. | None | **Medium** | Implement activity log list component in Detail Drawer Tab 3. |
| **RBAC UI Gating** | Head Admin cannot see or edit Super Admin accounts; cannot create users. | None | **Critical** | Enforce client-side role rules mirroring `_canSeeUser` and `_canManageUser`. |

---

## 5. Implementation Roadmap for Web Parity

### Phase 1: Data Access & Queries Layer (`src/lib/queries/users.ts`)
1. Define TypeScript interfaces:
   - `UserScopeItem`: `{ groupId: string; groupName: string; accountId?: string | null; accountName?: string | null; }`
   - `UserProfileItem`: normalized profile model with `status` (`Active` | `Suspended` | `Archived`), `normalizedName`, and `scopeSummaries`.
   - `RoleOption`: `{ id: string; name: string; level: number; }`
   - `GroupOption`: `{ id: string; name: string; }`
   - `AuditLogEntry`: audit trail record for Activity Log.
2. Implement Query Hooks:
   - `useUsersListQuery()`: queries `users_profile` with `roles` and `user_scopes` joins.
   - `useRolesQuery()`: fetches available roles from `roles`.
   - `useGroupsQuery()`: fetches active groups from `groups`.
   - `useAccountsByGroupsQuery(groupIds: string[])`: invokes `fn_get_accounts_by_groups`.
   - `useUserAuditLogsQuery(profileId: string)`: fetches user audit entries from `audit_logs`.
3. Implement Mutation Hooks:
   - `useSaveUserMutation()`: calls `upsert_user_profile_and_scopes`.
   - `useSetUserActiveMutation()`: calls `set_user_active`.
   - `useArchiveUserMutation()`: calls `fn_archive_user_account`.
   - `useResetPasswordMutation()`: calls `fn_log_password_reset_request` followed by `supabase.auth.resetPasswordForEmail`.
   - `useSetHrcoVisibilityMutation()`: calls `set_hrco_global_visibility`.

### Phase 2: User Listing Components (`src/components/users/`)
1. **`UserMetricsCards.tsx`**: Top summary banner with Total Users, Active, and Inactive KPI cards.
2. **`UserFilterBar.tsx`**: Search field, Role filter dropdown, and active filter pill.
3. **`UserTable.tsx`**:
   - Table columns: User (avatar + normalized name + email), Role, Scope Summary, Status Badge, HRCO Flag, Actions.
   - Clickable row opens `UserDetailDrawer`.
   - Head Admin filtering: excludes Super Admin rows if caller is Head Admin.

### Phase 3: User Detail & Edit Drawer (`src/components/users/UserDetailDrawer.tsx`)
1. **Header & Status Banner:**
   - Avatar initials, name, email, role badge, status badge, and close button.
   - Tabs: `Overview`, `Scope`, `Activity Log`.
2. **Tab 1: Overview:**
   - Basic Info Card: Full Name & Email (read-only for existing users), Role Dropdown (assignable roles filtered by caller level).
   - Live Permission Summary Card: groups and accounts scope preview.
   - Danger Zone Card: Activate/Deactivate, Reset Password, Archive Account with confirmation modals.
3. **Tab 2: Scope:**
   - Group Scope multi-select chips.
   - Dynamic Account Scope multi-select with search and Select All / Clear All.
   - HRCO Global Visibility switch toggle (conditional on HRCO role).
4. **Tab 3: Activity Log:**
   - Audit trail cards showing action, timestamp, and actor details.
5. **Sticky Action Bar:**
   - Diff confirmation dialog before submitting changes.
   - Re-login banner notification upon successful scope mutation.

### Phase 4: Create User Modal (`src/components/users/CreateUserModal.tsx`)
- Modal accessible to Super Admin only via `+ New User` button in top header.
- Form fields: Full Name, Email, Role dropdown, Group Scope chips, and Account Scope picker.
- Submits via `upsert_user_profile_and_scopes` with `p_profile_id = null`.

### Phase 5: Page Integration & Verification (`src/app/(dashboard)/users/page.tsx`)
- Replace `<ModuleEmptyState />` with `DashboardAuthShell` gated view.
- Verify entry permissions: only Super Admin and Head Admin can access `/users`.
- Wire up state management and verify full 1-to-1 parity against mobile.

---

## 6. Audit Verification & Sign-Off

- **Audit File Generated:** [`docs/audit/user_management_mobile_web_parity_audit.md`](file:///d:/Projects/ohmployee-web/docs/audit/user_management_mobile_web_parity_audit.md)
- **Mode:** Read-Only Audit (No application code mutated).
- **Parity Rating:** Mobile: 100% Production Ready | Web: 0% (Shell Placeholder). Full specification documented for implementation.
