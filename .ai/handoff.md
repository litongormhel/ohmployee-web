# AI Handoff

## Current Workflow

- Keep Next.js App Router route files in `src/app/**`.
- Keep reusable presentation components in `src/components/**`.
- Keep shared clients, providers, query contracts, and future server/client utilities in `src/lib/**`.
- Keep thin-client behavior: UI may call lightweight client helpers, but business rules, RBAC, RLS, and data integrity belong in Supabase.
- Keep the admin shell scaffold in the dashboard route group and source navigation from `src/lib/modules.ts`.
- Use `src/components/ModuleEmptyState.tsx` for scaffold-only module pages until real contracts are approved.

## Foundation Notes

- Supabase browser client setup exists at `src/lib/supabase/client.ts`.
- React Query is mounted through `src/app/providers.tsx` from the root layout.
- The dashboard shell provides a persistent desktop sidebar, topbar, responsive mobile module strip, active-route styling, and constrained main content container.
- `src/components/DashboardAuthShell.tsx` now owns the lightweight client-side dashboard guard and current-user context load from `get_web_current_user_context`.
- `src/lib/auth.ts` defines the RPC-backed current-user context, blocked-access states, and fail-closed module visibility helper.
- `src/lib/modules.ts` includes stable module keys for future backend capability mapping.
- Most module routes are placeholders only; do not add business logic until Supabase contracts and RLS are defined. Vacancy is the first read-only RPC-backed module surface.
- Root `/` redirects to `/dashboard` as the web app foundation entry point.

## Auth/RBAC Handoff

- Auth/RBAC architecture is documented in `docs/state/web_auth_rbac_state.md`.
- Dashboard route-group auth guarding is implemented through the client auth shell because the project currently has `@supabase/supabase-js` only; no SSR cookie adapter is installed.
- The temporary Supabase Auth-only context has been replaced with a call to `supabase.rpc("get_web_current_user_context")`.
- The shell renders only when `access_status === "allowed"`; missing sessions still redirect to `/login`.
- Missing profile, inactive/disabled account, unauthorized web role, RPC failure, missing module arrays, and malformed capabilities block the shell.
- Module visibility uses `src/lib/modules.ts` plus backend `allowed_module_keys`; `module_capabilities` is presentation-only metadata for sidebar/topbar display.
- Frontend role checks are display/navigation only. Backend RLS/RPC policies remain the authority for all data access, mutations, scopes, and workflow rules.
- Do not invent web-only roles; mirror Mobile role, group scope, and account scope semantics from Supabase.

## Backend Contract Handoff

- This repo currently has no local `supabase/migrations` directory.
- Backend implementation should happen in the authoritative Supabase migration workflow, or after adding an approved migration directory to this repo.
- Required canonical contract for the current frontend: `public.get_web_current_user_context()` RPC.
- Optional read contract: `public.web_current_user_context` as a `security_invoker = true` view once the RPC is safe.
- The context must include current Auth user id, safe full name/email, existing Mobile role key/name, `access_status`, group scope, account scope, `allowed_module_keys`, and `module_capabilities`.
- The contract must derive identity from `auth.uid()`, not caller arguments, and must not expose service-role data.
- Fail closed for unauthenticated, missing-profile, inactive, disabled, and unauthorized-web cases.
- See the `OHM2026_1072-IMPL-1` prompt in `docs/state/web_auth_rbac_state.md` for the exact migration/RPC/view implementation brief.

## Vacancy Web Handoff

- Vacancy Web architecture is documented in `docs/state/vacancy_web_state.md`.
- Current Vacancy implementation is a client desktop admin shell with a compact header, RPC-backed KPI cards, status tabs, submitted search, pipeline/aging filters, dense read-only table rows, pagination, loading/empty/error/blocked states, a right-side selected-row detail panel, applicant placeholder, and disabled capability-labeled action zone.
- The Vacancy page calls only `get_web_vacancy_summary(...)` and `list_web_vacancies(...)` through `src/lib/queries/vacancy.ts`.
- Vacancy list rows use the RPC field name `position_title` end-to-end in the frontend item contract, table, and selected-row detail panel.
- Do not add raw table queries, caller-controlled role/scope parameters, fake data, CRUD, or mutations.
- Target UX is a desktop admin command center: KPI summary row, status tabs, filter/search toolbar, dense table, detail drawer/panel, applicant placeholder, and capability-controlled action area.
- Web must mirror Mobile vacancy business rules and status transitions, but present them in a dense admin-panel workflow rather than Mobile cards.
- `OHM2026_1077` adds the backend read-contract architecture for Vacancy Web. The recommended migration should create `public.list_web_vacancies(...)` for scoped dense-table rows and `public.get_web_vacancy_summary(...)` for scoped KPI/counts, with `public.get_web_vacancy_detail(p_vacancy_id uuid)` deferred until the detail drawer needs real fields.
- The Vacancy Web list contract must reuse existing Mobile semantics from `vw_vacancy_list`, `vw_vacancy_detail`, `fn_is_active_vacancy_applicant_status`, `v_vacancy_pipeline_status`, `has_recent_hire`, and closure flags. It must not invent new Vacancy statuses, expose applicant contact fields, or expose employee/Plantilla-sensitive fields.
- Read scope must be enforced in Supabase from `auth.uid()` and existing RBAC/scope helpers: Super Admin / Head Admin broad access; OM / ATL / TL / HRCO / Recruitment scoped access; Viewer scoped read-only as allowed.
- Required future backend contracts include verification/availability of the scoped vacancy list RPC and KPI summary RPC in the target Supabase project, optional detail RPC, and later action RPCs that reuse Mobile vacancy rules for approval, applicant status updates, closure requests, and allowed vacancy/headcount creation.
- Vacancy UI uses backend `row_capabilities` only for presentation hints. Supabase RPC/RLS must remain the authority for view, approve, applicant-status update, request-closure, and add-vacancy/headcount permissions. Current action buttons remain disabled because no action RPC contract exists yet.
- See the `OHM2026_1077-IMPL-1` prompt in `docs/state/vacancy_web_state.md` for the exact Supabase migration implementation brief.
