// app/(dashboard)/hr-emploc/page.tsx
"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  FileSearch,
  LockKeyhole,
  Send,
  Loader2,
  CheckCircle2,
  Clock,
  AlertCircle,
  FileText,
  RotateCcw,
  Users,
  Search,
  X,
  Download,
  ChevronDown,
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
  fetchHrEmplocsForExport,
  downloadCsv,
  getCorrectionAttachmentSignedUrl,
  isBenefitsOnlyCorrection,
  HrEmplocDataError,
  type HrEmplocListItem,
  type BulkMoveResultItem,
} from "@/lib/queries/hr_emploc";
import { AssignEmployeeNoModal } from "@/components/hr-emploc/AssignEmployeeNoModal";
import { DeployToPlantillaModal } from "@/components/hr-emploc/DeployToPlantillaModal";
import { TagDeficiencyModal } from "@/components/hr-emploc/TagDeficiencyModal";
import { UploadAttachmentModal } from "@/components/hr-emploc/UploadAttachmentModal";
import { SubmitCorrectionModal } from "@/components/hr-emploc/SubmitCorrectionModal";
import { ReviewApproveModal } from "@/components/hr-emploc/ReviewApproveModal";
import { ReviewRevertModal } from "@/components/hr-emploc/ReviewRevertModal";
import { HrEmplocSavedViewsModal } from "@/components/hr-emploc/HrEmplocSavedViewsModal";
import {
  useHrEmplocSavedViews,
  type HrEmplocFilterState,
  type HrEmplocSavedView,
} from "@/components/hr-emploc/useHrEmplocSavedViews";
import { createClient } from "@/lib/supabase/client";

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

function getErrorKind(error: unknown) {
  return error instanceof HrEmplocDataError ? error.kind : null;
}

export default function HrEmplocPage() {
  const [queue, setQueue] = useState<HrEmplocQueue>("pending");
  const [searchDraft, setSearchDraft] = useState("");
  const [search, setSearch] = useState("");
  const [accountId, setAccountId] = useState("");
  const [groupId, setGroupId] = useState("");
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState<number>(10);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  // Modal target states
  const [assignTarget, setAssignTarget] = useState<HrEmplocListItem | null>(null);
  const [deployTarget, setDeployTarget] = useState<HrEmplocListItem | null>(null);
  const [correctionTarget, setCorrectionTarget] = useState<HrEmplocListItem | null>(null);
  const [uploadTarget, setUploadTarget] = useState<HrEmplocListItem | null>(null);
  const [submitCorrectionTarget, setSubmitCorrectionTarget] = useState<HrEmplocListItem | null>(null);
  const [approveReviewTarget, setApproveReviewTarget] = useState<HrEmplocListItem | null>(null);
  const [revertReviewTarget, setRevertReviewTarget] = useState<HrEmplocListItem | null>(null);
  const [bulkResultModal, setBulkResultModal] = useState<{
    isOpen: boolean;
    moved: number;
    skipped: number;
    results: BulkMoveResultItem[];
  } | null>(null);

  // Saved Views
  const { savedViews, saveView, updateView, deleteView } = useHrEmplocSavedViews();
  const [isSavedViewsModalOpen, setIsSavedViewsModalOpen] = useState(false);

  // Export dropdown state
  const [isExporting, setIsExporting] = useState(false);
  const [isExportMenuOpen, setIsExportMenuOpen] = useState(false);
  const exportDropdownRef = useRef<HTMLDivElement>(null);

  // Notifications
  const [successToast, setSuccessToast] = useState<{ message: string } | null>(null);
  const [errorToast, setErrorToast] = useState<{ message: string } | null>(null);

  const bulkMoveMutation = useBulkMoveToPlantilla();

  // Accounts & Groups lookup query for compact filter dropdowns
  const accountsQuery = useQuery({
    queryKey: ["filter-accounts-list"],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("accounts")
        .select("id, account_name, group_id, groups(group_name)")
        .order("account_name");
      if (error) return [];
      return (data ?? []).map((row) => ({
        id: row.id as string,
        name: row.account_name as string,
        groupId: row.group_id as string | null,
        groupName: Array.isArray(row.groups)
          ? ((row.groups[0] as unknown as Record<string, unknown>)?.group_name as string | null)
          : row.groups && typeof row.groups === "object"
          ? ((row.groups as unknown as Record<string, unknown>).group_name as string | null)
          : null,
      }));
    },
    staleTime: 60_000,
  });

  const accounts = useMemo(() => accountsQuery.data ?? [], [accountsQuery.data]);

  const uniqueGroups = useMemo(() => {
    const map = new Map<string, string>();
    for (const a of accounts) {
      if (a.groupId && a.groupName) {
        map.set(a.groupId, a.groupName);
      }
    }
    return Array.from(map.entries()).map(([id, name]) => ({ id, name }));
  }, [accounts]);

  function updateQueue(nextQueue: HrEmplocQueue) {
    setQueue(nextQueue);
    setPage(1);
    setSelectedId(null);
  }

  function applySearch() {
    setSearch(searchDraft.trim());
    setPage(1);
    setSelectedId(null);
  }

  function clearAllFilters() {
    setSearchDraft("");
    setSearch("");
    setAccountId("");
    setGroupId("");
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

  // Close export dropdown when clicking outside
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (
        exportDropdownRef.current &&
        !exportDropdownRef.current.contains(event.target as Node)
      ) {
        setIsExportMenuOpen(false);
      }
    }
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setIsExportMenuOpen(false);
      }
    }
    if (isExportMenuOpen) {
      document.addEventListener("mousedown", handleClickOutside);
      document.addEventListener("keydown", handleKeyDown);
      return () => {
        document.removeEventListener("mousedown", handleClickOutside);
        document.removeEventListener("keydown", handleKeyDown);
      };
    }
  }, [isExportMenuOpen]);

  async function handleExport(scope: "current_view" | "masterlist") {
    setIsExportMenuOpen(false);
    setIsExporting(true);
    setErrorToast(null);

    try {
      const exportFilters = {
        search: search || undefined,
        accountId: accountId || undefined,
        groupId: groupId || undefined,
      };

      const result = await fetchHrEmplocsForExport(scope, queue, exportFilters);
      downloadCsv(result.csv, result.filename);

      setSuccessToast({
        message: `Successfully exported ${result.rowCount} records to ${result.filename}`,
      });
      setTimeout(() => {
        setSuccessToast((prev) => (prev?.message.includes(result.filename) ? null : prev));
      }, 6000);
    } catch (err) {
      console.error("[hr-emploc export error]", err);
      const message = err instanceof Error ? err.message : "Failed to generate CSV export.";
      setErrorToast({ message: `Export failed: ${message}` });
      setTimeout(() => {
        setErrorToast(null);
      }, 6000);
    } finally {
      setIsExporting(false);
    }
  }

  const currentFilters: HrEmplocFilterState = useMemo(
    () => ({
      queue,
      search,
      accountId,
      groupId,
    }),
    [queue, search, accountId, groupId]
  );

  function handleApplySavedView(view: HrEmplocSavedView) {
    setQueue(view.filters.queue);
    setSearchDraft(view.filters.search || "");
    setSearch(view.filters.search || "");
    setAccountId(view.filters.accountId || "");
    setGroupId(view.filters.groupId || "");
    setPage(1);
    setSelectedId(null);
    setIsSavedViewsModalOpen(false);

    setSuccessToast({
      message: `Applied saved view "${view.name}".`,
    });
    setTimeout(() => {
      setSuccessToast((prev) => (prev?.message.includes(view.name) ? null : prev));
    }, 5000);
  }

  function handleSaveView(name: string, filters: HrEmplocFilterState) {
    saveView(name, filters);
    setSuccessToast({
      message: `Saved view preset "${name}" successfully.`,
    });
    setTimeout(() => {
      setSuccessToast((prev) => (prev?.message.includes(name) ? null : prev));
    }, 5000);
  }

  function handleUpdateView(id: string, name: string, filters: HrEmplocFilterState) {
    updateView(id, name, filters);
    setSuccessToast({
      message: `Updated view preset "${name}" with current filters.`,
    });
    setTimeout(() => {
      setSuccessToast((prev) => (prev?.message.includes(name) ? null : prev));
    }, 5000);
  }

  function handleDeleteView(id: string, name: string) {
    deleteView(id);
    setSuccessToast({
      message: `Deleted view preset "${name}".`,
    });
    setTimeout(() => {
      setSuccessToast((prev) => (prev?.message.includes(name) ? null : prev));
    }, 5000);
  }

  async function handleDownloadAttachment(row: HrEmplocListItem) {
    if (!row.attachmentUrl) return;
    try {
      const url = await getCorrectionAttachmentSignedUrl(row.attachmentUrl);
      window.open(url, "_blank", "noopener,noreferrer");
    } catch (err) {
      console.error("[hr-emploc attachment download error]", err);
      const message = err instanceof Error ? err.message : "Failed to open attachment.";
      setErrorToast({ message: `Attachment error: ${message}` });
    }
  }

  // Group filter parameters for list query
  const listParams = useMemo(
    () => ({
      queue,
      accountId: accountId.trim() || undefined,
      groupId: groupId.trim() || undefined,
      search: search.trim() || undefined,
      page,
      pageSize,
    }),
    [queue, accountId, groupId, search, page, pageSize]
  );

  // Summary query parameters across all tabs
  const summaryParams = useMemo(
    () => ({
      accountId: accountId.trim() || undefined,
      groupId: groupId.trim() || undefined,
      search: search.trim() || undefined,
    }),
    [accountId, groupId, search]
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

  // Tab counters computation with live fetched row parity
  const tabCounts: Record<HrEmplocQueue, number> = useMemo(() => {
    const summary = summaryQuery.data;
    const counts: Record<HrEmplocQueue, number> = {
      pending: summary?.pending ?? 0,
      correction: summary?.correction ?? 0,
      review: summary?.review ?? 0,
      ready: summary?.ready ?? 0,
      deficiency: summary?.correction ?? 0,
      complete: summary?.ready ?? 0,
      deletion_pending: summary?.pendingDeletion ?? 0,
      all: 0,
    };

    // Ensure active tab accurately matches live fetched rows count from listQuery
    if (listQuery.data?.totalCount !== undefined && !listQuery.isLoading) {
      counts[queue] = listQuery.data.totalCount;
    }

    return counts;
  }, [summaryQuery.data, listQuery.data, listQuery.isLoading, queue]);

  const totalMasterlistCount = useMemo(() => {
    const s = summaryQuery.data;
    if (!s) return 0;
    return (s.pending ?? 0) + (s.correction ?? 0) + (s.review ?? 0) + (s.ready ?? 0);
  }, [summaryQuery.data]);

  const isAnyFilterActive = Boolean(searchDraft.trim() || search || accountId || groupId);

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
          onClick: retryQueryReads,
          disabled: summaryQuery.isFetching || listQuery.isFetching,
        }}
      />

      {successToast && (
        <div
          role="status"
          aria-live="polite"
          className="flex items-center justify-between gap-3 rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800 shadow-sm animate-in fade-in slide-in-from-top-2 duration-200"
        >
          <div className="flex items-center gap-2">
            <span className="flex h-6 w-6 items-center justify-center rounded-full bg-emerald-100 text-emerald-700 font-bold text-xs">
              ✓
            </span>
            <span className="font-medium text-xs sm:text-sm">{successToast.message}</span>
          </div>
          <button
            type="button"
            onClick={() => setSuccessToast(null)}
            className="rounded p-1 text-emerald-600 hover:bg-emerald-100 hover:text-emerald-900 transition-colors cursor-pointer"
            aria-label="Dismiss notification"
          >
            ✕
          </button>
        </div>
      )}

      {errorToast && (
        <div
          role="alert"
          aria-live="assertive"
          className="flex items-center justify-between gap-3 rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800 shadow-sm animate-in fade-in slide-in-from-top-2 duration-200"
        >
          <div className="flex items-center gap-2">
            <span className="flex h-6 w-6 items-center justify-center rounded-full bg-red-100 text-red-700 font-bold text-xs">
              ✕
            </span>
            <span className="font-medium text-xs sm:text-sm">{errorToast.message}</span>
          </div>
          <button
            type="button"
            onClick={() => setErrorToast(null)}
            className="rounded p-1 text-red-600 hover:bg-red-100 hover:text-red-900 transition-colors cursor-pointer"
            aria-label="Dismiss error notification"
          >
            ✕
          </button>
        </div>
      )}

      {/* Status Tabs Navigation & Actions (Saved View + Export Data aligned to the right) */}
      <div
        aria-label="HR Emploc queue filter"
        className="flex items-center gap-2 rounded-lg border border-border-subtle bg-surface p-2 shadow-2xs"
      >
        <div
          role="tablist"
          className="flex items-center gap-1.5 overflow-x-auto no-scrollbar scrollbar-none min-w-0"
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

        {/* Right-hand side actions: Saved View & Export Data dropdown */}
        <div className="ml-auto shrink-0 flex items-center gap-2">
          {/* Saved View */}
          <button
            type="button"
            onClick={() => setIsSavedViewsModalOpen(true)}
            aria-label="Open saved views and presets"
            className="h-9 text-xs font-semibold border border-border-subtle bg-surface hover:bg-surface-hover px-3 flex items-center gap-1.5 rounded-lg text-text-primary transition-colors cursor-pointer"
          >
            <FileSearch className="w-3.5 h-3.5 shrink-0 text-text-secondary" />
            <span>Saved View</span>
            {savedViews.length > 0 && (
              <span className="rounded-full bg-brand-50 border border-brand-200 px-1.5 py-0.2 text-[10px] font-semibold text-brand-700">
                {savedViews.length}
              </span>
            )}
          </button>

          {/* Export Data dropdown */}
          <div className="relative" ref={exportDropdownRef}>
            <button
              type="button"
              disabled={isExporting}
              onClick={() => setIsExportMenuOpen((prev) => !prev)}
              aria-expanded={isExportMenuOpen}
              aria-haspopup="menu"
              className="h-9 text-xs font-semibold border border-border-subtle bg-surface hover:bg-surface-hover px-3 flex items-center gap-1.5 rounded-lg text-text-primary transition-colors disabled:opacity-60 disabled:cursor-not-allowed cursor-pointer"
            >
              {isExporting ? (
                <Loader2 className="w-4 h-4 shrink-0 animate-spin text-brand-600" />
              ) : (
                <Download className="w-4 h-4 shrink-0 text-text-secondary" />
              )}
              <span>{isExporting ? "Exporting..." : "Export Data"}</span>
              <ChevronDown
                className={`w-3.5 h-3.5 shrink-0 text-text-muted transition-transform duration-150 ${
                  isExportMenuOpen ? "rotate-180" : ""
                }`}
              />
            </button>

            {isExportMenuOpen && (
              <div
                role="menu"
                aria-label="Export options"
                className="absolute right-0 top-full mt-1.5 w-64 rounded-lg border border-border-subtle bg-surface p-1.5 shadow-lg z-50 animate-in fade-in zoom-in-95 duration-100"
              >
                <button
                  type="button"
                  role="menuitem"
                  onClick={() => handleExport("current_view")}
                  disabled={isExporting}
                  className="w-full flex flex-col items-start px-3 py-2 text-left rounded-md hover:bg-surface-hover transition-colors group cursor-pointer text-text-primary"
                >
                  <div className="flex items-center justify-between w-full">
                    <span className="text-xs font-semibold group-hover:text-brand-700">
                      Export Current View
                    </span>
                    <span className="font-mono text-[11px] font-medium text-text-muted bg-slate-100 border border-slate-200/60 rounded px-1.5 py-0.5">
                      {summaryQuery.isLoading ? "–" : (tabCounts[queue] ?? 0)}
                    </span>
                  </div>
                  <span className="text-[11px] text-text-muted mt-0.5">
                    {activeQueueLabel} queue ({summaryQuery.isLoading ? "–" : (tabCounts[queue] ?? 0)} records)
                  </span>
                </button>

                <div className="my-1 border-t border-border-subtle" />

                <button
                  type="button"
                  role="menuitem"
                  onClick={() => handleExport("masterlist")}
                  disabled={isExporting}
                  className="w-full flex flex-col items-start px-3 py-2 text-left rounded-md hover:bg-surface-hover transition-colors group cursor-pointer text-text-primary"
                >
                  <div className="flex items-center justify-between w-full">
                    <span className="text-xs font-semibold group-hover:text-brand-700">
                      Export Masterlist
                    </span>
                    <span className="font-mono text-[11px] font-medium text-text-muted bg-slate-100 border border-slate-200/60 rounded px-1.5 py-0.5">
                      {summaryQuery.isLoading ? "–" : totalMasterlistCount}
                    </span>
                  </div>
                  <span className="text-[11px] text-text-muted mt-0.5">
                    All queues: Pending to Ready / Transferred
                  </span>
                </button>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Compact Enterprise Filter Toolbar */}
      <form
        onSubmit={(e) => {
          e.preventDefault();
          applySearch();
        }}
        className="flex flex-wrap items-center justify-between gap-2.5 p-3 rounded-lg border border-border-subtle bg-surface"
      >
        <div className="flex flex-1 flex-wrap items-center gap-2.5 min-w-0">
          {/* Search Input */}
          <div className="relative flex-1 min-w-[280px]">
            <Search
              className="pointer-events-none absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-text-muted"
              aria-hidden="true"
            />
            <input
              aria-label="Search HR Emploc records"
              className="h-9 w-full rounded-md border border-border-default bg-surface-muted pl-9 pr-8 text-xs text-text-primary outline-none transition-colors focus:border-brand-500 focus:bg-surface-base disabled:cursor-not-allowed disabled:opacity-75"
              disabled={blocked}
              onChange={(e) => setSearchDraft(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  applySearch();
                }
              }}
              placeholder="Search applicant name, VCode, position, store, HRCO..."
              type="text"
              value={searchDraft}
            />
            {searchDraft && (
              <button
                aria-label="Clear search"
                className="absolute right-2.5 top-1/2 -translate-y-1/2 rounded p-0.5 text-text-muted hover:text-text-primary transition-colors cursor-pointer"
                disabled={blocked}
                onClick={() => {
                  setSearchDraft("");
                  setSearch("");
                  setPage(1);
                  setSelectedId(null);
                }}
                type="button"
              >
                <X className="h-3.5 w-3.5" aria-hidden="true" />
              </button>
            )}
          </div>

          {/* Group Selector */}
          <select
            aria-label="Group filter"
            className="h-9 min-w-[140px] rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-primary outline-none focus:border-brand-500 hover:border-slate-300 transition-colors cursor-pointer disabled:cursor-not-allowed disabled:opacity-50"
            disabled={blocked}
            onChange={(e) => {
              setGroupId(e.target.value);
              setPage(1);
              setSelectedId(null);
            }}
            value={groupId}
          >
            <option value="">All groups</option>
            {uniqueGroups.map((g) => (
              <option key={g.id} value={g.id}>
                {g.name}
              </option>
            ))}
          </select>

          {/* Account Selector */}
          <select
            aria-label="Account filter"
            className="h-9 min-w-[140px] rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-primary outline-none focus:border-brand-500 hover:border-slate-300 transition-colors cursor-pointer disabled:cursor-not-allowed disabled:opacity-50"
            disabled={blocked}
            onChange={(e) => {
              setAccountId(e.target.value);
              setPage(1);
              setSelectedId(null);
            }}
            value={accountId}
          >
            <option value="">All accounts</option>
            {(groupId
              ? accounts.filter((a) => a.groupId === groupId)
              : accounts
            ).map((a) => (
              <option key={a.id} value={a.id}>
                {a.name}
              </option>
            ))}
          </select>
        </div>

        {/* Action Endcap */}
        <div className="flex items-center gap-2 shrink-0">
          {queue === "ready" && (
            <button
              className="inline-flex h-9 items-center gap-1.5 rounded-md bg-emerald-700 px-3 text-xs font-semibold text-white shadow-xs hover:bg-emerald-800 transition disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
              disabled={bulkMoveMutation.isPending || rows.length === 0}
              onClick={handleBulkMove}
              type="button"
            >
              {bulkMoveMutation.isPending ? (
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
              ) : (
                <Send className="h-3.5 w-3.5" aria-hidden="true" />
              )}
              <span>{bulkMoveMutation.isPending ? "Deploying..." : "Bulk Deploy Ready"}</span>
            </button>
          )}

          {isAnyFilterActive && (
            <button
              aria-label="Clear all filters"
              className="inline-flex h-9 items-center gap-1.5 rounded-md px-2.5 text-xs font-medium text-text-muted hover:text-text-primary hover:bg-surface-hover transition-colors cursor-pointer"
              disabled={blocked}
              onClick={clearAllFilters}
              type="button"
            >
              <RotateCcw className="h-3.5 w-3.5" aria-hidden="true" />
              <span>Clear All</span>
            </button>
          )}
        </div>
      </form>

      {/* Roster Grid Component with Restructured Columns & Row Actions */}
      <HrEmplocTable
        errorKind={listErrorKind}
        isLoading={listQuery.isLoading}
        onPageChange={updatePage}
        onPageSizeChange={(newPageSize) => {
          setPageSize(newPageSize);
          setPage(1);
          setSelectedId(null);
        }}
        onRetry={retryQueryReads}
        onSelect={selectRow}
        onAddEmploc={(row) => setAssignTarget(row)}
        onForCorrection={(row) => setCorrectionTarget(row)}
        onAssignEmployeeNo={(row) => setAssignTarget(row)}
        onMoveToPlantilla={(row) => setDeployTarget(row)}
        onUploadAttachment={(row) => setUploadTarget(row)}
        onSubmitCorrection={(row) => setSubmitCorrectionTarget(row)}
        onApproveReview={(row) => setApproveReviewTarget(row)}
        onRevertReview={(row) => setRevertReviewTarget(row)}
        onDownloadAttachment={handleDownloadAttachment}
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

      {/* Add Emploc / Placement Onboarding Modal */}
      {assignTarget && (
        <AssignEmployeeNoModal
          hrEmplocId={assignTarget.id}
          candidateName={assignTarget.applicantName}
          vcode={assignTarget.vcode}
          currentEmployeeNo={assignTarget.employeeNo}
          onClose={() => setAssignTarget(null)}
          onSuccess={() => {
            setAssignTarget(null);
            setSuccessToast({
              message: `Placement onboarding updated for ${assignTarget.applicantName}.`,
            });
            retryQueryReads();
          }}
        />
      )}

      {/* Move to Plantilla Modal */}
      {deployTarget && (
        <DeployToPlantillaModal
          hrEmplocId={deployTarget.id}
          candidateName={deployTarget.applicantName}
          vcode={deployTarget.vcode}
          positionTitle={deployTarget.positionTitle}
          storeName={deployTarget.storeName}
          accountName={deployTarget.accountName}
          employeeNo={deployTarget.employeeNo}
          onClose={() => setDeployTarget(null)}
          onSuccess={() => {
            setDeployTarget(null);
            setSuccessToast({
              message: `Successfully deployed ${deployTarget.applicantName} to Plantilla.`,
            });
            retryQueryReads();
          }}
        />
      )}

      {/* For Correction Modal (Tag Deficiency) */}
      {correctionTarget && (
        <TagDeficiencyModal
          isOpen={true}
          hrEmplocId={correctionTarget.id}
          applicantName={correctionTarget.applicantName}
          vcode={correctionTarget.vcode}
          onClose={() => setCorrectionTarget(null)}
          onSuccess={() => {
            setCorrectionTarget(null);
            setSuccessToast({
              message: `Record ${correctionTarget.vcode} returned for correction successfully.`,
            });
            retryQueryReads();
          }}
        />
      )}

      {/* Upload Compliance Attachment Modal */}
      {uploadTarget && (
        <UploadAttachmentModal
          isOpen={true}
          row={uploadTarget}
          onClose={() => setUploadTarget(null)}
          onSuccess={(msg) => {
            setUploadTarget(null);
            setSuccessToast({
              message: msg || `Compliance attachment uploaded for ${uploadTarget.applicantName}.`,
            });
            retryQueryReads();
          }}
        />
      )}

      {/* Submit Correction Modal (Transition to Review) */}
      {submitCorrectionTarget && (
        <SubmitCorrectionModal
          isOpen={true}
          row={submitCorrectionTarget}
          canUploadAttachments={!isBenefitsOnlyCorrection(submitCorrectionTarget.deficiencyIssues)}
          onClose={() => setSubmitCorrectionTarget(null)}
          onSuccess={(msg) => {
            setSubmitCorrectionTarget(null);
            setSuccessToast({
              message: msg || `Correction submitted to Review for ${submitCorrectionTarget.applicantName}.`,
            });
            retryQueryReads();
          }}
        />
      )}

      {/* Approve Review Modal (Transition to Ready) */}
      {approveReviewTarget && (
        <ReviewApproveModal
          isOpen={true}
          row={approveReviewTarget}
          onClose={() => setApproveReviewTarget(null)}
          onSuccess={(msg) => {
            setApproveReviewTarget(null);
            setSuccessToast({
              message: msg || `Review approved for ${approveReviewTarget.applicantName}. Record is now Ready.`,
            });
            retryQueryReads();
          }}
        />
      )}

      {/* Revert Review Modal (Transition back to Correction) */}
      {revertReviewTarget && (
        <ReviewRevertModal
          isOpen={true}
          row={revertReviewTarget}
          onClose={() => setRevertReviewTarget(null)}
          onSuccess={(msg) => {
            setRevertReviewTarget(null);
            setSuccessToast({
              message: msg || `Review reverted to Correction for ${revertReviewTarget.applicantName}.`,
            });
            retryQueryReads();
          }}
        />
      )}

      {/* Saved Views Modal */}
      <HrEmplocSavedViewsModal
        isOpen={isSavedViewsModalOpen}
        onClose={() => setIsSavedViewsModalOpen(false)}
        currentFilters={currentFilters}
        accounts={accounts}
        groups={uniqueGroups}
        savedViews={savedViews}
        onSaveView={handleSaveView}
        onUpdateView={handleUpdateView}
        onDeleteView={handleDeleteView}
        onApplyView={handleApplySavedView}
      />

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
                className="rounded-md bg-brand-600 px-4 py-1.5 text-xs font-semibold text-white hover:bg-brand-700 transition cursor-pointer"
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
