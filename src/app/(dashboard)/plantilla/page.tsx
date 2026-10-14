"use client";

import { useState, useEffect, useMemo } from "react";
import { useQuery, useQueries } from "@tanstack/react-query";
import { LockKeyhole, Users, ArrowLeft, Building, Share2, ChevronRight, UserPlus } from "lucide-react";
import { useSearchParams, useRouter, usePathname } from "next/navigation";
import { loadCurrentUserContext, isQuotaOverrideRole, isOpsAmendmentRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/client";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { MetricCard } from "@/components/shared/MetricCard";
import { AdminFilterBar } from "@/components/shared/AdminFilterBar";
import { DataState } from "@/components/shared/DataState";
import { StatusBadge } from "@/components/ui/StatusBadge";
import type { BadgeVariant } from "@/components/ui/StatusBadge";
import {
  getPlantillaSummary,
  listWebPlantillaEmployees,
  listWebPlantillaStoreStaffing,
  deriveDeactivationOverlay,
  deriveStaffingRisk,
  PlantillaDataError,
  type PlantillaEmployeeListItem,
  type PlantillaStoreStaffingRow,
} from "@/lib/queries/plantilla";
import { PlantillaDetailDrawer } from "@/components/plantilla/PlantillaDetailDrawer";
import { StoreStaffingDrawer } from "@/components/plantilla/StoreStaffingDrawer";
import { SlotDetailDrawer } from "@/components/plantilla/SlotDetailDrawer";
import { RequestHeadcountModal } from "@/components/modals/RequestHeadcountModal";


// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type ViewMode = "employee" | "inactive" | "store";

// ---------------------------------------------------------------------------
// Status helpers
// ---------------------------------------------------------------------------

function plantillaStatusVariant(status: string | null | undefined): BadgeVariant {
  switch ((status ?? "").toLowerCase()) {
    case "active":
      return "success";
    case "pending transfer":
    case "pending_transfer":
      return "info";
    case "pending separation":
    case "pending_separation":
      return "danger";
    case "suspended":
      return "warning";
    case "inactive":
    case "terminated":
      return "neutral";
    default:
      return "neutral";
  }
}

function staffingStatusVariant(status: string | null | undefined): BadgeVariant {
  switch ((status ?? "").toLowerCase()) {
    case "fully-staffed":
    case "low":
      return "success";
    case "under-staffed":
    case "critical":
    case "high":
      return "danger";
    case "over-staffed":
    case "medium":
      return "warning";
    default:
      return "neutral";
  }
}

// ---------------------------------------------------------------------------
// Filter option constants
// ---------------------------------------------------------------------------



const STATUS_OPTIONS = [
  { value: "", label: "All Statuses" },
  { value: "active", label: "Active" },
  { value: "pending_transfer", label: "Pending Transfer" },
  { value: "pending_separation", label: "Pending Separation" },
  { value: "suspended", label: "Suspended" },
  { value: "inactive", label: "Inactive" },
];

const DEPLOYMENT_TYPE_OPTIONS = [
  { value: "", label: "All Types" },
  { value: "budgeted", label: "Budgeted" },
  { value: "additional", label: "Additional (AH)" },
];

const STAFFING_RISK_OPTIONS = [
  { value: "", label: "All SLA Status" },
  { value: "under-staffed", label: "Under-Staffed" },
  { value: "fully-staffed", label: "Fully-Staffed" },
  { value: "over-staffed", label: "Over-Staffed" },
];

const PAGE_SIZE = 25;

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function PlantillaPage() {
  const [view, setView] = useState<ViewMode>("employee");
  const [page, setPage] = useState(1);
  const [selectedPlantillaId, setSelectedPlantillaId] = useState<string | null>(null);
  const [selectedStoreRow, setSelectedStoreRow] = useState<PlantillaStoreStaffingRow | null>(null);
  const [selectedSlotId, setSelectedSlotId] = useState<string | null>(null);
  const [isRequestHeadcountOpen, setIsRequestHeadcountOpen] = useState(false);

  // Search parameters and router
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();

  // Hydration state
  const [isHydrated, setIsHydrated] = useState(false);
  // Search query specifically for the account selector list
  const [accountSearch, setAccountSearch] = useState("");
  const [selectorGroupId, setSelectorGroupId] = useState("");

  // Committed filter values (drive queries)
  const [search, setSearch] = useState("");
  const [accountId, setAccountId] = useState("");
  const [groupId, setGroupId] = useState("");

  // Pending (unsubmitted) filter values
  const [pendingSearch, setPendingSearch] = useState("");
  const [pendingAccountId, setPendingAccountId] = useState("");
  const [pendingGroupId, setPendingGroupId] = useState("");

  // Employee-specific pending filters
  const [pendingStoreId, setPendingStoreId] = useState("");
  const [pendingStatus, setPendingStatus] = useState("");
  const [pendingPlantillaType, setPendingPlantillaType] = useState("");

  // Committed employee filters
  const [storeId, setStoreId] = useState("");
  const [status, setStatus] = useState("");
  const [plantillaType, setPlantillaType] = useState("");

  // Store-specific pending filters
  const [pendingSlaStatus, setPendingSlaStatus] = useState("");

  // Committed store filters
  const [slaStatus, setSlaStatus] = useState("");

  // -------------------------------------------------------------------------
  // User Context and Account Lists
  // -------------------------------------------------------------------------

  const userContextQuery = useQuery({
    queryKey: ["currentUserContext"],
    queryFn: () => loadCurrentUserContext(),
    staleTime: Infinity,
  });

  const currentUser = userContextQuery.data?.currentUser;
  const userRole = currentUser?.roleKey ?? currentUser?.roleName;
  const canReviseQuota = isQuotaOverrideRole(userRole);
  const canRequestAdjustment = isOpsAmendmentRole(userRole);

  const allowedAccountsQuery = useQuery({
    queryKey: ["plantilla", "allowed-accounts", currentUser?.accountScope],
    queryFn: async () => {
      if (!currentUser) return [];
      const { mode, ids } = currentUser.accountScope;
      if (mode === "none") return [];

      const supabase = createClient();
      let query = supabase
        .from("accounts")
        .select(`
          id,
          account_name,
          group_id,
          is_pool_account,
          groups (
            group_name
          )
        `)
        .eq("is_active", true);

      if (mode === "scoped" && ids.length > 0) {
        query = query.in("id", ids);
      }

      const { data, error } = await query.order("account_name");
      if (error) throw error;
      return (data ?? []).map((row) => ({
        id: row.id as string,
        name: row.account_name as string,
        groupId: row.group_id as string | null,
        groupName: Array.isArray(row.groups)
          ? ((row.groups[0] as unknown as Record<string, unknown>)?.group_name as string | null)
          : row.groups && typeof row.groups === "object"
          ? ((row.groups as unknown as Record<string, unknown>).group_name as string | null)
          : null,
        isPoolAccount: !!row.is_pool_account,
      }));
    },
    enabled: !!currentUser,
  });

  const allowedAccountIds = allowedAccountsQuery.data?.map((a) => a.id) ?? [];


  const accountSummaries = useQueries({
    queries: allowedAccountIds.map((accId) => ({
      queryKey: ["plantilla", "summary-account", accId],
      queryFn: () => getPlantillaSummary({ accountId: accId }),
      staleTime: 30000,
      enabled: allowedAccountIds.length > 0,
    })),
  });

  const uniqueGroups = useMemo(() => {
    const accounts = allowedAccountsQuery.data ?? [];
    const map = new Map<string, string>();
    for (const a of accounts) {
      if (a.groupId && a.groupName) {
        map.set(a.groupId, a.groupName);
      }
    }
    return Array.from(map.entries()).map(([id, name]) => ({ id, name }));
  }, [allowedAccountsQuery.data]);

  // Deep-linking hydration and auto-select/auto-fire logic
  useEffect(() => {
    if (!userContextQuery.data) return;

    const urlAccountId = searchParams.get("accountId");
    const user = userContextQuery.data.currentUser;

    /* eslint-disable react-hooks/set-state-in-effect */
    if (urlAccountId) {
      setAccountId(urlAccountId);
      setPendingAccountId(urlAccountId);
    } else if (user) {
      const { accountScope } = user;
      if (accountScope.mode === "scoped" && accountScope.ids.length === 1) {
        setAccountId(accountScope.ids[0]);
        setPendingAccountId(accountScope.ids[0]);
      }
    }
    setIsHydrated(true);
    /* eslint-enable react-hooks/set-state-in-effect */
  }, [userContextQuery.data, searchParams]);

  // -------------------------------------------------------------------------
  // Queries (Gated behind accountId)
  // -------------------------------------------------------------------------

  const summaryQuery = useQuery({
    queryKey: ["plantilla", "summary", { search, accountId, groupId, selectorGroupId }],
    queryFn: () =>
      getPlantillaSummary({
        search: accountId ? (search || undefined) : undefined,
        accountId: accountId || undefined,
        groupId: accountId ? (groupId || undefined) : (selectorGroupId || undefined),
      }),
    enabled: isHydrated && !!currentUser,
  });

  const employeeQuery = useQuery({
    queryKey: [
      "plantilla",
      "employees",
      { search, accountId, groupId, storeId, status, plantillaType, page, view },
    ],
    queryFn: () =>
      listWebPlantillaEmployees({
        search: search || undefined,
        accountId: accountId || undefined,
        groupId: groupId || undefined,
        storeId: storeId || undefined,
        status: status || undefined,
        deployment: plantillaType || undefined,
        activeState: view === "inactive" ? "inactive" : "active",
        page,
        pageSize: PAGE_SIZE,
      }),
    enabled: (view === "employee" || view === "inactive") && !!accountId,
  });

  const storeQuery = useQuery({
    queryKey: ["plantilla", "stores", { search, accountId, groupId, slaStatus, page }],
    queryFn: () =>
      listWebPlantillaStoreStaffing({
        search: search || undefined,
        accountId: accountId || undefined,
        groupId: groupId || undefined,
        riskFilter: slaStatus || undefined,
        page,
        pageSize: PAGE_SIZE,
      }),
    enabled: view === "store" && !!accountId,
  });

  // -------------------------------------------------------------------------
  // Derived state
  // -------------------------------------------------------------------------

  const summaryData = summaryQuery.data;
  const summaryError =
    summaryQuery.error instanceof PlantillaDataError ? summaryQuery.error : null;
  const summaryBlocked = summaryError?.kind === "access_denied";

  const activeListQuery = view === "store" ? storeQuery : employeeQuery;
  const listError =
    activeListQuery.error instanceof PlantillaDataError ? activeListQuery.error : null;

  const isListLoading = activeListQuery.isLoading;
  const isListError = activeListQuery.isError && !isListLoading;
  const isAccessDenied = listError?.kind === "access_denied";
  const isRetryable = isListError && !isAccessDenied;

  const employeeRows = employeeQuery.data?.data ?? [];
  const storeRows = storeQuery.data?.data ?? [];
  const totalCount = activeListQuery.data?.totalCount ?? 0;
  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));

  // -------------------------------------------------------------------------
  // Handlers
  // -------------------------------------------------------------------------


  function getAccountSummary(accId: string) {
    const queryIndex = allowedAccountIds.indexOf(accId);
    if (queryIndex !== -1) {
      const q = accountSummaries[queryIndex];
      if (q && q.data) {
        return q.data;
      }
    }
    return { required: 0, actual: 0, hrProcess: 0, vacant: 0 };
  }

  function handleSelectAccount(accId: string) {
    setAccountId(accId);
    setPendingAccountId(accId);

    const params = new URLSearchParams(searchParams.toString());
    params.set("accountId", accId);
    router.push(`${pathname}?${params.toString()}`);
  }

  function handleBackToSelection() {
    setAccountId("");
    setPendingAccountId("");
    handleReset();

    const params = new URLSearchParams(searchParams.toString());
    params.delete("accountId");
    router.push(`${pathname}?${params.toString()}`);
  }

  function handleApply() {
    setSearch(pendingSearch);
    setAccountId(pendingAccountId);
    setGroupId(pendingGroupId);
    setStoreId(pendingStoreId);
    setStatus(pendingStatus);
    setPlantillaType(pendingPlantillaType);
    setSlaStatus(pendingSlaStatus);
    setPage(1);
  }

  function handleReset() {
    setPendingSearch("");
    setPendingGroupId("");
    setPendingStoreId("");
    setPendingStatus("");
    setPendingPlantillaType("");
    setPendingSlaStatus("");
    setSearch("");
    setGroupId("");
    setStoreId("");
    setStatus("");
    setPlantillaType("");
    setSlaStatus("");
    setPage(1);

    const user = userContextQuery.data?.currentUser;
    const isSingleScoped =
      user?.accountScope.mode === "scoped" && user?.accountScope.ids.length === 1;

    if (isSingleScoped) {
      const singleId = user.accountScope.ids[0];
      setAccountId(singleId);
      setPendingAccountId(singleId);
    } else {
      setAccountId("");
      setPendingAccountId("");
    }
  }

  function switchView(next: ViewMode) {
    if (next !== view) {
      setView(next);
      setPage(1);
      setSelectedPlantillaId(null);
      setSelectedStoreRow(null);
    }
  }

  // -------------------------------------------------------------------------
  // List content
  // -------------------------------------------------------------------------

  function renderListContent() {
    if (isListLoading) {
      return (
        <DataState
          kind="loading"
          title="Loading plantilla records"
          description="Fetching personnel and store data through Supabase RPCs."
        />
      );
    }

    if (isAccessDenied) {
      return (
        <DataState
          kind="access_denied"
          title="Access Restricted"
          description="Supabase RLS policies blocked this read. You are not authorized to view plantilla records outside your scoped boundary."
        />
      );
    }

    if (isRetryable) {
      return (
        <DataState
          kind="error"
          title="Fetch Failed"
          description={
            listError?.message ??
            "The plantilla query failed. You can retry without changing filters."
          }
          onRetry={() => activeListQuery.refetch()}
        />
      );
    }

    if (view === "employee" || view === "inactive") {
      if (employeeRows.length === 0) {
        return (
          <DataState
            kind="empty"
            title={view === "inactive" ? "No inactive records found" : "No employee records found"}
            description={
              view === "inactive"
                ? "No inactive or terminated plantilla employees match the current filters."
                : "No active plantilla employees match the current filters."
            }
          />
        );
      }
      return <EmployeeTable rows={employeeRows} onRowClick={setSelectedPlantillaId} />;
    }

    if (storeRows.length === 0) {
      return (
        <DataState
          kind="empty"
          title="No store records found"
          description="No store staffing records match the current filters."
        />
      );
    }
    return <StoreTable rows={storeRows} onRowClick={setSelectedStoreRow} />;
  }

  // -------------------------------------------------------------------------
  // View toggle element (injected into filter bar)
  // -------------------------------------------------------------------------

  const viewToggle = (
    <div
      aria-label="Plantilla view mode"
      className="flex items-center overflow-hidden rounded-md border border-border-default"
      role="tablist"
    >
      <button
        aria-selected={view === "employee"}
        role="tab"
        type="button"
        className={`h-10 px-4 text-sm font-semibold transition-colors ${
          view === "employee"
            ? "bg-brand-600 text-white"
            : "bg-surface-base text-text-secondary hover:bg-surface-hover"
        }`}
        onClick={() => switchView("employee")}
      >
        Employee View
      </button>
      <button
        aria-selected={view === "inactive"}
        role="tab"
        type="button"
        className={`h-9 border-l border-border-default px-3 text-sm font-medium transition-colors ${
          view === "inactive"
            ? "bg-brand-600 text-white"
            : "bg-surface-base text-text-secondary hover:bg-surface-hover"
        }`}
        onClick={() => switchView("inactive")}
      >
        Inactive
      </button>
      <button
        aria-selected={view === "store"}
        role="tab"
        type="button"
        className={`h-10 border-l border-border-default px-4 text-sm font-semibold transition-colors ${
          view === "store"
            ? "bg-brand-600 text-white"
            : "bg-surface-base text-text-secondary hover:bg-surface-hover"
        }`}
        onClick={() => switchView("store")}
      >
        Store Staffing
      </button>
    </div>
  );


  const inputClass =
    "h-10 w-36 rounded-md border border-border-default bg-surface-muted px-3 text-sm text-text-primary outline-none focus:border-brand-500 transition-colors";

  // -------------------------------------------------------------------------
  // Render Selection Screen / Main Roster
  // -------------------------------------------------------------------------

  if (userContextQuery.isLoading || !isHydrated) {
    return (
      <div className="flex min-h-[400px] items-center justify-center">
        <DataState
          kind="loading"
          title="Loading User Workspace"
          description="Resolving your authorization profile and scopes..."
        />
      </div>
    );
  }

  function renderAccountSelectionContent() {
    const isSummariesLoading = accountSummaries.some((q) => q.isLoading);
    if (allowedAccountsQuery.isLoading || isSummariesLoading) {
      return (
        <DataState
          kind="loading"
          title="Loading Accounts"
          description="Fetching your authorized accounts and staffing metrics..."
        />
      );
    }

    if (allowedAccountsQuery.isError) {
      return (
        <DataState
          kind="error"
          title="Failed to Load Accounts"
          description="An error occurred while fetching your authorized billing accounts."
          onRetry={() => {
            allowedAccountsQuery.refetch();
            accountSummaries.forEach((q) => q.refetch());
          }}
        />
      );
    }

    const accounts = allowedAccountsQuery.data ?? [];
    if (accounts.length === 0) {
      return (
        <DataState
          kind="access_denied"
          title="No Authorized Accounts"
          description="Your user profile does not have any active billing account scopes assigned. Access remains restricted."
        />
      );
    }

    const filteredAccounts = accounts.filter((a) => {
      const matchesSearch = a.name.toLowerCase().includes(accountSearch.toLowerCase());
      const matchesGroup = !selectorGroupId || a.groupId === selectorGroupId;
      return matchesSearch && matchesGroup;
    });

    return (
      <div className="flex flex-col gap-6">
        <div className="flex flex-wrap items-center gap-3">
          <div className="relative w-full max-w-xs">
            <input
              type="text"
              placeholder="Search accounts..."
              value={accountSearch}
              onChange={(e) => setAccountSearch(e.target.value)}
              className="h-10 w-full rounded-md border border-border-default bg-surface-base px-3 text-sm text-text-primary outline-none focus:border-brand-500 transition-colors"
            />
          </div>
          {uniqueGroups.length > 0 && (
            <select
              value={selectorGroupId}
              onChange={(e) => setSelectorGroupId(e.target.value)}
              className="h-10 rounded-md border border-border-default bg-surface-base px-3 text-sm text-text-primary outline-none focus:border-brand-500 transition-colors"
              aria-label="Filter accounts by group"
            >
              <option value="">All Groups</option>
              {uniqueGroups.map((g) => (
                <option key={g.id} value={g.id}>
                  {g.name}
                </option>
              ))}
            </select>
          )}
          {(accountSearch || selectorGroupId) && (
            <button
              type="button"
              onClick={() => {
                setAccountSearch("");
                setSelectorGroupId("");
              }}
              className="text-sm font-semibold text-brand-600 hover:text-brand-700 px-2"
            >
              Clear Filters
            </button>
          )}
        </div>

        {filteredAccounts.length === 0 ? (
          <DataState
            kind="empty"
            title="No accounts match search"
            description="Try searching with a different term."
          />
        ) : (
          <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
            {(() => {
              const sortedAccounts = filteredAccounts
                .map((account) => {
                  const summary = getAccountSummary(account.id);
                  const actual = summary.actual;
                  const vacant = summary.vacant;
                  const hrProcess = summary.hrProcess;
                  const required = actual + vacant;
                  const fillRate = required > 0 ? Math.round((actual / required) * 100) : 0;

                  return {
                    ...account,
                    actual,
                    vacant,
                    hrProcess,
                    required,
                    fillRate,
                  };
                })
                .sort((a, b) => {
                  // 1. Moses HQ pinned at the top
                  const isAMoses = a.name.trim().toLowerCase() === "moses hq";
                  const isBMoses = b.name.trim().toLowerCase() === "moses hq";
                  if (isAMoses && !isBMoses) return -1;
                  if (!isAMoses && isBMoses) return 1;

                  // 2. 0% fill rate at the bottom
                  const isAFillRateZero = a.fillRate === 0;
                  const isBFillRateZero = b.fillRate === 0;
                  if (isAFillRateZero && !isBFillRateZero) return 1;
                  if (!isAFillRateZero && isBFillRateZero) return -1;

                  // 3. Sort by problematic account (fill rate ascending)
                  if (a.fillRate !== b.fillRate) {
                    return a.fillRate - b.fillRate;
                  }

                  // 4. Stable alphabetical sort by name
                  return a.name.localeCompare(b.name);
                });

              return sortedAccounts.map((account) => {
                // Dynamic progress bar colors:
                // 100%+ = Green (emerald)
                // 95% - 99.99% = Yellow (amber)
                // Below 95% = Red
                const getProgressColors = (rate: number) => {
                  if (rate >= 100) {
                    return {
                      bar: "bg-emerald-500",
                      text: "text-emerald-700",
                    };
                  }
                  if (rate >= 95) {
                    return {
                      bar: "bg-amber-500",
                      text: "text-amber-700",
                    };
                  }
                  return {
                    bar: "bg-red-500",
                    text: "text-red-700",
                  };
                };

                const colors = getProgressColors(account.fillRate);

                return (
                  <button
                    key={account.id}
                    type="button"
                    onClick={() => handleSelectAccount(account.id)}
                    className="group relative flex w-full items-start gap-4 rounded-xl border border-border-default bg-surface-base p-5 text-left transition-all duration-300 hover:-translate-y-0.5 hover:border-brand-300 hover:shadow-md focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
                  >
                    {/* Left Icon Container */}
                    <div
                      className={`shrink-0 rounded-lg p-2.5 ${
                        account.isPoolAccount
                          ? "bg-purple-50 text-purple-600"
                          : "bg-brand-50/60 text-brand-600"
                      }`}
                    >
                      {account.isPoolAccount ? (
                        <Share2 className="h-5 w-5" />
                      ) : (
                        <Building className="h-5 w-5" />
                      )}
                    </div>

                    {/* Middle Content Section */}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-start justify-between gap-2">
                        <div className="min-w-0">
                          <h3 className="text-base font-bold text-text-primary truncate">
                            {!account.isPoolAccount && account.groupName && (
                              <span className="text-text-secondary font-normal text-sm mr-1">
                                {account.groupName.trim().toLowerCase().startsWith("group")
                                  ? account.groupName
                                  : `Group ${account.groupName}`}{" "}
                                •
                              </span>
                            )}
                            {account.name}
                          </h3>
                          {account.isPoolAccount && (
                            <p className="text-[10px] font-bold text-purple-600/80 tracking-wider mt-0.5 uppercase">
                              Workforce Pool Inside Plantilla
                            </p>
                          )}
                        </div>

                        {/* Badge container */}
                        <div className="shrink-0 flex items-center gap-1.5">
                          {account.isPoolAccount ? (
                            <span className="inline-flex items-center rounded-full bg-purple-100 px-2 py-0.5 text-[10px] font-bold text-purple-700 uppercase">
                              Pool
                            </span>
                          ) : (
                            account.fillRate < 80 && (
                              <span className="inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-bold text-amber-700 uppercase">
                                Warning
                              </span>
                            )
                          )}
                          <ChevronRight className="h-4 w-4 text-text-secondary/60 transition-transform group-hover:translate-x-0.5 shrink-0" />
                        </div>
                      </div>

                      {/* Personnel Stats Row */}
                      <div className="mt-2.5 text-xs text-text-secondary flex flex-wrap items-center gap-x-2 gap-y-1">
                        <span>
                          HC <strong className="text-text-primary font-bold">{account.actual}</strong>/
                          <strong className="text-text-primary font-bold">{account.required}</strong>
                        </span>
                        <span className="text-text-secondary/40">•</span>
                        <span>
                          Vacant <strong className="text-text-primary font-bold">{account.vacant}</strong>
                        </span>
                        {!account.isPoolAccount && (
                          <>
                            <span className="text-text-secondary/40">•</span>
                            <span>
                              Pipeline <strong className="text-text-primary font-bold">{account.hrProcess}</strong>
                            </span>
                          </>
                        )}
                      </div>

                      {/* Progress Bar (MFR) */}
                      {!account.isPoolAccount && (
                        <div className="mt-3.5 flex items-center gap-3">
                          <span className="text-[10px] font-bold text-text-secondary uppercase tracking-wider shrink-0 w-8">
                            MFR
                          </span>
                          <div className="relative flex-1 h-2 rounded-full bg-gray-100 overflow-hidden">
                            <div
                              className={`absolute left-0 top-0 h-full rounded-full transition-all duration-500 ${colors.bar}`}
                              style={{ width: `${Math.min(100, account.fillRate)}%` }}
                            />
                          </div>
                          <span className={`text-xs font-semibold shrink-0 w-8 text-right font-mono ${colors.text}`}>
                            {account.fillRate}%
                          </span>
                        </div>
                      )}
                    </div>
                  </button>
                );
              });
            })()}
          </div>
        )}
      </div>
    );
  }



  const selectedAccountName = allowedAccountsQuery.data?.find((a) => a.id === accountId)?.name;
  const pageSubtitle = selectedAccountName
    ? `Managing roster allocations, capacity targets, and offboarding for ${selectedAccountName}.`
    : "Select a billing account to audit roster allocations, capacity targets, and offboarding workflows.";

  return (
    <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-5 text-gray-900">
      {accountId &&
        (currentUser?.accountScope.mode === "all" ||
          (currentUser?.accountScope.mode === "scoped" &&
            currentUser?.accountScope.ids.length > 1)) && (
          <div className="flex">
            <button
              type="button"
              onClick={handleBackToSelection}
              className="inline-flex items-center gap-1.5 text-sm font-semibold text-brand-600 hover:text-brand-700 transition-colors"
            >
              <ArrowLeft className="h-4 w-4" />
              Back to Account Selection
            </button>
          </div>
        )}

      {accountId && (
        <AdminPageHeader
          title="Plantilla Directory"
          subtitle={pageSubtitle}
          icon={Users}
          readOnly
        />
      )}

      {/* KPI summary row */}
      <section
        aria-label="Plantilla summary metrics"
        className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4"
      >
        <MetricCard
          label="Required"
          value={summaryData?.required}
          helperText="Total required headcount (Actual + HR Process + Vacant)"
          isLoading={summaryQuery.isLoading}
          isBlocked={summaryBlocked}
          isError={!summaryBlocked && summaryQuery.isError}
          errorText="Summary data failed to load"
        />
        <MetricCard
          label="Actual"
          value={summaryData?.actual}
          helperText="Total active deployed employees"
          isLoading={summaryQuery.isLoading}
          isBlocked={summaryBlocked}
          isError={!summaryBlocked && summaryQuery.isError}
          errorText="Summary data failed to load"
        />
        <MetricCard
          label="HR Process"
          value={summaryData?.hrProcess}
          helperText="Onboarding pipeline candidates"
          isLoading={summaryQuery.isLoading}
          isBlocked={summaryBlocked}
          isError={!summaryBlocked && summaryQuery.isError}
          errorText="Summary data failed to load"
        />
        <MetricCard
          label="Vacant"
          value={summaryData?.vacant}
          helperText="Approved open vacancy slots"
          isLoading={summaryQuery.isLoading}
          isBlocked={summaryBlocked}
          isError={!summaryBlocked && summaryQuery.isError}
          errorText="Summary data failed to load"
        />
      </section>

      {!accountId ? (
        renderAccountSelectionContent()
      ) : (
        <>
          {/* Filter bar */}
          <AdminFilterBar
            searchPlaceholder="Search by employee, store, or VCode..."
            searchVal={pendingSearch}
            onSearchChange={setPendingSearch}
            onApply={handleApply}
            onReset={handleReset}
            showResetButton
            resetLabel="Reset"
            filterSlot={
              <div className="flex flex-wrap items-center gap-2">
                {viewToggle}

                {canRequestAdjustment && accountId && (
                  <button
                    type="button"
                    onClick={() => setIsRequestHeadcountOpen(true)}
                    className="inline-flex h-10 items-center gap-1.5 rounded-md bg-brand-600 px-3.5 py-2 text-sm font-semibold text-white shadow-xs hover:bg-brand-700 transition-colors"
                  >
                    <UserPlus className="h-4 w-4" />
                    <span>Request Headcount</span>
                  </button>
                )}

                <input
                  type="text"
                  placeholder="Account ID"
                  value={pendingAccountId}
                  onChange={(e) => setPendingAccountId(e.target.value)}
                  className={inputClass}
                  aria-label="Filter by account ID"
                />

                <input
                  type="text"
                  placeholder="Group ID"
                  value={pendingGroupId}
                  onChange={(e) => setPendingGroupId(e.target.value)}
                  className={inputClass}
                  aria-label="Filter by group ID"
                />

                {(view === "employee" || view === "inactive") && (
                  <>
                    <input
                      type="text"
                      placeholder="Store ID"
                      value={pendingStoreId}
                      onChange={(e) => setPendingStoreId(e.target.value)}
                      className={inputClass}
                      aria-label="Filter by store ID"
                    />

                    <select
                      value={pendingStatus}
                      onChange={(e) => setPendingStatus(e.target.value)}
                      className={inputClass}
                      aria-label="Filter by employment status"
                    >
                      <option value="">All Statuses</option>
                      {STATUS_OPTIONS.map((o) => (
                        <option key={o.value} value={o.value}>
                          {o.label}
                        </option>
                      ))}
                    </select>

                    <select
                      value={pendingPlantillaType}
                      onChange={(e) => setPendingPlantillaType(e.target.value)}
                      className={inputClass}
                      aria-label="Filter by plantilla type"
                    >
                      <option value="">All Types</option>
                      {DEPLOYMENT_TYPE_OPTIONS.map((o) => (
                        <option key={o.value} value={o.value}>
                          {o.label}
                        </option>
                      ))}
                    </select>
                  </>
                )}

                {view === "store" && (
                  <select
                    value={pendingSlaStatus}
                    onChange={(e) => setPendingSlaStatus(e.target.value)}
                    className={inputClass}
                    aria-label="Filter by staffing risk"
                  >
                    {STAFFING_RISK_OPTIONS.map((o) => (
                      <option key={o.value} value={o.value}>
                        {o.label}
                      </option>
                    ))}
                  </select>
                )}
              </div>
            }
          />

          {/* Detail drawer */}
          <PlantillaDetailDrawer
            plantillaId={selectedPlantillaId}
            onClose={() => setSelectedPlantillaId(null)}
          />

          {/* Store Staffing drawer */}
          <StoreStaffingDrawer
            storeRow={selectedStoreRow}
            onClose={() => setSelectedStoreRow(null)}
            canReviseQuota={canReviseQuota}
            canRequestAdjustment={canRequestAdjustment}
            onInspectSlot={(slotId) => setSelectedSlotId(slotId)}
            accountId={accountId}
            accountName={selectedAccountName}
          />

          {/* ADR-001 Slot Inspector & Audit Timeline Drawer */}
          <SlotDetailDrawer
            slotId={selectedSlotId}
            onClose={() => setSelectedSlotId(null)}
          />

          {/* Request Headcount Modal (New Demand Requisition) */}
          {isRequestHeadcountOpen && (
            <RequestHeadcountModal
              isOpen={isRequestHeadcountOpen}
              onClose={() => setIsRequestHeadcountOpen(false)}
              accountId={accountId}
              accountName={selectedAccountName}
              onSuccess={() => {
                activeListQuery.refetch();
                summaryQuery.refetch();
              }}
            />
          )}

          {/* Table area */}
          <div className="min-h-[520px] overflow-hidden rounded-md border border-border-default bg-surface-base">
            {renderListContent()}

            {!isListLoading && !isListError && totalCount > 0 && (
              <div className="flex items-center justify-between border-t border-border-default px-4 py-3 text-sm text-text-muted">
                <span>
                  {totalCount.toLocaleString()} record
                  {totalCount !== 1 ? "s" : ""}
                </span>
                {totalPages > 1 && (
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      disabled={page <= 1}
                      onClick={() => setPage((p) => Math.max(1, p - 1))}
                      className="h-8 rounded border border-border-default px-3 text-sm font-medium text-text-secondary transition-colors hover:bg-surface-hover disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      Previous
                    </button>
                    <span>
                      {page} / {totalPages}
                    </span>
                    <button
                      type="button"
                      disabled={page >= totalPages}
                      onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                      className="h-8 rounded border border-border-default px-3 text-sm font-medium text-text-secondary transition-colors hover:bg-surface-hover disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      Next
                    </button>
                  </div>
                )}
              </div>
            )}
          </div>
        </>
      )}

      {/* Footer system boundaries notice */}
      <section className="rounded-md border border-dashed border-gray-300 bg-gray-50 p-3">
        <div className="flex items-start gap-2 text-xs text-gray-600">
          <LockKeyhole className="mt-0.5 h-4 w-4 text-gray-400 shrink-0" aria-hidden="true" />
          <div>
            <span className="font-semibold text-gray-700">Read-Only Boundary:</span> Plantilla reads use{" "}
            <code className="font-mono bg-gray-100 px-1 rounded text-[11px]">get_web_plantilla_summary</code>,{" "}
            <code className="font-mono bg-gray-100 px-1 rounded text-[11px]">list_web_plantilla_employees</code>, and{" "}
            <code className="font-mono bg-gray-100 px-1 rounded text-[11px]">list_web_plantilla_store_staffing</code>.
            Employee transfers, AH slot management, separations, and other mutations remain disabled until backend action RPCs are approved.
          </div>
        </div>
      </section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Employee table
// ---------------------------------------------------------------------------

function EmployeeTable({
  rows,
  onRowClick,
}: {
  rows: PlantillaEmployeeListItem[];
  onRowClick: (id: string) => void;
}) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[1280px] text-left text-[0.9375rem]">
        <thead>
          <tr className="border-b border-table-rule bg-table-header">
            <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Emp ID
            </th>
            <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Name
            </th>
            <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Account / Store
            </th>
            <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Position
            </th>
            <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Assignment
            </th>
            <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Type
            </th>
            <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Status
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-table-rule">
          {rows.map((row) => {
            const overlay = deriveDeactivationOverlay(row.plantillaStatus);

            const rowClass = overlay.isPendingSeparation
              ? "border border-dashed border-status-danger-border bg-red-50/30 opacity-80 cursor-pointer transition-colors"
              : "transition-colors hover:bg-table-row-hover cursor-pointer";

            const displayName =
              row.lastName && row.firstName
                ? `${row.lastName}, ${row.firstName}`
                : (row.lastName ?? row.firstName ?? "—");

            return (
              <tr
                key={row.id}
                className={rowClass}
                onClick={() => onRowClick(row.id)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    onRowClick(row.id);
                  }
                }}
                tabIndex={0}
                role="button"
                aria-label={`View details for ${displayName}`}
              >
                <td className="px-3 py-2.5">
                  <span className="font-mono text-xs bg-mono-pill-surface border border-mono-pill-ring rounded px-1.5 py-0.5 text-table-text">
                    {row.employeeNo}
                  </span>
                </td>

                <td className="px-3 py-2.5 font-medium text-table-text">
                  <span>{displayName}</span>
                  {row.plantillaType === "AH" && (
                    <span className="ml-1.5 inline-flex items-center rounded border border-status-warning-border bg-amber-50 px-1.5 py-0.5 text-xs font-semibold text-status-warning-text">
                      AH
                    </span>
                  )}
                </td>

                <td className="px-4 py-2.5 text-table-text-sub">
                  <div className="leading-tight">
                    <div>{row.accountName ?? "—"}</div>
                    {row.primaryStoreName && (
                      <div className="text-xs text-table-text-muted">{row.primaryStoreName}</div>
                    )}
                  </div>
                </td>

                <td className="px-3 py-2.5 text-table-text-sub">{row.positionTitle ?? "—"}</td>

                <td className="px-3 py-2.5 text-table-text-sub">
                  {row.assignmentType === "Roving" && row.coveredStoresCount > 0 ? (
                    <span title={`Covers ${row.coveredStoresCount} store(s)`}>
                      Roving ({row.coveredStoresCount})
                    </span>
                  ) : (
                    (row.assignmentType ?? "—")
                  )}
                </td>

                <td className="px-3 py-2.5 text-xs text-table-text-sub">
                  {row.plantillaType ?? "—"}
                </td>

                <td className="px-4 py-2.5">
                  {row.plantillaStatus ? (
                    <span className="inline-flex items-center gap-1">
                      <StatusBadge
                        variant={plantillaStatusVariant(row.plantillaStatus)}
                        text={row.plantillaStatus}
                      />
                      {row.slaBreached && (
                        <span
                          className="text-xs font-semibold text-status-danger-text"
                          title="SLA breached"
                        >
                          ⚠
                        </span>
                      )}
                    </span>
                  ) : (
                    <span className="text-xs text-table-text-muted">—</span>
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Store staffing table
// ---------------------------------------------------------------------------

function formatFillRate(fillRate: number | null): string {
  if (fillRate === null) return "—";
  return `${(fillRate * 100).toFixed(1)}%`;
}

function StoreTable({
  rows,
  onRowClick,
}: {
  rows: PlantillaStoreStaffingRow[];
  onRowClick?: (row: PlantillaStoreStaffingRow) => void;
}) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[1400px] text-left text-[0.9375rem]">
        <thead>
          <tr className="border-b border-table-rule bg-table-header">
            <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Store Code
            </th>
            <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Store Name
            </th>
            <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Account / Region
            </th>
            <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Actual
            </th>
            <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              HR Pipeline
            </th>
            <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Vacancy
            </th>
            <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Required
            </th>
            <th
              className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted"
              title="Actual / (Actual + HR Pipeline + Vacancy)"
            >
              MFR %
            </th>
            <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Staffing Risk
            </th>
            <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              SLA Badge
            </th>
            <th className="px-4 py-2.5 text-right text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Actions
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-table-rule">
          {rows.map((row, index) => {
            const risk = deriveStaffingRisk(row);
            return (
              <tr
                key={`${row.storeId}-${row.storeCode ?? row.storeName ?? index}`}
                className="transition-colors hover:bg-table-row-hover cursor-pointer"
                onClick={() => onRowClick?.(row)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    onRowClick?.(row);
                  }
                }}
                tabIndex={0}
                role="button"
                aria-label={`View staffing details for ${row.storeName ?? "store"}`}
              >
                <td className="px-4 py-2.5">
                  <span className="font-mono text-xs text-table-text bg-mono-pill-surface border border-mono-pill-ring rounded px-1.5 py-0.5">
                    {row.storeCode ?? "—"}
                  </span>
                </td>

                <td className="px-4 py-2.5 font-medium text-table-text">
                  {row.storeName ?? "—"}
                </td>

                <td className="px-4 py-2.5 text-table-text-sub">
                  <div className="leading-tight">
                    <div>{row.accountName ?? "—"}</div>
                    {row.region && (
                      <div className="text-xs text-table-text-muted">{row.region}</div>
                    )}
                  </div>
                </td>

                {/* Actual — onboard_count from backend */}
                <td className="px-4 py-2.5 text-table-text-sub">{row.onboardCount}</td>

                {/* HR Pipeline — hr_pipeline_count from backend */}
                <td className="px-4 py-2.5 text-table-text-sub">{row.hrPipelineCount}</td>

                {/* Vacancy — open_headcount from backend */}
                <td className="px-4 py-2.5 text-table-text-sub">
                  {risk.vacancyCount > 0 ? (
                    <span
                      className={
                        risk.vacancySlaBreached ? "font-semibold text-status-danger-text" : ""
                      }
                    >
                      {risk.vacancyCount}
                      {risk.vacancySlaBreached && (
                        <span className="ml-1 text-xs" title="Vacancy SLA breached (7 days+)">
                          ⚠
                        </span>
                      )}
                    </span>
                  ) : (
                    <span className="text-table-text-muted">0</span>
                  )}
                </td>

                {/* Required — required_headcount from backend */}
                <td className="px-4 py-2.5 text-table-text-sub">{row.requiredHeadcount}</td>

                {/* MFR % — fill_rate from backend; formula: Actual / (Actual + HR Pipeline + Vacancy) */}
                <td
                  className="px-4 py-2.5 text-table-text-sub tabular-nums"
                  title="Actual / (Actual + HR Pipeline + Vacancy)"
                >
                  {formatFillRate(row.fillRate)}
                </td>

                <td className="px-4 py-2.5">
                  {risk.staffingRisk ? (
                    <StatusBadge
                      variant={staffingStatusVariant(risk.staffingRisk)}
                      text={risk.staffingRisk}
                    />
                  ) : (
                    <span className="text-xs text-table-text-muted">—</span>
                  )}
                </td>

                <td className="px-4 py-2.5">
                  {risk.slaBadge ? (
                    <StatusBadge
                      variant={staffingStatusVariant(risk.slaBadge)}
                      text={risk.slaBadge}
                    />
                  ) : (
                    <span className="text-xs text-table-text-muted">—</span>
                  )}
                </td>

                <td className="px-4 py-2.5 text-right">
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      onRowClick?.(row);
                    }}
                    className="inline-flex items-center gap-1 rounded border border-border-default bg-surface-base px-2.5 py-1 text-xs font-medium text-text-primary hover:bg-surface-hover shadow-xs transition-colors"
                  >
                    Manage Quota
                  </button>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
