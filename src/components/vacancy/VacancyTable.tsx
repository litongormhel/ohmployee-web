// components/vacancy/VacancyTable.tsx
"use client";

import {
  Calendar,
  Check,
  CheckCircle2,
  ClipboardList,
  LockKeyhole,
  Phone,
  RefreshCw,
  RotateCcw,
  TrendingUp,
  UserPlus,
  X,
} from "lucide-react";
import { StatusBadge, type BadgeVariant } from "@/components/ui/StatusBadge";
import { TablePagination } from "@/components/shared/TablePagination";
import {
  formatGroupName,
  type VacancyDataErrorKind,
  type VacancyListItem,
  type VacancyStatus,
} from "@/lib/queries/vacancy";
import { formatHrcoName, formatPersonName, formatStoreDisplay } from "@/lib/utils/formatName";
import { useCurrentUser } from "@/lib/auth";
import {
  canAddApplicant,
  canManageApplicantPipeline,
  canReviewVacancyClosures,
  isOpsTeam,
} from "@/lib/rbac";

export type { VacancyStatus } from "@/lib/queries/vacancy";

function getTableColumns(status: VacancyStatus): string[] {
  if (status === "open") {
    return [
      "VCODE",
      "POSITION",
      "ACCOUNT / GROUP",
      "OUTLET NAME",
      "HRCO",
      "AGING",
      "HC",
      "ACTIONS",
    ];
  }
  if (status === "closure") {
    return [
      "VCODE",
      "POSITION",
      "ACCOUNT / GROUP",
      "OUTLET NAME",
      "HRCO",
      "REASON FOR DELETION",
      "REQUESTED BY",
      "AGING",
      "HC",
      "ACTIONS",
    ];
  }
  if (status === "hired") {
    return [
      "VCODE",
      "POSITION",
      "ACCOUNT / GROUP",
      "OUTLET NAME",
      "HRCO",
      "APPLICANT",
      "ONBOARD DATE",
      "DAYS TO FILL",
    ];
  }
  if (status === "failed_backout") {
    return [
      "VCODE",
      "POSITION",
      "ACCOUNT / GROUP",
      "OUTLET NAME",
      "HRCO",
      "APPLICANT",
      "DATE OF BACKOUT",
      "STATUS",
      "AGING",
    ];
  }
  if (status === "pipeline") {
    return [
      "VCODE",
      "POSITION",
      "ACCOUNT / GROUP",
      "OUTLET NAME",
      "HRCO",
      "APPLICANT",
      "STATUS",
      "AGING",
      "ACTIONS",
    ];
  }
  return [
    "VCODE",
    "POSITION",
    "ACCOUNT / GROUP",
    "OUTLET NAME",
    "HRCO",
    "APPLICANT",
    "STATUS",
    "AGING",
    "HC",
    "ACTIONS",
  ];
}


type VacancyTableProps = {
  status: VacancyStatus;
  statusDescription?: string;
  rows: VacancyListItem[];
  selectedId: string | null;
  totalCount: number;
  page: number;
  pageSize: number;
  isLoading: boolean;
  errorKind: VacancyDataErrorKind | null;
  onSelect: (vacancy: VacancyListItem) => void;
  onAddApplicant?: (vacancy: VacancyListItem) => void;
  onEditApplicant?: (vacancy: VacancyListItem) => void;
  onAdvancePipeline?: (vacancy: VacancyListItem) => void;
  onMarkHired?: (vacancy: VacancyListItem) => void;
  onFailBackout?: (vacancy: VacancyListItem) => void;
  onReopenVacancy?: (vacancy: VacancyListItem) => void;
  onRequestClosure?: (vacancy: VacancyListItem) => void;
  onReviewClosure?: (vacancy: VacancyListItem, decision: "Approved" | "Rejected") => void;
  onWithdrawClosure?: (vacancy: VacancyListItem) => void;
  onEditHiredDate?: (vacancy: VacancyListItem) => void;
  onRetry: () => void;
  onPageChange: (page: number) => void;
  onPageSizeChange?: (pageSize: number) => void;
};


function formatAgingBucket(bucket: string): string {
  switch (bucket) {
    case "advance":
      return "Advance";
    case "1_15":
      return "1–15 days";
    case "16_30":
      return "16–30 days";
    case "31_60":
      return "31–60 days";
    case "61_120":
      return "61–120 days";
    case "gt121":
      return "121+ days";
    case "31_plus":
      return "31+ days";
    default:
      return bucket.replace(/_/g, " ");
  }
}

function getStatusLabel(row: VacancyListItem) {
  return row.derivedStatus ?? row.vacancyStatus ?? row.pipelineStatus ?? "—";
}

function getVacancyStatusVariant(status: string): BadgeVariant {
  const norm = status.toLowerCase().trim();
  if (norm === "open") return "info";
  if (norm === "pipeline" || norm === "with_applicant" || norm === "with applicant") return "info";
  if (norm === "hired" || norm === "filled" || norm === "complete" || norm === "completed") return "success";
  if (norm === "rejected" || norm === "failed" || norm === "failed_backout" || norm === "failed / backout") return "danger";
  if (norm === "backout") return "warning";
  if (norm === "for closure" || norm === "for_closure" || norm === "pending clearance") return "warning";
  if (norm === "closure" || norm === "closed") return "neutral";
  return "neutral";
}

function isOnBoardStatus(row: VacancyListItem): boolean {
  const statusValues = [
    row.stageBadge,
    row.derivedStatus,
    row.pipelineStatus,
    row.vacancyStatus,
  ];

  for (const status of statusValues) {
    if (!status) continue;
    const clean = status.toLowerCase().replace(/[\s_-]+/g, "");
    if (
      clean === "onboard" ||
      clean === "foronboard" ||
      clean === "onboarding" ||
      clean === "confirmedonboard"
    ) {
      return true;
    }
  }

  return false;
}

function getErrorCopy(kind: VacancyDataErrorKind | null) {
  if (kind === "access_denied") {
    return {
      title: "Access Restricted",
      body: "You do not have permission to view vacancies for this scope. Please contact your administrator if you need access.",
    };
  }

  return {
    title: "Unable to Load Vacancies",
    body: "Could not retrieve vacancy records. Please retry or adjust filters.",
  };
}

function formatOnboardDate(value: string | null | undefined): string {
  if (!value) return "—";
  const parts = value.split("-");
  if (parts.length === 3 && parts[0].length === 4) {
    const year = parseInt(parts[0], 10);
    const monthIndex = parseInt(parts[1], 10) - 1;
    const day = parseInt(parts[2], 10);
    const months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    if (monthIndex >= 0 && monthIndex < 12 && !Number.isNaN(day) && !Number.isNaN(year)) {
      return `${months[monthIndex]} ${day}, ${year}`;
    }
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  }).format(date);
}

function formatDropoutDate(value: string | null | undefined): string {
  if (!value) return "—";
  const parts = value.split("T")[0].split("-");
  if (parts.length === 3 && parts[0].length === 4) {
    const year = parseInt(parts[0], 10);
    const monthIndex = parseInt(parts[1], 10) - 1;
    const day = parseInt(parts[2], 10);
    const months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    if (monthIndex >= 0 && monthIndex < 12 && !Number.isNaN(day) && !Number.isNaN(year)) {
      return `${months[monthIndex]} ${day}, ${year}`;
    }
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  }).format(date);
}

export function VacancyTable({
  status,
  statusDescription = status,
  rows,
  selectedId,
  totalCount,
  page,
  pageSize,
  isLoading,
  errorKind,
  onSelect,
  onAddApplicant,
  onEditApplicant: _onEditApplicant,
  onAdvancePipeline,
  onMarkHired,
  onFailBackout: _onFailBackout,
  onReopenVacancy: _onReopenVacancy,
  onReviewClosure,
  onWithdrawClosure,
  onEditHiredDate: _onEditHiredDate,
  onRetry,
  onPageChange,
  onPageSizeChange,
}: VacancyTableProps) {
  const currentUser = useCurrentUser();
  const userCanAddApplicant = canAddApplicant(currentUser);
  const userCanManagePipeline = canManageApplicantPipeline(currentUser);
  const userCanReviewClosures = canReviewVacancyClosures(currentUser);
  const userIsOps = isOpsTeam(currentUser);

  const errorCopy = getErrorCopy(errorKind);
  const activeColumns = getTableColumns(status);

  return (
    <section className="flex min-h-[520px] flex-col rounded-md border border-table-rule-section bg-table-row">
      <div className="min-h-0 flex-1 overflow-auto">
        <table className="w-full min-w-[1280px] border-separate border-spacing-0 text-left text-[0.9375rem]">
          <thead className="sticky top-0 z-10 bg-table-header text-sm font-semibold text-text-secondary">
            <tr>
              {activeColumns.map((column) => (
                <th
                  className="border-b border-table-rule-section px-4 py-2.5"
                  key={column || "actions"}
                  scope="col"
                >
                  {column}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {isLoading ? (
              <tr>
                <td className="px-3 py-12 text-center" colSpan={activeColumns.length}>
                  <div className="mx-auto flex max-w-md flex-col items-center gap-2">
                    <RefreshCw
                      className="h-5 w-5 animate-spin text-brand-500"
                      aria-hidden="true"
                    />
                    <div className="text-sm font-medium text-table-text-sub">
                      Loading vacancies
                    </div>
                    <div className="text-sm text-table-text-muted">
                      Fetching {statusDescription.toLowerCase()} requisitions...
                    </div>
                  </div>
                </td>
              </tr>
            ) : errorKind ? (
              <tr>
                <td className="px-3 py-12 text-center" colSpan={activeColumns.length}>
                  <div className="mx-auto flex max-w-md flex-col items-center gap-2">
                    <div className="rounded-md border border-status-danger-border bg-status-danger-bg p-2">
                      <LockKeyhole
                        className="h-5 w-5 text-status-danger-text"
                        aria-hidden="true"
                      />
                    </div>
                    <div className="text-sm font-medium text-table-text">
                      {errorCopy.title}
                    </div>
                    <div className="text-sm text-table-text-muted">{errorCopy.body}</div>
                    {errorKind === "retryable" ? (
                      <button
                        className="mt-2 inline-flex h-8 items-center gap-2 rounded-md border border-table-rule-section bg-table-row px-3 text-sm font-medium text-table-text-sub"
                        onClick={onRetry}
                        type="button"
                      >
                        <RefreshCw className="h-4 w-4" aria-hidden="true" />
                        Retry
                      </button>
                    ) : null}
                  </div>
                </td>
              </tr>
            ) : rows.length === 0 ? (
              <tr>
                <td className="px-3 py-12 text-center" colSpan={activeColumns.length}>
                  <div className="mx-auto flex max-w-md flex-col items-center gap-2">
                    <div className="rounded-md border border-table-rule-section bg-table-header p-2">
                      <ClipboardList
                        className="h-5 w-5 text-table-text-muted"
                        aria-hidden="true"
                      />
                    </div>
                    <div className="text-sm font-medium text-table-text-sub">
                      No vacancies found
                    </div>
                    <div className="text-sm text-table-text-muted">
                      No requisitions found matching the current queue and filter criteria.
                    </div>
                  </div>
                </td>
              </tr>
            ) : (
              rows.map((row, index) => {
                const statusKey = (row.derivedStatus ?? row.vacancyStatus ?? "").toLowerCase();
                return (
                  <tr
                    className={`border-b border-table-rule transition-colors ${
                      row.rowCapabilities.canViewDetail ? "cursor-pointer" : "cursor-not-allowed"
                    } ${
                      selectedId === row.id ? "bg-table-row-selected" : "hover:bg-table-row-hover"
                    }`}
                    key={`${row.id}-${row.applicantId ?? row.vcode}-${index}`}
                    onClick={() => {
                      if (row.rowCapabilities.canViewDetail) {
                        onSelect(row);
                      }
                    }}
                  >
                    {/* 1. VCODE */}
                    <td className="border-b border-table-rule px-4 py-2.5 font-mono text-sm font-semibold text-table-text-sub">
                      {row.cgCode || row.vcode || "Uncoded"}
                    </td>

                    {/* 2. POSITION */}
                    <td className="border-b border-table-rule px-4 py-2.5">
                      <div className="font-medium text-table-text">
                        {row.position_title ?? "—"}
                      </div>
                      <div className="text-xs text-table-text-muted">
                        {row.employmentType || "Stationary"}
                      </div>
                    </td>

                    {/* 3. ACCOUNT / GROUP */}
                    <td className="border-b border-table-rule px-4 py-2.5">
                      <div className="font-medium text-table-text">
                        {row.accountName ?? "—"}
                      </div>
                      <div className="text-xs text-table-text-muted">
                        {formatGroupName(row.groupName, row.accountName) || "—"}
                      </div>
                    </td>

                    {/* 4. OUTLET NAME */}
                    <td className="border-b border-table-rule px-4 py-2.5">
                      {(() => {
                        const storeInfo = formatStoreDisplay(row.storeName, row.assignedStores);
                        return (
                          <div title={storeInfo.isMulti ? storeInfo.tooltip : undefined}>
                            <div className="font-medium text-table-text flex items-center gap-1.5">
                              <span className="truncate">{storeInfo.displayText}</span>
                              {storeInfo.isMulti && (
                                <span className="inline-flex items-center px-1.5 py-0.2 rounded text-[10px] font-semibold bg-brand-50 text-brand-700 border border-brand-200 shrink-0">
                                  +{storeInfo.extraCount}
                                </span>
                              )}
                            </div>
                            {row.storeLocation ? (
                              <div className="text-xs text-table-text-muted">
                                {row.storeLocation}
                              </div>
                            ) : null}
                          </div>
                        );
                      })()}
                    </td>

                    {/* 5. HRCO */}
                    <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub">
                      {row.hrcoName ? (
                        <div className="font-medium text-table-text">
                          {formatHrcoName(row.hrcoName)}
                        </div>
                      ) : (
                        <span className="inline-flex items-center rounded-md border border-table-rule bg-table-header px-2 py-0.5 text-xs text-table-text-muted">
                          Unassigned
                        </span>
                      )}
                    </td>

                    {/* When status is closure: Render REASON FOR DELETION and REQUESTED BY, omit STATUS and APPLICANT */}
                    {status === "closure" ? (
                      <>
                        {/* 6. REASON FOR DELETION */}
                        <td className="border-b border-table-rule px-4 py-2.5 font-medium text-text-primary">
                          <span>{row.closureReason || "Requested for Deletion"}</span>
                        </td>

                        {/* 7. REQUESTED BY */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-sm text-table-text-muted">
                          <span className="font-medium text-table-text-sub">
                            {row.closureRequestedBy || "Operations"}
                          </span>
                          {row.closureRequestedAt && (
                            <span className="text-text-muted">
                              {" "}• {new Date(row.closureRequestedAt).toLocaleDateString()}
                            </span>
                          )}
                        </td>
                      </>
                    ) : status === "hired" ? (
                      <>
                        {/* 6. APPLICANT */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub">
                          <div className="font-semibold text-table-text">
                            {row.applicantName ? formatPersonName(null, null, null, row.applicantName) : "Hired Worker"}
                          </div>
                        </td>

                        {/* 7. ONBOARD DATE - beside Applicant */}
                        <td className="border-b border-table-rule px-4 py-2.5">
                          <span className="inline-flex items-center gap-1.5 rounded border border-border-default bg-surface-muted px-2 py-0.5 font-medium text-text-secondary text-xs">
                            <Calendar className="h-3 w-3 shrink-0 text-text-muted" aria-hidden="true" />
                            <span>{formatOnboardDate(row.hiredDate)}</span>
                          </span>
                        </td>

                        {/* 8. DAYS TO FILL (from vacant date until onboard date) */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub">
                          {row.daysToFill !== null && row.daysToFill !== undefined ? (
                            <span className="inline-flex items-center rounded-md border border-border-default bg-surface-muted px-2 py-0.5 text-xs font-medium text-text-secondary">
                              {row.daysToFill} {row.daysToFill === 1 ? "day" : "days"}
                            </span>
                          ) : (
                            <span className="text-table-text-muted">—</span>
                          )}
                        </td>
                      </>
                    ) : status === "failed_backout" ? (
                      <>
                        {/* 6. APPLICANT */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub">
                          <div className="font-semibold text-table-text">
                            {row.applicantName ? formatPersonName(null, null, null, row.applicantName) : "Candidate"}
                          </div>
                        </td>

                        {/* 7. DATE OF BACKOUT */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-sm text-table-text-muted font-mono">
                          {formatDropoutDate(row.dropoutDate)}
                        </td>

                        {/* 8. STATUS (simple typography, no pill) */}
                        <td className="border-b border-table-rule px-4 py-2.5">
                          <span className="text-xs font-medium text-text-secondary">
                            {row.dropoutReason || "Failed / Backout"}
                          </span>
                        </td>

                        {/* 9. AGING */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub">
                          {row.agingDays !== null && row.agingDays !== undefined ? (
                            <span className="inline-flex items-center rounded-md border border-border-default bg-surface-muted px-2 py-0.5 text-xs font-medium text-text-secondary">
                              {row.agingDays} {row.agingDays === 1 ? "day" : "days"}
                            </span>
                          ) : row.agingBucket === "advance" ? (
                            <span className="inline-flex items-center rounded-md border border-border-default bg-surface-muted px-2 py-0.5 text-xs font-medium text-text-secondary">
                              Advance
                            </span>
                          ) : row.agingBucket ? (
                            <span className="inline-flex items-center rounded-md border border-table-rule bg-table-row px-2 py-0.5 text-xs text-table-text-muted">
                              {formatAgingBucket(row.agingBucket)}
                            </span>
                          ) : (
                            <span className="text-table-text-muted">—</span>
                          )}
                        </td>
                      </>
                    ) : (
                      <>
                        {/* 6. APPLICANT */}
                        {status !== "open" && (
                          <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub">
                            {status === "pipeline" ? (
                              /* Pipeline Tab: Display Candidate Full Name, and underneath, mobile phone number with phone icon */
                              <div className="flex flex-col gap-0.5">
                                <div className="font-semibold text-table-text">
                                  {row.applicantName ? formatPersonName(null, null, null, row.applicantName) : "Assigned Candidate"}
                                </div>
                                {row.contactNumber ? (
                                  <div className="inline-flex items-center gap-1 font-mono text-[11px] text-table-text-muted">
                                    <Phone className="h-2.5 w-2.5 shrink-0" aria-hidden="true" />
                                    <span>{row.contactNumber}</span>
                                  </div>
                                ) : null}
                              </div>
                            ) : (
                              row.applicantName ? formatPersonName(null, null, null, row.applicantName) : "—"
                            )}
                          </td>
                        )}

                        {/* 7. STATUS */}
                        {status !== "open" && (
                          <td className="border-b border-table-rule px-4 py-2.5">
                            {status === "pipeline" ? (
                              <StatusBadge variant="info">
                                {row.stageBadge || "In Pipeline"}
                              </StatusBadge>
                            ) : (
                              <StatusBadge variant={getVacancyStatusVariant(statusKey)}>
                                {getStatusLabel(row)}
                              </StatusBadge>
                            )}
                          </td>
                        )}
                      </>
                    )}

                    {/* Columns 8, 9, 10: AGING, HC, ACTIONS (Omitted for Hired and Failed / Backout tabs) */}
                    {status !== "hired" && status !== "failed_backout" && (
                      <>
                        {/* 8. AGING */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub">
                          {row.agingDays !== null && row.agingDays !== undefined ? (
                            <span className="inline-flex items-center rounded-md border border-border-default bg-surface-muted px-2 py-0.5 text-xs font-medium text-text-secondary">
                              {row.agingDays} {row.agingDays === 1 ? "day" : "days"}
                            </span>
                          ) : row.agingBucket === "advance" ? (
                            <span className="inline-flex items-center rounded-md border border-border-default bg-surface-muted px-2 py-0.5 text-xs font-medium text-text-secondary">
                              Advance
                            </span>
                          ) : row.agingBucket ? (
                            <span className="inline-flex items-center rounded-md border border-table-rule bg-table-row px-2 py-0.5 text-xs text-table-text-muted">
                              {formatAgingBucket(row.agingBucket)}
                            </span>
                          ) : (
                            <span className="text-table-text-muted">—</span>
                          )}
                        </td>

                        {/* 9. HC (Omitted in Pipeline tab where 1 row = 1 candidate) */}
                        {status !== "pipeline" && (
                          <td className="border-b border-table-rule px-4 py-2.5 font-mono text-sm text-table-text-sub">
                            {row.hcDisplay || `${row.confirmedOnboardCount ?? row.hcFilled ?? 0}/${row.headcount ?? row.hcTotal ?? 1}`}
                          </td>
                        )}

                        {/* 10. ACTIONS */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-right">
                          <div className="flex items-center justify-end gap-1.5">
                            {status === "open" && userCanAddApplicant && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  if (onAddApplicant) {
                                    onAddApplicant(row);
                                  } else {
                                    onSelect(row);
                                  }
                                }}
                                className="inline-flex items-center gap-1 rounded bg-brand-50 px-2 py-1 text-xs font-semibold text-brand-700 border border-brand-200 hover:bg-brand-100 transition shadow-xs"
                                title={`Add applicant for ${row.vcode}`}
                              >
                                <UserPlus className="h-3.5 w-3.5" aria-hidden="true" />
                                <span>+ Applicant</span>
                              </button>
                            )}

                            {status === "pipeline" && userCanManagePipeline && (
                              <>
                                {onAdvancePipeline && (
                                  <button
                                    type="button"
                                    onClick={(e) => {
                                      e.stopPropagation();
                                      onAdvancePipeline(row);
                                    }}
                                    className="inline-flex items-center gap-1 rounded bg-surface-muted px-2 py-1 text-xs font-semibold text-text-primary border border-border-default hover:bg-surface-hover transition shadow-xs cursor-pointer"
                                    title={`Update pipeline stage for ${row.applicantName || row.vcode}`}
                                  >
                                    <TrendingUp className="h-3.5 w-3.5" aria-hidden="true" />
                                    <span className="hidden sm:inline">Update</span>
                                  </button>
                                )}
                                {onMarkHired && isOnBoardStatus(row) && (
                                  <button
                                    type="button"
                                    onClick={(e) => {
                                      e.stopPropagation();
                                      onMarkHired(row);
                                    }}
                                    className="inline-flex items-center gap-1 rounded bg-brand-50 px-2 py-1 text-xs font-semibold text-brand-700 border border-brand-200 hover:bg-brand-100 transition shadow-xs cursor-pointer"
                                    title={`Approve placement / mark ${row.applicantName || row.vcode} as hired`}
                                  >
                                    <CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" />
                                    <span className="hidden sm:inline">Approve</span>
                                  </button>
                                )}
                              </>
                            )}

                            {status === "closure" && (
                              <div className="flex items-center gap-1">
                                {userIsOps && onWithdrawClosure && (
                                  <button
                                    type="button"
                                    onClick={(e) => {
                                      e.stopPropagation();
                                      onWithdrawClosure(row);
                                    }}
                                    className="inline-flex items-center gap-1 rounded bg-surface-muted px-2 py-1 text-xs font-semibold text-text-secondary border border-border-default hover:bg-surface-hover transition shadow-xs cursor-pointer"
                                    title={`Withdraw closure request for ${row.vcode}`}
                                  >
                                    <RotateCcw className="h-3 w-3" aria-hidden="true" />
                                    <span className="hidden sm:inline">Withdraw</span>
                                  </button>
                                )}
                                {userCanReviewClosures && onReviewClosure && (
                                  <>
                                    <button
                                      type="button"
                                      onClick={(e) => {
                                        e.stopPropagation();
                                        onReviewClosure(row, "Approved");
                                      }}
                                      className="inline-flex items-center gap-1 rounded bg-brand-50 px-2 py-1 text-xs font-semibold text-brand-700 border border-brand-200 hover:bg-brand-100 transition shadow-xs cursor-pointer"
                                      title={`Approve closure request for ${row.vcode}`}
                                    >
                                      <Check className="h-3 w-3" aria-hidden="true" />
                                      <span className="hidden sm:inline">Approve</span>
                                    </button>
                                    <button
                                      type="button"
                                      onClick={(e) => {
                                        e.stopPropagation();
                                        onReviewClosure(row, "Rejected");
                                      }}
                                      className="inline-flex items-center gap-1 rounded border border-danger-border bg-surface-base px-2 py-1 text-xs font-semibold text-danger-text hover:bg-danger-bg transition shadow-xs cursor-pointer"
                                      title={`Reject closure request for ${row.vcode}`}
                                    >
                                      <X className="h-3 w-3" aria-hidden="true" />
                                      <span className="hidden sm:inline">Reject</span>
                                    </button>
                                  </>
                                )}
                              </div>
                            )}
                          </div>
                        </td>
                      </>
                    )}
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      <TablePagination
        page={page}
        pageSize={pageSize}
        totalCount={totalCount}
        pageSizeOptions={[10, 25, 50]}
        onPageChange={onPageChange}
        onPageSizeChange={onPageSizeChange}
        isLoading={isLoading}
      />
    </section>
  );
}
