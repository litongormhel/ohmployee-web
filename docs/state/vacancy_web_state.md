# Vacancy Web State

## Scope

This document defines the target OHMployee Web Vacancy module architecture before implementation. It is intentionally limited to web layout, behavior, role/capability gates, and Supabase contract requirements.

No code, fake data, CRUD flow, or Supabase query implementation is introduced by this architecture pass.

## Current Vacancy Web Assessment

- `src/app/(dashboard)/vacancy/page.tsx` now renders a client-only desktop Vacancy Management command-center shell with a compact page header, non-data KPI summary placeholders, status tabs for `open`, `with_applicant`, `rejected`, and `backout`, disabled search/filter controls, a dense table region, a read-only detail panel, and a backend-contract warning note.
- `src/components/vacancy/VacancyTable.tsx` now renders an honest read-only table shell with operational columns, a no-records state, footer pagination placeholder, a selection-driven detail placeholder, an applicant section placeholder, and a capability-labeled action zone.
- `src/lib/queries/vacancy.ts` defines a narrow `VacancyStatus`, `VacancyListItem`, and `getVacancies(status)` placeholder that always returns an empty array.
- The Vacancy page no longer calls the placeholder query from the shell UI. It intentionally avoids Supabase calls, list/detail queries, CRUD, mutations, mocked business records, sample employee names, or fabricated applicant data.
- The module currently has no real Supabase query, RPC, view, RLS-backed data access, mutations, applicant actions, active search/filter behavior, KPI totals, or enabled workflow actions.
- The current shell is a Phase 1 foundation marker for a dense admin command center rather than a stretched Mobile vacancy card list.

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

Display compact KPI tiles above the table after a backend aggregate contract exists.

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

- Search by vacancy code, position, department, store/account/group, or applicant name when supported.
- Department/position filter.
- Scope filter if the user has multiple account or group scopes.
- Date/aging filter.
- Status is controlled by tabs, not duplicated as a separate primary filter.

Filters should be reflected in query parameters only if route persistence is explicitly desired in the implementation pass.

### Dense Vacancy Table

The table should optimize for scanning and operational decisions.

Recommended columns:

- Vacancy code.
- Position/title.
- Department or business unit.
- Account/group/location, depending on Mobile scope terms.
- Status.
- Applicant summary.
- Requested/created date.
- Aging.
- Owner/requester or approver, if available and web-safe.
- Last activity.
- Row-level action affordance only when capabilities allow.

The table should support loading, empty, error, selected-row, and limited-access states. Empty states must be real no-record states, not mocked data.

### Detail Drawer/Panel

Selecting a row should open a right-side detail drawer or split-panel detail area. The drawer should be read-first and action-aware.

Recommended sections:

- Vacancy identity: code, position, department, scope, status.
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

Action buttons must be hidden or disabled from backend-provided capability and record-state signals. The browser must not infer authority from role names.

## Web-Specific Behavior Mirroring Mobile Rules

- Web should mirror Mobile vacancy business rules, status names, allowed transitions, scope boundaries, and RBAC semantics.
- Web may present denser controls and tables, but it must not introduce new workflow states or looser transitions.
- Any status transition, applicant update, approval, closure request, or headcount/vacancy creation must call a Supabase RPC that already validates the authenticated user, scope, capability, and record state.
- Web list and detail reads must be scoped by backend RLS/RPC contracts using the current authenticated user; the frontend should not pass profile, role, group, or account ids as authority.
- Frontend capability checks are for presentation and ergonomics only.

## Supabase Data Contract Requirements

### List Contract

Vacancy Web needs a backend-approved list RPC or view before replacing the empty placeholder query.

Recommended canonical shape:

```sql
select *
from public.list_web_vacancies(
  p_status := 'open',
  p_search := null,
  p_filters := '{}'::jsonb,
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

Recommended list row fields:

| Field | Notes |
| --- | --- |
| `vacancy_id` | Internal id for selection and detail lookup. |
| `vcode` | Vacancy code shown in the table. |
| `position_title` | Position/title label. |
| `department_name` | Department/business unit label. |
| `scope_label` | Account/group/location label, if web-safe. |
| `status` | Mobile-compatible vacancy status key. |
| `applicant_count` | Summary only if authorized. |
| `current_applicant_name` | Optional and only if Mobile permits exposure. |
| `created_at` or `requested_at` | For sorting and aging. |
| `age_days` | Prefer backend-computed if business-specific. |
| `last_activity_at` | Optional operational recency field. |
| `row_capabilities` | Optional per-record action keys. |

### Detail Contract

A detail RPC or scoped view is needed if the drawer requires fields beyond the list row.

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

### KPI Contract

KPI totals should use a scoped aggregate RPC or a list RPC metadata payload. The browser should not compute privileged totals from records it has not been authorized to fetch.

Recommended shape:

```sql
select *
from public.get_web_vacancy_summary(p_filters := '{}'::jsonb);
```

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

ID: OHM2026_1075-IMPL-1

Implement the Vacancy Web shell UI only.

Read only:
- `src/app/(dashboard)/vacancy/page.tsx`
- `src/components/vacancy/**`
- `src/lib/queries/vacancy.ts`
- `src/lib/auth.ts`
- `src/lib/modules.ts`
- `docs/state/vacancy_web_state.md`
- `docs/state/web_auth_rbac_state.md`
- `docs/state/web_foundation_state.md`
- `.ai/current_state.md`
- `.ai/handoff.md`

Tasks:
1. Refactor the Vacancy page into a desktop admin command-center shell.
2. Add a non-data KPI summary row with empty/loading-ready states only; do not invent numbers.
3. Add a dense filter/search toolbar UI that does not call Supabase yet.
4. Preserve status tabs for `open`, `with_applicant`, `rejected`, and `backout`.
5. Keep the table read-only and backed by the existing empty placeholder contract.
6. Add a detail drawer or right-side panel shell that opens from selected real rows only; no fake detail data.
7. Add an applicant section placeholder inside the detail surface.
8. Add a capability-controlled action area structure, but do not wire mutations.
9. Keep all RBAC/RLS/business authority in Supabase and avoid role-name checks in UI components.

Constraints:
- Do not add fake data.
- Do not add Supabase queries.
- Do not create CRUD.
- Do not implement mutations.
- Do not copy Mobile card UI directly.
- Keep Web as a desktop admin panel.
- Preserve backend-authoritative RBAC/RLS.

Validation:
- Run `npm`/project lint or typecheck command if available.
- Confirm the page renders without mocked records.
