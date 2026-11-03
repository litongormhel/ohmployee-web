# OHMni AI Co-Pilot State & Technical Architecture Specification

**Module:** OHMni (AI Operations & Data Self-Service Co-Pilot)  
**Endpoint:** `/api/ohmni` (Streaming Next.js Route Handler)  
**UI Interface:** Tarsi-Style Centered Floating Card Overlay (`max-w-[680px]`, `h-[calc(100vh-48px)]`, rounded-3xl, centered in workspace)  
**Navigation Placement:** Directly below CENCOM in `Sidebar.tsx` (for CENCOM roles) or below Dashboard/primary navigation (for non-CENCOM roles), Header trigger in `AdminTopbar.tsx`, and `⌘K` / `Ctrl+K` keyboard shortcut (100% visible across all authenticated roles)  
**Last Updated:** 2026-11-03 (`ohm#0hmn1sop`)

---

## 1. Overview & Architecture

OHMni is an enterprise AI co-pilot designed to allow HR personnel, operations managers, and administrators to self-serve operational data queries and standard operating procedure (SOP) lookups without manual SQL or reporting escalation.

### Core Architecture
- **Creator Identity & Ecosystem Architecture:** OHMni recognizes **OHM (Ormhel Litong)**, IT Manager at Moses Coop and Systems Architect of OHMployee, as its sole designer and creator. Any questions regarding who built OHMni or who Ohm is highlight Ohm's role architecting both the Mobile and Web ecosystems (Plantilla, Vacancy, HR Emploc, CENCOM, OHMni).
- **Multi-Model Discovery & Automatic Quota Failover:** Dynamically fails over across Google Gemini models (`gemini-3.5-flash-lite`, `gemini-3.1-flash-lite`, `gemini-flash-lite-latest`, `gemini-3.8-flash`, `gemini-3.6-flash`, `gemini-3.5-flash`) with `maxRetries: 0` and chunk buffering to handle Free Tier 20-req/day exhaustion (`429 RESOURCE_EXHAUSTED`) seamlessly.
- **Zero-Quota Deterministic Local Fallback:** If all candidate models in the pool hit 429 quota exhaustion, streams a clean conversational Taglish/English answer from a deterministic local router (SOP manual step-by-step instructions or direct Supabase RLS tool execution), ensuring zero red error boxes ever appear in the user interface. Headcount Request SOP directs users to the **Plantilla** module (`/plantilla` -> select Account -> click `+ Request Headcount` in header action bar -> submit for Approvals).
- **Postgrest Synchronous Query Chaining:** Group resolution is handled via plain async data helper `resolveGroupFilter(supabase, rawFilter)`. Filter builder methods (`.ilike(...)`, `.or(...)`, `.limit(...)`) are chained synchronously on `supabase.from("plantilla_slots").select(...)`, completely preventing Promise thenable unwrapping and resolving `query.limit is not a function`.
- **Security & RLS Enforcement:** Runs under the requesting user's Bearer JWT session token. Queries are executed with PostgreSQL Row-Level Security (RLS) and RBAC scopes applied. `SUPABASE_SERVICE_ROLE_KEY` is strictly prohibited. Unauthenticated requests receive `401 Unauthorized`.
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
