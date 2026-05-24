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
- The Shared Web UI System architecture has been defined and documented in `docs/state/web_ui_system_state.md`, auditing existing Vacancy UI patterns, specifying reusable admin primitives, defining visual system tokens, and mapping out a phased extraction roadmap.


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
- Vacancy Web is fully integrated with the detail read contract `public.get_web_vacancy_detail(p_vacancy_id uuid)` in the frontend.
- Blank module pages intentionally avoid mocked records, charts, and CRUD actions.
- The safe web current-user context RPC/view contract is documented in `docs/state/web_auth_rbac_state.md`; this repo has no local migration for it.
- Frontend code may use module capabilities only for shell display metadata. Supabase RLS/RPC remains the authority for all actions and business data.
- Vacancy Web now renders a high-fidelity desktop/admin-first read-only overlay drawer for vacancy details instead of a static selection sidebar. The dense list table is full screen width.
- Vacancy Web fetches only from the approved read RPCs. It does not render fake rows, query raw tables, include sample employee/applicant names, bypass RLS, or implement CRUD/mutations.
- `OHM2026_1077` and `OHM2026_1082` document the proposed Vacancy Web read contracts in `docs/state/vacancy_web_state.md`. The recommended backend-first list contract is `public.list_web_vacancies(...)` and `public.get_web_vacancy_summary(...)`. The recommended detail drawer contract is `public.get_web_vacancy_detail(p_vacancy_id uuid)`.
- The Web Vacancy detail contract wraps existing Mobile semantics from `vw_vacancy_detail`, `fn_is_active_vacancy_applicant_status`, active applicant lists, and existing RBAC/scope helpers. It derives the caller from `auth.uid()`, enforces Super Admin/Head Admin broad access and scoped OM/ATL/TL/HRCO/Recruitment/Viewer reads, separates list-only vs. detail-only fields, and returns row capabilities (`can_approve`, `can_update_applicant_status`, `can_request_closure`) without exposing applicant PII (contact numbers or email addresses).
- Remaining Vacancy gaps are backend availability/verification of the scoped list, summary, and detail RPCs in the target Supabase project, followed by Phase 4 (mutations and action RPCs).
- The Shared Web UI System Phase 2 low-risk primitives (`AdminPageHeader`, `MetricCard`, `DataState`, and `StatusBadge`) are fully implemented under `src/components/shared/` and `src/components/ui/` with lightweight TypeScript typings, explicit prop mappings, and strict aesthetic adherence. The Phase 3 structural layout components (`AdminFilterBar`, `CapabilityActionBar`, and `DetailDrawer`) are also fully implemented as generic, domain-neutral containers under `src/components/shared/`.
- The Vacancy module has been fully refactored to consume the central Shared Web UI System (Phase 4): the list page uses `AdminPageHeader`, `MetricCard`, and `AdminFilterBar`, and the detail drawer uses `DetailDrawer`, `CapabilityActionBar`, and `StatusBadge` where safe. All exact read-only queries, filter query parameter bindings, active pipeline filters, pagination, access-denied RLS shields, non-PII candidate structures, and historical timelines are preserved perfectly with zero visual or functional regressions.
- The HR Emploc Web module (OHM2026_1094) has been fully implemented in the frontend. The blank `/hr-emploc` shell was refactored into a high-fidelity read-only operational compliance queue using the shared AdminPageHeader, MetricCard, AdminFilterBar, DataState, StatusBadge, DetailDrawer, and CapabilityActionBar components. The client queries (`getWebHrEmplocSummary`, `listWebHrEmplocs`, and `getWebHrEmplocDetail`) are successfully wired to dynamic status tabs, search & filters (assignment, position, accountId, groupId), a compact dense grid table, and a 640px details drawer command center displaying placement parameter metrics, SLA breach alert warnings (Tiers 1 & 2), deficiencies checklist, corrected file attachments, separation/deletion banners, timeline logs, and permission badges. Verified successfully via pnpm lint and pnpm build (zero warnings, zero errors).
- Remaining gaps are backend implementation/mutations integration (Phase 4 action RPCs).
- The Plantilla Web module (OHM2026_1095) target architecture and state design are now fully defined and documented in `docs/state/plantilla_web_state.md`. This details Employee/Store dual views, scoped RBAC visibility, strict database-level PII masking rules, deactivation row styling, separation/backout clearance workflows, Additional Headcount (AH) temporary slot integrations, 640px sliding detail drawer layout, SLA/status breach timers, recommended SQL RPC contracts, and shared UI component mappings.



