import {
  AlertCircle,
  AlertTriangle,
  Archive,
  ArrowLeftRight,
  Bell,
  Briefcase,
  Building2,
  CalendarClock,
  CheckCircle2,
  Clock,
  FileSearch,
  FileSpreadsheet,
  FileWarning,
  Key,
  KeyRound,
  RotateCcw,
  Shield,
  Tag,
  Timer,
  UserCheck,
  UserMinus,
  UserPlus,
  Users,
  UserX,
  XCircle,
  type LucideIcon,
} from "lucide-react";
import type { NotificationItem, ParsedDeepLink } from "@/lib/queries/notifications";
import {
  sanitizeNotificationDeepLink,
  extractEntityCodeFromItem,
} from "./deep_links";

// ============================================================================
// Types
// ============================================================================

export type NotificationSeverity =
  | "success"
  | "info"
  | "pending"
  | "warning"
  | "critical";

export type NotificationModule =
  | "vacancy"
  | "plantilla"
  | "hr_emploc"
  | "approvals"
  | "cencom"
  | "system";

export interface NotificationPresentation {
  severity: NotificationSeverity;
  statusLabel: string;
  icon: LucideIcon;
  module: NotificationModule;
  moduleLabel: string;
  entityCode: string | null;
  actor: string | null;
  isAttentionRequired: boolean;
  containerClass: string;
  badgeClass: string;
  dotClass: string;
  deepLink: ParsedDeepLink | null;
}

// ============================================================================
// Entity Code Extractor
// ============================================================================

export function extractEntityCode(item: NotificationItem): string | null {
  return extractEntityCodeFromItem(item);
}

// ============================================================================
// Actor Extractor
// ============================================================================

export function extractActor(item: NotificationItem): string | null {
  const payload = (item.data || {}) as Record<string, unknown>;
  if (typeof payload.actor_name === "string" && payload.actor_name) return payload.actor_name;
  if (typeof payload.requester_name === "string" && payload.requester_name) return payload.requester_name;

  // Look for patterns like "by <Name>", "requested by <Name>", "from <Name>"
  const match = item.message.match(/(?:by|from|requester:)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)/);
  if (match?.[1]) {
    return match[1];
  }

  return null;
}

// ============================================================================
// Module Categorizer
// ============================================================================

export function resolveNotificationModule(item: NotificationItem): NotificationModule {
  const refType = (item.reference_type || "").toLowerCase();
  const notifType = (item.notification_type || "").toLowerCase();
  const event = (item.event_type || "").toLowerCase();
  const route = (item.deep_link_route || "").toLowerCase();
  const title = (item.title || "").toLowerCase();

  // 1. Approvals Center Requests
  if (
    refType === "headcount_request" ||
    refType === "new_store_request" ||
    refType === "coverage_request" ||
    refType === "vacancy_closure" ||
    refType === "deactivation_request" ||
    refType === "deactivation_batch" ||
    refType === "hr_emploc_deletion" ||
    refType === "applicant_movement" ||
    refType === "account_group_transfer_request" ||
    refType === "plantilla_import_batch" ||
    notifType === "plantilla_import" ||
    route.includes("/approvals")
  ) {
    return "approvals";
  }

  // 2. Vacancy Module
  if (
    refType === "vacancy" ||
    refType === "vacancy_request" ||
    refType === "vacancy_import_batch" ||
    route.includes("/vacanc") ||
    title.includes("vacancy") ||
    title.includes("vcode")
  ) {
    return "vacancy";
  }

  // 3. Plantilla Module
  if (
    refType === "plantilla" ||
    refType === "transfer" ||
    refType === "plantilla_edr_lapse" ||
    refType === "plantilla_edr_breach" ||
    route.includes("/plantilla") ||
    title.includes("plantilla") ||
    title.includes("on-leave") ||
    title.includes("resignation")
  ) {
    return "plantilla";
  }

  // 4. HR Emploc Module
  if (
    refType === "hr_emploc" ||
    refType === "hr_emploc_correction" ||
    route.includes("/hr-emploc") ||
    title.includes("emploc")
  ) {
    return "hr_emploc";
  }

  // 5. CENCOM / Workforce Pool
  if (
    refType.startsWith("workforce_") ||
    refType === "workforce_pool_request" ||
    event.startsWith("wf_") ||
    title.includes("reliever") ||
    title.includes("workforce") ||
    title.includes("cencom")
  ) {
    return "cencom";
  }

  // 6. System / Account / Permissions
  return "system";
}

export function getModuleLabel(module: NotificationModule): string {
  switch (module) {
    case "vacancy":
      return "Vacancy";
    case "plantilla":
      return "Plantilla";
    case "hr_emploc":
      return "HR Emploc";
    case "approvals":
      return "Approvals";
    case "cencom":
      return "CENCOM";
    case "system":
    default:
      return "System";
  }
}

// ============================================================================
// Central Severity & Presentation Resolver
// ============================================================================

export function resolveNotificationPresentation(
  item: NotificationItem
): NotificationPresentation {
  const notifType = (item.notification_type || "").toLowerCase();
  const event = (item.event_type || "").toLowerCase();
  const title = (item.title || "").toLowerCase();
  const message = (item.message || "").toLowerCase();
  const refType = (item.reference_type || "").toLowerCase();
  const sla = item.sla_level ?? 0;
  const mod = resolveNotificationModule(item);

  // Defaults
  let severity: NotificationSeverity = "info";
  let statusLabel = "Notice";
  let icon: LucideIcon = Bell;
  let isAttentionRequired = false;

  // --------------------------------------------------------------------------
  // 1. Critical Level (SLA Breach L2, Rejections, Failures)
  // --------------------------------------------------------------------------
  if (
    sla >= 2 ||
    notifType === "breach" ||
    notifType === "rejection" ||
    event.includes("breach") ||
    event.includes("rejected") ||
    event.includes("failed") ||
    title.includes("breach") ||
    title.includes("rejected") ||
    title.includes("rollback failed") ||
    title.includes("sla breach")
  ) {
    severity = "critical";
    icon = AlertCircle;
    isAttentionRequired = true;

    if (sla >= 2 || title.includes("sla breach") || event.includes("breach")) {
      statusLabel = "SLA Breach (L2)";
    } else if (title.includes("rollback failed")) {
      statusLabel = "Rollback Failed";
    } else {
      statusLabel = "Rejected";
      icon = XCircle;
    }
  }

  // --------------------------------------------------------------------------
  // 2. Warning Level (SLA Warning L1, Approaching SLA, Deficiencies/Corrections)
  // --------------------------------------------------------------------------
  else if (
    sla === 1 ||
    notifType === "warning" ||
    event.includes("escalat") ||
    title.includes("unactioned") ||
    title.includes("escalat") ||
    title.includes("sla warning") ||
    title.includes("overdue") ||
    title.includes("edr lapsed") ||
    title.includes("requires correction") ||
    title.includes("ghost employee") ||
    title.includes("on hold")
  ) {
    severity = "warning";
    icon = AlertTriangle;
    isAttentionRequired = true;

    if (title.includes("edr lapsed")) {
      statusLabel = "EDR Lapsed";
      icon = CalendarClock;
    } else if (title.includes("requires correction")) {
      statusLabel = "Correction Required";
      icon = FileWarning;
    } else if (title.includes("on hold")) {
      statusLabel = "On Hold";
    } else {
      statusLabel = "SLA Warning (L1)";
      icon = Timer;
    }
  }

  // --------------------------------------------------------------------------
  // 3. Success Level (Approved, Completed, VCode Created, Executed)
  // CRITICAL FIX: Evaluated BEFORE pending/submission rules so "Deletion Request Approved"
  // gets stamped as Success / Approved!
  // --------------------------------------------------------------------------
  else if (
    notifType === "approved" ||
    (notifType === "approval" && !title.includes("vcode needed") && !title.includes("needs approval")) ||
    event.includes("_approved") ||
    event.includes("processed") ||
    event.includes("completed") ||
    title.includes("request approved") ||
    title.includes("closure approved") ||
    title.includes("deletion request approved") ||
    title.includes("store request approved") ||
    title.includes("transfer request approved") ||
    title.includes("transfer approved") ||
    title.includes("account transfer approved") ||
    title.includes("vcode created") ||
    title.includes("moved to plantilla")
  ) {
    severity = "success";
    icon = CheckCircle2;
    isAttentionRequired = false;

    if (title.includes("vcode created")) {
      statusLabel = "VCode Created";
      icon = Tag;
    } else if (title.includes("moved to plantilla")) {
      statusLabel = "Plantilla Assigned";
      icon = UserCheck;
    } else {
      statusLabel = "Approved";
    }
  }

  // --------------------------------------------------------------------------
  // 4. Pending Level (Awaiting Approval, Submission, Needs Action)
  // CRITICAL FIX: "Import Plantilla Batch Awaiting Approval" lands here as Pending / Pending Approval!
  // --------------------------------------------------------------------------
  else if (
    notifType === "submission" ||
    notifType === "approval_required" ||
    event.includes("submission") ||
    event.includes("submitted") ||
    event.includes("awaiting_approval") ||
    event.includes("pending") ||
    title.includes("awaiting approval") ||
    title.includes("needs approval") ||
    title.includes("action required") ||
    title.includes("request —") ||
    title.includes("request submitted") ||
    title.includes("rollback requested") ||
    title.includes("vcode needed") ||
    message.includes("awaiting approval") ||
    message.includes("pending review")
  ) {
    severity = "pending";
    icon = Clock;
    isAttentionRequired = true;

    if (title.includes("vcode needed")) {
      statusLabel = "Pending VCode";
      icon = Tag;
    } else if (title.includes("rollback requested")) {
      statusLabel = "Rollback Pending";
      icon = RotateCcw;
    } else if (title.includes("correction submitted")) {
      statusLabel = "Pending Verification";
      icon = FileSearch;
    } else {
      statusLabel = "Pending Approval";
      if (refType === "headcount_request") icon = UserPlus;
      else if (refType === "vacancy_closure") icon = Archive;
      else if (refType === "hr_emploc_deletion") icon = UserMinus;
      else if (refType === "deactivation" || refType === "deactivation_request") icon = UserX;
      else if (refType === "new_store_request") icon = Building2;
      else if (refType === "coverage_request") icon = Shield;
      else if (refType === "account_group_transfer_request") icon = ArrowLeftRight;
      else if (refType === "account_request") icon = KeyRound;
      else if (refType === "vacancy_request") icon = Briefcase;
      else if (refType.startsWith("workforce_")) icon = Users;
    }
  }

  // --------------------------------------------------------------------------
  // 5. Info / System Level (General Notice, Informational Broadcasts)
  // --------------------------------------------------------------------------
  else {
    severity = "info";
    icon = Bell;
    isAttentionRequired = false;

    if (title.includes("access granted")) {
      statusLabel = "Access Granted";
      icon = Key;
    } else if (title.includes("leaving / joining group")) {
      statusLabel = "Scope Notice";
      icon = ArrowLeftRight;
    } else if (refType === "mika_import" || refType === "store_import") {
      statusLabel = "Import Notice";
      icon = FileSpreadsheet;
    } else {
      statusLabel = "Notice";
    }
  }

  // Styling token classes
  let containerClass = "bg-surface-subtle text-text-secondary border-border-default";
  let badgeClass = "bg-surface-subtle text-text-secondary border-border-default";
  let dotClass = "bg-brand-500";

  switch (severity) {
    case "success":
      containerClass = "bg-status-success-bg text-status-success-text border-status-success-border";
      badgeClass = "bg-status-success-bg text-status-success-text border-status-success-border";
      dotClass = "bg-emerald-500";
      break;
    case "pending":
      containerClass = "bg-status-warning-bg text-status-warning-text border-status-warning-border";
      badgeClass = "bg-status-warning-bg text-status-warning-text border-status-warning-border";
      dotClass = "bg-amber-500";
      break;
    case "warning":
      containerClass = "bg-status-warning-bg text-status-warning-text border-status-warning-border";
      badgeClass = "bg-status-warning-bg text-status-warning-text border-status-warning-border";
      dotClass = "bg-amber-500";
      break;
    case "critical":
      containerClass = "bg-status-danger-bg text-status-danger-text border-status-danger-border";
      badgeClass = "bg-status-danger-bg text-status-danger-text border-status-danger-border";
      dotClass = "bg-rose-500";
      break;
    case "info":
    default:
      containerClass = "bg-status-info-bg text-status-info-text border-status-info-border";
      badgeClass = "bg-status-info-bg text-status-info-text border-status-info-border";
      dotClass = "bg-sky-500";
      break;
  }

  // Resolve deep link
  const deepLink = sanitizeNotificationDeepLink(item, mod);

  return {
    severity,
    statusLabel,
    icon,
    module: mod,
    moduleLabel: getModuleLabel(mod),
    entityCode: extractEntityCode(item),
    actor: extractActor(item),
    isAttentionRequired,
    containerClass,
    badgeClass,
    dotClass,
    deepLink,
  };
}
