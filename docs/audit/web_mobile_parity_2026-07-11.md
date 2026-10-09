# Web/Mobile UX Parity Audit
**Audit ID:** ohm#7k3n9dqm  
**Date:** 2026-07-11  
**Auditor:** Antigravity (Read-Only Pass)  
**Scope:** Navigation/entry-flow structure per module — what loads first, what requires a selection step before data renders.

---

## Reference Pattern (Validated)

**Mobile pattern (target):** Selection-first, progressive disclosure.  
Example: Mobile Plantilla Directory → user selects Account first → sees employee list scoped to that account.

**Web anti-pattern (to flag):** Full list/table rendered immediately on page load with no prior selection step.  
Example: Plantilla Web currently loads the full unscoped employee roster on route entry.

> [!IMPORTANT]
> ADR-001 governs: HC, Vacancy, Plantilla, Coverage, Dashboard, CENCOM, Recruitment. Any recommended change touching these modules is flagged explicitly for compliance audit scope.

---

## Module 1: Dashboard (`/dashboard`)

### Current Web Entry Behavior
- **What loads on entry:** KPI summary row (5 cards) + Operational Analytics row + Security Dashboard section — all rendered immediately on page load with no selection step.
- **Data source:** `fn_dashboard_metrics()` + `fn_dashboard_operational_analytics()` — both `SECURITY DEFINER`, derive scope from `auth.uid()`. The backend enforces role-based scope silently; the frontend always fires both RPCs unconditionally on mount.
- **Affected files:**
  - [`dashboard/page.tsx`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/dashboard/page.tsx) — both `useQuery` hooks fire on component mount with no precondition.
  - [`src/lib/queries/dashboard.ts`](file:///d:/Projects/ohmployee-web/src/lib/queries/dashboard.ts)

### Mobile Entry Behavior
- Dashboard on mobile is similarly a summary/overview surface (not a list module), so no account-selection step is mandated. Mobile dashboard is an aggregate read, not a scoped-entity browsing screen.

### Gap Assessment
| Field | Value |
|-------|-------|
| **Gap (Y/N)** | **N — Intentional Design Difference** |
| **Gap Description** | Dashboard is inherently cross-module and aggregate. The backend derives scope from `auth.uid()`; no account selection is needed because the data is already scoped server-side. There is no browsable entity list to scope. |
| **Recommended Flow Change** | None. The dashboard correctly fires its RPCs on load; the backend is the scope boundary. |
| **ADR-001 Flag** | ⚠️ ADR-001 governs Dashboard. No flow change is recommended, so no compliance audit is needed. |
| **Complexity Estimate** | N/A |
| **Regression Risk** | Low — no change recommended. |

---

## Module 2: Vacancy (`/vacancy`)

### Current Web Entry Behavior
- **What loads on entry:** KPI MetricCard row (4 cards) + status tabs (Open/With Applicant/Rejected/Backout) + filter bar + full vacancy list table — all rendered immediately on page load, no prior Account selection step required.
- **Default list call:** `list_web_vacancies(p_status="Open", all other filters null, p_limit=25, p_offset=0)` fires on mount unconditionally.
- **Filter availability:** Account UUID and Group UUID fields exist in the filter bar as plain text inputs (not a preceding selection step) — the user can optionally type a UUID to narrow scope, but data loads without it.
- **Affected files:**
  - [`vacancy/page.tsx`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/vacancy/page.tsx) — `summaryQuery` and `listQuery` both fire on mount.
  - [`src/lib/queries/vacancy.ts`](file:///d:/Projects/ohmployee-web/src/lib/queries/vacancy.ts)
  - [`src/components/vacancy/VacancyTable.tsx`](file:///d:/Projects/ohmployee-web/src/components/vacancy/VacancyTable.tsx)

### Mobile Entry Behavior
- Mobile Vacancy navigation uses account-scoped entry: users navigate through their assigned account/group context before seeing the vacancy list. The scoped accounts come from the authenticated user profile, not from a preceding UI selection. Scoped roles (OM, HRCO, ATL, TL, Recruitment) see only vacancies within their `get_my_allowed_accounts()` boundary automatically.
- **Key difference:** Mobile scoping is implicit through role-based account assignment, not an explicit selection step presented to the user in the vacancy module itself. The "selection" is the session/profile context established at login.

### Gap Assessment
| Field | Value |
|-------|-------|
| **Gap (Y/N)** | **Partial — Presentation Gap, not a structural gap** |
| **Gap Description** | The web list fires immediately and the backend silently scopes via `auth.uid()`. However, the Account UUID filter is a raw text input (not a picker/selector) — admin users with broad access (SA, HA) see the full cross-account list immediately with no guided account selection. Mobile presents a more guided experience. For scoped roles (OM, HRCO), web already auto-scopes correctly via RPC. The gap is primarily for broad-access admin roles on web who may receive an overwhelming unfiltered list. |
| **Recommended Flow Change** | Add an Account selector (dropdown backed by user's allowed accounts) as a first-class filter with a default empty/placeholder state. Consider deferring the full list load until at least one Account is selected for roles with broad access (SA/HA). For scoped roles, continue firing on mount since scope is already implicit. This is a UX refinement, not a correctness issue. |
| **Affected Files** | `vacancy/page.tsx`, `vacancy.ts` query wrapper, `VacancyTable.tsx` |
| **ADR-001 Flag** | ⚠️ ADR-001 governs Vacancy. Any account-selection gate change must be reviewed under ADR-001 compliance scope before implementation. |
| **Complexity Estimate** | **M** — requires an accounts dropdown RPC or existing scope list, conditional query enabled state, and possible filter bar restructuring. |
| **Regression Risk** | Medium — disabling the automatic list load for broad-access users changes observable behavior. Risk of breaking existing admin workflows that rely on seeing all vacancies immediately. Must verify scoped-role path still auto-fires correctly. |

---

## Module 3: HR Emploc (`/hr-emploc`)

### Current Web Entry Behavior
- **What loads on entry:** KPI summary (4 cards) + queue tabs (Pending Review/For Correction/Compliance Complete/Pending Deletion/All History) + filter bar + full compliance queue table — all rendered immediately on page load, default queue is `"pending"`.
- **Default list call:** `list_web_hr_emplocs(p_queue="pending", all other filters null, p_limit=25)` fires on mount unconditionally.
- **Filter availability:** Account UUID and Group UUID as text inputs; assignment type and position dropdowns — all optional, no prior selection required.
- **Affected files:**
  - [`hr-emploc/page.tsx`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/hr-emploc/page.tsx) — both `summaryQuery` and `listQuery` (via `listParams`) fire on mount.
  - [`src/lib/queries/hr_emploc.ts`](file:///d:/Projects/ohmployee-web/src/lib/queries/hr_emploc.ts)
  - [`src/components/hr-emploc/HrEmplocTable.tsx`](file:///d:/Projects/ohmployee-web/src/components/hr-emploc/HrEmplocTable.tsx)

### Mobile Entry Behavior
- Mobile HR Emploc is a compliance queue within the hiring pipeline. The mobile experience typically routes through the pipeline linearly (Vacancy → Applicant → Emploc), meaning users arrive at an HR Emploc record with context already established from the upstream flow. There is no standalone "select Account, then see Emploc list" selection pattern documented; the module is more queue/workflow-oriented than directory-oriented.
- Scoped roles (HRCO, OM) are constrained by account assignment at the backend; the mobile queue already filters automatically based on user profile scope.

### Gap Assessment
| Field | Value |
|-------|-------|
| **Gap (Y/N)** | **Partial — same structural pattern as Vacancy** |
| **Gap Description** | Web loads the full pending queue immediately. For broad-access roles (SA, HA, HR Personnel), this produces a cross-account list on entry. Scoped roles auto-scope correctly via backend. Unlike Plantilla (directory) or Vacancy (slot list), HR Emploc is a workflow queue — the "list everything immediately" pattern is more defensible here since the queue is inherently operational and time-sensitive. However, an Account selector would still improve usability for broad-access admins. |
| **Recommended Flow Change** | Lower priority than Vacancy and Plantilla. Recommend adding an Account selector as a first-class filter, but do NOT defer list loading behind an account selection gate — the workflow queue must be immediately accessible. |
| **Affected Files** | `hr-emploc/page.tsx`, `hr_emploc.ts` query wrapper |
| **ADR-001 Flag** | Not in ADR-001 direct governance list. No compliance audit needed. |
| **Complexity Estimate** | **S** — account selector dropdown addition only; no load-gate change. |
| **Regression Risk** | Low — additive change only; no existing behavior removed. |

---

## Module 4: Plantilla (`/plantilla`)

### Current Web Entry Behavior
- **What loads on entry (Employee view — default):** KPI MetricCard row (4 cards) + view toggle (Employee/Store) + filter bar + full employee roster table — rendered immediately on page load with no Account selection step.
- **Default list call:** `list_web_plantilla_employees(p_active_state="active", all other filters null, p_limit=25)` fires on mount unconditionally.
- **Default summary call:** `get_web_plantilla_summary()` fires on mount unconditionally.
- **Inactive/Store views:** Also fire immediately when view toggle is changed; no account selection gate.
- **Filter availability:** Account UUID, Group UUID, Store ID, Employment Status, Deployment Type — all optional text/select inputs; no prior account selection required.
- **Affected files:**
  - [`plantilla/page.tsx`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/plantilla/page.tsx) — `summaryQuery`, `employeeQuery`, `storeQuery` all fire on mount/view-change.
  - [`src/lib/queries/plantilla.ts`](file:///d:/Projects/ohmployee-web/src/lib/queries/plantilla.ts)
  - [`src/components/plantilla/PlantillaDetailDrawer.tsx`](file:///d:/Projects/ohmployee-web/src/components/plantilla/PlantillaDetailDrawer.tsx)

### Mobile Entry Behavior
- **Confirmed gap (reference case from prompt):** Mobile Plantilla Directory requires Account selection first, then shows the employee list scoped to that account. This is the explicitly documented target pattern.
- Mobile requires: user picks Account → then sees employee list for that account.
- Web currently: loads all employees (across all scoped accounts) immediately, with Account as an optional post-load filter.

### Gap Assessment
| Field | Value |
|-------|-------|
| **Gap (Y/N)** | **YES — Confirmed gap, reference case** |
| **Gap Description** | Web loads the full multi-account employee roster immediately. Mobile requires Account selection before showing the scoped list. This is the exact anti-pattern identified in the prompt as the reference case. Even with backend scoping via `auth.uid()`, broad-access roles (SA, HA, HR Personnel) receive an unguided cross-account dump on load. |
| **Recommended Flow Change** | Gate the employee list and store staffing list behind an Account selection step. On entry, show KPI cards (which can still load) and an Account picker/selector. The list table should remain empty/unpopulated until an Account is selected. Once selected, fire `list_web_plantilla_employees` and `list_web_plantilla_store_staffing` with `p_account_id` pre-filled. For scoped roles with only one allowed account, auto-select it and fire immediately (no user interaction required). |
| **Affected Files** | `plantilla/page.tsx`, `plantilla.ts` query wrapper (add `enabled: !!accountId` to both list queries), possibly a new `AccountSelectorStep` component or reuse of existing filter dropdown. |
| **ADR-001 Flag** | ⚠️ ADR-001 governs Plantilla. This recommended change touches the primary entry flow of an ADR-001-governed module. **Flag for compliance audit before implementation.** |
| **Complexity Estimate** | **M** — requires conditional `enabled` logic on queries, Account selector with preloaded allowed accounts, and possible empty-state placeholder for the "no account selected" state. The detail drawer and mutation flows are unaffected. |
| **Regression Risk** | Medium-High — changes the default behavior from "load all on entry" to "gate behind selection." Risk areas: (1) scoped roles with one account must auto-fire without regression; (2) existing bookmark/deep-link behavior with `accountId` in URL params needs consideration; (3) the KPI summary cards continue loading but now show cross-account totals even when the list is gated — may cause confusion if KPI total doesn't match the filtered list. Must define whether summary also gates behind account selection or remains global. |

### Plantilla Account-First Change Scope Confirmation
The just-approved Plantilla account-first change (referenced in the prompt as "already validated") pertains to gating the employee list behind an Account selection. **Current code confirms this change has NOT yet been implemented** — `plantilla/page.tsx` lines 138–181 show both `summaryQuery` and `employeeQuery` firing on mount unconditionally, with no `enabled` condition tied to `accountId`. The approval to implement this pattern is confirmed in the prompt, but the code change is still pending.

---

## Module 5: CENCOM (`/cencom`)

### Current Web Entry Behavior
- **What loads on entry:** `ModuleEmptyState` placeholder component only. No data is loaded; no list, no KPI, no selection step.
- **Implementation status:** Scaffold/blank stub — `src/app/(dashboard)/cencom/page.tsx` is 6 lines and renders only `<ModuleEmptyState href="/cencom" />`.
- **No state document:** No `cencom_state.md` or `cencom_web_state.md` exists in `docs/state/`. The module is not documented beyond the route stub.
- **Affected files:**
  - [`cencom/page.tsx`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/cencom/page.tsx)

### Mobile Entry Behavior
- CENCOM on mobile is the Central Compliance monitoring surface tied to aging buckets (`1_15`, `16_30`, `31_60`, `61_120`, `gt121`), penalty exposure, and SLA tracking across vacancies and staffing. It is inherently cross-account/aggregate in nature. Mobile entry is likely account-filtered or role-scoped at the session level rather than presenting an explicit selection step.
- **Note:** Without a CENCOM state document, mobile UX specifics cannot be confirmed from available documentation.

### Gap Assessment
| Field | Value |
|-------|-------|
| **Gap (Y/N)** | **Cannot assess — module is scaffold-only** |
| **Gap Description** | Web CENCOM is a blank stub with no implementation. There is no navigation flow, data loading, or UX to audit against mobile. No state document exists to establish the target behavior. |
| **Recommended Flow Change** | Before implementing CENCOM web, create `docs/state/cencom_web_state.md` defining the mobile navigation pattern for CENCOM. Evaluate whether CENCOM is a cross-account aggregate (no account selection needed) or a scoped compliance drilldown (account selection first). |
| **ADR-001 Flag** | ⚠️ ADR-001 governs CENCOM. Any implementation must go through ADR-001 compliance review. |
| **Complexity Estimate** | **L** — full module implementation is out of scope; state document creation is **S**. |
| **Regression Risk** | None — no existing behavior to regress. |

---

## Module 6: Approvals (`/approvals`)

### Current Web Entry Behavior
- **What loads on entry:** `ModuleEmptyState` placeholder component only. No data is loaded; no list, no KPI, no selection step.
- **Implementation status:** Scaffold/blank stub — `src/app/(dashboard)/approvals/page.tsx` is 6 lines and renders only `<ModuleEmptyState href="/approvals" />`.
- **No state document:** No `approvals_state.md` or `approvals_web_state.md` exists in `docs/state/`.
- **Affected files:**
  - [`approvals/page.tsx`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/approvals/page.tsx)

### Mobile Entry Behavior
- Approvals on mobile is an inbox/queue of pending approval items spanning multiple modules (AH requests, transfers, separations, etc.). By nature, an approvals queue is cross-module and often cross-account. Mobile likely presents the queue immediately without an account-selection step, since approvers need visibility into all pending items regardless of account.
- **Note:** Without an Approvals state document, mobile UX specifics cannot be confirmed.

### Gap Assessment
| Field | Value |
|-------|-------|
| **Gap (Y/N)** | **Cannot assess — module is scaffold-only** |
| **Gap Description** | Web Approvals is a blank stub with no implementation. There is no navigation flow, data loading, or UX to audit against mobile. |
| **Recommended Flow Change** | Before implementing Approvals web, create `docs/state/approvals_web_state.md`. Approvals is likely a queue-first module (no account-selection gate needed) — similar to HR Emploc in nature — but this should be validated against mobile behavior before implementation. |
| **ADR-001 Flag** | Not in ADR-001 direct governance list. No compliance audit needed at this stage. |
| **Complexity Estimate** | **L** — full module implementation is out of scope; state document creation is **S**. |
| **Regression Risk** | None — no existing behavior to regress. |

---

## Summary Matrix

| Module | Web Entry | Mobile Pattern | Gap? | Complexity | ADR-001 | Regression Risk |
|--------|-----------|----------------|------|------------|---------|-----------------|
| **Dashboard** | Full KPI load on mount | Aggregate; no selection step | **N** | N/A | ⚠️ Yes (no change) | Low |
| **Vacancy** | Full list load on mount | Implicit scope via profile | **Partial** | M | ⚠️ Yes | Medium |
| **HR Emploc** | Full queue load on mount | Workflow queue; inline scope | **Partial** | S | No | Low |
| **Plantilla** | Full roster load on mount | **Account-select first** | **YES** | M | ⚠️ Yes | Medium-High |
| **CENCOM** | Scaffold only | Unknown (no docs) | **Cannot assess** | L | ⚠️ Yes | None |
| **Approvals** | Scaffold only | Unknown (no docs) | **Cannot assess** | L | No | None |

---

## Priority Recommendations (No-Fix Pass — Audit Only)

> [!IMPORTANT]
> These are audit findings only. No code changes are proposed or written in this pass. Each recommendation requires a separate implementation prompt.

1. **P1 — Plantilla (confirmed gap, reference case):** Implement account-selection gate before list load. ADR-001 review required. Separate implementation prompt needed.

2. **P2 — Vacancy (partial gap, broad-access UX):** Add Account selector as first-class filter. Evaluate whether to defer list load behind account selection for SA/HA roles. ADR-001 review required.

3. **P3 — HR Emploc (partial gap, lower priority):** Add Account selector as first-class filter. No load-gate recommended — queue must be immediately accessible. No ADR-001 review needed.

4. **P4 — CENCOM (scaffold):** Create state document before implementing. ADR-001 review required for any implementation.

5. **P5 — Approvals (scaffold):** Create state document before implementing. Evaluate account-selection pattern vs. queue-first pattern.

---

## Regression Guard Protocol — Active Flags

The following items are flagged under the Regression Guard Protocol. Do NOT fix; flag only.

| Flag | Module | Risk Description |
|------|--------|-----------------|
| **RGP-001** | Plantilla | Gating list behind account selection will change the current behavior where SA/HA/HR Personnel see the full roster immediately. Any scoped-role path (OM, HRCO with single account) must auto-fire to avoid breaking their workflow. |
| **RGP-002** | Plantilla | KPI summary currently loads cross-account totals regardless of account filter. After account-gate: if summary also gates, the 4 MetricCards will remain empty until account is selected — potential UX confusion. If summary does NOT gate, KPI totals may not match the filtered list — inconsistency risk. |
| **RGP-003** | Vacancy | Disabling the automatic list load for broad-access roles may break admin workflows that rely on seeing all vacancies on entry. Implementation must preserve scoped-role behavior. |
| **RGP-004** | Plantilla | Store view (`view === "store"`) also fires immediately. If the employee view gets an account-gate, the store view must receive the same treatment for UX consistency — but this doubles the regression surface. |
| **RGP-005** | Plantilla (Detail Drawer) | `PlantillaDetailDrawer` row-click wiring currently relies on `selectedPlantillaId` state. Any restructuring of the page entry flow must not break the drawer open/close/clear cycle. |

---

## ADR-001 Compliance Audit Scope

The following modules have recommended changes that touch ADR-001-governed behavior. A separate compliance audit must be scoped before implementation:

| Module | Recommended Change | ADR-001 Section |
|--------|--------------------|-----------------|
| Plantilla | Account-selection gate on list load | Plantilla |
| Vacancy | Account selector + possible load-gate for broad-access roles | Vacancy |
| CENCOM | State document creation + implementation planning | CENCOM |
| Dashboard | No change — noted for completeness | Dashboard |

---

*Audit completed: 2026-07-11T12:14 UTC+8. Read-only pass — no code changes, no migrations, no mutations.*
