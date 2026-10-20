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
import { ApprovalsDataState } from "@/components/approvals/ApprovalsDataState";
import { AccountRequestDataTable } from "@/components/approvals/AccountRequestDataTable";
import { AccountTransferDataTable } from "@/components/approvals/AccountTransferDataTable";
import { ApplicantMovementDataTable } from "@/components/approvals/ApplicantMovementDataTable";
import { CoverageDataTable } from "@/components/approvals/CoverageDataTable";
import { DeactivationDataTable } from "@/components/approvals/DeactivationDataTable";
import { HeadcountDataTable } from "@/components/approvals/HeadcountDataTable";
import { HrEmplocDeletionDataTable } from "@/components/approvals/HrEmplocDeletionDataTable";
import { NewStoreDataTable } from "@/components/approvals/NewStoreDataTable";
import { PlantillaApprovalDataTable } from "@/components/approvals/PlantillaApprovalDataTable";
import { RelieverDataTable } from "@/components/approvals/RelieverDataTable";
import { VacancyClosureDataTable } from "@/components/approvals/VacancyClosureDataTable";
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
  usePlantillaApprovals,
  usePlantillaApprovalCounts,
  type RequestCategoryCounts,
  type RequestCategoryKey,
} from "@/lib/queries/requests";
import {
  useAccountApprovalQueue,
  useAccountRequestCounts,
  type AccountRequestStatus,
} from "@/lib/queries/accountRequests";
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

interface QueueToolbarProps<T extends string = ApprovalStatusTab> {
  searchQuery: string;
  onSearchChange: (val: string) => void;
  searchPlaceholder?: string;
  currentTab: T;
  onTabChange: (tab: T) => void;
  counts?: { pending: number; approved: number; rejected: number };
  isCountsLoading?: boolean;
  isCountsError?: boolean;
  approvedLabel?: string;
  onRefresh: () => void;
  isRefreshing: boolean;
  isLoading: boolean;
}

function QueueToolbar<T extends string = ApprovalStatusTab>({
  searchQuery,
  onSearchChange,
  searchPlaceholder = "Filter requests...",
  currentTab,
  onTabChange,
  counts,
  isCountsLoading = false,
  isCountsError = false,
  approvedLabel = "Approved",
  onRefresh,
  isRefreshing,
  isLoading,
}: QueueToolbarProps<T>) {
  const renderBadge = (count: number | undefined, tabName: T) => {
    if (isCountsLoading) {
      return (
        <span className="ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold text-text-muted">
          ...
        </span>
      );
    }
    if (isCountsError || count === undefined) {
      return (
        <span className="ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold text-text-muted">
          —
        </span>
      );
    }
    const isSelected = currentTab === tabName;
    return (
      <span
        className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold shadow-2xs transition-colors ${
          isSelected
            ? "bg-brand-600 text-white"
            : "bg-slate-100 text-slate-600 border border-slate-200/80"
        }`}
      >
        {count}
      </span>
    );
  };

  return (
    <div className="border-b border-[var(--line)] pb-3">
      {/* Search / Filter Strip with Refresh */}
      <div className="flex items-center justify-between gap-3">
        <div className="relative w-72 sm:w-80">
          <Search className="pointer-events-none absolute left-2.5 top-2.5 h-3.5 w-3.5 text-[var(--muted)]" />
          <input
            type="text"
            placeholder={searchPlaceholder}
            value={searchQuery}
            onChange={(e) => onSearchChange(e.target.value)}
            className="h-8 w-full rounded-[9px] border border-[var(--line)] bg-[var(--bg)] pl-8 pr-3 text-xs text-[var(--text)] placeholder:text-[var(--muted)] focus:border-[var(--text)] focus:outline-hidden"
          />
        </div>

        {/* Refresh */}
        <button
          type="button"
          onClick={onRefresh}
          disabled={isRefreshing || isLoading}
          className="inline-flex h-8 items-center gap-1.5 rounded-[9px] border border-[var(--line)] bg-transparent px-3 text-xs font-normal text-[var(--muted)] hover:text-[var(--text)] hover:border-[var(--text)] disabled:opacity-50 transition cursor-pointer"
        >
          <RefreshCw
            className={`h-3 w-3 ${
              isRefreshing ? "animate-spin text-[var(--text)]" : ""
            }`}
          />
          <span>Refresh</span>
        </button>
      </div>

      {/* Sub-Tabs directly below the search/filter strip */}
      <div className="mt-3 flex items-center gap-1.5 overflow-x-auto no-scrollbar scrollbar-none" role="tablist">
        <button
          type="button"
          role="tab"
          aria-selected={currentTab === "pending"}
          onClick={() => onTabChange("pending" as T)}
          className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
            currentTab === "pending"
              ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
              : "border-transparent bg-transparent text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary"
          }`}
        >
          <span>Pending</span>
          {renderBadge(counts?.pending, "pending" as T)}
        </button>

        <button
          type="button"
          role="tab"
          aria-selected={currentTab === "approved"}
          onClick={() => onTabChange("approved" as T)}
          className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
            currentTab === "approved"
              ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
              : "border-transparent bg-transparent text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary"
          }`}
        >
          <span>{approvedLabel}</span>
          {renderBadge(counts?.approved, "approved" as T)}
        </button>

        <button
          type="button"
          role="tab"
          aria-selected={currentTab === "rejected"}
          onClick={() => onTabChange("rejected" as T)}
          className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
            currentTab === "rejected"
              ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
              : "border-transparent bg-transparent text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary"
          }`}
        >
          <span>Rejected</span>
          {renderBadge(counts?.rejected, "rejected" as T)}
        </button>
      </div>
    </div>
  );
}

export function ActiveQueueReviewPane({
  selectedCategory,
  onSelectCategory,
  counts,
}: ActiveQueueReviewPaneProps) {
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
  const [plantillaTab, setPlantillaTab] = useState<ApprovalStatusTab>("pending");
  const [accountTab, setAccountTab] = useState<AccountRequestStatus>("pending");

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
  const [plantillaSearchQuery, setPlantillaSearchQuery] = useState("");
  const [accountSearchQuery, setAccountSearchQuery] = useState("");

  // ── Unified Pagination State (Vacancy Parity) ───────────────────────────
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(10);

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
    data: headcountCounts,
    isLoading: isHeadcountCountsLoading,
    isError: isHeadcountCountsError,
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
    data: deletionCounts,
    isLoading: isDeletionCountsLoading,
    isError: isDeletionCountsError,
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
    data: newStoreCounts,
    isLoading: isNewStoreCountsLoading,
    isError: isNewStoreCountsError,
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
    data: closureCounts,
    isLoading: isClosureCountsLoading,
    isError: isClosureCountsError,
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
    data: movementCounts,
    isLoading: isMovementCountsLoading,
    isError: isMovementCountsError,
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
    data: deactCounts,
    isLoading: isDeactCountsLoading,
    isError: isDeactCountsError,
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
    data: transferCounts,
    isLoading: isTransferCountsLoading,
    isError: isTransferCountsError,
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
    data: relieverCounts,
    isLoading: isRelieverCountsLoading,
    isError: isRelieverCountsError,
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
    data: coverageCounts,
    isLoading: isCoverageCountsLoading,
    isError: isCoverageCountsError,
    refetch: refetchCoverageCounts,
  } = useCoverageCounts();

  // 10. Plantilla Approvals (Candidate Deployments)
  const {
    data: plantillaRequests = [],
    isLoading: isPlantillaLoading,
    isError: isPlantillaError,
    refetch: refetchPlantilla,
    isRefetching: isPlantillaRefetching,
  } = usePlantillaApprovals(plantillaTab);

  const {
    data: plantillaCounts,
    isLoading: isPlantillaCountsLoading,
    isError: isPlantillaCountsError,
    refetch: refetchPlantillaCounts,
  } = usePlantillaApprovalCounts();

  // 11. Account Sign-Up Requests
  const {
    data: accountRequests = [],
    isLoading: isAccountLoading,
    isError: isAccountError,
    refetch: refetchAccount,
    isRefetching: isAccountRefetching,
  } = useAccountApprovalQueue(accountTab);

  const {
    data: accountCounts,
    isLoading: isAccountCountsLoading,
    isError: isAccountCountsError,
    refetch: refetchAccountCounts,
  } = useAccountRequestCounts();

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

  const filteredPlantillaRequests = useMemo(() => {
    if (!plantillaSearchQuery.trim()) return plantillaRequests;
    const q = plantillaSearchQuery.toLowerCase();
    return plantillaRequests.filter((req) => {
      return (
        req.applicantName.toLowerCase().includes(q) ||
        req.vcode.toLowerCase().includes(q) ||
        req.account.toLowerCase().includes(q) ||
        req.position.toLowerCase().includes(q) ||
        req.emplocNo.toLowerCase().includes(q) ||
        req.requestedBy.toLowerCase().includes(q) ||
        (req.reviewedBy?.toLowerCase().includes(q) ?? false) ||
        (req.remarks?.toLowerCase().includes(q) ?? false)
      );
    });
  }, [plantillaRequests, plantillaSearchQuery]);

  const filteredAccountRequests = useMemo(() => {
    if (!accountSearchQuery.trim()) return accountRequests;
    const q = accountSearchQuery.toLowerCase();
    return accountRequests.filter((req) => {
      return (
        req.fullName.toLowerCase().includes(q) ||
        req.email.toLowerCase().includes(q) ||
        (req.mobileNumber && req.mobileNumber.toLowerCase().includes(q)) ||
        (req.requestedRoleName && req.requestedRoleName.toLowerCase().includes(q)) ||
        (req.notes && req.notes.toLowerCase().includes(q)) ||
        (req.rejectionReason && req.rejectionReason.toLowerCase().includes(q)) ||
        (req.reviewerDisplayName && req.reviewerDisplayName.toLowerCase().includes(q))
      );
    });
  }, [accountRequests, accountSearchQuery]);

  // ── 1. New Store Requests Queue ──────────────────────────────────────────
  if (selectedCategory === "new_stores") {
    const handleRefresh = () => {
      refetchNewStores();
      refetchNewStoreCounts();
    };

    return (
      <div className="flex h-full flex-col">
        <QueueToolbar
          searchQuery={newStoreSearchQuery}
          onSearchChange={(val) => {
            setNewStoreSearchQuery(val);
            setPage(1);
          }}
          searchPlaceholder="Search store, account, city, province, requester..."
          currentTab={newStoreTab}
          onTabChange={(tab) => {
            setNewStoreTab(tab);
            setPage(1);
          }}
          counts={newStoreCounts}
          isCountsLoading={isNewStoreCountsLoading}
          isCountsError={isNewStoreCountsError}
          onRefresh={handleRefresh}
          isRefreshing={isNewStoreRefetching}
          isLoading={isNewStoreLoading}
        />

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isNewStoreLoading ? (
            <ApprovalsDataState
              kind="loading"
              title="Loading New Store Requests"
              description="Fetching new store addition requests..."
            />
          ) : isNewStoreError ? (
            <ApprovalsDataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching new store requests."
              onRetry={handleRefresh}
            />
          ) : filteredNewStoreRequests.length === 0 ? (
            <ApprovalsDataState
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
              page={page}
              pageSize={pageSize}
              totalCount={filteredNewStoreRequests.length}
              onPageChange={setPage}
              onPageSizeChange={(newSize) => {
                setPageSize(newSize);
                setPage(1);
              }}
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
        <QueueToolbar
          searchQuery={vacancyClosureSearchQuery}
          onSearchChange={(val) => {
            setVacancyClosureSearchQuery(val);
            setPage(1);
          }}
          searchPlaceholder="Search VCode, store, position, requester..."
          currentTab={vacancyClosureTab}
          onTabChange={(tab) => {
            setVacancyClosureTab(tab);
            setPage(1);
          }}
          counts={closureCounts}
          isCountsLoading={isClosureCountsLoading}
          isCountsError={isClosureCountsError}
          onRefresh={handleRefresh}
          isRefreshing={isClosureRefetching}
          isLoading={isClosureLoading}
        />

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isClosureLoading ? (
            <ApprovalsDataState
              kind="loading"
              title="Loading Vacancy Closures"
              description="Fetching vacancy closure requests..."
            />
          ) : isClosureError ? (
            <ApprovalsDataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching vacancy closure requests."
              onRetry={handleRefresh}
            />
          ) : filteredClosureRequests.length === 0 ? (
            <ApprovalsDataState
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
              page={page}
              pageSize={pageSize}
              totalCount={filteredClosureRequests.length}
              onPageChange={setPage}
              onPageSizeChange={(newSize) => {
                setPageSize(newSize);
                setPage(1);
              }}
            />
          )}
        </div>
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
        <QueueToolbar
          searchQuery={deletionSearchQuery}
          onSearchChange={(val) => {
            setDeletionSearchQuery(val);
            setPage(1);
          }}
          searchPlaceholder="Search employee, VCode, store, requester..."
          currentTab={hrEmplocTab}
          onTabChange={(tab) => {
            setHrEmplocTab(tab);
            setPage(1);
          }}
          counts={deletionCounts}
          isCountsLoading={isDeletionCountsLoading}
          isCountsError={isDeletionCountsError}
          onRefresh={handleRefresh}
          isRefreshing={isDeletionRefetching}
          isLoading={isDeletionLoading}
        />

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isDeletionLoading ? (
            <ApprovalsDataState
              kind="loading"
              title="Loading Deletion Requests"
              description="Fetching HR Emploc deletion requests..."
            />
          ) : isDeletionError ? (
            <ApprovalsDataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching deletion requests."
              onRetry={handleRefresh}
            />
          ) : filteredDeletionRequests.length === 0 ? (
            <ApprovalsDataState
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
              page={page}
              pageSize={pageSize}
              totalCount={filteredDeletionRequests.length}
              onPageChange={setPage}
              onPageSizeChange={(newSize) => {
                setPageSize(newSize);
                setPage(1);
              }}
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
        <QueueToolbar
          searchQuery={searchQuery}
          onSearchChange={(val) => {
            setSearchQuery(val);
            setPage(1);
          }}
          searchPlaceholder="Search store, VCode, position, requester..."
          currentTab={headcountTab}
          onTabChange={(tab) => {
            setHeadcountTab(tab);
            setPage(1);
          }}
          counts={headcountCounts}
          isCountsLoading={isHeadcountCountsLoading}
          isCountsError={isHeadcountCountsError}
          onRefresh={handleRefresh}
          isRefreshing={isRefetching}
          isLoading={isLoading}
        />

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isLoading ? (
            <ApprovalsDataState
              kind="loading"
              title="Loading Headcount Requests"
              description="Fetching quota amendments and headcount requests..."
            />
          ) : isError ? (
            <ApprovalsDataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching pending headcount requests."
              onRetry={handleRefresh}
            />
          ) : filteredRequests.length === 0 ? (
            <ApprovalsDataState
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
              page={page}
              pageSize={pageSize}
              totalCount={filteredRequests.length}
              onPageChange={setPage}
              onPageSizeChange={(newSize) => {
                setPageSize(newSize);
                setPage(1);
              }}
            />
          )}
        </div>
      </div>
    );
  }

  // ── 5. Plantilla Placements Queue (Candidate Deployments) ─────────────────
  if (selectedCategory === "plantilla_approvals") {
    const handleRefresh = () => {
      refetchPlantilla();
      refetchPlantillaCounts();
    };

    return (
      <div className="flex h-full flex-col">
        <QueueToolbar
          searchQuery={plantillaSearchQuery}
          onSearchChange={(val) => {
            setPlantillaSearchQuery(val);
            setPage(1);
          }}
          searchPlaceholder="Search candidate, VCode, account, position, requester..."
          currentTab={plantillaTab}
          onTabChange={(tab) => {
            setPlantillaTab(tab);
            setPage(1);
          }}
          counts={plantillaCounts}
          isCountsLoading={isPlantillaCountsLoading}
          isCountsError={isPlantillaCountsError}
          onRefresh={handleRefresh}
          isRefreshing={isPlantillaRefetching}
          isLoading={isPlantillaLoading}
        />

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isPlantillaLoading ? (
            <ApprovalsDataState
              kind="loading"
              title="Loading Plantilla Deployments"
              description="Fetching pending candidate deployment approvals..."
            />
          ) : isPlantillaError ? (
            <ApprovalsDataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching candidate plantilla approvals."
              onRetry={handleRefresh}
            />
          ) : filteredPlantillaRequests.length === 0 ? (
            <ApprovalsDataState
              kind="empty"
              title={
                plantillaSearchQuery
                  ? "No Matching Requests"
                  : plantillaTab === "pending"
                  ? "No Pending Candidate Deployments"
                  : plantillaTab === "approved"
                  ? "No Approved Candidate Deployments"
                  : "No Rejected Candidate Deployments"
              }
              description={
                plantillaSearchQuery
                  ? `No requests match "${plantillaSearchQuery}". Clear your search query to see all items.`
                  : plantillaTab === "pending"
                  ? "All candidate plantilla placement requests have been reviewed and processed."
                  : plantillaTab === "approved"
                  ? "No approved candidate deployments found in this queue."
                  : "No rejected candidate deployments found in this queue."
              }
            />
          ) : (
            <PlantillaApprovalDataTable
              requests={filteredPlantillaRequests}
              tab={plantillaTab}
              page={page}
              pageSize={pageSize}
              totalCount={filteredPlantillaRequests.length}
              onPageChange={setPage}
              onPageSizeChange={(newSize) => {
                setPageSize(newSize);
                setPage(1);
              }}
            />
          )}
        </div>
      </div>
    );
  }

  // ── 6. Account Sign-Up Requests Queue ─────────────────────────────────────
  if (selectedCategory === "account_requests") {
    const handleRefresh = () => {
      refetchAccount();
      refetchAccountCounts();
    };

    return (
      <div className="flex h-full flex-col">
        <QueueToolbar<AccountRequestStatus>
          searchQuery={accountSearchQuery}
          onSearchChange={(val) => {
            setAccountSearchQuery(val);
            setPage(1);
          }}
          searchPlaceholder="Search applicant, email, phone, requested role..."
          currentTab={accountTab}
          onTabChange={(tab) => {
            setAccountTab(tab);
            setPage(1);
          }}
          counts={accountCounts}
          isCountsLoading={isAccountCountsLoading}
          isCountsError={isAccountCountsError}
          onRefresh={handleRefresh}
          isRefreshing={isAccountRefetching}
          isLoading={isAccountLoading}
        />

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isAccountLoading ? (
            <ApprovalsDataState
              kind="loading"
              title="Loading Account Sign-Up Requests"
              description="Fetching pending user registration and access requests..."
            />
          ) : isAccountError ? (
            <ApprovalsDataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching account sign-up requests."
              onRetry={handleRefresh}
            />
          ) : filteredAccountRequests.length === 0 ? (
            <ApprovalsDataState
              kind="empty"
              title={
                accountSearchQuery
                  ? "No Matching Requests"
                  : accountTab === "pending"
                  ? "No Pending Sign-Up Requests"
                  : accountTab === "approved"
                  ? "No Approved Sign-Up Requests"
                  : "No Rejected Sign-Up Requests"
              }
              description={
                accountSearchQuery
                  ? `No requests match "${accountSearchQuery}". Clear your search query to see all items.`
                  : accountTab === "pending"
                  ? "All user registration requests have been reviewed and provisioned."
                  : accountTab === "approved"
                  ? "No approved account requests found in this queue."
                  : "No rejected account requests found in this queue."
              }
            />
          ) : (
            <AccountRequestDataTable
              requests={filteredAccountRequests}
              tab={accountTab}
              page={page}
              pageSize={pageSize}
              totalCount={filteredAccountRequests.length}
              onPageChange={setPage}
              onPageSizeChange={(newSize) => {
                setPageSize(newSize);
                setPage(1);
              }}
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
        <QueueToolbar
          searchQuery={movementSearchQuery}
          onSearchChange={(val) => {
            setMovementSearchQuery(val);
            setPage(1);
          }}
          searchPlaceholder="Search applicant, VCode, store, requester..."
          currentTab={movementTab}
          onTabChange={(tab) => {
            setMovementTab(tab);
            setPage(1);
          }}
          counts={movementCounts}
          isCountsLoading={isMovementCountsLoading}
          isCountsError={isMovementCountsError}
          onRefresh={handleRefresh}
          isRefreshing={isMovementRefetching}
          isLoading={isMovementLoading}
        />

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isMovementLoading ? (
            <ApprovalsDataState
              kind="loading"
              title="Loading Applicant Movement Requests"
              description="Fetching candidate transfer and swap requisitions..."
            />
          ) : isMovementError ? (
            <ApprovalsDataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching pending applicant movements."
              onRetry={handleRefresh}
            />
          ) : filteredMovementRequests.length === 0 ? (
            <ApprovalsDataState
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
              page={page}
              pageSize={pageSize}
              totalCount={filteredMovementRequests.length}
              onPageChange={setPage}
              onPageSizeChange={(newSize) => {
                setPageSize(newSize);
                setPage(1);
              }}
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
        <QueueToolbar<DeactivationStatusTab>
          searchQuery={deactivationSearchQuery}
          onSearchChange={(val) => {
            setDeactivationSearchQuery(val);
            setPage(1);
          }}
          searchPlaceholder="Search employee, ID, store, position, account..."
          currentTab={deactivationTab}
          onTabChange={(tab) => {
            setDeactivationTab(tab);
            setPage(1);
          }}
          counts={deactCounts}
          isCountsLoading={isDeactCountsLoading}
          isCountsError={isDeactCountsError}
          approvedLabel="Deactivated"
          onRefresh={handleRefreshDeactivations}
          isRefreshing={isDeactRefetching}
          isLoading={isDeactLoading}
        />

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isDeactLoading ? (
            <ApprovalsDataState
              kind="loading"
              title="Loading Deactivation Requests"
              description="Fetching live employee deactivation and separation clearance requests..."
            />
          ) : isDeactError ? (
            <ApprovalsDataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching deactivation requests."
              onRetry={handleRefreshDeactivations}
            />
          ) : filteredDeactivationRequests.length === 0 ? (
            <ApprovalsDataState
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
              page={page}
              pageSize={pageSize}
              totalCount={filteredDeactivationRequests.length}
              onPageChange={setPage}
              onPageSizeChange={(newSize) => {
                setPageSize(newSize);
                setPage(1);
              }}
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
        <QueueToolbar
          searchQuery={transferSearchQuery}
          onSearchChange={(val) => {
            setTransferSearchQuery(val);
            setPage(1);
          }}
          searchPlaceholder="Search account, group, AGT-#, requester..."
          currentTab={transferTab}
          onTabChange={(tab) => {
            setTransferTab(tab);
            setPage(1);
          }}
          counts={transferCounts}
          isCountsLoading={isTransferCountsLoading}
          isCountsError={isTransferCountsError}
          onRefresh={handleRefresh}
          isRefreshing={isTransferRefetching}
          isLoading={isTransferLoading}
        />

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isTransferLoading ? (
            <ApprovalsDataState
              kind="loading"
              title="Loading Account Group Transfers"
              description="Fetching account group reassignments and simulation snapshots..."
            />
          ) : isTransferError ? (
            <ApprovalsDataState
              kind="error"
              title="Failed to Load Queue"
              description="An error occurred while fetching account group transfers."
              onRetry={handleRefresh}
            />
          ) : filteredTransferRequests.length === 0 ? (
            <ApprovalsDataState
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
              page={page}
              pageSize={pageSize}
              totalCount={filteredTransferRequests.length}
              onPageChange={setPage}
              onPageSizeChange={(newSize) => {
                setPageSize(newSize);
                setPage(1);
              }}
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
        <QueueToolbar
          searchQuery={rovingSearchQuery}
          onSearchChange={(val) => {
            setRovingSearchQuery(val);
            setPage(1);
          }}
          searchPlaceholder="Search group name, code, account, requester..."
          currentTab={coverageTab}
          onTabChange={(tab) => {
            setCoverageTab(tab);
            setPage(1);
          }}
          counts={coverageCounts}
          isCountsLoading={isCoverageCountsLoading}
          isCountsError={isCoverageCountsError}
          onRefresh={handleRefresh}
          isRefreshing={isRovingRefetching}
          isLoading={isRovingLoading}
        />

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isRovingLoading ? (
            <ApprovalsDataState
              kind="loading"
              title="Loading Roving Coverage Groups"
              description="Fetching coverage group structural requests..."
            />
          ) : isRovingError ? (
            <ApprovalsDataState
              kind="error"
              title="Failed to Load Coverage Requests"
              description="An error occurred while fetching pending coverage requests."
              onRetry={handleRefresh}
            />
          ) : filteredRovingRequests.length === 0 ? (
            <ApprovalsDataState
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
              page={page}
              pageSize={pageSize}
              totalCount={filteredRovingRequests.length}
              onPageChange={setPage}
              onPageSizeChange={(newSize) => {
                setPageSize(newSize);
                setPage(1);
              }}
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
        <QueueToolbar
          searchQuery={relieverSearchQuery}
          onSearchChange={(val) => {
            setRelieverSearchQuery(val);
            setPage(1);
          }}
          searchPlaceholder="Search reliever name, ID, store, account, requester..."
          currentTab={relieverTab}
          onTabChange={(tab) => {
            setRelieverTab(tab);
            setPage(1);
          }}
          counts={relieverCounts}
          isCountsLoading={isRelieverCountsLoading}
          isCountsError={isRelieverCountsError}
          onRefresh={handleRefresh}
          isRefreshing={isRelieverRefetching}
          isLoading={isRelieverLoading}
        />

        {/* Requests List Area */}
        <div className="mt-4 flex-1 min-h-0 flex flex-col">
          {isRelieverLoading ? (
            <ApprovalsDataState
              kind="loading"
              title="Loading Reliever Deployments"
              description="Fetching reliever endorsement requests from workforce pool..."
            />
          ) : isRelieverError ? (
            <ApprovalsDataState
              kind="error"
              title="Failed to Load Reliever Deployments"
              description="An error occurred while fetching pending reliever endorsement requests."
              onRetry={handleRefresh}
            />
          ) : filteredRelieverRequests.length === 0 ? (
            <ApprovalsDataState
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
              page={page}
              pageSize={pageSize}
              totalCount={filteredRelieverRequests.length}
              onPageChange={setPage}
              onPageSizeChange={(newSize) => {
                setPageSize(newSize);
                setPage(1);
              }}
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
