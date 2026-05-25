# Web Mutation Workflow State & Architecture Specification

## 1. Scope & Purpose

This document defines the architecture for the **first write (mutation) workflow** in OHMployee Web. Until now every module (Vacancy, HR Emploc, Plantilla) is strictly read-only: KPI summaries, dense lists, and detail drawers consume `SECURITY DEFINER` read RPCs, and every `CapabilityActionBar` button is a disabled presentation hint driven by `row_capabilities`.

This pass does **not** implement any mutation. It selects the safest first write action, specifies its backend-authoritative contract, and fixes the exact phase order so implementation can proceed without re-deciding architecture mid-flight.

Core principle, unchanged: **Supabase is the absolute authority.** The browser never decides whether a mutation is allowed, never passes caller identity/role/scope as arguments, and never mutates raw tables. All writes flow through a single `SECURITY DEFINER` RPC that re-derives the caller from `auth.uid()`, re-checks capability + scope + record state, performs the transaction, and writes the audit trail.

---

## 2. Candidate Comparison

Four candidate first-mutations were considered. Each is scored on reversibility, blast radius, cross-module coupling, privilege level, and whether the read scaffold already exists.

| Candidate | State transition | Reversible? | Blast radius | Cross-module coupling | Min role | Read scaffold ready |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **HR Emploc deficiency tagging** | `Pending`/`For Review` → `For Correction` (+ writes `correction_reason` JSONB) | **Yes** — record can return to `For Review` after correction; tags can be re-tagged | **Low** — annotation + sideways/backward status flip inside one record | **None** — stays within HR Emploc | `hrPersonnel` | **Yes** (`canTagDeficiency`, drawer + checklist live) |
| HR Emploc correction review | `For Review` → `Complete` | Partially — `Complete` unlocks employee-no assignment & plantilla movement | Medium — forward gate that escalates the record toward irreversible deployment | None directly, but unlocks downstream deploy chain | `hrPersonnel` | Yes (`canReviewDeletion` distinct; review-approve flag not yet modeled) |
| Vacancy closure request | open vacancy → pending closure (request only) | Request reversible, but closure approval removes a slot | Medium — affects recruiting pipeline visibility & queues | Couples Vacancy → Applicant pipeline | `om`/scoped | Partial (`can_request_closure` hint, no closure UI form) |
| Plantilla deactivation / separation request | `Active` → `Pending Separation` → archive | **No** (on approval) — archives the active employee; Backout **reopens the Vacancy slot** | **High** — mutates the official active directory + can rewrite vacancy state | Strong: Plantilla → Vacancy reopen on backout | `om`/`hrco`/`hrPersonnel` | Partial (clearance panel renders, no submit form) |

### Why the others are deferred

- **Correction review** is a *forward* gate: moving a record to `Complete` is the precondition that unlocks `Assign Employee No` and `Move to Plantilla`. A wrong approval propagates toward irreversible deployment. It is the natural *second* mutation (it closes the same correction loop tagging opens), but it carries more downstream consequence than tagging.
- **Vacancy closure** crosses the Vacancy→Applicant boundary and changes operational queue visibility; the read drawer exposes only a capability hint, not a closure form.
- **Plantilla deactivation** has the largest blast radius in the whole system: on approval it archives an active employee and, for Backout, **automatically reopens the original vacancy** (`vacancies.status = 'Open'`). It is explicitly the *last* mutation to wire, not the first.

---

## 3. Recommended First Mutation

**HR Emploc Deficiency Tagging** (`Pending`/`For Review` → `For Correction`).

### Rationale

1. **Most reversible.** Tagging sends a record *backward/sideways* into the correction loop. The canonical cycle already supports the return path (`For Correction` → HRCO uploads → `For Review`), so a mistaken tag is fully recoverable without admin intervention or data archival.
2. **Lowest blast radius.** It writes a `correction_reason` JSONB block and flips one status field on a single record. It does not assign employee numbers, does not move records to Plantilla, does not archive anything, and does not touch the Vacancy or Plantilla tables.
3. **Zero cross-module coupling.** The effect is contained entirely within the HR Emploc record. No vacancy reopens, no directory rows change.
4. **Backend hooks already exist.** The correction notification trigger (`trg_notify_hr_emploc_correction_tagged`) is already wired in the authoritative repo, so the action plugs into an established notification rail rather than inventing one.
5. **Read scaffold is complete.** `HrEmplocDetailDrawer.tsx` already renders the requirements checklist, the `correction_reason`-driven deficiency states, the `Tag Deficiency (HR Compliance)` action (currently disabled), and the `canTagDeficiency` capability flag is already normalized in `src/lib/queries/hr_emploc.ts`. Only the enable + form + mutation wiring is missing.
6. **Least-privileged actor.** `hrPersonnel` performs compliance annotation, not an admin-only state escalation. The action does not unlock any further capability.

This makes it the ideal proving ground for the entire web mutation pattern (modal → RPC → invalidation → audit) at minimum risk.

---

## 4. Mutation Architecture (Backend-Authoritative)

### 4.1 Backend RPC / Action Contract

```sql
CREATE OR REPLACE FUNCTION public.tag_web_hr_emploc_deficiency(
  p_hr_emploc_id  uuid,
  p_deficiencies  jsonb,            -- { "<issue_type_key>": "<note text>", ... }
  p_remarks       text DEFAULT NULL -- optional free-text HR compliance remark
)
RETURNS jsonb                       -- result envelope, see below
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$ ... $$;
```

Result envelope (single JSONB row, no raw record leakage):

```json
{
  "ok": true,
  "hr_emploc_id": "uuid",
  "new_hr_status": "For Correction",
  "correction_reason": { "nbi_clearance": "blurry scan", "birth_certificate": "missing PSA seal" },
  "tagged_at": "2026-05-25T08:00:00Z"
}
```

Contract rules:

- **Identity**: derived only from `auth.uid()`. No `profile_id`, `role_key`, `account_id`, or `group_id` accepted as authority arguments.
- **Grants**: `EXECUTE` granted to `authenticated` only; revoked from `PUBLIC` and `anon`.
- **Inputs**: `p_deficiencies` keys must be validated against the canonical `hr_emploc_issue_types` set; unknown keys are rejected. Values are trimmed notes. `p_remarks` is optional and length-bounded.
- **Single transaction**: capability re-check → scope re-check → record-state precheck → write `correction_reason` + set `hr_status = 'For Correction'` → insert audit log row → (trigger fires notification). All-or-nothing.
- **No business logic in the browser.** The frontend supplies only the selected issue keys, notes, and the record id.

### 4.2 Validation Rules (enforced in the RPC, fail closed)

1. Record exists and is visible under the caller's RLS scope (else `access_denied`).
2. Caller has `hr_emploc.tag_deficiency` capability (`hrPersonnel`); all other roles rejected.
3. `hr_status` is currently `Pending` or `For Review` (else `invalid_state`).
4. `status = 'Pending Emploc'` (record not already deployed/transferred).
5. **No active deletion request** — record must not be `Pending Deletion` (the edit-lock overlay). Blocked otherwise.
6. `employee_no IS NULL` is *not* required (a record can be For Review with a number), but `Complete`/`Transferred`/`Rejected`/`Moved to Plantilla` states are rejected.
7. `p_deficiencies` is a non-empty object with at least one valid `hr_emploc_issue_types` key.

### 4.3 Capability Gating

- **Module gate**: `module_capabilities.hr_emploc` must expose tag capability for the role (presentation only).
- **Row gate**: `row_capabilities.can_tag_deficiency` (normalized to `canTagDeficiency`) governs button visibility/enablement.
- **Authority**: the RPC re-derives and re-checks capability server-side. Frontend gating is ergonomics only; the RPC is the boundary.
- Button is enabled only when `detail.rowCapabilities.canTagDeficiency === true && !isPendingDeletion`.

### 4.4 Audit Logging Requirements

- The RPC must insert an immutable audit event into the existing HR Emploc audit log surface that feeds `audit_logs_timeline` (rendered by the drawer's Activity History Trail).
- Event fields: `event_label = "Correction Tagged"`, `event_description` summarizing the tagged deficiency keys (no PII), `profile_name` resolved from `auth.uid()`, `created_at = now()`.
- The audit write is inside the same transaction as the status change — never best-effort/after-the-fact.
- The existing notification trigger (`trg_notify_hr_emploc_correction_tagged`) is the alert rail to the coordinator; it is not re-implemented client-side.

### 4.5 Rollback / Blocked States

- **No optimistic UI for the first mutation.** The modal stays open and pending until the RPC resolves; there is no client-side rollback to manage.
- **Blocked (pre-flight)**: if the record is `Pending Deletion`, already `Complete`/`Transferred`/`Rejected`, or out of scope, the action is disabled in the UI and additionally rejected by the RPC.
- **Reversal path**: a wrongly tagged record is corrected through the existing loop — the standard correction-review action (the planned *second* mutation) flips `For Correction` → `For Review`. Tagging does not need its own destructive undo.
- **Failure**: on any RPC error the status flip does not occur (transaction rolled back server-side); the UI surfaces the error and leaves the record untouched.

---

## 5. Required Frontend UI States

The mutation reuses the existing drawer; it adds one confirmation modal and the wiring around the already-present `Tag Deficiency` action button.

1. **Disabled (default)** — current state. Button shows as an unexposed capability hint when `canTagDeficiency` is false or record is locked.
2. **Enabled** — `canTagDeficiency === true && !isPendingDeletion`. Button becomes clickable.
3. **Confirmation modal** — opens on click: requirement/issue-type checkboxes (sourced from the canonical issue-type list), a note field per selected deficiency, an optional HR remarks textarea, and Confirm/Cancel. Confirm disabled until ≥1 deficiency selected.
4. **Submitting** — Confirm shows a spinner; modal inputs disabled; no second submit allowed (mutation `isPending`).
5. **Success** — modal closes, toast/inline confirmation, drawer + list + KPIs refetch (see §6); the record now shows `For Correction` and the new tags.
6. **Error** — modal stays open with an inline message. `access_denied` → "You are not authorized…"; `invalid_state` → "This record can no longer be tagged…"; validation → field-level message; retryable → retry affordance. Maps through the existing `HrEmplocDataError` kind discriminator extended with an `invalid_state` kind.

### Error handling alignment

Extend the existing `HrEmplocDataError` kinds (`access_denied | retryable`) with an `invalid_state` kind for state-precondition rejections (HTTP/Postgres state errors that are not RLS denials). The existing `getErrorKind` PostgrestError classifier is reused and extended; mutation errors are not optimistically swallowed.

---

## 6. Query Invalidation Strategy

On mutation success, invalidate (via `queryClient.invalidateQueries`) exactly the read surfaces affected by the status flip:

1. `["hr-emploc-detail", hrEmplocId]` — the open drawer reflects `For Correction` and new tags.
2. The HR Emploc **list** query key (all queues) — the row moves from `Pending Review` into the `For Correction` queue.
3. The HR Emploc **summary** query key — `Total Processing` decrements and `Action Needed` increments.

Do not invalidate Vacancy or Plantilla query caches — this mutation has no effect on those modules. No optimistic cache mutation for the first action; rely on refetch for correctness.

---

## 7. Exact Phase Order

Implementation must proceed strictly in this order. Each phase is independently verifiable and no later phase begins until the prior one is confirmed.

1. **Backend RPC** — implement and apply `public.tag_web_hr_emploc_deficiency(...)` in the authoritative Supabase repo. Includes `SECURITY DEFINER`, locked `search_path`, `auth.uid()` identity, capability/scope/state checks, transactional status + `correction_reason` write, audit insert, grants. Validate with SQL tests across roles before any frontend change.
2. ✅ **Frontend action contract** — typed `tagWebHrEmplocDeficiency(...)` wrapper added to `src/lib/queries/hr_emploc.ts`. `TagDeficiencyParams` and `TagDeficiencyResult` types added. `HrEmplocDataErrorKind` extended with `invalid_state`; `getErrorKind` maps `P0001` → `invalid_state` and `42501` → `access_denied`.
3. ✅ **Disabled button becomes enabled** — `CapabilityActionBar` updated to enable buttons when `isAvailable && !!onClick`. The "Tag Deficiency" action in `HrEmplocDetailDrawer.tsx` is gated on `canTagDeficiency && !isPendingDeletion`; all other actions remain disabled (no `onClick`).
4. ✅ **Confirmation modal** — `TagDeficiencyModal` sub-component added in `HrEmplocDetailDrawer.tsx`. Contains issue-type checkboxes + per-issue note inputs + optional remarks textarea. Wired to `useMutation` calling `tagWebHrEmplocDeficiency`. Submit disabled until ≥1 issue selected. Inputs and submit locked during `isPending`. Inline error display for `access_denied`, `invalid_state`, and `retryable` kinds.
5. ✅ **Success invalidation** — on success, invalidates `["hr-emploc-detail", hrEmplocId]`, `["hr-emploc-list"]`, and `["hr-emploc-summary"]` via `queryClient.invalidateQueries`. Modal closes via `onSubmitted()`. No optimistic UI.
6. ✅ **State-doc update** — this doc, `.ai/current_state.md`, and `.ai/handoff.md` updated. Audit event rendering in the drawer timeline depends on the backend RPC inserting the audit row; the frontend timeline already consumes `audit_logs_timeline` from `get_web_hr_emploc_detail`.

---

## 8. Implementation Status (OHM2026_1109)

Frontend phases 2–5 are complete and validated (`pnpm lint` clean, `pnpm build` clean).

**Files changed:**
- `src/lib/queries/hr_emploc.ts` — added `invalid_state` error kind, `P0001` classifier, `TagDeficiencyParams`, `TagDeficiencyResult`, `tagWebHrEmplocDeficiency`
- `src/components/shared/CapabilityActionBar.tsx` — enabled button when `isAvailable && !!onClick`
- `src/components/hr-emploc/HrEmplocDetailDrawer.tsx` — `isTagModalOpen` state, canTag guard, wired `onClick`, `TagDeficiencyModal` sub-component

**Remaining prerequisite:** Backend RPC `public.tag_web_hr_emploc_deficiency(...)` must be implemented in the authoritative Supabase repo (Phase 1 above) before the mutation can execute end-to-end.

**Next mutation:** HR Emploc correction review (`For Correction` → `For Review` → `Complete`) as specified in §2.

---

## 9. Exact Next Implementation Prompt

ID: OHM2026_1107-IMPL-1

Implement the backend-authoritative Supabase RPC for the OHMployee Web first mutation: HR Emploc deficiency tagging.

Read only:
- `docs/state/web_mutation_workflow_state.md`
- `docs/state/hr_emploc_web_state.md`
- `docs/state/web_auth_rbac_state.md`
- `.ai/current_state.md`
- `.ai/handoff.md`
- Existing Supabase HR Emploc migrations/views/RPCs only, especially `list_web_hr_emplocs`, `get_web_hr_emploc_detail`, `hr_emploc_issue_types`, the HR Emploc audit log surface feeding `audit_logs_timeline`, and `trg_notify_hr_emploc_correction_tagged`.
- Existing RBAC/scope helpers only: `get_web_current_user_context`, `i_have_full_access`, `get_my_allowed_accounts`, `user_scopes`, and the role permission matrix.

Tasks:
1. Add a migration in the authoritative Supabase repo; do not edit frontend code.
2. Create `public.tag_web_hr_emploc_deficiency(p_hr_emploc_id uuid, p_deficiencies jsonb, p_remarks text default null)` as `SECURITY DEFINER` with `SET search_path = public`, granted to `authenticated`, revoked from `PUBLIC`/`anon`.
3. Derive caller identity exclusively from `auth.uid()`. Accept no role/profile/account/group authority arguments.
4. Enforce, in order, failing closed: record visible under caller RLS scope; caller is `hrPersonnel` with tag capability; `hr_status IN ('Pending','For Review')`; `status = 'Pending Emploc'`; record not `Pending Deletion`; not `Complete`/`Transferred`/`Rejected`/`Moved to Plantilla`; `p_deficiencies` non-empty with valid `hr_emploc_issue_types` keys.
5. In one transaction: write `correction_reason` JSONB, set `hr_status = 'For Correction'`, insert an immutable audit event (`Correction Tagged`, deficiency-key summary with no PII, actor from `auth.uid()`, `now()`); allow the existing notification trigger to fire.
6. Return the JSONB envelope `{ ok, hr_emploc_id, new_hr_status, correction_reason, tagged_at }`; never return raw sensitive columns or contact PII.
7. Add validation SQL proving: unauthenticated blocked; non-`hrPersonnel` blocked; out-of-scope record blocked; `Pending Deletion`/`Complete` records rejected with a clear state error; valid `hrPersonnel` tag succeeds and writes exactly one audit row.

Constraints:
- Do not edit frontend code in this prompt.
- Do not weaken RLS or grants. Do not invent statuses or roles. Do not add caller-controlled authority arguments.
- Preserve Supabase as the business authority and reuse the existing correction cycle and notification trigger.

Validation:
- Run the authoritative Supabase migration validation/test workflow.
- Test as Super Admin, Head Admin, hrPersonnel (in/out of scope), Encoder, OM/HRCO, Viewer, and unauthenticated caller.
- Verify list queue movement (`Pending Review` → `For Correction`) and summary count deltas match the same scoped base query.

After this RPC is verified, proceed to OHM2026_1107-IMPL-2 (frontend wrapper + modal + invalidation) per the phase order in §7.
