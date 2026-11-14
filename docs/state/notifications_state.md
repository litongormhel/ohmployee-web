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

## Database & RLS Invariants
- Zero DDL, zero schema changes, and zero migrations required.
- Realtime synchronization wired via Supabase `postgres_changes` on `public.notifications`.
- Scoped mark-all and bulk mutations execute via client `.in("id", ids)` updates with fallback to `public.mark_notification_read(p_notification_id)`.
