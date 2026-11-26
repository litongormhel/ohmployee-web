import React from "react";
import {
  MapPin,
  UserCheck,
  RotateCw,
  Plus,
  AlertCircle,
  Clock,
  Building2,
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
  renderVacancyStatusBadge,
  resolveLeaveDetails,
  getEdrLapseStatus,
  FloatingDoleBadge,
  type StoreCapacityRow,
  type StoreLookupMap,
  type PipelineCandidateItem,
} from "./types";

// ---------------------------------------------------------------------------
// Tab 1: Active Employees Table
// ---------------------------------------------------------------------------

export function EmployeeActiveTable({
  rows,
  onRowClick,
  storeLookupMap,
  onUpdateStatus,
}: {
  rows: PlantillaEmployeeListItem[];
  onRowClick: (id: string) => void;
  storeLookupMap: StoreLookupMap;
  onUpdateStatus: (emp: PlantillaEmployeeListItem) => void;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs flex-1 min-h-0 flex flex-col">
      <div className="overflow-auto flex-1 min-h-0">
        <table className="w-full min-w-[980px] text-left text-xs">
          <thead className="sticky top-0 z-10 bg-table-header shadow-2xs">
            <tr className="border-b border-table-rule">
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Member
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Store
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Position
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Assignment
              </th>
              <th className="px-3.5 py-2 text-right text-xs font-semibold text-text-secondary whitespace-nowrap">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-table-rule">
            {rows.map((row) => {
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
                <tr
                  key={row.id}
                  className="transition-colors hover:bg-table-row-hover cursor-pointer"
                  onClick={() => onRowClick(row.id)}
                  tabIndex={0}
                  role="button"
                  aria-label={`View details for ${displayName}`}
                >
                  <td className="px-3.5 py-2">
                    <div className="flex items-center gap-2.5">
                      <div className="h-7.5 w-7.5 rounded-full bg-surface-muted border border-border-default text-brand-primary font-bold text-[11px] flex items-center justify-center shrink-0 shadow-xs">
                        {initials}
                      </div>
                      <div className="min-w-0">
                        <span className="font-semibold text-table-text text-xs hover:text-brand-primary transition-colors">
                          {displayName}
                        </span>
                        <div className="font-mono text-[11px] text-table-text-muted mt-0.5">
                          {row.cgCode || row.vcode ? `${row.cgCode || row.vcode} • ${row.employeeNo}` : row.employeeNo}
                        </div>
                      </div>
                    </div>
                  </td>

                  <td className="px-3.5 py-2 text-table-text">
                    <div className="min-w-0">
                      <div className="font-medium text-table-text text-xs">
                        {formatStoreName(row.primaryStoreName || row.vcode || "—")}
                      </div>
                      {locationLabel && (
                        <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-1.5 py-0.2 text-[10px] font-medium text-text-secondary border border-border-subtle mt-0.5">
                          <MapPin className="h-2.5 w-2.5 text-text-muted shrink-0" />
                          <span className="truncate max-w-[150px]">{locationLabel}</span>
                        </span>
                      )}
                    </div>
                  </td>

                  <td className="px-3.5 py-2">
                    <span className="font-medium text-table-text text-xs">
                      {row.positionTitle ? formatPosition(row.positionTitle) : "General Staff"}
                    </span>
                  </td>

                  <td className="px-3.5 py-2">
                    <span className="inline-flex items-center gap-1 rounded-md bg-surface-muted border border-border-default px-1.5 py-0.5 text-xs font-semibold text-text-secondary">
                      {row.assignmentType?.toLowerCase() === "roving" ? "Roving" : "Stationary"}
                    </span>
                  </td>

                  <td className="px-3.5 py-2 text-right">
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        onUpdateStatus(row);
                      }}
                      className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-base px-2.5 py-1 text-xs font-semibold text-text-secondary hover:text-brand-primary hover:border-border-strong hover:bg-surface-hover transition-colors shadow-2xs cursor-pointer"
                      aria-label={`Update employment status for ${displayName}`}
                    >
                      <UserCheck className="h-3 w-3" />
                      <span>Update</span>
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tab 2: On-Leave Employees Table (Leave Details & Reliever Flows)
// ---------------------------------------------------------------------------

export function EmployeeOnLeaveTable({
  rows,
  activeCoverageMap,
  onRowClick,
  storeLookupMap,
  onAssignReliever,
  onReturnToActive,
}: {
  rows: PlantillaEmployeeListItem[];
  activeCoverageMap: Map<string, ActiveCoverageItem>;
  onRowClick: (id: string) => void;
  storeLookupMap: StoreLookupMap;
  onAssignReliever: (emp: PlantillaEmployeeListItem) => void;
  onReturnToActive: (emp: PlantillaEmployeeListItem, reliever: ActiveCoverageItem | null) => void;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs flex-1 min-h-0 flex flex-col">
      <div className="overflow-auto flex-1 min-h-0">
        <table className="w-full min-w-[1050px] text-left text-xs">
          <thead className="sticky top-0 z-10 bg-table-header shadow-2xs">
            <tr className="border-b border-table-rule">
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Member
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Store
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Position
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Leave Reason
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                EDR
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Reliever (Moses HQ)
              </th>
              <th className="px-3.5 py-2 text-right text-xs font-semibold text-text-secondary whitespace-nowrap">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-table-rule">
            {rows.map((row) => {
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
              const assignedReliever = activeCoverageMap.get(row.id) ?? null;
              const leaveInfo = resolveLeaveDetails(row, assignedReliever);
              const lapseStatus = getEdrLapseStatus(leaveInfo.edr);

              return (
                <tr
                  key={row.id}
                  className="transition-colors hover:bg-table-row-hover cursor-pointer"
                  onClick={() => onRowClick(row.id)}
                  tabIndex={0}
                  role="button"
                  aria-label={`View on-leave record for ${displayName}`}
                >
                  {/* 1. Member */}
                  <td className="px-3.5 py-2">
                    <div className="flex items-center gap-2.5">
                      <div className="h-7.5 w-7.5 rounded-full bg-amber-50 border border-amber-200 text-amber-700 font-bold text-[11px] flex items-center justify-center shrink-0 shadow-xs dark:bg-amber-950/40 dark:border-amber-800 dark:text-amber-300">
                        {initials}
                      </div>
                      <div className="min-w-0">
                        <span className="font-semibold text-table-text text-xs hover:text-brand-primary transition-colors">
                          {displayName}
                        </span>
                        <div className="font-mono text-[11px] text-table-text-muted mt-0.5">
                          {row.cgCode || row.vcode ? `${row.cgCode || row.vcode} • ${row.employeeNo}` : row.employeeNo}
                        </div>
                      </div>
                    </div>
                  </td>

                  {/* 2. Store */}
                  <td className="px-3.5 py-2 text-table-text">
                    <div className="min-w-0">
                      <div className="font-medium text-table-text text-xs">
                        {formatStoreName(row.primaryStoreName || row.vcode || "—")}
                      </div>
                      {locationLabel && (
                        <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-1.5 py-0.2 text-[10px] font-medium text-text-secondary border border-border-subtle mt-0.5">
                          <MapPin className="h-2.5 w-2.5 text-text-muted shrink-0" />
                          <span className="truncate max-w-[150px]">{locationLabel}</span>
                        </span>
                      )}
                    </div>
                  </td>

                  {/* 3. Position */}
                  <td className="px-3.5 py-2">
                    <span className="font-medium text-table-text text-xs">
                      {row.positionTitle ? formatPosition(row.positionTitle) : "General Staff"}
                    </span>
                  </td>

                  {/* 4. Leave Reason */}
                  <td className="px-3.5 py-2">
                    <div className="flex flex-col">
                      <span className="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-semibold bg-amber-100 text-amber-800 border border-amber-300 dark:bg-amber-950 dark:text-amber-200 dark:border-amber-800 w-fit">
                        {leaveInfo.reason}
                      </span>
                    </div>
                  </td>

                  {/* 5. EDR */}
                  <td className="px-3.5 py-2">
                    {leaveInfo.edr ? (
                      <div className="flex flex-col">
                        <span
                          className={`font-mono text-xs ${
                            lapseStatus.isBreached
                              ? "font-bold text-red-600 dark:text-red-400"
                              : lapseStatus.isLapsed
                              ? "font-semibold text-amber-700 dark:text-amber-300"
                              : "text-table-text"
                          }`}
                        >
                          {formatDate(leaveInfo.edr)}
                        </span>
                        {lapseStatus.isBreached ? (
                          <span
                            className="inline-flex items-center gap-1 mt-0.5 rounded px-1.5 py-0.2 text-[10px] font-bold bg-red-100 text-red-800 border border-red-300 dark:bg-red-950 dark:text-red-200 dark:border-red-800 w-fit"
                            title="SLA Breached: 3+ days past EDR without action. Escalated to Operations Manager (OM)."
                          >
                            <AlertCircle className="h-2.5 w-2.5 shrink-0 text-red-600" />
                            <span>Breached ({lapseStatus.daysLapsed}d) • OM Escalated</span>
                          </span>
                        ) : lapseStatus.isLapsed ? (
                          <span
                            className="inline-flex items-center gap-1 mt-0.5 rounded px-1.5 py-0.2 text-[10px] font-bold bg-amber-100 text-amber-800 border border-amber-300 dark:bg-amber-950 dark:text-amber-200 dark:border-amber-800 w-fit"
                            title="EDR lapsed: HRCO notified to update status or return to Active."
                          >
                            <Clock className="h-2.5 w-2.5 shrink-0 text-amber-700" />
                            <span>Lapsed ({lapseStatus.daysLapsed}d) • HRCO Notified</span>
                          </span>
                        ) : null}
                      </div>
                    ) : (
                      <span className="font-mono text-xs text-text-muted">—</span>
                    )}
                  </td>

                  {/* 6. Reliever (Moses HQ) */}
                  <td className="px-3.5 py-2">
                    {assignedReliever ? (
                      <div className="flex flex-col">
                        <span className="font-semibold text-emerald-700 dark:text-emerald-300 text-xs flex items-center gap-1">
                          <UserCheck className="h-3 w-3" />
                          {assignedReliever.employeeName}
                        </span>
                        <span className="font-mono text-[10px] text-text-muted">
                          {assignedReliever.employeeNumber}
                        </span>
                      </div>
                    ) : (
                      <div className="flex items-center">
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            onAssignReliever(row);
                          }}
                          className="inline-flex items-center gap-1 rounded border border-brand-200 bg-brand-50 px-2 py-0.5 text-xs font-semibold text-brand-700 hover:bg-brand-100 transition shadow-2xs cursor-pointer dark:bg-brand-950 dark:border-brand-800 dark:text-brand-300"
                        >
                          <Plus className="h-2.5 w-2.5" />
                          <span>Assign Reliever</span>
                        </button>
                      </div>
                    )}
                  </td>

                  {/* 7. Actions */}
                  <td className="px-3.5 py-2 text-right">
                    <div className="flex items-center justify-end gap-1.5">
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          onReturnToActive(row, assignedReliever);
                        }}
                        className="inline-flex items-center gap-1 rounded-md bg-emerald-600 px-2 py-1 text-xs font-semibold text-white shadow-2xs hover:bg-emerald-700 transition cursor-pointer"
                      >
                        <RotateCw className="h-3 w-3" />
                        <span>Return to Active</span>
                      </button>
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tab 3: Vacancy Table (All Vacant Stores Only)
// ---------------------------------------------------------------------------

export function StoreVacancyTable({
  rows,
  onSelectVacancy,
}: {
  rows: VacancyListItem[];
  onSelectVacancy: (v: VacancyListItem) => void;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs flex-1 min-h-0 flex flex-col">
      <div className="overflow-auto flex-1 min-h-0">
        <table className="w-full min-w-[1050px] text-left text-xs">
          <thead className="sticky top-0 z-10 bg-table-header shadow-2xs">
            <tr className="border-b border-table-rule">
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                VCode / CGCode
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Store Branch / Anchor Branch
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Area & City
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Applicant
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Stage
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Aging
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Position
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                HC
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Remarks
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-table-rule">
            {rows.map((row) => {
              const codeDisplay = row.vcode || row.cgCode || "—";
              const rawName = row.storeName || "Unnamed Store";
              const cleanStoreName = formatStoreName(rawName).replace(/\s*\([^)]*\)/g, "").trim();
              const isRoving = Boolean(
                row.employmentType?.toLowerCase() === "roving" ||
                row.cgCode ||
                row.vcode?.startsWith("CG-")
              );
              const hasApplicant = Boolean(row.applicantName && row.applicantName.trim() !== "" && row.applicantName.trim() !== "—");
              const applicantDisplay = hasApplicant ? formatPersonName(row.applicantName) : "—";
              const stage = resolveVacancyWorkflowStage(row);
              const agingDaysDisplay = row.agingDays != null ? `${row.agingDays}d` : "—";
              const remarksText = (
                row.remarks ||
                row.opsRemarks ||
                row.recruitmentRemarks ||
                row.hrRemarks ||
                row.closureReason ||
                ""
              ).trim() || "—";
              const assignedCount = row.assignedStoreDetails?.length || row.assignedStores?.length || 0;
              const rovingSlotShare = row.slotShare ?? (isRoving && assignedCount > 1 ? Math.round((1.0 / assignedCount) * 100) / 100 : null);
              const hcDisplay = isRoving && rovingSlotShare != null ? rovingSlotShare : 1;

              return (
                <tr
                  key={row.id}
                  className="transition-colors hover:bg-table-row-hover cursor-pointer"
                  onClick={() => onSelectVacancy(row)}
                  tabIndex={0}
                  role="button"
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault();
                      onSelectVacancy(row);
                    }
                  }}
                  aria-label={`Open vacancy details for slot ${codeDisplay}`}
                >
                  <td className="px-3.5 py-2 font-mono text-xs font-bold text-text-primary whitespace-nowrap">
                    <div>{codeDisplay}</div>
                    {row.cgCode && row.vcode && row.cgCode !== row.vcode && (
                      <div className="font-mono text-[10px] font-normal text-text-muted mt-0.5">
                        {row.vcode}
                      </div>
                    )}
                  </td>
                  <td className="px-3.5 py-2 font-medium text-table-text">
                    <div className="flex items-center gap-1.5 flex-wrap">
                      <span className="font-bold text-xs">{cleanStoreName}</span>
                      {isRoving && (
                        <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[10px] font-semibold bg-blue-50 text-brand-700 border border-brand-200 dark:bg-brand-950 dark:text-brand-300 dark:border-brand-800">
                          Roving
                        </span>
                      )}
                    </div>
                  </td>
                  <td className="px-3.5 py-2 text-table-text whitespace-nowrap">
                    <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-2 py-0.5 text-[10px] font-medium text-text-secondary border border-border-subtle">
                      <MapPin className="h-2.5 w-2.5 text-text-muted shrink-0" />
                      <span>{row.storeLocation || "Unassigned Area"}</span>
                    </span>
                  </td>
                  <td className="px-3.5 py-2 whitespace-nowrap">
                    {hasApplicant ? (
                      <span className="font-medium text-text-primary text-xs">
                        {applicantDisplay}
                      </span>
                    ) : (
                      <span className="font-mono text-xs text-gray-400 dark:text-gray-500">
                        —
                      </span>
                    )}
                  </td>
                  <td className="px-3.5 py-2 whitespace-nowrap">
                    {renderVacancyStatusBadge(stage)}
                  </td>
                  <td className="px-3.5 py-2 font-mono text-xs font-semibold text-text-secondary tabular-nums whitespace-nowrap">
                    {agingDaysDisplay}
                  </td>
                  <td className="px-3.5 py-2 font-medium text-table-text text-xs whitespace-nowrap">
                    {row.position_title ? formatPosition(row.position_title) : "General Staff"}
                  </td>
                  <td className="px-3.5 py-2 whitespace-nowrap">
                    <span
                      title={
                        isRoving && rovingSlotShare != null
                          ? `${hcDisplay} roving headcount share across ${assignedCount} stores`
                          : "1 approved headcount"
                      }
                      className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-bold bg-red-50 text-red-700 border border-red-200 dark:bg-red-950/80 dark:text-red-300 dark:border-red-800 shrink-0"
                    >
                      {hcDisplay}
                    </span>
                  </td>
                  <td className="px-3.5 py-2 text-[11px] text-text-muted max-w-[200px] truncate" title={remarksText !== "—" ? remarksText : undefined}>
                    {remarksText}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tab 4: Pipeline Candidates Table (Recruitment / Onboarding Before Plantilla)
// ---------------------------------------------------------------------------

export function EmployeePipelineTable({
  rows,
  onRowClick,
}: {
  rows: PipelineCandidateItem[];
  onRowClick?: (id: string) => void;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs flex-1 min-h-0 flex flex-col">
      <div className="overflow-auto flex-1 min-h-0">
        <table className="w-full min-w-[980px] text-left text-xs">
          <thead className="sticky top-0 z-10 bg-table-header shadow-2xs">
            <tr className="border-b border-table-rule">
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Candidate Name
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                VCode
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Target Store
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Target Position
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Onboarding Stage
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Requirements
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                HRCO / Recruiter
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Endorsed Date
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-table-rule">
            {rows.map((row) => {
              const displayName = formatPersonName(row.applicant_name) || "—";
              const initials = getInitials(null, null, row.applicant_name);
              const cleanStoreName = row.store_name ? formatStoreName(row.store_name) : "—";
              const dateStr = formatDate(row.date_requested || row.hired_date);
              const isReqComplete = row.requirement_overall_status?.toLowerCase() === "complete";

              return (
                <tr
                  key={row.id}
                  className="transition-colors hover:bg-table-row-hover"
                  onClick={() => onRowClick?.(row.id)}
                  tabIndex={0}
                  role="button"
                  aria-label={`Candidate ${displayName}`}
                >
                  <td className="px-3.5 py-2">
                    <div className="flex items-center gap-2.5">
                      <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300 font-semibold text-[11px] border border-blue-200 dark:border-blue-800">
                        {initials}
                      </div>
                      <div className="min-w-0">
                        <span className="font-semibold text-table-text text-xs block truncate">
                          {displayName}
                        </span>
                      </div>
                    </div>
                  </td>
                  <td className="px-3.5 py-2 font-mono text-xs text-text-secondary whitespace-nowrap">
                    <span className="rounded-md border border-border-default bg-surface-muted px-1.5 py-0.5 text-[11px]">
                      {row.vcode || "—"}
                    </span>
                  </td>
                  <td className="px-3.5 py-2 whitespace-nowrap text-text-primary">
                    <span className="font-medium text-table-text text-xs">{cleanStoreName}</span>
                  </td>
                  <td className="px-3.5 py-2 whitespace-nowrap text-text-secondary">
                    {row.position ? formatPosition(row.position) : "Staff"}
                  </td>
                  <td className="px-3.5 py-2 whitespace-nowrap">
                    <span className="inline-flex items-center rounded-full border border-blue-200 bg-blue-50 px-2 py-0.5 text-[11px] font-semibold text-blue-700 dark:border-blue-800 dark:bg-blue-950/60 dark:text-blue-300">
                      {row.status || "Pending Emploc"}
                    </span>
                  </td>
                  <td className="px-3.5 py-2 whitespace-nowrap">
                    <span
                      className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[11px] font-semibold ${
                        isReqComplete
                          ? "border-emerald-200 bg-emerald-50 text-emerald-700 dark:border-emerald-800 dark:bg-emerald-950/60 dark:text-emerald-300"
                          : "border-amber-200 bg-amber-50 text-amber-700 dark:border-amber-800 dark:bg-amber-950/60 dark:text-amber-300"
                      }`}
                    >
                      {row.requirement_overall_status || "Incomplete"}
                    </span>
                  </td>
                  <td className="px-3.5 py-2 whitespace-nowrap text-text-secondary">
                    {row.hrco_name || "—"}
                  </td>
                  <td className="px-3.5 py-2 whitespace-nowrap text-text-secondary font-mono text-[11px]">
                    {dateStr}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tab 5: Floating Employees Table
// ---------------------------------------------------------------------------

export function EmployeeFloatingTable({
  rows,
  onRowClick,
  storeLookupMap,
  onAssignStore,
}: {
  rows: PlantillaEmployeeListItem[];
  onRowClick: (id: string) => void;
  storeLookupMap: StoreLookupMap;
  onAssignStore: (emp: PlantillaEmployeeListItem) => void;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs flex-1 min-h-0 flex flex-col">
      <div className="overflow-auto flex-1 min-h-0">
        <table className="w-full min-w-[980px] text-left text-xs">
          <thead className="sticky top-0 z-10 bg-table-header shadow-2xs">
            <tr className="border-b border-table-rule">
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Member
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Store
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Position
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Assignment
              </th>
              <th className="px-3.5 py-2 text-right text-xs font-semibold text-text-secondary whitespace-nowrap">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-table-rule">
            {rows.map((row) => {
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
              const floatingDays = getFloatingDurationDays(row);

              return (
                <tr
                  key={row.id}
                  className="transition-colors hover:bg-table-row-hover cursor-pointer"
                  onClick={() => onRowClick(row.id)}
                  tabIndex={0}
                  role="button"
                  aria-label={`View floating personnel ${displayName}`}
                >
                  <td className="px-3.5 py-2">
                    <div className="flex items-center gap-2.5">
                      <div className="h-7.5 w-7.5 rounded-full bg-blue-50 border border-blue-200 text-blue-700 font-bold text-[11px] flex items-center justify-center shrink-0 shadow-xs dark:bg-blue-950/40 dark:border-blue-800 dark:text-blue-300">
                        {initials}
                      </div>
                      <div className="min-w-0">
                        <span className="font-semibold text-table-text text-xs hover:text-brand-primary transition-colors">
                          {displayName}
                        </span>
                        <div className="flex items-center gap-2 mt-0.5">
                          <span className="font-mono text-[11px] text-table-text-muted">
                            {row.cgCode || row.vcode ? `${row.cgCode || row.vcode} • ${row.employeeNo}` : row.employeeNo}
                          </span>
                          <FloatingDoleBadge days={floatingDays} />
                        </div>
                      </div>
                    </div>
                  </td>

                  <td className="px-3.5 py-2 text-table-text">
                    <div className="min-w-0">
                      <div className="font-medium text-text-muted italic text-xs">Unassigned</div>
                      {locationLabel ? (
                        <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-1.5 py-0.2 text-[10px] font-medium text-text-secondary border border-border-subtle mt-0.5">
                          <MapPin className="h-2.5 w-2.5 text-text-muted shrink-0" />
                          <span className="truncate max-w-[150px]">{locationLabel}</span>
                        </span>
                      ) : null}
                    </div>
                  </td>

                  <td className="px-3.5 py-2">
                    <span className="font-medium text-table-text text-xs">
                      {row.positionTitle ? formatPosition(row.positionTitle) : "General Staff"}
                    </span>
                  </td>

                  <td className="px-3.5 py-2">
                    <span className="inline-flex items-center gap-1 rounded-md bg-surface-muted border border-border-default px-1.5 py-0.5 text-xs font-semibold text-text-secondary">
                      {row.assignmentType?.toLowerCase() === "roving" ? "Roving" : "Stationary"}
                    </span>
                  </td>

                  <td className="px-3.5 py-2 text-right">
                    <div className="flex items-center justify-end">
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          onAssignStore(row);
                        }}
                        className="inline-flex items-center gap-1 rounded-md bg-brand-600 px-2.5 py-1 text-xs font-semibold text-white shadow-2xs hover:bg-brand-700 transition cursor-pointer"
                      >
                        <Building2 className="h-3 w-3" />
                        <span>Assign Store</span>
                      </button>
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tab 5: Deactivation Table (Pending & Deactivated)
// ---------------------------------------------------------------------------

export function EmployeeDeactivationTable({
  rows,
  onRowClick,
  storeLookupMap,
}: {
  rows: PlantillaEmployeeListItem[];
  onRowClick: (id: string) => void;
  storeLookupMap: StoreLookupMap;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs flex-1 min-h-0 flex flex-col">
      <div className="overflow-auto flex-1 min-h-0">
        <table className="w-full min-w-[980px] text-left text-xs">
          <thead className="sticky top-0 z-10 bg-table-header shadow-2xs">
            <tr className="border-b border-table-rule">
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Emploc#
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Member
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                VCode
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Store
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Position
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Assignment
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Status
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-table-rule">
            {rows.map((row) => {
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
                <tr
                  key={row.id}
                  className="transition-colors hover:bg-table-row-hover cursor-pointer opacity-85"
                  onClick={() => onRowClick(row.id)}
                  tabIndex={0}
                  role="button"
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault();
                      onRowClick(row.id);
                    }
                  }}
                  aria-label={`View deactivation details for ${displayName}`}
                >
                  {/* 1. Emploc# */}
                  <td className="px-3.5 py-2 font-mono text-xs font-medium text-table-text whitespace-nowrap">
                    {row.employeeNo || "—"}
                  </td>

                  {/* 2. Member */}
                  <td className="px-3.5 py-2">
                    <div className="flex items-center gap-2.5">
                      <div className="h-7.5 w-7.5 rounded-full bg-surface-muted border border-border-default text-text-muted font-bold text-[11px] flex items-center justify-center shrink-0 shadow-xs">
                        {initials}
                      </div>
                      <span className="font-semibold text-table-text text-xs hover:text-brand-primary transition-colors">
                        {displayName}
                      </span>
                    </div>
                  </td>

                  {/* 3. VCode */}
                  <td className="px-3.5 py-2 font-mono text-xs text-table-text whitespace-nowrap">
                    {row.vcode || row.cgCode || "—"}
                  </td>

                  {/* 4. Store */}
                  <td className="px-3.5 py-2 text-table-text">
                    <div className="min-w-0">
                      <div className="font-medium text-table-text text-xs">
                        {formatStoreName(row.primaryStoreName || row.vcode || "—")}
                      </div>
                      {locationLabel && (
                        <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-1.5 py-0.2 text-[10px] font-medium text-text-secondary border border-border-subtle mt-0.5">
                          <MapPin className="h-2.5 w-2.5 text-text-muted shrink-0" />
                          <span className="truncate max-w-[150px]">{locationLabel}</span>
                        </span>
                      )}
                    </div>
                  </td>

                  {/* 5. Position */}
                  <td className="px-3.5 py-2">
                    <span className="font-medium text-table-text text-xs">
                      {row.positionTitle ? formatPosition(row.positionTitle) : "General Staff"}
                    </span>
                  </td>

                  {/* 6. Assignment */}
                  <td className="px-3.5 py-2">
                    <span className="inline-flex items-center gap-1 rounded-md bg-surface-muted border border-border-default px-1.5 py-0.5 text-xs font-semibold text-text-secondary">
                      {row.assignmentType?.toLowerCase() === "roving" ? "Roving" : "Stationary"}
                    </span>
                  </td>

                  {/* 7. Status */}
                  <td className="px-3.5 py-2">
                    {isDeactivated ? (
                      <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[11px] font-semibold bg-red-100 text-red-700 border border-red-300 dark:bg-red-950 dark:text-red-200 dark:border-red-800">
                        Deactivated
                      </span>
                    ) : (
                      <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[11px] font-semibold bg-amber-100 text-amber-800 border border-amber-300 dark:bg-amber-950 dark:text-amber-200 dark:border-amber-800">
                        Pending for Deactivation
                      </span>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tab 6: Inactive Employees Table (Historical & Attrition Archive)
// ---------------------------------------------------------------------------

export function EmployeeInactiveTable({
  rows,
  onRowClick,
  storeLookupMap,
  onRequestDeactivation,
}: {
  rows: PlantillaEmployeeListItem[];
  onRowClick: (id: string) => void;
  storeLookupMap: StoreLookupMap;
  onRequestDeactivation?: (emp: PlantillaEmployeeListItem) => void;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs flex-1 min-h-0 flex flex-col">
      <div className="overflow-auto flex-1 min-h-0">
        <table className="w-full min-w-[1100px] text-left text-xs">
          <thead className="sticky top-0 z-10 bg-table-header shadow-2xs">
            <tr className="border-b border-table-rule">
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Member / Employee
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Last Store Branch
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Separation Type
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Separation Date
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Status
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Remarks
              </th>
              <th className="px-3.5 py-2 text-right text-xs font-semibold text-text-secondary whitespace-nowrap">
                Action
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-table-rule">
            {rows.map((row) => {
              const displayName =
                formatPersonName(row.firstName, row.lastName, null, row.fullName) ||
                row.employeeNo ||
                "Unknown Employee";
              const initials = getInitials(row.firstName, row.lastName, row.fullName);

              const storeInfo = row.primaryStoreName
                ? storeLookupMap.get(row.primaryStoreName.toLowerCase().trim())
                : null;
              const locationDisplay =
                storeInfo?.city && storeInfo?.province
                  ? `${storeInfo.city} • ${storeInfo.province}`
                  : storeInfo?.province || storeInfo?.city || null;

              const isRoving = row.assignmentType?.toLowerCase() === "roving";
              const cleanStoreName = row.primaryStoreName
                ? formatStoreName(row.primaryStoreName).replace(/\s*\([^)]*\)/g, "").trim()
                : "Unassigned Store";

              // 3. Separation Type Badge
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

              // 4. Separation Date
              const sepDateRaw = row.separationDate || row.dateDeployed;
              const formattedDate = sepDateRaw ? formatDate(sepDateRaw) : "—";

              // 5. Deactivation Status Resolution
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

              // 6. Remarks
              const remarks = row.separationRemarks?.trim() || "—";

              return (
                <tr
                  key={row.id}
                  className="transition-colors hover:bg-table-row-hover cursor-pointer opacity-90"
                  onClick={() => onRowClick(row.id)}
                  tabIndex={0}
                  role="button"
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault();
                      onRowClick(row.id);
                    }
                  }}
                  aria-label={`View separation record for ${displayName}`}
                >
                  {/* 1. Member / Employee (Position beside emploc ID) */}
                  <td className="px-3.5 py-2 font-medium text-table-text">
                    <div className="flex items-center gap-2">
                      <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-surface-muted text-[11px] font-bold text-text-secondary border border-border-default">
                        {initials}
                      </div>
                      <div className="flex flex-col min-w-0">
                        <span className="font-semibold text-text-primary text-xs truncate max-w-[190px]" title={displayName}>
                          {displayName}
                        </span>
                        <div className="flex items-center gap-1.5 text-[10px] text-text-muted truncate">
                          <span className="font-mono text-text-secondary font-medium">
                            {row.employeeNo}
                          </span>
                          {row.positionTitle && (
                            <span className="font-medium text-text-secondary truncate">
                              {formatPosition(row.positionTitle)}
                            </span>
                          )}
                        </div>
                      </div>
                    </div>
                  </td>

                  {/* 2. Last Store Branch (Area & City beside VCode) */}
                  <td className="px-3.5 py-2 font-medium text-table-text">
                    <div className="flex flex-col">
                      <div className="flex items-center gap-1.5 flex-wrap">
                        <span className="font-medium text-xs">{cleanStoreName}</span>
                        {isRoving && (
                          <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[10px] font-semibold bg-blue-50 text-brand-700 border border-brand-200 dark:bg-brand-950 dark:text-brand-300 dark:border-brand-800">
                            Roving
                          </span>
                        )}
                      </div>
                      <div className="flex items-center gap-1.5 text-[10px] text-text-muted mt-0.5 flex-wrap">
                        {(row.vcode || row.cgCode) && (
                          <span className="font-mono text-[10px] text-text-muted">
                            {row.vcode || row.cgCode}
                          </span>
                        )}
                        {locationDisplay && (
                          <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-1.5 py-0.2 text-[10px] font-medium text-text-secondary border border-border-subtle">
                            <MapPin className="h-2.5 w-2.5 text-text-muted shrink-0" />
                            <span>{locationDisplay}</span>
                          </span>
                        )}
                      </div>
                    </div>
                  </td>

                  {/* 3. Separation Type */}
                  <td className="px-3.5 py-2 whitespace-nowrap">
                    <StatusBadge variant={sepBadgeVariant} text={sepLabel} />
                  </td>

                  {/* 4. Separation Date */}
                  <td className="px-3.5 py-2 font-mono text-xs text-text-secondary tabular-nums whitespace-nowrap">
                    {formattedDate}
                  </td>

                  {/* 5. Status (Pending for Deactivation / Deactivated / Inactive) */}
                  <td className="px-3.5 py-2 whitespace-nowrap">
                    {isDeactivated ? (
                      <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[11px] font-semibold bg-red-100 text-red-700 border border-red-300 dark:bg-red-950 dark:text-red-200 dark:border-red-800">
                        Deactivated
                      </span>
                    ) : isPendingDeactivation ? (
                      <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[11px] font-semibold bg-amber-100 text-amber-800 border border-amber-300 dark:bg-amber-950 dark:text-amber-200 dark:border-amber-800">
                        Pending for Deactivation
                      </span>
                    ) : (
                      <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[11px] font-medium bg-surface-muted text-text-secondary border border-border-default">
                        Inactive
                      </span>
                    )}
                  </td>

                  {/* 6. Remarks */}
                  <td className="px-3.5 py-2 text-[11px] text-text-secondary max-w-[200px] truncate" title={remarks !== "—" ? remarks : undefined}>
                    {remarks}
                  </td>

                  {/* 7. Action */}
                  <td className="px-3.5 py-2 text-right whitespace-nowrap">
                    {hasExistingRequest ? (
                      <span className="text-text-muted text-xs">—</span>
                    ) : (
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          onRequestDeactivation?.(row);
                        }}
                        className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg bg-surface-muted hover:bg-surface-base border border-border-default text-text-primary text-xs font-semibold transition cursor-pointer hover:border-brand-primary hover:text-brand-primary shadow-2xs"
                        title={`Request deactivation for ${displayName}`}
                      >
                        <UserMinus className="w-3.5 h-3.5 text-text-secondary" />
                        <span>Request Deactivation</span>
                      </button>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Store Capacity Table (Store View)
// ---------------------------------------------------------------------------

function formatCapacityCount(val: number): string {
  if (!val || val === 0) return "0";
  if (Number.isInteger(val)) return val.toString();
  return Number(val.toFixed(2)).toString();
}

export function StoreCapacityTable({
  rows,
  canRequestHeadcount = false,
  canRequestReactivation = false,
  onRequestHeadcount,
  onRequestReactivate,
  onWithdrawReactivate,
  pendingReactivationsMap,
  onSelectStore,
}: {
  rows: StoreCapacityRow[];
  canRequestHeadcount?: boolean;
  canRequestReactivation?: boolean;
  onRequestHeadcount?: (store: StoreCapacityRow) => void;
  onRequestReactivate?: (store: StoreCapacityRow) => void;
  onWithdrawReactivate?: (store: StoreCapacityRow, requestId: string) => void;
  pendingReactivationsMap?: Map<string, string>;
  onSelectStore?: (store: StoreCapacityRow) => void;
}) {
  const showActions = Boolean(
    (canRequestHeadcount && onRequestHeadcount) ||
    (canRequestReactivation && (onRequestReactivate || onWithdrawReactivate))
  );

  const totals = React.useMemo(() => {
    let req = 0;
    let act = 0;
    let pipe = 0;
    let leave = 0;
    let vac = 0;
    rows.forEach((r) => {
      // Exclude archived stores from operational totals
      if (r.isArchived) return;
      req += r.plantillaRequired;
      act += r.activeDeployed;
      pipe += r.pipelineCount || 0;
      leave += r.onLeave;
      vac += r.openVacancy;
    });
    const format = (n: number) => {
      const rounded = Math.round(n * 100) / 100;
      return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(2);
    };
    return {
      required: format(req),
      actual: format(act),
      pipeline: format(pipe),
      onLeave: format(leave),
      vacancy: format(vac),
    };
  }, [rows]);

  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs flex-1 min-h-0 flex flex-col">
      <div className="overflow-auto flex-1 min-h-0">
        <table className="w-full min-w-[1040px] text-left text-xs">
          <thead className="sticky top-0 z-10 bg-table-header shadow-2xs">
            <tr className="border-b border-table-rule">
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Store Branch
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Area & City
              </th>
              <th className="px-3.5 py-2 text-center text-xs font-semibold text-text-secondary whitespace-nowrap">
                Required ({totals.required})
              </th>
              <th className="px-3.5 py-2 text-center text-xs font-semibold text-text-secondary whitespace-nowrap">
                Actual ({totals.actual})
              </th>
              <th className="px-3.5 py-2 text-center text-xs font-semibold text-text-secondary whitespace-nowrap">
                Pipeline ({totals.pipeline})
              </th>
              <th className="px-3.5 py-2 text-center text-xs font-semibold text-text-secondary whitespace-nowrap">
                On-Leave ({totals.onLeave})
              </th>
              <th className="px-3.5 py-2 text-center text-xs font-semibold text-text-secondary whitespace-nowrap">
                Vacancy ({totals.vacancy})
              </th>
              <th className="px-3.5 py-2 text-center text-xs font-semibold text-text-secondary whitespace-nowrap">
                Fulfillment Status
              </th>
              {showActions && (
                <th className="px-3.5 py-2 text-right text-xs font-semibold text-text-secondary whitespace-nowrap">
                  Actions
                </th>
              )}
            </tr>
          </thead>
          <tbody className="divide-y divide-table-rule">
            {rows.map((store) => {
              const locationLabel = [store.city, store.province].filter(Boolean).join(", ");
              const isRoving = store.deploymentTypes.includes("Roving");
              const isStationary = store.deploymentTypes.includes("Stationary");
              const isMixed = isRoving && isStationary;

              const vcodeColorClass = store.code
                ? isMixed
                  ? "border-indigo-300 bg-gradient-to-r from-blue-50 to-purple-50 text-indigo-800 dark:border-indigo-700 dark:from-blue-950/60 dark:to-purple-950/60 dark:text-indigo-200"
                  : isRoving
                  ? "border-purple-300 bg-purple-50 text-purple-700 dark:border-purple-800 dark:bg-purple-950/60 dark:text-purple-300"
                  : "border-blue-300 bg-blue-50 text-blue-700 dark:border-blue-800 dark:bg-blue-950/60 dark:text-blue-300"
                : isMixed
                ? "border-dashed border-indigo-300 bg-indigo-50/50 text-indigo-600 dark:border-indigo-800/60 dark:bg-indigo-950/30 dark:text-indigo-400"
                : isRoving
                ? "border-dashed border-purple-300 bg-purple-50/50 text-purple-600 dark:border-purple-800/60 dark:bg-purple-950/30 dark:text-purple-400"
                : "border-dashed border-blue-300 bg-blue-50/50 text-blue-600 dark:border-blue-800/60 dark:bg-blue-950/30 dark:text-blue-400";

              const vcodeTitle = store.code
                ? `${isMixed ? "Mixed (Stationary & Roving)" : isRoving ? "Roving" : "Stationary"} VCode: ${store.code}`
                : `${isMixed ? "Mixed" : isRoving ? "Roving" : "Stationary"} store (No VCode assigned yet)`;

              return (
                <tr
                  key={store.id}
                  className={`transition-colors hover:bg-table-row-hover ${
                    store.isArchived ? "opacity-60 bg-surface-muted/30" : ""
                  }`}
                >
                  {/* 1. Store Branch */}
                  <td className="px-3.5 py-2 font-medium text-table-text">
                    <div className="flex items-center gap-1.5 flex-wrap">
                      <button
                        type="button"
                        onClick={() => onSelectStore?.(store)}
                        className="font-bold text-xs text-left hover:text-brand-600 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 rounded transition-colors"
                        title={`View deployments and history for ${formatStoreName(store.storeBranch)}`}
                      >
                        {formatStoreName(store.storeBranch)}
                      </button>
                      <span
                        className={`inline-flex items-center rounded border px-1.5 py-0.2 font-mono text-[10px] font-semibold ${vcodeColorClass}`}
                        title={vcodeTitle}
                      >
                        {store.code || "No VCode"}
                      </span>
                    </div>
                  </td>

                  {/* 2. Area & City */}
                  <td className="px-3.5 py-2 text-table-text">
                    <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-1.5 py-0.2 text-[10px] font-medium text-text-secondary border border-border-subtle">
                      <MapPin className="h-2.5 w-2.5 text-text-muted shrink-0" />
                      <span>{locationLabel || "Unassigned Area"}</span>
                    </span>
                  </td>

                  {/* 3. Plantilla Required (centered) */}
                  <td className="px-3.5 py-2 text-center font-mono font-bold text-text-primary text-xs">
                    {formatCapacityCount(store.plantillaRequired)}
                  </td>

                  {/* 4. Active Deployed (centered, emerald) */}
                  <td className="px-3.5 py-2 text-center font-mono font-bold text-emerald-600 dark:text-emerald-400 text-xs">
                    {formatCapacityCount(store.activeDeployed)}
                  </td>

                  {/* 5. Pipeline (centered, blue if > 0) */}
                  <td className="px-3.5 py-2 text-center font-mono font-bold text-xs">
                    {(store.pipelineCount ?? 0) > 0 ? (
                      <span className="text-blue-600 dark:text-blue-400">
                        {formatCapacityCount(store.pipelineCount ?? 0)}
                      </span>
                    ) : (
                      <span className="text-text-muted">0</span>
                    )}
                  </td>

                  {/* 6. On-Leave (centered, amber) */}
                  <td className="px-3.5 py-2 text-center font-mono font-bold text-amber-600 dark:text-amber-400 text-xs">
                    {formatCapacityCount(store.onLeave)}
                  </td>

                  {/* 7. Open Vacancy (centered, red if > 0) */}
                  <td className="px-3.5 py-2 text-center font-mono font-bold text-xs">
                    {store.openVacancy > 0 ? (
                      <span className="text-red-600 dark:text-red-400">{formatCapacityCount(store.openVacancy)}</span>
                    ) : (
                      <span className="text-text-muted">0</span>
                    )}
                  </td>

                  {/* 8. Fulfillment Status */}
                  <td className="px-3.5 py-2 text-center">
                    {store.isArchived || store.statusBadge === "Archived" ? (
                      <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[11px] font-semibold bg-surface-muted text-text-muted border border-border-default">
                        Archived
                      </span>
                    ) : store.statusBadge === "Standby" || (store.plantillaRequired === 0 && store.activeDeployed === 0) ? (
                      <span
                        className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[11px] font-semibold bg-surface-muted text-text-secondary border border-border-default"
                        title="Active store profile with zero allocated headcount quota"
                      >
                        Standby (0 Quota)
                      </span>
                    ) : store.statusBadge === "In Pipeline" ? (
                      <span
                        className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[11px] font-semibold bg-amber-50 text-amber-800 border border-amber-300 dark:bg-amber-950 dark:text-amber-200 dark:border-amber-800"
                        title="Candidate in recruitment screening or HR Emploc onboarding pipeline"
                      >
                        In Pipeline
                      </span>
                    ) : store.isFulfilled ? (
                      <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[11px] font-semibold bg-emerald-100 text-emerald-800 border border-emerald-300 dark:bg-emerald-950 dark:text-emerald-200 dark:border-emerald-800">
                        100% Fulfilled
                      </span>
                    ) : (
                      <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[11px] font-semibold bg-red-100 text-red-700 border border-red-300 dark:bg-red-950 dark:text-red-200 dark:border-red-800">
                        Understaffed
                      </span>
                    )}
                  </td>

                  {/* 8. Actions */}
                  {showActions && (
                    <td className="px-3.5 py-2 text-right whitespace-nowrap">
                      {store.isArchived ? (
                        pendingReactivationsMap?.has(store.id) ? (
                          <div className="flex items-center justify-end gap-1.5">
                            <span
                              className="inline-flex items-center gap-1 rounded-full bg-amber-50 px-2 py-0.5 text-[10px] font-semibold text-amber-800 border border-amber-300 dark:bg-amber-950/60 dark:text-amber-200 dark:border-amber-800"
                              title="Reactivation request under review by Data Team"
                            >
                              <span className="h-1.5 w-1.5 rounded-full bg-amber-500 animate-pulse" />
                              Under Review
                            </span>
                            {canRequestReactivation && onWithdrawReactivate && (
                              <button
                                type="button"
                                onClick={() =>
                                  onWithdrawReactivate(
                                    store,
                                    pendingReactivationsMap.get(store.id)!
                                  )
                                }
                                className="inline-flex items-center gap-1 rounded-md border border-red-200 bg-surface-base px-2 py-0.5 text-[10px] font-semibold text-red-600 shadow-2xs hover:bg-red-50 hover:border-red-300 dark:border-red-900 dark:hover:bg-red-950/40 transition cursor-pointer"
                                title={`Withdraw reactivation request for ${formatStoreName(store.storeBranch)}`}
                              >
                                <span>Withdraw</span>
                              </button>
                            )}
                          </div>
                        ) : canRequestReactivation && onRequestReactivate ? (
                          <button
                            type="button"
                            onClick={() => onRequestReactivate(store)}
                            className="inline-flex items-center gap-1 rounded-md border border-brand-300 bg-brand-50 px-2.5 py-1 text-[11px] font-semibold text-brand-700 shadow-2xs hover:bg-brand-100 hover:border-brand-400 dark:bg-brand-950/60 dark:border-brand-800 dark:text-brand-300 transition cursor-pointer"
                            title={`Request reactivation for ${formatStoreName(store.storeBranch)}`}
                          >
                            <RotateCw className="h-3 w-3 text-brand-600 shrink-0" />
                            <span>Reactivate</span>
                          </button>
                        ) : (
                          <span className="text-[11px] text-text-muted italic px-2">Archived</span>
                        )
                      ) : canRequestHeadcount && onRequestHeadcount ? (
                        <button
                          type="button"
                          onClick={() => onRequestHeadcount(store)}
                          className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-base px-2.5 py-1 text-[11px] font-semibold text-text-primary shadow-2xs hover:bg-surface-hover hover:border-border-strong transition cursor-pointer"
                          title={`Request stationary headcount for ${formatStoreName(store.storeBranch)}`}
                        >
                          <Plus className="h-3 w-3 text-brand-600 shrink-0" />
                          <span>Request HC</span>
                        </button>
                      ) : (
                        <span className="text-[11px] text-text-muted">—</span>
                      )}
                    </td>
                  )}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
