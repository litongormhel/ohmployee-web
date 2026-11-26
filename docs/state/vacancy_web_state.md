# Vacancy Web State

## Scope

This document tracks the OHMployee Web Vacancy module architecture and current read-only frontend integration. It is intentionally limited to web layout, behavior, role/capability gates, and Supabase read contract requirements.

No fake data, CRUD flow, mutation, raw table query, or RLS bypass is introduced by this integration pass.

---

## Target Architecture

Vacancy Web should be a desktop-first admin workspace composed of:

1. KPI summary row for high-level workload state.
2. Status tabs for operational queue switching.
3. Filter/search bar for narrowing the active queue.
4. Dense vacancy table for scanning and comparison.
5. Detail drawer or right-side panel for selected vacancy context.
6. Applicant section placeholder inside the detail surface.
7. Capability-controlled action area for approved workflows.

The frontend remains presentation-only. Supabase remains authoritative for record visibility, workflow rules, RBAC, RLS, status transitions, applicant updates, closure requests, and headcount/vacancy creation.

## UI/UX Layout Spec

### Page Frame

- Use the existing dashboard shell and keep Vacancy inside the admin content area.
- Use a compact page header with module title, short operational subtitle, and any allowed primary action such as adding a vacancy/headcount.
- Avoid mobile card layouts, oversized marketing sections, or decorative dashboard blocks.

### KPI Summary Row

Display compact KPI tiles above the table from `get_web_vacancy_summary(...)`.

Recommended KPIs:

- Open vacancies.
- Vacancies with applicant.
- Pending approvals or review items.
- Backout/rejected count.
- Aging or oldest open vacancy, if Mobile business rules expose this safely.

KPI values must come from Supabase. Do not compute broad privileged totals from unscoped browser data.

### Status Tabs

Status tabs should remain a primary queue control, using backend-supported status keys.

Initial tab set:

- `open`
- `with_applicant`
- `rejected`
- `backout`

Future tabs may be added only when backed by Mobile-compatible status semantics.

### Filter/Search Bar

Add a dense toolbar above the table once the list contract supports filtering.

Recommended filters:

- Search by vacancy code, `position_title`, department, store/account/group, or applicant name when supported.
- Department/`position_title` filter.
- Scope filter if the user has multiple account or group scopes.
- Date/aging filter.
- Status is controlled by tabs, not duplicated as a separate primary filter.

Filters should be reflected in query parameters only if route persistence is explicitly desired in the implementation pass.

### Dense Vacancy Table

The table should optimize for scanning and operational decisions.

Recommended columns:

- Vacancy code.
- `position_title`.
- Department or business unit.
- Account/group/location, depending on Mobile scope terms.
- Status.
- Applicant summary.
- Requested/created date.
- Aging.
- Owner/requester or approver, if available and web-safe.
- Last activity.
- Row-level action affordance only when capabilities allow.
- Headcount (HC) column displays official hired capacity (`hc_filled / hc_total`, e.g. `0/3`) per ADR-001 Rule 2, accompanied by a dynamic in-process indicator when candidate sourcing is active (`● N/Total in process (X open)`), providing immediate clarity on pipeline progression without misrepresenting un-deployed candidates as official active Plantilla employees.

The table supports loading, empty, retryable error, blocked/read-denied, selected-row, and paginated states. Empty states are real no-record states, not mocked data.

### Detail Modal UX Structure (Multi-Tab Modal & Comprehensive Activity History)

The Vacancy Detail Modal (`VacancyDetailDrawer.tsx`, rendered via centered `Modal` with `maxWidthClass="max-w-3xl"`) is a desktop-first, admin-oriented command center surface. When a vacancy is selected from the dense table, the modal opens with an always-visible top summary and 4 segmented navigation tabs (`SegmentedTabs`):

1. **Compact Header & Always-Visible Top Strip**:
   - **Header**: Prominent monospaced `VCode` badge, status badge (`Open`, `Pipeline`, `Pending Clearance`, `Hired`), primary `Position Title`, `Account / Group / Store` hierarchy subtitle, and top-right `headerActions` (`Adjust Quota`, `HC Adjustment`, `Request Closure`, `Withdraw Closure`). `Adjust Quota` (`ReviseHeadcountQuotaModal`) is authorized for Data Team, Super Admin, and Ops roles (`OM`, `TL`, `ATL`, `HRCO`) via `canReviseHeadcountQuota` and `public.revise_vcode_headcount_quota`. All action buttons adhere to high-contrast brand tokens (`bg-brand-button hover:bg-brand-button-hover text-white`).
   - **4-Column KPI Strip**: Displays `Hired (hc_filled/hc_total)`, `Pipeline (activeApplicantCount)`, `Avail (availableSlots)`, and color-coded `Aging (agingDays + bucket)` (`<= 7d` Green/Emerald, `8–15d` Yellow/Amber, `> 15d` Red/Rose). Numbers render as whole integers when exact and 1–2 decimal places only when fractional (`0.5`, `0.33`).
2. **Tab 1: Pipeline & Applicants (`pipeline`)**:
   - Header titled `Applicant` with active and onboarded counters.
   - Displays individual candidate cards showing candidate name with an inline edit icon (`<Edit3 />`) directly beside the name, tagged role (for multi-position stores), current stage badge, color-coded aging pill, contact number, recruiter/onboard date, and pipeline stage actions (`Update Stage / Backout`, `Mark Hired`), plus the PII Guard notice.
3. **Tab 2: Vacancy Details (`details`)**:
   - Displays Source, Vacancy Type, Urgency Level, Province/City, Employment Type, Assigned Roving Stores (with `CGCode` and `Anchor` store badges), inline `Vacant Since` date editor, `Target Fill Date`, `Date Created`, SLA breach warning (> 60 days), and Headcount & Approvals Context.
4. **Tab 3: Ownership & Team (`ownership`)**:
   - Displays structured assignment cards for `HRCO Assignee`, `Recruiter`, `Operations Manager (OM)`, `Team Leader (TL)`, `Assistant Team Leader (ATL)`, `Triggered By` / `Deployed By`, `Reliever on Duty`, and `HRCO Remarks`.
5. **Tab 4: Activity History (`history`) — Clean Chronological Timeline**:
   - Powered by `public.get_vacancy_activity_timeline(p_vacancy_id)` inside `public.get_web_vacancy_detail(p_vacancy_id)` (`20262606000174` & `20262606000176`).
   - Aggregates and deduplicates chronological lifecycle events across `vacancies`, `applicants`, `applicant_status_history`, `applicant_profile_edit_history`, `vacancy_closure_requests`, `hr_emploc`, and meaningful field-level `audit_logs` diffs.
   - Renders a clean, simple vertical timeline (without redundant header labels or heavy nested card borders) showing event title, timestamp, clean description (with whole-number / 1–2 decimal HC formatting), and `By <Actor Name>`.

### Drawer Interaction Behavior

- **Open State**:
  - Instantly triggered by clicking the action "Eye" icon in the dense vacancy table row.
  - Supports standard keyboard triggers: arrow keys to move row selection, and pressing `Enter` to open the drawer.
- **Close State**:
  - Dismissed by clicking the top-right close icon, clicking outside the panel area (backdrop overlay), or pressing the `Escape` key.
  - Instantly clears row selection state.
- **Deep-Linking & Global Search Integration**:
  - The page fully integrates with URL query routing parameters (`?search=VCODE`, `?vcode=VCODE`, `?id=UUID`, `?tab=STATUS`).
  - Navigating from Global Search (or direct link) automatically populates `searchDraft` and `search`, filters the table roster to the target requisition, synchronizes the active tab, and immediately auto-opens `VacancyDetailDrawer` via `selectedVacancyId` (or via exact VCode match in live rows).
  - Dismissing the drawer preserves the search and filter context without re-opening.
- **Loading State**:
  - Displays consistent, highly-structured skeleton loaders for the entire panel layout to prevent layout shifts during fetches.
- **Blocked/Not-Found State**:
  - **Access Denied**: If a user attempts to select a vacancy they are not authorized to view due to RLS/scope limits, a locked shield icon is shown indicating access is denied.
  - **Not Found**: If the record has been closed or deleted, a "Record Not Found" panel with a refresh trigger is displayed.

## Web-Specific Behavior Mirroring Mobile Rules

- Web should mirror Mobile vacancy business rules, status names, allowed transitions, scope boundaries, and RBAC semantics.
- Web may present denser controls and tables, but it must not introduce new workflow states or looser transitions.
- Any status transition, applicant update, approval, closure request, or headcount/vacancy creation must call a Supabase RPC that already validates the authenticated user, scope, capability, and record state.
- Web list and detail reads must be scoped by backend RLS/RPC contracts using the current authenticated user; the frontend should not pass profile, role, group, or account ids as authority.
- Frontend capability checks are for presentation and ergonomics only.

## Supabase Data Contract Requirements

### List Contract

Frontend implementation now expects this canonical browser contract:

```ts
supabase.rpc("list_web_vacancies", {
  p_status,
  p_account_id,
  p_group_id,
  p_aging_bucket,
  p_urgency,
  p_search,
  p_vacant_from,
  p_vacant_to,
  p_sort_by: "aging_days",
  p_sort_dir: "desc",
  p_limit,
  p_offset,
});
```

The current UI reads `row_capabilities`, `total_count`, `aging_bucket`, and `pipeline_status` directly from the returned rows. Permission/RLS/RPC authorization failures render a blocked state; other failures render a retryable error state.

Deployed canonical shape:

```sql
select *
from public.list_web_vacancies(
  p_status := 'Open',
  p_account_id := null,
  p_group_id := null,
  p_position := null,
  p_urgency := null,
  p_aging_bucket := null,
  p_search := null,
  p_vacant_from := null,
  p_vacant_to := null,
  p_sort_by := 'aging_days',
  p_sort_dir := 'desc',
  p_limit := 50,
  p_offset := 0
);
```

The contract should:

- Derive caller identity from `auth.uid()`.
- Apply existing Mobile RBAC and RLS scope.
- Accept only filter/search/pagination arguments, not caller-controlled role/profile/scope arguments.
- Return only web-safe list fields.
- Include record-level capability hints if needed for row actions.
- Support stable ordering for pagination.
- Return `total_count` as a windowed count for the current filtered result, or document that the UI must call the summary/count RPC for counts.
- Enforce a safe max limit, recommended `100`, with a default of `50`.

Recommended list row fields:

| Field | Notes |
| --- | --- |
| `vacancy_id` | Internal id for selection and detail lookup. |
| `vcode` | Vacancy code shown in the table. |
| `account_id` | Internal id for scoped filters only; omit if not needed by UI. |
| `account_name` | Existing `vw_vacancy_list.account`. |
| `group_id` | Internal id for scoped filters only; omit if not needed by UI. |
| `group_name` | Web-safe group label. |
| `store_id` | Internal id for selection/filtering only. |
| `store_name` | Store/branch label, using Mobile's existing store fields. |
| `position_title` | Position/title label. |
| `employment_type` | Mobile-compatible employment/deployment type label. |
| `vacancy_status` | Raw vacancy status from Mobile semantics, without inventing new statuses. |
| `pipeline_status` | Derived applicant occupancy status: `Open` or `Pipeline`, based on canonical active applicant predicate. |
| `derived_status` | Existing Mobile-derived queue status where needed for tab parity. |
| `active_applicant_count` | Count only; no applicant PII in list. |
| `confirmed_onboard_count` | Count only, used with `has_recent_hire` if web chooses a hired visibility queue later. |
| `has_recent_hire` | Existing Mobile visibility flag; not a slot occupancy signal. |
| `has_pending_closure` | Existing Mobile closure queue signal. |
| `closure_request_status` | Web-safe closure status label when present. |
| `vacant_date` | Date used for aging. |
| `aging_days` | Backend-computed, using Mobile/CENCOM semantics. Advance/future vacancy should be `null` or `0` only if explicitly documented. |
| `aging_bucket` | Canonical bucket: `advance`, `1_15`, `16_30`, `31_60`, `61_120`, `gt121`. Prefer reusing `fn_cencom_td_aging_bucket` or equivalent logic. |
| `target_fill_date` | Existing target fill date. |
| `urgency_level` | Existing Mobile urgency value, such as `High`, `Medium`, or `Normal`; do not invent new urgency values. |
| `urgency_tier` | Optional web/CENCOM-derived operational tier if reused safely: `advance`, `normal`, `elevated`, `critical`, `immediate`. |
| `penalty_exposure` | Optional nullable JSON/number only if an existing authoritative SLA/penalty source is safe; otherwise return `null`. |
| `hrco_user_id` | Optional internal assignment id. |
| `hrco_name` | Live HRCO name only when the user is still active and still has HRCO role, matching the existing live lookup fix. |
| `last_activity_at` | Optional operational recency field. |
| `row_capabilities` | JSONB presentation hints such as `can_view_detail`, `can_update_applicant_status`, `can_request_closure`; action RPCs must recheck authority. |
| `total_count` | Optional repeated filtered count for pagination. |

The list must not return employee/Plantilla-sensitive fields, applicant contact numbers, raw triggered/requested user ids, source Plantilla ids, service-role-only data, or broad unscoped totals.

### Filters, Search, Sorting, And Pagination

Supported input contract:

| Input | Type | Notes |
| --- | --- | --- |
| `p_status` | `text null` | Frontend maps tabs to backend `derived_status`: `open`→`Open`, `with_applicant`→`Pipeline`, `rejected`/`backout`→`null` because terminal applicant-status filtering is not deployed. |
| `p_account_id` | `uuid null` | Optional narrowing within caller scope. Invalid UI values are dropped before the RPC call. |
| `p_group_id` | `uuid null` | Optional narrowing within caller scope. Invalid UI values are dropped before the RPC call. |
| `p_position` | `text null` | Deployed backend parameter; not currently exposed in the page UI. |
| `p_urgency` | `text null` | Existing values only: `High`, `Medium`, `Normal`. |
| `p_aging_bucket` | `text null` | `advance`, `1_15`, `16_30`, `31_60`, `61_120`, `gt121`. |
| `p_search` | `text null` | Case-insensitive search across `vcode`, account, group, store/branch, area/city, and `position_title`. Do not search applicant names in the list unless explicitly approved. |
| `p_vacant_from` / `p_vacant_to` | `date null` | Date range over `vacant_date`. Invalid UI values are dropped before the RPC call. |
| `p_sort_by` | `text` | Allowlist only. Current page sends fixed `aging_days`. |
| `p_sort_dir` | `text` | `asc` or `desc`, default `desc`. |
| `p_limit` | `integer` | Default `50`, max `100`. |
| `p_offset` | `integer` | Default `0`, never negative. |

Pagination should use offset/limit for the first Web integration because it is simple for admin tables and works with a filtered count. Use deterministic secondary ordering, such as `ORDER BY <allowlisted sort>, vcode, vacancy_id`, so rows do not jump between pages. Consider keyset pagination only if the list grows large enough to make deep offsets expensive.

### Detail Contract Recommendation

A specialized read-only detail contract is required to populate the rich operational layout of the Vacancy Detail Drawer.

#### Recommended RPC Signature

```sql
select *
from public.get_web_vacancy_detail(p_vacancy_id := '93cfa3cc-4e5a-4712-a1f9-58b29f0e1fcc'::uuid);
```

#### Access Control & Scoped Authority Boundaries
- **Caller Identity**: Derived exclusively from `auth.uid()`. Under no circumstances should `auth_user_id`, `profile_id`, `role_key`, or scoped ID parameters be accepted as caller arguments.
- **Grants**: Execution is strictly granted to the `authenticated` role. Access is revoked from `PUBLIC` and `anon`.
- **RBAC & Scope Filters**: Enforces matching Mobile RBAC parameters:
  - **Super Admin / Head Admin**: Broad read access over all active/closed vacancies.
  - **Operations Manager (OM) / ATL / TL / HRCO / Recruitment**: Read access is strictly restricted to vacancies within their allowed accounts (`get_my_allowed_accounts()`) and groups (`user_scopes`).
  - **Viewer**: Scoped read-only access.
  - **Disabled/Inactive Profiles**: Instantly denied (fails closed returning empty/error status).
- **RLS Preservations**: Calls the view invokers under the user's current security context (`vw_vacancy_detail`) to respect database-level RLS policies.

#### Field Mappings & Taxonomy (List vs. Detail)

To maintain database efficiency and minimize payload size, fields are strictly segregated between the list contract and the detail contract:

| Field | List Only | Detail Only | Both | Notes / Business Rules |
| --- | :---: | :---: | :---: | --- |
| `total_count` | `X` | | | Result count windowing for list pagination. |
| `vacancy_id` | | | `X` | Internal record primary key. |
| `vcode` | | | `X` | Human-readable vacancy code. |
| `account_name` | | | `X` | Client account / regional name. |
| `group_name` | | | `X` | Sub-group scope assignment. |
| `store_name` | | | `X` | Store/branch location. |
| `position_title` | | | `X` | Position mapping name. |
| `employment_type` | | | `X` | Deployment model label. |
| `vacancy_status` | | | `X` | Baseline status enum. |
| `pipeline_status` | | | `X` | Slot occupancy state (Open/Pipeline). |
| `derived_status` | | | `X` | Derived queue state. |
| `active_applicant_count` | | | `X` | Total counts for candidate summary. |
| `confirmed_onboard_count` | | | `X` | Total counts for onboard/hire summary. |
| `has_recent_hire` | | | `X` | Hired queue visibility indicator. |
| `has_pending_closure` | | | `X` | Closure request marker. |
| `closure_request_status`| | | `X` | Pending closure queue tracking. |
| `vacant_date` | | | `X` | Vacant slot baseline date. |
| `aging_days` | | | `X` | Days active (backend-computed). |
| `aging_bucket` | | | `X` | SLA aging bucket. |
| `target_fill_date` | | | `X` | Target recruitment deadline. |
| `urgency_level` | | | `X` | Existing urgency values. |
| `hrco_name` | | | `X` | Live HRCO assignee profile label. |
| `last_activity_at` | | | `X` | Recency tracking index. |
| `row_capabilities` | | | `X` | Action hint presentation mapping (`jsonb`). |
| `requested_by_id` | | `X` | | Audit metadata: requester UUID. |
| `requested_by_name` | | `X` | | Audit metadata: requester profile name. |
| `approved_by_id` | | `X` | | Audit metadata: approver UUID. |
| `approved_by_name` | | `X` | | Audit metadata: approver profile name. |
| `approved_at` | | `X` | | Audit metadata: approval timestamp. |
| `headcount_request_id` | | `X` | | Parent headcount request reference link. |
| `vacancy_reason` | | `X` | | Stated origin (Replacement vs. Expansion). |
| `job_description` | | `X` | | Compact summary of roles/qualifications. |
| `closure_requested_at` | | `X` | | Timestamp of closure submission. |
| `closure_requested_by` | | `X` | | User profile who requested closure. |
| `closure_reason` | | `X` | | Stated reason for closure cancellation. |
| `active_applicants_list` | | `X` | | JSONB array of active candidates: `[{ "applicant_id": uuid, "display_name": text, "status_label": text, "updated_at": timestamp }]`. No email or phone contact details exposed. |
| `activity_history` | | `X` | | JSONB array of structural audit events for the timeline component. |

### KPI Contract

KPI totals should use a scoped aggregate RPC or a list RPC metadata payload. The browser should not compute privileged totals from records it has not been authorized to fetch.

Recommended shape:

```sql
select *
from public.get_web_vacancy_summary(
  p_status := null,
  p_account_id := null,
  p_group_id := null,
  p_position := null,
  p_urgency := null,
  p_search := null,
  p_vacant_from := null,
  p_vacant_to := null
);
```

Recommended summary fields:

| Field | Notes |
| --- | --- |
| `open_count` | `derived_status = 'Open'` and no pending closure. |
| `pipeline_count` | Canonical active applicant count > 0 and no pending closure. |
| `with_applicant_count` | Alias of `pipeline_count` for current web tab wording. |
| `hired_visible_count` | `has_recent_hire = true`, if web later exposes the Mobile Hired visibility queue. |
| `closure_pending_count` | `has_pending_closure = true` or closure status pending. |
| `rejected_count` | Count of vacancies/applicants with rejected terminal applicant status only if Mobile exposes this queue safely; otherwise omit or return `0` with documentation. |
| `backout_count` | Count of vacancies/applicants with backout terminal applicant status only if Mobile exposes this queue safely; otherwise omit or return `0` with documentation. |
| `oldest_aging_days` | Max scoped `aging_days` excluding advance vacancies. |
| `aging_bucket_counts` | JSON object keyed by canonical aging bucket. |
| `urgency_counts` | JSON object keyed by existing urgency values or derived urgency tier if approved. |
| `total_filtered_count` | Optional total for the same filters/search. |

If rejected/backout queues require applicant terminal-status aggregation, compute them from `applicants` using the same scope-filtered vacancy base. Do not infer new vacancy statuses.

### Action RPCs

Web should reuse Mobile action RPCs where they already exist and match the same business workflow.

Required action categories:

- Approve vacancy or related vacancy workflow item.
- Update applicant status.
- Request vacancy closure.
- Add vacancy/headcount if the Mobile rule set allows the user's role/scope to do so.

If Mobile does not already expose web-safe RPCs for these actions, the backend implementation should add tightly scoped action RPCs that call the same underlying business rules rather than duplicating logic in the browser.

## Role And Capability Gates

Capability keys should come from `get_web_current_user_context().module_capabilities.vacancy` or from record-level capability hints returned by Vacancy RPCs.

Recommended module-level gates:

| Gate | Purpose |
| --- | --- |
| `vacancy.view` | Can see the Vacancy module and read scoped vacancy lists/details. |
| `vacancy.approve` | Can see approval controls when record state also permits approval. |
| `vacancy.update_applicant_status` | Can update applicant workflow status when record and applicant state allow it. |
| `vacancy.request_closure` | Can request closure when record state permits it. |
| `vacancy.add` | Can add vacancy/headcount if Mobile business rules allow it. |

Do not hardcode role names into Vacancy components. Use backend capability keys for UI visibility, and rely on Supabase action RPCs for final authorization.

## Security And Scope Recommendation

Use RPCs as the canonical Web contract:

- `public.list_web_vacancies(...)`
- `public.get_web_vacancy_summary(...)`
- later `public.get_web_vacancy_detail(p_vacancy_id uuid)`

Recommended implementation style:

- Use `SECURITY DEFINER` only if needed to safely join profile/RBAC/scope tables and Mobile vacancy views. If used, lock `search_path` to `public`, derive caller from `auth.uid()`, grant only to `authenticated`, revoke from `PUBLIC` and `anon`, and keep the returned projection narrow.
- Back the RPCs with an internal `security_invoker = true` view, for example `public.v_web_vacancy_base`, only if that view can be safely selected under the caller's RLS. The helper view should not be granted directly to the browser unless it is intentionally part of the contract.
- Do not pass profile id, role, group scope, or account scope as authority arguments. Account/group/store/position filter ids are narrowing filters only.
- Super Admin and Head Admin should receive broad access through existing `i_have_full_access()` / role level >= 90 semantics.
- OM, ATL, TL, HRCO, Recruitment, and Viewer should receive read rows only inside existing Mobile account/group scope. Viewer remains read-only and must not receive mutation capabilities.
- Recruitment scoped read access should be limited to the vacancy/applicant surfaces Mobile already permits; do not broaden into employee/Plantilla fields.
- Use existing account/group scope helpers and/or `user_scopes`; prefer account ids internally when possible, but remain compatible with existing Mobile helpers that return account names.
- Record-level capability hints are display hints only. Every future action RPC must re-derive caller identity, re-check role/scope/capability, and validate the current record state.

---

## Multi-Slot VCode Onboarding & Slot-Resolution Discipline (`ohm#fix-multi-slot-vcode-onboarding-collision`)

When confirming an applicant onboard (`Confirm Onboarding / Mark Hired` via `confirm_applicant_onboard` and `fn_sync_slot_to_hr_processing`):
1. **Unowned Slot Resolution Invariant**: On multi-headcount / multi-slot VCodes, slot selection must never execute an unconstrained `LIMIT 1` query. Slot resolution must:
   - Honor `p_slot_id` (or `applicants.slot_id`) if already bound.
   - If resolving an open slot, select only from slots with `slot_status IN ('pipeline', 'open')`, `closed_at IS NULL`, and `current_occupant_plantilla_id IS NULL`.
   - Strictly exclude any slot that is already owned by an active record in `hr_emploc` (`NOT EXISTS (SELECT 1 FROM hr_emploc WHERE slot_id = plantilla_slots.id AND deleted_at IS NULL)`).
   - Order candidate slots by `pipeline` first (already reserved for applicant), followed by `slot_ordinal ASC`.
2. **Coherent Linkage**: `confirm_applicant_onboard` synchronizes the resolved slot ID to both `hr_emploc.slot_id` and `applicants.slot_id`, permanently preventing duplicate assignment collisions against `uq_hr_emploc_one_active_per_slot`.

---

## Option A Multi-Slot & Multi-Position Granularity Standard (`ohm#multi-slot-multi-position-granularity`)

In Plantilla Tab 3 (Vacancy), every physical slot in a multi-slot store requisition (`required_headcount > 1`) strictly renders as a distinct, solo row (`1 Row = 1 Physical Slot / Tao`):
1. **Anti-Table Jitter Lock (Zero-Collapse Rule)**: Unallocated slots with zero active applicants are NEVER merged or collapsed into a single summary store row. Prevents layout jumping, pagination shifting, and preserves 100% parity between rendered table rows and the tab badge (`Vacancy X (Y slots)`).
2. **Multi-Position Independence**: When multiple positions exist under the same store/VCode (e.g. 2 Cashiers + 1 Bundler), each slot independently reflects its physical position (`plantilla_slots.position` or `hr_emploc.position`), allowing precise position filtering.
3. **Sequential Slot Ordinal Identity**: Each slot row displays its distinct sequential slot indicator (`Slot 1`, `Slot 2`, `Slot 3`).

---

## RBAC Dynamic Capability Enforcement & Closure Review RPC (`ohm#fix-rbac-dynamic-overrides-and-vacancy-closure`)

1. **Dormant `vacancy.create` and `vacancy.edit` Deprecation**:
   - `vacancy.create` and `vacancy.edit` were orphaned rules seeded in early RBAC migrations. Vacancies in OHMployee strictly originate through Headcount Requests, Plantilla Attrition Backfills, or Batch Imports per ADR-001/002. Core attributes are derived from the underlying Plantilla slot; direct vacancy editing does not exist.
   - Permanently deleted `('vacancy', 'vacancy', 'create')` (migration 168) and `('vacancy', 'vacancy', 'edit')` (migration 169) from `role_permission_definitions`, `role_permission_matrix`, and `role_permission_overrides`, reducing Vacancy RBAC rules from 16 to 14.
2. **Dynamic Effective Permissions Integration**:
   - `get_web_current_user_context()` joins `role_permission_overrides` against `role_permission_matrix` with Super Admin immunity (`role_name = 'Super Admin' -> true`), ensuring custom toggles in `/rbac` (e.g. revoking `vacancy.approve_closure` on Head Admin) immediately take effect.
   - `normalizeCapabilities` in `src/lib/auth.ts` extracts canonical string keys (`${resource_key}.${action_key}` and `${action_key}`) so frontend components receive populated capability arrays.
   - `canReviewVacancyClosures`, `canRequestVacancyClosure`, `canAddApplicant`, and `canPerformDrawerAction` in `src/lib/rbac.ts` consult `currentUser.moduleCapabilities` first before falling back to static role levels.
3. **Closure Review RPC & RLS Guard**:
   - Gated review mutations through `public.review_vacancy_closure_request` and `public.approve_all_vacancy_closure_requests`, checking `public.fn_current_user_can('vacancy', 'vacancy', 'approve_closure')`.
   - Re-asserted `closure_req_update_encoder_plus` RLS policy on `public.vacancy_closure_requests` requiring `fn_current_user_can('vacancy', 'vacancy', 'approve_closure')` for updates.
4. **Historical Closure PostgREST Join Fix**:
   - Fixed `fetchVacancyClosureRequests` (`src/lib/queries/requests.ts`) by applying `vacancies:vacancies!vacancy_vcode!left` (explicit LEFT JOIN) so closed/archived vacancies do not drop approved closure records in `Approvals Center -> Vacancy Closures` (`/approvals?tab=vacancy_closures`).
   - Added descriptive link in `/vacancy?status=closure` queue banner pointing directly to the Approvals Center historical log.

---

## Multi-Position Vacancy Intake & Candidate Disambiguation (`ohm#multi-position-vacancy-applicant-intake`)

Stores in OHMployee frequently require multiple positions under a single store requisition (e.g. 2 Merchandisers + 1 Salesman).
Per ADR-002 Invariant 2 (`1 Store = 1 VCode`), multiple positions are normalized as line items in `public.vacancy_requirements` under that single VCode.

1. **Intake Position Selection Parity**:
   - In `AddApplicantModal`, requirements are queried via `useVacancyRequirements(vcode)`.
   - **Single Position**: If exactly 1 requirement exists, or only 1 non-full requirement remains, it is automatically assigned without modal friction.
   - **Multiple Positions**: If 2+ positions exist under the store, the modal surfaces a dedicated position selector displaying position title, slot availability badge (`N Slots` / `Full`), and hired/pipeline counters (`Hired: N/Needed • Pipeline: X`). Full positions are disabled. Submission is blocked until a position is selected.
   - `endorseApplicant` persists `vacancy_requirement_id` directly to `public.applicants`.
2. **Pipeline Candidate Disambiguation**:
   - `pipelineApplicants` and `fetchVacancyDetail` resolve candidate positions dynamically via `vacancy_requirements` + `positions`, displaying the specific tagged role (`Merchandiser` vs `Salesman`) instead of the general vacancy card header title.
3. **Mark Hired / Onboarding Linkage**:
   - `MarkHiredModal` receives `vacancyRequirementId` from the candidate. For legacy candidates lacking an intake tag, it offers a fallback requirement selector so `confirm_applicant_onboard(p_vacancy_requirement_id)` is invoked with the specific position, preventing candidate misallocation.

---

## Clean Open Requisition & Zero-Applicant Avail Invariant (`ohm#clean-open-vacancy-and-backout-invariants`)

Resolves the 1/3 capacity progression, Avail metric invariant, and clean-slate return upon candidate backout across Web and Mobile:

1. **Avail Metric (Zero-Applicant Invariant)**:
   - `Avail` strictly represents open unallocated slots with zero active applicants (`Avail = Open or walang applicant`):
     $$\text{Avail} = \max(0, \text{hc\_needed} - \text{hired\_count} - \text{pipeline\_count} - \text{hr\_processing\_count})$$
   - Adding an applicant to screening immediately reduces `Avail` by 1. For a 1/3 requisition (1 hired, 3 needed):
     - 0 active pipeline applicants $\rightarrow$ `Avail = 2` (renders in Open tab with 2 Available)
     - 1 active pipeline applicant $\rightarrow$ `Avail = 1` (renders in Open tab with 1 Available)
     - 2 active pipeline applicants $\rightarrow$ `Avail = 0` (capacity exhausted; leaves Open tab)
2. **Strict Position Intake Lock**:
   - `AddApplicantModal` and `endorseApplicant` prevent adding another applicant to a position or requisition that is `Full` (`availableSlots <= 0`), preventing over-endorsement until an active candidate backs out.
3. **Clean Return to Open Tab on Backout (Anti-Ghost Applicant Lock)**:
   - When a candidate backs out or fails, they route to the **Failed / Backout Tab** (`p_status = 'Failed'`).
   - The store requisition returns to the **Open Tab** clean with zero applicants (`clean malinis at walang nakalagay na applicant`). Ghost applicants (such as `CRUZ, JAMES PAUL` on `TEST011`) are permanently prevented by:
     - Automated trigger `trg_applicants_terminal_archival` on `public.applicants` auto-archiving (`is_archived = true`, `archived_at = now()`) and decoupling `slot_id = NULL` on terminal status transitions (`backout`, `failed`, `rejected`, `did_not_report`, `withdrew`).
     - Surgical filtering in `public.get_web_vacancy_detail` excluding terminal dropouts from `pipeline_summary`.
     - Frontend queries and capacity calculators strictly filtering out terminal candidates across all case variants.

---

## Confirmed Onboard Candidates & Strict Zero-Capacity Open Invariant (`ohm#fix-vacancy-open-onboard-dual-existence-and-hr-processing-sync`)

Enforces ADR-001 Rule 4 and ADR-002 capacity rules preventing requisitions whose candidates are confirmed onboard (active in HR Emploc) from dual-existing in the Vacancy Open tab:

1. **Dual Existence Prevention (ADR Invariant)**:
   - A single-slot vacancy (`required_headcount = 1`) cannot exist across both the Vacancy Open tab and HR Emploc.
   - When an applicant reaches `Confirmed Onboard`, they enter HR Emploc processing (`hr_processing_count >= 1`).
   - Once all required slots are occupied by Confirmed Onboard candidates or active Plantilla personnel (`(confirmed_onboard_count + active_plantilla_count) >= required_headcount`), remaining open capacity is `0`. The vacancy evaluates to `'Hired'` (`derived_status = 'Hired'`) and is strictly excluded from Open and Pipeline tabs.
2. **Strict Capacity Filter (`list_web_vacancies` & `get_web_vacancy_summary`)**:
   - Removed the `OR lower(s.pipeline_status) = 'open'` bypass predicate.
   - Requisitions appear in the Open tab if and only if open capacity exists:
     $$\text{Remaining Open Capacity} = (\text{hc\_total} - \text{hc\_filled} - \text{hr\_processing\_count} - \text{active\_applicant\_count}) > 0$$
3. **Multi-Headcount Requisitions (`required_headcount > 1`)**:
   - Requisitions requiring multiple headcount (e.g., `ACT-G5-008` with `hc_total = 3`, `hc_filled = 1`, `hr_processing_count = 1`) retain accurate open capacity (`remaining = 1`) and legitimately remain in the Open tab to recruit for the remaining open slot.
4. **Roving and Pool Slot Synchronization**:
   - `slot_stats` in `vw_vacancy_list` removes the `is_roving = false` exclusion, ensuring roving slots in `hr_processing` are accurately counted.
   - `hr_emploc_stats` queries active onboarding records directly from `public.hr_emploc`, guaranteeing that pool vacancies with unpopulated slot foreign keys are safely counted in `hr_processing_count`.

## Seed Vacancy Closed Slot Reason & Fix Closure Approval (`ohm#fix-vacancy-closure-slot-reason-fkey-violation`)

Root-caused and resolved foreign key constraint violation on `plantilla_slots_closure_reason_fkey` during Vacancy Closure Approval ([IMG_4427.jpg], [20262606000179_seed_vacancy_closed_slot_reason_and_fix_closure_approval.sql](file:///D:/Projects/ohmployee-web/supabase/migrations/20262606000179_seed_vacancy_closed_slot_reason_and_fix_closure_approval.sql)):

1. **Root Cause Forensic Diagnosis (`IMG_4427.jpg`)**:
   - In `VacancyClosureDataTable.tsx` (`handleConfirmApprove`), approving a vacancy closure request triggers `review_vacancy_closure_request`, which updates `public.vacancy_closure_requests SET status = 'Approved'`.
   - This fires database trigger `on_closure_reviewed` -> `public.handle_closure_approval()`.
   - In `handle_closure_approval()`, remaining open/pipeline slots in `public.plantilla_slots` are updated to `slot_status = 'closed'` with `closure_reason_code` determined by a CASE statement: if the reason is not store closure (`LOWER(reason) LIKE '%store closed%'`), it falls back to `ELSE 'VACANCY_CLOSED'`.
   - However, `plantilla_slots.closure_reason_code` has a strict foreign key constraint `plantilla_slots_closure_reason_fkey` referencing `public.slot_reason_codes(code)`.
   - Because code `'VACANCY_CLOSED'` was never seeded into `public.slot_reason_codes`, any closure request with operational or non-store-closure reasons (such as `"Operational Restructuring"`, `"Headcount Allocation Cancelled by Client"`, etc.) threw SQLSTATE `23503: insert or update on table "plantilla_slots" violates foreign key constraint "plantilla_slots_closure_reason_fkey"`.
2. **Database Migration & Hardening**:
   - **Master Lookup Seed**: Seeded `'VACANCY_CLOSED'` (`'Vacancy Closed'`, `'Slot closed and decommissioned due to approved vacancy closure request.'`, `is_active = true`, `sort_order = 92`) into `public.slot_reason_codes`.
   - **RPC Hardening**: Surgically updated `public.handle_closure_approval()` to set `closed_at = NOW()`, resolve `closed_by` from `public.users_profile` via `auth.uid()` or reviewer name, map headcount reduction reasons to `'HC_REDUCTION'`, and map all remaining approved closures to `'VACANCY_CLOSED'`.
3. **Verification**:
   - Migration applied to Staging (`qqiiznmqxfoamqytjica`), verified `pg_get_functiondef` live matching, tested approving pending requisition closure `a2741731-0042-42eb-b523-748dee421a7a` (`TEST005`) with 100% success (all 3 slots closed with `VACANCY_CLOSED`, vacancy archived and marked `Closed`), passed all 264 unit tests (`npm test`), 0 ESLint errors/warnings (`npm run lint`), 0 secret leaks (`check:secrets`), 0 SQL contract violations (`check:sql`), and clean Turbopack build (`npm run build`).

## Partial / Staggered Roving Coverage Group Store Onboarding (`ohm#partial-roving-coverage-store-onboarding-and-agawa-backfill`)

Implements 100% Web-Mobile workflow parity for partial / per-store onboarding of Roving Coverage Group candidates ([20262606000188_partial_roving_coverage_store_onboarding_and_agawa_backfill.sql](file:///D:/Projects/ohmployee-web/supabase/migrations/20262606000188_partial_roving_coverage_store_onboarding_and_agawa_backfill.sql), [MarkHiredModal.tsx](file:///D:/Projects/ohmployee-web/src/components/vacancy/MarkHiredModal.tsx)):

1. **Store Footprint Selection Checklist (`MarkHiredModal.tsx`)**:
   - When opening **Confirm Onboarding / Mark Hired** for an applicant belonging to a multi-store Coverage Group (`CG-*` or any store linked in `public.coverage_group_stores`), the modal renders the **Approve Onboarding Store Footprint** checklist card (matching Mobile's `_CoverageOnboardingStoreSelectionSheet`).
   - Checked store(s) transition immediately to `Confirmed Onboard` (`Onboard Now → HR Emploc` or `Fast-Track → Active Plantilla`), while unchecked store(s) remain in the Vacancy & Plantilla Pipeline (`For Requirements`).
   - Any member store already confirmed onboard earlier renders as a locked green row (`Already Onboarded ✓`).
2. **Lifecycle & Option A Fast-Track Engine (`confirm_coverage_group_onboarding` & `confirm_applicant_onboard`)**:
   - **Initial Partial Onboarding**: Selected stores are recorded as `'Confirmed'` in `public.hr_emploc_store_links` (`plantilla_slots.slot_status = 'hr_processing'`); unselected member stores are recorded as `'Pending'` in `public.hr_emploc_store_links` and automatically retain/create a linked `public.applicants` row (`status = 'For Requirements'`, `coverage_group_id`, `coverage_slot_id`) on the remaining store's VCode (`plantilla_slots.slot_status = 'pipeline'`).
   - **Remaining Store Completed While Still in HR Emploc**: Confirming onboarding on the remaining store merges it into the candidate's existing `public.hr_emploc` record (`hr_emploc_store_links.status = 'Confirmed'`, `covered_stores` updated) without creating a duplicate `hr_emploc` row.
   - **Remaining Store Completed After Candidate Is Already Active in Plantilla (Option A Fast-Track)**: Confirming onboarding on the remaining store links it directly to the employee's active `public.plantilla` record via `public.plantilla_store_links`, marks the store's `plantilla_slots` row `'occupied'`, closes the store's `vacancies` row (`'Filled'`), and invokes `public.fn_sync_employee_store_allocations` to rebalance `public.employee_store_allocations` ($1/N$, e.g. `0.50 + 0.50` HC).

---

> [!NOTE]
> **Historical Assessment & Implementation Phases Archive:**
> Historical pre-implementation assessments and phase checklists have been archived to [`docs/state/archive/vacancy_web_state_historical.md`](archive/vacancy_web_state_historical.md) to keep this live specification token-optimized.
