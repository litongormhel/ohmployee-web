<!--
ADR-MIRROR: DO NOT EDIT. Read-only copy of ADR-Index. Edit in mobile repo, then run `npm run sync:adr`.
source: OHMployee/docs/architecture/adr/README.md
source_commit: 0eb4407 2026-11-23T23:02:59+08:00
source_sha256: c00349da320eda6c44696f31cc7045c79a9c691013aeb47010f24632ae5efe17
synced_at: 2026-11-26T02:43:50.249Z
-->
# OHMployee Architecture Decision Records (Hub-and-Spoke Modular Hub)

Welcome to the unified, modular Architecture Decision Records (ADR) system for OHMployee and OHMployee Web.

> [!TIP]
> **Token-Optimized Loading Protocol for AI Agents:**
> When addressing a prompt, do **NOT** read all ADR files. Load only:
> 1. `00_core_invariants.md` (always loaded, ~70 lines)
> 2. The single module-specific ADR file matching the task (e.g., `02_vacancy.md` for Vacancy tasks).

---

## Modular Directory Index

| File | Module / Domain | Governing Scope | Approx. Size |
| :--- | :--- | :--- | :--- |
| **[`00_core_invariants.md`](00_core_invariants.md)** | **Core Cross-Module Invariants** | Slot Authority, Hired Source, Lifecycle Sync, Denormalized Writes, User Management SSOT. | ~70 lines |
| **[`01_plantilla.md`](01_plantilla.md)** | **Plantilla & Store Identity** | Store Identity (1 Store = 1 VCODE), Plantilla Baseline Import, Headcount Fractions ($1/N$), 6 Sub-Tabs, DOLE Floating, Relievers. | ~250 lines |
| **[`02_vacancy.md`](02_vacancy.md)** | **Vacancy** | Capacity Behavioral Matrix, 5 Tabs, Candidate-Level Pipeline, Strict Closure Lock, Aging Continuity. | ~150 lines |
| **[`03_hr_emploc.md`](03_hr_emploc.md)** | **HR Emploc** | 5 Operational Queues, Emploc Number Ownership, Atomic Deployment, 4 Statutory Requirements, Deployed Reverts. | ~190 lines |
| **[`04_approvals_requisitions.md`](04_approvals_requisitions.md)** | **Approvals & Headcount Requests** | 11 Functional Queues, Option 1 Requisition Routing, ADR-003 Unified Roving Atomic Stores, /my-requests. | ~320 lines |
| **[`05_more_module.md`](05_more_module.md)** | **More Module (Operations Hub)** | 5 Tabs, 5 Canonical Batch Imports with 72h Rollback, QA Simulation Sandbox, Impersonation, MIKA Ghost Detection. | ~200 lines |
| **[`06_dashboard_cencom.md`](06_dashboard_cencom.md)** | **Dashboard & CENCOM** | 4 Executive KPIs, CENCOM 5 Tabs, MFR Health Scale, Database Computes / UI Renders, Rounding Contract. | ~90 lines |

---

## Archival Reference
Historical design plans and superseded pre-ADR proposals are preserved in [../archive/](../archive/README.md).
