"use client";

import { useState, useEffect, useMemo } from "react";
import { useQuery, useQueries } from "@tanstack/react-query";
import {
  LockKeyhole,
  Users,
  ArrowLeft,
  Building,
  Building2,
  Share2,
  ChevronRight,
  Plus,
  Search,
  RotateCcw,
  X,
  MapPin,
  Eye,
} from "lucide-react";
import { useSearchParams, useRouter, usePathname } from "next/navigation";
import { loadCurrentUserContext, isQuotaOverrideRole, isOpsAmendmentRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/client";
import { MetricCard } from "@/components/shared/MetricCard";
import { DataState } from "@/components/shared/DataState";
import { StatusBadge } from "@/components/ui/StatusBadge";
import type { BadgeVariant } from "@/components/ui/StatusBadge";
import {
  getPlantillaSummary,
  listWebPlantillaEmployees,
  deriveDeactivationOverlay,
  PlantillaDataError,
  type PlantillaEmployeeListItem,
  type PlantillaStoreStaffingRow,
} from "@/lib/queries/plantilla";
import { PlantillaDetailDrawer } from "@/components/plantilla/PlantillaDetailDrawer";
import { StoreStaffingDrawer } from "@/components/plantilla/StoreStaffingDrawer";
import { StoreStaffingOverviewDrawer } from "@/components/plantilla/StoreStaffingOverviewDrawer";
import { SlotDetailDrawer } from "@/components/plantilla/SlotDetailDrawer";
import { RequestHeadcountModal } from "@/components/modals/RequestHeadcountModal";

// ---------------------------------------------------------------------------
// Types & Constants
// ---------------------------------------------------------------------------

type ViewMode = "active" | "inactive";

const PAGE_SIZE = 25;

function plantillaStatusVariant(status: string | null | undefined): BadgeVariant {
  switch ((status ?? "").toLowerCase().trim()) {
    case "active":
      return "success";
    case "on leave":
    case "on_leave":
      return "warning";
    case "floating":
      return "neutral";
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

function getInitials(firstName: string | null, lastName: string | null): string {
  const f = (firstName?.trim() || "")[0] ?? "";
  const l = (lastName?.trim() || "")[0] ?? "";
  return (f + l).toUpperCase() || "EM";
}

// ---------------------------------------------------------------------------
// Page Component
// ---------------------------------------------------------------------------

export default function PlantillaPage() {
  const [view, setView] = useState<ViewMode>("active");
  const [page, setPage] = useState(1);
  const [selectedPlantillaId, setSelectedPlantillaId] = useState<string | null>(null);
  const [selectedStoreRow, setSelectedStoreRow] = useState<PlantillaStoreStaffingRow | null>(null);
  const [selectedSlotId, setSelectedSlotId] = useState<string | null>(null);
  const [isStoreStaffingOverviewOpen, setIsStoreStaffingOverviewOpen] = useState(false);
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

  // Directory filter state (internally managed — NO raw UUID inputs)
  const [accountId, setAccountId] = useState("");
  const [search, setSearch] = useState("");
  const [storeId, setStoreId] = useState("");
  const [status, setStatus] = useState("");
  const [assignmentType, setAssignmentType] = useState("");

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
    } else if (user) {
      const { accountScope } = user;
      if (accountScope.mode === "scoped" && accountScope.ids.length === 1) {
        setAccountId(accountScope.ids[0]);
      }
    }
    setIsHydrated(true);
    /* eslint-enable react-hooks/set-state-in-effect */
  }, [userContextQuery.data, searchParams]);

  // Stores under current account for dropdown & city/province lookup
  const storesUnderAccountQuery = useQuery({
    queryKey: ["plantilla", "account-stores", accountId],
    queryFn: async () => {
      if (!accountId) return [];
      const supabase = createClient();
      const { data, error } = await supabase
        .from("stores")
        .select("id, store_name, store_code, area_city, area_province, province")
        .eq("account_id", accountId)
        .eq("is_active", true)
        .order("store_name");
      if (error) throw error;
      return (data ?? []).map((s) => ({
        id: s.id as string,
        name: s.store_name as string,
        code: (s.store_code as string | null) ?? null,
        city: (s.area_city as string | null) ?? null,
        province: ((s.area_province ?? s.province) as string | null) ?? null,
      }));
    },
    enabled: !!accountId,
    staleTime: 30000,
  });

  const storeLookupMap = useMemo(() => {
    const map = new Map<string, { city: string | null; province: string | null; code: string | null }>();
    (storesUnderAccountQuery.data ?? []).forEach((s) => {
      const info = { city: s.city, province: s.province, code: s.code };
      map.set(s.name.toLowerCase().trim(), info);
      map.set(s.id, info);
    });
    return map;
  }, [storesUnderAccountQuery.data]);

  // -------------------------------------------------------------------------
  // Queries (Gated behind accountId)
  // -------------------------------------------------------------------------

  const summaryQuery = useQuery({
    queryKey: ["plantilla", "summary", { search, accountId, selectorGroupId }],
    queryFn: () =>
      getPlantillaSummary({
        search: accountId ? (search || undefined) : undefined,
        accountId: accountId || undefined,
        groupId: selectorGroupId || undefined,
      }),
    enabled: isHydrated && !!currentUser,
  });

  // Query for active roster or inactive roster
  const employeeQuery = useQuery({
    queryKey: [
      "plantilla",
      "employees",
      { search, accountId, storeId, status, assignmentType, page, view },
    ],
    queryFn: () =>
      listWebPlantillaEmployees({
        search: search.trim() || undefined,
        accountId: accountId || undefined,
        storeId: storeId || undefined,
        status: status || undefined,
        deployment: assignmentType || undefined,
        activeState: view === "inactive" ? "inactive" : "active",
        page,
        pageSize: PAGE_SIZE,
      }),
    enabled: !!accountId,
  });

  // Count query for inactive badge
  const inactiveCountQuery = useQuery({
    queryKey: ["plantilla", "inactive-count", accountId],
    queryFn: async () => {
      if (!accountId) return 0;
      const res = await listWebPlantillaEmployees({
        accountId,
        activeState: "inactive",
        page: 1,
        pageSize: 1,
      });
      return res.totalCount;
    },
    enabled: !!accountId,
    staleTime: 30000,
  });

  // -------------------------------------------------------------------------
  // Derived state
  // -------------------------------------------------------------------------

  const summaryData = summaryQuery.data;
  const summaryError =
    summaryQuery.error instanceof PlantillaDataError ? summaryQuery.error : null;
  const summaryBlocked = summaryError?.kind === "access_denied";

  const listError =
    employeeQuery.error instanceof PlantillaDataError ? employeeQuery.error : null;

  const isListLoading = employeeQuery.isLoading;
  const isListError = employeeQuery.isError && !isListLoading;
  const isAccessDenied = listError?.kind === "access_denied";
  const isRetryable = isListError && !isAccessDenied;

  const employeeRows = employeeQuery.data?.data ?? [];
  const totalCount = employeeQuery.data?.totalCount ?? 0;
  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));

  const hasActiveFilters = Boolean(search.trim() || storeId || status || assignmentType);

  const activeCount = summaryData?.actual ?? (view === "active" ? totalCount : 0);
  const inactiveCount = inactiveCountQuery.data ?? (view === "inactive" ? totalCount : 0);

  const fulfillmentRate =
    summaryData?.required && summaryData.required > 0
      ? Math.round(((summaryData.actual ?? 0) / summaryData.required) * 100)
      : 0;

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
    setSearch("");
    setStoreId("");
    setStatus("");
    setAssignmentType("");
    setPage(1);

    const params = new URLSearchParams(searchParams.toString());
    params.set("accountId", accId);
    router.push(`${pathname}?${params.toString()}`);
  }

  function handleBackToSelection() {
    setAccountId("");
    setSearch("");
    setStoreId("");
    setStatus("");
    setAssignmentType("");
    setPage(1);

    const params = new URLSearchParams(searchParams.toString());
    params.delete("accountId");
    router.push(`${pathname}?${params.toString()}`);
  }

  function handleResetFilters() {
    setSearch("");
    setStoreId("");
    setStatus("");
    setAssignmentType("");
    setPage(1);
  }

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
              className="h-10 w-full rounded-lg border border-border-default bg-surface-base px-3 text-sm text-text-primary outline-none focus:border-brand-500 transition-colors"
            />
          </div>
          {uniqueGroups.length > 0 && (
            <select
              value={selectorGroupId}
              onChange={(e) => setSelectorGroupId(e.target.value)}
              className="h-10 rounded-lg border border-border-default bg-surface-base px-3 text-sm text-text-primary outline-none focus:border-brand-500 transition-colors"
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
  const showBackToSelection =
    currentUser?.accountScope.mode === "all" ||
    (currentUser?.accountScope.mode === "scoped" && currentUser?.accountScope.ids.length > 1);

  return (
    <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-6 text-gray-900">
      {!accountId ? (
        <>
          <div className="flex flex-col gap-1">
            <h1 className="text-2xl font-bold tracking-tight text-text-primary">
              Plantilla Directory
            </h1>
            <p className="text-sm text-text-secondary">
              Select a billing account to audit roster allocations, capacity targets, and staffing governance.
            </p>
          </div>
          {renderAccountSelectionContent()}
        </>
      ) : (
        <>
          {/* 1. Header & Context Strip */}
          <header className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between border-b border-border-default pb-4">
            <div className="space-y-1.5">
              {/* Breadcrumb Backlink */}
              <nav className="flex items-center gap-1.5 text-xs text-text-muted" aria-label="Breadcrumb">
                {showBackToSelection ? (
                  <button
                    type="button"
                    onClick={handleBackToSelection}
                    className="inline-flex items-center gap-1 font-medium text-text-secondary hover:text-brand-600 transition-colors"
                  >
                    <ArrowLeft className="h-3.5 w-3.5" />
                    <span>Account Selection</span>
                  </button>
                ) : (
                  <span>Plantilla Directory</span>
                )}
                <span className="text-text-muted/60">/</span>
                <span className="font-semibold text-text-primary truncate max-w-[240px] sm:max-w-none">
                  {selectedAccountName}
                </span>
              </nav>

              {/* Title with account name and role badge */}
              <div className="flex flex-wrap items-center gap-2.5">
                <h1 className="text-xl sm:text-2xl font-bold tracking-tight text-text-primary">
                  {selectedAccountName}
                </h1>
                {userRole && (
                  <span className="inline-flex items-center rounded-full bg-brand-50 border border-brand-200/80 px-2.5 py-0.5 text-xs font-semibold text-brand-700 capitalize">
                    {userRole.replace(/_/g, " ")}
                  </span>
                )}
              </div>
              <p className="text-xs text-text-secondary">
                Managing roster allocations, capacity targets, and staffing offboarding.
              </p>
            </div>

            {/* Right-aligned Action Bar */}
            <div className="flex flex-wrap items-center gap-2.5">
              {/* Secondary button: Store Staffing drawer trigger with quota badge */}
              <button
                type="button"
                onClick={() => setIsStoreStaffingOverviewOpen(true)}
                className="inline-flex h-10 items-center gap-2 rounded-lg border border-border-default bg-surface-base px-3.5 text-xs sm:text-sm font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary hover:border-border-subtle transition-colors shadow-xs"
              >
                <Building2 className="h-4 w-4 text-text-muted" />
                <span>Store Staffing</span>
                <span className="inline-flex items-center rounded-full bg-surface-muted px-2 py-0.5 text-[11px] font-bold text-text-primary border border-border-default font-mono">
                  {summaryData?.required ?? 0} Quota
                </span>
              </button>

              {/* Primary button: + Request Headcount (with icon) */}
              {canRequestAdjustment && (
                <button
                  type="button"
                  onClick={() => setIsRequestHeadcountOpen(true)}
                  className="inline-flex h-10 items-center gap-2 rounded-lg bg-brand-600 px-4 text-xs sm:text-sm font-semibold text-white shadow-xs hover:bg-brand-700 transition-colors focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
                >
                  <Plus className="h-4 w-4" />
                  <span>Request Headcount</span>
                </button>
              )}
            </div>
          </header>

          {/* 2. Metrics Bar Refinement */}
          <section aria-label="Plantilla summary metrics" className="space-y-3">
            <div className="grid gap-3 grid-cols-2 lg:grid-cols-4">
              <MetricCard
                label="Required Quota"
                value={summaryData?.required}
                helperText="Total budgeted capacity quota"
                isLoading={summaryQuery.isLoading}
                isBlocked={summaryBlocked}
                isError={!summaryBlocked && summaryQuery.isError}
                errorText="Summary data failed to load"
              />
              <MetricCard
                label="Active Deployed"
                value={summaryData?.actual}
                helperText="Active deployed on-site"
                badge={summaryData?.required ? `${fulfillmentRate}% fulfilled` : undefined}
                isLoading={summaryQuery.isLoading}
                isBlocked={summaryBlocked}
                isError={!summaryBlocked && summaryQuery.isError}
                errorText="Summary data failed to load"
              />
              <MetricCard
                label="HR Pipeline"
                value={summaryData?.hrProcess}
                helperText="Onboarding & candidate pipeline"
                isLoading={summaryQuery.isLoading}
                isBlocked={summaryBlocked}
                isError={!summaryBlocked && summaryQuery.isError}
                errorText="Summary data failed to load"
              />
              <MetricCard
                label="Open Vacant"
                value={summaryData?.vacant}
                helperText="Approved open vacancy slots"
                isLoading={summaryQuery.isLoading}
                isBlocked={summaryBlocked}
                isError={!summaryBlocked && summaryQuery.isError}
                errorText="Summary data failed to load"
              />
            </div>

            {/* Subtle fulfillment rate indicator strip */}
            {!summaryBlocked && !summaryQuery.isLoading && (summaryData?.required ?? 0) > 0 && (
              <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2.5 rounded-xl border border-border-default bg-surface-muted/40 px-4 py-2.5 text-xs text-text-secondary shadow-xs">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="font-semibold text-text-primary">Fulfillment Rate (MFR):</span>
                  <span className="font-mono font-bold text-text-primary">{fulfillmentRate}%</span>
                  <span className="text-text-muted">
                    ({summaryData?.actual ?? 0} active deployed / {summaryData?.required ?? 0} required quota)
                  </span>
                </div>
                <div className="flex items-center gap-3 w-full sm:w-64">
                  <div className="relative flex-1 h-2 rounded-full bg-gray-200 overflow-hidden">
                    <div
                      className={`absolute left-0 top-0 h-full rounded-full transition-all duration-500 ${
                        fulfillmentRate >= 100
                          ? "bg-emerald-500"
                          : fulfillmentRate >= 95
                          ? "bg-amber-500"
                          : "bg-red-500"
                      }`}
                      style={{ width: `${Math.min(100, fulfillmentRate)}%` }}
                    />
                  </div>
                  <span
                    className={`font-mono font-bold text-xs shrink-0 ${
                      fulfillmentRate >= 100
                        ? "text-emerald-700"
                        : fulfillmentRate >= 95
                        ? "text-amber-700"
                        : "text-red-700"
                    }`}
                  >
                    {fulfillmentRate}%
                  </span>
                </div>
              </div>
            )}
          </section>

          {/* 3. Toolbar & Filter Redesign */}
          <div className="space-y-3">
            {/* Segmented Tab Switcher */}
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div
                role="tablist"
                aria-label="Plantilla roster view"
                className="inline-flex items-center rounded-lg border border-border-default bg-surface-muted p-1"
              >
                <button
                  type="button"
                  role="tab"
                  aria-selected={view === "active"}
                  onClick={() => {
                    if (view !== "active") {
                      setView("active");
                      setPage(1);
                    }
                  }}
                  className={`inline-flex items-center gap-2 rounded-md px-3.5 py-1.5 text-xs font-semibold transition-all ${
                    view === "active"
                      ? "bg-surface-base text-text-primary shadow-xs"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Active Roster</span>
                  <span
                    className={`inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-bold font-mono transition-colors ${
                      view === "active"
                        ? "bg-brand-50 text-brand-700 border border-brand-200/80"
                        : "bg-surface-base text-text-muted border border-border-default"
                    }`}
                  >
                    {activeCount}
                  </span>
                </button>

                <button
                  type="button"
                  role="tab"
                  aria-selected={view === "inactive"}
                  onClick={() => {
                    if (view !== "inactive") {
                      setView("inactive");
                      setPage(1);
                    }
                  }}
                  className={`inline-flex items-center gap-2 rounded-md px-3.5 py-1.5 text-xs font-semibold transition-all ${
                    view === "inactive"
                      ? "bg-surface-base text-text-primary shadow-xs"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                >
                  <span>Inactive / Floating</span>
                  <span
                    className={`inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-bold font-mono transition-colors ${
                      view === "inactive"
                        ? "bg-purple-50 text-purple-700 border border-purple-200/80"
                        : "bg-surface-base text-text-muted border border-border-default"
                    }`}
                  >
                    {inactiveCount}
                  </span>
                </button>
              </div>
            </div>

            {/* Unified Search & Filter Bar */}
            <div className="flex flex-col lg:flex-row items-stretch lg:items-center gap-2.5 rounded-xl border border-border-default bg-surface-base p-3 shadow-xs">
              {/* Prominent search input with instant clear */}
              <div className="relative flex-1 min-w-[260px]">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted" />
                <input
                  type="text"
                  placeholder="Search by member name, store, VCode, or position..."
                  value={search}
                  onChange={(e) => {
                    setSearch(e.target.value);
                    setPage(1);
                  }}
                  className="h-10 w-full rounded-lg border border-border-default bg-surface-muted pl-9 pr-9 text-sm text-text-primary outline-none transition-colors focus:border-brand-500 focus:bg-surface-base"
                  aria-label="Search plantilla roster"
                />
                {search && (
                  <button
                    type="button"
                    onClick={() => {
                      setSearch("");
                      setPage(1);
                    }}
                    className="absolute right-2.5 top-1/2 -translate-y-1/2 rounded-full p-1 text-text-muted hover:text-text-primary hover:bg-surface-hover transition-colors"
                    aria-label="Clear search"
                  >
                    <X className="h-3.5 w-3.5" />
                  </button>
                )}
              </div>

              {/* Dropdowns row */}
              <div className="flex flex-wrap items-center gap-2">
                {/* Store selector dropdown */}
                <div className="min-w-[170px] flex-1 sm:flex-initial">
                  <select
                    value={storeId}
                    onChange={(e) => {
                      setStoreId(e.target.value);
                      setPage(1);
                    }}
                    className="h-10 w-full rounded-lg border border-border-default bg-surface-base px-3 text-xs sm:text-sm text-text-primary outline-none transition-colors focus:border-brand-500 cursor-pointer"
                    aria-label="Filter by store"
                  >
                    <option value="">All Stores</option>
                    {(storesUnderAccountQuery.data ?? []).map((s) => (
                      <option key={s.id} value={s.id}>
                        {s.name} {s.city ? `(${s.city})` : ""}
                      </option>
                    ))}
                  </select>
                </div>

                {/* Status dropdown */}
                <div className="min-w-[130px] flex-1 sm:flex-initial">
                  <select
                    value={status}
                    onChange={(e) => {
                      setStatus(e.target.value);
                      setPage(1);
                    }}
                    className="h-10 w-full rounded-lg border border-border-default bg-surface-base px-3 text-xs sm:text-sm text-text-primary outline-none transition-colors focus:border-brand-500 cursor-pointer"
                    aria-label="Filter by status"
                  >
                    <option value="">All Statuses</option>
                    <option value="active">Active</option>
                    <option value="on leave">On Leave</option>
                    <option value="floating">Floating</option>
                  </select>
                </div>

                {/* Assignment Type dropdown */}
                <div className="min-w-[130px] flex-1 sm:flex-initial">
                  <select
                    value={assignmentType}
                    onChange={(e) => {
                      setAssignmentType(e.target.value);
                      setPage(1);
                    }}
                    className="h-10 w-full rounded-lg border border-border-default bg-surface-base px-3 text-xs sm:text-sm text-text-primary outline-none transition-colors focus:border-brand-500 cursor-pointer"
                    aria-label="Filter by assignment type"
                  >
                    <option value="">All Types</option>
                    <option value="stationary">Stationary</option>
                    <option value="roving">Roving</option>
                    <option value="reliever">Reliever</option>
                  </select>
                </div>

                {/* Reset / Clear filters button only when active filters exist */}
                {hasActiveFilters && (
                  <button
                    type="button"
                    onClick={handleResetFilters}
                    className="inline-flex h-10 items-center gap-1.5 rounded-lg border border-rose-200/80 bg-rose-50 px-3 text-xs font-semibold text-rose-700 hover:bg-rose-100 hover:text-rose-800 transition-colors shadow-xs"
                  >
                    <RotateCcw className="h-3.5 w-3.5" />
                    <span>Reset Filters</span>
                  </button>
                )}
              </div>
            </div>
          </div>

          {/* 4. Table Polish Area */}
          <div className="min-h-[520px] overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs">
            {isListLoading ? (
              <DataState
                kind="loading"
                title="Loading plantilla records"
                description="Fetching personnel roster through Supabase RPCs..."
              />
            ) : isAccessDenied ? (
              <DataState
                kind="access_denied"
                title="Access Restricted"
                description="Supabase RLS policies blocked this read. You are not authorized to view plantilla records outside your scoped boundary."
              />
            ) : isRetryable ? (
              <DataState
                kind="error"
                title="Fetch Failed"
                description={
                  listError?.message ??
                  "The plantilla query failed. You can retry without changing filters."
                }
                onRetry={() => employeeQuery.refetch()}
              />
            ) : employeeRows.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-16 px-4 text-center">
                <div className="relative mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-brand-50 border border-brand-100 shadow-xs">
                  <Users className="h-8 w-8 text-brand-600" />
                  {hasActiveFilters && (
                    <span className="absolute -top-1 -right-1 flex h-5 w-5 items-center justify-center rounded-full bg-amber-500 text-[10px] font-bold text-white shadow-xs">
                      !
                    </span>
                  )}
                </div>
                <h3 className="text-base font-bold text-text-primary">
                  {hasActiveFilters
                    ? "No matching plantilla records"
                    : view === "inactive"
                    ? "No inactive or floating records"
                    : "No active employee records"}
                </h3>
                <p className="mt-1.5 max-w-sm text-xs text-text-muted leading-relaxed">
                  {hasActiveFilters
                    ? "We couldn't find any employees matching your current search or filter criteria. Try adjusting your parameters."
                    : view === "inactive"
                    ? "There are currently no inactive, suspended, or floating personnel for this account."
                    : "There are currently no active personnel deployed under this account."}
                </p>
                {hasActiveFilters && (
                  <button
                    type="button"
                    onClick={handleResetFilters}
                    className="mt-4 inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3.5 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary transition-colors shadow-xs"
                  >
                    <RotateCcw className="h-3.5 w-3.5" />
                    <span>Reset all filters</span>
                  </button>
                )}
              </div>
            ) : (
              <EmployeeTable
                rows={employeeRows}
                onRowClick={setSelectedPlantillaId}
                storeLookupMap={storeLookupMap}
              />
            )}

            {!isListLoading && !isListError && totalCount > 0 && (
              <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 border-t border-border-default px-4 py-3 text-xs sm:text-sm text-text-muted">
                <span>
                  Showing {Math.min((page - 1) * PAGE_SIZE + 1, totalCount)}–
                  {Math.min(page * PAGE_SIZE, totalCount)} of {totalCount.toLocaleString()} record
                  {totalCount !== 1 ? "s" : ""}
                </span>
                {totalPages > 1 && (
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      disabled={page <= 1}
                      onClick={() => setPage((p) => Math.max(1, p - 1))}
                      className="h-8 rounded-lg border border-border-default px-3 text-xs font-semibold text-text-secondary transition-colors hover:bg-surface-hover disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      Previous
                    </button>
                    <span className="font-medium text-text-secondary">
                      {page} of {totalPages}
                    </span>
                    <button
                      type="button"
                      disabled={page >= totalPages}
                      onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                      className="h-8 rounded-lg border border-border-default px-3 text-xs font-semibold text-text-secondary transition-colors hover:bg-surface-hover disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      Next
                    </button>
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Drawers & Modals */}
          <PlantillaDetailDrawer
            plantillaId={selectedPlantillaId}
            onClose={() => setSelectedPlantillaId(null)}
          />

          <StoreStaffingOverviewDrawer
            isOpen={isStoreStaffingOverviewOpen}
            onClose={() => setIsStoreStaffingOverviewOpen(false)}
            accountId={accountId}
            accountName={selectedAccountName}
            summaryRequiredQuota={summaryData?.required}
            canReviseQuota={canReviseQuota}
            canRequestAdjustment={canRequestAdjustment}
            onSelectStore={(store) => {
              setSelectedStoreRow(store);
            }}
          />

          <StoreStaffingDrawer
            storeRow={selectedStoreRow}
            onClose={() => setSelectedStoreRow(null)}
            canReviseQuota={canReviseQuota}
            canRequestAdjustment={canRequestAdjustment}
            onInspectSlot={(slotId) => setSelectedSlotId(slotId)}
            accountId={accountId}
            accountName={selectedAccountName}
          />

          <SlotDetailDrawer
            slotId={selectedSlotId}
            onClose={() => setSelectedSlotId(null)}
          />

          {isRequestHeadcountOpen && (
            <RequestHeadcountModal
              isOpen={isRequestHeadcountOpen}
              onClose={() => setIsRequestHeadcountOpen(false)}
              accountId={accountId}
              accountName={selectedAccountName}
              onSuccess={() => {
                employeeQuery.refetch();
                summaryQuery.refetch();
                inactiveCountQuery.refetch();
              }}
            />
          )}

          {/* Footer system boundaries notice */}
          <section className="rounded-xl border border-dashed border-gray-300 bg-gray-50/80 p-3.5">
            <div className="flex items-start gap-2.5 text-xs text-gray-600">
              <LockKeyhole className="mt-0.5 h-4 w-4 text-gray-400 shrink-0" aria-hidden="true" />
              <div>
                <span className="font-semibold text-gray-700">Governance & Boundary:</span> Plantilla data is queried securely via scoped RPCs (
                <code className="font-mono bg-gray-100 px-1 py-0.5 rounded text-[11px]">get_web_plantilla_summary</code>,{" "}
                <code className="font-mono bg-gray-100 px-1 py-0.5 rounded text-[11px]">list_web_plantilla_employees</code>, and{" "}
                <code className="font-mono bg-gray-100 px-1 py-0.5 rounded text-[11px]">list_web_plantilla_store_staffing</code>).
                All quota modifications and personnel movements enforce ADR-001 audit logging and safety floor verification.
              </div>
            </div>
          </section>
        </>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Employee Table Component
// ---------------------------------------------------------------------------

function EmployeeTable({
  rows,
  onRowClick,
  storeLookupMap,
}: {
  rows: PlantillaEmployeeListItem[];
  onRowClick: (id: string) => void;
  storeLookupMap: Map<string, { city: string | null; province: string | null; code: string | null }>;
}) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[980px] text-left text-sm">
        <thead>
          <tr className="border-b border-table-rule bg-table-header">
            <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Member
            </th>
            <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Store
            </th>
            <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Position
            </th>
            <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Assignment
            </th>
            <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Status
            </th>
            <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-normal text-table-text-muted">
              Actions
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

            const initials = getInitials(row.firstName, row.lastName);

            // Lookup City/Province for store
            const storeInfo = row.primaryStoreName
              ? storeLookupMap.get(row.primaryStoreName.toLowerCase().trim())
              : null;
            const locationLabel = [storeInfo?.city, storeInfo?.province].filter(Boolean).join(", ");

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
                {/* MEMBER: Formatted employee name with avatar initials and subtle ID subtitle */}
                <td className="px-4 py-3">
                  <div className="flex items-center gap-3">
                    <div className="h-9 w-9 rounded-full bg-brand-50 border border-brand-200/70 text-brand-700 font-bold text-xs flex items-center justify-center shrink-0 shadow-xs">
                      {initials}
                    </div>
                    <div className="min-w-0">
                      <div className="flex items-center gap-1.5 flex-wrap">
                        <span className="font-semibold text-table-text text-sm hover:text-brand-600 transition-colors">
                          {displayName}
                        </span>
                        {row.plantillaType === "AH" && (
                          <span className="inline-flex items-center rounded border border-status-warning-border bg-amber-50 px-1.5 py-0.2 text-[10px] font-bold text-status-warning-text">
                            AH
                          </span>
                        )}
                      </div>
                      <div className="font-mono text-xs text-table-text-muted mt-0.5">
                        {row.employeeNo}
                      </div>
                    </div>
                  </div>
                </td>

                {/* STORE: Outlet name with City/Province pill */}
                <td className="px-4 py-3 text-table-text">
                  <div className="min-w-0">
                    <div className="font-medium text-table-text truncate">
                      {row.primaryStoreName || "Unassigned Outlet"}
                    </div>
                    {locationLabel ? (
                      <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-2 py-0.5 text-[11px] font-medium text-text-secondary border border-border-subtle mt-1">
                        <MapPin className="h-3 w-3 text-text-muted shrink-0" />
                        <span className="truncate max-w-[150px]">{locationLabel}</span>
                      </span>
                    ) : row.accountName ? (
                      <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-2 py-0.5 text-[11px] font-medium text-text-muted border border-border-subtle mt-1 truncate max-w-[150px]">
                        {row.accountName}
                      </span>
                    ) : null}
                  </div>
                </td>

                {/* POSITION: Job position with level or tier */}
                <td className="px-4 py-3">
                  <div className="flex flex-col">
                    <span className="font-medium text-table-text text-sm">
                      {row.positionTitle ?? "General Staff"}
                    </span>
                    <span className="text-xs text-table-text-muted mt-0.5">
                      {row.plantillaType ? `${row.plantillaType} Position` : "Standard Tier"}
                    </span>
                  </div>
                </td>

                {/* ASSIGNMENT: Clean badge (Stationary / Roving / Reliever) */}
                <td className="px-4 py-3">
                  {row.assignmentType?.toLowerCase() === "roving" ? (
                    <span className="inline-flex items-center gap-1 rounded-md bg-sky-50 border border-sky-200/80 px-2 py-0.5 text-xs font-semibold text-sky-700">
                      Roving{row.coveredStoresCount > 1 ? ` (${row.coveredStoresCount})` : ""}
                    </span>
                  ) : row.assignmentType?.toLowerCase() === "reliever" ? (
                    <span className="inline-flex items-center gap-1 rounded-md bg-purple-50 border border-purple-200/80 px-2 py-0.5 text-xs font-semibold text-purple-700">
                      Reliever
                    </span>
                  ) : (
                    <span className="inline-flex items-center gap-1 rounded-md bg-slate-50 border border-slate-200/80 px-2 py-0.5 text-xs font-semibold text-slate-700">
                      Stationary
                    </span>
                  )}
                </td>

                {/* STATUS: Design-token StatusBadge */}
                <td className="px-4 py-3">
                  {row.plantillaStatus ? (
                    <span className="inline-flex items-center gap-1.5">
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

                {/* ACTIONS: One-click button to open PlantillaDetailDrawer */}
                <td className="px-4 py-3 text-right">
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      onRowClick(row.id);
                    }}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-secondary hover:text-brand-600 hover:border-brand-300 hover:bg-brand-50/40 transition-colors shadow-xs"
                    aria-label={`View details for ${displayName}`}
                  >
                    <Eye className="h-3.5 w-3.5" />
                    <span>Details</span>
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
