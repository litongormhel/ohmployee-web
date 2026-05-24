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

- Supabase business queries, RPC calls, RLS policies, and module workflows are not implemented.
- Backend profile/scope loading and real RBAC capability filtering are wired to the expected RPC contract, but the database implementation is outside this web repo.
- An allowed user with an empty `allowed_module_keys` array receives dashboard-only navigation; missing module/capability fields fail closed.
- Vacancy data access is a typed empty foundation placeholder only.
- Blank module pages intentionally avoid mocked records, charts, and CRUD actions.
- The safe web current-user context RPC/view contract is documented in `docs/state/web_auth_rbac_state.md`; this repo has no local migration for it.
- Frontend code may use module capabilities only for shell display metadata. Supabase RLS/RPC remains the authority for all actions and business data.
