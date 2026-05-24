// components/vacancy/VacancyTable.tsx
"use client";

import {
  ClipboardList,
  Clock3,
  Eye,
  LockKeyhole,
  RefreshCw,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import type {
  VacancyDataErrorKind,
  VacancyListItem,
  VacancyStatus,
} from "@/lib/queries/vacancy";

export type { VacancyStatus } from "@/lib/queries/vacancy";

const tableColumns = [
  "VCode",
  "Position",
  "Department",
  "Scope",
  "Status",
  "Applicant",
  "Requested",
  "Aging",
  "Last Activity",
  "",
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


function formatDate(value: string | null) {
  if (!value) {
    return "--";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat("en", {
    month: "short",
    day: "2-digit",
    year: "numeric",
  }).format(date);
}

function getScope(row: VacancyListItem) {
  return [row.accountName, row.groupName, row.storeName].filter(Boolean).join(" / ");
}

function getAgingLabel(row: VacancyListItem) {
  if (row.agingDays === null) {
    return row.agingBucket ?? "--";
  }

  return `${row.agingDays}d${row.agingBucket ? ` / ${row.agingBucket}` : ""}`;
}

function getStatusLabel(row: VacancyListItem) {
  return row.derivedStatus ?? row.vacancyStatus ?? row.pipelineStatus ?? "--";
}

function getApplicantLabel(row: VacancyListItem) {
  if (row.activeApplicantCount > 0) {
    return `${row.activeApplicantCount} active`;
  }

  if (row.confirmedOnboardCount > 0 || row.hasRecentHire) {
    return `${row.confirmedOnboardCount} onboarded`;
  }

  return "None";
}

function getErrorCopy(kind: VacancyDataErrorKind | null) {
  if (kind === "access_denied") {
    return {
      title: "Vacancy access blocked",
      body: "Supabase denied this read request for the current user. The page is staying read-blocked instead of showing partial or unscoped records.",
    };
  }

  return {
    title: "Vacancy data unavailable",
    body: "The vacancy RPC request failed. You can retry without changing filters.",
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
    <section className="flex min-h-[440px] flex-col rounded-md border border-gray-200 bg-white">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-gray-200 px-3 py-2">
        <div>
          <div className="flex items-center gap-2">
            <h2 className="text-sm font-semibold text-gray-900">
              {statusDescription}
            </h2>
            <Badge className="font-mono text-[11px] text-gray-500">{status}</Badge>
          </div>
          <p className="mt-0.5 text-xs text-gray-500">
            Read-only rows from the scoped vacancy list RPC.
          </p>
        </div>
        <div className="flex items-center gap-2 text-xs text-gray-500">
          <Clock3 className="h-4 w-4" aria-hidden="true" />
          {isLoading ? "Loading vacancy queue" : `${totalCount} scoped records`}
        </div>
      </div>

      <div className="min-h-0 flex-1 overflow-auto">
        <table className="w-full min-w-[1060px] border-separate border-spacing-0 text-left text-sm">
          <thead className="sticky top-0 z-10 bg-gray-50 text-xs font-semibold uppercase text-gray-500">
            <tr>
              {tableColumns.map((column) => (
                <th
                  className="border-b border-gray-200 px-3 py-2"
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
                    <div className="text-sm font-medium text-gray-700">
                      Loading scoped vacancies
                    </div>
                    <div className="text-sm text-gray-500">
                      Fetching {statusDescription.toLowerCase()} through
                      list_web_vacancies.
                    </div>
                  </div>
                </td>
              </tr>
            ) : errorKind ? (
              <tr>
                <td className="px-3 py-12 text-center" colSpan={tableColumns.length}>
                  <div className="mx-auto flex max-w-md flex-col items-center gap-2">
                    <div className="rounded-md border border-red-200 bg-red-50 p-2">
                      <LockKeyhole
                        className="h-5 w-5 text-red-500"
                        aria-hidden="true"
                      />
                    </div>
                    <div className="text-sm font-medium text-gray-800">
                      {errorCopy.title}
                    </div>
                    <div className="text-sm text-gray-500">{errorCopy.body}</div>
                    {errorKind === "retryable" ? (
                      <button
                        className="mt-2 inline-flex h-8 items-center gap-2 rounded-md border border-gray-200 bg-white px-3 text-sm font-medium text-gray-700"
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
                    <div className="rounded-md border border-gray-200 bg-gray-50 p-2">
                      <ClipboardList
                        className="h-5 w-5 text-gray-400"
                        aria-hidden="true"
                      />
                    </div>
                    <div className="text-sm font-medium text-gray-700">
                      No vacancies found
                    </div>
                    <div className="text-sm text-gray-500">
                      The backend returned an empty scoped result for this queue,
                      search, and filter combination.
                    </div>
                  </div>
                </td>
              </tr>
            ) : (
              rows.map((row) => (
                <tr
                  className={`border-b border-gray-100 transition-colors ${
                    row.rowCapabilities.canViewDetail ? "cursor-pointer" : "cursor-not-allowed"
                  } ${
                    selectedId === row.id ? "bg-blue-50" : "hover:bg-gray-50"
                  }`}
                  key={row.id}
                  onClick={() => {
                    if (row.rowCapabilities.canViewDetail) {
                      onSelect(row);
                    }
                  }}
                >
                  <td className="border-b border-gray-100 px-3 py-2 font-mono text-xs text-gray-700">
                    {row.vcode}
                  </td>
                  <td className="border-b border-gray-100 px-3 py-2">
                    <div className="font-medium text-gray-900">
                      {row.position_title ?? "--"}
                    </div>
                    <div className="text-xs text-gray-500">
                      {row.employmentType ?? "Employment type unavailable"}
                    </div>
                  </td>
                  <td className="border-b border-gray-100 px-3 py-2 text-gray-600">
                    {row.department ?? "--"}
                  </td>
                  <td className="border-b border-gray-100 px-3 py-2 text-gray-600">
                    {getScope(row) || "--"}
                  </td>
                  <td className="border-b border-gray-100 px-3 py-2">
                    <div className="flex flex-col items-start gap-1">
                      <Badge className="border-blue-200 bg-blue-50 text-blue-700">
                        {getStatusLabel(row)}
                      </Badge>
                      <span className="text-xs text-gray-500">
                        {row.pipelineStatus ?? "Pipeline unavailable"}
                      </span>
                    </div>
                  </td>
                  <td className="border-b border-gray-100 px-3 py-2 text-gray-600">
                    {getApplicantLabel(row)}
                  </td>
                  <td className="border-b border-gray-100 px-3 py-2 text-gray-600">
                    {formatDate(row.vacantDate)}
                  </td>
                  <td className="border-b border-gray-100 px-3 py-2 text-gray-600">
                    {getAgingLabel(row)}
                  </td>
                  <td className="border-b border-gray-100 px-3 py-2 text-gray-600">
                    {formatDate(row.lastActivityAt)}
                  </td>
                  <td className="border-b border-gray-100 px-3 py-2 text-right">
                    <button
                      aria-label={`Select vacancy ${row.vcode}`}
                      className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-gray-200 text-gray-500 hover:bg-white transition animate-duration-150"
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
              ))
            )}
          </tbody>
        </table>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-2 border-t border-gray-200 px-3 py-2 text-xs text-gray-500">
        <span>
          {firstRecord}-{lastRecord} of {totalCount} records
        </span>
        <div className="flex items-center gap-2">
          <button
            className="h-8 rounded-md border border-gray-200 px-3 font-medium text-gray-600 disabled:text-gray-300"
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
            className="h-8 rounded-md border border-gray-200 px-3 font-medium text-gray-600 disabled:text-gray-300"
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

