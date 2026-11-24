import React from "react";
import type { BadgeVariant } from "@/components/ui/StatusBadge";
import type { EmployeeIdentitySummary } from "@/types/display";
import type { PlantillaEmployeeListItem, ActiveCoverageItem } from "@/lib/queries/plantilla";
import { deriveDeactivationOverlay } from "@/lib/queries/plantilla";
import type { VacancyListItem } from "@/lib/queries/vacancy";

// ---------------------------------------------------------------------------
// View & Tab Enums / Unions
// ---------------------------------------------------------------------------

export type PlantillaViewMode = "store" | "moses_pool" | "analytics";
export type MainViewToggle = "employee" | "store";
export type StatusSubTab = "active" | "on_leave" | "vacancy" | "floating" | "deactivation" | "inactive";
export type DisplayView = "table" | "cards";

export type VacancyWorkflowStage =
  | "Vacancy - Open"
  | "Vacancy - Pipeline"
  | "Vacancy - Closure"
  | "HR Emploc - Pending"
  | "HR Emploc - For Emploc"
  | "HR Emploc - Correction"
  | "HR Emploc - Ready"
  | "HR Emploc - Review";

export const VALID_LEAVE_REASONS = [
  "Sick / Medical Leave",
  "Maternity / Paternity Leave",
  "Vacation Leave",
  "Emergency Family Leave",
  "Other Authorized Leave",
] as const;

// ---------------------------------------------------------------------------
// Component Data Contracts
// ---------------------------------------------------------------------------

export interface StoreCapacityRow {
  id: string;
  storeBranch: string;
  code: string | null;
  city: string | null;
  province: string | null;
  plantillaRequired: number;
  activeDeployed: number;
  onLeave: number;
  openVacancy: number;
  isFulfilled: boolean;
  deploymentTypes: Array<"Roving" | "Stationary">;
}

export interface AccountSummaryMetric {
  actual: number;
  vacant: number;
  hrProcess: number;
  required: number;
  fillRate: number;
  leave: number;
}

export interface RelieverTargetEmployee extends EmployeeIdentitySummary {
  id: string;
  displayName: string;
  employeeNo: string;
  storeId?: string | null;
  storeName?: string | null;
}

export interface ReturnToActiveTarget {
  employee: {
    id: string;
    displayName: string;
    employeeNo: string;
    storeName?: string | null;
  };
  reliever: {
    id: string;
    name: string;
    employeeNumber: string;
  } | null;
}

export interface AssignStoreTargetEmployee extends EmployeeIdentitySummary {
  id: string;
  displayName: string;
  employeeNo: string;
}

export interface UpdateStatusTargetEmployee extends EmployeeIdentitySummary {
  id: string;
  displayName: string;
  employeeNo: string;
  currentStatus: string;
}

export interface DeactivationTargetEmployee extends EmployeeIdentitySummary {
  id: string;
  displayName: string;
  employeeNo: string;
  currentStatus: string;
}

export interface ArchiveModalAccount {
  id: string;
  name: string;
  actual: number;
  vacant: number;
  required: number;
  groupName?: string | null;
}

export interface AbsorbModalAccount {
  id: string;
  name: string;
}

export interface StoreWithAvailableSlots {
  id: string;
  name: string;
  city: string | null;
  province: string | null;
  code: string | null;
  hcFilled: number;
  hcTotal: number;
  openSlots: number;
}

export type StoreLookupMap = Map<
  string,
  { id?: string; city: string | null; province: string | null; code: string | null }
>;

// ---------------------------------------------------------------------------
// Helper Functions & Badge Renderers
// ---------------------------------------------------------------------------

export function plantillaStatusVariant(status: string | null | undefined): BadgeVariant {
  switch ((status ?? "").toLowerCase().trim()) {
    case "active":
      return "success";
    case "on leave":
    case "on_leave":
      return "warning";
    case "floating":
      return "neutral";
    case "pending transfer":
    case "pending_transfer":
      return "info";
    case "pending separation":
    case "pending_separation":
      return "danger";
    case "suspended":
      return "warning";
    case "inactive":
    case "terminated":
      return "neutral";
    default:
      return "neutral";
  }
}

export function getInitials(firstName: string | null, lastName: string | null, fullName?: string | null): string {
  if (firstName || lastName) {
    const f = (firstName?.trim() || "")[0] ?? "";
    const l = (lastName?.trim() || "")[0] ?? "";
    return (f + l).toUpperCase() || "EM";
  }
  if (fullName && fullName.trim()) {
    const parts = fullName.trim().split(/\s+/);
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return (parts[0][0] ?? "E").toUpperCase();
  }
  return "EM";
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return "—";
  try {
    const d = new Date(value);
    if (isNaN(d.getTime())) {
      const parts = value.split("-");
      if (parts.length === 3) {
        return `${parts[1]}/${parts[2]}/${parts[0]}`;
      }
      return value;
    }
    return d.toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
    });
  } catch {
    return value;
  }
}

export function resolveVacancyWorkflowStage(v: VacancyListItem): VacancyWorkflowStage {
  const badgeRaw = (v.stageBadge || "").trim();
  const pipeRaw = (v.pipelineStatus || "").trim();
  const vacRaw = (v.vacancyStatus || "").trim();
  const target = `${badgeRaw} ${pipeRaw} ${vacRaw}`.toLowerCase();

  // 1. Vacancy - Closure (takes precedence if pending closure or closure stage)
  const isClosure =
    v.hasPendingClosure === true ||
    (v.closureRequestStatus || "").toLowerCase() === "pending" ||
    target.includes("closure") ||
    target.includes("for closure");

  if (isClosure) {
    return "Vacancy - Closure";
  }

  // 2. HR Emploc Stages
  if (target.includes("correction")) {
    return "HR Emploc - Correction";
  }
  if (target.includes("review")) {
    return "HR Emploc - Review";
  }
  if (target.includes("for emploc") || target.includes("for_emploc")) {
    return "HR Emploc - For Emploc";
  }
  if (target.includes("ready") || target.includes("complete")) {
    return "HR Emploc - Ready";
  }
  if (
    target.includes("hr emploc") ||
    target.includes("emploc") ||
    target.includes("onboard")
  ) {
    return "HR Emploc - Pending";
  }

  // 3. Vacancy - Pipeline
  if (target.includes("pipeline")) {
    return "Vacancy - Pipeline";
  }

  const hasApplicant = Boolean(
    v.applicantName &&
    v.applicantName.trim() !== "" &&
    v.applicantName.trim() !== "—" &&
    v.applicantName.trim() !== "-"
  );

  if (hasApplicant) {
    return "Vacancy - Pipeline";
  }

  // 4. Vacancy - Open
  return "Vacancy - Open";
}

export function isHrPipelineWorkflowStage(stage: VacancyWorkflowStage): boolean {
  return (
    stage === "HR Emploc - Pending" ||
    stage === "HR Emploc - For Emploc" ||
    stage === "HR Emploc - Correction" ||
    stage === "HR Emploc - Ready" ||
    stage === "HR Emploc - Review"
  );
}

export function getVacancyRemainingCapacity(v: VacancyListItem): number {
  const total = v.hcTotal ?? v.headcount ?? 1;
  const filled = v.hcFilled ?? 0;
  const remaining = Math.max(0, total - filled);
  // An open vacancy requisition represents at least 1 unfilled slot
  if (
    remaining === 0 &&
    (v.stageBadge === "Vacancy - Open" ||
      v.pipelineStatus === "Vacancy - Open" ||
      v.vacancyStatus === "Open" ||
      v.derivedStatus === "Open")
  ) {
    return 1;
  }
  return remaining;
}

export function renderVacancyStatusBadge(stage: VacancyWorkflowStage) {
  switch (stage) {
    case "Vacancy - Open":
      return (
        <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold bg-surface-muted text-text-secondary border border-border-default">
          Vacancy - Open
        </span>
      );
    case "Vacancy - Pipeline":
      return (
        <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold bg-blue-50 text-blue-700 border border-blue-200 dark:bg-blue-950 dark:text-blue-300 dark:border-blue-800">
          Vacancy - Pipeline
        </span>
      );
    case "Vacancy - Closure":
      return (
        <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold bg-rose-50 text-rose-700 border border-rose-200 dark:bg-rose-950 dark:text-rose-300 dark:border-rose-800">
          Vacancy - Closure
        </span>
      );
    case "HR Emploc - Pending":
      return (
        <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold bg-amber-50 text-amber-800 border border-amber-200 dark:bg-amber-950 dark:text-amber-300 dark:border-amber-800">
          HR Emploc - Pending
        </span>
      );
    case "HR Emploc - For Emploc":
      return (
        <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold bg-indigo-50 text-indigo-700 border border-indigo-200 dark:bg-indigo-950 dark:text-indigo-300 dark:border-indigo-800">
          HR Emploc - For Emploc
        </span>
      );
    case "HR Emploc - Correction":
      return (
        <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold bg-red-50 text-red-700 border border-red-200 dark:bg-red-950 dark:text-red-300 dark:border-red-800">
          HR Emploc - Correction
        </span>
      );
    case "HR Emploc - Ready":
      return (
        <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200 dark:bg-emerald-950 dark:text-emerald-300 dark:border-emerald-800">
          HR Emploc - Ready
        </span>
      );
    case "HR Emploc - Review":
      return (
        <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold bg-purple-50 text-purple-700 border border-purple-200 dark:bg-purple-950 dark:text-purple-300 dark:border-purple-800">
          HR Emploc - Review
        </span>
      );
    default:
      return (
        <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold bg-surface-muted text-text-secondary border border-border-default">
          {stage}
        </span>
      );
  }
}

export function isDeactivationRecord(emp: PlantillaEmployeeListItem): boolean {
  const s = (emp.plantillaStatus || "").toLowerCase().trim();
  const sep = (emp.separationType || "").toLowerCase().trim();
  const overlay = deriveDeactivationOverlay(emp.plantillaStatus);
  return (
    overlay.isPendingSeparation ||
    s === "pending for deactivation" ||
    s === "pending_for_deactivation" ||
    s === "pending deactivation" ||
    s === "pending_deactivation" ||
    s === "for deactivation" ||
    s === "pending separation" ||
    s === "pending_separation" ||
    s === "deactivated" ||
    sep === "pending deactivation" ||
    sep === "pending_deactivation" ||
    sep === "for deactivation" ||
    sep === "deactivated"
  );
}

export function isFloatingRecord(emp: PlantillaEmployeeListItem): boolean {
  if (isDeactivationRecord(emp)) return false;
  const s = (emp.plantillaStatus || "").toLowerCase().trim();
  const sep = (emp.separationType || "").toLowerCase().trim();
  return s === "floating" || sep === "floating";
}

export function FloatingDoleBadge({ days }: { days: number }) {
  const remaining = Math.max(0, 180 - days);

  if (days >= 180) {
    return (
      <span
        title="DOLE Art. 301 limit breached (maximum 180-day floating period exceeded). Immediate recall or statutory separation required."
        className="inline-flex items-center gap-1 rounded-full bg-red-100 px-2 py-0.5 text-[10px] font-bold text-red-800 border border-red-300 dark:bg-red-950/70 dark:text-red-300 dark:border-red-800 shrink-0"
      >
        <span className="h-1.5 w-1.5 rounded-full bg-red-600 animate-pulse" />
        <span>{days}d • DOLE Breach</span>
      </span>
    );
  }

  if (days >= 120) {
    return (
      <span
        title={`Critical aging: ${days} days floating (${remaining} days remaining until DOLE 180-day temporary layoff maximum).`}
        className="inline-flex items-center gap-1 rounded-full bg-rose-50 px-2 py-0.5 text-[10px] font-bold text-rose-700 border border-rose-300 dark:bg-rose-950/60 dark:text-rose-300 dark:border-rose-800 shrink-0"
      >
        <span className="h-1.5 w-1.5 rounded-full bg-rose-500" />
        <span>{days}d • {remaining}d left</span>
      </span>
    );
  }

  if (days >= 60) {
    return (
      <span
        title={`Aged floating: ${days} days in pool (${remaining} days until DOLE 180-day limit).`}
        className="inline-flex items-center gap-1 rounded-full bg-amber-50 px-2 py-0.5 text-[10px] font-bold text-amber-800 border border-amber-300 dark:bg-amber-950/60 dark:text-amber-300 dark:border-amber-800 shrink-0"
      >
        <span className="h-1.5 w-1.5 rounded-full bg-amber-500" />
        <span>{days}d • {remaining}d left</span>
      </span>
    );
  }

  if (days >= 30) {
    return (
      <span
        title={`Active floating: ${days} days (${remaining} days until DOLE 180-day limit).`}
        className="inline-flex items-center gap-1 rounded-full bg-blue-50 px-2 py-0.5 text-[10px] font-bold text-blue-700 border border-blue-200 dark:bg-blue-950/60 dark:text-blue-300 dark:border-blue-800 shrink-0"
      >
        <span className="h-1.5 w-1.5 rounded-full bg-blue-500" />
        <span>{days}d • {remaining}d left</span>
      </span>
    );
  }

  return (
    <span
      title={`Fresh floating: ${days} days elapsed (${remaining} days until DOLE 180-day limit).`}
      className="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-[10px] font-semibold text-emerald-800 border border-emerald-200 dark:bg-emerald-950/50 dark:text-emerald-300 dark:border-emerald-800 shrink-0"
    >
      <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
      <span>{days}d • {remaining}d left</span>
    </span>
  );
}

export function isInactiveRecord(emp: PlantillaEmployeeListItem): boolean {
  if (isFloatingRecord(emp)) return false;
  const s = (emp.plantillaStatus || "").toLowerCase().trim();
  const sep = (emp.separationType || "").toLowerCase().trim();
  const overlay = deriveDeactivationOverlay(emp.plantillaStatus);
  return (
    s === "resigned" ||
    s === "awol" ||
    s === "terminated" ||
    s === "inactive" ||
    s === "separated" ||
    s === "pending for deactivation" ||
    s === "pending_for_deactivation" ||
    s === "pending deactivation" ||
    s === "pending_deactivation" ||
    s === "for deactivation" ||
    s === "pending separation" ||
    s === "pending_separation" ||
    s === "deactivated" ||
    sep === "resigned" ||
    sep === "awol" ||
    sep === "terminated" ||
    sep === "separated" ||
    sep === "pending deactivation" ||
    sep === "pending_deactivation" ||
    sep === "for deactivation" ||
    sep === "deactivated" ||
    overlay.isPendingSeparation ||
    emp.isActive === false
  );
}

export function isOnLeaveRecord(emp: PlantillaEmployeeListItem): boolean {
  if (isDeactivationRecord(emp)) return false;
  if (isFloatingRecord(emp)) return false;
  if (isInactiveRecord(emp)) return false;
  const s = (emp.plantillaStatus || "").toLowerCase().trim();
  return s === "on leave" || s === "on_leave";
}

export function resolveLeaveDetails(
  emp: PlantillaEmployeeListItem,
  coverage?: ActiveCoverageItem | null,
): { reason: string; edr: string | null } {
  const remarks = (emp.separationRemarks || "").trim();

  let reason = "";
  if (remarks) {
    const match = remarks.match(/Reason:\s*([^|]+)/i);
    const candidate = (match ? match[1] : remarks).trim();
    const found = VALID_LEAVE_REASONS.find(
      (r) => r.toLowerCase() === candidate.toLowerCase() || candidate.toLowerCase().includes(r.toLowerCase()),
    );
    if (found) {
      reason = found;
    } else if (/maternity|paternity/i.test(candidate)) {
      reason = "Maternity / Paternity Leave";
    } else if (/sick|medical/i.test(candidate)) {
      reason = "Sick / Medical Leave";
    } else if (/vacation/i.test(candidate)) {
      reason = "Vacation Leave";
    } else if (/emergency/i.test(candidate)) {
      reason = "Emergency Family Leave";
    } else if (/authorized|other/i.test(candidate)) {
      reason = "Other Authorized Leave";
    } else if (candidate) {
      reason = candidate;
    }
  }

  if (!reason) {
    reason = "Sick / Medical Leave";
  }

  let edr: string | null = null;
  if (coverage?.endDate) {
    edr = coverage.endDate;
  } else if (remarks) {
    const edrMatch = remarks.match(/EDR:\s*([0-9]{4}-[0-9]{2}-[0-9]{2}|[^\s|]+)/i);
    if (edrMatch) {
      edr = edrMatch[1].trim();
    }
  }

  return { reason, edr };
}

export function getEdrLapseStatus(edr: string | null | undefined): {
  daysLapsed: number;
  isLapsed: boolean;
  isBreached: boolean;
} {
  if (!edr) return { daysLapsed: 0, isLapsed: false, isBreached: false };
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const returnDate = new Date(edr);
    returnDate.setHours(0, 0, 0, 0);
    if (isNaN(returnDate.getTime())) {
      return { daysLapsed: 0, isLapsed: false, isBreached: false };
    }
    const diffTime = today.getTime() - returnDate.getTime();
    const daysLapsed = Math.floor(diffTime / (1000 * 60 * 60 * 24));
    return {
      daysLapsed,
      isLapsed: daysLapsed > 0 && daysLapsed < 3,
      isBreached: daysLapsed >= 3,
    };
  } catch {
    return { daysLapsed: 0, isLapsed: false, isBreached: false };
  }
}
