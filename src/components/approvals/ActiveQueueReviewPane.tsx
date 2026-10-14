"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import {
  ArrowRight,
  Building2,
  CheckCheck,
  RefreshCw,
  Search,
  Users,
  X,
} from "lucide-react";
import { DataState } from "@/components/shared/DataState";
import { ApplicantMovementApprovalCard } from "@/components/approvals/ApplicantMovementApprovalCard";
import { CoverageGroupApprovalCard } from "@/components/approvals/CoverageGroupApprovalCard";
import { DeactivationDataTable } from "@/components/approvals/DeactivationDataTable";
import { HeadcountAmendmentApprovalCard } from "@/components/approvals/HeadcountAmendmentApprovalCard";
import { HeadcountStandardApprovalCard } from "@/components/approvals/HeadcountStandardApprovalCard";
import { HrEmplocDeletionReviewCard } from "@/components/approvals/HrEmplocDeletionReviewCard";
import { NewStoreApprovalCard } from "@/components/approvals/NewStoreApprovalCard";
import { RelieverCoverageApprovalCard } from "@/components/approvals/RelieverCoverageApprovalCard";
import { StoreTransferApprovalCard } from "@/components/approvals/StoreTransferApprovalCard";
import { VacancyClosureApprovalCard } from "@/components/approvals/VacancyClosureApprovalCard";
import { useCurrentUser, isHeadOrSuperAdmin } from "@/lib/auth";
import {
  REQUEST_CATEGORIES,
  usePendingHeadcountRequests,
  usePendingNewStoreRequests,
  usePendingVacancyClosureRequests,
  usePendingApplicantMovements,
  useDeactivationRequests,
  useDeactivationCounts,
  type DeactivationStatusTab,
  usePendingAccountGroupTransfers,
  usePendingRelieverEndorsements,
  usePendingCoverageRequests,
  useApproveAllVacancyClosures,
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
  relievers: { href: "/cencom", label: "Open CENCOM Module" },
};

export function ActiveQueueReviewPane({
  selectedCategory,
  onSelectCategory,
  counts,
}: ActiveQueueReviewPaneProps) {
  const currentUser = useCurrentUser();
  const canBulkApproveClosures = isHeadOrSuperAdmin(
    currentUser?.roleKey || currentUser?.roleName
  );

  // Search & Filter state
  const [filterType, setFilterType] = useState<"all" | "amendment" | "standard">("all");
  const [searchQuery, setSearchQuery] = useState("");
  const [deletionSearchQuery, setDeletionSearchQuery] = useState("");
  const [newStoreSearchQuery, setNewStoreSearchQuery] = useState("");
  const [vacancyClosureSearchQuery, setVacancyClosureSearchQuery] = useState("");
  const [movementSearchQuery, setMovementSearchQuery] = useState("");
  const [movementTypeFilter, setMovementTypeFilter] = useState<"all" | "TRANSFER" | "SWAP">("all");
  const [deactivationSearchQuery, setDeactivationSearchQuery] = useState("");
  const [deactivationTab, setDeactivationTab] = useState<DeactivationStatusTab>("pending");
  const [transferSearchQuery, setTransferSearchQuery] = useState("");
  const [relieverSearchQuery, setRelieverSearchQuery] = useState("");
  const [rovingSearchQuery, setRovingSearchQuery] = useState("");
  const [relieverPriorityFilter, setRelieverPriorityFilter] = useState<"all" | "Urgent" | "High" | "Normal">("all");

  // Bulk actions state
  const [isApproveAllClosuresOpen, setIsApproveAllClosuresOpen] = useState(false);
  const [approveAllFeedback, setApproveAllFeedback] = useState<{
    type: "success" | "error";
    message: string;
  } | null>(null);

  // Queries
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

  const {
    data: newStoreRequests = [],
    isLoading: isNewStoreLoading,
    isError: isNewStoreError,
    refetch: refetchNewStores,
    isRefetching: isNewStoreRefetching,
  } = usePendingNewStoreRequests();

  const {
    data: closureRequests = [],
    isLoading: isClosureLoading,
    isError: isClosureError,
    refetch: refetchClosures,
    isRefetching: isClosureRefetching,
  } = usePendingVacancyClosureRequests();

  const {
    data: movementRequests = [],
    isLoading: isMovementLoading,
    isError: isMovementError,
    refetch: refetchMovements,
    isRefetching: isMovementRefetching,
  } = usePendingApplicantMovements();

  const {
    data: deactivationRequests = [],
    isLoading: isDeactLoading,
    isError: isDeactError,
    refetch: refetchDeactivations,
    isRefetching: isDeactRefetching,
  } = useDeactivationRequests(deactivationTab);

  const {
    data: deactCounts = { pending: 0, approved: 0, rejected: 0 },
    refetch: refetchDeactCounts,
  } = useDeactivationCounts();

  const {
    data: transferRequests = [],
    isLoading: isTransferLoading,
    isError: isTransferError,
    refetch: refetchTransfers,
    isRefetching: isTransferRefetching,
  } = usePendingAccountGroupTransfers();

  const {
    data: relieverRequests = [],
    isLoading: isRelieverLoading,
    isError: isRelieverError,
    refetch: refetchRelievers,
    isRefetching: isRelieverRefetching,
  } = usePendingRelieverEndorsements();

  const {
    data: rovingRequests = [],
    isLoading: isRovingLoading,
    isError: isRovingError,
    refetch: refetchRoving,
    isRefetching: isRovingRefetching,
  } = usePendingCoverageRequests();

  const approveAllClosuresMutation = useApproveAllVacancyClosures();

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

  const filteredNewStoreRequests = useMemo(() => {
    if (!newStoreSearchQuery.trim()) return newStoreRequests;
    const q = newStoreSearchQuery.toLowerCase();
    return newStoreRequests.filter(
      (req) =>
        req.storeName.toLowerCase().includes(q) ||
        req.accountName.toLowerCase().includes(q) ||
        req.city.toLowerCase().includes(q) ||
        req.province.toLowerCase().includes(q) ||
        req.requestedByName?.toLowerCase().includes(q) ||
        req.groupName?.toLowerCase().includes(q) ||
        req.reason.toLowerCase().includes(q)
    );
  }, [newStoreRequests, newStoreSearchQuery]);

  const filteredClosureRequests = useMemo(() => {
    if (!vacancyClosureSearchQuery.trim()) return closureRequests;
    const q = vacancyClosureSearchQuery.toLowerCase();
    return closureRequests.filter(
      (req) =>
        req.vacancyVcode.toLowerCase().includes(q) ||
        req.position?.toLowerCase().includes(q) ||
        req.storeName?.toLowerCase().includes(q) ||
        req.storeBranch?.toLowerCase().includes(q) ||
        req.account?.toLowerCase().includes(q) ||
        req.requestedBy.toLowerCase().includes(q) ||
        req.reason.toLowerCase().includes(q) ||
        req.details?.toLowerCase().includes(q)
    );
  }, [closureRequests, vacancyClosureSearchQuery]);

  const filteredMovementRequests = useMemo(() => {
    return movementRequests.filter((req) => {
      if (movementTypeFilter !== "all" && req.movementType !== movementTypeFilter) {
        return false;
      }
      if (!movementSearchQuery.trim()) return true;
      const q = movementSearchQuery.toLowerCase();
      const matchSource =
        req.sourceApplicantName.toLowerCase().includes(q) ||
        req.sourceVacancyVcode.toLowerCase().includes(q) ||
        req.sourceStoreName?.toLowerCase().includes(q) ||
        req.sourcePosition?.toLowerCase().includes(q) ||
        req.sourceAccountName?.toLowerCase().includes(q);
      const matchTarget =
        req.targetApplicantName?.toLowerCase().includes(q) ||
        req.targetVacancyVcode.toLowerCase().includes(q) ||
        req.targetStoreName?.toLowerCase().includes(q) ||
        req.targetPosition?.toLowerCase().includes(q) ||
        req.targetAccountName?.toLowerCase().includes(q);
      const matchMeta =
        req.requestNumber.toLowerCase().includes(q) ||
        req.requestedByName.toLowerCase().includes(q) ||
        req.reason.toLowerCase().includes(q) ||
        req.remarks?.toLowerCase().includes(q);

      return matchSource || matchTarget || matchMeta;
    });
  }, [movementRequests, movementTypeFilter, movementSearchQuery]);

  const transferCount = useMemo(
    () => movementRequests.filter((r) => r.movementType === "TRANSFER").length,
    [movementRequests]
  );
  const swapCount = useMemo(
    () => movementRequests.filter((r) => r.movementType === "SWAP").length,
    [movementRequests]
  );

  const filteredDeactivationRequests = useMemo(() => {
    if (!deactivationSearchQuery.trim()) return deactivationRequests;
    const q = deactivationSearchQuery.toLowerCase();
    return deactivationRequests.filter((req) => {
      return (
        req.employeeName.toLowerCase().includes(q) ||
        req.employeeNo?.toLowerCase().includes(q) ||
        req.storeName?.toLowerCase().includes(q) ||
        req.positionTitle?.toLowerCase().includes(q) ||
        req.accountName.toLowerCase().includes(q) ||
        req.groupName?.toLowerCase().includes(q) ||
        req.requestedByName.toLowerCase().includes(q) ||
        req.separationStatus.toLowerCase().includes(q) ||
        req.remarks?.toLowerCase().includes(q) ||
        (req.rejectionReason?.toLowerCase().includes(q) ?? false)
      );
    });
  }, [deactivationRequests, deactivationSearchQuery]);

  const filteredTransferRequests = useMemo(() => {
    if (!transferSearchQuery.trim()) return transferRequests;
    const q = transferSearchQuery.toLowerCase();
    return transferRequests.filter((req) => {
      return (
        req.accountName.toLowerCase().includes(q) ||
        req.requestNumber.toLowerCase().includes(q) ||
        req.fromGroupName.toLowerCase().includes(q) ||
        req.fromGroupCode.toLowerCase().includes(q) ||
        req.toGroupName.toLowerCase().includes(q) ||
        req.toGroupCode.toLowerCase().includes(q) ||
        req.requestedByName.toLowerCase().includes(q) ||
        req.reason.toLowerCase().includes(q)
      );
    });
  }, [transferRequests, transferSearchQuery]);

  const filteredRelieverRequests = useMemo(() => {
    return relieverRequests.filter((req) => {
      if (
        relieverPriorityFilter !== "all" &&
        req.priority.toLowerCase() !== relieverPriorityFilter.toLowerCase()
      ) {
        return false;
      }
      if (!relieverSearchQuery.trim()) return true;
      const q = relieverSearchQuery.toLowerCase();
      return (
        (req.employeeName?.toLowerCase().includes(q) ?? false) ||
        (req.employeeNumber?.toLowerCase().includes(q) ?? false) ||
        (req.requestedStore?.toLowerCase().includes(q) ?? false) ||
        (req.requestedAccount?.toLowerCase().includes(q) ?? false) ||
        (req.requestedGroup?.toLowerCase().includes(q) ?? false) ||
        (req.requestedBy?.toLowerCase().includes(q) ?? false) ||
        (req.reason?.toLowerCase().includes(q) ?? false) ||
        (req.poolType?.toLowerCase().includes(q) ?? false)
      );
    });
  }, [relieverRequests, relieverPriorityFilter, relieverSearchQuery]);

  const filteredRovingRequests = useMemo(() => {
    if (!rovingSearchQuery.trim()) return rovingRequests;
    const q = rovingSearchQuery.toLowerCase();
    return rovingRequests.filter((req) => {
      return (
        req.requestType.toLowerCase().includes(q) ||
        (req.accountName?.toLowerCase().includes(q) ?? false) ||
        (req.targetCoverageGroupName?.toLowerCase().includes(q) ?? false) ||
        (req.targetCoverageGroupCode?.toLowerCase().includes(q) ?? false) ||
        req.requestedByName.toLowerCase().includes(q) ||
        (req.reason?.toLowerCase().includes(q) ?? false)
      );
    });
  }, [rovingRequests, rovingSearchQuery]);

  const quotaCount = useMemo(
    () => requests.filter((r) => r.isQuotaAmendment).length,
    [requests]
  );
  const standardCount = useMemo(
    () => requests.filter((r) => !r.isQuotaAmendment).length,
    [requests]
  );

  const handleConfirmApproveAllClosures = async () => {
    setApproveAllFeedback(null);
    try {
      const res = await approveAllClosuresMutation.mutateAsync();
      setApproveAllFeedback({
        type: "success",
        message: `Approved ${res.approved_count} pending vacancy closure${
          res.approved_count === 1 ? "" : "s"
        }${res.skipped_count > 0 ? ` (${res.skipped_count} skipped)` : ""}.`,
      });
      setIsApproveAllClosuresOpen(false);
    } catch (err: unknown) {
      setApproveAllFeedback({
        type: "error",
        message:
          err instanceof Error
            ? err.message
            : "Failed to approve all closure requests.",
      });
    }
  };


  // ── 1. New Store Requests Queue ──────────────────────────────────────────
  if (selectedCategory === "new_stores") {
    return (
      <div className="flex h-full flex-col">
        {/* Pane Toolbar */}
        <div className="border-b border-border-default pb-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-semibold text-text-primary">
                  New Store Requests Queue
                </h2>
                <span className="rounded-full bg-emerald-100 px-2.5 py-0.5 font-mono text-xs font-semibold text-emerald-800">
                  {newStoreRequests.length} pending
                </span>
              </div>
              <p className="mt-0.5 text-xs text-text-secondary">
                Review store registry additions and branch onboarding requests awaiting administrative verification.
              </p>
            </div>

            <button
              type="button"
              onClick={() => refetchNewStores()}
              disabled={isNewStoreRefetching || isNewStoreLoading}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${isNewStoreRefetching ? "animate-spin text-brand-600" : ""}`}
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
                placeholder="Search store name, account, location, requester..."
                value={newStoreSearchQuery}
                onChange={(e) => setNewStoreSearchQuery(e.target.value)}
                className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
              />
            </div>
          </div>
        </div>

        {/* Requests List Area */}
        <div className="mt-4 flex-1 space-y-4">
          {isNewStoreLoading ? (
            <DataState
              kind="loading"
              title="Loading New Store Requests"
              description="Fetching pending new store addition requests..."
            />
          ) : isNewStoreError ? (
            <DataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching pending new store requests."
              onRetry={() => refetchNewStores()}
            />
          ) : filteredNewStoreRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                newStoreSearchQuery
                  ? "No Matching Requests"
                  : "No Pending Store Requests"
              }
              description={
                newStoreSearchQuery
                  ? `No requests match "${newStoreSearchQuery}". Clear your search query to see all items.`
                  : "All new store addition requests have been reviewed and processed."
              }
            />
          ) : (
            <div className="space-y-4">
              {filteredNewStoreRequests.map((req) => (
                <NewStoreApprovalCard key={req.id} request={req} />
              ))}
            </div>
          )}
        </div>
      </div>
    );
  }

  // ── 2. Vacancy Closures Queue ─────────────────────────────────────────────
  if (selectedCategory === "vacancy_closures") {
    return (
      <div className="flex h-full flex-col">
        {/* Pane Toolbar */}
        <div className="border-b border-border-default pb-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-semibold text-text-primary">
                  Vacancy Closures Queue
                </h2>
                <span className="rounded-full bg-indigo-100 px-2.5 py-0.5 font-mono text-xs font-semibold text-indigo-800">
                  {closureRequests.length} pending
                </span>
              </div>
              <p className="mt-0.5 text-xs text-text-secondary">
                Review position requisition retirement and closed-slot clearance requests awaiting administrative action.
              </p>
            </div>

            <div className="flex items-center gap-2">
              {canBulkApproveClosures && (
                <button
                  type="button"
                  onClick={() => setIsApproveAllClosuresOpen(true)}
                  disabled={
                    closureRequests.length === 0 ||
                    approveAllClosuresMutation.isPending
                  }
                  className="inline-flex h-8 items-center gap-1.5 rounded-md border border-emerald-300 bg-emerald-600 px-3 text-xs font-medium text-white shadow-2xs hover:bg-emerald-700 disabled:opacity-50 transition"
                >
                  <CheckCheck className="h-3.5 w-3.5" />
                  <span>Approve All Pending Closures</span>
                </button>
              )}

              <button
                type="button"
                onClick={() => refetchClosures()}
                disabled={isClosureRefetching || isClosureLoading}
                className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50"
              >
                <RefreshCw
                  className={`h-3.5 w-3.5 ${
                    isClosureRefetching ? "animate-spin text-brand-600" : ""
                  }`}
                />
                <span>Refresh</span>
              </button>
            </div>
          </div>

          {/* Feedback Banner */}
          {approveAllFeedback && (
            <div
              className={`mt-3 flex items-start gap-2 rounded-md p-2.5 text-xs ${
                approveAllFeedback.type === "success"
                  ? "border border-emerald-200 bg-emerald-50 text-emerald-800"
                  : "border border-rose-200 bg-rose-50 text-rose-800"
              }`}
            >
              <div className="flex-1">{approveAllFeedback.message}</div>
              <button
                type="button"
                onClick={() => setApproveAllFeedback(null)}
                className="text-text-muted hover:text-text-primary"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            </div>
          )}

          {/* Search */}
          <div className="mt-4">
            <div className="relative min-w-[240px] max-w-sm">
              <Search className="pointer-events-none absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
              <input
                type="text"
                placeholder="Search VCode, store, position, requester..."
                value={vacancyClosureSearchQuery}
                onChange={(e) => setVacancyClosureSearchQuery(e.target.value)}
                className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
              />
            </div>
          </div>
        </div>

        {/* Requests List Area */}
        <div className="mt-4 flex-1 space-y-4">
          {isClosureLoading ? (
            <DataState
              kind="loading"
              title="Loading Vacancy Closures"
              description="Fetching pending vacancy closure requests..."
            />
          ) : isClosureError ? (
            <DataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching pending vacancy closure requests."
              onRetry={() => refetchClosures()}
            />
          ) : filteredClosureRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                vacancyClosureSearchQuery
                  ? "No Matching Requests"
                  : "No Pending Vacancy Closures"
              }
              description={
                vacancyClosureSearchQuery
                  ? `No requests match "${vacancyClosureSearchQuery}". Clear your search query to see all items.`
                  : "All vacancy closure requests have been reviewed and processed."
              }
            />
          ) : (
            <div className="space-y-4">
              {filteredClosureRequests.map((req) => (
                <VacancyClosureApprovalCard key={req.id} request={req} />
              ))}
            </div>
          )}
        </div>

        {/* Approve All Confirmation Modal */}
        {isApproveAllClosuresOpen && (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4 backdrop-blur-xs">
            <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-base p-6 shadow-xl animate-drawer-in">
              <div className="flex items-start justify-between gap-3">
                <div className="flex items-center gap-2">
                  <div className="flex h-9 w-9 items-center justify-center rounded-full bg-emerald-100 text-emerald-700">
                    <CheckCheck className="h-5 w-5" />
                  </div>
                  <div>
                    <h3 className="text-base font-semibold text-text-primary">
                      Approve All Pending Closures
                    </h3>
                    <p className="text-xs text-text-secondary">
                      Bulk approval of all active closure requisitions
                    </p>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => setIsApproveAllClosuresOpen(false)}
                  disabled={approveAllClosuresMutation.isPending}
                  className="text-text-muted hover:text-text-primary"
                >
                  <X className="h-5 w-5" />
                </button>
              </div>

              <div className="mt-4 rounded-lg border border-slate-200 bg-slate-50 p-3 text-xs space-y-2">
                <p className="text-text-primary font-medium">
                  Are you sure you want to approve all{" "}
                  <span className="font-bold text-emerald-700">
                    {closureRequests.length}
                  </span>{" "}
                  pending vacancy closure requests?
                </p>
                <p className="text-text-secondary">
                  This action will permanently close and archive each corresponding vacancy and reconcile active plantilla slots per ADR-001.
                </p>
              </div>

              <div className="mt-6 flex justify-end gap-2">
                <button
                  type="button"
                  onClick={() => setIsApproveAllClosuresOpen(false)}
                  disabled={approveAllClosuresMutation.isPending}
                  className="rounded-md border border-border-default bg-white px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition"
                >
                  Cancel
                </button>
                <button
                  type="button"
                  onClick={handleConfirmApproveAllClosures}
                  disabled={approveAllClosuresMutation.isPending}
                  className="inline-flex items-center gap-1.5 rounded-md bg-emerald-600 px-4 py-1.5 text-xs font-medium text-white hover:bg-emerald-700 disabled:opacity-50 transition"
                >
                  {approveAllClosuresMutation.isPending ? (
                    <>
                      <RefreshCw className="h-3.5 w-3.5 animate-spin" />
                      <span>Processing Bulk Approval...</span>
                    </>
                  ) : (
                    <>
                      <CheckCheck className="h-3.5 w-3.5" />
                      <span>Confirm Bulk Approval</span>
                    </>
                  )}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    );
  }

  // ── 3. HR Emploc Deletions Queue ─────────────────────────────────────────
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

  // ── 4. Headcount Approvals Queue ─────────────────────────────────────────
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

  // ── 5. Applicant Movement Requests (AMR) Queue ───────────────────────────
  if (selectedCategory === "applicant_movements") {
    return (
      <div className="flex h-full flex-col">
        {/* Pane Toolbar */}
        <div className="border-b border-border-default pb-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-semibold text-text-primary">
                  Applicant Movement Approvals
                </h2>
                <span className="rounded-full bg-indigo-100 px-2.5 py-0.5 font-mono text-xs font-semibold text-indigo-800">
                  {movementRequests.length} pending
                </span>
              </div>
              <p className="mt-0.5 text-xs text-text-secondary">
                Review candidate transfer and slot swap requests awaiting administrative clearance and execution.
              </p>
            </div>

            <button
              type="button"
              onClick={() => refetchMovements()}
              disabled={isMovementRefetching || isMovementLoading}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${isMovementRefetching ? "animate-spin text-brand-600" : ""}`}
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
                onClick={() => setMovementTypeFilter("all")}
                className={`rounded-md px-3 py-1 font-medium transition ${
                  movementTypeFilter === "all"
                    ? "bg-white text-text-primary shadow-2xs font-semibold"
                    : "text-text-secondary hover:text-text-primary"
                }`}
              >
                All ({movementRequests.length})
              </button>
              <button
                type="button"
                onClick={() => setMovementTypeFilter("TRANSFER")}
                className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                  movementTypeFilter === "TRANSFER"
                    ? "bg-white text-text-primary shadow-2xs font-semibold"
                    : "text-text-secondary hover:text-text-primary"
                }`}
              >
                <span>Transfers</span>
                {transferCount > 0 && (
                  <span className="rounded-full bg-blue-100 px-1.5 text-[10px] font-mono font-semibold text-blue-700">
                    {transferCount}
                  </span>
                )}
              </button>
              <button
                type="button"
                onClick={() => setMovementTypeFilter("SWAP")}
                className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                  movementTypeFilter === "SWAP"
                    ? "bg-white text-text-primary shadow-2xs font-semibold"
                    : "text-text-secondary hover:text-text-primary"
                }`}
              >
                <span>Swaps</span>
                {swapCount > 0 && (
                  <span className="rounded-full bg-purple-100 px-1.5 text-[10px] font-mono font-semibold text-purple-700">
                    {swapCount}
                  </span>
                )}
              </button>
            </div>

            {/* Search Input */}
            <div className="relative min-w-[240px] flex-1 max-w-sm">
              <Search className="pointer-events-none absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
              <input
                type="text"
                placeholder="Search applicant, VCode, store, position..."
                value={movementSearchQuery}
                onChange={(e) => setMovementSearchQuery(e.target.value)}
                className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
              />
            </div>
          </div>
        </div>

        {/* Requests List Area */}
        <div className="mt-4 flex-1 space-y-4">
          {isMovementLoading ? (
            <DataState
              kind="loading"
              title="Loading Applicant Movement Requests"
              description="Fetching live pending candidate transfer and swap requisitions..."
            />
          ) : isMovementError ? (
            <DataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching pending applicant movements."
              onRetry={() => refetchMovements()}
            />
          ) : filteredMovementRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                movementSearchQuery
                  ? "No Matching Movement Requests"
                  : movementTypeFilter !== "all"
                    ? `No Pending ${movementTypeFilter === "TRANSFER" ? "Transfers" : "Swaps"}`
                    : "No Pending Movement Requests"
              }
              description={
                movementSearchQuery
                  ? `No requests match "${movementSearchQuery}". Clear your search query to see all items.`
                  : "All applicant transfer and swap requests have been reviewed and resolved."
              }
            />
          ) : (
            <div className="space-y-4">
              {filteredMovementRequests.map((req) => (
                <ApplicantMovementApprovalCard key={req.id} request={req} />
              ))}
            </div>
          )}
        </div>
      </div>
    );
  }

  // ── 6. Account Deactivations Queue ───────────────────────────────────────
  if (selectedCategory === "deactivations") {
    const handleRefreshDeactivations = () => {
      refetchDeactivations();
      refetchDeactCounts();
    };

    return (
      <div className="flex h-full flex-col">
        {/* Pane Toolbar */}
        <div className="border-b border-border-default pb-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex flex-wrap items-center gap-3">
              {/* Search bar */}
              <div className="relative w-64 sm:w-72">
                <Search className="pointer-events-none absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
                <input
                  type="text"
                  placeholder="Search employee, ID, store, position, account..."
                  value={deactivationSearchQuery}
                  onChange={(e) => setDeactivationSearchQuery(e.target.value)}
                  className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
                />
              </div>

              {/* Sub-Tabs: Pending / Deactivated / Rejected */}
              <div className="flex items-center gap-1 rounded-lg border border-border-default bg-slate-100/80 p-1 text-xs">
                <button
                  type="button"
                  onClick={() => setDeactivationTab("pending")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    deactivationTab === "pending"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Pending</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      deactivationTab === "pending"
                        ? "bg-amber-100 text-amber-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {deactCounts.pending}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setDeactivationTab("approved")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    deactivationTab === "approved"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Deactivated</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      deactivationTab === "approved"
                        ? "bg-emerald-100 text-emerald-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {deactCounts.approved}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setDeactivationTab("rejected")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    deactivationTab === "rejected"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Rejected</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      deactivationTab === "rejected"
                        ? "bg-rose-100 text-rose-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {deactCounts.rejected}
                  </span>
                </button>
              </div>
            </div>

            {/* Refresh trigger */}
            <button
              type="button"
              onClick={handleRefreshDeactivations}
              disabled={isDeactRefetching || isDeactLoading}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isDeactRefetching ? "animate-spin text-brand-600" : ""
                }`}
              />
              <span>Refresh</span>
            </button>
          </div>
        </div>

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isDeactLoading ? (
            <DataState
              kind="loading"
              title="Loading Deactivation Requests"
              description="Fetching live employee deactivation and separation clearance requests..."
            />
          ) : isDeactError ? (
            <DataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching deactivation requests."
              onRetry={handleRefreshDeactivations}
            />
          ) : filteredDeactivationRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                deactivationSearchQuery
                  ? "No Matching Deactivation Requests"
                  : deactivationTab === "pending"
                  ? "No Pending Deactivation Requests"
                  : deactivationTab === "approved"
                  ? "No Deactivated Records"
                  : "No Rejected Deactivation Requests"
              }
              description={
                deactivationSearchQuery
                  ? `No requests match "${deactivationSearchQuery}". Clear your search query to see all items.`
                  : deactivationTab === "pending"
                  ? "All employee separation clearances and deactivation requests have been processed."
                  : deactivationTab === "approved"
                  ? "No approved or completed employee deactivations found in this queue."
                  : "No rejected employee deactivation requests found in this queue."
              }
            />
          ) : (
            <DeactivationDataTable
              requests={filteredDeactivationRequests}
              tab={deactivationTab}
            />
          )}
        </div>
      </div>
    );
  }

  // ── 7. Account Group Transfers Category ────────────────────────────────
  if (selectedCategory === "account_group_transfers") {
    const livePendingCount = counts.account_group_transfers ?? transferRequests.length;

    return (
      <div className="flex h-full flex-col">
        {/* Header Toolbar */}
        <div className="flex flex-col gap-3 border-b border-border-default pb-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <div className="flex items-center gap-2">
              <h2 className="text-lg font-semibold text-text-primary">
                {currentCategoryConfig.label}
              </h2>
              <span className="rounded-full bg-blue-100 px-2.5 py-0.5 font-mono text-xs font-semibold text-blue-800">
                {livePendingCount} pending
              </span>
            </div>
            <p className="mt-0.5 text-xs text-text-secondary">
              {currentCategoryConfig.description}
            </p>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={() => refetchTransfers()}
              disabled={isTransferRefetching}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-white px-3 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50 transition"
              title="Refresh Queue"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${isTransferRefetching ? "animate-spin" : ""}`}
                aria-hidden="true"
              />
              <span>Refresh</span>
            </button>

            {/* Client-side Search */}
            <div className="relative w-full sm:w-64">
              <Search
                className="absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-text-muted"
                aria-hidden="true"
              />
              <input
                type="text"
                placeholder="Search account, group, AGT-#..."
                value={transferSearchQuery}
                onChange={(e) => setTransferSearchQuery(e.target.value)}
                className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
              />
            </div>
          </div>
        </div>

        {/* Requests List Area */}
        <div className="mt-4 flex-1 space-y-4">
          {isTransferLoading ? (
            <DataState
              kind="loading"
              title="Loading Account Group Transfers"
              description="Fetching live account group reassignments and simulation snapshots..."
            />
          ) : isTransferError ? (
            <DataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching pending account group transfers."
              onRetry={() => refetchTransfers()}
            />
          ) : filteredTransferRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                transferSearchQuery
                  ? "No Matching Account Group Transfers"
                  : "No Pending Account Group Transfers"
              }
              description={
                transferSearchQuery
                  ? `No requests match "${transferSearchQuery}". Clear your search query to see all items.`
                  : "All organizational account group reassignments have been processed."
              }
            />
          ) : (
            <div className="space-y-4">
              {filteredTransferRequests.map((req) => (
                <StoreTransferApprovalCard key={req.id} request={req} />
              ))}
            </div>
          )}
        </div>
      </div>
    );
  }

  // ── 8. Roving Coverage Groups Review Queue ──────────────────────────────
  if (selectedCategory === "coverage") {
    const activeCount = counts.coverage ?? rovingRequests.length;
    const isBusy = isRovingLoading || isRovingRefetching;

    return (
      <div className="flex h-full flex-col">
        {/* Header */}
        <div className="border-b border-border-default pb-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-2">
              <h2 className="text-lg font-semibold text-text-primary">
                Roving Coverage Group Structures
              </h2>
              {activeCount > 0 && (
                <span className="rounded-full bg-blue-100 px-2.5 py-0.5 font-mono text-xs font-semibold text-blue-800">
                  {activeCount} pending
                </span>
              )}
            </div>

            <button
              type="button"
              onClick={() => refetchRoving()}
              disabled={isBusy}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-white px-3 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50 transition"
              title="Refresh Queue"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${isBusy ? "animate-spin" : ""}`}
              />
              <span>Refresh</span>
            </button>
          </div>
          <p className="mt-0.5 text-xs text-text-secondary">
            Operational review queue for CENCOM roving store allocation groups and schedule structures
          </p>
        </div>

        {/* Toolbar: Search */}
        <div className="my-4 flex flex-wrap items-center gap-3">
          <div className="relative min-w-[240px] flex-1">
            <Search className="absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-text-tertiary" />
            <input
              type="text"
              placeholder="Search by group name, code, operation type, account, or requester..."
              value={rovingSearchQuery}
              onChange={(e) => setRovingSearchQuery(e.target.value)}
              className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-8 text-xs text-text-primary placeholder:text-text-tertiary focus:border-brand-500 focus:outline-none"
            />
            {rovingSearchQuery && (
              <button
                type="button"
                onClick={() => setRovingSearchQuery("")}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-text-tertiary hover:text-text-primary"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            )}
          </div>
        </div>

        {/* Content Stream */}
        <div className="flex-1 overflow-y-auto pr-1">
          {isRovingLoading ? (
            <DataState
              kind="loading"
              title="Loading Roving Coverage Groups"
              description="Fetching pending coverage group structural requests..."
            />
          ) : isRovingError ? (
            <DataState
              kind="error"
              title="Failed to Load Coverage Requests"
              description="An error occurred while fetching pending coverage requests."
              onRetry={() => refetchRoving()}
            />
          ) : filteredRovingRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                rovingSearchQuery
                  ? "No Matching Coverage Group Requests"
                  : "No Pending Coverage Group Requests"
              }
              description={
                rovingSearchQuery
                  ? `No requests match "${rovingSearchQuery}". Clear your search query to see all items.`
                  : "All CENCOM roving coverage group structural requests have been processed."
              }
            />
          ) : (
            <div className="space-y-4">
              {filteredRovingRequests.map((req) => (
                <CoverageGroupApprovalCard key={req.id} request={req} />
              ))}
            </div>
          )}
        </div>
      </div>
    );
  }

  // ── 9. Reliever Endorsements Review Queue ────────────────────────────────
  if (selectedCategory === "relievers") {
    const activeCount = counts.relievers ?? relieverRequests.length;
    const isBusy = isRelieverLoading || isRelieverRefetching;

    return (
      <div className="flex h-full flex-col">
        {/* Header */}
        <div className="border-b border-border-default pb-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-2">
              <h2 className="text-lg font-semibold text-text-primary">
                Reliever Endorsements & Pool Deployments
              </h2>
              {activeCount > 0 && (
                <span className="rounded-full bg-blue-100 px-2.5 py-0.5 font-mono text-xs font-semibold text-blue-800">
                  {activeCount} pending
                </span>
              )}
            </div>

            <button
              type="button"
              onClick={() => refetchRelievers()}
              disabled={isBusy}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-white px-3 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50 transition"
              title="Refresh Queue"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${isBusy ? "animate-spin" : ""}`}
              />
              <span>Refresh</span>
            </button>
          </div>
          <p className="mt-0.5 text-xs text-text-secondary">
            Operational review queue for temporary reliever pool deployments and workforce coverage
          </p>
        </div>

        {/* Toolbar: Search and Filters */}
        <div className="my-4 flex flex-wrap items-center gap-3">
          <div className="relative min-w-[240px] flex-1">
            <Search className="absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-text-tertiary" />
            <input
              type="text"
              placeholder="Search by reliever name, ID, store, account, or requester..."
              value={relieverSearchQuery}
              onChange={(e) => setRelieverSearchQuery(e.target.value)}
              className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-8 text-xs text-text-primary placeholder:text-text-tertiary focus:border-brand-500 focus:outline-none"
            />
            {relieverSearchQuery && (
              <button
                type="button"
                onClick={() => setRelieverSearchQuery("")}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-text-tertiary hover:text-text-primary"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            )}
          </div>

          {/* Priority Filter */}
          <div className="flex items-center gap-1.5">
            <span className="text-2xs font-semibold uppercase tracking-wider text-text-tertiary">
              Priority:
            </span>
            {(["all", "Urgent", "High", "Normal"] as const).map((p) => (
              <button
                key={p}
                type="button"
                onClick={() => setRelieverPriorityFilter(p)}
                className={`rounded-md px-2.5 py-1 text-2xs font-semibold capitalize transition ${
                  relieverPriorityFilter === p
                    ? "bg-slate-900 text-white shadow-2xs"
                    : "bg-surface-subtle text-text-secondary hover:bg-surface-hover hover:text-text-primary border border-border-subtle"
                }`}
              >
                {p}
              </button>
            ))}
          </div>
        </div>

        {/* Content Stream */}
        <div className="flex-1 overflow-y-auto pr-1">
          {isRelieverLoading ? (
            <DataState
              kind="loading"
              title="Loading Reliever Deployments"
              description="Fetching pending reliever endorsement requests from workforce pool..."
            />
          ) : isRelieverError ? (
            <DataState
              kind="error"
              title="Failed to Load Reliever Deployments"
              description="An error occurred while fetching pending reliever endorsement requests."
              onRetry={() => refetchRelievers()}
            />
          ) : filteredRelieverRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                relieverSearchQuery || relieverPriorityFilter !== "all"
                  ? "No Matching Reliever Endorsements"
                  : "No Pending Reliever Endorsements"
              }
              description={
                relieverSearchQuery || relieverPriorityFilter !== "all"
                  ? "No requests match your current search and priority filters. Try clearing filters to see all pending items."
                  : "All workforce pool reliever endorsements have been processed."
              }
            />
          ) : (
            <div className="space-y-4">
              {filteredRelieverRequests.map((req) => (
                <RelieverCoverageApprovalCard key={req.requestId} request={req} />
              ))}
            </div>
          )}
        </div>
      </div>
    );
  }

  // ── 9. Other Categories (Fallback Pane) ──────────────────────────────────
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
          {Boolean(linkInfo) && (
            <Link
              href={(linkInfo as { href: string; label: string }).href}
              className="inline-flex h-9 items-center gap-1.5 rounded-md border border-brand-300 bg-brand-50 px-4 text-xs font-semibold text-brand-700 shadow-2xs hover:bg-brand-100 transition"
            >
              <span>{(linkInfo as { href: string; label: string }).label}</span>
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
