"use client";

import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Archive,
  ArrowLeftRight,
  ArrowRight,
  Briefcase,
  ChevronDown,
  ChevronRight,
  GitFork,
  Layers,
  MapPin,
  RefreshCw,
  Search,
  Store,
  UserCheck,
  UserMinus,
  UserPlus,
  Users,
  UserX,
} from "lucide-react";
import { ApprovalsDataState } from "@/components/approvals/ApprovalsDataState";
import { AccountArchiveDataTable } from "@/components/approvals/AccountArchiveDataTable";
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
  type ApprovalStatusTab,
  type RequestCategoryKey,
  type HeadcountRequestItem,
  type NewStoreRequestItem,
  type VacancyClosureRequestItem,
  type ApplicantMovementRequestItem,
  type DeactivationRequestItem,
  type AccountGroupTransferItem,
  type RelieverEndorsementItem,
  type CoverageGroupRequestItem,
  type PlantillaApprovalItem,
  type AccountArchiveItem,
  fetchHeadcountRequests,
  fetchNewStoreRequests,
  fetchVacancyClosureRequests,
  fetchApplicantMovementRequests,
  fetchDeactivationRequests,
  fetchAccountGroupTransfers,
  fetchRelieverEndorsements,
  fetchCoverageRequests,
  fetchPlantillaApprovals,
  fetchAccountArchiveRequests,
} from "@/lib/queries/requests";
import {
  fetchApprovalQueue,
  type AccountRequestItem,
  type AccountRequestStatus,
} from "@/lib/queries/accountRequests";
import {
  fetchEmplocDeletionRequests,
  type EmplocDeletionRequestItem,
} from "@/lib/queries/hr_emploc";

interface AllRequestsUnifiedQueueProps {
  onSelectCategory: (key: RequestCategoryKey) => void;
  allowedCategories?: RequestCategoryKey[];
}

interface UnifiedQueuesData {
  headcount: HeadcountRequestItem[];
  deactivations: DeactivationRequestItem[];
  applicant_movements: ApplicantMovementRequestItem[];
  account_group_transfers: AccountGroupTransferItem[];
  coverage: CoverageGroupRequestItem[];
  new_stores: NewStoreRequestItem[];
  plantilla_approvals: PlantillaApprovalItem[];
  account_requests: AccountRequestItem[];
  hr_emploc_deletions: EmplocDeletionRequestItem[];
  account_archives: AccountArchiveItem[];
  relievers: RelieverEndorsementItem[];
  vacancy_closures: VacancyClosureRequestItem[];
  errors: Partial<Record<RequestCategoryKey, string>>;
}

const CATEGORY_META: Record<
  Exclude<RequestCategoryKey, "all_requests">,
  {
    label: string;
    description: string;
    icon: React.ComponentType<{ className?: string }>;
  }
> = {
  deactivations: {
    label: "Deactivations",
    description: "Employee separation clearance, backouts, and deactivation requests",
    icon: UserMinus,
  },
  headcount: {
    label: "Headcount",
    description: "Quota amendments, replacements, relievers, and capacity expansions",
    icon: Users,
  },
  coverage: {
    label: "Coverage",
    description: "Roving store allocation groups and roving schedule requests",
    icon: MapPin,
  },
  applicant_movements: {
    label: "Applicant Movements",
    description: "Cross-store applicant transfers, swap approvals, and slot reassignment",
    icon: ArrowLeftRight,
  },
  account_group_transfers: {
    label: "Account Group Transfers",
    description: "Account reassignments across operational management groups",
    icon: GitFork,
  },
  new_stores: {
    label: "New Stores",
    description: "Store registry additions and branch onboarding requests",
    icon: Store,
  },
  plantilla_approvals: {
    label: "Plantilla Placements",
    description: "Candidate endorsements and slot deployment approvals to permanent plantilla",
    icon: Briefcase,
  },
  account_requests: {
    label: "Account Sign-Ups",
    description: "Staff and user registration approval and access provisioning queue",
    icon: UserPlus,
  },
  hr_emploc_deletions: {
    label: "HR Emploc Deletions",
    description: "Employee location link and assignment expungement requests",
    icon: UserX,
  },
  account_archives: {
    label: "Account Archives",
    description: "Billing account retirement and archive approval queue",
    icon: Archive,
  },
  relievers: {
    label: "Relievers",
    description: "Temporary reliever pool deployments and workforce coverage",
    icon: UserCheck,
  },
  vacancy_closures: {
    label: "Vacancy Closures",
    description: "Position requisition retirement and closed-slot clearance requests",
    icon: Archive,
  },
};

const ALL_CATEGORY_KEYS: Array<Exclude<RequestCategoryKey, "all_requests">> = [
  "deactivations",
  "headcount",
  "coverage",
  "applicant_movements",
  "account_group_transfers",
  "new_stores",
  "plantilla_approvals",
  "account_requests",
  "hr_emploc_deletions",
  "account_archives",
  "relievers",
  "vacancy_closures",
];

const PREVIEW_CAP = 5;

export function AllRequestsUnifiedQueue({
  onSelectCategory,
  allowedCategories,
}: AllRequestsUnifiedQueueProps) {
  const queryClient = useQueryClient();
  const [currentTab, setCurrentTab] = useState<ApprovalStatusTab>("pending");
  const [searchQuery, setSearchQuery] = useState("");

  // Track explicit user accordion expansion state overrides
  const [manualExpanded, setManualExpanded] = useState<
    Record<string, boolean>
  >({});

  // Track "Show all X requests" per category section
  const [expandedAllItems, setExpandedAllItems] = useState<
    Record<string, boolean>
  >({});

  // ── Parallel resilient fetching using Promise.allSettled ─────────────────
  const {
    data: queues,
    isLoading,
    isRefetching,
    refetch,
  } = useQuery<UnifiedQueuesData>({
    queryKey: ["all-requests-unified", currentTab],
    queryFn: async () => {
      const results: UnifiedQueuesData = {
        headcount: [],
        deactivations: [],
        applicant_movements: [],
        account_group_transfers: [],
        coverage: [],
        new_stores: [],
        plantilla_approvals: [],
        account_requests: [],
        hr_emploc_deletions: [],
        account_archives: [],
        relievers: [],
        vacancy_closures: [],
        errors: {},
      };

      const [
        headcountRes,
        deactRes,
        movementRes,
        transferRes,
        coverageRes,
        newStoreRes,
        plantillaRes,
        accountRes,
        deletionRes,
        archiveRes,
        relieverRes,
        closureRes,
      ] = await Promise.allSettled([
        fetchHeadcountRequests(currentTab),
        fetchDeactivationRequests(currentTab),
        fetchApplicantMovementRequests(currentTab),
        fetchAccountGroupTransfers(currentTab),
        fetchCoverageRequests(currentTab),
        fetchNewStoreRequests(currentTab),
        fetchPlantillaApprovals(currentTab),
        fetchApprovalQueue(currentTab as AccountRequestStatus),
        fetchEmplocDeletionRequests(currentTab),
        fetchAccountArchiveRequests(currentTab).then((r) => r.data),
        fetchRelieverEndorsements(currentTab),
        fetchVacancyClosureRequests(currentTab),
      ]);

      if (headcountRes.status === "fulfilled") results.headcount = headcountRes.value;
      else results.errors.headcount = String(headcountRes.reason);

      if (deactRes.status === "fulfilled") results.deactivations = deactRes.value;
      else results.errors.deactivations = String(deactRes.reason);

      if (movementRes.status === "fulfilled") results.applicant_movements = movementRes.value;
      else results.errors.applicant_movements = String(movementRes.reason);

      if (transferRes.status === "fulfilled") results.account_group_transfers = transferRes.value;
      else results.errors.account_group_transfers = String(transferRes.reason);

      if (coverageRes.status === "fulfilled") results.coverage = coverageRes.value;
      else results.errors.coverage = String(coverageRes.reason);

      if (newStoreRes.status === "fulfilled") results.new_stores = newStoreRes.value;
      else results.errors.new_stores = String(newStoreRes.reason);

      if (plantillaRes.status === "fulfilled") results.plantilla_approvals = plantillaRes.value;
      else results.errors.plantilla_approvals = String(plantillaRes.reason);

      if (accountRes.status === "fulfilled") results.account_requests = accountRes.value;
      else results.errors.account_requests = String(accountRes.reason);

      if (deletionRes.status === "fulfilled") results.hr_emploc_deletions = deletionRes.value;
      else results.errors.hr_emploc_deletions = String(deletionRes.reason);

      if (archiveRes.status === "fulfilled") results.account_archives = archiveRes.value;
      else results.errors.account_archives = String(archiveRes.reason);

      if (relieverRes.status === "fulfilled") results.relievers = relieverRes.value;
      else results.errors.relievers = String(relieverRes.reason);

      if (closureRes.status === "fulfilled") results.vacancy_closures = closureRes.value;
      else results.errors.vacancy_closures = String(closureRes.reason);

      return results;
    },
    staleTime: 15000,
  });

  const handleRefresh = async () => {
    await Promise.all([
      refetch(),
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] }),
    ]);
  };

  // ── Global Search Filters ────────────────────────────────────────────────
  const normalizedQuery = searchQuery.trim().toLowerCase();

  const filteredData = useMemo(() => {
    if (!queues) return null;
    if (!normalizedQuery) return queues;

    return {
      headcount: queues.headcount.filter(
        (r) =>
          r.targetVcode?.toLowerCase().includes(normalizedQuery) ||
          r.storeName?.toLowerCase().includes(normalizedQuery) ||
          r.accountName?.toLowerCase().includes(normalizedQuery) ||
          r.positionName?.toLowerCase().includes(normalizedQuery) ||
          r.groupName?.toLowerCase().includes(normalizedQuery) ||
          r.requestedByName?.toLowerCase().includes(normalizedQuery) ||
          r.reason?.toLowerCase().includes(normalizedQuery)
      ),
      deactivations: queues.deactivations.filter(
        (r) =>
          r.employeeName?.toLowerCase().includes(normalizedQuery) ||
          r.employeeNo?.toLowerCase().includes(normalizedQuery) ||
          r.accountName?.toLowerCase().includes(normalizedQuery) ||
          r.groupName?.toLowerCase().includes(normalizedQuery) ||
          r.storeName?.toLowerCase().includes(normalizedQuery) ||
          r.positionTitle?.toLowerCase().includes(normalizedQuery) ||
          r.requestedByName?.toLowerCase().includes(normalizedQuery) ||
          r.remarks?.toLowerCase().includes(normalizedQuery)
      ),
      applicant_movements: queues.applicant_movements.filter(
        (r) =>
          r.requestNumber?.toLowerCase().includes(normalizedQuery) ||
          r.sourceApplicantName?.toLowerCase().includes(normalizedQuery) ||
          r.targetApplicantName?.toLowerCase().includes(normalizedQuery) ||
          r.sourceVacancyVcode?.toLowerCase().includes(normalizedQuery) ||
          r.targetVacancyVcode?.toLowerCase().includes(normalizedQuery) ||
          r.sourceAccountName?.toLowerCase().includes(normalizedQuery) ||
          r.targetAccountName?.toLowerCase().includes(normalizedQuery) ||
          r.reason?.toLowerCase().includes(normalizedQuery)
      ),
      account_group_transfers: queues.account_group_transfers.filter(
        (r) =>
          r.requestNumber?.toLowerCase().includes(normalizedQuery) ||
          r.accountName?.toLowerCase().includes(normalizedQuery) ||
          r.fromGroupName?.toLowerCase().includes(normalizedQuery) ||
          r.toGroupName?.toLowerCase().includes(normalizedQuery) ||
          r.reason?.toLowerCase().includes(normalizedQuery) ||
          r.requestedByName?.toLowerCase().includes(normalizedQuery)
      ),
      coverage: queues.coverage.filter(
        (r) =>
          r.requestType?.toLowerCase().includes(normalizedQuery) ||
          r.accountName?.toLowerCase().includes(normalizedQuery) ||
          r.targetCoverageGroupCode?.toLowerCase().includes(normalizedQuery) ||
          r.targetCoverageGroupName?.toLowerCase().includes(normalizedQuery) ||
          r.reason?.toLowerCase().includes(normalizedQuery) ||
          r.requestedByName?.toLowerCase().includes(normalizedQuery)
      ),
      new_stores: queues.new_stores.filter(
        (r) =>
          r.storeName?.toLowerCase().includes(normalizedQuery) ||
          r.province?.toLowerCase().includes(normalizedQuery) ||
          r.city?.toLowerCase().includes(normalizedQuery) ||
          r.accountName?.toLowerCase().includes(normalizedQuery) ||
          r.position?.toLowerCase().includes(normalizedQuery) ||
          r.reason?.toLowerCase().includes(normalizedQuery) ||
          r.requestedByName?.toLowerCase().includes(normalizedQuery)
      ),
      plantilla_approvals: queues.plantilla_approvals.filter(
        (r) =>
          r.applicantName?.toLowerCase().includes(normalizedQuery) ||
          r.vcode?.toLowerCase().includes(normalizedQuery) ||
          r.account?.toLowerCase().includes(normalizedQuery) ||
          r.position?.toLowerCase().includes(normalizedQuery) ||
          r.emplocNo?.toLowerCase().includes(normalizedQuery) ||
          r.requestedBy?.toLowerCase().includes(normalizedQuery)
      ),
      account_requests: queues.account_requests.filter(
        (r) =>
          r.fullName?.toLowerCase().includes(normalizedQuery) ||
          r.email?.toLowerCase().includes(normalizedQuery) ||
          r.requestedRoleName?.toLowerCase().includes(normalizedQuery) ||
          r.mobileNumber?.toLowerCase().includes(normalizedQuery) ||
          r.notes?.toLowerCase().includes(normalizedQuery)
      ),
      hr_emploc_deletions: queues.hr_emploc_deletions.filter(
        (r) =>
          r.applicantName?.toLowerCase().includes(normalizedQuery) ||
          r.vcode?.toLowerCase().includes(normalizedQuery) ||
          r.reason?.toLowerCase().includes(normalizedQuery) ||
          r.deletionType?.toLowerCase().includes(normalizedQuery) ||
          r.storeName?.toLowerCase().includes(normalizedQuery) ||
          r.positionTitle?.toLowerCase().includes(normalizedQuery)
      ),
      account_archives: queues.account_archives.filter(
        (r) =>
          r.accountName?.toLowerCase().includes(normalizedQuery) ||
          r.accountCode?.toLowerCase().includes(normalizedQuery) ||
          r.groupName?.toLowerCase().includes(normalizedQuery) ||
          r.remarks?.toLowerCase().includes(normalizedQuery) ||
          r.requestedBy?.toLowerCase().includes(normalizedQuery)
      ),
      relievers: queues.relievers.filter(
        (r) =>
          r.employeeName?.toLowerCase().includes(normalizedQuery) ||
          r.employeeNumber?.toLowerCase().includes(normalizedQuery) ||
          r.requestedAccount?.toLowerCase().includes(normalizedQuery) ||
          r.requestedStore?.toLowerCase().includes(normalizedQuery) ||
          r.reason?.toLowerCase().includes(normalizedQuery)
      ),
      vacancy_closures: queues.vacancy_closures.filter(
        (r) =>
          r.vacancyVcode?.toLowerCase().includes(normalizedQuery) ||
          r.storeName?.toLowerCase().includes(normalizedQuery) ||
          r.storeBranch?.toLowerCase().includes(normalizedQuery) ||
          r.position?.toLowerCase().includes(normalizedQuery) ||
          r.account?.toLowerCase().includes(normalizedQuery) ||
          r.reason?.toLowerCase().includes(normalizedQuery)
      ),
      errors: queues.errors,
    };
  }, [queues, normalizedQuery]);

  // Total matching items across all categories
  const totalMatchingItems = useMemo(() => {
    if (!filteredData) return 0;
    return (
      filteredData.deactivations.length +
      filteredData.headcount.length +
      filteredData.coverage.length +
      filteredData.applicant_movements.length +
      filteredData.account_group_transfers.length +
      filteredData.new_stores.length +
      filteredData.plantilla_approvals.length +
      filteredData.account_requests.length +
      filteredData.hr_emploc_deletions.length +
      filteredData.account_archives.length +
      filteredData.relievers.length +
      filteredData.vacancy_closures.length
    );
  }, [filteredData]);

  // ── Dynamic Category Sorting: Non-empty on top, empty at bottom ──────────
  const activeCategories = useMemo(() => {
    const list = ALL_CATEGORY_KEYS.filter(
      (k) => !allowedCategories || allowedCategories.includes(k)
    );

    if (!filteredData) return list;

    return [...list].sort((a, b) => {
      const countA = (filteredData[a] as unknown[])?.length ?? 0;
      const countB = (filteredData[b] as unknown[])?.length ?? 0;
      // Non-empty categories first
      if (countA > 0 && countB === 0) return -1;
      if (countA === 0 && countB > 0) return 1;
      // If both have items or both 0, maintain stable order
      return ALL_CATEGORY_KEYS.indexOf(a) - ALL_CATEGORY_KEYS.indexOf(b);
    });
  }, [filteredData, allowedCategories]);

  const toggleAccordion = (key: string, defaultOpen: boolean) => {
    setManualExpanded((prev) => {
      const current = prev[key] ?? defaultOpen;
      return { ...prev, [key]: !current };
    });
  };

  const toggleExpandAllItems = (key: string) => {
    setExpandedAllItems((prev) => ({
      ...prev,
      [key]: !prev[key],
    }));
  };

  return (
    <div className="space-y-6">
      {/* ── Top Unified Filter & Search Bar ───────────────────────────────── */}
      <div className="border-b border-[var(--line)] pb-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          {/* Left: Global Search + Status Sub-tabs */}
          <div className="flex flex-wrap items-center gap-3 sm:gap-4">
            <div className="relative w-64 sm:w-72">
              <Search className="pointer-events-none absolute left-2.5 top-2.5 h-3.5 w-3.5 text-[var(--muted)]" />
              <input
                type="text"
                placeholder="Search all 10 approval queues..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="h-8 w-full rounded-[9px] border border-[var(--line)] bg-[var(--bg)] pl-8 pr-3 text-xs text-[var(--text)] placeholder:text-[var(--muted)] focus:border-[var(--text)] focus:outline-hidden"
              />
            </div>

            <div
              className="flex items-center gap-1.5 overflow-x-auto no-scrollbar scrollbar-none"
              role="tablist"
            >
              <button
                type="button"
                role="tab"
                aria-selected={currentTab === "pending"}
                onClick={() => setCurrentTab("pending")}
                className={`group inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border px-3 py-1.5 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                  currentTab === "pending"
                    ? "border-border-brand bg-brand-subtle text-text-brand-bold shadow-2xs"
                    : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
                }`}
              >
                <span>Pending</span>
                {!isLoading && currentTab === "pending" && (
                  <span className="ml-1 rounded-full bg-brand-500 px-1.5 py-0.5 font-mono text-xs text-white">
                    {totalMatchingItems}
                  </span>
                )}
              </button>

              <button
                type="button"
                role="tab"
                aria-selected={currentTab === "approved"}
                onClick={() => setCurrentTab("approved")}
                className={`group inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border px-3 py-1.5 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                  currentTab === "approved"
                    ? "border-border-brand bg-brand-subtle text-text-brand-bold shadow-2xs"
                    : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
                }`}
              >
                <span>Approved / Completed</span>
                {!isLoading && currentTab === "approved" && (
                  <span className="ml-1 rounded-full bg-brand-500 px-1.5 py-0.5 font-mono text-xs text-white">
                    {totalMatchingItems}
                  </span>
                )}
              </button>

              <button
                type="button"
                role="tab"
                aria-selected={currentTab === "rejected"}
                onClick={() => setCurrentTab("rejected")}
                className={`group inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border px-3 py-1.5 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                  currentTab === "rejected"
                    ? "border-border-brand bg-brand-subtle text-text-brand-bold shadow-2xs"
                    : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
                }`}
              >
                <span>Rejected</span>
                {!isLoading && currentTab === "rejected" && (
                  <span className="ml-1 rounded-full bg-brand-500 px-1.5 py-0.5 font-mono text-xs text-white">
                    {totalMatchingItems}
                  </span>
                )}
              </button>
            </div>
          </div>

          {/* Right: Refresh button */}
          <button
            type="button"
            onClick={handleRefresh}
            disabled={isRefetching || isLoading}
            className="inline-flex h-8 shrink-0 items-center gap-1.5 rounded-[9px] border border-[var(--line)] bg-transparent px-3 text-xs font-normal text-[var(--muted)] hover:text-[var(--text)] hover:border-[var(--text)] disabled:opacity-50 transition cursor-pointer"
          >
            <RefreshCw
              className={`h-3 w-3 ${
                isRefetching ? "animate-spin text-[var(--text)]" : ""
              }`}
            />
            <span>Refresh All</span>
          </button>
        </div>
      </div>

      {/* ── Loading State ─────────────────────────────────────────────────── */}
      {isLoading && (
        <ApprovalsDataState
          kind="loading"
          title="Loading All Requests Hub..."
          description="Fetching live items across all operational queues concurrently..."
        />
      )}

      {/* ── Category Accordion Sections ───────────────────────────────────── */}
      {!isLoading && (
        <div className="space-y-4">
          {activeCategories.map((catKey) => {
            const meta = CATEGORY_META[catKey];
            const Icon = meta?.icon ?? Layers;
            const items = (filteredData ? filteredData[catKey] : []) as unknown[];
            const itemCount = items.length;
            const hasItems = itemCount > 0;
            const errorMessage = filteredData?.errors[catKey];

            // Auto-expand non-empty; auto-collapse empty; respect manual toggles
            const isOpen = manualExpanded[catKey] ?? hasItems;
            const isShowingAll = expandedAllItems[catKey] ?? false;

            const visibleItems = isShowingAll
              ? items
              : items.slice(0, PREVIEW_CAP);

            return (
              <section
                key={catKey}
                className={`rounded-xl border transition-all ${
                  hasItems
                    ? "border-[var(--line)] bg-[var(--surface-base)] shadow-2xs"
                    : "border-[var(--line)] bg-[var(--surface-subtle)]/40 opacity-85"
                }`}
              >
                {/* ── Category Section Header ─────────────────────────────── */}
                <div className="flex flex-wrap items-center justify-between gap-3 p-4">
                  <div
                    onClick={() => toggleAccordion(catKey, hasItems)}
                    className="flex items-center gap-3 cursor-pointer select-none min-w-0 flex-1"
                  >
                    <button
                      type="button"
                      aria-label={isOpen ? "Collapse section" : "Expand section"}
                      className="p-1 text-[var(--muted)] hover:text-[var(--text)] transition cursor-pointer"
                    >
                      {isOpen ? (
                        <ChevronDown className="h-4 w-4" />
                      ) : (
                        <ChevronRight className="h-4 w-4" />
                      )}
                    </button>

                    <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg border border-[var(--line)] bg-[var(--bg)] text-[var(--text)]">
                      <Icon className="h-4 w-4 text-brand-600" />
                    </div>

                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <h2 className="text-sm font-semibold text-[var(--text)] truncate">
                          {meta?.label ?? catKey}
                        </h2>

                        <span
                          className={`rounded-full px-2 py-0.5 font-mono text-xs font-semibold ${
                            hasItems
                              ? "bg-brand-500 text-white"
                              : "bg-surface-subtle text-[var(--muted)] border border-[var(--line)]"
                          }`}
                        >
                          {itemCount}
                        </span>
                      </div>

                      {isOpen && meta?.description && (
                        <p className="mt-0.5 text-xs text-[var(--muted)] line-clamp-1">
                          {meta.description}
                        </p>
                      )}
                    </div>
                  </div>

                  {/* Header Right Action: "Open Tab ->" */}
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => onSelectCategory(catKey)}
                      className="inline-flex h-7 items-center gap-1.5 rounded-lg border border-[var(--line)] bg-[var(--bg)] px-2.5 text-xs font-medium text-[var(--text)] hover:border-brand-500 hover:text-brand-600 transition cursor-pointer"
                    >
                      <span>Open Tab</span>
                      <ArrowRight className="h-3 w-3" />
                    </button>
                  </div>
                </div>

                {/* ── Section Body (Expanded) ─────────────────────────────── */}
                {isOpen && (
                  <div className="border-t border-[var(--line)] p-4 pt-3">
                    {errorMessage ? (
                      <ApprovalsDataState
                        kind="error"
                        title={`Failed to load ${meta?.label ?? catKey}`}
                        description={errorMessage}
                        onRetry={handleRefresh}
                      />
                    ) : items.length === 0 ? (
                      <div className="py-6 text-center">
                        <p className="text-xs text-[var(--muted)]">
                          {searchQuery
                            ? `No ${meta?.label ?? catKey} requests match "${searchQuery}".`
                            : `No ${currentTab} ${meta?.label ?? catKey} requests.`}
                        </p>
                      </div>
                    ) : (
                      <div className="space-y-3">
                        {/* Table Render per category */}
                        {catKey === "deactivations" && (
                          <DeactivationDataTable
                            requests={visibleItems as DeactivationRequestItem[]}
                            tab={currentTab}
                            page={1}
                            pageSize={visibleItems.length}
                            totalCount={visibleItems.length}
                          />
                        )}

                        {catKey === "headcount" && (
                          <HeadcountDataTable
                            requests={visibleItems as HeadcountRequestItem[]}
                            tab={currentTab}
                            page={1}
                            pageSize={visibleItems.length}
                            totalCount={visibleItems.length}
                          />
                        )}

                        {catKey === "coverage" && (
                          <CoverageDataTable
                            requests={visibleItems as CoverageGroupRequestItem[]}
                            tab={currentTab}
                            page={1}
                            pageSize={visibleItems.length}
                            totalCount={visibleItems.length}
                          />
                        )}

                        {catKey === "applicant_movements" && (
                          <ApplicantMovementDataTable
                            requests={visibleItems as ApplicantMovementRequestItem[]}
                            tab={currentTab}
                            page={1}
                            pageSize={visibleItems.length}
                            totalCount={visibleItems.length}
                          />
                        )}

                        {catKey === "account_group_transfers" && (
                          <AccountTransferDataTable
                            requests={visibleItems as AccountGroupTransferItem[]}
                            tab={currentTab}
                            page={1}
                            pageSize={visibleItems.length}
                            totalCount={visibleItems.length}
                          />
                        )}

                        {catKey === "new_stores" && (
                          <NewStoreDataTable
                            requests={visibleItems as NewStoreRequestItem[]}
                            tab={currentTab}
                            page={1}
                            pageSize={visibleItems.length}
                            totalCount={visibleItems.length}
                          />
                        )}

                        {catKey === "plantilla_approvals" && (
                          <PlantillaApprovalDataTable
                            requests={visibleItems as PlantillaApprovalItem[]}
                            tab={currentTab}
                            page={1}
                            pageSize={visibleItems.length}
                            totalCount={visibleItems.length}
                          />
                        )}

                        {catKey === "account_requests" && (
                          <AccountRequestDataTable
                            requests={visibleItems as AccountRequestItem[]}
                            tab={currentTab as AccountRequestStatus}
                            page={1}
                            pageSize={visibleItems.length}
                            totalCount={visibleItems.length}
                          />
                        )}

                        {catKey === "hr_emploc_deletions" && (
                          <HrEmplocDeletionDataTable
                            requests={visibleItems as EmplocDeletionRequestItem[]}
                            tab={currentTab}
                            page={1}
                            pageSize={visibleItems.length}
                            totalCount={visibleItems.length}
                          />
                        )}

                        {catKey === "account_archives" && (
                          <AccountArchiveDataTable
                            requests={visibleItems as AccountArchiveItem[]}
                            tab={currentTab}
                            page={1}
                            pageSize={visibleItems.length}
                            totalCount={visibleItems.length}
                          />
                        )}

                        {catKey === "relievers" && (
                          <RelieverDataTable
                            requests={visibleItems as RelieverEndorsementItem[]}
                            tab={currentTab}
                            page={1}
                            pageSize={visibleItems.length}
                            totalCount={visibleItems.length}
                          />
                        )}

                        {catKey === "vacancy_closures" && (
                          <VacancyClosureDataTable
                            requests={visibleItems as VacancyClosureRequestItem[]}
                            tab={currentTab}
                            page={1}
                            pageSize={visibleItems.length}
                            totalCount={visibleItems.length}
                          />
                        )}

                        {/* Preview Cap & Expansion Bar */}
                        {itemCount > PREVIEW_CAP && (
                          <div className="flex flex-wrap items-center justify-between gap-2 border-t border-[var(--line)] pt-3 text-xs text-[var(--muted)]">
                            <span>
                              Showing {visibleItems.length} of {itemCount} requests
                            </span>

                            <div className="flex items-center gap-3">
                              <button
                                type="button"
                                onClick={() => toggleExpandAllItems(catKey)}
                                className="font-medium text-brand-600 hover:text-brand-500 hover:underline cursor-pointer"
                              >
                                {isShowingAll
                                  ? `Show first ${PREVIEW_CAP} requests`
                                  : `Show all ${itemCount} requests`}
                              </button>

                              <span className="text-[var(--line)]">|</span>

                              <button
                                type="button"
                                onClick={() => onSelectCategory(catKey)}
                                className="inline-flex items-center gap-1 font-medium text-[var(--text)] hover:text-brand-600 hover:underline cursor-pointer"
                              >
                                <span>View all in {meta?.label ?? catKey} Tab</span>
                                <ArrowRight className="h-3 w-3" />
                              </button>
                            </div>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                )}
              </section>
            );
          })}
        </div>
      )}
    </div>
  );
}
