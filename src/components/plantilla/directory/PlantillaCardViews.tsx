import React from "react";
import {
  ChevronRight,
  MapPin,
  CheckCircle2,
  AlertCircle,
  UserCheck,
  RotateCw,
  Clock,
  User,
  Building,
  Calendar,
  UserMinus,
} from "lucide-react";
import { StatusBadge } from "@/components/ui/StatusBadge";
import type {
  PlantillaEmployeeListItem,
  ActiveCoverageItem,
} from "@/lib/queries/plantilla";
import { getFloatingDurationDays } from "@/lib/queries/plantilla";
import type { VacancyListItem } from "@/lib/queries/vacancy";
import {
  formatPersonName,
  formatPosition,
  formatStoreName,
} from "@/lib/utils/displayText";
import {
  getInitials,
  formatDate,
  resolveVacancyWorkflowStage,
  resolveLeaveDetails,
  getEdrLapseStatus,
  FloatingDoleBadge,
  plantillaStatusVariant,
  type StoreLookupMap,
  type PipelineCandidateItem,
} from "./types";

// ---------------------------------------------------------------------------
// Employee Card Component (Active)
// ---------------------------------------------------------------------------

export function EmployeeCard({
  row,
  onSelect,
  storeLookupMap,
}: {
  row: PlantillaEmployeeListItem;
  onSelect: () => void;
  storeLookupMap: StoreLookupMap;
}) {
  const displayName =
    formatPersonName(
      row.firstName,
      row.lastName,
      null,
      row.fullName || `${row.lastName || ""}, ${row.firstName || ""}`,
    ) || "—";

  const initials = getInitials(row.firstName, row.lastName);
  const storeInfo = row.primaryStoreName
    ? storeLookupMap.get(row.primaryStoreName.toLowerCase().trim())
    : null;
  const locationLabel = [storeInfo?.city, storeInfo?.province].filter(Boolean).join(", ");

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onSelect}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onSelect();
        }
      }}
      className="group relative flex flex-col justify-between overflow-hidden rounded-xl border border-border-default bg-surface-base p-4 text-left shadow-xs transition-all duration-200 hover:-translate-y-0.5 hover:border-brand-primary hover:shadow-md cursor-pointer focus:outline-none focus:ring-2 focus:ring-brand-primary border-l-4 border-l-emerald-600"
    >
      <div>
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 shrink-0 rounded-full bg-surface-muted border border-border-default text-brand-primary font-bold text-xs flex items-center justify-center shadow-xs">
            {initials}
          </div>

          <div className="flex-1 min-w-0">
            <h4 className="text-sm font-bold text-text-primary truncate group-hover:text-brand-primary transition-colors">
              {displayName}
            </h4>

            <div className="flex items-center gap-1.5 text-xs text-text-muted mt-0.5 truncate">
              <span className="font-mono text-text-secondary">
                {row.cgCode || row.vcode ? `${row.cgCode || row.vcode} • ${row.employeeNo}` : row.employeeNo || "—"}
              </span>
              <span className="text-text-muted/40">•</span>
              <span className="font-semibold text-brand-primary truncate">
                {row.positionTitle ? formatPosition(row.positionTitle) : "General Staff"}
              </span>
            </div>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            {row.plantillaStatus && (
              <StatusBadge
                variant={plantillaStatusVariant(row.plantillaStatus)}
                text={row.plantillaStatus}
              />
            )}
            <ChevronRight className="h-5 w-5 text-text-muted/60 transition-transform group-hover:translate-x-0.5" />
          </div>
        </div>
      </div>

      <div className="mt-3.5 pt-2.5 border-t border-border-subtle flex flex-wrap items-center justify-between gap-2 text-xs text-text-secondary">
        <div className="flex items-center gap-1.5 truncate max-w-[70%]">
          <MapPin className="h-3.5 w-3.5 text-text-muted shrink-0" />
          <span className="truncate font-medium text-text-secondary">
            {formatStoreName(row.primaryStoreName || "—")}
            {locationLabel ? ` (${locationLabel})` : ""}
          </span>
        </div>

        <span className="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-semibold border bg-surface-muted text-text-secondary border-border-default">
          {row.assignmentType || "Stationary"}
        </span>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Employee On-Leave Card Component
// ---------------------------------------------------------------------------

export function EmployeeOnLeaveCard({
  row,
  coverageItem,
  onSelect,
  storeLookupMap,
  onAssignReliever,
  onReturnToActive,
}: {
  row: PlantillaEmployeeListItem;
  coverageItem: ActiveCoverageItem | null | undefined;
  onSelect: () => void;
  storeLookupMap: StoreLookupMap;
  onAssignReliever: (emp: PlantillaEmployeeListItem) => void;
  onReturnToActive: (emp: PlantillaEmployeeListItem, reliever: ActiveCoverageItem | null) => void;
}) {
  const displayName =
    formatPersonName(
      row.firstName,
      row.lastName,
      null,
      row.fullName || `${row.lastName || ""}, ${row.firstName || ""}`,
    ) || "—";

  const initials = getInitials(row.firstName, row.lastName);
  const storeInfo = row.primaryStoreName
    ? storeLookupMap.get(row.primaryStoreName.toLowerCase().trim())
    : null;
  const locationLabel = [storeInfo?.city, storeInfo?.province].filter(Boolean).join(", ");
  const assignedReliever = coverageItem ?? null;
  const leaveInfo = resolveLeaveDetails(row, assignedReliever);
  const lapseStatus = getEdrLapseStatus(leaveInfo.edr);

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onSelect}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onSelect();
        }
      }}
      className="group relative flex flex-col justify-between overflow-hidden rounded-xl border border-border-default bg-surface-base p-4 text-left shadow-xs transition-all duration-200 hover:-translate-y-0.5 hover:border-brand-primary hover:shadow-md cursor-pointer focus:outline-none focus:ring-2 focus:ring-brand-primary border-l-4 border-l-amber-500"
    >
      <div>
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 shrink-0 rounded-full bg-amber-50 border border-amber-200 text-amber-700 font-bold text-xs flex items-center justify-center shadow-xs dark:bg-amber-950 dark:border-amber-800 dark:text-amber-300">
            {initials}
          </div>

          <div className="flex-1 min-w-0">
            <h4 className="text-sm font-bold text-text-primary truncate group-hover:text-brand-primary transition-colors">
              {displayName}
            </h4>

            <div className="flex items-center gap-1.5 text-xs text-text-muted mt-0.5 truncate">
              <span className="font-mono text-text-secondary">{row.employeeNo || "—"}</span>
              <span className="text-text-muted/40">•</span>
              <span className="font-semibold text-text-secondary truncate">
                {row.positionTitle ? formatPosition(row.positionTitle) : "General Staff"}
              </span>
            </div>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <span
              className="inline-flex items-center px-1.5 py-0.2 rounded text-[10px] font-semibold bg-amber-100 text-amber-800 border border-amber-300 dark:bg-amber-950 dark:text-amber-200 dark:border-amber-800 max-w-[140px] truncate"
              title={leaveInfo.reason}
            >
              {leaveInfo.reason}
            </span>
            <ChevronRight className="h-5 w-5 text-text-muted/60 transition-transform group-hover:translate-x-0.5" />
          </div>
        </div>

        {/* Reliever Coverage Status & EDR */}
        <div className="mt-3 rounded-lg border border-border-subtle bg-surface-muted/60 px-3 py-2 text-xs flex items-center justify-between gap-2">
          {coverageItem ? (
            <div className="flex items-center gap-1.5 text-emerald-700 dark:text-emerald-300 font-medium min-w-0">
              <CheckCircle2 className="h-3.5 w-3.5 shrink-0" />
              <span className="truncate">Covered by {coverageItem.employeeName}</span>
            </div>
          ) : (
            <div className="flex items-center gap-1.5 text-amber-700 dark:text-amber-300 font-medium">
              <AlertCircle className="h-3.5 w-3.5 shrink-0" />
              <span>No Reliever Assigned</span>
            </div>
          )}
          {leaveInfo.edr && (
            <div className="flex items-center gap-1.5 text-[11px] font-mono shrink-0">
              <span className="text-text-muted">EDR:</span>
              <span
                className={`font-semibold ${
                  lapseStatus.isBreached
                    ? "text-red-600 dark:text-red-400 font-bold"
                    : lapseStatus.isLapsed
                    ? "text-amber-700 dark:text-amber-300"
                    : "text-text-primary"
                }`}
              >
                {formatDate(leaveInfo.edr)}
              </span>
              {lapseStatus.isBreached ? (
                <span className="rounded px-1 py-0.2 text-[9px] font-bold bg-red-100 text-red-800 border border-red-300 dark:bg-red-950 dark:text-red-200">
                  Breached ({lapseStatus.daysLapsed}d)
                </span>
              ) : lapseStatus.isLapsed ? (
                <span className="rounded px-1 py-0.2 text-[9px] font-bold bg-amber-100 text-amber-800 border border-amber-300 dark:bg-amber-950 dark:text-amber-200">
                  Lapsed ({lapseStatus.daysLapsed}d)
                </span>
              ) : null}
            </div>
          )}
        </div>
      </div>

      <div className="mt-3.5 pt-2.5 border-t border-border-subtle flex flex-wrap items-center justify-between gap-2 text-xs text-text-secondary">
        <div className="flex items-center gap-1.5 truncate max-w-[55%]">
          <MapPin className="h-3.5 w-3.5 text-text-muted shrink-0" />
          <span className="truncate font-medium text-text-secondary">
            {formatStoreName(row.primaryStoreName || "—")}
            {locationLabel ? ` (${locationLabel})` : ""}
          </span>
        </div>

        <div className="flex items-center gap-1.5 shrink-0">
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              onAssignReliever(row);
            }}
            className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-base px-2 py-1 text-[11px] font-semibold text-text-secondary hover:text-brand-primary hover:bg-surface-hover transition-colors shadow-2xs cursor-pointer"
          >
            <UserCheck className="h-3 w-3" />
            <span>Reliever</span>
          </button>
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              onReturnToActive(row, coverageItem ?? null);
            }}
            className="inline-flex items-center gap-1 rounded-md border border-brand-primary/40 bg-brand-50 px-2 py-1 text-[11px] font-semibold text-brand-700 hover:bg-brand-100 dark:bg-brand-950 dark:text-brand-300 transition-colors shadow-2xs cursor-pointer"
          >
            <RotateCw className="h-3 w-3" />
            <span>Return</span>
          </button>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Vacancy Card Component
// ---------------------------------------------------------------------------

export function VacancyCard({
  row,
  onSelect,
}: {
  row: VacancyListItem;
  onSelect: () => void;
  storeLookupMap: StoreLookupMap;
}) {
  const codeDisplay = row.vcode || row.cgCode || "—";
  const rawName = row.storeName || "Unnamed Store";
  const cleanStoreName = formatStoreName(rawName).replace(/\s*\([^)]*\)/g, "").trim();
  const isRoving = Boolean(
    row.employmentType?.toLowerCase() === "roving" ||
    row.cgCode ||
    row.vcode?.startsWith("CG-")
  );
  const hasApplicant = Boolean(row.applicantName && row.applicantName.trim() !== "" && row.applicantName.trim() !== "—");
  const applicantDisplay = hasApplicant ? formatPersonName(row.applicantName) : null;
  const stage = resolveVacancyWorkflowStage(row);
  const rowHcTotal = row.hcTotal ?? row.headcount ?? 1;
  const assignedCount = row.assignedStoreDetails?.length || row.assignedStores?.length || 0;
  const rovingSlotShare = row.slotShare ?? (isRoving && assignedCount > 1 ? Math.round((1.0 / assignedCount) * 100) / 100 : null);
  const hcDisplay = isRoving && rovingSlotShare != null ? rovingSlotShare : 1;
  const remarksDisplay = (
    row.remarks ||
    row.opsRemarks ||
    row.recruitmentRemarks ||
    row.hrRemarks ||
    row.closureReason ||
    ""
  ).trim();

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onSelect}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onSelect();
        }
      }}
      className="group relative flex flex-col justify-between overflow-hidden rounded-xl border border-border-default bg-surface-base p-4 text-left shadow-xs transition-all duration-200 hover:-translate-y-0.5 hover:border-brand-primary hover:shadow-md cursor-pointer focus:outline-none focus:ring-2 focus:ring-brand-primary border-l-4 border-l-sky-500"
    >
      <div>
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <span className="font-mono text-xs font-bold text-text-primary">
                {codeDisplay}
              </span>
              {row.cgCode && row.vcode && row.cgCode !== row.vcode && (
                <span className="font-mono text-[10px] text-text-muted">
                  ({row.vcode})
                </span>
              )}
              {isRoving && (
                <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[10px] font-semibold bg-blue-50 text-brand-700 border border-brand-200 dark:bg-brand-950 dark:text-brand-300 dark:border-brand-800">
                  Roving
                </span>
              )}
            </div>
            <h4 className="text-sm font-bold text-text-primary truncate mt-0.5 group-hover:text-brand-primary transition-colors">
              {cleanStoreName}
            </h4>
          </div>

          <div className="flex items-center gap-1.5 shrink-0">
            <span
              title={
                isRoving && rovingSlotShare != null
                  ? `${hcDisplay} roving headcount share (${row.slotFraction || `1/${assignedCount}`}) across ${assignedCount} stores`
                  : "1 approved headcount"
              }
              className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-bold bg-red-50 text-red-700 border border-red-200 dark:bg-red-950/80 dark:text-red-300 dark:border-red-800 shrink-0"
            >
              {hcDisplay}
            </span>
            <ChevronRight className="h-5 w-5 text-text-muted/60 transition-transform group-hover:translate-x-0.5" />
          </div>
        </div>

        <div className="mt-2 flex items-center justify-between text-xs text-text-muted">
          <span className="font-medium text-text-secondary truncate">
            {row.position_title ? formatPosition(row.position_title) : "Store Personnel"}
          </span>
          <span className="inline-flex items-center gap-1 text-[11px] font-medium text-text-muted">
            <Clock className="h-3 w-3" />
            {row.agingDays != null ? `${row.agingDays}d aging` : "—"}
          </span>
        </div>

        {applicantDisplay ? (
          <div className="mt-2.5 flex items-center gap-1.5 rounded-lg border border-border-subtle bg-surface-muted/50 px-2.5 py-1.5 text-xs text-text-secondary">
            <User className="h-3.5 w-3.5 text-text-muted shrink-0" />
            <span className="truncate font-medium">{applicantDisplay}</span>
          </div>
        ) : (
          <div className="mt-2.5 flex items-center gap-1.5 rounded-lg border border-dashed border-border-subtle bg-surface-muted/20 px-2.5 py-1.5 text-xs text-text-muted">
            <span>No active applicant assigned</span>
          </div>
        )}

        {remarksDisplay && (
          <div className="mt-2 flex items-start gap-1.5 rounded-lg border border-border-subtle bg-surface-muted/30 px-2.5 py-1.5 text-xs text-text-secondary" title={remarksDisplay}>
            <span className="truncate italic font-medium">
              &ldquo;{remarksDisplay}&rdquo;
            </span>
          </div>
        )}
      </div>

      <div className="mt-3.5 pt-2.5 border-t border-border-subtle flex items-center justify-between gap-2 text-xs text-text-secondary">
        <span className="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-medium bg-surface-muted text-text-secondary border border-border-default">
          {stage}
        </span>
        <span className="text-[11px] text-text-muted font-mono">
          HC Capacity: {rowHcTotal}
        </span>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Pipeline Candidate Card Component (Recruitment / Onboarding Before Plantilla)
// ---------------------------------------------------------------------------

export function PipelineCard({
  row,
  onSelect,
}: {
  row: PipelineCandidateItem;
  onSelect?: () => void;
}) {
  const displayName = formatPersonName(row.applicant_name) || "—";
  const initials = getInitials(null, null, row.applicant_name);
  const cleanStore = row.store_name ? formatStoreName(row.store_name) : "—";
  const dateStr = formatDate(row.date_requested || row.hired_date);
  const isReqComplete = row.requirement_overall_status?.toLowerCase() === "complete";

  return (
    <div
      onClick={onSelect}
      role="button"
      tabIndex={0}
      className="group relative flex flex-col justify-between rounded-xl border border-border-default bg-surface-base p-3.5 shadow-xs transition hover:border-border-hover hover:bg-surface-hover hover:shadow-sm cursor-pointer"
    >
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-2.5 min-w-0">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300 font-semibold text-xs border border-blue-200 dark:border-blue-800">
            {initials}
          </div>
          <div className="min-w-0 flex-1">
            <h4 className="text-xs font-semibold text-text-primary truncate">
              {displayName}
            </h4>
            <div className="flex items-center gap-1.5 text-[11px] text-text-secondary">
              <span className="font-mono">{row.vcode || "—"}</span>
              <span>•</span>
              <span className="truncate">{row.position ? formatPosition(row.position) : "Staff"}</span>
            </div>
          </div>
        </div>
        <span className="shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold bg-blue-50 text-blue-700 border border-blue-200 dark:bg-blue-950/60 dark:text-blue-300 dark:border-blue-800">
          {row.status || "Pending Emploc"}
        </span>
      </div>

      <div className="mt-3 flex flex-col gap-1.5 border-t border-table-rule pt-2.5 text-xs text-text-secondary">
        <div className="flex items-center justify-between">
          <span className="flex items-center gap-1 text-[11px] text-text-muted truncate">
            <Building className="h-3 w-3 shrink-0" />
            <span className="truncate">{cleanStore}</span>
          </span>
          <span
            className={`text-[10px] font-medium px-1.5 py-0.5 rounded ${
              isReqComplete
                ? "bg-emerald-50 text-emerald-700 dark:bg-emerald-950/60 dark:text-emerald-300"
                : "bg-amber-50 text-amber-700 dark:bg-amber-950/60 dark:text-amber-300"
            }`}
          >
            Reqs: {row.requirement_overall_status || "Incomplete"}
          </span>
        </div>
        <div className="flex items-center justify-between text-[11px] text-text-muted">
          <span>HRCO: {row.hrco_name || "—"}</span>
          <span>Endorsed: {dateStr}</span>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Employee Floating Card Component
// ---------------------------------------------------------------------------

export function EmployeeFloatingCard({
  row,
  onSelect,
  onAssignStore,
}: {
  row: PlantillaEmployeeListItem;
  onSelect: () => void;
  storeLookupMap: StoreLookupMap;
  onAssignStore: (emp: PlantillaEmployeeListItem) => void;
}) {
  const displayName =
    formatPersonName(
      row.firstName,
      row.lastName,
      null,
      row.fullName || `${row.lastName || ""}, ${row.firstName || ""}`,
    ) || "—";

  const initials = getInitials(row.firstName, row.lastName);

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onSelect}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onSelect();
        }
      }}
      className="group relative flex flex-col justify-between overflow-hidden rounded-xl border border-border-default bg-surface-base p-4 text-left shadow-xs transition-all duration-200 hover:-translate-y-0.5 hover:border-brand-primary hover:shadow-md cursor-pointer focus:outline-none focus:ring-2 focus:ring-brand-primary border-l-4 border-l-indigo-500"
    >
      <div>
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 shrink-0 rounded-full bg-indigo-50 border border-indigo-200 text-indigo-700 font-bold text-xs flex items-center justify-center shadow-xs dark:bg-indigo-950 dark:border-indigo-800 dark:text-indigo-300">
            {initials}
          </div>

          <div className="flex-1 min-w-0">
            <h4 className="text-sm font-bold text-text-primary truncate group-hover:text-brand-primary transition-colors">
              {displayName}
            </h4>

            <div className="flex items-center gap-1.5 text-xs text-text-muted mt-0.5 truncate">
              <span className="font-mono text-text-secondary">{row.employeeNo || "—"}</span>
              <span className="text-text-muted/40">•</span>
              <span className="font-semibold text-text-secondary truncate">
                {row.positionTitle ? formatPosition(row.positionTitle) : "General Staff"}
              </span>
            </div>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <StatusBadge variant="neutral" text="Floating" />
            <ChevronRight className="h-5 w-5 text-text-muted/60 transition-transform group-hover:translate-x-0.5" />
          </div>
        </div>

        <div className="mt-3 rounded-lg border border-border-subtle bg-surface-muted/40 px-3 py-2 text-xs flex items-center justify-between gap-2">
          <span className="text-text-muted text-[11px]">DOLE Tracking:</span>
          <FloatingDoleBadge days={getFloatingDurationDays(row)} />
        </div>
      </div>

      <div className="mt-3.5 pt-2.5 border-t border-border-subtle flex items-center justify-between gap-2 text-xs text-text-secondary">
        <span className="font-mono text-[11px] text-text-muted">
          {row.vcode || row.cgCode || "No VCode"}
        </span>

        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation();
            onAssignStore(row);
          }}
          className="inline-flex items-center gap-1 rounded-md border border-brand-primary/40 bg-brand-50 px-2.5 py-1 text-xs font-semibold text-brand-700 hover:bg-brand-100 dark:bg-brand-950 dark:text-brand-300 transition-colors shadow-2xs cursor-pointer"
        >
          <Building className="h-3 w-3" />
          <span>Assign Store</span>
        </button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Employee Deactivation Card Component
// ---------------------------------------------------------------------------

export function EmployeeDeactivationCard({
  row,
  onSelect,
  storeLookupMap,
}: {
  row: PlantillaEmployeeListItem;
  onSelect: () => void;
  storeLookupMap: StoreLookupMap;
}) {
  const displayName =
    formatPersonName(
      row.firstName,
      row.lastName,
      null,
      row.fullName || `${row.lastName || ""}, ${row.firstName || ""}`,
    ) || "—";

  const initials = getInitials(row.firstName, row.lastName);
  const storeInfo = row.primaryStoreName
    ? storeLookupMap.get(row.primaryStoreName.toLowerCase().trim())
    : null;
  const locationLabel = [storeInfo?.city, storeInfo?.province].filter(Boolean).join(", ");
  const s = (row.plantillaStatus || "").toLowerCase();
  const isDeactivated = s === "deactivated" || row.plantillaStatus?.toLowerCase().includes("deactivated");

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onSelect}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onSelect();
        }
      }}
      className="group relative flex flex-col justify-between overflow-hidden rounded-xl border border-border-default bg-surface-base p-4 text-left shadow-xs transition-all duration-200 hover:-translate-y-0.5 hover:border-brand-primary hover:shadow-md cursor-pointer focus:outline-none focus:ring-2 focus:ring-brand-primary border-l-4 border-l-rose-500"
    >
      <div>
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 shrink-0 rounded-full bg-rose-50 border border-rose-200 text-rose-700 font-bold text-xs flex items-center justify-center shadow-xs dark:bg-rose-950 dark:border-rose-800 dark:text-rose-300">
            {initials}
          </div>

          <div className="flex-1 min-w-0">
            <h4 className="text-sm font-bold text-text-primary truncate group-hover:text-brand-primary transition-colors">
              {displayName}
            </h4>

            <div className="flex items-center gap-1.5 text-xs text-text-muted mt-0.5 truncate">
              <span className="font-mono text-text-secondary">{row.employeeNo || "—"}</span>
              <span className="text-text-muted/40">•</span>
              <span className="font-mono text-text-muted">{row.vcode || row.cgCode || "—"}</span>
            </div>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            {isDeactivated ? (
              <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold bg-red-100 text-red-700 border border-red-300 dark:bg-red-950 dark:text-red-200 dark:border-red-800">
                Deactivated
              </span>
            ) : (
              <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold bg-amber-100 text-amber-800 border border-amber-300 dark:bg-amber-950 dark:text-amber-200 dark:border-amber-800">
                Pending for Deactivation
              </span>
            )}
            <ChevronRight className="h-5 w-5 text-text-muted/60 transition-transform group-hover:translate-x-0.5" />
          </div>
        </div>

        <div className="mt-2.5 text-xs text-text-secondary">
          <span className="font-medium text-text-secondary">{row.positionTitle ? formatPosition(row.positionTitle) : "General Staff"}</span>
        </div>
      </div>

      <div className="mt-3.5 pt-2.5 border-t border-border-subtle flex flex-wrap items-center justify-between gap-2 text-xs text-text-secondary">
        <div className="flex items-center gap-1.5 truncate max-w-[70%]">
          <MapPin className="h-3.5 w-3.5 text-text-muted shrink-0" />
          <span className="truncate font-medium text-text-secondary">
            {formatStoreName(row.primaryStoreName || "—")}
            {locationLabel ? ` (${locationLabel})` : ""}
          </span>
        </div>

        <span className="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-semibold border bg-surface-muted text-text-secondary border-border-default">
          {row.assignmentType || "Stationary"}
        </span>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Employee Inactive Card Component
// ---------------------------------------------------------------------------

export function EmployeeInactiveCard({
  row,
  onSelect,
  storeLookupMap,
  onRequestDeactivation,
}: {
  row: PlantillaEmployeeListItem;
  onSelect: () => void;
  storeLookupMap: StoreLookupMap;
  onRequestDeactivation?: (emp: PlantillaEmployeeListItem) => void;
}) {
  const displayName =
    formatPersonName(
      row.firstName,
      row.lastName,
      null,
      row.fullName || `${row.lastName || ""}, ${row.firstName || ""}`,
    ) || "—";

  const initials = getInitials(row.firstName, row.lastName);
  const storeInfo = row.primaryStoreName
    ? storeLookupMap.get(row.primaryStoreName.toLowerCase().trim())
    : null;
  const locationLabel = [storeInfo?.city, storeInfo?.province].filter(Boolean).join(", ");

  const rawType = (row.separationType || row.plantillaStatus || "Resigned").toLowerCase();
  let sepBadgeVariant: "warning" | "danger" | "neutral" = "neutral";
  let sepLabel = "Separated";
  if (rawType.includes("resigned") || rawType.includes("resignation")) {
    sepBadgeVariant = "warning";
    sepLabel = "Resigned";
  } else if (rawType.includes("awol")) {
    sepBadgeVariant = "danger";
    sepLabel = "AWOL";
  } else if (rawType.includes("terminat")) {
    sepBadgeVariant = "danger";
    sepLabel = "Terminated";
  }

  // Deactivation Status Resolution
  const s = (row.plantillaStatus || "").toLowerCase().trim();
  const sep = (row.separationType || "").toLowerCase().trim();
  const isDeactivated = s === "deactivated" || sep === "deactivated";
  const isPendingDeactivation =
    s === "pending for deactivation" ||
    s === "pending_for_deactivation" ||
    s === "pending deactivation" ||
    s === "pending_deactivation" ||
    s === "for deactivation" ||
    s === "pending separation" ||
    s === "pending_separation" ||
    sep === "pending deactivation" ||
    sep === "pending_deactivation" ||
    sep === "for deactivation";

  const hasExistingRequest = isDeactivated || isPendingDeactivation;

  const sepDateRaw = row.separationDate || row.dateDeployed;
  const formattedDate = sepDateRaw ? formatDate(sepDateRaw) : "—";
  const remarks = row.separationRemarks?.trim() || "";

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onSelect}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onSelect();
        }
      }}
      className="group relative flex flex-col justify-between overflow-hidden rounded-xl border border-border-default bg-surface-base p-4 text-left shadow-xs transition-all duration-200 hover:-translate-y-0.5 hover:border-brand-primary hover:shadow-md cursor-pointer focus:outline-none focus:ring-2 focus:ring-brand-primary border-l-4 border-l-slate-400"
    >
      <div>
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 shrink-0 rounded-full bg-surface-muted border border-border-default text-text-secondary font-bold text-xs flex items-center justify-center shadow-xs">
            {initials}
          </div>

          <div className="flex-1 min-w-0">
            <h4 className="text-sm font-bold text-text-primary truncate group-hover:text-brand-primary transition-colors">
              {displayName}
            </h4>

            <div className="flex items-center gap-1.5 text-xs text-text-muted mt-0.5 truncate">
              <span className="font-mono text-text-secondary font-medium">{row.employeeNo || "—"}</span>
              {row.positionTitle && (
                <>
                  <span className="text-text-muted/40">•</span>
                  <span className="font-semibold text-text-secondary truncate">
                    {formatPosition(row.positionTitle)}
                  </span>
                </>
              )}
            </div>
          </div>

          <div className="flex items-center gap-1.5 shrink-0">
            <StatusBadge variant={sepBadgeVariant} text={sepLabel} />
            {isDeactivated ? (
              <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[10px] font-semibold bg-red-100 text-red-700 border border-red-300 dark:bg-red-950 dark:text-red-200 dark:border-red-800">
                Deactivated
              </span>
            ) : isPendingDeactivation ? (
              <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[10px] font-semibold bg-amber-100 text-amber-800 border border-amber-300 dark:bg-amber-950 dark:text-amber-200 dark:border-amber-800">
                Pending Deact
              </span>
            ) : null}
            <ChevronRight className="h-5 w-5 text-text-muted/60 transition-transform group-hover:translate-x-0.5" />
          </div>
        </div>

        {/* Remarks box */}
        <div className="mt-3 rounded-lg border border-border-subtle bg-surface-muted/50 px-3 py-2 text-xs">
          <div className="text-[11px] font-semibold text-text-muted uppercase tracking-wider mb-0.5">
            Remarks
          </div>
          <div className="text-text-secondary truncate" title={remarks || undefined}>
            {remarks || "No operational remarks recorded"}
          </div>
        </div>
      </div>

      <div className="mt-3.5 pt-2.5 border-t border-border-subtle flex flex-wrap items-center justify-between gap-2 text-xs text-text-secondary">
        <div className="flex items-center gap-1.5 truncate max-w-[55%]">
          <MapPin className="h-3.5 w-3.5 text-text-muted shrink-0" />
          <span className="truncate font-medium text-text-secondary">
            {formatStoreName(row.primaryStoreName || "—")}
            {locationLabel ? ` (${locationLabel})` : ""}
          </span>
        </div>

        <div className="flex items-center gap-2">
          <div className="flex items-center gap-1 text-[11px] font-mono text-text-muted">
            <Calendar className="h-3.5 w-3.5 text-text-muted shrink-0" />
            <span>{formattedDate}</span>
          </div>

          {!hasExistingRequest && onRequestDeactivation && (
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                onRequestDeactivation(row);
              }}
              className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-surface-muted hover:bg-surface-base border border-border-default text-text-primary text-[11px] font-semibold transition cursor-pointer hover:border-brand-primary hover:text-brand-primary shadow-2xs"
              title={`Request deactivation for ${displayName}`}
            >
              <UserMinus className="w-3 h-3 text-text-secondary" />
              <span>Request Deactivation</span>
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
