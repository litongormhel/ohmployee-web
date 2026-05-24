# Current State

OHMployee Web is a Next.js App Router project with a lightweight admin command shell, authentication page, and scaffold-only module routes.

## Foundation

- App Router root remains in `src/app`.
- Reusable components live in `src/components`.
- Shared library code lives in `src/lib`.
- React Query is available app-wide through the providers wrapper.
- Supabase client environment variables are documented in `.env.example`.
- Dashboard routes use a persistent admin shell with a desktop sidebar, topbar, responsive mobile navigation strip, and centered main content container.
- The web module map is centralized in `src/lib/modules.ts`.
- Dashboard routes now validate the Supabase Auth user and load the web-safe backend context through `get_web_current_user_context` in `src/components/DashboardAuthShell.tsx`.
- Unauthenticated dashboard visits redirect to `/login`.
- `/login` redirects already-authenticated visitors to `/dashboard`, and successful login lands on `/dashboard`.
- Logout is available in the sidebar and signs out before redirecting to `/login`.
- This web repo currently has no local `supabase/migrations` directory.
- The frontend now requires `public.get_web_current_user_context()` as the canonical Supabase RPC for web shell bootstrap, with an optional `security_invoker` view named `public.web_current_user_context` after the RPC is safe.
- The admin shell renders only when the RPC returns `access_status === "allowed"`.
- Backend `allowed_module_keys` drives sidebar/topbar module visibility; `module_capabilities` is kept presentation-only.
- Missing profiles, inactive/disabled accounts, unauthorized web roles, RPC failures, malformed module arrays, and malformed capability payloads render a blocked-access screen instead of the shell.

## Module Registry

- Dashboard: `/dashboard`
- CENCOM: `/cencom`
- Vacancy: `/vacancy`
- HR Emploc: `/hr-emploc`
- Plantilla: `/plantilla`
- Approvals: `/approvals`
- User Management: `/users`
- Team Directory: `/team-directory`
- Notifications: `/notifications`
- Reports: `/reports`
- Settings: `/settings`
- More: `/more`

## Not Implemented

- Most Supabase business queries, RLS policies, and module workflows are not implemented in this web repo. Vacancy Web now calls its approved read-only RPC names.
- Backend profile/scope loading and real RBAC capability filtering are wired to the expected RPC contract, but the database implementation is outside this web repo.
- An allowed user with an empty `allowed_module_keys` array receives dashboard-only navigation; missing module/capability fields fail closed.
- Vacancy data access is now wired through `get_web_vacancy_summary(...)` and `list_web_vacancies(...)` only.
- Vacancy list row typing and rendering now use the RPC field name `position_title` rather than a legacy `position`/camelCase frontend alias.
- Vacancy Web target architecture is now documented in `docs/state/vacancy_web_state.md`: desktop admin command-center layout, KPI row, status tabs, filter/search toolbar, dense table, detail drawer, applicant placeholder, and capability-controlled action area.
- Vacancy Web expects the read contracts `get_web_vacancy_summary(...)` and `list_web_vacancies(...)`; detail and action contracts are still not implemented in the frontend.
- Blank module pages intentionally avoid mocked records, charts, and CRUD actions.
- The safe web current-user context RPC/view contract is documented in `docs/state/web_auth_rbac_state.md`; this repo has no local migration for it.
- Frontend code may use module capabilities only for shell display metadata. Supabase RLS/RPC remains the authority for all actions and business data.
- Vacancy Web now renders a desktop/admin-first read-only UI: compact page header, RPC-backed KPI row, status tabs, submitted search, pipeline/aging filters, dense table rows, pagination, loading, empty, retryable error, blocked/read-denied states, detail panel from selected list rows, applicant summary placeholder, and disabled capability-labeled action zone.
- Vacancy Web fetches only from the approved read RPCs. It does not render fake rows, query raw tables, include sample employee/applicant names, bypass RLS, or implement CRUD/mutations.
- `OHM2026_1077` documents the proposed Vacancy Web read contract in `docs/state/vacancy_web_state.md`. The recommended backend-first contract is `public.list_web_vacancies(...)` for scoped dense-table reads and `public.get_web_vacancy_summary(...)` for scoped KPI/counts, with an optional later `public.get_web_vacancy_detail(p_vacancy_id uuid)`.
- The Web Vacancy read contract should wrap existing Mobile semantics from `vw_vacancy_list`, `vw_vacancy_detail`, `fn_is_active_vacancy_applicant_status`, `v_vacancy_pipeline_status`, hired visibility, closure flags, and existing RBAC/scope helpers. It must derive the caller from `auth.uid()`, enforce Super Admin/Head Admin broad access and scoped OM/ATL/TL/HRCO/Recruitment/Viewer reads, and return only web-safe fields.
- Remaining Vacancy gaps are backend availability/verification of the scoped list and summary RPCs in the target Supabase project, an optional detail contract, and later action RPCs for approval, applicant updates, closure requests, and vacancy/headcount creation.
