# Vacancy Web State

## Scope

This document tracks the OHMployee Web Vacancy module architecture and current read-only frontend integration. It is intentionally limited to web layout, behavior, role/capability gates, and Supabase read contract requirements.

No fake data, CRUD flow, mutation, raw table query, or RLS bypass is introduced by this integration pass.

## Current Vacancy Web Assessment

- `src/lib/queries/vacancy.ts` now calls the approved read RPC names: `get_web_vacancy_summary(...)` for KPI counts and `list_web_vacancies(...)` for dense list rows.
- The query layer sends only queue/search/filter/sort/pagination arguments. It does not pass caller identity, role, profile, account, or group ids as authority.
- `src/app/(dashboard)/vacancy/page.tsx` now uses React Query to load the read-only Vacancy summary and list RPCs, with status tabs, submitted search, pipeline/aging filters, pagination state, loading state, empty state, blocked state, and retryable error state.
- `src/components/vacancy/VacancyTable.tsx` now renders backend rows with `row_capabilities`, `total_count`, `aging_bucket`, and `pipeline_status`; table row selection is read-only and detail-panel content is limited to list-returned fields.
- `OHM2026_1081` aligned the Vacancy frontend row contract with the RPC field name `position_title`; the query normalizer, table, and selected-row detail panel no longer consume a legacy `position`/camelCase frontend field.
- Vacancy actions remain disabled/placeholder only. Add vacancy, approval, applicant-status update, closure, and detail-action mutations are not implemented.
- The module still has no raw table query, CRUD, mutation, service-role access, fake rows, sample employee/applicant names, or applicant contact exposure.

## OHM2026_1077 Backend Assessment

This architecture pass inspected the authoritative Supabase sibling repo at `/Users/armanjr/Projects/OHMployee/OHMployee` because this web repo has no local `supabase/migrations` directory.

Relevant existing Mobile/backend artifacts:

- `public.vw_vacancy_list` and `public.vw_vacancy_detail` are the current Mobile read surfaces. They project `vacancies` with account/store/area/position/employment/status fields, vacancy source/request metadata, `vacant_date`, `aging_days`, `target_fill_date`, `urgency_level`, closure flags, active/confirmed applicant counts, `has_recent_hire`, `group_id/group_name`, and HRCO assignment.
- `public.fn_is_active_vacancy_applicant_status(text)` is the canonical active-applicant predicate. Active statuses are `New`, `For Interview`, `For Requirements`, and `For Onboard` including normalized lowercase/snake_case equivalents.
- `public.v_vacancy_pipeline_status` classifies vacancy slot occupancy as `Pipeline` when the canonical active applicant count is greater than zero, otherwise `Open`.
- Mobile Vacancy semantics distinguish slot status from recent hired-applicant visibility. `derived_status = 'Open'` may coexist with `has_recent_hire = true` after a reopened vacancy; the Hired tab is visibility-only and must not block Open-slot display.
- `public.fn_vacancy_summary_counts(p_account_ids uuid[] default null)` exists in the remote schema, but it accepts caller-provided account ids. Web should not use that shape directly as an authority boundary.
- `public.get_web_current_user_context()` now exists in the authoritative Supabase repo. It derives identity from `auth.uid()`, returns role/scope/module capability metadata, and maps role permission matrix entries to web module keys.
- Existing RBAC helpers include `get_my_role_level()`, `get_effective_role()`, `get_my_profile_id()`, `get_current_profile_id()`, `i_have_full_access()`, `is_super_admin()`, and `get_my_allowed_accounts()`. Current scoped checks commonly use account names via `get_my_allowed_accounts()` plus full-access checks for Super Admin and Head Admin.
- Role levels are table-backed: Super Admin 100, Head Admin 90, OM/Operations Manager 70, HRCO 45, ATL/TL around 40-42/41, Recruitment 20, Viewer 10.

Important gaps for Web:

- Existing Mobile views are broad projections and should not be exposed to the web table directly unless their underlying RLS and grants are verified for every selected column.
- Some later `CREATE VIEW` replacements for `vw_vacancy_list` and `vw_vacancy_detail` omit `WITH (security_invoker = true)`. The web contract should explicitly preserve invoker semantics for helper views or centralize enforcement in `SECURITY DEFINER` RPCs with locked search path and explicit caller/scope checks.
- Existing Mobile list/detail projections include fields that are not needed for the dense Web list, such as triggered/request user ids and headcount-request internals. The Web list must project only web-safe operational fields.
- No approved Web-specific list, KPI/count, filter/search/sort/pagination, or row capability contract exists yet.

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

The table supports loading, empty, retryable error, blocked/read-denied, selected-row, and paginated states. Empty states are real no-record states, not mocked data.

### Detail Drawer/Panel

Selecting a row opens the right-side detail panel using only list-returned read fields. A future detail RPC is still required before exposing broader detail context.

Recommended sections:

- Vacancy identity: code, `position_title`, department, scope, status.
- Request/headcount context.
- Timeline or status history placeholder if a backend-safe contract exists later.
- Applicant section placeholder.
- Capability-controlled action area.

The detail surface should not fetch or expose fields beyond the user's RLS/RPC-authorized scope.

### Applicant Section Placeholder

The applicant section should reserve the structure for future applicant workflows without implementing them prematurely.

Recommended placeholder states:

- No applicant attached.
- Applicant summary available from detail contract.
- Applicant workflow unavailable until backend contract is implemented.

Do not add applicant mutation UI until backend action RPCs and capability keys are confirmed.

### Capability-Controlled Action Area

Actions should render only when the current module capabilities and selected record state allow them. The backend action RPC must still enforce the same rule.

Expected action families:

- Approve vacancy or vacancy movement.
- Update applicant status.
- Request closure.
- Add vacancy/headcount if allowed.

Action buttons are disabled and display backend row capability hints only. The browser does not infer authority from role names.

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
  p_queue,
  p_search,
  p_filters,
  p_sort: "aging_days",
  p_sort_dir: "desc",
  p_limit,
  p_offset,
});
```

The current UI reads `row_capabilities`, `total_count`, `aging_bucket`, and `pipeline_status` directly from the returned rows. Permission/RLS/RPC authorization failures render a blocked state; other failures render a retryable error state.

Vacancy Web needs a backend-approved list RPC before replacing the empty placeholder query. Prefer an RPC as the canonical browser contract, backed by a narrow `security_invoker` helper view only if useful inside the migration.

Recommended canonical shape:

```sql
select *
from public.list_web_vacancies(
  p_queue := 'open',
  p_search := null,
  p_filters := '{}'::jsonb,
  p_sort := 'aging_days',
  p_sort_dir := 'desc',
  p_limit := 50,
  p_offset := 0
);
```

The exact function name may change to match the authoritative Supabase naming pattern, but the contract should:

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
| `p_queue` | `text` | One of `open`, `pipeline`, `with_applicant`, `hired`, `closure`, `rejected`, `backout`, `all`; map aliases to Mobile semantics. `with_applicant` should mean canonical active-applicant `Pipeline`. |
| `p_search` | `text null` | Case-insensitive search across `vcode`, account, group, store/branch, area/city, and `position_title`. Do not search applicant names in the list unless explicitly approved. |
| `p_filters` | `jsonb` | Filter object only; do not accept caller-controlled profile/role/scope authority. |
| `p_sort` | `text` | Allowlist only. Recommended: `aging_days`, `vacant_date`, `target_fill_date`, `urgency_level`, `account_name`, `group_name`, `store_name`, `position_title`, `updated_at`, `vcode`. |
| `p_sort_dir` | `text` | `asc` or `desc`, default `desc`. |
| `p_limit` | `integer` | Default `50`, max `100`. |
| `p_offset` | `integer` | Default `0`, never negative. |

Recommended `p_filters` keys:

| Key | Type | Notes |
| --- | --- | --- |
| `status` | `text[]` | Raw vacancy statuses only if the UI needs more than the queue. Must not introduce new statuses. |
| `account_ids` | `uuid[]` | Optional narrowing within caller scope. Ignore or reject ids outside caller scope. |
| `group_ids` | `uuid[]` | Optional narrowing within caller scope. Ignore or reject ids outside caller scope. |
| `store_ids` | `uuid[]` | Optional narrowing within caller scope. |
| `position_ids` | `uuid[]` | Optional narrowing within caller scope. |
| `aging_buckets` | `text[]` | `advance`, `1_15`, `16_30`, `31_60`, `61_120`, `gt121`. |
| `urgency_levels` | `text[]` | Existing values only. |
| `vacant_date_from` / `vacant_date_to` | `date` | Date range over `vacant_date`. |
| `target_fill_date_from` / `target_fill_date_to` | `date` | Date range over `target_fill_date`. |

Pagination should use offset/limit for the first Web integration because it is simple for admin tables and works with a filtered count. Use deterministic secondary ordering, such as `ORDER BY <allowlisted sort>, vcode, vacancy_id`, so rows do not jump between pages. Consider keyset pagination only if the list grows large enough to make deep offsets expensive.

### Detail Contract

A detail RPC is needed later if the drawer requires fields beyond the list row. Do not implement it in the first Web list migration unless the frontend is ready to consume it.

Recommended shape:

```sql
select *
from public.get_web_vacancy_detail(p_vacancy_id := '<uuid>');
```

The detail contract should:

- Derive caller identity from `auth.uid()`.
- Validate record visibility through existing Mobile RBAC/RLS.
- Return one vacancy detail payload or no row/permission error.
- Include applicant summary only when authorized.
- Include action eligibility hints only as presentation metadata; action RPCs remain authoritative.
- Keep applicant detail minimal: summary/status counts and current active applicant display name only if already allowed by Mobile. Do not return mobile number/contact fields in the initial detail contract.

### KPI Contract

KPI totals should use a scoped aggregate RPC or a list RPC metadata payload. The browser should not compute privileged totals from records it has not been authorized to fetch.

Recommended shape:

```sql
select *
from public.get_web_vacancy_summary(
  p_search := null,
  p_filters := '{}'::jsonb
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

## Implementation Phases

### Phase 1: Shell UI

- Refactor the Vacancy page into a desktop admin command-center layout.
- Keep data placeholders empty and honest.
- Add KPI row, filter/search bar structure, status tabs, dense table structure, detail drawer structure, applicant placeholder, and action area container.
- No fake data and no real Supabase queries.
- Implemented in the web shell as of `OHM2026_1076`: the UI is static/read-only, action controls remain disabled, and backend capability keys are displayed only as presentation placeholders until real module and record capabilities are passed from approved contracts.

### Phase 2: Read-Only List

- Implement the approved scoped list contract in Supabase first.
- Replace `getVacancies` placeholder with typed client integration.
- Add loading, empty, error, pagination, search, filter, and tab behavior.
- Keep actions disabled or absent unless capabilities are present.

### Phase 3: Detail Drawer

- Implement the approved detail contract in Supabase first.
- Load detail data only after row selection.
- Render vacancy context, applicant placeholder/summary, record activity fields, and record-level capability state.

### Phase 4: Actions Later

- Wire approval, applicant status updates, closure requests, and add vacancy/headcount only after action RPCs are confirmed.
- Each action must be backend-authoritative, RLS/RBAC-enforced, auditable, and consistent with Mobile business rules.
- Add optimistic UI only if the backend contract and validation strategy support it.

## Exact Next Implementation Prompt

ID: OHM2026_1077-IMPL-1

Implement the Supabase backend read contract for OHMployee Web Vacancy list and KPI summary.

Read only:
- `docs/state/vacancy_web_state.md`
- `docs/state/web_auth_rbac_state.md`
- `docs/state/web_foundation_state.md`
- `.ai/current_state.md`
- `.ai/handoff.md`
- Existing Supabase vacancy migrations/views/RPCs only, especially `vw_vacancy_list`, `vw_vacancy_detail`, `v_vacancy_pipeline_status`, applicant status helpers, closure/hired lifecycle migrations, and CENCOM aging/priority helpers if reused.
- Existing Supabase RBAC/scope helper migrations only, especially `get_web_current_user_context`, `get_my_role_level`, `get_effective_role`, `get_my_profile_id`, `get_current_profile_id`, `i_have_full_access`, `get_my_allowed_accounts`, `user_scopes`, and the role permission matrix.

Tasks:
1. Add a migration in the authoritative Supabase repo; do not edit frontend code.
2. Create a scoped Web vacancy list RPC, recommended `public.list_web_vacancies(p_queue text default 'open', p_search text default null, p_filters jsonb default '{}'::jsonb, p_sort text default 'aging_days', p_sort_dir text default 'desc', p_limit integer default 50, p_offset integer default 0)`.
3. Derive caller identity only from `auth.uid()`. Do not accept caller-controlled profile, role, account scope, or group scope authority.
4. Enforce `vacancy.view`/Mobile-equivalent read access and existing Mobile scope:
   - Super Admin / Head Admin broad access via existing full-access semantics.
   - OM / ATL / TL / HRCO / Recruitment scoped by existing account/group scope.
   - Viewer read-only only within allowed scope.
5. Base list semantics on existing Mobile Vacancy sources:
   - use `vw_vacancy_list` semantics;
   - use `fn_is_active_vacancy_applicant_status` for active applicant/pipeline status;
   - preserve `derived_status`, `has_recent_hire`, `has_pending_closure`, and closure status behavior;
   - do not invent vacancy statuses.
6. Return only web-safe dense table fields:
   - `vacancy_id`, `vcode`, `account_id`, `account_name`, `group_id`, `group_name`, `store_id`, `store_name`, `position_id`, `position_title`, `employment_type`;
   - `vacancy_status`, `pipeline_status`, `derived_status`, `active_applicant_count`, `confirmed_onboard_count`, `has_recent_hire`, `has_pending_closure`, `closure_request_status`;
   - `vacant_date`, `aging_days`, `aging_bucket`, `target_fill_date`, `urgency_level`, optional `urgency_tier`;
   - nullable `penalty_exposure` only if an existing authoritative safe source exists, otherwise return `null`;
   - `hrco_user_id`, live-validated `hrco_name`, optional `last_activity_at`, `row_capabilities`, optional `total_count`.
7. Implement filters/search:
   - queue/status;
   - account ids, group ids, store ids/search keyword, position ids;
   - aging bucket, urgency, vacant date range, target fill date range.
8. Implement allowlisted sorting and deterministic pagination:
   - allowed sorts: `aging_days`, `vacant_date`, `target_fill_date`, `urgency_level`, `account_name`, `group_name`, `store_name`, `position_title`, `updated_at`, `vcode`;
   - default `aging_days desc`;
   - clamp limit to max `100`;
   - secondary order by `vcode` and `vacancy_id`.
9. Create a scoped KPI/count RPC, recommended `public.get_web_vacancy_summary(p_search text default null, p_filters jsonb default '{}'::jsonb)`, using the same base scope and filters as the list.
10. Summary should return scoped counts for open, pipeline/with applicant, optional hired-visible, pending closure, rejected/backout if safely derivable from applicant terminal statuses, oldest aging, aging bucket counts, urgency counts, and total filtered count.
11. Add comments and validation SQL proving unauthenticated callers are blocked, scoped users cannot see out-of-scope vacancies, broad admins can see broad rows, Viewer receives read-only hints, and no employee/Plantilla-sensitive fields or applicant contact fields are exposed.
12. Do not implement the detail RPC unless needed for the next frontend phase. If added, keep it read-only, scoped, and web-safe.
13. After implementation, update `docs/state/vacancy_web_state.md`, `.ai/handoff.md`, and `.ai/current_state.md` with final function names and any field differences.

Constraints:
- Do not edit frontend code.
- Do not add fake data.
- Do not weaken RLS or grants.
- Do not expose sensitive employee/Plantilla fields.
- Do not expose applicant mobile/contact fields in the list.
- Do not invent new Vacancy statuses.
- Do not use caller-provided account/group/profile/role arguments as authority.
- Preserve Supabase as business authority.
- Mirror Mobile Vacancy semantics.

Validation:
- Run the authoritative Supabase migration validation/test workflow.
- Test as Super Admin, Head Admin, OM/ATL/TL/HRCO/Recruitment scoped users, Viewer, unauthorized active user, and unauthenticated caller.
- Verify list rows and summary counts match the same scoped base query.
- Verify search/filter/sort/pagination are deterministic and scoped.
- Verify rejected/backout counts are omitted, null, or correctly derived without inventing vacancy statuses.
