// app/(dashboard)/hr-emploc/page.tsx
"use client";

import { useMemo, useState, type FormEvent } from "react";
import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import {
  FileSearch,
  LockKeyhole,
  Building,
  Briefcase,
  Send,
  Loader2,
  CheckCircle2,
  UploadCloud,
  Clock,
  AlertCircle,
  FileText,
  RotateCcw,
  Users,
} from "lucide-react";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
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
import { AdminFilterBar } from "@/components/shared/AdminFilterBar";
import { AssignEmployeeNoModal } from "@/components/hr-emploc/AssignEmployeeNoModal";

const queueTabs: Array<{
  value: HrEmplocQueue;
  label: string;
  icon: typeof Clock;
}> = [
  {
    value: "pending",
    label: "Pending",
    icon: Clock,
  },
  {
    value: "correction",
    label: "Correction",
    icon: AlertCircle,
  },
  {
    value: "review",
    label: "Review",
    icon: FileText,
  },
  {
    value: "ready",
    label: "Ready",
    icon: CheckCircle2,
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
  const [bulkResultModal, setBulkResultModal] = useState<{
    isOpen: boolean;
    moved: number;
    skipped: number;
    results: BulkMoveResultItem[];
  } | null>(null);
  const [assignTarget, setAssignTarget] = useState<HrEmplocListItem | null>(null);

  const bulkMoveMutation = useBulkMoveToPlantilla();

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

  function updatePage(nextPage: number) {
    setPage(nextPage);
    setSelectedId(null);
  }

  function retryQueryReads() {
    void summaryQuery.refetch();
    void listQuery.refetch();
  }

  async function handleBulkMove() {
    if (window.confirm("Deploy all ready candidates into Plantilla slots?")) {
      const results = await bulkMoveMutation.mutateAsync();
      const moved = results.filter((r) => r.result === "moved").length;
      const skipped = results.filter((r) => r.result === "skipped").length;
      setBulkResultModal({
        isOpen: true,
        moved,
        skipped,
        results,
      });
      retryQueryReads();
    }
  }

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
  const tabCounts: Record<HrEmplocQueue, number> = useMemo(() => {
    const summary = summaryQuery.data;
    return {
      pending: summary?.pending ?? 0,
      correction: summary?.correction ?? 0,
      review: summary?.review ?? 0,
      ready: summary?.ready ?? 0,
      deficiency: summary?.correction ?? 0,
      complete: summary?.ready ?? 0,
      deletion_pending: summary?.pendingDeletion ?? 0,
      all: 0,
    };
  }, [summaryQuery.data]);

  return (
    <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-4 text-gray-900">
      <AdminPageHeader
        categoryTag="ADMIN PANEL"
        moduleName="HR Emploc"
        title="HR Employee Placement (Emploc)"
        subtitle="Store assignment reconciliation, employee movements, and workforce compliance."
        icon={Users}
        primaryAction={{
          label: summaryQuery.isFetching || listQuery.isFetching ? "Refreshing..." : "Refresh Data",
          icon: RotateCcw,
          onClick: () => {
            void summaryQuery.refetch();
            void listQuery.refetch();
          },
          disabled: summaryQuery.isFetching || listQuery.isFetching,
        }}
      />

      {/* Unified workbench card: Status tabs & Filter toolbar */}
      <div className="flex flex-col gap-3 rounded-lg border border-border-default bg-surface-card p-3 shadow-xs">
        {/* Status Tabs Navigation */}
        <div
          aria-label="HR Emploc queue filter"
          className="flex items-center gap-1.5 overflow-x-auto no-scrollbar scrollbar-none border-b border-border-subtle pb-3"
          role="tablist"
        >
          {queueTabs.map((tab) => {
            const Icon = tab.icon;
            const isActive = queue === tab.value;
            const count = tabCounts[tab.value];
            return (
              <button
                key={tab.value}
                aria-selected={isActive}
                className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                  isActive
                    ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
                    : "border-transparent bg-transparent text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary"
                }`}
                onClick={() => updateQueue(tab.value)}
                role="tab"
                type="button"
              >
                {Icon && (
                  <Icon
                    className={`w-4 h-4 shrink-0 transition-colors ${
                      isActive
                        ? "text-brand-700"
                        : "text-text-muted group-hover:text-text-secondary"
                    }`}
                  />
                )}
                <span>{tab.label}</span>
                <span
                  className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold shadow-2xs transition-colors ${
                    isActive
                      ? "bg-brand-600 text-white"
                      : "bg-slate-100 text-slate-600 border border-slate-200/80"
                  }`}
                >
                  {summaryQuery.isLoading ? "–" : count}
                </span>
              </button>
            );
          })}
        </div>

        {/* Filter Bar Controls */}
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
              {queue === "ready" && (
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
              <Link
                href="/hr-emploc/import"
                className="inline-flex h-10 items-center gap-1.5 rounded-md border border-gray-300 bg-white px-3.5 text-sm font-semibold text-gray-700 shadow-xs hover:bg-gray-50 transition"
              >
                <UploadCloud className="h-4 w-4 text-gray-500" aria-hidden="true" />
                <span>Import XLSX</span>
              </Link>
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
        </div>

        {/* Roster Grid Component */}
        <HrEmplocTable
          errorKind={listErrorKind}
          isLoading={listQuery.isLoading}
          onPageChange={updatePage}
          onRetry={retryQueryReads}
          onSelect={selectRow}
          onAssignEmployeeNo={(row) => setAssignTarget(row)}
          page={page}
          pageSize={pageSize}
          rows={rows}
          selectedId={selectedId}
          queue={queue}
          queueLabel={activeQueueLabel}
          totalCount={totalCount}
        />

        {/* Selected Details Aside Inspector */}
        <HrEmplocDetailDrawer
          hrEmplocId={selectedId}
          onClose={() => setSelectedId(null)}
        />

        {/* Inline Assign Employee No Modal (opened from table row) */}
        {assignTarget && (
          <AssignEmployeeNoModal
            hrEmplocId={assignTarget.id}
            candidateName={assignTarget.applicantName}
            vcode={assignTarget.vcode}
            currentEmployeeNo={assignTarget.employeeNo}
            onClose={() => setAssignTarget(null)}
            onSuccess={() => {
              setAssignTarget(null);
              retryQueryReads();
            }}
          />
        )}

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
