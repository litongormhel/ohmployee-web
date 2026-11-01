# OHMni AI Co-Pilot State & Technical Architecture Specification

**Module:** OHMni (AI Operations & Data Self-Service Co-Pilot)  
**Endpoint:** `/api/ohmni` (Streaming Next.js Route Handler)  
**UI Interface:** Tarsi-Style Centered Floating Card Overlay (`max-w-[680px]`, `h-[calc(100vh-48px)]`, rounded-3xl, centered in workspace)  
**Navigation Placement:** Directly below CENCOM in `Sidebar.tsx`, Header trigger in `AdminTopbar.tsx`, and `⌘K` / `Ctrl+K` keyboard shortcut  
**Last Updated:** 2026-11-01 (`ohm#0hmn1ui`)

---

## 1. Overview & Architecture

OHMni is an enterprise AI co-pilot designed to allow HR personnel, operations managers, and administrators to self-serve operational data queries and standard operating procedure (SOP) lookups without manual SQL or reporting escalation.

### Core Architecture
- **Model:** Google Gemini 3.5 Flash (`gemini-3.5-flash`) via Vercel AI SDK (`ai` v7, `@ai-sdk/google`, `@ai-sdk/react`, `zod`). Upgraded from `gemini-3.8-flash` to ensure high availability and prevent 20-request/day Free Tier quota exhaustion (`429 RESOURCE_EXHAUSTED`).
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
   - Assistant messages: Left-aligned with `Bot` avatar, markdown/table formatting, and live trust badges (`⚡ Verified Live Data • {toolName}`).

4. **Client-Side Tool Output Fallback:**
   - As soon as a tool part reaches `state === 'output-available'` or has output/result, badge flips to `⚡ Verified Live Data`.
   - If stream finishes (`!isLoading`) and an assistant message contains completed tool outputs but zero text parts, `ToolOutputFallbackView` automatically renders formatted data cards/tables directly from the tool's JSON instead of leaving `"Analyzing operations data..."` or a blank card.

5. **Bottom Composer Box:**
   - Clean rounded container with auto-resizing textarea.
   - Bottom bar with soft route pill (`⚡ Cloud • {currentRoute}`) and circular submit button with `ArrowUp` icon.
   - Micro-caption: `"OHMni can make mistakes. Review important details."`

---

## 3. Backend Read-Only Tools

1. **`getPlantillaSummary`:** Queries `plantilla_slots` table for total, filled, vacant slots, and fill rate percentage with up to 15 sample rows, wrapped in 8-second timeout safeguard.
2. **`getOpenVacancies`:** Returns vacant/open slots from `plantilla_slots` with position title, branch, and status, wrapped in 8-second timeout safeguard.
3. **`getEmplocQueueStatus`:** Queries `hr_emploc` table for pending or active movement items, `hr_status`, and employee details, wrapped in 8-second timeout safeguard.
4. **`getHeadcountRequests`:** Queries `headcount_requests` table for requisition status, urgency, branch, requested role, and creation dates, wrapped in 8-second timeout safeguard.
