// app/(dashboard)/hr-emploc/page.tsx
"use client";

import { useMemo, useState, type FormEvent } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  ClipboardCheck,
  FileSearch,
  LockKeyhole,
  Building,
  Briefcase,
} from "lucide-react";
import {
  HrEmplocTable,
  type HrEmplocQueue,
} from "@/components/hr-emploc/HrEmplocTable";
import { HrEmplocDetailDrawer } from "@/components/hr-emploc/HrEmplocDetailDrawer";
import {
  getWebHrEmplocSummary,
  listWebHrEmplocs,
  HrEmplocDataError,
  type HrEmplocListItem,
} from "@/lib/queries/hr_emploc";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { MetricCard } from "@/components/shared/MetricCard";
import { AdminFilterBar } from "@/components/shared/AdminFilterBar";

const queueTabs: Array<{ value: HrEmplocQueue; label: string; description: string }> = [
  {
    value: "pending",
    label: "Pending Review",
    description: "Confirmed onboard recruits awaiting initial document audit or correction re-check.",
  },
  {
    value: "deficiency",
    label: "For Correction",
    description: "Recruits sent back to field coordinators with active document deficiencies.",
  },
  {
    value: "complete",
    label: "Compliance Complete",
    description: "Compliance validation completed. Ready for employee ID assignment and Plantilla deploy.",
  },
  {
    value: "deletion_pending",
    label: "Pending Deletion",
    description: "Recruits with separation or duplicate separation requests pending admin review.",
  },
  {
    value: "all",
    label: "All / History",
    description: "Auditable global history of all employee compliance allocations.",
  },
];

const pageSize = 25;

function getErrorKind(error: unknown) {
  return error instanceof HrEmplocDataError ? error.kind : null;
}

export default function HrEmplocPage() {
  const [queue, setQueue] = useState<HrEmplocQueue>("pending");
  const [searchDraft, setSearchDraft] = useState("");
  const [search, setSearch] = useState("");
  const [assignment, setAssignment] = useState<"Stationary" | "Roving" | "">("");
  const [position, setPosition] = useState("");
  const [accountId, setAccountId] = useState("");
  const [groupId, setGroupId] = useState("");
  const [page, setPage] = useState(1);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  // Group filter parameters
  const listParams = useMemo(
    () => ({
      queue,
      accountId: accountId.trim() || undefined,
      groupId: groupId.trim() || undefined,
      position: position.trim() || undefined,
      assignment: assignment || undefined,
      search: search.trim() || undefined,
      page,
      pageSize,
    }),
    [queue, accountId, groupId, position, assignment, search, page],
  );

  const summaryParams = useMemo(
    () => ({
      accountId: accountId.trim() || undefined,
      groupId: groupId.trim() || undefined,
      position: position.trim() || undefined,
      search: search.trim() || undefined,
    }),
    [accountId, groupId, position, search],
  );

  // Queries
  const summaryQuery = useQuery({
    queryKey: ["hr-emploc-summary", summaryParams],
    queryFn: () => getWebHrEmplocSummary(summaryParams),
    retry: false,
  });

  const listQuery = useQuery({
    queryKey: ["hr-emploc-list", listParams],
    queryFn: () => listWebHrEmplocs(listParams),
    retry: false,
  });

  const rows = listQuery.data?.data ?? [];
  const totalCount = listQuery.data?.totalCount ?? 0;

  const listErrorKind = getErrorKind(listQuery.error);
  const summaryErrorKind = getErrorKind(summaryQuery.error);
  const errorKind = listErrorKind ?? summaryErrorKind;
  const blocked = errorKind === "access_denied";

  const activeQueueLabel =
    queueTabs.find((tab) => tab.value === queue)?.label ?? "Compliance Queue";
  const activeQueueDescription =
    queueTabs.find((tab) => tab.value === queue)?.description ?? "Employee placements in compliance.";

  // Metric summaries
  const kpis = [
    {
      label: "Total Processing",
      value: summaryQuery.data?.totalPending,
      helper: "Pending initial review or audit",
      badge: "Pending",
    },
    {
      label: "Action Needed",
      value: summaryQuery.data?.actionNeeded,
      helper: "Deficiency tags sent to field",
      badge: "Correction",
    },
    {
      label: "Ready to Deploy",
      value: summaryQuery.data?.readyToDeploy,
      helper: "Compliance met, awaiting ID",
      badge: "Complete",
    },
    {
      label: "SLA Breach Watch",
      value: summaryQuery.data?.slaBreaches,
      helper: " Lagging past 3-day window",
      badge: "Aging Watch",
    },
  ];

  function updateQueue(nextQueue: HrEmplocQueue) {
    setQueue(nextQueue);
    setPage(1);
    setSelectedId(null);
  }

  function applySearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSearch(searchDraft.trim());
    setPage(1);
    setSelectedId(null);
  }

  function selectRow(row: HrEmplocListItem) {
    setSelectedId(row.id);
  }

  function retryQueryReads() {
    void summaryQuery.refetch();
    void listQuery.refetch();
  }

  function updatePage(nextPage: number) {
    setPage(nextPage);
    setSelectedId(null);
  }

  return (
    <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-4 p-4 text-gray-900 sm:p-5">
      {/* Page Header */}
      <AdminPageHeader
        title="HR Emploc Compliance"
        subtitle="Operational onboarding compliance control panel backed by scoped Supabase summary and roster RPCs."
        icon={ClipboardCheck}
        readOnly={true}
      />

      {/* KPI Cards Row (CLS Shift Guarded) */}
      <section
        aria-label="Compliance summary metrics"
        className="grid gap-2 sm:grid-cols-2 xl:grid-cols-4"
      >
        {kpis.map((item) => (
          <MetricCard
            key={item.label}
            label={item.label}
            value={item.value}
            helperText={item.helper}
            isLoading={summaryQuery.isLoading}
            isBlocked={blocked}
            badgeLabel={item.badge}
            isError={summaryQuery.isError}
            errorText="Summary data failed to load"
          />
        ))}
      </section>

      {/* Queue Status Tabs & Filters Bar */}
      <section className="flex min-h-0 flex-1 flex-col gap-3">
        {/* Status Tabs Navigation */}
        <div className="flex flex-col gap-2 border-b border-gray-100 pb-3">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div
              aria-label="Compliance queue filter"
              className="inline-flex rounded-md border border-gray-200 bg-white p-1 shadow-xs"
              role="tablist"
            >
              {queueTabs.map((tab) => (
                <button
                  aria-selected={queue === tab.value}
                  className={`rounded px-3 py-1.5 text-xs font-semibold transition-all duration-150 ${
                    queue === tab.value
                      ? "bg-blue-600 text-white shadow-sm"
                      : "text-gray-600 hover:bg-gray-100"
                  }`}
                  key={tab.value}
                  onClick={() => updateQueue(tab.value)}
                  role="tab"
                  type="button"
                >
                  {tab.label}
                </button>
              ))}
            </div>
            <div className="text-xs text-gray-400 font-medium">
              Roster matches are evaluated under backend-authoritative Supabase RBAC scopes.
            </div>
          </div>
          <p className="text-xs text-gray-500 italic pl-1">
            {activeQueueDescription}
          </p>
        </div>

        {/* Filter Bar Controls */}
        <div className="flex min-h-0 flex-1 flex-col gap-3">
          <AdminFilterBar
            searchPlaceholder="Search candidate name, VCode, deficiencies..."
            searchVal={searchDraft}
            onSearchChange={setSearchDraft}
            onSearchSubmit={applySearch}
            disabled={blocked}
            showApplyButton={true}
            applyLabel="Search & Filter"
            extraActionsSlot={
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md border border-gray-200 bg-white px-3 text-sm font-medium text-gray-400 hover:bg-gray-50/50 cursor-not-allowed transition-colors"
                disabled
                type="button"
              >
                <FileSearch className="h-4 w-4" aria-hidden="true" />
                Saved View
              </button>
            }
          >
            {/* Assignment filter */}
            <select
              aria-label="Assignment type filter"
              className="h-9 rounded-md border border-gray-200 bg-white px-3 text-sm text-gray-600 outline-none focus:border-blue-300 transition-colors"
              disabled={blocked}
              onChange={(event) => {
                setAssignment(event.target.value as "Stationary" | "Roving" | "");
                setPage(1);
                setSelectedId(null);
              }}
              value={assignment}
            >
              <option value="">All Assignment Types</option>
              <option value="Stationary">Stationary</option>
              <option value="Roving">Roving</option>
            </select>

            {/* Position filter */}
            <div className="relative flex items-center">
              <Briefcase className="absolute left-2.5 h-3.5 w-3.5 text-gray-400 pointer-events-none" />
              <input
                aria-label="Position title filter"
                className="h-9 rounded-md border border-gray-200 bg-white pl-8 pr-3 text-sm text-gray-600 outline-none focus:border-blue-300 transition-colors w-[150px]"
                disabled={blocked}
                onChange={(event) => {
                  setPosition(event.target.value);
                  setPage(1);
                  setSelectedId(null);
                }}
                placeholder="Position Filter"
                type="text"
                value={position}
              />
            </div>

            {/* Account UUID filter */}
            <div className="relative flex items-center">
              <Building className="absolute left-2.5 h-3.5 w-3.5 text-gray-400 pointer-events-none" />
              <input
                aria-label="Account UUID filter"
                className="h-9 rounded-md border border-gray-200 bg-white pl-8 pr-3 text-sm text-gray-600 outline-none focus:border-blue-300 transition-colors w-[150px]"
                disabled={blocked}
                onChange={(event) => {
                  setAccountId(event.target.value);
                  setPage(1);
                  setSelectedId(null);
                }}
                placeholder="Account ID (UUID)"
                type="text"
                value={accountId}
              />
            </div>

            {/* Group UUID filter */}
            <div className="relative flex items-center">
              <Building className="absolute left-2.5 h-3.5 w-3.5 text-gray-400 pointer-events-none" />
              <input
                aria-label="Group UUID filter"
                className="h-9 rounded-md border border-gray-200 bg-white pl-8 pr-3 text-sm text-gray-600 outline-none focus:border-blue-300 transition-colors w-[150px]"
                disabled={blocked}
                onChange={(event) => {
                  setGroupId(event.target.value);
                  setPage(1);
                  setSelectedId(null);
                }}
                placeholder="Group ID (UUID)"
                type="text"
                value={groupId}
              />
            </div>
          </AdminFilterBar>

          {/* Roster Grid Component */}
          <HrEmplocTable
            errorKind={listErrorKind}
            isLoading={listQuery.isLoading}
            onPageChange={updatePage}
            onRetry={retryQueryReads}
            onSelect={selectRow}
            page={page}
            pageSize={pageSize}
            rows={rows}
            selectedId={selectedId}
            queue={queue}
            queueLabel={activeQueueLabel}
            totalCount={totalCount}
          />
        </div>

        {/* Selected Details Aside Inspector */}
        <HrEmplocDetailDrawer
          hrEmplocId={selectedId}
          onClose={() => setSelectedId(null)}
        />
      </section>

      {/* Footer System Boundaries Notice */}
      <section className="rounded-md border border-dashed border-gray-300 bg-gray-50 p-3">
        <div className="flex items-start gap-2 text-xs text-gray-600">
          <LockKeyhole className="mt-0.5 h-4 w-4 text-gray-400 shrink-0" aria-hidden="true" />
          <div>
            <span className="font-semibold text-gray-700">Audit Security Active:</span> Allocation queries are gated under server-authoritative RLS scopes using <code className="font-mono bg-gray-100 px-1 rounded text-[11px]">auth.uid()</code> and user profile metadata. Tagging deficiencies, correcting remarks, employee ID assignments, Plantilla transitions, and separation approvals remain read-only pending approved backend mutations.
          </div>
        </div>
      </section>
    </div>
  );
}
