// components/vacancy/VacancyTable.tsx
"use client";

import {
  ClipboardList,
  Clock3,
  FileText,
  LockKeyhole,
  MoreHorizontal,
  UserRound,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";

export type VacancyStatus = "open" | "with_applicant" | "rejected" | "backout";

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

const actionCapabilities = [
  { key: "vacancy.approve", label: "Approve" },
  { key: "vacancy.update_applicant_status", label: "Applicant status" },
  { key: "vacancy.request_closure", label: "Request closure" },
];

type VacancyTableProps = {
  status: VacancyStatus;
  statusDescription: string;
};

type VacancyDetailPanelProps = {
  capabilities?: string[];
};

export function VacancyTable({ status, statusDescription }: VacancyTableProps) {
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
            Read-only table frame awaiting scoped vacancy list data.
          </p>
        </div>
        <div className="flex items-center gap-2 text-xs text-gray-500">
          <Clock3 className="h-4 w-4" aria-hidden="true" />
          No refresh source configured
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
            <tr>
              <td className="px-3 py-12 text-center" colSpan={tableColumns.length}>
                <div className="mx-auto flex max-w-md flex-col items-center gap-2">
                  <div className="rounded-md border border-gray-200 bg-gray-50 p-2">
                    <ClipboardList className="h-5 w-5 text-gray-400" aria-hidden="true" />
                  </div>
                  <div className="text-sm font-medium text-gray-700">
                    No vacancy records loaded
                  </div>
                  <div className="text-sm text-gray-500">
                    This shell does not fetch Supabase data or render sample rows.
                    Records will appear here after the approved list contract is
                    implemented.
                  </div>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-2 border-t border-gray-200 px-3 py-2 text-xs text-gray-500">
        <span>0 records</span>
        <span>Pagination placeholder pending backend limit and offset contract</span>
      </div>
    </section>
  );
}

export function VacancyDetailPanel({
  capabilities = [],
}: VacancyDetailPanelProps) {
  return (
    <aside className="flex min-h-[440px] flex-col rounded-md border border-gray-200 bg-white">
      <div className="border-b border-gray-200 px-3 py-2">
        <div className="flex items-center justify-between gap-3">
          <div>
            <h2 className="text-sm font-semibold text-gray-900">
              Vacancy Detail
            </h2>
            <p className="mt-0.5 text-xs text-gray-500">
              Selection-driven detail drawer placeholder.
            </p>
          </div>
          <button
            aria-label="Detail actions"
            className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-gray-200 text-gray-400"
            disabled
            type="button"
          >
            <MoreHorizontal className="h-4 w-4" aria-hidden="true" />
          </button>
        </div>
      </div>

      <div className="flex flex-1 flex-col gap-3 p-3">
        <section className="rounded-md border border-dashed border-gray-300 bg-gray-50 p-3">
          <div className="flex items-start gap-2">
            <FileText className="mt-0.5 h-4 w-4 text-gray-400" aria-hidden="true" />
            <div>
              <div className="text-sm font-medium text-gray-700">
                Select a vacancy from the table
              </div>
              <p className="mt-1 text-sm text-gray-500">
                The drawer opens from real list rows only. No placeholder vacancy
                identity, request context, or timeline data is fabricated.
              </p>
            </div>
          </div>
        </section>

        <section className="rounded-md border border-gray-200 p-3">
          <div className="flex items-center gap-2 text-sm font-semibold text-gray-800">
            <UserRound className="h-4 w-4 text-gray-500" aria-hidden="true" />
            Applicant Section
          </div>
          <p className="mt-2 text-sm text-gray-500">
            Applicant summary and workflow controls are reserved for a future
            detail contract and backend-authorized action RPCs.
          </p>
        </section>

        <section className="rounded-md border border-gray-200 p-3">
          <div className="flex items-center gap-2 text-sm font-semibold text-gray-800">
            <LockKeyhole className="h-4 w-4 text-gray-500" aria-hidden="true" />
            Action Zone
          </div>
          <div className="mt-3 grid gap-2">
            {actionCapabilities.map((action) => {
              const isAvailable = capabilities.includes(action.key);

              return (
                <button
                  className="flex h-9 items-center justify-between rounded-md border border-gray-200 bg-gray-50 px-3 text-left text-sm text-gray-500"
                  disabled
                  key={action.key}
                  type="button"
                >
                  <span>{action.label}</span>
                  <span className="font-mono text-[11px]">
                    {isAvailable ? "available" : "not exposed"}
                  </span>
                </button>
              );
            })}
          </div>
          <p className="mt-3 text-xs text-gray-500">
            Capability visibility is presentation-only. Supabase RPCs must still
            enforce record state, scope, and authorization before actions are
            wired.
          </p>
        </section>
      </div>
    </aside>
  );
}
