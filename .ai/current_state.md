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
- Dashboard routes now load a minimal Supabase Auth-backed current-user context in `src/components/DashboardAuthShell.tsx`.
- Unauthenticated dashboard visits redirect to `/login`.
- `/login` redirects already-authenticated visitors to `/dashboard`, and successful login lands on `/dashboard`.
- Logout is available in the sidebar and signs out before redirecting to `/login`.
- This web repo currently has no local `supabase/migrations` directory.
- The current backend design handoff recommends `public.get_web_current_user_context()` as the canonical Supabase RPC for web shell bootstrap, with an optional `security_invoker` view named `public.web_current_user_context` after the RPC is safe.

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
- Backend profile/scope loading and real RBAC capability filtering are not implemented.
- The current web user context intentionally uses Supabase Auth session/user only and fails closed to minimal dashboard module visibility.
- Vacancy data access is a typed empty foundation placeholder only.
- Blank module pages intentionally avoid mocked records, charts, and CRUD actions.
- The safe web current-user context RPC/view is designed in `docs/state/web_auth_rbac_state.md` but has not been implemented.
- No frontend code should consume real module capabilities until the backend contract exists and returns Mobile RBAC-derived role, active status, group scope, account scope, allowed module keys, and capabilities.
