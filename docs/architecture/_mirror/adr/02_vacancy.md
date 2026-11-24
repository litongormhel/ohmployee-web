<!--
ADR-MIRROR: DO NOT EDIT. Read-only copy of ADR-Vacancy. Edit in mobile repo, then run `npm run sync:adr`.
source: OHMployee/docs/architecture/adr/02_vacancy.md
source_commit: 2ad3464 2026-11-24T14:22:04+08:00
source_sha256: f57ac0932777e581ea8da1cad75419ce1347c255157e7fb53cd3cd4ae7739063
synced_at: 2026-11-24T11:30:14.910Z
-->
# Vacancy Module Architecture

- **Status:** ACCEPTED & LOCKED
- **Scope:** Vacancy Capacity Behavioral Matrix (Single-Slot vs. Multi-Slot), Five Status Tabs, Candidate-Level Pipeline Expansion, Strict Closure Lock, Six-Stage Lifecycle, and Aging Continuity.

---

## Vacancy

### Rule 4 — Classification Priority

**Module scope:** Vacancy (authoritative implementation). Dashboard and CENCOM are downstream consumers.

**Authoritative rule (do not revert without equally explicit re-verification — this exact rule has flipped 7 times in this repo's history; see `docs/state/vacancy_state.md` §`ohm#8j4q1r6z`):**

> Open tab: visible iff `(hc_needed - hired_count - pipeline_count - hr_processing_count) > 0`, shown with that value. Pipeline tab: visible iff `pipeline_count > 0`, independent of Open. A vacancy may appear in Open, Pipeline, both, or neither.

**Closure Lifecycle & Pending Capacity Retention Invariant:**
- **Pending Closure Stays Counted in Open Capacity**: While a requisition has a pending closure request (`has_pending_closure = true` / `closure_request_status = 'Pending'`), its authorized capacity remains active. It MUST remain visible in the Open Tab (rendered under Stage badge `Vacancy - Closure`) and continue contributing to unfilled capacity counts until official administrative approval. Endorsement of new applicants while a closure request is pending is hard-locked.
- **Approved Closure Slot Inactivation**: Only upon administrative approval (`handle_closure_approval` / `review_vacancy_closure_request(p_status = 'Approved')`) is the physical slot closed (`slot_status = 'closed'`), the vacancy archived (`is_archived = true`), and the headcount permanently removed from Open capacity. Closed vacancies never show in Open or Pipeline.

#### Operational Capacity Contract (Single-Slot vs. Multi-Slot Behavioral Matrix)
To eliminate operational ambiguity between Open and Pipeline queues across Web and Mobile:

1. **Single-Slot Vacancies (`required_headcount = 1`)**:
   - **Unassigned (`0/1`)**: Appears in the **Open Tab** (`remaining_open = 1`).
   - **Applicant Endorsed / Undergoing Screening (`1/1 in Pipeline`)**: The moment an applicant is added or enters screening (`For Interview / Intro`, `For Medical`, etc.), that single slot is under active processing. It **leaves the Open Tab** (`remaining_open = 1 - 1 = 0`) and moves to the **Pipeline Tab**.
2. **Multi-Slot Vacancies (`required_headcount > 1`, e.g. `3` Headcount)**:
   - **Partially Sourced (`1/3` or `2/3`)**: As long as unallocated capacity remains (`remaining_open > 0`), the requisition **MUST REMAIN in the Open Tab** displaying the remaining open slots (e.g. `1 Available` when 2 of 3 slots are in pipeline or hired). Simultaneously, the active applicants appear in the **Pipeline Tab**.
   - **Fully Allocated (`3/3`)**: Once all slots are occupied by active pipeline candidates, confirmed onboards, or active hires (`hired_count + pipeline_count + hr_processing_count >= hc_needed`), the requisition has zero unallocated demand (`remaining_open = 0`) and **completely leaves the Open Tab**.

### Standard Five Status Tabs Architecture & Candidate-Level Pipeline Expansion

**Status: ACCEPTED.** Codifies the standard queue surfaces and row granularity for the Vacancy module across Web and Mobile:

1. **Tab 1: Open** (`p_status = 'Open'`): Active store requisitions with remaining unallocated capacity (`(hc_needed - hired_count - pipeline_count - hr_processing_count) > 0`), displaying remaining unfilled slots.
2. **Tab 2: Pipeline** (`p_status = 'Pipeline'`): Active candidates undergoing recruitment screening.
   - **Candidate-Level Expansion Invariant (`ohm#p6k2v9q4`)**: In the Pipeline tab, requisitions expand into **1 Row per Candidate** (**per tao ang bilang**). A 3-headcount requisition with 2 active applicants renders as 2 distinct actionable rows displaying each candidate's full name, contact details, stage, and aging. The tab badge strictly reflects total active candidates, guaranteeing 1:1 parity with the rendered roster.
3. **Tab 3: Hired** (`p_status = 'Hired'`): Requisitions where candidates reached confirmed onboard status (`confirmed_onboard_count >= required_headcount`) or active Plantilla deployment.
4. **Tab 4: Closure** (`p_status = 'Closure'`): Requisitions with pending store closure or headcount reduction requests awaiting administrative approval (`has_pending_closure = true`).
5. **Tab 5: Failed / Backout** (`p_status = 'Failed'`): Historical roster of candidates who dropped out, backed out, failed medical/ops evaluation, or did not report.

### Strict Applicant Closure Lock Invariant (`ohm#c3m8v1k4` — 2026-11-12)

**Status: ACCEPTED.** Database trigger / assertion `public.fn_assert_vacancy_closeable(p_vcode)` enforces that:
- Requesting vacancy closure or approving closure is **HARD BLOCKED for all roles** (including Super Admin, Ops, and Recruitment) whenever active, non-terminal applicants exist in the pipeline.
- Requesters must first formally advance candidates to confirmed placement (`Mark Hired`) or record terminal dropouts (`Backout`, `Failed`, `Rejected`, `Did Not Report`) with mandatory reason capture before closure can be initiated.

### Six Canonical Pipeline Stages & One-Time Profile Edit Policy (`ohm#p8r4m2k9`, `ohm#p9v2k4m7`)

1. **Six Progressive Pipeline Stages**: Candidate progression strictly standardizes on 6 sequential stages:
   `1. For Interview / Intro` $\rightarrow$ `2. For Requirements` $\rightarrow$ `3. For Medical` $\rightarrow$ `4. Pending Approval` $\rightarrow$ `5. For Deployment` $\rightarrow$ `6. For Onboard`.
2. **Terminal Dropouts**: Terminal exits are categorized into `Backout`, `Failed / Rejected by Ops`, `Rejected`, or `Did Not Report` with mandatory audit reason logging.
3. **One-Time Profile Edit Policy (`fn_update_applicant_profile_once`)**: Non-admin users are restricted to exactly one profile identity edit (`profile_edit_count = 0`) with uppercase name normalization, contact number verification, and mandatory edit audit justification. Super Admin and Head Admin maintain administrative bypass.

### Slot-Based Vacancy Demand Authority (Slots, Not Store Count)

**Status: ACCEPTED.** Total vacancy across an account or the organization is STRICTLY derived from authorized, unfulfilled **physical slots** (`plantilla_slots`), NEVER from the count of store branches:
1. **Multi-Headcount Stores**: A single store requiring 3 employees with 0 deployed staff constitutes **3 Vacancy Slots**, NOT 1 vacancy.
2. **Roving Coverage Groups**: A roving coverage group spanning 5 stores for 1 roaming merchandiser constitutes **1 Vacancy Slot**, NOT 5 vacancies.
3. **Core Invariant**: Store count must never dictate vacancy demand. Physical rows in `public.plantilla_slots` with `slot_status IN ('open', 'pipeline')` remain the sole unit of measure for vacancy counting across all views, KPIs, and reports.

### Vacancy Lifecycle Transitions (Backout Reopening, In-Flight Closure, & 30-Day Hired Auto-Archive)

**Status: ACCEPTED.** Codifies the state transitions between the 5 operational tabs:

1. **Applicant Backout & Immediate Slot Reopening with Aging Continuity**:
   - When an active candidate backs out (whether in Vacancy screening via `failBackoutApplicant` or in HR Emploc onboarding via `tag_backout`):
     - The applicant record is tagged `backout` and routes to the **Failed / Backout Tab**.
     - The linked plantilla slot is immediately released to `open` via `fn_set_slot_status(slot_id, 'open', 'BACKOUT')`.
     - Database trigger `trg_reopen_vacancy_on_slot_open` restores `vacancies.status = 'Open'`, and because unallocated capacity increases (`remaining_open > 0`), the store **immediately reappears in the Open Tab** ready for new candidate endorsement.
     - **Aging Continuity Invariant (Anti-Reset Lock)**: Reopening the vacancy MUST NOT reset its aging clock (`aging_days`) to the backout date or `CURRENT_DATE`. The requisition's aging strictly maintains unbroken continuity from the original date the position became vacant (`vacant_date` / separation date of the previous employee / initial headcount requisition creation). Failed recruitments and candidate dropouts during screening or HR Emploc onboarding never wipe out the accumulated vacancy duration.
2. **In-Flight Closure Request Routing**:
   - When Operations submits a vacancy closure request (`has_pending_closure = true`, `closure_request_status = 'Pending'`):
     - The requisition **immediately vacates the Open and Pipeline tabs** (Rule 4 closure priority).
     - It routes to the **Closure Tab** (`p_status = 'Closure'`) to await administrative review and approval (`Approve / Reject / Withdraw`).
3. **Hired Auto-Archive 30-Day Governance**:
   - Fulfilled requisitions / confirmed onboards remain visible in the **Hired Tab** for an operational auditing window of **30 calendar days**.
   - Database sweep function `fn_archive_hired_vacancies` automatically transitions records with `a.hired_at < NOW() - INTERVAL '30 days'` to `is_archived = true`, `status = 'Archived'`, cleanly archiving completed historical hiring cycles while preserving full audit history.

**7th revision (`ohm#w8r4n2yj`, 2026-08-04):** added `hr_processing_count` as a third subtraction term. Rationale: a Confirmed-Onboard/HIRED applicant sitting in `plantilla_slots.slot_status = 'hr_processing'` (awaiting Employee Number, before reaching `Plantilla.status = 'Active'`) was previously counted in NEITHER `hired_count` NOR `pipeline_count` — a real population, already exposed as `hr_processing_count` in `vw_slot_derived_vacancy_shadow`, that business confirms is effectively already hired and not truly vacant. No SQL change required — the column already existed in the view; only `VacancyItem.remainingOpenCount` (`models.dart`) and Dashboard's parallel raw-map formula (`dashboard_screen.dart`) were updated.

**Status: SHIPPED, live-verified (commit `622fa4f`; 7th revision commit pending).** The DB's raw `open_count`/`derivedOpenCount` field (`hc_needed - hired_count`, no pipeline or hr_processing subtraction) is a distinct, still-valid field used by 9+ other call sites for org-wide capacity totals — it is not itself wrong, it simply is not the Open-tab membership/display formula.

**Known gaps** for Dashboard/CENCOM consumers of this rule are tracked in the "Dashboard & CENCOM" section below, not here — this section is Vacancy's own authoritative implementation only.

### vw_slot_derived_vacancy_shadow / Standardized Open Visibility Filter

This is the original 2026-07-30 decision this ADR started from, preserved here as Rule 4's Vacancy-specific detail:

1. **Derived Logic as Single Source of Truth**: All layers (API, service queries, repository methods, dashboard aggregations, movement targets, and UI screens) MUST rely EXCLUSIVELY on derived vacancy state from `vw_slot_derived_vacancy_shadow`.
2. **Standardized Open Visibility Filter**: A vacancy is defined as "Open" if and only if `open_count > 0` (or `vacancy_tab = 'Open'`) — the base-line filter that Vacancy's tab logic further refines with the pipeline subtraction above.
3. **Deprecation of Legacy Visibility Flags**: Base table fields `closed_at`, `status`, and `is_active` MUST NOT determine vacancy visibility, filtering, or counting in any query or endpoint.
4. **Backward Compatibility**: `closed_at` and `status` remain on `vacancies` for audit and historical record tracking only.

```sql
-- Standard Open Vacancy Query (Authoritative API / UI base filter)
SELECT *
FROM vw_slot_derived_vacancy_shadow
WHERE open_count > 0;

-- FORBIDDEN FOR VISIBILITY FILTERING (Do NOT use)
-- WHERE closed_at IS NULL
-- WHERE status = 'Open'
```

**Edge Case Resolution**: Even if `closed_at` is NOT NULL on legacy rows, if `open_count > 0`, the vacancy STILL SHOWS as Open. Audit and historical logs remain intact while operational queries rely on real-time slot state.

### Vacancy Requirements Normalization (`ohm#7f3a9c2d` — 2026-07-08)

**Status: ACCEPTED — MIGRATION APPLIED TO STAGING.** `supabase/migrations/20260708012728_add_vacancy_requirements_normalization.sql`.

**Context.** Vacancy previously assumed 1 position per VCode (`vacancies.position_id` + `vacancies.required_headcount`). This caused HC ambiguity when multiple positions were required under a single request.

**Decision.** Introduce `public.vacancy_requirements` as line items under a vacancy (VCode): `vacancy_id` (FK → `vacancies.id`, cascade), `position_id` (not null), `employment_type`, `hc_needed` (> 0), `hc_filled` (>= 0, trigger-guarded to never exceed `hc_needed`).

**Consequences.**
- Enables per-position HC tracking under a single VCode.
- Enables structured assignment (future UI/RPC work — not part of this migration).
- Legacy `vacancies.position_id` / `vacancies.required_headcount` are preserved byte-for-byte — no destructive change, no column drop, no existing query rewritten.
- RLS is read-only for `authenticated` for now: `vr_same_access_as_vacancy` composes with `vacancies_read_scoped` via an `EXISTS` subquery (a role only sees a requirement row if it could also see the parent vacancy row). No INSERT/UPDATE/DELETE policy is granted to `authenticated`/`anon` — per the RPC-first mutation rule, writes are deferred to a follow-up migration that introduces the assignment RPC. Until then only `service_role` can write.

**Backfill Result (verified on staging, 2026-07-08).** 117 of 245 `vacancies` rows have a non-null `position_id` and were backfilled 1:1 (`hc_needed = required_headcount`, `hc_filled = 0`). **Known gap:** 128 rows have `position_id IS NULL` and were skipped (the column is `NOT NULL` on `vacancy_requirements` by design — no fabricated FK values were inserted). Of those 128: 127 are historical (archived/closed/filled/soft-deleted, not live). **1 live exception:** `VCSSG2_0300` (account TWO, WAREHOUSE, status Open, not archived, not deleted) has `position` text (`WAREHOUSEMAN`) but no resolved `position_id` — a pre-existing data-quality gap in `vacancies` itself, not caused by or fixed by this migration. Flagged for a future data-repair pass; not blocking, since it's a single row and the legacy read path (`vacancies.position`/`required_headcount`) is completely unaffected.

**Requires (future work, not in this migration).** UI for the per-position assignment step. A `SECURITY DEFINER` RPC (with RBAC guard) to write `hc_filled` as positions are filled, replacing the current read-only-RLS posture.

### `vacancies.status = 'Archived'` Direct Writers (`ohm#9r4t7wln` — 2026-08-10)

**Distinct from Rule 1's "5" count above.** Rule 1's carve-out (`fn_archive_all_operational_data`, `fn_archive_plantilla_data`, `fn_qa_archive_operational_data_reset`, `fn_qa_rollback_operational_data_reset`, `fn_rollback_archive_batch`) is scoped specifically to direct writers of `plantilla_slots.slot_status` — a different table/column than this note. This note names the confirmed live direct writers of `vacancies.status = 'Archived'`, audited separately under `ohm#3k8n5wqz`, and applies the same underlying principle to them explicitly: **bulk archival is not a lifecycle transition**, so these SA-gated functions are justified in writing `vacancies.status` directly rather than being subject to `fn_is_valid_vacancy_transition()`'s transition-matrix gate.

Confirmed live writers (all `SECURITY DEFINER`, all gated on `is_super_admin()`, verified live 2026-08-10):

- `archive_vacancy_record` — single-record manual archive
- `fn_archive_all_operational_data` — full cross-module QA reset
- `fn_qa_archive_operational_data_reset` — full cross-module QA reset (earlier/parallel build of the function above)
- `fn_archive_vacancy_data` — Vacancy-module-only bulk archive
- `fn_archive_moses_hq_data` — archives pool vacancies (`is_pool_vacancy = true`)
- `fn_archive_hired_vacancies` — archives stale hired vacancies (Confirmed-Onboard ≥ 30 days)

**Informational, not an action item:** 3 of the 6 (`fn_qa_archive_operational_data_reset`, `archive_vacancy_record`, `fn_archive_hired_vacancies`) are currently unwired from any Flutter call site (confirmed via `.dart` source grep — only referenced in the auto-generated `database_types.ts` type file, never invoked). Flagged for a future cleanup/consolidation decision; not resolved here.

---
