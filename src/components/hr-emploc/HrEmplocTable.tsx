// components/hr-emploc/HrEmplocTable.tsx
"use client";

import {
  Clock3,
  Eye,
  LockKeyhole,
  AlertTriangle,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DataState } from "@/components/shared/DataState";
import type {
  HrEmplocDataErrorKind,
  HrEmplocListItem,
  HrEmplocQueue,
} from "@/lib/queries/hr_emploc";

export type { HrEmplocQueue } from "@/lib/queries/hr_emploc";

const tableColumns = [
  "Candidate",
  "VCode",
  "Account / Store",
  "Assignment",
  "Position",
  "HR Status",
  "Deployment",
  "Employee No",
  "SLA Age",
  "Deficiencies",
  "",
];

type HrEmplocTableProps = {
  queue: HrEmplocQueue;
  queueLabel: string;
  rows: HrEmplocListItem[];
  selectedId: string | null;
  totalCount: number;
  page: number;
  pageSize: number;
  isLoading: boolean;
  errorKind: HrEmplocDataErrorKind | null;
  onSelect: (row: HrEmplocListItem) => void;
  onRetry: () => void;
  onPageChange: (page: number) => void;
};



function getHrStatusVariant(status: string): "info" | "success" | "warning" | "danger" | "neutral" {
  const norm = status.toLowerCase().trim();
  if (norm === "pending" || norm === "for review" || norm === "for_review") return "info";
  if (norm === "for correction" || norm === "for_correction" || norm === "correction") return "warning";
  if (norm === "complete" || norm === "completed") return "success";
  if (norm === "pending deletion" || norm === "pending_deletion" || norm === "deletion") return "danger";
  return "neutral";
}

export function HrEmplocTable({
  queue,
  queueLabel,
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
}: HrEmplocTableProps) {
  const pageCount = Math.max(1, Math.ceil(totalCount / pageSize));
  const firstRecord = totalCount === 0 ? 0 : (page - 1) * pageSize + 1;
  const lastRecord = Math.min(totalCount, page * pageSize);

  const getErrorTitle = () => {
    return errorKind === "access_denied" ? "HR Emploc Access Blocked" : "Compliance Queue Data Unavailable";
  };

  const getErrorDescription = () => {
    return errorKind === "access_denied"
      ? "Supabase denied this compliance read request due to active RLS boundary checks. Partial or unscoped listings are blocked."
      : "The compliance RPC request failed on the server. You can retry the query directly.";
  };

  return (
    <section className="flex min-h-[440px] flex-col rounded-md border border-gray-200 bg-white">
      {/* Table Header Controls */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-gray-200 px-3 py-2">
        <div>
          <div className="flex items-center gap-2">
            <h2 className="text-sm font-semibold text-gray-900">
              {queueLabel}
            </h2>
            <Badge className="font-mono text-[10px] text-gray-500 bg-gray-100 hover:bg-gray-100 border-none">
              {queue}
            </Badge>
          </div>
          <p className="mt-0.5 text-xs text-gray-500">
            Compact queue tracking compliant onboarding milestones.
          </p>
        </div>
        <div className="flex items-center gap-2 text-xs text-gray-500">
          <Clock3 className="h-4 w-4" aria-hidden="true" />
          {isLoading ? "Loading compliance list" : `${totalCount} records scoped`}
        </div>
      </div>

      {/* Main Table Container */}
      <div className="min-h-0 flex-1 overflow-auto">
        <table className="w-full min-w-[1120px] border-separate border-spacing-0 text-left text-sm">
          <thead className="sticky top-0 z-10 bg-gray-50 text-xs font-semibold uppercase text-gray-500">
            <tr>
              {tableColumns.map((column, idx) => (
                <th
                  className={`border-b border-gray-200 px-3 py-2 ${
                    column === "" ? "text-right" : ""
                  }`}
                  key={column || `actions-${idx}`}
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
                  <DataState
                    kind="loading"
                    title="Loading compliance roster"
                    description="Executing list_web_hr_emplocs query on the Supabase cluster."
                  />
                </td>
              </tr>
            ) : errorKind ? (
              <tr>
                <td className="px-3 py-12 text-center" colSpan={tableColumns.length}>
                  <DataState
                    kind={errorKind === "access_denied" ? "access_denied" : "error"}
                    title={getErrorTitle()}
                    description={getErrorDescription()}
                    onRetry={onRetry}
                  />
                </td>
              </tr>
            ) : rows.length === 0 ? (
              <tr>
                <td className="px-3 py-12 text-center" colSpan={tableColumns.length}>
                  <DataState
                    kind="empty"
                    title="No recruits found"
                    description="No employee allocation records found matching active queue or filter criteria."
                  />
                </td>
              </tr>
            ) : (
              rows.map((row) => {
                const isPendingDeletion =
                  row.hrStatus.toLowerCase().trim() === "pending deletion" ||
                  row.hrStatus.toLowerCase().trim() === "pending_deletion";

                const isSlaBreached = row.slaBreached;

                return (
                  <tr
                    className={`border-b border-gray-100 transition-colors ${
                      row.rowCapabilities.canViewDetail ? "cursor-pointer" : "cursor-not-allowed"
                    } ${
                      selectedId === row.id
                        ? "bg-blue-50"
                        : isPendingDeletion
                        ? "bg-red-50 hover:bg-red-100"
                        : "hover:bg-gray-50"
                    }`}
                    key={row.id}
                    onClick={() => {
                      if (row.rowCapabilities.canViewDetail) {
                        onSelect(row);
                      }
                    }}
                  >
                    {/* Candidate Name */}
                    <td className="border-b border-gray-100 px-3 py-2">
                      <div className="font-semibold text-gray-900 flex items-center gap-1.5">
                        {isPendingDeletion && (
                          <AlertTriangle className="h-3.5 w-3.5 text-red-500 shrink-0" aria-hidden="true" />
                        )}
                        <span className={isPendingDeletion ? "text-gray-500 line-through" : ""}>
                          {row.applicantName}
                        </span>
                      </div>
                    </td>

                    {/* Vacancy Code */}
                    <td className="border-b border-gray-100 px-3 py-2">
                      <span className="font-mono text-xs text-gray-700 bg-gray-50 border border-gray-100 rounded px-1.5 py-0.5 select-all">
                        {row.vcode}
                      </span>
                    </td>

                    {/* Account / Store */}
                    <td className="border-b border-gray-100 px-3 py-2 text-gray-600">
                      <div className="font-medium text-gray-800 truncate max-w-[180px]">
                        {row.accountName ?? "--"}
                      </div>
                      <div className="text-xs text-gray-400 truncate max-w-[180px]">
                        {row.storeName ?? "--"}
                      </div>
                    </td>

                    {/* Assignment Type */}
                    <td className="border-b border-gray-100 px-3 py-2 text-gray-600">
                      {row.assignmentType === "Roving" ? (
                        <div className="relative group inline-block">
                          <span className="inline-flex items-center gap-1 text-xs font-semibold px-2 py-0.5 rounded-full bg-purple-50 text-purple-700 border border-purple-100">
                            Roving ({row.coveredStoresCount})
                          </span>
                          {/* Tooltip */}
                          <div className="absolute left-1/2 -translate-x-1/2 bottom-full mb-1 hidden group-hover:block bg-gray-900 text-white text-[10px] rounded py-1 px-2.5 shadow-md whitespace-nowrap z-30 transition duration-150">
                            Covers {row.coveredStoresCount} roving store placements.
                          </div>
                        </div>
                      ) : (
                        <span className="inline-flex items-center gap-1 text-xs font-semibold px-2 py-0.5 rounded-full bg-slate-50 text-slate-600 border border-slate-100">
                          Stationary
                        </span>
                      )}
                    </td>

                    {/* Position */}
                    <td className="border-b border-gray-100 px-3 py-2 text-gray-800">
                      {row.positionTitle ?? "--"}
                    </td>

                    {/* HR Status */}
                    <td className="border-b border-gray-100 px-3 py-2">
                      <StatusBadge variant={getHrStatusVariant(row.hrStatus)}>
                        {row.hrStatus}
                      </StatusBadge>
                    </td>

                    {/* Deployment Status */}
                    <td className="border-b border-gray-100 px-3 py-2 text-gray-600">
                      <span className="text-xs font-medium text-gray-700 bg-gray-50 border border-gray-100 rounded px-1.5 py-0.5">
                        {row.deploymentStatus}
                      </span>
                    </td>

                    {/* Employee Number */}
                    <td className="border-b border-gray-100 px-3 py-2">
                      {row.employeeNo ? (
                        <Badge className="font-mono text-xs bg-emerald-50 text-emerald-700 border-emerald-200">
                          {row.employeeNo}
                        </Badge>
                      ) : (
                        <span className="text-xs text-gray-400 italic">Unassigned</span>
                      )}
                    </td>

                    {/* SLA Age */}
                    <td className="border-b border-gray-100 px-3 py-2">
                      <div className="flex flex-col items-start">
                        <span
                          className={`font-semibold ${
                            isSlaBreached ? "text-red-600" : "text-gray-700"
                          }`}
                        >
                          {row.slaElapsedDays} Days
                        </span>
                        {isSlaBreached && (
                          <span className="inline-flex text-[9px] font-bold text-red-700 bg-red-50 border border-red-200 rounded px-1 mt-0.5 uppercase tracking-wide">
                            Breach
                          </span>
                        )}
                      </div>
                    </td>

                    {/* Deficiency Summary */}
                    <td className="border-b border-gray-100 px-3 py-2 text-xs text-gray-500 max-w-[150px] truncate">
                      {row.deficiencySummary || (
                        <span className="text-gray-400 italic">None</span>
                      )}
                    </td>

                    {/* Actions */}
                    <td className="border-b border-gray-100 px-3 py-2 text-right">
                      <div className="flex items-center justify-end gap-1.5">
                        {/* Capability hints */}
                        {row.rowCapabilities.canAssignEmployeeNo && (
                          <span
                            aria-label="Can assign employee number"
                            className="inline-block w-2 h-2 rounded-full bg-emerald-500"
                            title="Can Assign Employee ID"
                          />
                        )}
                        {row.rowCapabilities.canMoveToPlantilla && (
                          <span
                            aria-label="Can deploy to Plantilla"
                            className="inline-block w-2 h-2 rounded-full bg-blue-500"
                            title="Can Deploy to Plantilla"
                          />
                        )}
                        {isPendingDeletion && (
                          <span title="Record Locked: Pending Deletion">
                            <LockKeyhole
                              className="h-3.5 w-3.5 text-red-500"
                            />
                          </span>
                        )}
                        <button
                          aria-label={`Inspect candidate ${row.applicantName}`}
                          className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-gray-200 bg-white text-gray-500 hover:bg-gray-100 hover:text-gray-700 transition"
                          disabled={!row.rowCapabilities.canViewDetail}
                          onClick={(e) => {
                            e.stopPropagation();
                            onSelect(row);
                          }}
                          type="button"
                        >
                          <Eye className="h-4 w-4" aria-hidden="true" />
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

      {/* Pagination Footer */}
      <div className="flex flex-wrap items-center justify-between gap-2 border-t border-gray-200 px-3 py-2 text-xs text-gray-500">
        <span>
          Showing {firstRecord}-{lastRecord} of {totalCount} compliance records
        </span>
        <div className="flex items-center gap-2">
          <button
            className="h-8 rounded-md border border-gray-200 bg-white px-3 font-medium text-gray-600 shadow-xs hover:bg-gray-50 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            disabled={page <= 1 || isLoading}
            onClick={() => onPageChange(page - 1)}
            type="button"
          >
            Previous
          </button>
          <span className="font-medium">
            Page {page} of {pageCount}
          </span>
          <button
            className="h-8 rounded-md border border-gray-200 bg-white px-3 font-medium text-gray-600 shadow-xs hover:bg-gray-50 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
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
