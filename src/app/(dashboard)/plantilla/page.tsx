"use client";

import { useState, useEffect, useMemo } from "react";
import { useQuery, useQueries } from "@tanstack/react-query";
import {
  LockKeyhole,
  Users,
  Building,
  Building2,
  Share2,
  ChevronLeft,
  ChevronRight,
  Plus,
  Search,
  RotateCcw,
  X,
  MapPin,
  Filter,
  Briefcase,
} from "lucide-react";
import { useSearchParams, useRouter, usePathname } from "next/navigation";
import { loadCurrentUserContext, isQuotaOverrideRole, isOpsAmendmentRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/client";
import { DataState } from "@/components/shared/DataState";
import { StatusBadge } from "@/components/ui/StatusBadge";
import type { BadgeVariant } from "@/components/ui/StatusBadge";
import {
  getPlantillaSummary,
  listWebPlantillaEmployees,
  fetchNeedsHrcoEmployees,
  fetchUnassignedHrcoCount,
  deriveDeactivationOverlay,
  PlantillaDataError,
  type PlantillaEmployeeListItem,
  type PlantillaStoreStaffingRow,
} from "@/lib/queries/plantilla";
import { fetchTeamDirectory, type TeamDirectoryUser } from "@/lib/queries/team_directory";
import { listVacancies, type VacancyListItem } from "@/lib/queries/vacancy";
import { PlantillaDetailDrawer } from "@/components/plantilla/PlantillaDetailDrawer";
import { StoreStaffingDrawer } from "@/components/plantilla/StoreStaffingDrawer";
import { StoreStaffingOverviewDrawer } from "@/components/plantilla/StoreStaffingOverviewDrawer";
import { SlotDetailDrawer } from "@/components/plantilla/SlotDetailDrawer";
import { RequestHeadcountModal } from "@/components/modals/RequestHeadcountModal";

// ---------------------------------------------------------------------------
// Types & Constants
// ---------------------------------------------------------------------------

type DirectoryTab = "active" | "vacancy" | "inactive" | "needs_hr";

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

function getInitials(firstName: string | null, lastName: string | null, fullName?: string | null): string {
  if (firstName || lastName) {
    const f = (firstName?.trim() || "")[0] ?? "";
    const l = (lastName?.trim() || "")[0] ?? "";
    return (f + l).toUpperCase() || "EM";
  }
  if (fullName && fullName.trim()) {
    const parts = fullName.trim().split(/\s+/);
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return (parts[0][0] ?? "E").toUpperCase();
  }
  return "EM";
}

function formatLeadershipName(user: TeamDirectoryUser): string {
  if (user.firstName && user.lastName) {
    return `${user.firstName[0].toUpperCase()}. ${user.lastName}`;
  }
  if (user.fullName) {
    if (user.fullName.includes(",")) {
      const parts = user.fullName.split(",");
      const last = parts[0]?.trim();
      const first = parts.slice(1).join(",").trim();
      if (first && last) {
        return `${first[0].toUpperCase()}. ${last}`;
      }
    }
    const parts = user.fullName.trim().split(/\s+/);
    if (parts.length > 1) {
      const first = parts[0];
      const last = parts.slice(1).join(" ");
      return `${first[0].toUpperCase()}. ${last}`;
    }
    return user.fullName;
  }
  return "—";
}

// ---------------------------------------------------------------------------
// Page Component
// ---------------------------------------------------------------------------

export default function PlantillaPage() {
  const [tab, setTab] = useState<DirectoryTab>("active");
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

  // Directory filter state
  const [accountId, setAccountId] = useState("");
  const [search, setSearch] = useState("");
  const [storeId, setStoreId] = useState("");
  const [status, setStatus] = useState("");
  const [assignmentType, setAssignmentType] = useState("");
  const [isFilterOpen, setIsFilterOpen] = useState(false);

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
    enabled: isHydrated && !!currentUser && !!accountId,
  });

  // Query for leadership roles: OM, TL, ATL, HRCO
  const teamDirectoryQuery = useQuery({
    queryKey: ["team-directory", "plantilla-account", accountId],
    queryFn: () => fetchTeamDirectory({ accountId }),
    enabled: !!accountId,
    staleTime: 60000,
  });

  const leadershipTeam = useMemo(() => {
    const users = teamDirectoryQuery.data ?? [];
    const om: string[] = [];
    const tl: string[] = [];
    const atl: string[] = [];
    const hrco: string[] = [];

    for (const u of users) {
      const role = (u.roleName || "").toLowerCase().replace(/[^a-z0-9]/g, "");
      const formatted = formatLeadershipName(u);
      if (!formatted || formatted === "—") continue;

      if (role === "om" || role === "operationsmanager") {
        om.push(formatted);
      } else if (role === "tl" || role === "teamleader") {
        tl.push(formatted);
      } else if (role === "atl" || role === "assistantteamleader") {
        atl.push(formatted);
      } else if (role === "hrco" || role === "hrcoordinator") {
        hrco.push(formatted);
      }
    }

    const formatRoleDisplay = (names: string[]) => {
      const unique = Array.from(new Set(names));
      if (unique.length === 0) return "—";
      if (unique.length <= 2) return unique.join(", ");
      return `${unique[0]}, ${unique[1]} +${unique.length - 2} more`;
    };

    return {
      om: formatRoleDisplay(om),
      tl: formatRoleDisplay(tl),
      atl: formatRoleDisplay(atl),
      hrco: formatRoleDisplay(hrco),
    };
  }, [teamDirectoryQuery.data]);

  // Query for active or inactive roster
  const employeeQuery = useQuery({
    queryKey: [
      "plantilla",
      "employees",
      { search, accountId, storeId, status, assignmentType, page, tab },
    ],
    queryFn: () =>
      listWebPlantillaEmployees({
        search: search.trim() || undefined,
        accountId: accountId || undefined,
        storeId: storeId || undefined,
        status: status || undefined,
        deployment: assignmentType || undefined,
        activeState: tab === "inactive" ? "inactive" : "active",
        page,
        pageSize: PAGE_SIZE,
      }),
    enabled: !!accountId && (tab === "active" || tab === "inactive"),
  });

  // Query for vacancies
  const vacancyListQuery = useQuery({
    queryKey: ["plantilla", "vacancies", accountId, search, page],
    queryFn: () =>
      listVacancies({
        accountId: accountId || undefined,
        search: search.trim() || undefined,
        status: "open",
        page,
        pageSize: PAGE_SIZE,
      }),
    enabled: !!accountId && tab === "vacancy",
    staleTime: 30000,
  });

  // Query for Needs HR... employees
  const needsHrcoQuery = useQuery({
    queryKey: ["plantilla", "needs-hrco-list", accountId, search],
    queryFn: () => fetchNeedsHrcoEmployees(accountId, search),
    enabled: !!accountId && tab === "needs_hr",
    staleTime: 30000,
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

  // Count query for Needs HR... badge
  const unassignedHrcoCountQuery = useQuery({
    queryKey: ["plantilla", "unassigned-hrco-count", accountId],
    queryFn: () => fetchUnassignedHrcoCount(accountId),
    enabled: !!accountId,
    staleTime: 30000,
  });

  // -------------------------------------------------------------------------
  // Derived state
  // -------------------------------------------------------------------------

  const summaryData = summaryQuery.data;

  const listError =
    employeeQuery.error instanceof PlantillaDataError ? employeeQuery.error : null;

  const isListLoading =
    tab === "vacancy"
      ? vacancyListQuery.isLoading
      : tab === "needs_hr"
      ? needsHrcoQuery.isLoading
      : employeeQuery.isLoading;

  const isListError =
    tab === "vacancy"
      ? vacancyListQuery.isError && !vacancyListQuery.isLoading
      : tab === "needs_hr"
      ? needsHrcoQuery.isError && !needsHrcoQuery.isLoading
      : employeeQuery.isError && !employeeQuery.isLoading;

  const isAccessDenied = listError?.kind === "access_denied";
  const isRetryable = isListError && !isAccessDenied;

  const employeeRows = employeeQuery.data?.data ?? [];
  const vacancyRows = vacancyListQuery.data?.data ?? [];
  const needsHrRows = needsHrcoQuery.data ?? [];

  const totalCount =
    tab === "vacancy"
      ? vacancyListQuery.data?.totalCount ?? 0
      : tab === "needs_hr"
      ? needsHrRows.length
      : employeeQuery.data?.totalCount ?? 0;

  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));

  const hasActiveFilters = Boolean(search.trim() || storeId || status || assignmentType);

  const activeCount = summaryData?.actual ?? 0;
  const vacancyCount = summaryData?.vacant ?? 0;
  const inactiveCount = inactiveCountQuery.data ?? 0;
  const needsHrCount = unassignedHrcoCountQuery.data ?? 0;

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
    setTab("active");
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
    setTab("active");
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

  const selectedAccountName = allowedAccountsQuery.data?.find((a) => a.id === accountId)?.name ?? "Account";
  const showBackToSelection =
    currentUser?.accountScope.mode === "all" ||
    (currentUser?.accountScope.mode === "scoped" && currentUser?.accountScope.ids.length > 1);

  return (
    <div className="relative flex h-full min-h-[calc(100vh-7rem)] flex-col gap-5 text-gray-900 pb-16">
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
          {/* 1. Header & Context Banner (Deep Navy #0f244a / Brand Background) */}
          <div className="rounded-2xl bg-gradient-to-b from-[#0f244a] to-[#0A2349] p-4 sm:p-5 text-white shadow-md border border-white/10 space-y-4">
            {/* Top row: Back button, Account title, subtitle, and desktop Store Staffing shortcut */}
            <div className="flex items-center justify-between gap-3">
              <div className="flex items-center gap-3 min-w-0">
                {showBackToSelection && (
                  <button
                    type="button"
                    onClick={handleBackToSelection}
                    aria-label="Back to Account Selection"
                    className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-white/10 hover:bg-white/15 border border-white/15 text-white transition-colors cursor-pointer"
                  >
                    <ChevronLeft className="h-5 w-5" />
                  </button>
                )}

                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-black text-white tracking-wide truncate">
                    {selectedAccountName}
                  </h1>
                  <p className="text-xs font-semibold text-white/60 tracking-wide mt-0.5">
                    Viewing: Store Employees
                  </p>
                </div>
              </div>

              {/* Secondary button: Store Staffing drawer trigger with quota badge */}
              <button
                type="button"
                onClick={() => setIsStoreStaffingOverviewOpen(true)}
                className="hidden sm:inline-flex items-center gap-2 rounded-xl bg-white/10 hover:bg-white/15 border border-white/15 px-3.5 py-2 text-xs font-semibold text-white shadow-xs transition-colors shrink-0"
              >
                <Building2 className="h-4 w-4 text-white/70" />
                <span>Store Staffing</span>
                <span className="rounded-full bg-white/20 px-2 py-0.5 text-[11px] font-bold font-mono">
                  {summaryData?.required ?? 0}
                </span>
              </button>
            </div>

            {/* 4-Column Metric Card */}
            <div className="rounded-xl border border-white/15 bg-white/[0.06] p-2.5 sm:p-3">
              <div className="grid grid-cols-4 divide-x divide-white/15 text-center">
                <div className="px-1 sm:px-2 flex flex-col items-center justify-center">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-white/60">
                    MFR
                  </span>
                  <span className="mt-1 text-2xl sm:text-3xl font-black text-white font-mono leading-none">
                    {fulfillmentRate}%
                  </span>
                </div>

                <div className="px-1 sm:px-2 flex flex-col items-center justify-center">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-white/60">
                    ACTIVE
                  </span>
                  <span className="mt-1 text-xl sm:text-2xl font-black text-white font-mono leading-none">
                    {activeCount}
                  </span>
                </div>

                <div className="px-1 sm:px-2 flex flex-col items-center justify-center">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-white/60">
                    VACANCY
                  </span>
                  <span className="mt-1 text-xl sm:text-2xl font-black text-[#FCD34D] font-mono leading-none">
                    {vacancyCount}
                  </span>
                </div>

                <div className="px-1 sm:px-2 flex flex-col items-center justify-center">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-white/60">
                    PIPELINE
                  </span>
                  <span className="mt-1 text-xl sm:text-2xl font-black text-white font-mono leading-none">
                    {summaryData?.hrProcess ?? 0}
                  </span>
                </div>
              </div>
            </div>

            {/* Leadership Team Strip: OM, TL, ATL, HRCO */}
            <div className="rounded-lg border border-white/10 bg-black/20 p-2">
              <div className="grid grid-cols-4 divide-x divide-white/10 text-center">
                <div className="px-1 flex flex-col items-center justify-center min-w-0">
                  <span className="text-[9px] font-bold uppercase tracking-wider text-white/50">
                    OM
                  </span>
                  <span className="mt-0.5 text-xs font-bold text-white truncate max-w-full">
                    {leadershipTeam.om}
                  </span>
                </div>

                <div className="px-1 flex flex-col items-center justify-center min-w-0">
                  <span className="text-[9px] font-bold uppercase tracking-wider text-white/50">
                    TL
                  </span>
                  <span className="mt-0.5 text-xs font-bold text-white truncate max-w-full">
                    {leadershipTeam.tl}
                  </span>
                </div>

                <div className="px-1 flex flex-col items-center justify-center min-w-0">
                  <span className="text-[9px] font-bold uppercase tracking-wider text-white/50">
                    ATL
                  </span>
                  <span className="mt-0.5 text-xs font-bold text-white truncate max-w-full">
                    {leadershipTeam.atl}
                  </span>
                </div>

                <div className="px-1 flex flex-col items-center justify-center min-w-0">
                  <span className="text-[9px] font-bold uppercase tracking-wider text-white/50">
                    HRCO
                  </span>
                  <span className="mt-0.5 text-xs font-bold text-white truncate max-w-full">
                    {leadershipTeam.hrco}
                  </span>
                </div>
              </div>
            </div>
          </div>

          {/* 2. Underline Navigation Tabs */}
          <div className="border-b border-border-default bg-surface-base rounded-xl overflow-hidden shadow-xs">
            <div
              role="tablist"
              aria-label="Plantilla Directory Tabs"
              className="flex items-center gap-1 sm:gap-2 px-2 sm:px-4 overflow-x-auto scrollbar-none"
            >
              {/* Tab 1: Active */}
              <button
                type="button"
                role="tab"
                aria-selected={tab === "active"}
                onClick={() => {
                  setTab("active");
                  setPage(1);
                }}
                className={`flex items-center gap-2 border-b-[3px] py-3.5 px-3 sm:px-4 text-xs sm:text-sm font-semibold transition-all whitespace-nowrap ${
                  tab === "active"
                    ? "border-[#0E2C5C] text-[#0E2C5C] font-bold"
                    : "border-transparent text-text-muted hover:text-text-primary"
                }`}
              >
                <span>Active</span>
                <span
                  className={`rounded-full px-2 py-0.5 text-[10px] font-bold font-mono transition-colors ${
                    tab === "active"
                      ? "bg-[#0E2C5C] text-white"
                      : "bg-surface-muted text-text-secondary"
                  }`}
                >
                  {activeCount}
                </span>
              </button>

              {/* Tab 2: Vacancy */}
              <button
                type="button"
                role="tab"
                aria-selected={tab === "vacancy"}
                onClick={() => {
                  setTab("vacancy");
                  setPage(1);
                }}
                className={`flex items-center gap-2 border-b-[3px] py-3.5 px-3 sm:px-4 text-xs sm:text-sm font-semibold transition-all whitespace-nowrap ${
                  tab === "vacancy"
                    ? "border-[#0E2C5C] text-[#0E2C5C] font-bold"
                    : "border-transparent text-text-muted hover:text-text-primary"
                }`}
              >
                <span>Vacancy</span>
                <span
                  className={`rounded-full px-2 py-0.5 text-[10px] font-bold font-mono transition-colors ${
                    tab === "vacancy"
                      ? "bg-[#0E2C5C] text-white"
                      : "bg-surface-muted text-text-secondary"
                  }`}
                >
                  {vacancyCount}
                </span>
              </button>

              {/* Tab 3: Inactive */}
              <button
                type="button"
                role="tab"
                aria-selected={tab === "inactive"}
                onClick={() => {
                  setTab("inactive");
                  setPage(1);
                }}
                className={`flex items-center gap-2 border-b-[3px] py-3.5 px-3 sm:px-4 text-xs sm:text-sm font-semibold transition-all whitespace-nowrap ${
                  tab === "inactive"
                    ? "border-[#0E2C5C] text-[#0E2C5C] font-bold"
                    : "border-transparent text-text-muted hover:text-text-primary"
                }`}
              >
                <span>Inactive</span>
                <span
                  className={`rounded-full px-2 py-0.5 text-[10px] font-bold font-mono transition-colors ${
                    tab === "inactive"
                      ? "bg-[#0E2C5C] text-white"
                      : "bg-surface-muted text-text-secondary"
                  }`}
                >
                  {inactiveCount}
                </span>
              </button>

              {/* Tab 4: Needs HR... */}
              <button
                type="button"
                role="tab"
                aria-selected={tab === "needs_hr"}
                onClick={() => {
                  setTab("needs_hr");
                  setPage(1);
                }}
                className={`flex items-center gap-2 border-b-[3px] py-3.5 px-3 sm:px-4 text-xs sm:text-sm font-semibold transition-all whitespace-nowrap ${
                  tab === "needs_hr"
                    ? "border-[#0E2C5C] text-[#0E2C5C] font-bold"
                    : "border-transparent text-text-muted hover:text-text-primary"
                }`}
              >
                <span>Needs HR...</span>
                <span
                  className={`rounded-full px-2 py-0.5 text-[10px] font-bold font-mono transition-colors ${
                    tab === "needs_hr"
                      ? "bg-[#0E2C5C] text-white"
                      : "bg-surface-muted text-text-secondary"
                  }`}
                >
                  {needsHrCount}
                </span>
              </button>
            </div>
          </div>

          {/* 3. Search & Filter Row */}
          <div className="space-y-3">
            <div className="flex items-center gap-2">
              <div className="relative flex-1">
                <Search className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted" />
                <input
                  type="text"
                  placeholder="Search employee, emploc no, name, store..."
                  value={search}
                  onChange={(e) => {
                    setSearch(e.target.value);
                    setPage(1);
                  }}
                  className="h-10 w-full rounded-xl border border-border-default bg-surface-base pl-10 pr-9 text-sm text-text-primary outline-none transition-colors focus:border-brand-500 focus:ring-1 focus:ring-brand-500 shadow-xs"
                  aria-label="Search employee, emploc no, name, store..."
                />
                {search && (
                  <button
                    type="button"
                    onClick={() => {
                      setSearch("");
                      setPage(1);
                    }}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-text-muted hover:text-text-primary"
                    aria-label="Clear search"
                  >
                    <X className="h-4 w-4" />
                  </button>
                )}
              </div>

              {/* Square filter toggle button */}
              <button
                type="button"
                onClick={() => setIsFilterOpen(!isFilterOpen)}
                className={`relative flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border transition-colors shadow-xs ${
                  isFilterOpen || hasActiveFilters
                    ? "border-brand-500 bg-brand-50 text-brand-700"
                    : "border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover hover:text-text-primary"
                }`}
                aria-label="Toggle filters"
                title="Toggle filters"
              >
                <Filter className="h-4 w-4" />
                {hasActiveFilters && (
                  <span className="absolute -top-1 -right-1 h-2.5 w-2.5 rounded-full bg-brand-600 ring-2 ring-white" />
                )}
              </button>
            </div>

            {/* Expandable filter shelf when isFilterOpen is active */}
            {isFilterOpen && (
              <div className="flex flex-wrap items-center gap-2.5 rounded-xl border border-border-default bg-surface-base p-3 shadow-xs">
                <div className="min-w-[170px] flex-1 sm:flex-initial">
                  <select
                    value={storeId}
                    onChange={(e) => {
                      setStoreId(e.target.value);
                      setPage(1);
                    }}
                    className="h-9 w-full rounded-lg border border-border-default bg-surface-base px-2.5 text-xs text-text-primary outline-none cursor-pointer focus:border-brand-500"
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

                <div className="min-w-[130px] flex-1 sm:flex-initial">
                  <select
                    value={status}
                    onChange={(e) => {
                      setStatus(e.target.value);
                      setPage(1);
                    }}
                    className="h-9 w-full rounded-lg border border-border-default bg-surface-base px-2.5 text-xs text-text-primary outline-none cursor-pointer focus:border-brand-500"
                    aria-label="Filter by status"
                  >
                    <option value="">All Statuses</option>
                    <option value="active">Active</option>
                    <option value="on leave">On Leave</option>
                    <option value="floating">Floating</option>
                  </select>
                </div>

                <div className="min-w-[130px] flex-1 sm:flex-initial">
                  <select
                    value={assignmentType}
                    onChange={(e) => {
                      setAssignmentType(e.target.value);
                      setPage(1);
                    }}
                    className="h-9 w-full rounded-lg border border-border-default bg-surface-base px-2.5 text-xs text-text-primary outline-none cursor-pointer focus:border-brand-500"
                    aria-label="Filter by assignment type"
                  >
                    <option value="">All Types</option>
                    <option value="stationary">Stationary</option>
                    <option value="roving">Roving</option>
                    <option value="reliever">Reliever</option>
                  </select>
                </div>

                {hasActiveFilters && (
                  <button
                    type="button"
                    onClick={handleResetFilters}
                    className="inline-flex h-9 items-center gap-1.5 rounded-lg border border-rose-200 bg-rose-50 px-3 text-xs font-semibold text-rose-700 hover:bg-rose-100 transition-colors"
                  >
                    <RotateCcw className="h-3 w-3" />
                    <span>Reset Filters</span>
                  </button>
                )}
              </div>
            )}
          </div>

          {/* 4. Employee Cards (Mobile Card Design) / Content Area */}
          <div className="min-h-[460px]">
            {isListLoading ? (
              <DataState
                kind="loading"
                title="Loading plantilla records"
                description="Fetching roster through Supabase RPCs..."
              />
            ) : isAccessDenied ? (
              <DataState
                kind="access_denied"
                title="Access Restricted"
                description="Supabase RLS policies blocked this read. You are not authorized to view records outside your scoped boundary."
              />
            ) : isRetryable ? (
              <DataState
                kind="error"
                title="Fetch Failed"
                description={listError?.message ?? "Failed to load plantilla records."}
                onRetry={() => {
                  if (tab === "vacancy") vacancyListQuery.refetch();
                  else if (tab === "needs_hr") needsHrcoQuery.refetch();
                  else employeeQuery.refetch();
                }}
              />
            ) : tab === "vacancy" ? (
              vacancyRows.length === 0 ? (
                <EmptyTabState
                  hasActiveFilters={hasActiveFilters}
                  onResetFilters={handleResetFilters}
                  tabLabel="vacancies"
                />
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3.5">
                  {vacancyRows.map((v) => (
                    <VacancyCard
                      key={v.id}
                      vacancy={v}
                      onRequestHeadcount={() => setIsRequestHeadcountOpen(true)}
                    />
                  ))}
                </div>
              )
            ) : tab === "needs_hr" ? (
              needsHrRows.length === 0 ? (
                <EmptyTabState
                  hasActiveFilters={hasActiveFilters}
                  onResetFilters={handleResetFilters}
                  tabLabel="employees needing HRCO assignment"
                />
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3.5">
                  {needsHrRows.map((row) => (
                    <EmployeeRosterCard
                      key={row.id}
                      row={row}
                      isNeedsHr
                      onSelect={() => setSelectedPlantillaId(row.id)}
                      storeLookupMap={storeLookupMap}
                    />
                  ))}
                </div>
              )
            ) : employeeRows.length === 0 ? (
              <EmptyTabState
                hasActiveFilters={hasActiveFilters}
                onResetFilters={handleResetFilters}
                tabLabel={tab === "inactive" ? "inactive employees" : "active employees"}
              />
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3.5">
                {employeeRows.map((row) => (
                  <EmployeeRosterCard
                    key={row.id}
                    row={row}
                    isInactive={tab === "inactive"}
                    onSelect={() => setSelectedPlantillaId(row.id)}
                    storeLookupMap={storeLookupMap}
                  />
                ))}
              </div>
            )}

            {/* Pagination Controls */}
            {!isListLoading && !isListError && totalCount > 0 && (
              <div className="mt-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 border-t border-border-default pt-4 text-xs sm:text-sm text-text-muted">
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

          {/* 5. Floating Action Button (FAB) */}
          {canRequestAdjustment && (
            <button
              type="button"
              onClick={() => setIsRequestHeadcountOpen(true)}
              aria-label="Request Headcount"
              title="Request Headcount"
              className="fixed bottom-6 right-6 z-40 flex h-14 w-14 items-center justify-center rounded-full bg-[#0E2C5C] hover:bg-[#0A2349] text-white shadow-xl transition-all duration-200 hover:scale-105 active:scale-95 focus:outline-none focus:ring-4 focus:ring-brand-500/30 cursor-pointer"
            >
              <Plus className="h-6 w-6 stroke-[2.5]" />
            </button>
          )}

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
                unassignedHrcoCountQuery.refetch();
                if (tab === "vacancy") vacancyListQuery.refetch();
                if (tab === "needs_hr") needsHrcoQuery.refetch();
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
// Employee Roster Card Component (Mobile Card Design)
// ---------------------------------------------------------------------------

function EmployeeRosterCard({
  row,
  isInactive,
  isNeedsHr,
  onSelect,
  storeLookupMap,
}: {
  row: PlantillaEmployeeListItem;
  isInactive?: boolean;
  isNeedsHr?: boolean;
  onSelect: () => void;
  storeLookupMap: Map<string, { city: string | null; province: string | null; code: string | null }>;
}) {
  const overlay = deriveDeactivationOverlay(row.plantillaStatus);
  const displayName =
    row.lastName && row.firstName
      ? `${row.lastName}, ${row.firstName}`
      : (row.lastName ?? row.firstName ?? "—");

  const initials = getInitials(row.firstName, row.lastName);

  // Store City/Province
  const storeInfo = row.primaryStoreName
    ? storeLookupMap.get(row.primaryStoreName.toLowerCase().trim())
    : null;
  const locationLabel = [storeInfo?.city, storeInfo?.province].filter(Boolean).join(", ");

  const statusLower = (row.plantillaStatus ?? "").toLowerCase();
  const isOnLeave = statusLower === "on leave" || statusLower === "on_leave";
  const isPendingSeparation = overlay.isPendingSeparation || statusLower === "pending separation";

  const accentBorderClass = isPendingSeparation
    ? "border-l-4 border-l-rose-500 bg-rose-50/20"
    : isOnLeave
    ? "border-l-4 border-l-amber-500"
    : isInactive
    ? "border-l-4 border-l-slate-400"
    : isNeedsHr
    ? "border-l-4 border-l-sky-500"
    : "border-l-4 border-l-emerald-500";

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onSelect}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onSelect();
        }
      }}
      className={`group relative flex flex-col justify-between overflow-hidden rounded-xl border border-border-default bg-surface-base p-4 text-left shadow-xs transition-all duration-200 hover:-translate-y-0.5 hover:border-brand-300 hover:shadow-md cursor-pointer focus:outline-none focus:ring-2 focus:ring-brand-500 ${accentBorderClass}`}
    >
      <div>
        {/* Top Header: Avatar + Name / [Employee Number • Position] + Chevron */}
        <div className="flex items-center gap-3">
          {/* Dark navy circle avatar with initials */}
          <div className="h-10 w-10 shrink-0 rounded-full bg-[#0E2C5C] text-white font-bold text-xs flex items-center justify-center shadow-xs">
            {initials}
          </div>

          {/* Name & Subtitle */}
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-1.5 flex-wrap">
              <h4 className="text-sm font-bold text-text-primary truncate group-hover:text-brand-600 transition-colors">
                {displayName}
              </h4>
              {row.plantillaType === "AH" && (
                <span className="shrink-0 rounded border border-amber-300 bg-amber-50 px-1.5 py-0.2 text-[10px] font-bold text-amber-700">
                  AH
                </span>
              )}
            </div>

            <div className="flex items-center gap-1.5 text-xs text-text-muted mt-0.5 truncate">
              <span className="font-mono text-text-secondary">{row.employeeNo || "—"}</span>
              <span className="text-text-muted/40">•</span>
              <span className="font-semibold text-brand-700 truncate">
                {row.positionTitle || "General Staff"}
              </span>
            </div>
          </div>

          {/* Right Chevron & Status Badge */}
          <div className="flex items-center gap-2 shrink-0">
            {isNeedsHr ? (
              <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-bold bg-amber-50 text-amber-700 border border-amber-200">
                Needs HRCO
              </span>
            ) : row.plantillaStatus && row.plantillaStatus.toLowerCase() !== "active" ? (
              <StatusBadge
                variant={plantillaStatusVariant(row.plantillaStatus)}
                text={row.plantillaStatus}
              />
            ) : null}
            <ChevronRight className="h-5 w-5 text-text-muted/60 transition-transform group-hover:translate-x-0.5" />
          </div>
        </div>
      </div>

      {/* Operational footer strip */}
      <div className="mt-3.5 pt-2.5 border-t border-border-subtle flex flex-wrap items-center justify-between gap-2 text-xs text-text-secondary">
        <div className="flex items-center gap-1.5 truncate max-w-[70%]">
          <MapPin className="h-3.5 w-3.5 text-text-muted shrink-0" />
          <span className="truncate font-medium text-text-secondary">
            {row.primaryStoreName || "Unassigned Outlet"}
            {locationLabel ? ` (${locationLabel})` : ""}
          </span>
        </div>

        <div className="flex items-center gap-1.5 shrink-0">
          <span
            className={`inline-flex items-center px-2 py-0.5 rounded text-[11px] font-semibold border ${
              row.assignmentType?.toLowerCase() === "roving"
                ? "bg-amber-50 text-amber-700 border-amber-200/80"
                : "bg-surface-muted text-text-secondary border-border-default"
            }`}
          >
            {row.assignmentType || "Stationary"}
            {row.coveredStoresCount > 1 ? ` (${row.coveredStoresCount})` : ""}
          </span>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Vacancy Card Component
// ---------------------------------------------------------------------------

function VacancyCard({
  vacancy,
  onRequestHeadcount,
}: {
  vacancy: VacancyListItem;
  onRequestHeadcount: () => void;
}) {
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onRequestHeadcount}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onRequestHeadcount();
        }
      }}
      className="group relative flex flex-col justify-between overflow-hidden rounded-xl border border-border-default bg-surface-base p-4 text-left shadow-xs transition-all duration-200 hover:-translate-y-0.5 hover:border-brand-300 hover:shadow-md cursor-pointer border-l-4 border-l-amber-500 focus:outline-none focus:ring-2 focus:ring-brand-500"
    >
      <div>
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 shrink-0 rounded-xl bg-amber-50 text-amber-700 border border-amber-200/80 flex items-center justify-center shadow-xs">
            <Briefcase className="h-5 w-5" />
          </div>

          <div className="flex-1 min-w-0">
            <h4 className="text-sm font-bold text-text-primary truncate group-hover:text-brand-600 transition-colors">
              {vacancy.position_title || "Open Position"}
            </h4>

            <div className="flex items-center gap-1.5 text-xs text-text-muted mt-0.5 truncate">
              <span className="font-mono font-bold text-brand-700">{vacancy.vcode}</span>
              <span className="text-text-muted/40">•</span>
              <span className="font-medium text-text-secondary">
                HC: {vacancy.activeApplicantCount > 0 ? vacancy.activeApplicantCount : 1}
              </span>
            </div>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <span
              className={`inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-bold ${
                vacancy.pipelineStatus?.toLowerCase() === "pipeline"
                  ? "bg-purple-100 text-purple-700"
                  : "bg-amber-100 text-amber-700"
              }`}
            >
              {vacancy.pipelineStatus || "Open"}
            </span>
            <ChevronRight className="h-5 w-5 text-text-muted/60 transition-transform group-hover:translate-x-0.5" />
          </div>
        </div>
      </div>

      <div className="mt-3.5 pt-2.5 border-t border-border-subtle flex items-center justify-between gap-2 text-xs text-text-secondary">
        <div className="flex items-center gap-1.5 truncate">
          <MapPin className="h-3.5 w-3.5 text-text-muted shrink-0" />
          <span className="truncate font-medium text-text-secondary">
            {vacancy.storeName || "Unassigned Outlet"}
          </span>
        </div>

        <span className="text-[11px] font-semibold text-text-muted font-mono">
          {vacancy.agingDays != null ? `${vacancy.agingDays}d aging` : "Open"}
        </span>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Empty State Helper
// ---------------------------------------------------------------------------

function EmptyTabState({
  hasActiveFilters,
  onResetFilters,
  tabLabel,
}: {
  hasActiveFilters: boolean;
  onResetFilters: () => void;
  tabLabel: string;
}) {
  return (
    <div className="flex flex-col items-center justify-center py-16 px-4 text-center rounded-2xl border border-dashed border-border-default bg-surface-muted/20">
      <div className="relative mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-brand-50 border border-brand-100 shadow-xs">
        <Users className="h-8 w-8 text-brand-600" />
        {hasActiveFilters && (
          <span className="absolute -top-1 -right-1 flex h-5 w-5 items-center justify-center rounded-full bg-amber-500 text-[10px] font-bold text-white shadow-xs">
            !
          </span>
        )}
      </div>
      <h3 className="text-base font-bold text-text-primary">
        {hasActiveFilters ? "No matching records found" : `No ${tabLabel}`}
      </h3>
      <p className="mt-1.5 max-w-sm text-xs text-text-muted leading-relaxed">
        {hasActiveFilters
          ? "We couldn't find any records matching your current filter criteria. Try adjusting your parameters."
          : `There are currently no ${tabLabel} listed under this account.`}
      </p>
      {hasActiveFilters && (
        <button
          type="button"
          onClick={onResetFilters}
          className="mt-4 inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3.5 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary transition-colors shadow-xs"
        >
          <RotateCcw className="h-3.5 w-3.5" />
          <span>Reset all filters</span>
        </button>
      )}
    </div>
  );
}
