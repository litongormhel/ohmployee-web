# Notifications State & Architecture (Alerts & Activity Center)

## Scope

This document tracks the OHMployee Web Notifications module architecture, taxonomy, state management, and visual components under `/notifications`.

## Architecture & Visual System

- **Command Center Layout**: Built using `AdminPageHeader`, top metric summary strip (`Unread`, `Needs Action`, `Today`), 5 category tabs (`All`, `Unread`, `Requests & Approvals`, `SLA & Alerts`, `System`), multi-module multi-select chips (`Vacancy`, `Plantilla`, `HR Emploc`, `Approvals`, `CENCOM`, `System`), search input, and "Needs action only" toggle.
- **High-Density Rows (~64–72px)**: Implemented in `src/components/notifications/NotificationRow.tsx`. Each notification renders:
  - Multi-select checkbox for bulk actions
  - Colored unread indicator dot + tinted row background (`bg-brand-50/25` / dark mode aware)
  - Severity icon inside a styled rounded container
  - Bold title if unread, regular if read
  - Canonical status badge derived from central taxonomy
  - Single-line message with full tooltip
  - Monospace code pill (`.mono-pill`) for entity codes (`VCYG1_0001`, `CPSAJV31`, `AMR-1234`, `AGT-2026-0001`) with copy-to-clipboard shortcut
  - Requester / actor name
  - Relative timestamp with absolute locale timestamp on hover
  - Primary inline CTA (e.g. `Inspect Vacancy →`, `View in Approvals →`) that automatically marks the item as read on click
  - Secondary quick toggle button (Mark as read / unread)
- **Consecutive Burst Collapsing**: Implemented in `src/components/notifications/NotificationBurstRow.tsx`. Consecutive same-type notifications within a date group collapse into a single expandable summary card (e.g. "3 Events: Approved") with count pill, burst selection checkbox, and "Mark all read" quick action.
- **Date Grouping**: Notifications are grouped into sticky chronological headers: `Today`, `Yesterday`, `This Week`, and `Earlier`.
- **Bulk Action Mode**: Implemented in `src/components/notifications/NotificationBulkBar.tsx`. Floating sticky toolbar appearing when items are selected with `Mark as read`, `Mark as unread`, and `Clear selection`.
- **Scope-Aware Mark All as Read with Confirmation & Undo**:
  - The top "Mark all as read" button detects active filters (e.g. "Mark Filtered Read (N)").
  - Prompts with a confirmation modal before execution.
  - Triggers `NotificationUndoToast.tsx` with a 5-second countdown to revert read states if performed by mistake.

## Single Source of Truth Taxonomy (`src/lib/notifications/severity.ts`)

Derives presentation strictly from `(type, event_type, title, sla_level)` using semantic theme tokens:

| Severity | Theme Tokens | Use Cases |
|---|---|---|
| **Success** | `status-success-bg`, `status-success-border`, `status-success-text` | Approved requests, finalized batches, VCode creation, Plantilla assignment |
| **Info** | `status-info-bg`, `status-info-border`, `status-info-text` | General notices, announcements, access grants, import status broadcasts |
| **Pending** | `status-warning-bg`, `status-warning-border`, `status-warning-text` | Awaiting review, submissions, rollback pending, pending verification |
| **Warning** | `status-warning-bg`, `status-warning-border`, `status-warning-text` | SLA Level 1 (3-day warnings), EDR lapsed, correction required, on hold |
| **Critical** | `status-danger-bg`, `status-danger-border`, `status-danger-text` | SLA Level 2 (5-day breaches), rejections, rollback failures |

### Resolved Edge Cases
1. **"Deletion Request Approved"**: Evaluates to **`Success`** (`Approved`, `CheckCircle2`) because positive resolution takes precedence over the word "deletion".
2. **"Import Plantilla Batch Awaiting Approval"**: Evaluates to **`Pending`** (`Pending Approval`, `Clock`) because "awaiting approval" takes precedence over the word "approval".

## Scoped Notification Delivery Architecture (Database Triggers)

Database migration `supabase/migrations/20262606000113_scope_notification_delivery_and_actioned_status.sql` enforces tenant & role scoping per ADR-001 cross-module invariants:

1. **Requisition Submission (`public.notify_hc_request_submitted`)**:
   - Scopes recipient query strictly by `group_id` / `account_id` via `public.user_scopes` (with `users_profile` direct assignment fallback).
   - Prevents multi-tenant fanout leaks across groups.
   - Includes active scoped `Encoder` users alongside `Head Admin` upon submission for early requisition visibility.
   - Honors `scope_type = 'global'` for unconstrained global admins.
2. **Requisition Actioning (`public.notify_hc_request_actioned`)**:
   - Updates approval tuple check to include `'approved_pending_vcode'`:
     `IF v_status IN ('approved', 'head admin approved', 'ha approved', 'approved_pending_vcode')`
   - Immediately dispatches approval notification to the Ops requestor (`requested_by_user_id` -> `_rnw_auth_uid`) upon Head Admin sign-off without awaiting downstream asynchronous steps.
3. **Role-Based Scoped Fanout (`public._rnw_notify_roles`)**:
   - Added 10-parameter signature `_rnw_notify_roles(..., p_group_id uuid, p_account_id uuid)` filtering Head Admin & Encoder recipients by target group/account while keeping Super Admin globally unscoped.
   - Preserves 8-parameter overload redirecting to 10-parameter with `(NULL, NULL)` for 100% backward compatibility with external triggers.
   - Permissions revoked from `PUBLIC` and `anon`.
4. **Coverage Request Scoping (`public.trg_coverage_request_notify`)**:
   - Resolves `account_id` and derived `group_id` across direct columns and linked `coverage_groups`, forwarding them to `_rnw_notify_roles()`.

## Centralized Deep-Link Sanitization Engine (`src/lib/notifications/deep_links.ts`)

Pure TypeScript engine with zero React dependencies (enabling native Node.js ESM test execution under `node --test`). Completely eliminates 404 broken links on Web by intercepting legacy/mobile route formats and routing to valid Next.js App Router paths:

| Legacy / Backend Route | Sanitized Web Route Destination | Action Label |
|---|---|---|
| `/headcount-requests/*` | `/approvals?tab=headcount` | `View in Approvals →` |
| `/vacancies/*/closure-request/*` | `/approvals?tab=vacancy_closures` | `View in Approvals →` |
| `/deactivation-requests/*` | `/approvals?tab=deactivations` | `View in Approvals →` |
| `/hr-emploc/deletion-requests/*` | `/approvals?tab=hr_emploc_deletions` | `View in Approvals →` |
| `/requests/applicant-movement/*` | `/approvals?tab=applicant_movements` | `View in Approvals →` |
| `/account-group-transfers/*` | `/approvals?tab=account_group_transfers` | `View in Approvals →` |
| `/workforce/requests/*`, `/workforce/pool-requests/*` | `/approvals?tab=relievers` | `View in Approvals →` |
| `/vacancies/:vcode` | `/vacancy?q=:vcode` (URL-encoded) | `Inspect Vacancy →` |
| `/transfers/*` | `/plantilla` | `Inspect Plantilla →` |
| `/account-requests/*` | `/users` | `Review User Requests →` |
| `/access-requests/*` | `/more` | `View in More →` |
| `/hr-emploc/:id/correction` | `/hr-emploc` | `Inspect Emploc →` |

### 3-Tier Safe Fallback Protocol
1. **Tier 1 (Whitelisted App Router Routes)**: Preserves valid App Router routes (`/approvals?tab=...`, `/plantilla/[id]`, `/hr-emploc/import`) and complex query parameters.
2. **Tier 2 (Module Semantic Fallback)**: Unmapped routes with known `fallbackModule` map to module root (`/approvals`, `/vacancy`, `/plantilla`, `/hr-emploc`, `/cencom`, `/notifications`).
3. **Tier 3 (Safe Null Termination)**: Completely unmapped routes terminate at `null`. `NotificationRow.tsx` conditionally renders `{p.deepLink ? <Link ...> : null}`, completely eliminating 404 links from rendering in the UI.

## Database & RLS Invariants
- Zero DDL schema table alterations (functions & triggers only).
- Non-admin visibility strictly enforced via RLS `notif_select_own` (`recipient_user_id = auth.uid()`). All triggers fan out by resolving `auth_user_id`.
- Realtime synchronization wired via Supabase `postgres_changes` on `public.notifications`.
- Scoped mark-all and bulk mutations execute via client `.in("id", ids)` updates with fallback to `public.mark_notification_read(p_notification_id)`.
