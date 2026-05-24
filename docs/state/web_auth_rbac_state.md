# Web Auth and RBAC State

## Scope

This document defines the intended OHMployee Web authentication guard and RBAC shell architecture. The lightweight web auth/RBAC shell now calls the backend current-user context RPC without middleware, module business queries, or frontend role rules.

The web app remains an admin-panel presentation layer. Supabase is the authority for session validity, RBAC, RLS, business rules, and data integrity.

## Current Foundation Observed

- `src/lib/supabase/client.ts` creates a browser Supabase client from `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
- `src/app/(auth)/login/page.tsx` signs in with Supabase Auth, redirects successful login to `/dashboard`, and redirects already-authenticated visitors away from `/login`.
- `src/app/(dashboard)/layout.tsx` delegates the dashboard route group to `src/components/DashboardAuthShell.tsx`.
- `src/components/DashboardAuthShell.tsx` loads the current Supabase Auth session/user on the client, calls `get_web_current_user_context`, redirects missing sessions to `/login`, renders a blocked-access screen for denied authenticated users, redirects hidden direct module routes back to `/dashboard`, and passes backend-filtered modules into the shell.
- `src/components/Sidebar.tsx` signs out through the browser Supabase client, redirects to `/login`, and renders only backend-visible modules.
- `src/components/AdminTopbar.tsx` renders the active module title and mobile module navigation from backend-visible modules only.
- `src/lib/auth.ts` defines the RPC-backed current-user context loader, fail-closed blocked states, and module visibility helper.
- `src/lib/modules.ts` is the current module registry and now includes stable module keys for future backend capability mapping.
- Most module pages are scaffold-only empty states. `vacancy` has a typed empty query placeholder and client-side table shell, but no real Supabase data contract.
- This repo currently has no local `supabase/migrations` directory. The frontend now expects the `get_web_current_user_context` RPC to exist in the Supabase authority project.

## Recommended Auth/RBAC Architecture

### Session Guard

- Guard the whole dashboard route group at `src/app/(dashboard)/layout.tsx`.
- The first implementation should use a server-capable Supabase session read at the App Router layout boundary.
- If no valid user session exists, redirect to `/login`.
- If a valid user session exists, load the user's safe web context before rendering the shell.
- Do not add module-by-module auth guards until a route-level RBAC contract is explicitly needed.
- Do not use frontend guards as authorization. They prevent confusing UI exposure only; Supabase RLS/RPC policies remain authoritative.

### Current User Context

Web needs one normalized current-user context before rendering dashboard navigation. The current frontend loader calls:

```ts
supabase.rpc("get_web_current_user_context")
```

The backend-backed context includes:

- Supabase Auth user id.
- Profile id and display metadata safe for the admin shell.
- Mobile-equivalent role identifier or role capability set.
- Group scope for modules that are group-limited.
- Account scope for modules that are account-limited.
- Module visibility/capability data derived from existing Mobile RBAC semantics.
- Status flags needed to block missing-profile, inactive, disabled, unauthorized, or failed access checks.

This context is currently fetched once in the dashboard shell wrapper and passed to shell components as presentation data. Client components may consume the already-loaded context, but they should not independently decide authority.

### RBAC Boundary

- Backend/RLS/RPC: authoritative permission checks, record visibility, mutations, workflow rules, and scope filtering.
- Frontend: navigation filtering, empty/blocked module states, labels, and route display decisions.
- Module pages: presentation only until their Supabase contracts and RLS are approved.
- Module visibility: driven by the existing `webModules` registry plus backend-provided capabilities, not by hardcoded role names in components.

## Required Backend Contracts

Required safe contract:

- A safe current-user profile/scope RPC named `get_web_current_user_context` that returns only the authenticated user's web-safe context.
- An optional `security_invoker` view can expose the same current-user context for read/query ergonomics after the RPC is in place, but the RPC should remain the canonical contract for shell bootstrap and fail-closed status handling.
- The contract must map the Supabase Auth user to the OHMployee profile/account identity used by Mobile.
- The contract must expose the existing Mobile role semantics without inventing web-only roles.
- The contract must expose group scope and account scope in the same shape Mobile uses, or in a documented web-safe projection.
- The contract must expose allowed module keys and capabilities so web does not duplicate role rules.
- The contract must fail closed for missing profiles, inactive accounts, disabled users, or unauthorized admin-panel access.

Recommended response shape for documentation and future typing:

```ts
type WebCurrentUserContext = {
  authUserId: string;
  profileId: string | null;
  displayName: string | null;
  email: string | null;
  role: {
    key: string | null;
    name: string | null;
  };
  active: boolean;
  status:
    | "active"
    | "authenticated_profile_missing"
    | "inactive"
    | "disabled"
    | "unauthorized_web";
  groupScope: {
    mode: "all" | "scoped" | "none";
    ids: string[];
  };
  accountScope: {
    mode: "all" | "scoped" | "none";
    ids: string[];
  };
  allowedModules: string[];
  capabilities: Record<string, string[]>;
};
```

This is a web projection shape, not a new database role model.

The current frontend accepts `access_status = "allowed"` as the only renderable shell state. It reads `allowed_module_keys` for navigation visibility and `module_capabilities` for sidebar/topbar display metadata only. If `access_status` is anything else, the dashboard route group stays blocked for the authenticated user.

Recommended database shape:

```sql
-- Canonical shell bootstrap contract.
select *
from public.get_web_current_user_context();

-- Optional read convenience once the RPC exists.
select *
from public.web_current_user_context;
```

The RPC/view should return exactly one row for an authenticated request. If the Auth user has no linked profile, is inactive/disabled, or is not authorized for web, the row should still identify the Auth user but return `active = false`, empty scopes, empty modules, empty capabilities, and the appropriate non-active `status`. For unauthenticated requests, the RPC should either return no rows or raise an unauthenticated error; the web shell treats both as `login`.

Recommended flattened SQL columns:

| Column | Type | Notes |
| --- | --- | --- |
| `auth_user_id` | `uuid` | Must equal `auth.uid()`. Never accept this as a caller argument. |
| `profile_id` | `uuid null` | Existing Mobile profile/user identity, if linked. |
| `full_name` | `text null` | Web-safe display name from existing profile semantics. |
| `email` | `text null` | Web-safe email, usually Auth email or approved profile email. |
| `role_key` | `text null` | Existing Mobile role key only. Do not create web-only roles. |
| `role_name` | `text null` | Existing Mobile display name only. |
| `active` | `boolean` | True only for valid, enabled, web-authorized users. |
| `status` | `text` | One of `active`, `authenticated_profile_missing`, `inactive`, `disabled`, `unauthorized_web`. |
| `group_scope_mode` | `text` | `all`, `scoped`, or `none`, derived from Mobile RBAC. |
| `group_scope_ids` | `uuid[]` | Empty unless scoped. |
| `account_scope_mode` | `text` | `all`, `scoped`, or `none`, derived from Mobile RBAC. |
| `account_scope_ids` | `uuid[]` | Empty unless scoped. |
| `allowed_module_keys` | `text[]` | Stable keys matching `src/lib/modules.ts`. |
| `capabilities` | `jsonb` | Object keyed by module key, each value an array of capability/action keys. |

Stable web module keys currently expected by the presentation layer:

`dashboard`, `cencom`, `vacancy`, `hr_emploc`, `plantilla`, `approvals`, `users`, `team_directory`, `notifications`, `reports`, `settings`, `more`.

Dashboard shell visibility must still be backend-authorized. If the backend chooses to allow a blocked shell for missing/inactive profiles, it should return no real modules and no capabilities; the frontend may show only a blocked shell or minimal dashboard route with no data widgets.

## RPC vs View Recommendation

Use both, but in this order:

1. Implement an RPC first as the canonical contract.
2. Add a `security_invoker = true` view only if web or future module queries benefit from selecting the same context shape.

The RPC is preferred for shell bootstrap because it can produce one normalized status row, centralize fail-closed behavior, avoid caller-provided user ids, and hide join complexity behind a stable function signature. It may use `security definer` only when required to bridge private RBAC/profile tables, and then only with a locked `search_path`, explicit `auth.uid()` checks, strict grants to `authenticated`, and no service-role exposure.

The view is useful for composable read access, but it must be `security_invoker` so RLS continues to apply as the authenticated user. The view should not become a bypass around Mobile RBAC tables. If the same table access cannot be made safe under invoker semantics, skip the view and keep the RPC as the only contract.

## Fail-Closed Behavior

- Unauthenticated: web redirects to `/login`; backend should return no context or an unauthenticated error.
- Authenticated but no linked profile: return `access_status = authenticated_profile_missing` or equivalent missing-profile status, no scopes, no modules, and no capabilities.
- Inactive profile/account: return `access_status = inactive`, no scopes, no modules, and no capabilities.
- Disabled user: return `access_status = disabled`, no scopes, no modules, and no capabilities.
- Authenticated and active but not web-authorized: return `access_status = unauthorized_web` or `unauthorized_role`, no scopes, no modules, and no capabilities.
- RPC failure, malformed payloads, missing module arrays, missing capability objects, and unknown statuses block the shell.
- Active and web-authorized: return `access_status = allowed`, Mobile-derived role, Mobile-derived scopes, `allowed_module_keys`, and `module_capabilities`.
- If an allowed user has an empty `allowed_module_keys` array, the frontend renders a dashboard-only shell. Missing or malformed module data is blocked.

The web app must treat unknown statuses, unknown roles, missing arrays, malformed capabilities, and hidden module keys as blocked. Frontend filtering is display-only; RLS/RPC checks still enforce authorization on every data query and mutation.

## Security Notes

- Do not expose service-role credentials or service-role-only tables to the browser.
- Do not accept `auth_user_id`, `profile_id`, `role_key`, group ids, or account ids as RPC arguments for current-user context.
- Derive the user exclusively from `auth.uid()`.
- Mirror existing Mobile RBAC semantics and authority tables; do not invent web-only roles or broader web scopes.
- Return only web-safe display fields and capability keys. Do not return policy internals, secret claims, raw permission rows, or unrelated user records.
- Keep group/account scope as filters for module data contracts. Scope visibility in the shell is not enough.
- Preserve RLS as the data access authority. A `security definer` RPC must be tightly scoped to this projection and should not expose generic table access.

## Module Visibility Matrix Draft

Visibility must be resolved from existing Mobile RBAC semantics and backend-provided capabilities. The frontend now filters navigation from backend `allowed_module_keys`; `module_capabilities` may be shown as display metadata only and must not become action authority. This is navigation/display filtering only and is not an authorization claim.

| Module | Route | Visibility rule draft | Scope input | Notes |
| --- | --- | --- | --- | --- |
| Dashboard | `/dashboard` | Visible to authenticated users who are authorized for the web admin panel. | Profile, role, group, account | Command-center shell only until summaries are contracted. |
| CENCOM | `/cencom` | Visible when backend exposes the CENCOM module capability. | Group/account as defined by Mobile | No business workflow yet. |
| Vacancy | `/vacancy` | Visible when backend exposes the Vacancy module capability. | Group/account as defined by Mobile | Current table query is placeholder-only and must remain RLS-backed when implemented. |
| HR Emploc | `/hr-emploc` | Visible when backend exposes the HR Emploc module capability. | Group/account as defined by Mobile | Scope must mirror Mobile. |
| Plantilla | `/plantilla` | Visible when backend exposes the Plantilla module capability. | Group/account as defined by Mobile | Position/staffing authority belongs in Supabase. |
| Approvals | `/approvals` | Visible when backend exposes the Approvals module capability. | Approval scope from backend | Approval routing must be backend-driven. |
| User Management | `/users` | Visible when backend exposes account/user administration capability. | Account scope | Web must not broaden account administration beyond backend scope. |
| Team Directory | `/team-directory` | Visible when backend exposes Team Directory capability. | Group/account as defined by Mobile | Directory record visibility must be RLS-filtered. |
| Notifications | `/notifications` | Visible when backend exposes Notifications capability. | User/profile scope | Delivery/read state remains backend-owned. |
| Reports | `/reports` | Visible when backend exposes Reports capability. | Group/account/report scope | Export/report access must be enforced server-side. |
| Settings | `/settings` | Visible when backend exposes Settings capability. | Account/admin scope | Configuration mutations require backend authority. |
| More | `/more` | Visible when at least one overflow module is visible or the shell needs an overflow landing. | Derived from visible module set | Should not reveal hidden modules. |

## Implementation Phases

1. Confirm Mobile RBAC contract names and scope semantics in Supabase.
2. Add a server-capable Supabase helper for App Router session reads once an SSR cookie adapter/package is approved.
3. Dashboard layout session guard and unauthenticated redirect to `/login` are implemented in the client auth shell.
4. Typed current-user context loading now calls `get_web_current_user_context`.
5. Stable module keys have been added to `webModules`; align them with backend capability keys when the contract is confirmed.
6. `Sidebar` and `AdminTopbar` now filter navigation from resolved module visibility.
7. Direct navigation to hidden modules redirects back to `/dashboard` in the client shell.
8. Replace placeholder module queries only after each module's data contract and RLS policy are approved.

## Exact Next Implementation Prompt

ID: OHM2026_1072-IMPL-1

Implement the safe Supabase current-user context backend contract for OHMployee Web.

Read only:
- `docs/state/web_auth_rbac_state.md`
- `docs/state/web_foundation_state.md`
- `.ai/current_state.md`
- `.ai/handoff.md`
- `src/lib/auth.ts`
- `src/lib/modules.ts`
- Existing Supabase migrations and Mobile RBAC schema/policy files in the authoritative Supabase repo.

Tasks:
1. Add a migration that creates the canonical current-user context RPC, preferably `public.get_web_current_user_context()`.
2. Derive the caller only from `auth.uid()`; do not accept caller-controlled user/profile/role/scope arguments.
3. Return one web-safe context row with:
   - `auth_user_id uuid`
   - `profile_id uuid null`
   - `full_name text null`
   - `email text null`
   - `role_key text null`
   - `role_name text null`
   - `active boolean`
   - `status text`
   - `group_scope_mode text`
   - `group_scope_ids uuid[]`
   - `account_scope_mode text`
   - `account_scope_ids uuid[]`
   - `allowed_module_keys text[]`
   - `capabilities jsonb`
4. Map role, active/disabled state, group scope, account scope, modules, and capabilities from the existing Mobile RBAC authority model.
5. Fail closed:
   - unauthenticated returns no row or an unauthenticated error;
   - missing profile returns `authenticated_profile_missing`, `active = false`, empty scopes/modules/capabilities unless dashboard blocked shell is explicitly backend-approved;
   - inactive returns `inactive`, `active = false`, empty scopes/modules/capabilities;
   - disabled returns `disabled`, `active = false`, empty scopes/modules/capabilities;
   - not web-authorized returns `unauthorized_web`, `active = false`, empty scopes/modules/capabilities.
6. Grant execution only to the authenticated role and keep anonymous callers blocked.
7. If useful after the RPC is safe, add `public.web_current_user_context` as a `security_invoker = true` view with the same shape.
8. Add migration comments/tests or SQL assertions that prove the contract does not expose other users, does not require service role, and preserves RLS/RBAC authority.

Constraints:
- Keep web as a thin admin-panel presentation layer.
- Keep Supabase/RLS/RPC as the authority.
- Do not invent new roles.
- Do not weaken RLS.
- Do not expose service-role credentials or service-role-only data.
- Do not implement frontend UI changes or module business features.
- Do not broaden module access beyond existing Mobile RBAC semantics.

Validation:
- Run the Supabase migration validation/test workflow available in the authoritative backend repo.
- Verify authenticated active users receive only their own context.
- Verify unauthenticated, missing-profile, inactive, disabled, and unauthorized-web cases fail closed.
- Update `docs/state/web_auth_rbac_state.md`, `docs/state/web_foundation_state.md`, `.ai/handoff.md`, and `.ai/current_state.md` with the final RPC/view names and status semantics after implementation.
