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
  Send,
  Loader2,
  CheckCircle2,
} from "lucide-react";
import {
  HrEmplocTable,
  type HrEmplocQueue,
} from "@/components/hr-emploc/HrEmplocTable";
import { HrEmplocDetailDrawer } from "@/components/hr-emploc/HrEmplocDetailDrawer";
import {
  getWebHrEmplocSummary,
  listWebHrEmplocs,
  useBulkMoveToPlantilla,
  HrEmplocDataError,
  type HrEmplocListItem,
  type BulkMoveResultItem,
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
      search: search.trim() || undefined,
      page,
      pageSize,
    }),
    [queue, accountId, groupId, search, page],
  );

  const summaryParams = useMemo(
    () => ({
      queue,
      accountId: accountId.trim() || undefined,
      groupId: groupId.trim() || undefined,
      search: search.trim() || undefined,
    }),
    [queue, accountId, groupId, search],
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

  const bulkMoveMutation = useBulkMoveToPlantilla();
  const [bulkResultModal, setBulkResultModal] = useState<{
    isOpen: boolean;
    moved: number;
    skipped: number;
    results: BulkMoveResultItem[];
  } | null>(null);

  function handleBulkMove() {
    if (confirm("Move all ready records to Plantilla? This will deploy all compliance-complete candidates with assigned employee numbers to their respective store slots.")) {
      bulkMoveMutation.mutate(undefined, {
        onSuccess: (results) => {
          const moved = results.filter((r) => r.result === "moved").length;
          const skipped = results.filter((r) => r.result === "skipped").length;
          setBulkResultModal({
            isOpen: true,
            moved,
            skipped,
            results,
          });
        },
      });
    }
  }

  return (
    <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-5 text-gray-900">
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
        className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4"
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
                  className={`rounded px-4 py-2 text-sm font-semibold transition-all duration-150 ${
                    queue === tab.value
                      ? "bg-brand-600 text-white shadow-sm"
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
            <div className="text-sm font-medium text-gray-500">
              Roster matches are evaluated under backend-authoritative Supabase RBAC scopes.
            </div>
          </div>
          <p className="pl-1 text-sm text-gray-500">
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
              <div className="flex items-center gap-2">
                {queue === "complete" && (
                  <button
                    className="inline-flex h-10 items-center gap-1.5 rounded-md bg-emerald-700 px-3.5 text-sm font-semibold text-white shadow-xs hover:bg-emerald-800 transition disabled:opacity-50 disabled:cursor-not-allowed"
                    disabled={bulkMoveMutation.isPending || rows.length === 0}
                    onClick={handleBulkMove}
                    type="button"
                  >
                    {bulkMoveMutation.isPending ? (
                      <Loader2 className="h-4 w-4 animate-spin" />
                    ) : (
                      <Send className="h-4 w-4" aria-hidden="true" />
                    )}
                    <span>{bulkMoveMutation.isPending ? "Deploying..." : "Bulk Deploy Ready"}</span>
                  </button>
                )}
                <button
                  className="inline-flex h-10 items-center gap-2 rounded-md border border-gray-200 bg-white px-4 text-sm font-medium text-gray-400 transition-colors hover:bg-gray-50/50 cursor-not-allowed"
                  disabled
                  type="button"
                >
                  <FileSearch className="h-4 w-4" aria-hidden="true" />
                  Saved View
                </button>
              </div>
            }
          >
            {/* Assignment filter */}
            <select
              aria-label="Assignment type filter"
              className="h-10 rounded-md border border-gray-200 bg-white px-3 text-sm text-gray-600 outline-none transition-colors focus:border-blue-300"
              disabled
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
                className="h-10 w-[170px] rounded-md border border-gray-200 bg-white pl-8 pr-3 text-sm text-gray-600 outline-none transition-colors focus:border-blue-300"
                disabled
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
                className="h-10 w-[170px] rounded-md border border-gray-200 bg-white pl-8 pr-3 text-sm text-gray-600 outline-none transition-colors focus:border-blue-300"
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
                className="h-10 w-[170px] rounded-md border border-gray-200 bg-white pl-8 pr-3 text-sm text-gray-600 outline-none transition-colors focus:border-blue-300"
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
            <span className="font-semibold text-gray-700">Audit Security Active:</span> Allocation queries, deficiency tagging, correction reviews, employee ID assignments, Plantilla deployments, and separation requests execute under server-authoritative RLS scopes using <code className="font-mono bg-gray-100 px-1 rounded text-[11px]">auth.uid()</code> and user profile metadata.
          </div>
        </div>
      </section>

      {/* Bulk Move Summary Dialog */}
      {bulkResultModal?.isOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div
            className="absolute inset-0 bg-black/40 backdrop-blur-xs"
            onClick={() => setBulkResultModal(null)}
          />
          <div className="relative z-10 w-full max-w-md bg-white rounded-lg border border-gray-200 shadow-xl overflow-hidden">
            <div className="flex items-center justify-between border-b border-gray-100 px-5 py-3.5 bg-emerald-50/50">
              <div className="flex items-center gap-2">
                <CheckCircle2 className="h-5 w-5 text-emerald-600" />
                <h3 className="text-sm font-semibold text-gray-900">Bulk Deploy Summary</h3>
              </div>
            </div>
            <div className="p-5 space-y-3">
              <p className="text-xs text-gray-600">
                Bulk move process completed for ready compliance records:
              </p>
              <div className="grid grid-cols-2 gap-3 text-xs">
                <div className="rounded-md border border-emerald-200 bg-emerald-50 p-3 text-center">
                  <span className="text-[10px] uppercase font-semibold text-emerald-700 block">Moved</span>
                  <span className="text-xl font-bold text-emerald-900">{bulkResultModal.moved}</span>
                </div>
                <div className="rounded-md border border-amber-200 bg-amber-50 p-3 text-center">
                  <span className="text-[10px] uppercase font-semibold text-amber-700 block">Skipped / Capacity</span>
                  <span className="text-xl font-bold text-amber-900">{bulkResultModal.skipped}</span>
                </div>
              </div>
              {bulkResultModal.results.length > 0 && (
                <div className="max-h-40 overflow-y-auto space-y-1 rounded border border-gray-100 p-2 text-[11px]">
                  {bulkResultModal.results.map((r, idx) => (
                    <div
                      key={r.hrEmplocId || `res-${idx}`}
                      className="flex justify-between items-center py-0.5 border-b border-gray-50 last:border-none"
                    >
                      <span className="font-mono text-gray-600 truncate max-w-[200px]">{r.hrEmplocId}</span>
                      <span
                        className={`font-semibold capitalize ${
                          r.result === "moved" ? "text-emerald-700" : "text-amber-700"
                        }`}
                      >
                        {r.result} {r.error ? `(${r.error})` : ""}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>
            <div className="flex justify-end border-t border-gray-100 px-5 py-3 bg-gray-50/50">
              <button
                type="button"
                onClick={() => setBulkResultModal(null)}
                className="rounded-md bg-brand-600 px-4 py-1.5 text-xs font-semibold text-white hover:bg-brand-700 transition"
              >
                Done
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
