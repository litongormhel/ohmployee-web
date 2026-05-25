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

## 8. Implementation Status (OHM2026_1109 → OHM2026_1112)

Frontend phases 2–5 are complete and validated (`pnpm lint` clean, `pnpm build` clean).

**Files changed:**
- `src/lib/queries/hr_emploc.ts` — added `invalid_state` error kind, `P0001` classifier, `TagDeficiencyParams`, `TagDeficiencyResult`, `tagWebHrEmplocDeficiency`
- `src/components/shared/CapabilityActionBar.tsx` — enabled button when `isAvailable && !!onClick`
- `src/components/hr-emploc/HrEmplocDetailDrawer.tsx` — `isTagModalOpen` state, canTag guard, wired `onClick`, `TagDeficiencyModal` sub-component

**Backend deployed:** Migration `20260607000004` applies `public.tag_web_hr_emploc_deficiency(...)` remotely. The mutation executes end-to-end.

**Next mutation:** HR Emploc correction review (`For Review` → `Complete` / `For Correction`) — architected in **Part II (§10–§18)**. Frontend wired (OHM2026_1112). Backend RPC applied remotely via migration `20260609000000`. Remaining gap: `can_review_correction` must be present in the `get_web_hr_emploc_detail` row capability payload.

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

---

# PART II — Second Mutation: HRCO Correction Review (OHM2026_1110)

## 10. Scope & Position in the Loop

The first mutation (Part I) **opens** the correction loop by sending a record `Pending`/`For Review` → `For Correction`. This second mutation **closes** that same loop. It is the *finalization* step described in `hr_emploc_web_state.md §6.4`: after the field coordinator (HRCO) uploads corrected documents, HR Personnel reviews the resubmission and decides its fate.

### 10.1 Reconciling the loop states

The canonical correction cycle has four states and three transitions; only the last transition is in scope here:

```
[Pending] / [For Review*]
     │ (1) Tag Deficiency — Part I mutation (hrPersonnel)
     ▼
[For Correction] ──────────────────────────────────────────┐
     │ (2) HRCO uploads corrected docs — OUT OF SCOPE        │
     │     (separate ops/Mobile RPC; not a web mutation)     │
     ▼                                                       │
[For Review] ──── (3) THIS MUTATION (hrPersonnel) ───────────┤
     │                                                       │
     ├── approve ──▶ [Complete]   (all deficiencies resolved)│
     └── return  ──▶ [For Correction] ──────────────────────┘   (residual deficiencies remain)
```

> The task brief labels this "For Correction → Complete". Precisely, the **reviewable** state is `For Review` — the state a record enters *after* the HRCO has resubmitted. `For Correction` records are still awaiting upload and are not yet reviewable. The end-to-end span is `For Correction` →(HRCO upload, out of scope)→ `For Review` →(this mutation)→ `Complete`. Transition (2) is performed by ops roles via an existing/Mobile RPC and is explicitly **not** wired as a web mutation here.

### 10.2 Why this is the correct second mutation

- It is the **natural inverse** of the first mutation and reuses the exact same surfaces: the `correction_reason` JSONB, the requirements checklist, the attachments list, and the audit timeline. No new read scaffold is required.
- It is a **forward gate**: approving to `Complete` is the precondition that unlocks `Assign Employee No` and `Move to Plantilla`. It therefore carries more downstream consequence than tagging and must be modeled with stricter approval semantics (see §15).

---

## 11. Backend RPC / Action Contract

```sql
CREATE OR REPLACE FUNCTION public.review_web_hr_emploc_correction(
  p_hr_emploc_id   uuid,
  p_decision       text,                 -- 'approve' | 'return'
  p_resolved_keys  text[]  DEFAULT NULL,  -- deficiency keys the reviewer affirms resolved
  p_remarks        text    DEFAULT NULL   -- optional reviewer note (bounded length)
)
RETURNS jsonb                            -- result envelope, see below
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
  "decision": "approve",
  "new_hr_status": "Complete",
  "correction_reason": {},
  "reviewed_at": "2026-05-25T09:00:00Z"
}
```

On `return`, `new_hr_status = "For Correction"` and `correction_reason` carries the **residual** (still-deficient) keys only.

Contract rules:

- **Identity**: derived only from `auth.uid()`. No `profile_id`, `role_key`, `account_id`, or `group_id` accepted as authority arguments.
- **Grants**: `EXECUTE` granted to `authenticated` only; revoked from `PUBLIC`/`anon`.
- **`p_decision`** is a closed enum (`'approve' | 'return'`); any other value → `invalid_state`.
- **`p_resolved_keys`** must be a subset of the keys currently present in `correction_reason`. Unknown keys are rejected (`invalid_state`). The browser asserts *which* deficiencies it considers resolved; the backend enforces the *completeness invariant*, never the quality judgment.
- **Single transaction**: capability re-check → scope re-check → state precheck → decision branch (approve | return) → status write + `correction_reason` rewrite → audit insert → notification trigger. All-or-nothing.
- **No business logic in the browser.** The frontend supplies only the record id, the decision, the resolved-key set, and an optional remark.

---

## 12. Validation Rules (enforced in the RPC, fail closed)

Common preconditions (both decisions):

1. Record exists and is visible under the caller's RLS scope (else `access_denied`).
2. Caller holds the **correction-review capability** (`hrPersonnel`; `superAdmin` retains global override). All other roles rejected. Per the role matrix, `hrPersonnel` performs "correction approvals, complete documentation review".
3. `hr_status = 'For Review'` (the only reviewable state). `Pending`, `For Correction`, `Complete`, `Transferred`, `Rejected`, `Moved to Plantilla` are all rejected with `invalid_state`.
4. `status = 'Pending Emploc'` (record not deployed/transferred).
5. **No active deletion request** — record must not be `Pending Deletion` (edit-lock overlay). Blocked otherwise.

Decision-specific:

- **`approve`** (strict model — see §15):
  6a. Every key currently in `correction_reason` must appear in `p_resolved_keys`. If any tagged deficiency is unaffirmed → reject with `invalid_state` ("unresolved deficiencies remain"). Approval with outstanding deficiencies is impossible.
  7a. *(Recommended)* at least one correction attachment exists in `hr_emploc_correction_attachments` for the record — proof that the HRCO actually resubmitted. A `For Review` record with zero attachments is suspect and should be returned, not approved.
- **`return`**:
  6b. `residual = (keys of correction_reason) − p_resolved_keys` must be **non-empty** (a fully-resolved set is an `approve`, not a `return`). If `p_resolved_keys` covers everything, reject and instruct to use `approve`.

---

## 13. Capability Gating

- **Row gate**: a new `row_capabilities.can_review_correction` (normalized to `canReviewCorrection`) governs button visibility/enablement. This is **distinct** from `can_review_deletion` (which gates the deletion-request approval flow) and from `can_tag_deficiency` (Part I). The backend must add `can_review_correction` to the `get_web_hr_emploc_detail` capability payload for `hrPersonnel` on `For Review` records.
- **Authority**: the RPC re-derives and re-checks capability server-side. Frontend gating is ergonomics only.
- Buttons are enabled only when `detail.rowCapabilities.canReviewCorrection === true && hrStatus === 'For Review' && !isPendingDeletion`.

---

## 14. Audit Logging, Notification, Invalidation, Rollback

### 14.1 Audit logging
- One immutable audit event per call, inside the same transaction as the status change.
- **approve** → `event_label = "Correction Approved"` (or "Compliance Completed"), description summarizing the resolved deficiency keys (no PII), actor from `auth.uid()`, `created_at = now()`.
- **return** → `event_label = "Correction Returned"`, description listing the residual deficiency keys (no PII).
- Never best-effort/after-the-fact; rolls back with the transaction on any failure.

### 14.2 Notification
- **return** re-fires the existing correction-notification rail (`trg_notify_hr_emploc_correction_tagged` or equivalent) so the HRCO is alerted that documents still need fixing. Do not re-implement notifications client-side.
- **approve** may fire a "compliance complete" notification if such a trigger exists; otherwise no new rail is invented.

### 14.3 Query invalidation (on success)
Invalidate exactly the affected read surfaces:
1. `["hr-emploc-detail", hrEmplocId]` — drawer reflects the new status and cleared/residual deficiencies.
2. `["hr-emploc-list"]` — the row moves between queues (`Pending Review`→`Compliance Complete` on approve; `Pending Review`→`For Correction` on return).
3. `["hr-emploc-summary"]` — `Total Processing` decrements; on approve `Ready to Deploy` increments; on return `Action Needed` increments.

Do **not** invalidate Vacancy or Plantilla caches. No optimistic cache mutation; rely on refetch.

### 14.4 Blocked states & rollback
- **Blocked (pre-flight)**: `Pending Deletion`, any non-`For Review` `hr_status`, out-of-scope, or `status != 'Pending Emploc'` → action disabled in UI and rejected by the RPC.
- **No optimistic UI.** The confirmation modal stays open until the RPC resolves.
- **`return` is the in-loop safety valve**: a record reviewed too hastily can be returned instead of approved; this is fully reversible (re-enters the correction loop).
- **`approve` (→ `Complete`) has no backward web path.** The Part I tagging RPC explicitly *rejects* `Complete` records, so a record cannot be re-tagged once Complete. Reopening a `Complete` record is **out of scope** and would require a separate privileged admin action. This irreversibility is the central reason the approval model must be strict (§15).
- **Failure**: on any RPC error the transaction rolls back server-side; the UI surfaces the error kind and leaves the record untouched.

---

## 15. Approval Models Compared

| Dimension | **Strict (all-deficiencies-resolved)** | Partial compliance (approve-with-exceptions) |
| :--- | :--- | :--- |
| Precondition to `Complete` | Every `correction_reason` key affirmed resolved | May approve with residual unresolved keys retained |
| Effect on `correction_reason` | Cleared (`{}`/null) on approve | Residual kept as annotation on a `Complete` record |
| Downstream risk | None — only fully-clean records graduate | Unresolved compliance gaps flow toward employee-no assignment, Plantilla, official directory |
| Reviewer cognitive model | Binary: clean → approve, else → return | Tri-state: approve / approve-with-exceptions / return |
| Reversibility need | Low — nothing dirty escapes the loop | High — needs a re-open path that does not exist |
| Auditability | "Approved" implies "fully compliant" — unambiguous | "Approved" is ambiguous; must inspect residual to know true state |
| Enterprise fit | Matches a compliance gate before deployment | Convenient but erodes the meaning of `Complete` |

### Partial-fix handling under the strict model
When the HRCO fixes *some* but not all deficiencies, the reviewer marks the good items resolved, leaves the rest, and chooses **Return**. The residual deficiencies become the new `correction_reason`; the record re-enters `For Correction`; the HRCO is re-notified. The loop repeats until the set is empty, at which point **Approve** becomes available. There is no "partially complete" terminal state.

---

## 16. Recommendation

**Adopt the strict all-deficiencies-resolved model.** `Complete` is the deployment gate that unlocks `Assign Employee No` and `Move to Plantilla` — both of which lead toward the irreversible official-directory write. Allowing partial compliance to reach `Complete` would let unresolved gaps escape the only place they can be caught, while the system has **no web path to re-open a `Complete` record**. The strict model keeps `Complete` semantically honest ("all compliance requirements verified"), keeps every dirty record inside the reversible loop via `return`, and makes the audit trail unambiguous. Partial compliance trades a small reviewer convenience for a standing compliance and irreversibility risk and is rejected.

---

## 17. Required Frontend UI States (OHM2026_1112 — implemented)

1. **Disabled (default)** — button hidden/disabled unless `canReviewCorrection && hrStatus === 'For Review' && !isPendingDeletion`.
2. **Enabled** — record is `For Review` and caller is an authorized reviewer.
3. **Review modal** — opens on click. Renders each `correction_reason` deficiency as a checklist row with a **Resolved / Still Deficient** toggle, the linked corrected attachment(s) for reference, and an optional reviewer remark.
   - All rows toggled **Resolved** → primary action becomes **"Approve & Complete"**.
   - Any row left **Still Deficient** → primary action switches to **"Return for Correction"**, carrying the still-deficient keys as the residual set.
4. **Confirmation step** — approve: "All N requirements verified resolved. This record moves to **Complete** and becomes eligible for employee-number assignment." return: lists the keys being sent back + the optional note.
5. **Submitting** — action shows a spinner; inputs disabled; no double-submit (`isPending`).
6. **Success** — modal closes; toast/inline confirmation; detail + list + summary refetch. Record shows `Complete` (cleared deficiencies) or `For Correction` (residual).
7. **Error** — modal stays open with an inline message mapped through the existing `HrEmplocDataError` kinds: `access_denied` → "You are not authorized…"; `invalid_state` → backend message (e.g. "unresolved deficiencies remain", "record can no longer be reviewed"); `retryable` → retry affordance.

Error handling reuses the existing `getErrorKind` classifier (`42501`→`access_denied`, `P0001`→`invalid_state`) with no new error kinds required.

---

## 18. Exact Next Implementation Prompt

ID: OHM2026_1110-IMPL-1

Implement the backend-authoritative Supabase RPC for the OHMployee Web second mutation: HR Emploc correction review (`For Review` → `Complete` on approve, `For Review` → `For Correction` on return).

Read only:
- `docs/state/web_mutation_workflow_state.md` (Part II, §10–§17)
- `docs/state/hr_emploc_web_state.md`
- `docs/state/web_auth_rbac_state.md`
- `.ai/current_state.md`
- `.ai/handoff.md`
- Existing Supabase HR Emploc migrations/views/RPCs only, especially `get_web_hr_emploc_detail`, `list_web_hr_emplocs`, `get_web_hr_emploc_summary`, `hr_emploc_issue_types`, `hr_emploc_correction_attachments`, the HR Emploc audit log surface feeding `audit_logs_timeline`, the correction notification trigger(s), and the Part I RPC `tag_web_hr_emploc_deficiency`.
- Existing RBAC/scope helpers only: `get_web_current_user_context`, `i_have_full_access`, `get_my_allowed_accounts`, `user_scopes`, the role permission matrix.

Tasks:
1. Add a migration in the authoritative Supabase repo; do not edit frontend code.
2. Create `public.review_web_hr_emploc_correction(p_hr_emploc_id uuid, p_decision text, p_resolved_keys text[] default null, p_remarks text default null)` as `SECURITY DEFINER` with `SET search_path = public`, granted to `authenticated`, revoked from `PUBLIC`/`anon`.
3. Derive caller identity exclusively from `auth.uid()`. Accept no role/profile/account/group authority arguments.
4. Enforce, in order, failing closed: record visible under caller RLS scope; caller is `hrPersonnel` (or `superAdmin`) with correction-review capability; `hr_status = 'For Review'`; `status = 'Pending Emploc'`; not `Pending Deletion`; `p_decision IN ('approve','return')`; `p_resolved_keys ⊆ keys(correction_reason)`.
5. **Strict approval**: for `approve`, every key in `correction_reason` must be present in `p_resolved_keys` (else reject `invalid_state`); recommended — require ≥1 row in `hr_emploc_correction_attachments`. For `return`, the residual `keys(correction_reason) − p_resolved_keys` must be non-empty.
6. In one transaction:
   - `approve` → set `hr_status = 'Complete'`, clear `correction_reason` (`'{}'::jsonb` or null), do **not** touch `employee_no`, insert immutable audit event `Correction Approved` (resolved-key summary, no PII), fire compliance-complete notification only if such a trigger already exists.
   - `return` → set `hr_status = 'For Correction'`, rewrite `correction_reason` to the residual keys, insert audit event `Correction Returned` (residual-key summary, no PII), re-fire the existing correction notification trigger to alert the HRCO.
7. Return the JSONB envelope `{ ok, hr_emploc_id, decision, new_hr_status, correction_reason, reviewed_at }`; never return raw sensitive columns or contact PII.
8. Add `can_review_correction` to the `get_web_hr_emploc_detail` row-capability payload (true only for authorized reviewers on `For Review`, non-`Pending Deletion` records). Keep it distinct from `can_review_deletion` and `can_tag_deficiency`.
9. Add validation SQL proving: unauthenticated blocked; non-`hrPersonnel` blocked; out-of-scope record blocked; non-`For Review` records rejected with a clear state error; `approve` with any unaffirmed deficiency rejected; `approve` with all resolved succeeds, clears `correction_reason`, leaves `employee_no` untouched, writes exactly one audit row; `return` with residual keys moves to `For Correction`, rewrites `correction_reason`, writes one audit row, re-fires notification.

Constraints:
- Do not edit frontend code in this prompt.
- Do not weaken RLS or grants. Do not invent statuses or roles. Do not add caller-controlled authority arguments.
- Do not assign employee numbers, move records to Plantilla, or touch Vacancy/Plantilla tables.
- Preserve Supabase as the business authority and reuse the existing correction loop and notification trigger(s).
- Enforce the **strict** model from §16 — no partial-compliance approvals.

Validation:
- Run the authoritative Supabase migration validation/test workflow.
- Test as Super Admin, Head Admin, hrPersonnel (in/out of scope), Encoder, OM/HRCO, Viewer, and unauthenticated caller.
- Verify queue movement (`Pending Review` → `Compliance Complete` on approve; `Pending Review` → `For Correction` on return) and summary count deltas match the same scoped base query.

After this RPC is verified the mutation executes end-to-end. Frontend is already wired (OHM2026_1112).

---

## 19. Implementation Status (OHM2026_1112)

Frontend phases for the second mutation are complete and validated (`pnpm lint` clean, `pnpm build` clean).

**Files changed:**
- `src/lib/queries/hr_emploc.ts` — added `canReviewCorrection` to `HrEmplocRowCapabilities`; normalized `can_review_correction | can_approve_correction`; added `ReviewCorrectionParams`, `ReviewCorrectionResult`, `reviewWebHrEmplocCorrection` RPC wrapper calling `public.review_web_hr_emploc_correction(p_hr_emploc_id, p_decision, p_resolved_keys, p_remarks)`.
- `src/components/hr-emploc/HrEmplocDetailDrawer.tsx` — imported `reviewWebHrEmplocCorrection` and `ReviewCorrectionParams`; added `isReviewModalOpen` state; wired "Review Correction Resubmission (HR Compliance)" action enabled when `canReviewCorrection && isForReview && !isPendingDeletion`; added `ReviewCorrectionModal` sub-component with per-deficiency Resolved/Still-Deficient toggles, auto-derived decision (all resolved → approve; any residual → return), decision-preview block, optional remarks textarea, submitting state, inline error display. On success: invalidates `["hr-emploc-detail", hrEmplocId]`, `["hr-emploc-list"]`, `["hr-emploc-summary"]`. No optimistic UI.

**Error handling:** `42501` → access/session error; `P0001` → backend validation message; generic → network fallback. Reuses existing `HrEmplocDataError` kinds with no new kinds required.

**Backend deployed:** Migration `20260609000000` applies `public.review_web_hr_emploc_correction(...)` remotely. **Remaining gap:** `can_review_correction` must be added to the `get_web_hr_emploc_detail` row capability payload before the mutation can execute end-to-end (per §13 / OHM2026_1110-IMPL-1).
