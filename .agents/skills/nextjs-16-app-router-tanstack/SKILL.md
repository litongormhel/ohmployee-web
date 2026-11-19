---
name: nextjs-16-app-router-tanstack
description: >
  Architectural and coding conventions for OHMployee Web using Next.js 16 App
  Router (Turbopack), React 19, TypeScript, and TanStack Query v5 with Supabase.
  Use whenever creating or refactoring routes, modals, detail drawers, query
  hooks in src/lib/queries/, cache invalidation matrices, SOLID presentation
  components, or RBAC route/action guards.
license: MIT
---

# Next.js 16 App Router + React 19 + TanStack Query v5 (`ohmployee-web`)

Standardizes how routes, data fetching, mutations, cache invalidation, and UI modals/drawers are built in `d:\Projects\ohmployee-web`.

## 1. Next.js 16 & React 19 Conventions

1. **Async Dynamic Route APIs (Next.js 16 Breaking Change)**:
   - In Next.js 16 App Router, `params` and `searchParams` passed to Page/Layout/Route Handlers are Promises (or accessed in client components via `useParams()` / `useSearchParams()`).
   - When using `useSearchParams()` in a Client Component, ensure a `<Suspense>` boundary wraps the consumer so `npm run build` (Turbopack static prerendering) never fails.
2. **Node `--test` & Turbopack Dual Compatibility**:
   - Shared utility and RBAC files (`src/lib/rbac.ts`, `src/lib/utils/*.ts`) are executed directly by Node's native test runner (`node --test`) AND compiled by Next.js Turbopack.
   - Prefer `as const` objects + union type aliases over TypeScript runtime `enum` blocks when modules are imported by `.test.mjs` suites, and use explicit `.ts` extensions on relative `import type` statements where required by Node ESM.
3. **Strict Dependency Inversion in UI Components (SOLID Phase 1–4)**:
   - **Never** instantiate `createClient()` directly inside page components, modals, or drawers (`src/app/**` or `src/components/**`).
   - All Supabase `.from(...)` and `.rpc(...)` calls belong exclusively in `src/lib/queries/<domain>.ts` (or domain sub-packages like `src/lib/queries/vacancy/`), exposed to components via typed async functions and TanStack Query hooks (`useQuery`, `useMutation`).
4. **Segregated Modal & Drawer Contracts (`src/types/modal.ts`, `src/types/display.ts`)**:
   - Modals must extend `BaseModalProps`, `ActionModalProps<TResult>`, or `EntityModalProps<TEntity, TResult>` from `src/types/modal.ts`.
   - Drawers must extend `BaseDrawerProps` and compose `DetailDrawer.tsx`.
   - Pass lean display summaries (`EmployeeIdentitySummary`, `StoreStaffingSummary`) instead of coupling modals to monolithic parent table payloads.

## 2. Query Layer & PostgREST Error Guard (`src/lib/queries/*.ts`)

Every query function in `src/lib/queries/` must follow three rules:

1. **Mandatory PostgREST Error Logging**:
   ```ts
   const { data, error } = await supabase.rpc('my_rpc_name', { p_id: id });
   if (error) {
     console.error('[PostgREST Schema Error] my_rpc_name:', error);
     throw error;
   }
   ```
   Never use empty `catch {}` blocks that hide schema mismatches or RLS denials.
2. **Physical Column Pre-Check**:
   - Before writing `.select('id, stores(id, store_name, area_city, area_province, island_group)')`, verify every column against `PHYSICAL_TABLES` in `scripts/check-sql-contracts.mjs`.
3. **Re-Export Facade Pattern for Large Domains**:
   - When a query file exceeds ~1,500 lines (e.g., `src/lib/queries/vacancy.ts`), split it into focused domain modules (`types.ts`, `*Helpers.ts`, `*Listing.ts`, `*Mutations.ts`, `*Export.ts`) under `src/lib/queries/<domain>/` and keep `src/lib/queries/<domain>.ts` as a clean re-export facade so imports never break.

## 3. Authoritative TanStack Query Cache Invalidation Matrix

Cross-module mutations in OHMployee affect derived counters across multiple screens (ADR-001 Rules 1, 2, 3, 6). Whenever a `useMutation` succeeds, invalidate the full blast radius:

| Mutation Domain | Required `queryClient.invalidateQueries` Keys |
|---|---|
| **Headcount Requests (Submit / Approve / Reject)** | `['request-category-counts']`, `['my-requests']`, `['headcount-requests']`, `['hc-request-stores']`, `['plantilla']`, `['vacancies']`, `['stores']`, `['cencom']` |
| **Vacancy Pipeline & Closures** | `['vacancies']`, `['vacancy-detail']`, `['vacancy-summary']`, `['vacancy-closure-requests']`, `['request-category-counts']`, `['my-requests']`, `['plantilla']`, `['hr-emploc']` |
| **HR Emploc Lifecycle (`submit`, `correction`, `assign_emploc`, `deploy`)** | `['hr-emploc']`, `['hr-emploc-detail']`, `['hr-emploc-counts']`, `['plantilla']`, `['vacancies']`, `['cencom']`, `['dashboard']` |
| **Plantilla Lifecycle (Status, Separation, Deactivation, Schedule, Store Assign)** | `['plantilla']`, `['plantilla-detail']`, `['web-plantilla-summary']`, `['store-staffing']`, `['plantilla-slot-detail']`, `['slot-history']`, `['vacancies']`, `['request-category-counts']` |
| **Coverage Groups & Reliever Endorsements** | `['request-category-counts']`, `['reliever-endorsements']`, `['coverage-group-requests']`, `['workforce-assignments']`, `['coverage-groups']`, `['plantilla']`, `['vacancies']`, `['stores']`, `['cencom']` |
| **RBAC Permission Overrides (`/rbac`)** | `['rbac-all-roles-effective-matrix']`, `['effective-permission-matrix']`, `['web-current-user-context']` |

## 4. State Preservation & Navigation Invariants

1. **Plantilla Full-Page Profile Return Context (Permanent Rule #5)**:
   - Navigating from `/plantilla` to `/plantilla/[id]` and clicking `← Back to Plantilla` must preserve all URL query parameters (`tab`, `view` (`table` vs `cards`), `search`, `account`, `page`).
2. **Table / Cards Universal View Toggle (Permanent Rule #3)**:
   - Any roster change in `/plantilla` must support both `PlantillaTableViews.tsx` and `PlantillaCardViews.tsx` across all 6 tabs (`Active`, `On-Leave`, `Vacancy`, `Floating`, `Deactivation`, `Inactive`) without crash or missing props.
3. **Role-Scoped Action Column Suppression**:
   - In operational tables (e.g., `HrEmplocTable.tsx`, `PlantillaTableViews.tsx`), hide the entire `Actions` column header and sticky cells when the current user role has zero valid capabilities on that queue/tab (or per Permanent Rule #3 on the Plantilla Deactivation tab).
