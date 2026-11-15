# OHMni AI Co-Pilot State & Technical Architecture Specification

**Module:** OHMni (AI Operations & Data Self-Service Co-Pilot)  
**Endpoint:** `/api/ohmni` (Streaming Next.js Route Handler)  
**UI Interface:** Tarsi-Style Centered Floating Card Overlay (`max-w-[680px]`, `h-[calc(100vh-48px)]`, rounded-3xl, centered in workspace)  
**Navigation Placement:** Directly below CENCOM in `Sidebar.tsx` (for CENCOM roles) or below Dashboard/primary navigation (for non-CENCOM roles), Header trigger in `AdminTopbar.tsx`, and `⌘K` / `Ctrl+K` keyboard shortcut (100% visible across all authenticated roles)  
**Last Updated:** 2026-11-15 (`ohm#ohmni-phase2-layer3`)

---

## 1. Overview & Architecture

OHMni is an enterprise AI co-pilot designed to allow HR personnel, operations managers, and administrators to self-serve operational data queries and standard operating procedure (SOP) lookups without manual SQL or reporting escalation.

### Phase 2 Architecture: Real-Time Intelligence & Safe Action Execution
- **Layer 1: Context Awareness & Operational Briefing:**
  - **Active Screen Context Awareness (`activeContext`):** Automatically parses URL route and query parameters via `usePathname()` and `useSearchParams()` (`store`, `account`, `vcode`, `q`) on Web, and `activeContext` route map on Mobile. Forwards active context payload `{ route, storeName, accountName, vcode }` to the `/api/ohmni` route handler and displays a live context badge in the chat welcome view (`📍 Context: Store • Account • Slot`).
  - **Dynamic Contextual Starter Prompts:** Dynamically injects tailored question prompts based on active screen context (e.g. `"Kumusta ang staffing sa [Store]?"`, `"Check details ng slot [VCODE]"`).
  - **Context-Bound System Prompt:** Instructs Gemini to bind relative and deictic queries (*"dito"*, *"here"*, *"this store"*, *"staffing rito"*, *"this slot"*) to the current active screen context.
  - **Daily Operational Briefing (`getOperationalBriefing`):** Aggregates operational priorities across 5 dimensions: pending headcount requests, open vacancies, aging vacancies (>30 days SLA alert), pending HR emploc movements, and pending vacancy closures, supplemented by priority understaffed accounts from `v_account_allocation_kpi`.
- **Layer 2: Safe Interactive Action Drafting & In-Place Confirmation/Execution:**
  - **Action Ready Cards:** When asked to draft or submit a headcount request or close a vacancy, OHMni prepares verified structured drafts (`draftHeadcountRequest` and `draftVacancyClosure`) with resolved UUIDs (`storeId`, `accountId`, `positionId`) rendered directly within interactive cards.
  - **In-Place "Confirm & Submit":** Users execute submissions directly from within the chat conversation without leaving their context.
    - **Headcount Request:** Submits via `submitHeadcountRequest` RPC (`public.submit_headcount_request`), immediately invalidates query caches (`request-category-counts`, `my-requests`, `headcount-requests`, `plantilla`, `vacancies`), and transitions the card into a confirmed state with direct links to `/my-requests` and `/approvals`.
    - **Vacancy Closure:** Submits via `requestVacancyClosure` (`rpc_submit_vacancy_closure_request`), invalidates relevant caches, and renders confirmed state linking to `/my-requests` and `/vacancy`.
  - **Mobile Parity:** Updated `_confirmAndSubmitHeadcount` in `ohmni_chat_screen.dart` utilizing `PlantillaScopeService().submitHeadcountRequest` with store/position/account resolution conforming strictly to database contracts.
- **Layer 3: Deep Operational Drill-Down & Relational Audit Tracing:**
  - **Slot Deep Dive (`inspectSlot`):** Queries `plantilla_slots`, resolves `stores` & `accounts`, links current occupant (`employee_name`, `employee_no`, `status`, `deployment_type`, `date_hired`) via `plantilla`, reserved candidate applicant via `applicants`, and recent transition history via `slot_history`.
  - **Branch Staff Roster (`inspectStoreRoster`):** Aggregates staff currently deployed to a specific branch/store from `plantilla`, calculating active, on-leave, and floating breakdowns, accompanied by open vacancy counts from `vw_vacancy_list`.
  - **Relational Audit Trail (`getSlotAuditHistory`):** Queries chronological state transitions from `slot_history`, resolves performer identities from `users_profile`, and traces changes in status, occupants, reasons, and remarks.
  - **Rich Visual Cards & Fallbacks:** `ToolOutputFallbackView` presents structured cards for slot details, branch rosters, and audit event logs, complemented by dynamic contextual starter prompts (`"Sino-sino ang nakaduty sa [Store]?"`, `"Ano ang audit history ng [VCODE]?"`) and Flutter Mobile local deterministic fallbacks in `ohmni_service.dart`.

### Core Architecture
- **Creator Identity & Ecosystem Architecture:** OHMni recognizes **OHM (Ormhel Litong)**, IT Manager at Moses Coop and Systems Architect of OHMployee, as its sole designer and creator. Any questions regarding who built OHMni or who Ohm is highlight Ohm's role architecting both the Mobile and Web ecosystems (Plantilla, Vacancy, HR Emploc, CENCOM, OHMni).
- **Multi-Model Discovery & Automatic Quota Failover:** Dynamically fails over across Google Gemini models (`gemini-3.5-flash-lite`, `gemini-3.1-flash-lite`, `gemini-flash-lite-latest`, `gemini-3.8-flash`, `gemini-3.6-flash`, `gemini-3.5-flash`) with `maxRetries: 0` and chunk buffering to handle Free Tier 20-req/day exhaustion (`429 RESOURCE_EXHAUSTED`) seamlessly.
- **Zero-Quota Deterministic Local Fallback:** If all candidate models in the pool hit 429 quota exhaustion, streams a clean conversational Taglish/English answer from a deterministic local router (SOP manual step-by-step instructions or direct Supabase RLS tool execution), ensuring zero red error boxes ever appear in the user interface. Headcount Request SOP directs users to the **Plantilla** module (`/plantilla` -> select Account -> click `+ Request Headcount` in header action bar -> submit for Approvals).
- **Postgrest Synchronous Query Chaining:** Group resolution is handled via plain async data helper `resolveGroupFilter(supabase, rawFilter)`. Filter builder methods (`.ilike(...)`, `.or(...)`, `.limit(...)`) are chained synchronously on `supabase.from("plantilla_slots").select(...)`, completely preventing Promise thenable unwrapping and resolving `query.limit is not a function`.
- **Security & RLS Enforcement:** Runs under the requesting user's Bearer JWT session token. Queries are executed with PostgreSQL Row-Level Security (RLS) and RBAC scopes applied. `SUPABASE_SERVICE_ROLE_KEY` is strictly prohibited. Unauthenticated requests receive `401 Unauthorized`. Immediately after token authentication, validates web user access via `get_web_current_user_context` RPC (`access_status === "allowed"`), failing closed with `403 Forbidden` for inactive, unlinked, or unauthorized accounts before any model invocation or tool execution (`ohm#k7q2m9x4`).
- **Postgrest Query Sanitization:** User filter terms (`branchFilter`, `employeeFilter`, `groupFilter`) are sanitized via `sanitizeOrTerm` before interpolation into PostgREST `.or(...)` filter clauses, stripping delimiter injection characters (`,`, `(`, `)`, `"`, `\`) while preserving valid search inputs (`ohm#k7q2m9x4`).
- **Query Timeout Safeguards:** All backend Supabase tool calls execute with an 8-second timeout safeguard (`executeWithTimeout`) to prevent database hanging.
- **State Persistence:** Session-only memory managed in React client state (`useChat`). Resets cleanly on browser refresh or via the header reset button (`↺`). Zero unnecessary database tables.

---

## 2. Card Anatomy (Tarsi-Style Aesthetic)

1. **Overlay & Workspace Alignment:**
   - Positioned inside workspace to the right of `Sidebar.tsx` (`fixed inset-0 lg:left-[var(--sidebar-width)] z-50 bg-slate-900/10 backdrop-blur-[2px]`).
   - Left navigation sidebar remains 100% visible, accessible, and interactive.
   - Floating card dimensions: `w-full max-w-[680px] h-[calc(100vh-48px)] max-h-[780px] bg-white rounded-3xl shadow-2xl border border-slate-200/80 flex flex-col overflow-hidden mx-auto my-auto`.
   - Dismissible via Escape key, backdrop click, or top-left `<` button.

2. **Top Header:**
   - Left: Circular subtle button (`ChevronLeft`) calling `onClose`.
   - Title & Badge: Bold `Chat` title with soft green status pill (`⚡ LIVE` / pulsing `⏳ SYNCING` while `isLoading`), plus subtitle `"Ask questions about slots, vacancies, or HR queues in plain language."`
   - Right: Circular reset button (`RotateCcw`) calling `handleReset` (`setMessages([])`).

3. **Welcome View & Active Stream:**
   - Always-visible welcome greeting with Robot Icon avatar (`Bot` in `w-8 h-8 rounded-full bg-emerald-100 text-emerald-700`) labeled `OHMni`, greeting `"Hi OHM!"`, and 3 contextual starter prompts tailored to active route when chat is empty.
   - User messages: Right-aligned pill (`bg-slate-900 text-white text-sm px-4 py-2.5 rounded-2xl max-w-[80%]`).
   - Assistant messages: Left-aligned with `Bot` avatar.
   - **Clean Thinking State:** Displays a subtle `Thinking.....` label alongside a spinner inside the response bubble while generation/tools are in progress. Live data feed pills (`⏳ Querying...`, `⚡ Live Data Verified`) are completely removed for a minimal, distraction-free aesthetic.
   - **Simple Text-First Answers:** When Gemini returns conversational text, only the clean text and bullets are rendered via `FormattedContent`.

4. **Client-Side Tool Output Fallback:**
   - Activates only if the stream finishes (`!isLoading`) and an assistant message contains completed tool outputs but zero text parts.
   - Selects the **last non-empty tool output** (or the last tool invocation if all were empty).
   - Renders a **single plain-language summary line + clean bullet list** (e.g. `"Found **1** open vacancy: • **VCBPIG1_0183** — MOTORIZED COLLECTOR (open, regular)"`). Zero duplicate cards, zero 4-box `0` KPI grids, and zero empty tables.

5. **Bottom Composer Box:**
   - Clean rounded container with auto-resizing textarea.
   - Minimalist bottom action bar with right-aligned circular submit button (`ArrowUp`). Route pill removed.
   - Micro-caption: `"OHMni can make mistakes. Review important details."`

---

## 3. Backend Read-Only Tools

1. **`getPlantillaSummary`:** Queries `plantilla_slots` table for total, filled, vacant slots, and fill rate percentage with sample rows. Supports `groupFilter` and `accountFilter` with intelligent account resolution via `accounts` table (`resolveAccountFilter`). When an account (such as `"Alturas"`) is queried, accesses `v_account_allocation_kpi` and `v_plantilla_safe` to accurately return the active employee count (e.g. 754), open vacancies (1), and 100% fill rate. Wrapped in 8-second timeout safeguard.
2. **`getOpenVacancies`:** Returns vacant/open slots from `plantilla_slots` with position title, branch, and status. Supports `groupFilter` and `accountFilter` (filtering by resolved `account_id`). Wrapped in 8-second timeout safeguard.
3. **`getEmplocQueueStatus`:** Queries `hr_emploc` table for pending or active movement items, `hr_status`, and employee details, wrapped in 8-second timeout safeguard.
4. **`getHeadcountRequests`:** Queries `headcount_requests` table for requisition status, urgency, branch, requested role, and creation dates, wrapped in 8-second timeout safeguard.
5. **`inspectSlot`:** Queries `plantilla_slots` by `legacy_vcode` or UUID, resolving store and account names, occupant identity (`employee_name`, `employee_no`, `status`, `deployment_type`, `date_hired`) from `plantilla`, reserved candidate from `applicants`, and latest state transition from `slot_history`.
6. **`inspectStoreRoster`:** Queries `plantilla` for all personnel assigned to a branch/store, returning employee names, numbers, position titles, statuses (`active`, `on_leave`, `floating`), and open vacancy metrics from `vw_vacancy_list`.
7. **`getSlotAuditHistory`:** Queries `slot_history` chronologically for a specific slot, resolving performer names from `users_profile`, and detailing status transitions, past occupants, reasons, and remarks.
