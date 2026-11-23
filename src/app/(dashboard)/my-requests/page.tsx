"use client";

import { Suspense, useMemo, useState } from "react";
import {
  AlertCircle,
  Building2,
  Calendar,
  CheckCircle2,
  Clock,
  Eye,
  FileText,
  Filter,
  Layers,
  LayoutGrid,
  List,
  RefreshCw,
  Search,
  Send,
  User,
  Users,
  XCircle,
} from "lucide-react";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { MetricCard } from "@/components/shared/MetricCard";
import { DataState } from "@/components/shared/DataState";
import { TablePagination } from "@/components/shared/TablePagination";
import { useCurrentUser } from "@/lib/auth";
import {
  calculateMyRequestsCounts,
  MyRequestCategoryType,
  MyRequestItem,
  MyRequestStatus,
  useMyRequests,
} from "@/lib/queries/my_requests";
import { MyRequestsDataTable } from "@/components/my-requests/MyRequestsDataTable";
import { MyRequestDetailModal } from "@/components/my-requests/MyRequestDetailModal";

type StatusTab = "all" | "pending" | "approved" | "rejected";
type DisplayView = "table" | "cards";

function formatRelativeTime(dateString: string): string {
  try {
    const date = new Date(dateString);
    if (isNaN(date.getTime())) return "—";
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffSec = Math.floor(diffMs / 1000);
    const diffMin = Math.floor(diffSec / 60);
    const diffHours = Math.floor(diffMin / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffDays > 30) {
      return date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
    }
    if (diffDays > 0) return `${diffDays}d ago`;
    if (diffHours > 0) return `${diffHours}h ago`;
    if (diffMin > 0) return `${diffMin}m ago`;
    return "just now";
  } catch {
    return "—";
  }
}

function formatFullDate(dateString?: string | null): string {
  if (!dateString) return "—";
  try {
    const d = new Date(dateString);
    if (isNaN(d.getTime())) return "—";
    return d.toLocaleString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
      hour12: true,
    });
  } catch {
    return dateString;
  }
}

function getCategoryBadgeColor(category: MyRequestItem["category"]): string {
  switch (category) {
    case "headcount":
      return "bg-purple-50 text-purple-700 border-purple-200 dark:bg-purple-950/40 dark:text-purple-300 dark:border-purple-800";
    case "new_stores":
      return "bg-blue-50 text-blue-700 border-blue-200 dark:bg-blue-950/40 dark:text-blue-300 dark:border-blue-800";
    case "vacancy_closures":
      return "bg-amber-50 text-amber-700 border-amber-200 dark:bg-amber-950/40 dark:text-amber-300 dark:border-amber-800";
    case "deactivations":
      return "bg-rose-50 text-rose-700 border-rose-200 dark:bg-rose-950/40 dark:text-rose-300 dark:border-rose-800";
    case "applicant_movements":
      return "bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-950/40 dark:text-emerald-300 dark:border-emerald-800";
    case "coverage":
      return "bg-cyan-50 text-cyan-700 border-cyan-200 dark:bg-cyan-950/40 dark:text-cyan-300 dark:border-cyan-800";
    default:
      return "bg-slate-50 text-slate-700 border-slate-200 dark:bg-slate-800 dark:text-slate-300 dark:border-slate-700";
  }
}

function getStatusBadge(status: MyRequestStatus) {
  switch (status) {
    case "pending":
      return (
        <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-amber-500/10 text-amber-600 dark:text-amber-400 border border-amber-500/20">
          <Clock size={12} className="animate-spin text-amber-500" />
          Pending Review
        </span>
      );
    case "approved":
      return (
        <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20">
          <CheckCircle2 size={12} />
          Approved
        </span>
      );
    case "rejected":
      return (
        <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-rose-500/10 text-rose-600 dark:text-rose-400 border border-rose-500/20">
          <XCircle size={12} />
          Rejected
        </span>
      );
    case "cancelled":
      return (
        <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-slate-500/10 text-slate-600 dark:text-slate-400 border border-slate-500/20">
          <AlertCircle size={12} />
          Cancelled
        </span>
      );
  }
}

function MyRequestsContent() {
  const currentUser = useCurrentUser();
  const { data: requests = [], isLoading, isRefetching, refetch, error } = useMyRequests(currentUser);

  const [displayView, setDisplayView] = useState<DisplayView>("table");
  const [activeTab, setActiveTab] = useState<StatusTab>("all");
  const [selectedCategory, setSelectedCategory] = useState<MyRequestCategoryType>("all");
  const [searchQuery, setSearchQuery] = useState("");
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(10);

  // Detail Modal State
  const [selectedDetailRequest, setSelectedDetailRequest] = useState<MyRequestItem | null>(null);
  const [isDetailModalOpen, setIsDetailModalOpen] = useState(false);

  const counts = useMemo(() => calculateMyRequestsCounts(requests), [requests]);

  const filteredRequests = useMemo(() => {
    return requests.filter((item) => {
      // 1. Status Filter
      if (activeTab === "pending" && item.status !== "pending") return false;
      if (activeTab === "approved" && item.status !== "approved") return false;
      if (activeTab === "rejected" && item.status !== "rejected" && item.status !== "cancelled") return false;

      // 2. Category Filter
      if (selectedCategory !== "all" && item.category !== selectedCategory) return false;

      // 3. Search Query
      if (searchQuery.trim()) {
        const q = searchQuery.toLowerCase().trim();
        const matchTitle = item.title.toLowerCase().includes(q);
        const matchSubtitle = item.subtitle.toLowerCase().includes(q);
        const matchStore = item.details.storeName?.toLowerCase().includes(q);
        const matchAccount = item.details.accountName?.toLowerCase().includes(q);
        const matchPos = item.details.positionName?.toLowerCase().includes(q);
        const matchEmp = item.details.employeeName?.toLowerCase().includes(q);
        const matchVcode = item.details.vcode?.toLowerCase().includes(q);
        const matchReason = item.details.reason?.toLowerCase().includes(q);
        const matchRemarks = item.reviewerRemarks?.toLowerCase().includes(q);

        return (
          matchTitle ||
          matchSubtitle ||
          matchStore ||
          matchAccount ||
          matchPos ||
          matchEmp ||
          matchVcode ||
          matchReason ||
          matchRemarks
        );
      }

      return true;
    });
  }, [requests, activeTab, selectedCategory, searchQuery]);

  const totalCount = filteredRequests.length;
  const pageCount = Math.max(1, Math.ceil(totalCount / pageSize));
  const safePage = Math.min(page, pageCount);

  const paginatedRequests = useMemo(() => {
    const start = (safePage - 1) * pageSize;
    return filteredRequests.slice(start, start + pageSize);
  }, [filteredRequests, safePage, pageSize]);

  const handleOpenDetails = (item: MyRequestItem) => {
    setSelectedDetailRequest(item);
    setIsDetailModalOpen(true);
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <AdminPageHeader
        categoryTag="Personnel & Operations"
        moduleName="My Requests"
        title="My Requests"
        subtitle="Track status, approval milestones, and reviewer remarks for all operational requests you have submitted."
        actionSlot={
          <button
            type="button"
            onClick={() => refetch()}
            disabled={isLoading || isRefetching}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg border border-[var(--line)] bg-[var(--card)] hover:bg-[var(--soft)] text-[var(--text)] transition cursor-pointer disabled:opacity-50"
          >
            <RefreshCw size={13} className={isRefetching ? "animate-spin" : ""} />
            <span>Refresh</span>
          </button>
        }
      />

      {/* KPI Metrics */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <MetricCard
          label="Total Submitted"
          value={counts.total}
          helperText="Lifetime requests"
          icon={Send}
        />
        <MetricCard
          label="Pending Review"
          value={counts.pending}
          helperText="Awaiting approvers"
          icon={Clock}
          variant="warning"
        />
        <MetricCard
          label="Approved"
          value={counts.approved}
          helperText="Successfully cleared"
          icon={CheckCircle2}
          variant="positive"
        />
        <MetricCard
          label="Rejected / Closed"
          value={counts.rejected}
          helperText="Declined or cancelled"
          icon={XCircle}
          variant="danger"
        />
      </div>

      {/* Filter Toolbar & View Switcher */}
      <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4 p-4 rounded-xl border border-[var(--line)] bg-[var(--card)]">
        {/* Status Segmented Tabs */}
        <div className="flex items-center gap-1 bg-[var(--soft)] p-1 rounded-lg border border-[var(--line)] overflow-x-auto">
          <button
            type="button"
            onClick={() => {
              setActiveTab("all");
              setPage(1);
            }}
            className={`px-3 py-1.5 text-xs font-medium rounded-md transition whitespace-nowrap cursor-pointer ${
              activeTab === "all"
                ? "bg-[var(--card)] text-[var(--text)] font-semibold shadow-xs"
                : "text-[var(--muted)] hover:text-[var(--text)]"
            }`}
          >
            All ({counts.total})
          </button>
          <button
            type="button"
            onClick={() => {
              setActiveTab("pending");
              setPage(1);
            }}
            className={`px-3 py-1.5 text-xs font-medium rounded-md transition whitespace-nowrap cursor-pointer ${
              activeTab === "pending"
                ? "bg-[var(--card)] text-amber-600 dark:text-amber-400 font-semibold shadow-xs"
                : "text-[var(--muted)] hover:text-[var(--text)]"
            }`}
          >
            Pending ({counts.pending})
          </button>
          <button
            type="button"
            onClick={() => {
              setActiveTab("approved");
              setPage(1);
            }}
            className={`px-3 py-1.5 text-xs font-medium rounded-md transition whitespace-nowrap cursor-pointer ${
              activeTab === "approved"
                ? "bg-[var(--card)] text-emerald-600 dark:text-emerald-400 font-semibold shadow-xs"
                : "text-[var(--muted)] hover:text-[var(--text)]"
            }`}
          >
            Approved ({counts.approved})
          </button>
          <button
            type="button"
            onClick={() => {
              setActiveTab("rejected");
              setPage(1);
            }}
            className={`px-3 py-1.5 text-xs font-medium rounded-md transition whitespace-nowrap cursor-pointer ${
              activeTab === "rejected"
                ? "bg-[var(--card)] text-rose-600 dark:text-rose-400 font-semibold shadow-xs"
                : "text-[var(--muted)] hover:text-[var(--text)]"
            }`}
          >
            Rejected ({counts.rejected})
          </button>
        </div>

        {/* Right Search, Category Dropdown & View Mode Switcher */}
        <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-2.5">
          {/* View Mode Switcher (Table default vs Cards) */}
          <div className="inline-flex h-8 items-center rounded-lg border border-[var(--line)] bg-[var(--soft)] p-0.5 shrink-0">
            <button
              type="button"
              onClick={() => setDisplayView("table")}
              aria-label="Table View"
              title="Table View (Easy Read)"
              className={`inline-flex h-full items-center gap-1.5 rounded-md px-2.5 text-xs font-semibold transition-colors cursor-pointer ${
                displayView === "table"
                  ? "bg-[var(--card)] text-[var(--text)] shadow-xs"
                  : "text-[var(--muted)] hover:text-[var(--text)]"
              }`}
            >
              <List className="h-3.5 w-3.5 text-brand-500" />
              <span className="inline">Table</span>
            </button>
            <button
              type="button"
              onClick={() => setDisplayView("cards")}
              aria-label="Cards View"
              title="Cards View"
              className={`inline-flex h-full items-center gap-1.5 rounded-md px-2.5 text-xs font-semibold transition-colors cursor-pointer ${
                displayView === "cards"
                  ? "bg-[var(--card)] text-[var(--text)] shadow-xs"
                  : "text-[var(--muted)] hover:text-[var(--text)]"
              }`}
            >
              <LayoutGrid className="h-3.5 w-3.5" />
              <span className="inline">Cards</span>
            </button>
          </div>

          {/* Category Dropdown */}
          <div className="relative">
            <select
              value={selectedCategory}
              onChange={(e) => {
                setSelectedCategory(e.target.value as MyRequestCategoryType);
                setPage(1);
              }}
              className="w-full sm:w-auto appearance-none bg-[var(--soft)] border border-[var(--line)] rounded-lg px-3 py-1.5 pr-8 text-xs font-medium text-[var(--text)] focus:outline-hidden focus:ring-2 focus:ring-brand-500 cursor-pointer"
            >
              <option value="all">All Request Types</option>
              <option value="headcount">Headcount Requests</option>
              <option value="new_stores">New Store Requests</option>
              <option value="vacancy_closures">Vacancy Closures</option>
              <option value="deactivations">Employee Deactivations</option>
              <option value="applicant_movements">Applicant Movements</option>
              <option value="coverage">Coverage Groups</option>
            </select>
            <Filter size={12} className="absolute right-2.5 top-2.5 text-[var(--muted)] pointer-events-none" />
          </div>

          {/* Search Input */}
          <div className="relative min-w-[200px]">
            <input
              type="text"
              placeholder="Search my requests…"
              value={searchQuery}
              onChange={(e) => {
                setSearchQuery(e.target.value);
                setPage(1);
              }}
              className="w-full bg-[var(--soft)] border border-[var(--line)] rounded-lg pl-8 pr-3 py-1.5 text-xs text-[var(--text)] placeholder:text-[var(--muted)] focus:outline-hidden focus:ring-2 focus:ring-brand-500"
            />
            <Search size={13} className="absolute left-2.5 top-2.5 text-[var(--muted)]" />
          </div>
        </div>
      </div>

      {/* Main Request Content */}
      {isLoading ? (
        <div className="space-y-3">
          {[1, 2, 3, 4, 5].map((i) => (
            <div
              key={i}
              className="h-14 rounded-xl border border-[var(--line)] bg-[var(--card)] animate-pulse"
            />
          ))}
        </div>
      ) : error ? (
        <DataState
          kind="error"
          title="Failed to load your requests"
          description={error instanceof Error ? error.message : "An error occurred while loading submitted requests."}
          onRetry={() => refetch()}
        />
      ) : filteredRequests.length === 0 ? (
        <DataState
          kind="empty"
          title="No requests found"
          description={
            searchQuery || selectedCategory !== "all" || activeTab !== "all"
              ? "No requests match your selected filters. Try clearing your search or status selection."
              : "You haven't submitted any operational requests yet. Requests you submit for headcount, new stores, vacancy closures, or deactivations will automatically appear here."
          }
          onRetry={searchQuery || selectedCategory !== "all" || activeTab !== "all" ? () => {
            setActiveTab("all");
            setSelectedCategory("all");
            setSearchQuery("");
            setPage(1);
          } : undefined}
        />
      ) : (
        <div className="space-y-4">
          {/* Table View (Default & High Readability) */}
          {displayView === "table" ? (
            <MyRequestsDataTable
              requests={paginatedRequests}
              onViewDetails={handleOpenDetails}
            />
          ) : (
            /* Cards View (Alternative) */
            <div className="space-y-3">
              {paginatedRequests.map((item) => (
                <div
                  key={item.id}
                  onClick={() => handleOpenDetails(item)}
                  className="p-5 rounded-xl border border-[var(--line)] bg-[var(--card)] hover:border-[var(--line-strong)] transition shadow-2xs space-y-3.5 cursor-pointer"
                >
                  {/* Card Header */}
                  <div className="flex flex-wrap items-center justify-between gap-2.5">
                    <div className="flex items-center gap-2">
                      <span
                        className={`inline-flex items-center px-2 py-0.5 rounded-md text-[11px] font-semibold border ${getCategoryBadgeColor(
                          item.category
                        )}`}
                      >
                        {item.categoryLabel}
                      </span>
                      <span className="text-xs text-[var(--muted)]">·</span>
                      <span className="text-xs font-mono text-[var(--muted)]">
                        {formatRelativeTime(item.createdAt)}
                      </span>
                    </div>
                    <div className="flex items-center gap-2">
                      {getStatusBadge(item.status)}
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          handleOpenDetails(item);
                        }}
                        className="inline-flex items-center gap-1 px-2 py-1 text-2xs font-medium rounded-md border border-[var(--line)] bg-[var(--soft)] hover:bg-[var(--card)] text-[var(--text)] transition cursor-pointer"
                      >
                        <Eye size={11} className="text-brand-500" />
                        <span>Details</span>
                      </button>
                    </div>
                  </div>

                  {/* Title & Subtitle */}
                  <div>
                    <h3 className="text-sm font-semibold text-[var(--text)] leading-snug">
                      {item.title}
                    </h3>
                    <p className="text-xs text-[var(--muted)] mt-0.5">
                      {item.subtitle}
                    </p>
                  </div>

                  {/* Key Details Pill Strip */}
                  <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 text-xs text-[var(--muted)] bg-[var(--soft)]/50 p-2.5 rounded-lg border border-[var(--line)]">
                    {item.details.storeName && (
                      <span className="flex items-center gap-1.5">
                        <Building2 size={12} className="text-brand-500" />
                        <span>Store: <strong className="text-[var(--text)] font-medium">{item.details.storeName}</strong></span>
                      </span>
                    )}
                    {item.details.accountName && (
                      <span className="flex items-center gap-1.5">
                        <Layers size={12} className="text-purple-500" />
                        <span>Account: <strong className="text-[var(--text)] font-medium">{item.details.accountName}</strong></span>
                      </span>
                    )}
                    {item.details.vcode && (
                      <span className="flex items-center gap-1.5">
                        <FileText size={12} className="text-amber-500" />
                        <span>VCODE: <strong className="text-[var(--text)] font-mono font-medium">{item.details.vcode}</strong></span>
                      </span>
                    )}
                    {item.details.employeeName && (
                      <span className="flex items-center gap-1.5">
                        <User size={12} className="text-blue-500" />
                        <span>Personnel: <strong className="text-[var(--text)] font-medium">{item.details.employeeName}</strong></span>
                      </span>
                    )}
                    {item.details.headcountNeeded && (
                      <span className="flex items-center gap-1.5">
                        <Users size={12} className="text-emerald-500" />
                        <span>Headcount: <strong className="text-[var(--text)] font-medium">{item.details.headcountNeeded}</strong></span>
                      </span>
                    )}
                    {item.details.proposedTarget !== undefined && item.details.proposedTarget !== null && (
                      <span className="flex items-center gap-1.5">
                        <span>Target Quota: <strong className="text-[var(--text)] font-medium">{item.details.previousTarget ?? "—"} → {item.details.proposedTarget}</strong></span>
                      </span>
                    )}
                    <span className="flex items-center gap-1.5 ml-auto text-[11px] text-[var(--muted)]">
                      <Calendar size={11} />
                      <span>Submitted {formatFullDate(item.createdAt)}</span>
                    </span>
                  </div>

                  {/* Justification / Reason */}
                  {item.details.reason && (
                    <div className="text-xs text-[var(--text)] bg-[var(--soft)]/30 px-3 py-2 rounded-lg border border-[var(--line)]">
                      <span className="font-semibold text-[var(--muted)] uppercase text-[10px] tracking-wider block mb-0.5">
                        Stated Justification
                      </span>
                      <p className="italic text-[var(--text)] leading-relaxed line-clamp-2">
                        &ldquo;{item.details.reason}&rdquo;
                      </p>
                    </div>
                  )}

                  {/* Reviewer Section / Alerts */}
                  {item.status === "rejected" && (
                    <div className="p-3 rounded-lg border border-rose-200 bg-rose-50/70 dark:bg-rose-950/30 dark:border-rose-900/50 flex items-start gap-2.5">
                      <XCircle size={15} className="text-rose-600 dark:text-rose-400 shrink-0 mt-0.5" />
                      <div className="text-xs text-rose-800 dark:text-rose-300 space-y-1">
                        <div className="font-semibold flex items-center gap-2">
                          <span>Rejected by Approver</span>
                          {item.reviewedByName && (
                            <span className="text-[11px] font-normal text-rose-700 dark:text-rose-400">
                              ({item.reviewedByName})
                            </span>
                          )}
                        </div>
                        {item.reviewerRemarks ? (
                          <p className="leading-relaxed font-mono text-[11px]">
                            Feedback: {item.reviewerRemarks}
                          </p>
                        ) : (
                          <p className="italic text-[11px] text-rose-700/80">
                            No specific rejection reason provided.
                          </p>
                        )}
                      </div>
                    </div>
                  )}

                  {item.status === "approved" && (
                    <div className="p-2.5 rounded-lg border border-emerald-200 bg-emerald-50/70 dark:bg-emerald-950/30 dark:border-emerald-900/50 flex items-center justify-between text-xs text-emerald-800 dark:text-emerald-300">
                      <div className="flex items-center gap-2">
                        <CheckCircle2 size={14} className="text-emerald-600 dark:text-emerald-400 shrink-0" />
                        <span>
                          Cleared & Approved
                          {item.reviewedByName ? ` by ${item.reviewedByName}` : ""}
                          {item.reviewerRemarks ? `: "${item.reviewerRemarks}"` : ""}
                        </span>
                      </div>
                      {item.reviewedAt && (
                        <span className="text-[11px] text-emerald-700 dark:text-emerald-400 font-mono">
                          {formatRelativeTime(item.reviewedAt)}
                        </span>
                      )}
                    </div>
                  )}

                  {item.status === "pending" && (
                    <div className="flex items-center gap-2 text-xs text-amber-700 dark:text-amber-400 bg-amber-50/50 dark:bg-amber-950/20 px-3 py-1.5 rounded-md border border-amber-200/60 dark:border-amber-900/40">
                      <Clock size={12} className="animate-spin shrink-0" />
                      <span>Your request is queued and currently awaiting review from authorized administrators.</span>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}

          {/* Pagination Controls */}
          {totalCount > 0 && (
            <div className="rounded-xl border border-[var(--line)] bg-[var(--card)] overflow-hidden shadow-2xs">
              <TablePagination
                page={safePage}
                pageSize={pageSize}
                totalCount={totalCount}
                pageSizeOptions={[10, 20, 50]}
                onPageChange={(newPage) => setPage(newPage)}
                onPageSizeChange={(newSize) => {
                  setPageSize(newSize);
                  setPage(1);
                }}
              />
            </div>
          )}
        </div>
      )}

      {/* Request Detail Modal */}
      <MyRequestDetailModal
        isOpen={isDetailModalOpen}
        onClose={() => setIsDetailModalOpen(false)}
        request={selectedDetailRequest}
      />
    </div>
  );
}

export default function MyRequestsPage() {
  return (
    <Suspense
      fallback={
        <div className="space-y-4">
          <div className="h-14 bg-[var(--soft)] rounded-lg animate-pulse" />
          <div className="h-32 bg-[var(--soft)] rounded-lg animate-pulse" />
        </div>
      }
    >
      <MyRequestsContent />
    </Suspense>
  );
}
