// components/vacancy/VacancyTable.tsx
"use client";

import {
  Archive,
  Calendar,
  Check,
  CheckCircle2,
  ClipboardList,
  Clock3,
  Eye,
  LockKeyhole,
  Phone,
  RefreshCw,
  RotateCcw,
  TrendingUp,
  User,
  UserMinus,
  X,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { StatusBadge, type BadgeVariant } from "@/components/ui/StatusBadge";
import type {
  VacancyDataErrorKind,
  VacancyListItem,
  VacancyStatus,
} from "@/lib/queries/vacancy";

export type { VacancyStatus } from "@/lib/queries/vacancy";

function getTableColumns(status: VacancyStatus): string[] {
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
      "PENALTY",
      "ACTIONS",
    ];
  }
  if (status === "failed_backout") {
    return [
      "VCODE",
      "POSITION",
      "ACCOUNT / GROUP",
      "OUTLET NAME",
      "HRCO",
      "STATUS",
      "APPLICANT",
      "PENALTY",
      "ACTIONS",
    ];
  }
  return [
    "VCODE",
    "POSITION",
    "ACCOUNT / GROUP",
    "OUTLET NAME",
    "HRCO",
    "STATUS",
    "APPLICANT",
    "AGING",
    "PENALTY",
    "ACTIONS",
  ];
}


type VacancyTableProps = {
  status: VacancyStatus;
  statusDescription: string;
  rows: VacancyListItem[];
  selectedId: string | null;
  totalCount: number;
  page: number;
  pageSize: number;
  isLoading: boolean;
  errorKind: VacancyDataErrorKind | null;
  onSelect: (vacancy: VacancyListItem) => void;
  onAddApplicant?: (vacancy: VacancyListItem) => void;
  onAdvancePipeline?: (vacancy: VacancyListItem) => void;
  onMarkHired?: (vacancy: VacancyListItem) => void;
  onFailBackout?: (vacancy: VacancyListItem) => void;
  onReopenVacancy?: (vacancy: VacancyListItem) => void;
  onRequestClosure?: (vacancy: VacancyListItem) => void;
  onReviewClosure?: (vacancy: VacancyListItem, decision: "Approved" | "Rejected") => void;
  onEditHiredDate?: (vacancy: VacancyListItem) => void;
  onRetry: () => void;
  onPageChange: (page: number) => void;
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
  if (norm === "closure" || norm === "closed") return "neutral";
  return "neutral";
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

export function VacancyTable({
  status,
  statusDescription,
  rows,
  selectedId,
  totalCount,
  page,
  pageSize,
  isLoading,
  errorKind,
  onSelect,
  onAdvancePipeline,
  onMarkHired,
  onFailBackout,
  onReopenVacancy,
  onRequestClosure,
  onReviewClosure,
  onEditHiredDate,
  onRetry,
  onPageChange,
}: VacancyTableProps) {
  const pageCount = Math.max(1, Math.ceil(totalCount / pageSize));
  const firstRecord = totalCount === 0 ? 0 : (page - 1) * pageSize + 1;
  const lastRecord = Math.min(totalCount, page * pageSize);
  const errorCopy = getErrorCopy(errorKind);
  const activeColumns = getTableColumns(status);

  return (
    <section className="flex min-h-[520px] flex-col rounded-md border border-table-rule-section bg-table-row">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-table-rule-section px-4 py-3">
        <div>
          <div className="flex items-center gap-2">
            <h2 className="text-base font-semibold text-table-text">
              {statusDescription}
            </h2>
            <Badge className="font-mono text-[11px] text-table-text-muted">
              {status === "failed_backout" ? "failed / backout" : status}
            </Badge>
          </div>
          <p className="mt-1 text-sm text-table-text-muted">
            Active store requisitions matching current filter criteria.
          </p>
        </div>
        <div className="flex items-center gap-2 text-sm text-table-text-muted">
          <Clock3 className="h-4 w-4" aria-hidden="true" />
          {isLoading ? "Loading vacancy queue" : `${totalCount} records`}
        </div>
      </div>

      <div className="min-h-0 flex-1 overflow-auto">
        <table className="w-full min-w-[1280px] border-separate border-spacing-0 text-left text-[0.9375rem]">
          <thead className="sticky top-0 z-10 bg-table-header text-xs font-semibold uppercase text-table-text-muted">
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
                      className="h-5 w-5 animate-spin text-blue-500"
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
              rows.map((row) => {
                const statusKey = (row.derivedStatus ?? row.vacancyStatus ?? "").toLowerCase();
                return (
                  <tr
                    className={`border-b border-table-rule transition-colors ${
                      row.rowCapabilities.canViewDetail ? "cursor-pointer" : "cursor-not-allowed"
                    } ${
                      selectedId === row.id ? "bg-table-row-selected" : "hover:bg-table-row-hover"
                    }`}
                    key={row.id}
                    onClick={() => {
                      if (row.rowCapabilities.canViewDetail) {
                        onSelect(row);
                      }
                    }}
                  >
                    {/* 1. VCODE */}
                    <td className="border-b border-table-rule px-4 py-2.5 font-mono text-sm font-semibold text-table-text-sub">
                      {row.vcode}
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
                        {row.groupName || "General / Direct"}
                      </div>
                    </td>

                    {/* 4. OUTLET NAME */}
                    <td className="border-b border-table-rule px-4 py-2.5">
                      <div className="font-medium text-table-text">
                        {row.storeName ?? "—"}
                      </div>
                      {row.storeLocation ? (
                        <div className="text-xs text-table-text-muted">
                          {row.storeLocation}
                        </div>
                      ) : null}
                    </td>

                    {/* 5. HRCO */}
                    <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub">
                      {row.hrcoName ? (
                        <div className="flex items-center gap-1.5 font-medium text-table-text">
                          <User className="h-3.5 w-3.5 shrink-0 text-table-text-muted" aria-hidden="true" />
                          <span>{row.hrcoName}</span>
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
                        <td className="border-b border-table-rule px-4 py-2.5 font-medium text-rose-900">
                          {row.closureReason || "Requested for Deletion"}
                        </td>

                        {/* 7. REQUESTED BY */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-xs text-table-text-muted">
                          <span className="font-medium text-table-text-sub">
                            {row.closureRequestedBy || "Operations"}
                          </span>
                          {row.closureRequestedAt && (
                            <span className="text-gray-400">
                              {" "}• {new Date(row.closureRequestedAt).toLocaleDateString()}
                            </span>
                          )}
                        </td>
                      </>
                    ) : (
                      <>
                        {/* 6. STATUS */}
                        <td className="border-b border-table-rule px-4 py-2.5">
                          {status === "pipeline" ? (
                            <StatusBadge variant="info">
                              {row.stageBadge || "In Pipeline"}
                            </StatusBadge>
                          ) : status === "failed_backout" ? (
                            <StatusBadge variant="danger">
                              {row.dropoutReason || "Failed / Backout"}
                            </StatusBadge>
                          ) : (
                            <StatusBadge variant={getVacancyStatusVariant(statusKey)}>
                              {getStatusLabel(row)}
                            </StatusBadge>
                          )}
                        </td>

                        {/* 7. APPLICANT */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub">
                          {status === "open" ? (
                            <span className="text-table-text-muted">—</span>
                          ) : status === "pipeline" ? (
                            /* Pipeline Tab: Query and display Candidate Full Name, contact number, and current stage badge */
                            <div className="flex flex-col gap-1">
                              <div className="font-semibold text-table-text">
                                {row.applicantName || "Assigned Candidate"}
                              </div>
                              <div className="flex flex-wrap items-center gap-1.5">
                                <span className="inline-flex items-center rounded-full border border-purple-200 bg-purple-50 px-2 py-0.5 text-[10px] font-medium text-purple-700">
                                  {row.stageBadge || (row.activeApplicantCount > 1 ? `${row.activeApplicantCount} in pipeline` : "In Pipeline")}
                                </span>
                                {row.contactNumber && (
                                  <span className="inline-flex items-center gap-1 font-mono text-[11px] text-table-text-muted">
                                    <Phone className="h-2.5 w-2.5" />
                                    {row.contactNumber}
                                  </span>
                                )}
                              </div>
                            </div>
                          ) : status === "hired" ? (
                            /* Hired Tab: Display Hired Worker Name, Onboard Date, and Position */
                            <div className="flex flex-col gap-0.5">
                              <div className="font-semibold text-table-text">
                                {row.applicantName || "Hired Worker"}
                              </div>
                              <div className="flex flex-wrap items-center gap-2 text-xs text-table-text-muted">
                                {row.hiredDate && (
                                  <span className="inline-flex items-center gap-1 rounded border border-emerald-200 bg-emerald-50 px-1.5 py-0.5 font-medium text-emerald-800 text-[10px]">
                                    Onboard: {row.hiredDate}
                                  </span>
                                )}
                                {row.position_title && (
                                  <span className="text-[11px] text-slate-600">
                                    {row.position_title}
                                  </span>
                                )}
                              </div>
                            </div>
                          ) : status === "failed_backout" ? (
                            /* Failed / Backout Tab: Display Candidate Full Name, Dropout / Failure Reason, and Date */
                            <div className="flex flex-col gap-1">
                              <div className="font-semibold text-table-text">
                                {row.applicantName || "Candidate"}
                              </div>
                              <div className="flex flex-wrap items-center gap-1.5">
                                {row.dropoutDate && (
                                  <span className="text-[11px] text-table-text-muted font-mono">
                                    {row.dropoutDate}
                                  </span>
                                )}
                              </div>
                            </div>
                          ) : (
                            row.applicantName || "—"
                          )}
                        </td>
                      </>
                    )}

                    {/* 8. AGING (omitted completely for failed_backout tab) */}
                    {status !== "failed_backout" && (
                      <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub">
                        {row.agingDays !== null && row.agingDays !== undefined ? (
                          <span
                            className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs ${
                              row.agingDays <= 15
                                ? "border border-emerald-200/80 bg-emerald-50 font-medium text-emerald-700"
                                : row.agingDays <= 30
                                ? "border border-amber-200/80 bg-amber-50 font-medium text-amber-700"
                                : "border border-rose-200/80 bg-rose-50 font-semibold text-rose-700"
                            }`}
                          >
                            {row.agingDays} {row.agingDays === 1 ? "day" : "days"}
                          </span>
                        ) : row.agingBucket === "advance" ? (
                          <span className="inline-flex items-center rounded-md border border-blue-200/80 bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700">
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
                    )}

                    {/* 9. PENALTY */}
                    <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub">
                      {row.hasPenalty || (row.penaltyAmount !== null && row.penaltyAmount > 0) || row.penaltyExposure > 0 ? (
                        <span className="inline-flex items-center rounded-md border border-rose-200 bg-rose-50 px-2 py-0.5 text-xs font-bold text-rose-700">
                          {row.penaltyAmount !== null && row.penaltyAmount > 0
                            ? `₱${row.penaltyAmount.toLocaleString()}`
                            : row.penaltyExposure > 0
                            ? `₱${row.penaltyExposure.toLocaleString()}`
                            : "Penalty Active"}
                        </span>
                      ) : (
                        <span className="inline-flex items-center rounded-md border border-table-rule bg-table-header px-2 py-0.5 text-xs font-medium text-table-text-muted">
                          No Penalty
                        </span>
                      )}
                    </td>

                    {/* 10. ACTIONS */}
                    <td className="border-b border-table-rule px-4 py-2.5 text-right">
                      <div className="flex items-center justify-end gap-1.5">
                        {/* Open tab: No Endorse button - drawer only */}

                        {status === "pipeline" && (
                          <>
                            {onAdvancePipeline && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onAdvancePipeline(row);
                                }}
                                className="inline-flex items-center gap-1 rounded bg-purple-50 px-2 py-1 text-xs font-semibold text-purple-700 border border-purple-200 hover:bg-purple-100 transition shadow-xs"
                                title={`Update pipeline stage for ${row.applicantName || row.vcode}`}
                              >
                                <TrendingUp className="h-3.5 w-3.5" aria-hidden="true" />
                                <span className="hidden sm:inline">Stage</span>
                              </button>
                            )}
                            {onMarkHired && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onMarkHired(row);
                                }}
                                className="inline-flex items-center gap-1 rounded bg-emerald-50 px-2 py-1 text-xs font-semibold text-emerald-700 border border-emerald-200 hover:bg-emerald-100 transition shadow-xs"
                                title={`Mark ${row.applicantName || row.vcode} as hired`}
                              >
                                <CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" />
                                <span className="hidden sm:inline">Hire</span>
                              </button>
                            )}
                            {onFailBackout && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onFailBackout(row);
                                }}
                                className="inline-flex items-center justify-center rounded bg-rose-50 p-1 text-rose-700 border border-rose-200 hover:bg-rose-100 transition shadow-xs"
                                title={`Dropout / backout candidate for ${row.vcode}`}
                              >
                                <UserMinus className="h-3.5 w-3.5" aria-hidden="true" />
                              </button>
                            )}
                          </>
                        )}

                        {status === "hired" && onEditHiredDate && (
                          <button
                            type="button"
                            onClick={(e) => {
                              e.stopPropagation();
                              onEditHiredDate(row);
                            }}
                            className="inline-flex items-center gap-1 rounded bg-blue-50 px-2 py-1 text-xs font-semibold text-blue-700 border border-blue-200 hover:bg-blue-100 transition shadow-xs"
                            title={`Edit hired date for ${row.applicantName || row.vcode}`}
                          >
                            <Calendar className="h-3.5 w-3.5" aria-hidden="true" />
                            <span className="hidden sm:inline">Edit Date</span>
                          </button>
                        )}

                        {status === "closure" && (
                          <div className="flex items-center gap-1">
                            {onReviewClosure && (
                              <>
                                <button
                                  type="button"
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    onReviewClosure(row, "Approved");
                                  }}
                                  className="inline-flex items-center gap-1 rounded bg-emerald-50 px-2 py-1 text-xs font-semibold text-emerald-700 border border-emerald-200 hover:bg-emerald-100 transition shadow-xs"
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
                                  className="inline-flex items-center gap-1 rounded bg-rose-50 px-2 py-1 text-xs font-semibold text-rose-700 border border-rose-200 hover:bg-rose-100 transition shadow-xs"
                                  title={`Reject closure request for ${row.vcode}`}
                                >
                                  <X className="h-3 w-3" aria-hidden="true" />
                                  <span className="hidden sm:inline">Reject</span>
                                </button>
                              </>
                            )}
                            {onRequestClosure && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onRequestClosure(row);
                                }}
                                className="inline-flex items-center gap-1 rounded bg-slate-100 px-2 py-1 text-xs font-semibold text-slate-700 border border-slate-200 hover:bg-slate-200 transition shadow-xs"
                                title={`Review closure details for ${row.vcode}`}
                              >
                                <Archive className="h-3.5 w-3.5" aria-hidden="true" />
                                <span className="hidden sm:inline">Review</span>
                              </button>
                            )}
                          </div>
                        )}

                        {status === "failed_backout" && onReopenVacancy && (
                          <button
                            type="button"
                            onClick={(e) => {
                              e.stopPropagation();
                              onReopenVacancy(row);
                            }}
                            className="inline-flex items-center gap-1 rounded bg-emerald-50 px-2 py-1 text-xs font-semibold text-emerald-700 border border-emerald-200 hover:bg-emerald-100 transition shadow-xs"
                            title={`Reopen slot for ${row.vcode}`}
                          >
                            <RotateCcw className="h-3.5 w-3.5" aria-hidden="true" />
                            <span className="hidden sm:inline">Reopen</span>
                          </button>
                        )}

                        <button
                          aria-label={`Select vacancy ${row.vcode}`}
                          className="inline-flex h-7 w-7 items-center justify-center rounded-md border border-table-rule-section text-table-text-muted hover:bg-table-row transition"
                          disabled={!row.rowCapabilities.canViewDetail}
                          onClick={(e) => {
                            e.stopPropagation();
                            onSelect(row);
                          }}
                          type="button"
                          title="View Details"
                        >
                          <Eye className="h-3.5 w-3.5" aria-hidden="true" />
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-2 border-t border-table-rule-section px-4 py-3 text-sm text-table-text-muted">
        <span>
          {firstRecord}-{lastRecord} of {totalCount} records
        </span>
        <div className="flex items-center gap-2">
          <button
            className="h-8 rounded-md border border-table-rule-section px-3 font-medium text-table-text-sub disabled:opacity-50"
            disabled={page <= 1 || isLoading}
            onClick={() => onPageChange(page - 1)}
            type="button"
          >
            Previous
          </button>
          <span>
            Page {page} of {pageCount}
          </span>
          <button
            className="h-8 rounded-md border border-table-rule-section px-3 font-medium text-table-text-sub disabled:opacity-50"
            disabled={page >= pageCount || isLoading}
            onClick={() => onPageChange(page + 1)}
            type="button"
          >
            Next
          </button>
        </div>
      </div>
    </section>
  );
}
