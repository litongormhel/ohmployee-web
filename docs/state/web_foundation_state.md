# Web Foundation State

## Scope

This foundation pass stabilizes the Next.js App Router structure and establishes the scaffold-only admin shell.

## Routes

- `/`
- `/login`
- `/dashboard`
- `/cencom`
- `/vacancy`
- `/hr-emploc`
- `/plantilla`
- `/approvals`
- `/users`
- `/team-directory`
- `/notifications`
- `/reports`
- `/settings`
- `/more`

## Admin Shell

- Dashboard routes render inside a persistent desktop-first admin shell.
- The shell includes a left sidebar, topbar/header, active route styling, responsive mobile module navigation, and a constrained main content area.
- Module navigation is driven by `src/lib/modules.ts` and filtered by the current web user context.
- Blank module routes use clean empty states with title, operational purpose, and no mocked business records.
- Root `/` redirects to `/dashboard`.
- Dashboard routes are wrapped by a lightweight auth shell. Missing Supabase Auth sessions redirect to `/login`; login success and already-authenticated login visits redirect to `/dashboard`.
- Until backend RBAC/profile context exists, authenticated users only see the minimal dashboard module in navigation.

## Architecture Direction

- `src/app/**` owns routes and layouts.
- `src/components/**` owns reusable UI and feature presentation components.
- `src/lib/**` owns shared clients, provider support, and typed integration contracts.
- Supabase remains the authority for business logic, RBAC, and RLS.
- Web remains a thin presentation layer until Supabase contracts are defined.
- Authenticated dashboard protection should be added at the App Router dashboard layout boundary, not inside individual module widgets.
- Web RBAC should mirror Mobile semantics and use module visibility only for navigation/display; authorization remains enforced by Supabase.
- The detailed auth/RBAC shell design is tracked in `docs/state/web_auth_rbac_state.md`.

## Backend Contract Direction

- This web repo currently has no local `supabase/migrations` directory.
- The next backend step is a Supabase current-user context contract, not a frontend UI change.
- Recommended canonical contract: `public.get_web_current_user_context()` RPC.
- Optional follow-up contract: `public.web_current_user_context` as a `security_invoker = true` view if a composable read surface is useful.
- The contract must return the current Auth user id, safe name/email, existing Mobile role key/name, active status, group scope, account scope, allowed module keys, and module capabilities.
- The RPC/view must derive identity from `auth.uid()`, mirror Mobile RBAC semantics, and fail closed for unauthenticated, missing-profile, inactive, disabled, and unauthorized-web cases.
- Web should keep treating this as presentation data for navigation and shell state only; business data queries and mutations still need their own Supabase RLS/RPC authority.

## Remaining Gaps

- Define Supabase schema contracts and RLS before replacing placeholder query contracts.
- Add a server-readable Supabase session cookie flow when an SSR auth package/contract is approved.
- Replace the placeholder current-user profile/scope contract before filtering modules by real role, group scope, or account scope.
- Expand UI primitives only when referenced by real implementation work.
- Replace blank module shells with real workflows only after data contracts and authorization rules are approved.
