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
  Briefcase,
  LayoutGrid,
  List,
  AlertCircle,
  UserMinus,
} from "lucide-react";
import { useSearchParams, useRouter, usePathname } from "next/navigation";
import { loadCurrentUserContext, isQuotaOverrideRole, isOpsAmendmentRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/client";
import { MetricCard } from "@/components/shared/MetricCard";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
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
type DisplayView = "table" | "cards";

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
  const [displayView, setDisplayView] = useState<DisplayView>("table");
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
  const summaryError =
    summaryQuery.error instanceof PlantillaDataError ? summaryQuery.error : null;
  const summaryBlocked = summaryError?.kind === "access_denied";

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
    <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-5 text-gray-900">
      {!accountId ? (
        <>
          <AdminPageHeader
            categoryTag="ADMIN PANEL"
            moduleName="Plantilla"
            title="Plantilla Directory"
            subtitle="Select a billing account to audit roster allocations, capacity targets, and staffing governance."
            icon={Building2}
          />
          {renderAccountSelectionContent()}
        </>
      ) : (
        <>
          {/* 1. Header & Context Action Bar (Enterprise Web Header) */}
          <AdminPageHeader
            categoryTag="ADMIN PANEL"
            moduleName="Plantilla"
            title={
              <nav className="flex items-center gap-1.5 text-xs" aria-label="Breadcrumb">
                {showBackToSelection ? (
                  <button
                    type="button"
                    onClick={handleBackToSelection}
                    className="inline-flex items-center gap-1 font-medium text-text-secondary hover:text-brand-600 transition-colors"
                  >
                    <ArrowLeft className="h-3 w-3" />
                    <span>Accounts</span>
                  </button>
                ) : (
                  <span className="text-text-muted">Accounts</span>
                )}
                <span className="text-text-muted/60">/</span>
                <span className="text-sm font-semibold text-text-primary leading-tight truncate">
                  {selectedAccountName}
                </span>
                {userRole && (
                  <span className="inline-flex items-center rounded-full bg-brand-50 border border-brand-200/80 px-2 py-0.2 text-[10px] font-semibold text-brand-700 capitalize">
                    {userRole.replace(/_/g, " ")}
                  </span>
                )}
              </nav>
            }
            subtitle="Viewing: Store Employees • Managing roster allocations, capacity targets, and staffing governance."
            actionSlot={
              <div className="flex flex-wrap items-center gap-2">
                {/* Secondary button: Store Staffing drawer trigger with quota badge */}
                <button
                  type="button"
                  onClick={() => setIsStoreStaffingOverviewOpen(true)}
                  className="group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border border-border-default bg-surface-base px-3.5 py-2 text-xs font-semibold text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary transition cursor-pointer shadow-2xs"
                >
                  <Building2 className="w-4 h-4 shrink-0 text-text-muted group-hover:text-text-secondary transition-colors" />
                  <span>Store Staffing</span>
                  <span className="ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold bg-slate-100 text-slate-600 border border-slate-200/80 shadow-2xs transition-colors">
                    {summaryData?.required ?? 0} Quota
                  </span>
                </button>

                {/* Primary button: + Request Headcount */}
                {canRequestAdjustment && (
                  <button
                    type="button"
                    onClick={() => setIsRequestHeadcountOpen(true)}
                    className="inline-flex h-9 items-center gap-2 rounded-lg bg-brand-600 px-3.5 py-2 text-xs font-semibold text-white shadow-2xs hover:bg-brand-700 transition cursor-pointer focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
                  >
                    <Plus className="w-4 h-4 shrink-0" />
                    <span>Request Headcount</span>
                  </button>
                )}
              </div>
            }
          />

          {/* 2. Executive KPI & Leadership Team Bar */}
          <section aria-label="Plantilla summary metrics" className="space-y-3">
            <div className="grid gap-3 grid-cols-2 lg:grid-cols-4">
              <MetricCard
                label="Fulfillment Rate (MFR)"
                value={`${fulfillmentRate}%`}
                helperText={`${summaryData?.actual ?? 0} active / ${summaryData?.required ?? 0} quota`}
                badge={summaryData?.required ? `${fulfillmentRate}%` : undefined}
                isLoading={summaryQuery.isLoading}
                isBlocked={summaryBlocked}
                isError={!summaryBlocked && summaryQuery.isError}
                errorText="Summary data failed to load"
              />
              <MetricCard
                label="Active Deployed"
                value={summaryData?.actual}
                helperText="Active deployed personnel"
                isLoading={summaryQuery.isLoading}
                isBlocked={summaryBlocked}
                isError={!summaryBlocked && summaryQuery.isError}
                errorText="Summary data failed to load"
              />
              <MetricCard
                label="Open Vacancies"
                value={summaryData?.vacant}
                helperText="Approved open vacancy slots"
                isLoading={summaryQuery.isLoading}
                isBlocked={summaryBlocked}
                isError={!summaryBlocked && summaryQuery.isError}
                errorText="Summary data failed to load"
              />
              <MetricCard
                label="HR Pipeline"
                value={summaryData?.hrProcess}
                helperText="Candidate onboarding pipeline"
                isLoading={summaryQuery.isLoading}
                isBlocked={summaryBlocked}
                isError={!summaryBlocked && summaryQuery.isError}
                errorText="Summary data failed to load"
              />
            </div>

            {/* Leadership Team Strip: OM, TL, ATL, HRCO */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 rounded-xl border border-border-default bg-surface-muted/40 px-4 py-2.5 text-xs text-text-secondary shadow-xs">
              <div className="flex items-center gap-2 shrink-0">
                <Users className="h-4 w-4 text-brand-600" />
                <span className="font-bold uppercase tracking-wider text-[11px] text-text-primary">
                  Leadership Team:
                </span>
              </div>
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 flex-1 max-w-3xl">
                <div className="flex items-center gap-2 min-w-0">
                  <span className="rounded bg-brand-50 border border-brand-200/80 px-1.5 py-0.5 text-[10px] font-bold text-brand-700 shrink-0">
                    OM
                  </span>
                  <span className="font-semibold text-text-primary truncate" title={leadershipTeam.om}>
                    {leadershipTeam.om}
                  </span>
                </div>
                <div className="flex items-center gap-2 min-w-0">
                  <span className="rounded bg-brand-50 border border-brand-200/80 px-1.5 py-0.5 text-[10px] font-bold text-brand-700 shrink-0">
                    TL
                  </span>
                  <span className="font-semibold text-text-primary truncate" title={leadershipTeam.tl}>
                    {leadershipTeam.tl}
                  </span>
                </div>
                <div className="flex items-center gap-2 min-w-0">
                  <span className="rounded bg-brand-50 border border-brand-200/80 px-1.5 py-0.5 text-[10px] font-bold text-brand-700 shrink-0">
                    ATL
                  </span>
                  <span className="font-semibold text-text-primary truncate" title={leadershipTeam.atl}>
                    {leadershipTeam.atl}
                  </span>
                </div>
                <div className="flex items-center gap-2 min-w-0">
                  <span className="rounded bg-brand-50 border border-brand-200/80 px-1.5 py-0.5 text-[10px] font-bold text-brand-700 shrink-0">
                    HRCO
                  </span>
                  <span className="font-semibold text-text-primary truncate" title={leadershipTeam.hrco}>
                    {leadershipTeam.hrco}
                  </span>
                </div>
              </div>
            </div>
          </section>

          {/* 3. Navigation Tabs & Filter Toolbar */}
          <div className="space-y-3">
            {/* Standardized Tab Row & View Switcher */}
            <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border-subtle pb-3">
              <div
                role="tablist"
                aria-label="Plantilla Directory Tabs"
                className="flex items-center gap-1.5 overflow-x-auto no-scrollbar scrollbar-none"
              >
                {/* Tab 1: Active Roster */}
                <button
                  type="button"
                  role="tab"
                  aria-selected={tab === "active"}
                  onClick={() => {
                    setTab("active");
                    setPage(1);
                  }}
                  className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                    tab === "active"
                      ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
                      : "border-transparent bg-transparent text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary"
                  }`}
                >
                  <Users
                    className={`w-4 h-4 shrink-0 transition-colors ${
                      tab === "active"
                        ? "text-brand-700"
                        : "text-text-muted group-hover:text-text-secondary"
                    }`}
                  />
                  <span>Active Roster</span>
                  <span
                    className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold shadow-2xs transition-colors ${
                      tab === "active"
                        ? "bg-brand-600 text-white"
                        : "bg-slate-100 text-slate-600 border border-slate-200/80"
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
                  className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                    tab === "vacancy"
                      ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
                      : "border-transparent bg-transparent text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary"
                  }`}
                >
                  <Briefcase
                    className={`w-4 h-4 shrink-0 transition-colors ${
                      tab === "vacancy"
                        ? "text-brand-700"
                        : "text-text-muted group-hover:text-text-secondary"
                    }`}
                  />
                  <span>Vacancy</span>
                  <span
                    className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold shadow-2xs transition-colors ${
                      tab === "vacancy"
                        ? "bg-brand-600 text-white"
                        : "bg-slate-100 text-slate-600 border border-slate-200/80"
                    }`}
                  >
                    {vacancyCount}
                  </span>
                </button>

                {/* Tab 3: Inactive / Floating */}
                <button
                  type="button"
                  role="tab"
                  aria-selected={tab === "inactive"}
                  onClick={() => {
                    setTab("inactive");
                    setPage(1);
                  }}
                  className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                    tab === "inactive"
                      ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
                      : "border-transparent bg-transparent text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary"
                  }`}
                >
                  <UserMinus
                    className={`w-4 h-4 shrink-0 transition-colors ${
                      tab === "inactive"
                        ? "text-brand-700"
                        : "text-text-muted group-hover:text-text-secondary"
                    }`}
                  />
                  <span>Inactive / Floating</span>
                  <span
                    className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold shadow-2xs transition-colors ${
                      tab === "inactive"
                        ? "bg-brand-600 text-white"
                        : "bg-slate-100 text-slate-600 border border-slate-200/80"
                    }`}
                  >
                    {inactiveCount}
                  </span>
                </button>

                {/* Tab 4: Needs HRCO */}
                <button
                  type="button"
                  role="tab"
                  aria-selected={tab === "needs_hr"}
                  onClick={() => {
                    setTab("needs_hr");
                    setPage(1);
                  }}
                  className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                    tab === "needs_hr"
                      ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
                      : "border-transparent bg-transparent text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary"
                  }`}
                >
                  <AlertCircle
                    className={`w-4 h-4 shrink-0 transition-colors ${
                      tab === "needs_hr"
                        ? "text-brand-700"
                        : "text-text-muted group-hover:text-text-secondary"
                    }`}
                  />
                  <span>Needs HRCO</span>
                  <span
                    className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold shadow-2xs transition-colors ${
                      tab === "needs_hr"
                        ? "bg-brand-600 text-white"
                        : "bg-slate-100 text-slate-600 border border-slate-200/80"
                    }`}
                  >
                    {needsHrCount}
                  </span>
                </button>
              </div>

              {/* View switch: Table vs Cards */}
              <div className="flex h-9 items-center rounded-lg border border-border-default bg-surface-muted p-0.5">
                <button
                  type="button"
                  onClick={() => setDisplayView("table")}
                  aria-label="Table View"
                  title="Table View"
                  className={`inline-flex h-full items-center gap-1.5 rounded-md px-2.5 text-xs font-semibold transition-colors cursor-pointer ${
                    displayView === "table"
                      ? "bg-surface-base text-text-primary shadow-xs"
                      : "text-text-muted hover:text-text-primary"
                  }`}
                >
                  <List className="h-3.5 w-3.5" />
                  <span className="hidden sm:inline">Table</span>
                </button>
                <button
                  type="button"
                  onClick={() => setDisplayView("cards")}
                  aria-label="Cards View"
                  title="Cards View"
                  className={`inline-flex h-full items-center gap-1.5 rounded-md px-2.5 text-xs font-semibold transition-colors cursor-pointer ${
                    displayView === "cards"
                      ? "bg-surface-base text-text-primary shadow-xs"
                      : "text-text-muted hover:text-text-primary"
                  }`}
                >
                  <LayoutGrid className="h-3.5 w-3.5" />
                  <span className="hidden sm:inline">Cards</span>
                </button>
              </div>
            </div>

            {/* Unified Web Search & Filter Toolbar */}
            <div className="flex flex-col lg:flex-row items-stretch lg:items-center gap-2.5 rounded-xl border border-border-default bg-surface-base p-3 shadow-xs">
              <div className="relative flex-1 min-w-[240px]">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted" />
                <input
                  type="text"
                  placeholder="Search employee, emploc no, name, store..."
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

              {/* Desktop Filter Dropdowns */}
              <div className="flex flex-wrap items-center gap-2">
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

          {/* 4. Main Data Area: Table or Cards View */}
          <div className="min-h-[500px]">
            {isListLoading ? (
              <div className="rounded-xl border border-border-default bg-surface-base p-8">
                <DataState
                  kind="loading"
                  title="Loading plantilla records"
                  description="Fetching roster personnel through Supabase RPCs..."
                />
              </div>
            ) : isAccessDenied ? (
              <div className="rounded-xl border border-border-default bg-surface-base p-8">
                <DataState
                  kind="access_denied"
                  title="Access Restricted"
                  description="Supabase RLS policies blocked this read. You are not authorized to view plantilla records outside your scoped boundary."
                />
              </div>
            ) : isRetryable ? (
              <div className="rounded-xl border border-border-default bg-surface-base p-8">
                <DataState
                  kind="error"
                  title="Fetch Failed"
                  description={listError?.message ?? "The plantilla query failed."}
                  onRetry={() => {
                    if (tab === "vacancy") vacancyListQuery.refetch();
                    else if (tab === "needs_hr") needsHrcoQuery.refetch();
                    else employeeQuery.refetch();
                  }}
                />
              </div>
            ) : tab === "vacancy" ? (
              vacancyRows.length === 0 ? (
                <EmptyTabState
                  hasActiveFilters={hasActiveFilters}
                  onResetFilters={handleResetFilters}
                  tabLabel="vacancies"
                />
              ) : displayView === "table" ? (
                <VacancyTable
                  rows={vacancyRows}
                  onRequestHeadcount={() => setIsRequestHeadcountOpen(true)}
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
              ) : displayView === "table" ? (
                <EmployeeTable
                  rows={needsHrRows}
                  isNeedsHr
                  onRowClick={setSelectedPlantillaId}
                  storeLookupMap={storeLookupMap}
                />
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3.5">
                  {needsHrRows.map((row) => (
                    <EmployeeCard
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
                tabLabel={tab === "inactive" ? "inactive or floating employees" : "active deployed employees"}
              />
            ) : displayView === "table" ? (
              <EmployeeTable
                rows={employeeRows}
                isInactive={tab === "inactive"}
                onRowClick={setSelectedPlantillaId}
                storeLookupMap={storeLookupMap}
              />
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3.5">
                {employeeRows.map((row) => (
                  <EmployeeCard
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
              <div className="mt-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 border-t border-border-default pt-4 text-xs sm:text-sm text-text-muted">
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
// Employee Table Component (Enterprise Web Table)
// ---------------------------------------------------------------------------

function EmployeeTable({
  rows,
  isInactive,
  isNeedsHr,
  onRowClick,
  storeLookupMap,
}: {
  rows: PlantillaEmployeeListItem[];
  isInactive?: boolean;
  isNeedsHr?: boolean;
  onRowClick: (id: string) => void;
  storeLookupMap: Map<string, { city: string | null; province: string | null; code: string | null }>;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs">
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
                : isInactive
                ? "opacity-80 transition-colors hover:bg-table-row-hover cursor-pointer"
                : "transition-colors hover:bg-table-row-hover cursor-pointer";

              const displayName =
                row.lastName && row.firstName
                  ? `${row.lastName}, ${row.firstName}`
                  : (row.lastName ?? row.firstName ?? "—");

              const initials = getInitials(row.firstName, row.lastName);

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
                  {/* MEMBER */}
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

                  {/* STORE */}
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

                  {/* POSITION */}
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

                  {/* ASSIGNMENT */}
                  <td className="px-4 py-3">
                    {row.assignmentType?.toLowerCase() === "roving" ? (
                      <span className="inline-flex items-center gap-1 rounded-md bg-amber-50 border border-amber-200/80 px-2 py-0.5 text-xs font-semibold text-amber-700">
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

                  {/* STATUS */}
                  <td className="px-4 py-3">
                    {isNeedsHr ? (
                      <span className="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold bg-amber-50 text-amber-700 border border-amber-200">
                        Needs HRCO
                      </span>
                    ) : row.plantillaStatus ? (
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

                  {/* ACTIONS */}
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
    </div>
  );
}

// ---------------------------------------------------------------------------
// Vacancy Table Component
// ---------------------------------------------------------------------------

function VacancyTable({
  rows,
  onRequestHeadcount,
}: {
  rows: VacancyListItem[];
  onRequestHeadcount: () => void;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs">
      <div className="overflow-x-auto">
        <table className="w-full min-w-[980px] text-left text-sm">
          <thead>
            <tr className="border-b border-table-rule bg-table-header">
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
                VCode
              </th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
                Position
              </th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
                Store
              </th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
                HC Needed
              </th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
                Aging
              </th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-normal text-table-text-muted">
                Pipeline Status
              </th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-normal text-table-text-muted">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-table-rule">
            {rows.map((row) => (
              <tr
                key={row.id}
                className="transition-colors hover:bg-table-row-hover cursor-pointer"
                onClick={onRequestHeadcount}
              >
                <td className="px-4 py-3 font-mono font-bold text-brand-700">
                  {row.vcode}
                </td>
                <td className="px-4 py-3 font-medium text-table-text">
                  {row.position_title || "General Staff"}
                </td>
                <td className="px-4 py-3 text-table-text">
                  {row.storeName || "Unassigned Outlet"}
                </td>
                <td className="px-4 py-3 font-mono font-bold text-table-text">
                  {row.activeApplicantCount > 0 ? row.activeApplicantCount : 1}
                </td>
                <td className="px-4 py-3 text-xs text-text-muted font-mono">
                  {row.agingDays != null ? `${row.agingDays} days` : "—"}
                </td>
                <td className="px-4 py-3">
                  <span
                    className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-bold ${
                      row.pipelineStatus?.toLowerCase() === "pipeline"
                        ? "bg-purple-100 text-purple-700"
                        : "bg-amber-100 text-amber-700"
                    }`}
                  >
                    {row.pipelineStatus || "Open"}
                  </span>
                </td>
                <td className="px-4 py-3 text-right">
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      onRequestHeadcount();
                    }}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-secondary hover:text-brand-600 hover:border-brand-300 hover:bg-brand-50/40 transition-colors shadow-xs"
                  >
                    <span>Manage</span>
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Employee Card Component (Optional Cards View)
// ---------------------------------------------------------------------------

function EmployeeCard({
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
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 shrink-0 rounded-full bg-brand-50 border border-brand-200 text-brand-700 font-bold text-xs flex items-center justify-center shadow-xs">
            {initials}
          </div>

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

      <div className="mt-3.5 pt-2.5 border-t border-border-subtle flex flex-wrap items-center justify-between gap-2 text-xs text-text-secondary">
        <div className="flex items-center gap-1.5 truncate max-w-[70%]">
          <MapPin className="h-3.5 w-3.5 text-text-muted shrink-0" />
          <span className="truncate font-medium text-text-secondary">
            {row.primaryStoreName || "Unassigned Outlet"}
            {locationLabel ? ` (${locationLabel})` : ""}
          </span>
        </div>

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
  );
}

// ---------------------------------------------------------------------------
// Vacancy Card Component (Optional Cards View)
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
