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
- `src/components/DashboardAuthShell.tsx` now owns the lightweight client-side dashboard guard and current-user context load.
- `src/lib/auth.ts` defines the temporary Supabase Auth-only current-user context and fail-closed module visibility helper.
- `src/lib/modules.ts` includes stable module keys for future backend capability mapping.
- Current module routes are placeholders only; do not add business logic until Supabase contracts and RLS are defined.
- Root `/` redirects to `/dashboard` as the web app foundation entry point.

## Auth/RBAC Handoff

- Auth/RBAC architecture is documented in `docs/state/web_auth_rbac_state.md`.
- Dashboard route-group auth guarding is implemented through the client auth shell because the project currently has `@supabase/supabase-js` only; no SSR cookie adapter is installed.
- Replace the temporary Supabase Auth-only context with a safe backend profile/scope view or RPC before exposing real module visibility.
- Module visibility should use `src/lib/modules.ts` plus backend-provided Mobile RBAC capabilities.
- Frontend role checks are display/navigation only. Backend RLS/RPC policies remain the authority for all data access, mutations, scopes, and workflow rules.
- Do not invent web-only roles; mirror Mobile role, group scope, and account scope semantics from Supabase.

## Backend Contract Handoff

- This repo currently has no local `supabase/migrations` directory.
- Next backend implementation should happen in the authoritative Supabase migration workflow, or after adding an approved migration directory to this repo.
- Recommended canonical contract: `public.get_web_current_user_context()` RPC.
- Optional read contract: `public.web_current_user_context` as a `security_invoker = true` view once the RPC is safe.
- The context must include current Auth user id, safe full name/email, existing Mobile role key/name, active/status fields, group scope, account scope, allowed module keys, and module capabilities.
- The contract must derive identity from `auth.uid()`, not caller arguments, and must not expose service-role data.
- Fail closed for unauthenticated, missing-profile, inactive, disabled, and unauthorized-web cases.
- See the `OHM2026_1072-IMPL-1` prompt in `docs/state/web_auth_rbac_state.md` for the exact migration/RPC/view implementation brief.
