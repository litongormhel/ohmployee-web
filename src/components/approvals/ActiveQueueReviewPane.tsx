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
import { AccountTransferDataTable } from "@/components/approvals/AccountTransferDataTable";
import { ApplicantMovementDataTable } from "@/components/approvals/ApplicantMovementDataTable";
import { CoverageDataTable } from "@/components/approvals/CoverageDataTable";
import { DeactivationDataTable } from "@/components/approvals/DeactivationDataTable";
import { HeadcountDataTable } from "@/components/approvals/HeadcountDataTable";
import { HrEmplocDeletionDataTable } from "@/components/approvals/HrEmplocDeletionDataTable";
import { NewStoreDataTable } from "@/components/approvals/NewStoreDataTable";
import { RelieverDataTable } from "@/components/approvals/RelieverDataTable";
import { VacancyClosureDataTable } from "@/components/approvals/VacancyClosureDataTable";
import { useCurrentUser, isHeadOrSuperAdmin } from "@/lib/auth";
import {
  REQUEST_CATEGORIES,
  useHeadcountRequests,
  useHeadcountCounts,
  useNewStoreRequests,
  useNewStoreCounts,
  useVacancyClosureRequests,
  useVacancyClosureCounts,
  useApplicantMovementRequests,
  useApplicantMovementCounts,
  useDeactivationRequests,
  useDeactivationCounts,
  type DeactivationStatusTab,
  type ApprovalStatusTab,
  useAccountGroupTransfers,
  useAccountGroupTransferCounts,
  useRelieverEndorsements,
  useRelieverCounts,
  useCoverageRequests,
  useCoverageCounts,
  useApproveAllVacancyClosures,
  type RequestCategoryCounts,
  type RequestCategoryKey,
} from "@/lib/queries/requests";
import {
  useEmplocDeletionRequests,
  useEmplocDeletionCounts,
} from "@/lib/queries/hr_emploc";

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

  // Sub-tab selection state (pending | approved | rejected) for each queue
  const [newStoreTab, setNewStoreTab] = useState<ApprovalStatusTab>("pending");
  const [headcountTab, setHeadcountTab] = useState<ApprovalStatusTab>("pending");
  const [coverageTab, setCoverageTab] = useState<ApprovalStatusTab>("pending");
  const [vacancyClosureTab, setVacancyClosureTab] = useState<ApprovalStatusTab>("pending");
  const [hrEmplocTab, setHrEmplocTab] = useState<ApprovalStatusTab>("pending");
  const [movementTab, setMovementTab] = useState<ApprovalStatusTab>("pending");
  const [deactivationTab, setDeactivationTab] = useState<DeactivationStatusTab>("pending");
  const [transferTab, setTransferTab] = useState<ApprovalStatusTab>("pending");
  const [relieverTab, setRelieverTab] = useState<ApprovalStatusTab>("pending");

  // Search queries per queue
  const [searchQuery, setSearchQuery] = useState("");
  const [deletionSearchQuery, setDeletionSearchQuery] = useState("");
  const [newStoreSearchQuery, setNewStoreSearchQuery] = useState("");
  const [vacancyClosureSearchQuery, setVacancyClosureSearchQuery] = useState("");
  const [movementSearchQuery, setMovementSearchQuery] = useState("");
  const [deactivationSearchQuery, setDeactivationSearchQuery] = useState("");
  const [transferSearchQuery, setTransferSearchQuery] = useState("");
  const [relieverSearchQuery, setRelieverSearchQuery] = useState("");
  const [rovingSearchQuery, setRovingSearchQuery] = useState("");

  // Bulk actions state for Vacancy Closures
  const [isApproveAllClosuresOpen, setIsApproveAllClosuresOpen] = useState(false);
  const [approveAllFeedback, setApproveAllFeedback] = useState<{
    type: "success" | "error";
    message: string;
  } | null>(null);

  // ── Queries & Live Counts ───────────────────────────────────────────────
  // 1. Headcount
  const {
    data: requests = [],
    isLoading,
    isError,
    refetch,
    isRefetching,
  } = useHeadcountRequests(headcountTab);

  const {
    data: headcountCounts = { pending: 0, approved: 0, rejected: 0 },
    refetch: refetchHeadcountCounts,
  } = useHeadcountCounts();

  // 2. HR Emploc Deletions
  const {
    data: deletionRequests = [],
    isLoading: isDeletionLoading,
    isError: isDeletionError,
    refetch: refetchDeletions,
    isRefetching: isDeletionRefetching,
  } = useEmplocDeletionRequests(hrEmplocTab);

  const {
    data: deletionCounts = { pending: 0, approved: 0, rejected: 0 },
    refetch: refetchDeletionCounts,
  } = useEmplocDeletionCounts();

  // 3. New Store Requests
  const {
    data: newStoreRequests = [],
    isLoading: isNewStoreLoading,
    isError: isNewStoreError,
    refetch: refetchNewStores,
    isRefetching: isNewStoreRefetching,
  } = useNewStoreRequests(newStoreTab);

  const {
    data: newStoreCounts = { pending: 0, approved: 0, rejected: 0 },
    refetch: refetchNewStoreCounts,
  } = useNewStoreCounts();

  // 4. Vacancy Closures
  const {
    data: closureRequests = [],
    isLoading: isClosureLoading,
    isError: isClosureError,
    refetch: refetchClosures,
    isRefetching: isClosureRefetching,
  } = useVacancyClosureRequests(vacancyClosureTab);

  const {
    data: closureCounts = { pending: 0, approved: 0, rejected: 0 },
    refetch: refetchClosureCounts,
  } = useVacancyClosureCounts();

  // 5. Applicant Movements
  const {
    data: movementRequests = [],
    isLoading: isMovementLoading,
    isError: isMovementError,
    refetch: refetchMovements,
    isRefetching: isMovementRefetching,
  } = useApplicantMovementRequests(movementTab);

  const {
    data: movementCounts = { pending: 0, approved: 0, rejected: 0 },
    refetch: refetchMovementCounts,
  } = useApplicantMovementCounts();

  // 6. Deactivations
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

  // 7. Account Group Transfers
  const {
    data: transferRequests = [],
    isLoading: isTransferLoading,
    isError: isTransferError,
    refetch: refetchTransfers,
    isRefetching: isTransferRefetching,
  } = useAccountGroupTransfers(transferTab);

  const {
    data: transferCounts = { pending: 0, approved: 0, rejected: 0 },
    refetch: refetchTransferCounts,
  } = useAccountGroupTransferCounts();

  // 8. Relievers
  const {
    data: relieverRequests = [],
    isLoading: isRelieverLoading,
    isError: isRelieverError,
    refetch: refetchRelievers,
    isRefetching: isRelieverRefetching,
  } = useRelieverEndorsements(relieverTab);

  const {
    data: relieverCounts = { pending: 0, approved: 0, rejected: 0 },
    refetch: refetchRelieverCounts,
  } = useRelieverCounts();

  // 9. Coverage
  const {
    data: rovingRequests = [],
    isLoading: isRovingLoading,
    isError: isRovingError,
    refetch: refetchRoving,
    isRefetching: isRovingRefetching,
  } = useCoverageRequests(coverageTab);

  const {
    data: coverageCounts = { pending: 0, approved: 0, rejected: 0 },
    refetch: refetchCoverageCounts,
  } = useCoverageCounts();

  const approveAllClosuresMutation = useApproveAllVacancyClosures();

  const currentCategoryConfig = useMemo(() => {
    return (
      REQUEST_CATEGORIES.find((c) => c.key === selectedCategory) ??
      REQUEST_CATEGORIES[1]
    );
  }, [selectedCategory]);

  // ── Filtered Search Results ──────────────────────────────────────────────
  const filteredRequests = useMemo(() => {
    if (!searchQuery.trim()) return requests;
    const q = searchQuery.toLowerCase();
    return requests.filter((req) => {
      const matchesStore = req.storeName?.toLowerCase().includes(q);
      const matchesVcode = req.targetVcode?.toLowerCase().includes(q);
      const matchesPosition = req.positionName?.toLowerCase().includes(q);
      const matchesAccount = req.accountName?.toLowerCase().includes(q);
      const matchesRequester = req.requestedByName?.toLowerCase().includes(q);
      const matchesRemarks = req.reviewerRemarks?.toLowerCase().includes(q);
      const matchesReason = req.reason?.toLowerCase().includes(q);

      return (
        matchesStore ||
        matchesVcode ||
        matchesPosition ||
        matchesAccount ||
        matchesRequester ||
        matchesRemarks ||
        matchesReason
      );
    });
  }, [requests, searchQuery]);

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
        req.employeeNo?.toLowerCase().includes(q) ||
        (req.reviewerRemarks?.toLowerCase().includes(q) ?? false)
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
        req.reason.toLowerCase().includes(q) ||
        (req.reviewReason?.toLowerCase().includes(q) ?? false)
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
        req.details?.toLowerCase().includes(q) ||
        (req.reviewerRemarks?.toLowerCase().includes(q) ?? false)
    );
  }, [closureRequests, vacancyClosureSearchQuery]);

  const filteredMovementRequests = useMemo(() => {
    if (!movementSearchQuery.trim()) return movementRequests;
    const q = movementSearchQuery.toLowerCase();
    return movementRequests.filter((req) => {
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
        (req.remarks?.toLowerCase().includes(q) ?? false) ||
        (req.rejectionReason?.toLowerCase().includes(q) ?? false);

      return matchSource || matchTarget || matchMeta;
    });
  }, [movementRequests, movementSearchQuery]);

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
        req.reason.toLowerCase().includes(q) ||
        (req.rejectionReason?.toLowerCase().includes(q) ?? false)
      );
    });
  }, [transferRequests, transferSearchQuery]);

  const filteredRelieverRequests = useMemo(() => {
    if (!relieverSearchQuery.trim()) return relieverRequests;
    const q = relieverSearchQuery.toLowerCase();
    return relieverRequests.filter((req) => {
      return (
        (req.employeeName?.toLowerCase().includes(q) ?? false) ||
        (req.employeeNumber?.toLowerCase().includes(q) ?? false) ||
        (req.requestedStore?.toLowerCase().includes(q) ?? false) ||
        (req.requestedAccount?.toLowerCase().includes(q) ?? false) ||
        (req.requestedGroup?.toLowerCase().includes(q) ?? false) ||
        (req.requestedBy?.toLowerCase().includes(q) ?? false) ||
        (req.reason?.toLowerCase().includes(q) ?? false) ||
        (req.poolType?.toLowerCase().includes(q) ?? false) ||
        (req.rejectionReason?.toLowerCase().includes(q) ?? false)
      );
    });
  }, [relieverRequests, relieverSearchQuery]);

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
        (req.reason?.toLowerCase().includes(q) ?? false) ||
        (req.rejectionReason?.toLowerCase().includes(q) ?? false) ||
        (req.reviewerRemarks?.toLowerCase().includes(q) ?? false)
      );
    });
  }, [rovingRequests, rovingSearchQuery]);

  // Bulk closure confirm handler
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
      refetchClosures();
      refetchClosureCounts();
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
    const handleRefresh = () => {
      refetchNewStores();
      refetchNewStoreCounts();
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
                  placeholder="Search store, account, city, province, requester..."
                  value={newStoreSearchQuery}
                  onChange={(e) => setNewStoreSearchQuery(e.target.value)}
                  className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
                />
              </div>

              {/* Sub-Tabs: Pending / Approved / Rejected */}
              <div className="flex items-center gap-1 rounded-lg border border-border-default bg-slate-100/80 p-1 text-xs">
                <button
                  type="button"
                  onClick={() => setNewStoreTab("pending")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    newStoreTab === "pending"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Pending</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      newStoreTab === "pending"
                        ? "bg-amber-100 text-amber-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {newStoreCounts.pending}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setNewStoreTab("approved")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    newStoreTab === "approved"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Approved</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      newStoreTab === "approved"
                        ? "bg-emerald-100 text-emerald-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {newStoreCounts.approved}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setNewStoreTab("rejected")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    newStoreTab === "rejected"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Rejected</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      newStoreTab === "rejected"
                        ? "bg-rose-100 text-rose-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {newStoreCounts.rejected}
                  </span>
                </button>
              </div>
            </div>

            {/* Refresh */}
            <button
              type="button"
              onClick={handleRefresh}
              disabled={isNewStoreRefetching || isNewStoreLoading}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isNewStoreRefetching ? "animate-spin text-brand-600" : ""
                }`}
              />
              <span>Refresh</span>
            </button>
          </div>
        </div>

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isNewStoreLoading ? (
            <DataState
              kind="loading"
              title="Loading New Store Requests"
              description="Fetching new store addition requests..."
            />
          ) : isNewStoreError ? (
            <DataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching new store requests."
              onRetry={handleRefresh}
            />
          ) : filteredNewStoreRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                newStoreSearchQuery
                  ? "No Matching Requests"
                  : newStoreTab === "pending"
                  ? "No Pending Store Requests"
                  : newStoreTab === "approved"
                  ? "No Approved Store Requests"
                  : "No Rejected Store Requests"
              }
              description={
                newStoreSearchQuery
                  ? `No requests match "${newStoreSearchQuery}". Clear your search query to see all items.`
                  : newStoreTab === "pending"
                  ? "All new store addition requests have been reviewed and processed."
                  : newStoreTab === "approved"
                  ? "No approved new store requests found in this queue."
                  : "No rejected new store requests found in this queue."
              }
            />
          ) : (
            <NewStoreDataTable
              requests={filteredNewStoreRequests}
              tab={newStoreTab}
            />
          )}
        </div>
      </div>
    );
  }

  // ── 2. Vacancy Closures Queue ─────────────────────────────────────────────
  if (selectedCategory === "vacancy_closures") {
    const handleRefresh = () => {
      refetchClosures();
      refetchClosureCounts();
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
                  placeholder="Search VCode, store, position, requester..."
                  value={vacancyClosureSearchQuery}
                  onChange={(e) => setVacancyClosureSearchQuery(e.target.value)}
                  className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
                />
              </div>

              {/* Sub-Tabs: Pending / Approved / Rejected */}
              <div className="flex items-center gap-1 rounded-lg border border-border-default bg-slate-100/80 p-1 text-xs">
                <button
                  type="button"
                  onClick={() => setVacancyClosureTab("pending")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    vacancyClosureTab === "pending"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Pending</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      vacancyClosureTab === "pending"
                        ? "bg-amber-100 text-amber-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {closureCounts.pending}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setVacancyClosureTab("approved")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    vacancyClosureTab === "approved"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Approved</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      vacancyClosureTab === "approved"
                        ? "bg-emerald-100 text-emerald-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {closureCounts.approved}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setVacancyClosureTab("rejected")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    vacancyClosureTab === "rejected"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Rejected</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      vacancyClosureTab === "rejected"
                        ? "bg-rose-100 text-rose-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {closureCounts.rejected}
                  </span>
                </button>
              </div>
            </div>

            {/* Right side controls: Bulk Approve + Refresh */}
            <div className="flex items-center gap-2">
              {canBulkApproveClosures && vacancyClosureTab === "pending" && (
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
                onClick={handleRefresh}
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
        </div>

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isClosureLoading ? (
            <DataState
              kind="loading"
              title="Loading Vacancy Closures"
              description="Fetching vacancy closure requests..."
            />
          ) : isClosureError ? (
            <DataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching vacancy closure requests."
              onRetry={handleRefresh}
            />
          ) : filteredClosureRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                vacancyClosureSearchQuery
                  ? "No Matching Requests"
                  : vacancyClosureTab === "pending"
                  ? "No Pending Vacancy Closures"
                  : vacancyClosureTab === "approved"
                  ? "No Closed Vacancies"
                  : "No Rejected Vacancy Closures"
              }
              description={
                vacancyClosureSearchQuery
                  ? `No requests match "${vacancyClosureSearchQuery}". Clear your search query to see all items.`
                  : vacancyClosureTab === "pending"
                  ? "All vacancy closure requests have been reviewed and processed."
                  : vacancyClosureTab === "approved"
                  ? "No approved vacancy closure requests found in this queue."
                  : "No rejected vacancy closure requests found in this queue."
              }
            />
          ) : (
            <VacancyClosureDataTable
              requests={filteredClosureRequests}
              tab={vacancyClosureTab}
            />
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
    const handleRefresh = () => {
      refetchDeletions();
      refetchDeletionCounts();
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
                  placeholder="Search employee, VCode, store, requester..."
                  value={deletionSearchQuery}
                  onChange={(e) => setDeletionSearchQuery(e.target.value)}
                  className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
                />
              </div>

              {/* Sub-Tabs: Pending / Approved / Rejected */}
              <div className="flex items-center gap-1 rounded-lg border border-border-default bg-slate-100/80 p-1 text-xs">
                <button
                  type="button"
                  onClick={() => setHrEmplocTab("pending")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    hrEmplocTab === "pending"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Pending</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      hrEmplocTab === "pending"
                        ? "bg-amber-100 text-amber-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {deletionCounts.pending}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setHrEmplocTab("approved")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    hrEmplocTab === "approved"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Approved</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      hrEmplocTab === "approved"
                        ? "bg-emerald-100 text-emerald-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {deletionCounts.approved}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setHrEmplocTab("rejected")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    hrEmplocTab === "rejected"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Rejected</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      hrEmplocTab === "rejected"
                        ? "bg-rose-100 text-rose-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {deletionCounts.rejected}
                  </span>
                </button>
              </div>
            </div>

            {/* Refresh */}
            <button
              type="button"
              onClick={handleRefresh}
              disabled={isDeletionRefetching || isDeletionLoading}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isDeletionRefetching ? "animate-spin text-brand-600" : ""
                }`}
              />
              <span>Refresh</span>
            </button>
          </div>
        </div>

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isDeletionLoading ? (
            <DataState
              kind="loading"
              title="Loading Deletion Requests"
              description="Fetching HR Emploc deletion requests..."
            />
          ) : isDeletionError ? (
            <DataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching deletion requests."
              onRetry={handleRefresh}
            />
          ) : filteredDeletionRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                deletionSearchQuery
                  ? "No Matching Requests"
                  : hrEmplocTab === "pending"
                  ? "No Pending Deletion Requests"
                  : hrEmplocTab === "approved"
                  ? "No Approved Deletions"
                  : "No Rejected Deletions"
              }
              description={
                deletionSearchQuery
                  ? `No requests match "${deletionSearchQuery}". Clear your search to see all items.`
                  : hrEmplocTab === "pending"
                  ? "All HR Emploc deletion requests have been reviewed and processed."
                  : hrEmplocTab === "approved"
                  ? "No approved HR Emploc deletion requests found in this queue."
                  : "No rejected HR Emploc deletion requests found in this queue."
              }
            />
          ) : (
            <HrEmplocDeletionDataTable
              requests={filteredDeletionRequests}
              tab={hrEmplocTab}
            />
          )}
        </div>
      </div>
    );
  }

  // ── 4. Headcount Approvals Queue ─────────────────────────────────────────
  if (selectedCategory === "headcount") {
    const handleRefresh = () => {
      refetch();
      refetchHeadcountCounts();
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
                  placeholder="Search store, VCode, position, requester..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
                />
              </div>

              {/* Sub-Tabs: Pending / Approved / Rejected */}
              <div className="flex items-center gap-1 rounded-lg border border-border-default bg-slate-100/80 p-1 text-xs">
                <button
                  type="button"
                  onClick={() => setHeadcountTab("pending")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    headcountTab === "pending"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Pending</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      headcountTab === "pending"
                        ? "bg-amber-100 text-amber-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {headcountCounts.pending}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setHeadcountTab("approved")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    headcountTab === "approved"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Approved</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      headcountTab === "approved"
                        ? "bg-emerald-100 text-emerald-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {headcountCounts.approved}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setHeadcountTab("rejected")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    headcountTab === "rejected"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Rejected</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      headcountTab === "rejected"
                        ? "bg-rose-100 text-rose-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {headcountCounts.rejected}
                  </span>
                </button>
              </div>
            </div>

            {/* Refresh */}
            <button
              type="button"
              onClick={handleRefresh}
              disabled={isRefetching || isLoading}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isRefetching ? "animate-spin text-brand-600" : ""
                }`}
              />
              <span>Refresh</span>
            </button>
          </div>
        </div>

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isLoading ? (
            <DataState
              kind="loading"
              title="Loading Headcount Requests"
              description="Fetching quota amendments and headcount requests..."
            />
          ) : isError ? (
            <DataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching pending headcount requests."
              onRetry={handleRefresh}
            />
          ) : filteredRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                searchQuery
                  ? "No Matching Requests"
                  : headcountTab === "pending"
                  ? "No Pending Headcount Requests"
                  : headcountTab === "approved"
                  ? "No Approved Headcount Requests"
                  : "No Rejected Headcount Requests"
              }
              description={
                searchQuery
                  ? `No requests match "${searchQuery}". Clear your search query to see all items.`
                  : headcountTab === "pending"
                  ? "All headcount requests and quota amendments have been reviewed and processed."
                  : headcountTab === "approved"
                  ? "No approved headcount requests found in this queue."
                  : "No rejected headcount requests found in this queue."
              }
            />
          ) : (
            <HeadcountDataTable
              requests={filteredRequests}
              tab={headcountTab}
            />
          )}
        </div>
      </div>
    );
  }

  // ── 5. Applicant Movement Requests (AMR) Queue ───────────────────────────
  if (selectedCategory === "applicant_movements") {
    const handleRefresh = () => {
      refetchMovements();
      refetchMovementCounts();
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
                  placeholder="Search applicant, VCode, store, requester..."
                  value={movementSearchQuery}
                  onChange={(e) => setMovementSearchQuery(e.target.value)}
                  className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
                />
              </div>

              {/* Sub-Tabs: Pending / Approved / Rejected */}
              <div className="flex items-center gap-1 rounded-lg border border-border-default bg-slate-100/80 p-1 text-xs">
                <button
                  type="button"
                  onClick={() => setMovementTab("pending")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    movementTab === "pending"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Pending</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      movementTab === "pending"
                        ? "bg-amber-100 text-amber-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {movementCounts.pending}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setMovementTab("approved")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    movementTab === "approved"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Approved</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      movementTab === "approved"
                        ? "bg-emerald-100 text-emerald-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {movementCounts.approved}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setMovementTab("rejected")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    movementTab === "rejected"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Rejected</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      movementTab === "rejected"
                        ? "bg-rose-100 text-rose-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {movementCounts.rejected}
                  </span>
                </button>
              </div>
            </div>

            {/* Refresh */}
            <button
              type="button"
              onClick={handleRefresh}
              disabled={isMovementRefetching || isMovementLoading}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isMovementRefetching ? "animate-spin text-brand-600" : ""
                }`}
              />
              <span>Refresh</span>
            </button>
          </div>
        </div>

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isMovementLoading ? (
            <DataState
              kind="loading"
              title="Loading Applicant Movement Requests"
              description="Fetching candidate transfer and swap requisitions..."
            />
          ) : isMovementError ? (
            <DataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching pending applicant movements."
              onRetry={handleRefresh}
            />
          ) : filteredMovementRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                movementSearchQuery
                  ? "No Matching Movement Requests"
                  : movementTab === "pending"
                  ? "No Pending Movement Requests"
                  : movementTab === "approved"
                  ? "No Approved Movement Requests"
                  : "No Rejected Movement Requests"
              }
              description={
                movementSearchQuery
                  ? `No requests match "${movementSearchQuery}". Clear your search query to see all items.`
                  : movementTab === "pending"
                  ? "All applicant transfer and swap requests have been reviewed and resolved."
                  : movementTab === "approved"
                  ? "No approved applicant movements found in this queue."
                  : "No rejected applicant movements found in this queue."
              }
            />
          ) : (
            <ApplicantMovementDataTable
              requests={filteredMovementRequests}
              tab={movementTab}
            />
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
    const handleRefresh = () => {
      refetchTransfers();
      refetchTransferCounts();
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
                  placeholder="Search account, group, AGT-#, requester..."
                  value={transferSearchQuery}
                  onChange={(e) => setTransferSearchQuery(e.target.value)}
                  className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
                />
              </div>

              {/* Sub-Tabs: Pending / Approved / Rejected */}
              <div className="flex items-center gap-1 rounded-lg border border-border-default bg-slate-100/80 p-1 text-xs">
                <button
                  type="button"
                  onClick={() => setTransferTab("pending")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    transferTab === "pending"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Pending</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      transferTab === "pending"
                        ? "bg-amber-100 text-amber-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {transferCounts.pending}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setTransferTab("approved")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    transferTab === "approved"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Approved</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      transferTab === "approved"
                        ? "bg-emerald-100 text-emerald-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {transferCounts.approved}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setTransferTab("rejected")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    transferTab === "rejected"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Rejected</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      transferTab === "rejected"
                        ? "bg-rose-100 text-rose-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {transferCounts.rejected}
                  </span>
                </button>
              </div>
            </div>

            {/* Refresh */}
            <button
              type="button"
              onClick={handleRefresh}
              disabled={isTransferRefetching || isTransferLoading}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isTransferRefetching ? "animate-spin text-brand-600" : ""
                }`}
              />
              <span>Refresh</span>
            </button>
          </div>
        </div>

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isTransferLoading ? (
            <DataState
              kind="loading"
              title="Loading Account Group Transfers"
              description="Fetching account group reassignments and simulation snapshots..."
            />
          ) : isTransferError ? (
            <DataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching account group transfers."
              onRetry={handleRefresh}
            />
          ) : filteredTransferRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                transferSearchQuery
                  ? "No Matching Account Group Transfers"
                  : transferTab === "pending"
                  ? "No Pending Account Group Transfers"
                  : transferTab === "approved"
                  ? "No Approved Account Transfers"
                  : "No Rejected Account Transfers"
              }
              description={
                transferSearchQuery
                  ? `No requests match "${transferSearchQuery}". Clear your search query to see all items.`
                  : transferTab === "pending"
                  ? "All organizational account group reassignments have been processed."
                  : transferTab === "approved"
                  ? "No approved account group transfer requests found in this queue."
                  : "No rejected account group transfer requests found in this queue."
              }
            />
          ) : (
            <AccountTransferDataTable
              requests={filteredTransferRequests}
              tab={transferTab}
            />
          )}
        </div>
      </div>
    );
  }

  // ── 8. Roving Coverage Groups Review Queue ──────────────────────────────
  if (selectedCategory === "coverage") {
    const handleRefresh = () => {
      refetchRoving();
      refetchCoverageCounts();
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
                  placeholder="Search group name, code, account, requester..."
                  value={rovingSearchQuery}
                  onChange={(e) => setRovingSearchQuery(e.target.value)}
                  className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
                />
              </div>

              {/* Sub-Tabs: Pending / Approved / Rejected */}
              <div className="flex items-center gap-1 rounded-lg border border-border-default bg-slate-100/80 p-1 text-xs">
                <button
                  type="button"
                  onClick={() => setCoverageTab("pending")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    coverageTab === "pending"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Pending</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      coverageTab === "pending"
                        ? "bg-amber-100 text-amber-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {coverageCounts.pending}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setCoverageTab("approved")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    coverageTab === "approved"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Approved</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      coverageTab === "approved"
                        ? "bg-emerald-100 text-emerald-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {coverageCounts.approved}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setCoverageTab("rejected")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    coverageTab === "rejected"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Rejected</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      coverageTab === "rejected"
                        ? "bg-rose-100 text-rose-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {coverageCounts.rejected}
                  </span>
                </button>
              </div>
            </div>

            {/* Refresh */}
            <button
              type="button"
              onClick={handleRefresh}
              disabled={isRovingRefetching || isRovingLoading}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isRovingRefetching ? "animate-spin text-brand-600" : ""
                }`}
              />
              <span>Refresh</span>
            </button>
          </div>
        </div>

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isRovingLoading ? (
            <DataState
              kind="loading"
              title="Loading Roving Coverage Groups"
              description="Fetching coverage group structural requests..."
            />
          ) : isRovingError ? (
            <DataState
              kind="error"
              title="Failed to Load Coverage Requests"
              description="An error occurred while fetching pending coverage requests."
              onRetry={handleRefresh}
            />
          ) : filteredRovingRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                rovingSearchQuery
                  ? "No Matching Coverage Group Requests"
                  : coverageTab === "pending"
                  ? "No Pending Coverage Group Requests"
                  : coverageTab === "approved"
                  ? "No Approved Coverage Requests"
                  : "No Rejected Coverage Requests"
              }
              description={
                rovingSearchQuery
                  ? `No requests match "${rovingSearchQuery}". Clear your search query to see all items.`
                  : coverageTab === "pending"
                  ? "All CENCOM roving coverage group structural requests have been processed."
                  : coverageTab === "approved"
                  ? "No approved coverage group requests found in this queue."
                  : "No rejected coverage group requests found in this queue."
              }
            />
          ) : (
            <CoverageDataTable
              requests={filteredRovingRequests}
              tab={coverageTab}
            />
          )}
        </div>
      </div>
    );
  }

  // ── 9. Reliever Endorsements Review Queue ────────────────────────────────
  if (selectedCategory === "relievers") {
    const handleRefresh = () => {
      refetchRelievers();
      refetchRelieverCounts();
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
                  placeholder="Search reliever name, ID, store, account, requester..."
                  value={relieverSearchQuery}
                  onChange={(e) => setRelieverSearchQuery(e.target.value)}
                  className="h-8 w-full rounded-md border border-border-default bg-white pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
                />
              </div>

              {/* Sub-Tabs: Pending / Approved / Rejected */}
              <div className="flex items-center gap-1 rounded-lg border border-border-default bg-slate-100/80 p-1 text-xs">
                <button
                  type="button"
                  onClick={() => setRelieverTab("pending")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    relieverTab === "pending"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Pending</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      relieverTab === "pending"
                        ? "bg-amber-100 text-amber-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {relieverCounts.pending}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setRelieverTab("approved")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    relieverTab === "approved"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Approved</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      relieverTab === "approved"
                        ? "bg-emerald-100 text-emerald-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {relieverCounts.approved}
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setRelieverTab("rejected")}
                  className={`flex items-center gap-1.5 rounded-md px-3 py-1 font-medium transition ${
                    relieverTab === "rejected"
                      ? "bg-white text-text-primary shadow-2xs font-semibold"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Rejected</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10px] font-mono font-semibold ${
                      relieverTab === "rejected"
                        ? "bg-rose-100 text-rose-800"
                        : "bg-slate-200/80 text-text-muted"
                    }`}
                  >
                    {relieverCounts.rejected}
                  </span>
                </button>
              </div>
            </div>

            {/* Refresh */}
            <button
              type="button"
              onClick={handleRefresh}
              disabled={isRelieverRefetching || isRelieverLoading}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isRelieverRefetching ? "animate-spin text-brand-600" : ""
                }`}
              />
              <span>Refresh</span>
            </button>
          </div>
        </div>

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isRelieverLoading ? (
            <DataState
              kind="loading"
              title="Loading Reliever Deployments"
              description="Fetching reliever endorsement requests from workforce pool..."
            />
          ) : isRelieverError ? (
            <DataState
              kind="error"
              title="Failed to Load Reliever Deployments"
              description="An error occurred while fetching pending reliever endorsement requests."
              onRetry={handleRefresh}
            />
          ) : filteredRelieverRequests.length === 0 ? (
            <DataState
              kind="empty"
              title={
                relieverSearchQuery
                  ? "No Matching Reliever Endorsements"
                  : relieverTab === "pending"
                  ? "No Pending Reliever Endorsements"
                  : relieverTab === "approved"
                  ? "No Approved Reliever Deployments"
                  : "No Rejected Reliever Deployments"
              }
              description={
                relieverSearchQuery
                  ? `No requests match "${relieverSearchQuery}". Clear your search query to see all items.`
                  : relieverTab === "pending"
                  ? "All workforce pool reliever endorsements have been processed."
                  : relieverTab === "approved"
                  ? "No approved reliever endorsements found in this queue."
                  : "No rejected reliever endorsements found in this queue."
              }
            />
          ) : (
            <RelieverDataTable
              requests={filteredRelieverRequests}
              tab={relieverTab}
            />
          )}
        </div>
      </div>
    );
  }

  // ── Fallback Pane for Unmapped Categories ────────────────────────────────
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
