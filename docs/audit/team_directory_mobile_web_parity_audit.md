# Team Directory Mobile-to-Web Parity Audit & Implementation Specifications

**Audit ID:** `ohm#w41t932f`  
**Date:** 2026-10-12  
**Auditor:** Antigravity (Read-Only Deep Parity Audit Pass)  
**Target Codebases:**
- Mobile Source of Truth: `D:\Projects\OHMployee`
- Web Target: `D:\Projects\ohmployee-web`

---

## 1. Executive Summary

This audit performs an end-to-end architectural, functional, and schema inventory of the **Team Directory** module in the mobile Flutter application ([`OHMployee`](file:///D:/Projects/OHMployee)) and compares it with the current placeholder route (`src/app/(dashboard)/team-directory/page.tsx`) in [`ohmployee-web`](file:///D:/Projects/ohmployee-web) to define the 1-to-1 operational parity requirements and web implementation roadmap.

### Current Status
- **Mobile (`OHMployee`):**
  - **Feature Complete & Field-Proven:** Implemented in [`lib/features/team_directory/team_directory_screen.dart`](file:///D:/Projects/OHMployee/lib/features/team_directory/team_directory_screen.dart), backed by [`lib/data/services/team_directory_service.dart`](file:///D:/Projects/OHMployee/lib/data/services/team_directory_service.dart) and [`lib/data/models/team_directory_user.dart`](file:///D:/Projects/OHMployee/lib/data/models/team_directory_user.dart).
  - **Backend Hardening:** Powered by the secure, server-side security-definer RPC `public.get_team_directory()` (established in `20260522220000`, refined in `20260523110000`, and updated in `20260903000000_team_directory_uat_fix_pack.sql`).
  - **Operational Purpose:** Allows active operational staff (Operations Managers, Team Leaders, Assistant Team Leaders, HR Coordinators, Encoders, Recruitment, HR/Back-Office Personnel, and Viewers) to search, find, and contact colleagues while maintaining strict data minimization (zero exposure of sensitive HR/payroll data such as salary, ATM, civil status, or performance notes).
  - **Relational Intelligence:** Computes live reporting lines ("Reports To" and "Direct Reports") both through explicit manager IDs and hierarchical scope-matching fallbacks (`super_admin` ↔ `head_admin` ↔ `encoder` and `om` ↔ `tl` ↔ `atl` ↔ `hrco`).
- **Web (`ohmployee-web`):**
  - **Placeholder Only:** Route [`src/app/(dashboard)/team-directory/page.tsx`](file:///D:/Projects/ohmployee-web/src/app/(dashboard)/team-directory/page.tsx) renders only `<ModuleEmptyState href="/team-directory" />`.
  - **Infrastructure Ready:** The web navigation menu, modules registry ([`src/lib/modules.ts`](file:///D:/Projects/ohmployee-web/src/lib/modules.ts)), and user context RPC (`get_web_current_user_context`) already declare and authorize the `team_directory` module key. However, no query hooks, directory tables/grids, or detail drawers have been implemented yet.

---

## 2. Feature & View Inventory

### 2.1 Screen Architecture & Primary Views

In mobile, the Team Directory is accessible from the **More** module drawer (`MoreSectionId.teamDirectory`) for all active roles down to Viewer (`role_level >= 10`).

| UI Component / Feature | Mobile Implementation (`team_directory_screen.dart`) | Web Status (`team-directory/page.tsx`) | Parity Requirement for Web |
| :--- | :--- | :--- | :--- |
| **Search Bar** | Live search field with 350ms debounce and clear button. Matches full name, mobile number, and email. | ❌ None (`ModuleEmptyState`) | Integrate with shared [`AdminFilterBar`](file:///D:/Projects/ohmployee-web/src/components/shared/AdminFilterBar.tsx) with debounced input and clear button. |
| **Role Filter** | Popup menu filter dynamically populated from directory roles (plus "All roles" option), with active filter indicator (blue border when active). | ❌ None | Add Role filter dropdown within `AdminFilterBar` / `filterSlot`. |
| **Group / Account Scope Filter** | Supported by the underlying RPC (`p_group_id`, `p_account_id`), used for scoped multi-filtering. | ❌ None | Surface optional Group & Account selectors in the filter bar for high-tier roles (Super Admin, Head Admin, OM). |
| **View Layout** | Vertical card list (`_TeamDirectoryCard`). Compact, touch-friendly, with avatar + status dot, role badge, scope summary, contact snippet, and action chips. | ❌ None | Provide a responsive desktop layout: **Table View** (matching `UsersTable` / `HrEmplocTable` style) with optional toggle to **Grid/Card View**. |
| **Status Indicator** | Dot on avatar (green for `Available`) and dedicated `_StatusChip` in modal (Available, Busy, On Leave, Offline). | ❌ None | Implement [`StatusBadge`](file:///D:/Projects/ohmployee-web/src/components/ui/StatusBadge.tsx) / Avatar status indicator matching the 4 canonical states. |
| **Contact Action Chips** | Direct quick-action buttons on card: Call (`tel:`), SMS (`sms:`), Email (`mailto:`). Disabled with dimmed state if data is missing. | ❌ None | One-click contact action buttons (Copy to clipboard, `tel:`, and `mailto:` links with tooltips). |
| **Detail Inspector** | Bottom sheet (`DraggableScrollableSheet`) displaying header, full contact info, assigned Groups, assigned Accounts, and Interactive Reporting Structure. | ❌ None | Standard desktop slide-in [`DetailDrawer`](file:///D:/Projects/ohmployee-web/src/components/shared/DetailDrawer.tsx) on the right side. |

---

### 2.2 Card / Row Metadata & Formatting

Mobile renders each directory contact with clear visual hierarchy:

1. **Avatar:**
   - Profile photo from `profile_photo_url` if present; fallback to circular monogram avatar.
   - Distinct role background tint:
     - Super Admin: Purple (`#7C3AED`)
     - Head Admin: Teal (`#0F766E`)
     - Operations Manager (OM): Brand Blue (`#0053A6`)
     - Recruitment: Amber (`#B45309`)
     - Encoder: Slate (`#475569`)
     - General / Other (TL, ATL, HRCO): Brand Primary (`#0053A6`)
   - Online/Available green indicator badge (`#22C55E`) at bottom right of avatar.
2. **Name Formatting (`_formatDirectoryName`):**
   - Follows proper case: `Lastname, Firstname M.`
   - Formats `lastName` and `firstName` with single initial of `middleName` followed by period.
   - Graceful fallback to `fullName` or `displayName`.
3. **Role & Scope Summary:**
   - Line 2: `RoleName • ScopeSummary`
   - Scope Summary formatting:
     - Global Access (Super Admin)
     - All Groups (Head Admin)
     - Single Group: Group Name (e.g. `NORTH NCR`)
     - Multiple Groups: `X Groups`
     - Single Account: Account Name (e.g. `SM NORTH`)
     - Multiple Accounts: `Y Accounts`
     - Combined: `GroupSummary • AccountSummary`
     - Fallback: `No scope assigned`
4. **Contact Summary:**
   - Line 3: `Mobile • Email`
5. **Quick Actions:**
   - `Call` (`tel:<number>`), `SMS` (`sms:<number>`), `Email` (`mailto:<email>`).

---

### 2.3 Detail Drawer / Sheet & Reporting Structure

When clicking a user card in mobile, a comprehensive modal opens:

#### Section 1: Header Profile
- Large Avatar (radius 36) + Name + Role + Status Chip (`Available` | `Busy` | `On Leave` | `Offline`).

#### Section 2: Contact Information
- **Mobile Number:** Value with phone icon (or `-` if missing).
- **Email Address:** Value with mail icon (or `-` if missing).

#### Section 3: Scope Breakdown
- **Groups:** Distinct bulleted list of assigned group names (or `Global Access`, `All Groups`, or `No groups assigned`).
- **Accounts:** Distinct bulleted list of assigned account names (or `Global Access`, `All Accounts`, or `No accounts assigned`).

#### Section 4: Interactive Reporting Structure (`_ReportingStructure`)
This is the core differentiator of the mobile module. It resolves supervisor and subordinate relationships dynamically in memory from the full directory roster:
1. **Explicit Linkages:**
   - Checked first: `reports_to_auth_user_id` / `manager_auth_user_id` and `direct_report_auth_user_ids`.
2. **Operational Role Hierarchy Fallback:**
   If explicit IDs are null, relationships are inferred based on operational tiers within the same group/account scope:
   - **Reports To Mapping:**
     - `head_admin` → `super_admin`
     - `encoder` → `head_admin`
     - `tl` (Team Leader) → `om` (Operations Manager)
     - `atl` (Assistant Team Leader) → `tl`
     - `hrco` (HR Coordinator) → `atl`
   - **Direct Reports Mapping:**
     - `super_admin` → `head_admin`
     - `head_admin` → `encoder`
     - `om` → `tl`
     - `tl` → `atl`
     - `atl` → `hrco`
3. **Scope Matching Rule (`_sharesScope`):**
   - Two users share scope if either has broad global access (`role_level >= 90`), OR if they intersect on at least one Group or Account.
4. **Interactive Navigation:**
   - Clicking any person under "Reports To" or "Direct Reports" immediately opens their profile sheet in the inspector (enabling one-touch navigation through the organizational hierarchy).

#### Section 5: Primary Communication Actions
- Full-width call-to-action buttons for Call, SMS, and Email.

---

## 3. Schema & Query Mapping

### 3.1 Backend Function: `public.get_team_directory`

The backend RPC is strictly defined in PostgreSQL with `SECURITY DEFINER` and `STABLE` properties, ensuring zero leakage of non-directory employee records:

```sql
CREATE OR REPLACE FUNCTION public.get_team_directory(
  p_search     TEXT  DEFAULT NULL,
  p_role       TEXT  DEFAULT NULL,
  p_group_id   UUID  DEFAULT NULL,
  p_account_id UUID  DEFAULT NULL
)
RETURNS TABLE (
  auth_user_id      UUID,
  full_name         TEXT,
  last_name         TEXT,
  first_name        TEXT,
  middle_name       TEXT,
  display_name      TEXT,
  mobile_number     TEXT,
  email             TEXT,
  role_name         TEXT,
  role_level        INT,
  group_names       TEXT[],
  account_names     TEXT[],
  directory_status  TEXT,
  profile_photo_url TEXT,
  full_name_search  TEXT
)
```

### 3.2 Security & RBAC Visibility Matrix

The RPC enforces server-side row-level filtering based on the caller's role level and group scope:

| Caller Role | Role Level | Directory Visibility Scope | Exclusions |
| :--- | :--- | :--- | :--- |
| **Super Admin** | 100 | All active directory users across all groups and accounts. | Inactive profiles, Viewers (`role_level <= 10`). |
| **Head Admin** | 90 | All active directory users across all groups and accounts. | Inactive profiles, Viewers (`role_level <= 10`). |
| **Operations Manager (OM)** | 70 | Peer OMs (`role_level = 70`) + lower-role users (`role_level < 70`) who share at least one assigned group in `user_scopes`. | Higher admin roles (Super Admin, Head Admin); users outside group scope. |
| **Recruitment Team** | 20 | All active directory users below Super Admin (`role_level < 100`). | Super Admin, Viewers (`role_level <= 10`). |
| **Scoped Operations**<br>(ATL, TL, HRCO, Encoder, Back Office, HR Personnel, Viewer) | 10 – 45 | Users who share at least one assigned group in `user_scopes`. | Users outside group scope, Viewers (`role_level <= 10`). |
| **Sub-Viewer / Unregistered** | < 10 | Access denied; returns empty result set. | All rows blocked. |

> [!NOTE]
> **Data Minimization Guarantee:**
> The function explicitly excludes sensitive HR, payroll, banking, government ID, salary, and deactivation details. The returned fields contain operational contact identity only.

---

### 3.3 Database Tables & References

```
┌─────────────────────────────────┐           ┌─────────────────────────────────┐
│              roles              │           │             groups              │
├─────────────────────────────────┤           ├─────────────────────────────────┤
│ id: uuid (PK)                   │           │ id: uuid (PK)                   │
│ role_name: text                 │           │ group_name: text                │
│ role_level: integer             │           │ group_code: text                │
└─────────────────────────────────┘           └─────────────────────────────────┘
                 ▲                                             ▲
                 │ role_id                                     │ group_id
┌────────────────┴────────────────┐           ┌────────────────┴────────────────┐
│          users_profile          │◄──────────┤           user_scopes           │
├─────────────────────────────────┤  user_id  ├─────────────────────────────────┤
│ id: uuid (PK)                   │           │ id: uuid (PK)                   │
│ auth_user_id: uuid (FK auth)    │           │ user_id: uuid (FK users_profile)│
│ full_name: text                 │           │ group_id: uuid (FK groups)      │
│ last_name: text                 │           │ account_id: uuid (FK accounts)  │
│ first_name: text                │           └────────────────┬────────────────┘
│ middle_name: text               │                            │ account_id
│ mobile_number: text             │                            ▼
│ email: text                     │           ┌─────────────────────────────────┐
│ directory_status: text          │           │            accounts             │
│ is_active: boolean              │           ├─────────────────────────────────┤
│ full_name_search: text          │           │ id: uuid (PK)                   │
└─────────────────────────────────┘           │ account_name: text              │
                                              │ group_id: uuid (FK groups)      │
                                              └─────────────────────────────────┘
```

---

## 4. Operational Context & Outlets/Roster Clarification

In the prompt objective, references were made to assigned store clusters, staff rosters, and coordinator directories:
1. **Plantilla Store Roster Separation:**
   - In the OHMployee domain, the direct store/outlet rosters and deployed field staff (e.g. promodisers, merchandisers) belong to the **Plantilla** (`v_web_plantilla_store_staffing`, `v_plantilla`) and **HR Emploc** modules, where each employee record tracks `coordinator` / `assigned_hrco_user_id`.
2. **Team Directory's Scope in Mobile:**
   - The Team Directory module is specifically designed as the **internal corporate operations and leadership directory** (finding and contacting OMs, TLs, ATLs, HRCOs, Encoders, Recruitment, and Admins).
   - Its scope displays the high-level **Group and Account jurisdictions** (e.g., "NORTH NCR • 14 Accounts") rather than pagination through individual retail grocery stores.
   - For web, a valuable enhancement is adding a direct deep-link from an HR Coordinator's profile drawer to their filtered roster in `/plantilla` or `/hr-emploc`!

---

## 5. Parity Gap Analysis

| Feature / Capability | Mobile (`OHMployee`) | Current Web (`ohmployee-web`) | Priority | Gap Description |
| :--- | :--- | :--- | :--- | :--- |
| **Dedicated Query Hook** | `TeamDirectoryService.fetchDirectory` | None | **P0** | Web lacks `useTeamDirectory` TanStack query hook calling `get_team_directory`. |
| **Search & Filtering** | Name, mobile, email search + dynamic role filter | None | **P0** | Web needs `AdminFilterBar` with debounced search and dynamic role/scope select. |
| **Directory Table / Grid** | Card list with status dot, role badge, scopes, contact links | Placeholder empty state | **P0** | Web needs a modern data table (`TeamDirectoryTable`) with name, avatar, role, scope, status, and contact actions. |
| **Detail Drawer** | Bottom sheet with full info, scope pills, reporting lines | None | **P0** | Web needs `TeamDirectoryDetailDrawer` powered by `DetailDrawer`. |
| **Hierarchical Reporting Lines** | `_ReportingStructure` dynamic calculation (Manager + Direct Reports) | None | **P1** | Web needs in-memory hierarchy calculator matching mobile's role and scope rules. |
| **One-Click Contact Actions** | `tel:`, `sms:`, `mailto:` | None | **P1** | Web needs clickable links and "Copy to clipboard" buttons for mobile/email. |
| **Summary Metrics Bar** | None (implicit count) | None | **P2** | Web standard: 4 KPI metric cards (Total Contacts, Available, Busy/Leave, Departments/Roles). |
| **Cross-Module Deep Links** | None | None | **P2** | Link HRCO/TL directly to `/plantilla?search=CoordinatorName` or `/hr-emploc`. |

---

## 6. Implementation Roadmap for Web Parity

### Step 1: Query Hook & Types Definition
- **File:** `src/lib/queries/team_directory.ts`
- **Contents:**
  - Define `TeamDirectoryUser` TypeScript interface matching the RPC return contract:
    - `authUserId`, `fullName`, `lastName`, `firstName`, `middleName`, `displayName`, `mobileNumber`, `email`, `roleName`, `roleLevel`, `groupNames`, `accountNames`, `directoryStatus`, `profilePhotoUrl`.
  - Implement helper functions for name formatting, avatar initials, role tint color, and scope summaries.
  - Implement hierarchy calculator `getReportingStructure(targetUser, allUsers)`.
  - Implement `useTeamDirectory({ search, role, groupId, accountId })` TanStack query calling `supabase.rpc("get_team_directory", ...)`.

### Step 2: Directory Table & Grid Component
- **File:** `src/components/team-directory/TeamDirectoryTable.tsx`
- **Features:**
  - Responsive table layout following the existing `UsersTable.tsx` design language.
  - Columns:
    1. **Name & Avatar:** User avatar with role tint, availability dot, display name (`Last, First M.`), and email snippet.
    2. **Role & Tier:** Badge with role level and title.
    3. **Assigned Scope:** Badge/pills for Groups and Accounts summary.
    4. **Status:** `StatusBadge` (`Available`, `Busy`, `On Leave`, `Offline`).
    5. **Quick Contact:** Copy phone/email buttons and quick mail link.
    6. **Actions:** "View Profile" button to trigger the detail drawer.

### Step 3: Detail Drawer Component
- **File:** `src/components/team-directory/TeamDirectoryDetailDrawer.tsx`
- **Features:**
  - Built with [`DetailDrawer`](file:///D:/Projects/ohmployee-web/src/components/shared/DetailDrawer.tsx).
  - Header with large avatar, role badge, and status indicator.
  - Contact Information card with copy-to-clipboard feedback.
  - Assigned Groups & Accounts lists.
  - **Reporting Structure Section:**
    - "Reports To" list showing managers with clickable rows to switch drawer context.
    - "Direct Reports" list showing team members with clickable rows.
  - Quick action to view workforce in Plantilla for HRCOs/coordinators.

### Step 4: Page Assembly
- **File:** `src/app/(dashboard)/team-directory/page.tsx`
- **Features:**
  - Replace `ModuleEmptyState` with full dashboard page.
  - Top header with title: "Team Directory" and subtitle: "Find and contact Ops, Recruitment, and Data Team colleagues".
  - Metric summary cards (Total Directory, Available, On Leave/Busy, Unique Roles).
  - `AdminFilterBar` with live search, role dropdown filter, and reset button.
  - Data table with loading skeletons, empty states, and selection handlers.
  - Integrated `TeamDirectoryDetailDrawer`.

---

## 7. Verification Checklist

- [ ] RPC `get_team_directory` responds correctly when invoked from web authenticated client.
- [ ] Role hierarchy and scope-based visibility rules match mobile behavior.
- [ ] Name formatting complies with UAT fix standard: `Last, First M.`.
- [ ] Status indicators accurately reflect the 4 canonical values (`Available`, `Busy`, `On Leave`, `Offline`).
- [ ] Reporting structure matches mobile's exact manager/subordinate traversal algorithm.
- [ ] Clicking a manager or direct report smoothly switches the detail drawer to that user.
- [ ] Mobile/Email action links and clipboard utilities operate smoothly on desktop web.
