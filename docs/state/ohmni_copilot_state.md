# OHMni AI Co-Pilot State & Technical Architecture Specification

**Module:** OHMni (AI Operations & Data Self-Service Co-Pilot)  
**Endpoint:** `/api/ohmni` (Streaming Next.js Route Handler)  
**Drawer UI:** Docked Right-Side Drawer (`380px–400px` width)  
**Navigation Placement:** Directly below CENCOM in `Sidebar.tsx`, plus Header trigger in `AdminTopbar.tsx`, and `⌘K` / `Ctrl+K` keyboard shortcut  
**Last Updated:** 2026-11-01 (`ohm#0hmn1cop`)

---

## 1. Overview & Architecture

OHMni is an enterprise AI co-pilot designed to allow HR personnel, operations managers, and administrators to self-serve operational data queries and standard operating procedure (SOP) lookups without manual SQL or reporting escalation.

### Core Architecture
- **Model:** Google Gemini 3.8 Flash (`gemini-3.8-flash`) via Vercel AI SDK (`ai` v7, `@ai-sdk/google`, `@ai-sdk/react`, `zod`).
- **Security & RLS Enforcement:** Runs under the requesting user's Bearer JWT session token. Queries are executed with PostgreSQL Row-Level Security (RLS) and RBAC scopes applied. `SUPABASE_SERVICE_ROLE_KEY` is strictly prohibited. Unauthenticated requests receive `401 Unauthorized`.
- **State Persistence:** Session-only memory managed in React client state (`useChat`). Resets cleanly on browser refresh or via the header reset button (`↺`). Zero unnecessary database tables.

---

## 2. Drawer Anatomy (4-Zone Layout)

1. **Zone A (Compact Sub-Header, 44px / h-11):**
   - Live status indicator: `bg-emerald-500` when idle, pulsing `bg-amber-500` when streaming.
   - Dynamic route context pill: Reads `usePathname()` (e.g., `📍 /cencom`, `📍 /plantilla`, `📍 /vacancy`, `📍 /hr-emploc`).
   - Action controls: Reset chat (`↺`) and Close (`✕`).
2. **Zone B (Dynamic Body):**
   - **Route-Aware Zero-State:** When chat is empty, surfaces 3 route-contextual starter cards (e.g. Plantilla fill rates, HR Emploc pending queues, Headcount request tracking).
   - **Active Stream:** Displays compact user message pills (`bg-slate-900`) and structured assistant cards (`bg-white` with markdown tables, bullet lists, and monospace code badges).
   - **Tool Execution Trust Badges:**
     - Querying: `⏳ Querying live Supabase data ({toolName})...`
     - Verified: `⚡ Verified Live Data • {toolName}`
3. **Zone C (Contextual Quick-Follow-Up Strip):**
   - Horizontal action chips for rapid one-click drilldowns (`🔍 Vacant Only`, `📋 Check Emploc Queue`, `↺ Clear`).
4. **Zone D (Bottom Composer):**
   - Auto-aligned text input supporting `Enter` to submit and `Shift+Enter` for newlines.
   - Send button disabled during streaming.
   - Footer micro-caption: `🔒 Scoped to your RBAC permissions • Session resets on refresh`.

---

## 3. Backend Read-Only Tools

1. **`getPlantillaSummary`:** Queries `plantilla_slots` table for total, filled, vacant slots, and fill rate percentage with up to 15 sample rows.
2. **`getOpenVacancies`:** Returns vacant/open slots from `plantilla_slots` with position title, branch, and status.
3. **`getEmplocQueueStatus`:** Queries `hr_emploc` table for pending or active movement items, deployment status, and employee details.
4. **`getHeadcountRequests`:** Queries `headcount_requests` table for requisition status, urgency, branch, requested role, and creation dates.
