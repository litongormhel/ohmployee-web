"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import {
  ArrowRight,
  Building2,
  RefreshCw,
  Search,
  Users,
} from "lucide-react";
import { DataState } from "@/components/shared/DataState";
import { HeadcountAmendmentApprovalCard } from "@/components/approvals/HeadcountAmendmentApprovalCard";
import { HeadcountStandardApprovalCard } from "@/components/approvals/HeadcountStandardApprovalCard";
import { HrEmplocDeletionReviewCard } from "@/components/approvals/HrEmplocDeletionReviewCard";
import {
  REQUEST_CATEGORIES,
  usePendingHeadcountRequests,
  type RequestCategoryCounts,
  type RequestCategoryKey,
} from "@/lib/queries/requests";
import { useEmplocDeletionRequests } from "@/lib/queries/hr_emploc";

interface ActiveQueueReviewPaneProps {
  selectedCategory: RequestCategoryKey;
  onSelectCategory: (key: RequestCategoryKey) => void;
  counts: RequestCategoryCounts;
}

const CATEGORY_LINKS: Partial<Record<RequestCategoryKey, { href: string; label: string }>> = {
  coverage: { href: "/cencom", label: "Open CENCOM Module" },
  vacancy_closures: { href: "/vacancy", label: "Open Vacancy Module" },
  deactivations: { href: "/plantilla", label: "Open Plantilla Module" },
};

export function ActiveQueueReviewPane({
  selectedCategory,
  onSelectCategory,
  counts,
}: ActiveQueueReviewPaneProps) {
  const [filterType, setFilterType] = useState<"all" | "amendment" | "standard">("all");
  const [searchQuery, setSearchQuery] = useState("");
  const [deletionSearchQuery, setDeletionSearchQuery] = useState("");

  const {
    data: requests = [],
    isLoading,
    isError,
    refetch,
    isRefetching,
  } = usePendingHeadcountRequests();

  const {
    data: deletionRequests = [],
    isLoading: isDeletionLoading,
    isError: isDeletionError,
    refetch: refetchDeletions,
    isRefetching: isDeletionRefetching,
  } = useEmplocDeletionRequests();

  const currentCategoryConfig = useMemo(() => {
    return (
      REQUEST_CATEGORIES.find((c) => c.key === selectedCategory) ??
      REQUEST_CATEGORIES[1] // Default to headcount
    );
  }, [selectedCategory]);

  const filteredRequests = useMemo(() => {
    return requests.filter((req) => {
      // Type filter
      if (filterType === "amendment" && !req.isQuotaAmendment) return false;
      if (filterType === "standard" && req.isQuotaAmendment) return false;

      // Search query
      if (searchQuery.trim()) {
        const q = searchQuery.toLowerCase();
        const matchesStore = req.storeName?.toLowerCase().includes(q);
        const matchesVcode = req.targetVcode?.toLowerCase().includes(q);
        const matchesPosition = req.positionName?.toLowerCase().includes(q);
        const matchesAccount = req.accountName?.toLowerCase().includes(q);
        const matchesRequester = req.requestedByName?.toLowerCase().includes(q);

        return (
          matchesStore ||
          matchesVcode ||
          matchesPosition ||
          matchesAccount ||
          matchesRequester
        );
      }

      return true;
    });
  }, [requests, filterType, searchQuery]);

  const filteredDeletionRequests = useMemo(() => {
    if (!deletionSearchQuery.trim()) return deletionRequests;
    const q = deletionSearchQuery.toLowerCase();
    return deletionRequests.filter(
      (req) =>
        req.applicantName.toLowerCase().includes(q) ||
        req.vcode.toLowerCase().includes(q) ||
        req.storeName?.toLowerCase().includes(q) ||
        req.positionTitle?.toLowerCase().includes(q) ||
        req.requestedByName?.toLowerCase().includes(q) ||
        req.employeeNo?.toLowerCase().includes(q)
    );
  }, [deletionRequests, deletionSearchQuery]);

  const quotaCount = useMemo(
    () => requests.filter((r) => r.isQuotaAmendment).length,
    [requests]
  );
  const standardCount = useMemo(
    () => requests.filter((r) => !r.isQuotaAmendment).length,
    [requests]
  );

  // ── HR Emploc Deletions Queue ────────────────────────────────────────────
  if (selectedCategory === "hr_emploc_deletions") {
    return (
      <div className="flex h-full flex-col">
        {/* Pane Toolbar */}
        <div className="border-b border-border-default pb-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-semibold text-text-primary">
                  HR Emploc Deletion Queue
                </h2>
                <span className="rounded-full bg-amber-100 px-2.5 py-0.5 font-mono text-xs font-semibold text-amber-800">
                  {deletionRequests.length} pending
                </span>
              </div>
              <p className="mt-0.5 text-xs text-text-secondary">
                Review employee locator Backout and Duplicate Record deletion requests awaiting administrative approval.
              </p>
            </div>

            <button
              type="button"
              onClick={() => refetchDeletions()}
              disabled={isDeletionRefetching || isDeletionLoading}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${isDeletionRefetching ? "animate-spin text-brand-600" : ""}`}
              />
              <span>Refresh</span>
            </button>
          </div>

          {/* Search */}
          <div className="mt-4">
            <div className="relative min-w-[240px] max-w-sm">
              <Search className="pointer-events-none absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
              <input
                type="text"
                placeholder="Search employee, VCode, store..."
                value={deletionSearchQuery}
                onChange={(e) => setDeletionSearchQuery(e.target.value)}
                className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
              />
            </div>
          </div>
        </div>

        {/* Requests List Area */}
        <div className="mt-4 flex-1 space-y-4">
          {isDeletionLoading ? (
            <DataState
              kind="loading"
              title="Loading Deletion Requests"
              description="Fetching pending HR Emploc deletion requests..."
            />
          ) : isDeletionError ? (
            <DataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching pending deletion requests."
              onRetry={() => refetchDeletions()}
            />
          ) : filteredDeletionRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                deletionSearchQuery
                  ? "No Matching Requests"
                  : "No Pending Deletion Requests"
              }
              description={
                deletionSearchQuery
                  ? `No requests match "${deletionSearchQuery}". Clear your search to see all items.`
                  : "All HR Emploc deletion requests have been reviewed and processed."
              }
            />
          ) : (
            <div className="space-y-4">
              {filteredDeletionRequests.map((req) => (
                <HrEmplocDeletionReviewCard key={req.id} request={req} />
              ))}
            </div>
          )}
        </div>
      </div>
    );
  }

  // If Headcount queue is selected
  if (selectedCategory === "headcount") {
    return (
      <div className="flex h-full flex-col">
        {/* Pane Toolbar */}
        <div className="border-b border-border-default pb-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-semibold text-text-primary">
                  Headcount Approvals Queue
                </h2>
                <span className="rounded-full bg-brand-100 px-2.5 py-0.5 font-mono text-xs font-semibold text-brand-800">
                  {requests.length} pending
                </span>
              </div>
              <p className="mt-0.5 text-xs text-text-secondary">
                Review operational quota amendments and additional capacity requests awaiting administrative action.
              </p>
            </div>

            <button
              type="button"
              onClick={() => refetch()}
              disabled={isRefetching || isLoading}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${isRefetching ? "animate-spin text-brand-600" : ""}`}
              />
              <span>Refresh</span>
            </button>
          </div>

          {/* Filters & Search */}
          <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
            {/* Filter Tabs */}
            <div className="flex items-center gap-1 rounded-lg border border-border-default bg-slate-100/80 p-1 text-xs">
              <button
                type="button"
                onClick={() => setFilterType("all")}
                className={`rounded-md px-3 py-1 font-medium transition ${
                  filterType === "all"
                    ? "bg-white text-text-primary shadow-2xs font-semibold"
                    : "text-text-secondary hover:text-text-primary"
                }`}
              >
                All ({requests.length})
              </button>
              <button
                type="button"
                onClick={() => setFilterType("amendment")}
                className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                  filterType === "amendment"
                    ? "bg-white text-text-primary shadow-2xs font-semibold"
                    : "text-text-secondary hover:text-text-primary"
                }`}
              >
                <span>Quota Amendments</span>
                {quotaCount > 0 && (
                  <span className="rounded-full bg-purple-100 px-1.5 text-[10px] font-mono font-semibold text-purple-700">
                    {quotaCount}
                  </span>
                )}
              </button>
              <button
                type="button"
                onClick={() => setFilterType("standard")}
                className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                  filterType === "standard"
                    ? "bg-white text-text-primary shadow-2xs font-semibold"
                    : "text-text-secondary hover:text-text-primary"
                }`}
              >
                <span>Standard Headcount</span>
                {standardCount > 0 && (
                  <span className="rounded-full bg-blue-100 px-1.5 text-[10px] font-mono font-semibold text-blue-700">
                    {standardCount}
                  </span>
                )}
              </button>
            </div>

            {/* Search Input */}
            <div className="relative min-w-[240px] flex-1 max-w-sm">
              <Search className="pointer-events-none absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
              <input
                type="text"
                placeholder="Search store, VCode, position..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
              />
            </div>
          </div>
        </div>

        {/* Requests List Area */}
        <div className="mt-4 flex-1 space-y-4">
          {isLoading ? (
            <DataState
              kind="loading"
              title="Loading Headcount Requests"
              description="Fetching live pending quota amendments and headcount requests..."
            />
          ) : isError ? (
            <DataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching pending headcount requests."
              onRetry={() => refetch()}
            />
          ) : filteredRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                searchQuery
                  ? "No Matching Requests"
                  : filterType === "amendment"
                    ? "No Pending Quota Amendments"
                    : "No Pending Headcount Requests"
              }
              description={
                searchQuery
                  ? `No requests match "${searchQuery}". Clear your search query to see all items.`
                  : "All headcount requests and quota amendments have been reviewed and processed."
              }
            />
          ) : (
            <div className="space-y-4">
              {filteredRequests.map((req) =>
                req.isQuotaAmendment ? (
                  <HeadcountAmendmentApprovalCard key={req.id} request={req} />
                ) : (
                  <HeadcountStandardApprovalCard key={req.id} request={req} />
                )
              )}
            </div>
          )}
        </div>
      </div>
    );
  }

  // Non-Headcount Category View
  const count = counts[selectedCategory] ?? 0;
  const linkInfo = CATEGORY_LINKS[selectedCategory];

  return (
    <div className="flex h-full flex-col">
      {/* Header */}
      <div className="border-b border-border-default pb-4">
        <div className="flex items-center gap-2">
          <h2 className="text-lg font-semibold text-text-primary">
            {currentCategoryConfig.label}
          </h2>
          {count > 0 && (
            <span className="rounded-full bg-blue-100 px-2.5 py-0.5 font-mono text-xs font-semibold text-blue-800">
              {count} pending
            </span>
          )}
        </div>
        <p className="mt-0.5 text-xs text-text-secondary">
          {currentCategoryConfig.description}
        </p>
      </div>

      {/* Info Card */}
      <div className="mt-6 rounded-xl border border-border-default bg-surface-base p-8 text-center shadow-xs">
        <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-slate-100 text-slate-600">
          <Building2 className="h-6 w-6" />
        </div>

        <h3 className="mt-4 text-base font-semibold text-text-primary">
          {currentCategoryConfig.label} Queue
        </h3>

        <p className="mx-auto mt-2 max-w-md text-xs leading-relaxed text-text-secondary">
          There {count === 1 ? "is" : "are"}{" "}
          <span className="font-semibold font-mono text-text-primary">{count}</span>{" "}
          pending request{count !== 1 ? "s" : ""} registered in the database for{" "}
          <span className="font-semibold text-text-primary">{currentCategoryConfig.label}</span>.
          Operational review is routed through the dedicated module pipeline and mobile workflow.
        </p>

        <div className="mt-6 flex flex-wrap items-center justify-center gap-3">
          {linkInfo && (
            <Link
              href={linkInfo.href}
              className="inline-flex h-9 items-center gap-1.5 rounded-md border border-brand-300 bg-brand-50 px-4 text-xs font-semibold text-brand-700 shadow-2xs hover:bg-brand-100 transition"
            >
              <span>{linkInfo.label}</span>
              <ArrowRight className="h-3.5 w-3.5" />
            </Link>
          )}

          <button
            type="button"
            onClick={() => onSelectCategory("headcount")}
            className="inline-flex h-9 items-center gap-1.5 rounded-md border border-border-default bg-white px-4 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover transition"
          >
            <Users className="h-3.5 w-3.5" />
            <span>Switch to Headcount Approvals Queue</span>
          </button>
        </div>
      </div>
    </div>
  );
}
