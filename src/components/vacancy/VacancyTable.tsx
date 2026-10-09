// components/vacancy/VacancyTable.tsx
"use client";

import {
  ClipboardList,
  Clock3,
  Eye,
  LockKeyhole,
  RefreshCw,
  User,
  Users,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import type {
  VacancyDataErrorKind,
  VacancyListItem,
  VacancyStatus,
} from "@/lib/queries/vacancy";

export type { VacancyStatus } from "@/lib/queries/vacancy";

const tableColumns = [
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
  onRetry,
  onPageChange,
}: VacancyTableProps) {
  const pageCount = Math.max(1, Math.ceil(totalCount / pageSize));
  const firstRecord = totalCount === 0 ? 0 : (page - 1) * pageSize + 1;
  const lastRecord = Math.min(totalCount, page * pageSize);
  const errorCopy = getErrorCopy(errorKind);

  return (
    <section className="flex min-h-[520px] flex-col rounded-md border border-table-rule-section bg-table-row">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-table-rule-section px-4 py-3">
        <div>
          <div className="flex items-center gap-2">
            <h2 className="text-base font-semibold text-table-text">
              {statusDescription}
            </h2>
            <Badge className="font-mono text-[11px] text-table-text-muted">{status}</Badge>
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
              {tableColumns.map((column) => (
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
                <td className="px-3 py-12 text-center" colSpan={tableColumns.length}>
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
                <td className="px-3 py-12 text-center" colSpan={tableColumns.length}>
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
                <td className="px-3 py-12 text-center" colSpan={tableColumns.length}>
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
                        {row.groupName ?? "—"}
                      </div>
                    </td>

                    {/* 4. OUTLET NAME */}
                    <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub font-medium">
                      {row.storeName ?? "—"}
                    </td>

                    {/* 5. HRCO */}
                    <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub">
                      {row.hrcoName ? (
                        <div className="flex items-center gap-1.5">
                          <User className="h-3.5 w-3.5 shrink-0 text-table-text-muted" aria-hidden="true" />
                          <span>{row.hrcoName}</span>
                        </div>
                      ) : (
                        <span className="text-table-text-muted">—</span>
                      )}
                    </td>

                    {/* 6. STATUS */}
                    <td className="border-b border-table-rule px-4 py-2.5">
                      <div className="flex flex-col items-start gap-1">
                        <Badge
                          className={
                            statusKey === "open"
                              ? "border-blue-200 bg-blue-50 text-blue-700"
                              : statusKey === "pipeline" || statusKey === "with_applicant"
                              ? "border-purple-200 bg-purple-50 text-purple-700"
                              : statusKey === "hired" || statusKey === "filled"
                              ? "border-emerald-200 bg-emerald-50 text-emerald-700"
                              : "border-status-info-border bg-status-info-bg text-status-info-text"
                          }
                        >
                          {getStatusLabel(row)}
                        </Badge>
                        {row.pipelineStatus && row.pipelineStatus !== row.derivedStatus && (
                          <span className="text-[11px] text-table-text-muted">
                            {row.pipelineStatus}
                          </span>
                        )}
                      </div>
                    </td>

                    {/* 7. APPLICANT */}
                    <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub">
                      {row.applicantName ? (
                        <div>
                          <div className="font-medium text-table-text">
                            {row.applicantName}
                          </div>
                          {row.activeApplicantCount > 0 && (
                            <div className="text-[11px] text-table-text-muted">
                              {row.activeApplicantCount} in pipeline
                            </div>
                          )}
                        </div>
                      ) : row.activeApplicantCount > 0 ? (
                        <span className="inline-flex items-center gap-1.5 rounded-full border border-purple-200 bg-purple-50 px-2 py-0.5 text-xs font-medium text-purple-700">
                          <Users className="h-3 w-3 shrink-0" aria-hidden="true" />
                          <span>{row.activeApplicantCount} applicant{row.activeApplicantCount === 1 ? "" : "s"}</span>
                        </span>
                      ) : row.confirmedOnboardCount > 0 || row.hasRecentHire ? (
                        <span className="inline-flex items-center rounded-full border border-emerald-200 bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700">
                          <span>{row.confirmedOnboardCount} onboarded</span>
                        </span>
                      ) : (
                        <span className="text-table-text-muted">—</span>
                      )}
                    </td>

                    {/* 8. AGING */}
                    <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub">
                      {row.agingDays !== null && row.agingDays !== undefined ? (
                        <span
                          className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs ${
                            row.agingDays <= 15
                              ? "border border-emerald-200 bg-emerald-50 font-medium text-emerald-700"
                              : row.agingDays <= 30
                              ? "border border-amber-200 bg-amber-50 font-medium text-amber-700"
                              : "border border-rose-200 bg-rose-50 font-bold text-rose-700"
                          }`}
                        >
                          {row.agingDays} {row.agingDays === 1 ? "day" : "days"}
                        </span>
                      ) : row.agingBucket === "advance" ? (
                        <span className="inline-flex items-center rounded-full border border-blue-200 bg-blue-50 px-2.5 py-0.5 text-xs font-medium text-blue-700">
                          Advance
                        </span>
                      ) : row.agingBucket ? (
                        <span className="inline-flex items-center rounded-full border border-table-rule bg-table-row px-2.5 py-0.5 text-xs text-table-text-muted">
                          {formatAgingBucket(row.agingBucket)}
                        </span>
                      ) : (
                        <span className="text-table-text-muted">—</span>
                      )}
                    </td>

                    {/* 9. PENALTY */}
                    <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub">
                      {row.hasPenalty || (row.penaltyAmount !== null && row.penaltyAmount > 0) || row.penaltyExposure > 0 ? (
                        <span className="inline-flex items-center rounded-full border border-rose-200 bg-rose-50 px-2.5 py-0.5 text-xs font-semibold text-rose-700">
                          {row.penaltyAmount !== null && row.penaltyAmount > 0
                            ? `₱${row.penaltyAmount.toLocaleString()}`
                            : row.penaltyExposure > 0
                            ? `₱${row.penaltyExposure.toLocaleString()}`
                            : "Penalty Active"}
                        </span>
                      ) : (
                        <span className="inline-flex items-center rounded-full border border-table-rule bg-table-header px-2 py-0.5 text-xs text-table-text-muted">
                          None
                        </span>
                      )}
                    </td>

                    {/* 10. ACTIONS */}
                    <td className="border-b border-table-rule px-4 py-2.5 text-right">
                      <button
                        aria-label={`Select vacancy ${row.vcode}`}
                        className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-table-rule-section text-table-text-muted hover:bg-table-row transition animate-duration-150"
                        disabled={!row.rowCapabilities.canViewDetail}
                        onClick={(e) => {
                          e.stopPropagation();
                          onSelect(row);
                        }}
                        type="button"
                      >
                        <Eye className="h-4 w-4" aria-hidden="true" />
                      </button>
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
