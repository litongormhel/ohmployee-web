# ADR-001 Compliance Audit: Plantilla Account-First Flow
**Audit ID:** ohm#4t8w2xhp  
**Date:** 2026-07-11  
**Status:** COMPLETED (Read-Only Compliance Verdict)  

---

## 1. Compliance Verdict: CONDITIONAL PASS

The proposal to gate the initial loading of the Plantilla employee and store staffing lists behind a mandatory Account selection step (P1 finding from audit ohm#7k3n9dqm) complies with **ADR-001 (Plantilla Slot as Single Source of Truth)**, subject to the conditions outlined below.

---

## 2. Compliance Conditions

For the implementation to proceed compliant with ADR-001, the following exact conditions must be met:

1. **Scoped-Role Auto-Fire (Workflow Preservation):**
   - Users with scoped roles (e.g., `OM`, `HRCO`, or `Encoder` associated with only one authorized account in `get_web_current_user_context()`) must **not** be presented with an empty gate screen.
   - The UI must auto-select their single authorized account and execute the list queries (`list_web_plantilla_employees` and `list_web_plantilla_store_staffing`) immediately on mount.
   - Broad-access roles (e.g., `superAdmin`, `headAdmin`, `hrPersonnel`) must remain gated until they make an explicit selection.

2. **Dual-View Consistency (Employee vs. Store Views):**
   - The account gate must apply to both the **Employee-centric** and **Store-centric** views (`view === "employee"` and `view === "store"`). Gating one while letting the other load unconditionally is a compliance risk and UX inconsistency.

3. **Query Gate Isolation (`enabled` property):**
   - Client-side React Query hooks for list views (`employeeQuery` and `storeQuery`) must be gated using:
     ```typescript
     enabled: !!resolvedAccountId
     ```
   - The `summaryQuery` (KPI Metric Cards) may either load globally or gate alongside the list. If it loads globally, the cards must clearly reflect global/cross-account scope to avoid UX discrepancy. Gating the summary behind the account selection is recommended for absolute local consistency.

4. **URL Deep-Link Continuity:**
   - If `accountId` is provided as a query parameter in the URL on route entry, the filter state must initialize with this ID, and the query must execute immediately.

5. **No Backend Security Regression:**
   - Client-side gating is purely a presentation-layer optimization. The Supabase backend remains the absolute authority for data boundaries.
   - The client must never attempt to bypass role boundaries or construct mock data.

---

## 3. Confirmed Scope: Client-Only Change

This change is **purely client-side**. 
- **No database migrations** or RLS changes are required.
- **No changes** to the existing RPC signature `public.list_web_plantilla_employees` or `public.list_web_plantilla_store_staffing` are needed, as both already support filtering by `p_account_id`.
- The Next.js page controller (`src/app/(dashboard)/plantilla/page.tsx`) is the sole integration target.

---

## 4. Implementation Sign-off Reference

> [!IMPORTANT]
> **ADR-001 COMPLIANCE SIGN-OFF (ohm#4t8w2xhp):**
> Gating the Plantilla employee and store staffing lists behind a resolved `accountId` filter on the client is approved. The implementation must preserve immediate auto-fire for scoped users with a single account and enforce the gate consistently across both directory views.
