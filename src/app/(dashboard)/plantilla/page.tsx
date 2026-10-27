"use client";

import { useState, useMemo, Suspense } from "react";
import { useQuery } from "@tanstack/react-query";
import {
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
  BarChart3,
} from "lucide-react";
import { useSearchParams, useRouter, usePathname } from "next/navigation";
import { useCurrentUser, isQuotaOverrideRole, isOpsAmendmentRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/client";
import { MetricCard } from "@/components/shared/MetricCard";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { DataState } from "@/components/shared/DataState";
import { TablePagination } from "@/components/shared/TablePagination";
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
import {
  listVacancies,
  useDirectImportVacancy,
  fetchOccupiedStoreIdentifiers,
  type VacancyListItem,
} from "@/lib/queries/vacancy";
import { formatStoreDisplay } from "@/lib/utils/formatName";
import {
  formatPersonName,
  formatPosition,
  formatStoreName,
  formatAccountName,
  formatDisplayText,
} from "@/lib/utils/displayText";
import { PlantillaDetailDrawer } from "@/components/plantilla/PlantillaDetailDrawer";
import { VacancyDetailDrawer } from "@/components/vacancy/VacancyDetailDrawer";
import { StoreStaffingDrawer } from "@/components/plantilla/StoreStaffingDrawer";
import { StoreStaffingOverviewDrawer } from "@/components/plantilla/StoreStaffingOverviewDrawer";
import { SlotDetailDrawer } from "@/components/plantilla/SlotDetailDrawer";
import { RequestHeadcountModal } from "@/components/modals/RequestHeadcountModal";
import { MosesHqPoolView } from "@/components/plantilla/MosesHqPoolView";
import { WorkforceAnalyticsView } from "@/components/plantilla/WorkforceAnalyticsView";

// ---------------------------------------------------------------------------
// Types & Constants
// ---------------------------------------------------------------------------

export type PlantillaViewMode = "store" | "moses_pool" | "analytics";


type DirectoryTab = "active" | "vacancy" | "inactive" | "needs_hr";
type DisplayView = "table" | "cards";

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
  return (
    <Suspense
      fallback={
        <div className="space-y-6">
          <div className="h-14 border-b border-border-subtle bg-surface-base animate-pulse" />
          <div className="h-64 rounded-xl border border-border-default bg-surface-base animate-pulse" />
        </div>
      }
    >
      <PlantillaPageContent />
    </Suspense>
  );
}

function PlantillaPageContent() {
  const [tab, setTab] = useState<DirectoryTab>("active");
  const [displayView, setDisplayView] = useState<DisplayView>("table");
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState<number>(10);
  const [selectedPlantillaId, setSelectedPlantillaId] = useState<string | null>(null);
  const [selectedStoreRow, setSelectedStoreRow] = useState<PlantillaStoreStaffingRow | null>(null);
  const [selectedSlotId, setSelectedSlotId] = useState<string | null>(null);
  const [isStoreStaffingOverviewOpen, setIsStoreStaffingOverviewOpen] = useState(false);
  const [isRequestHeadcountOpen, setIsRequestHeadcountOpen] = useState(false);
  const [selectedVacancyId, setSelectedVacancyId] = useState<string | null>(null);
  const directImportMutation = useDirectImportVacancy();

  // Search parameters and router
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();

  // Search query specifically for the account selector list
  const [accountSearch, setAccountSearch] = useState("");
  const [selectorGroupId, setSelectorGroupId] = useState("");

  // Directory filter state
  const [search, setSearch] = useState("");
  const [storeId, setStoreId] = useState("");
  const [status, setStatus] = useState("");
  const [assignmentType, setAssignmentType] = useState("");

  // -------------------------------------------------------------------------
  // User Context and Account Lists
  // -------------------------------------------------------------------------

  const currentUser = useCurrentUser();
  const userRole = currentUser?.roleKey ?? currentUser?.roleName;
  const canReviseQuota = isQuotaOverrideRole(userRole);
  const canRequestAdjustment = isOpsAmendmentRole(userRole);

  // Derive viewMode directly from searchParams
  const viewParam = searchParams.get("view") || searchParams.get("tab");
  const viewMode: PlantillaViewMode =
    viewParam === "moses_pool" || viewParam === "pool" || viewParam === "moses"
      ? "moses_pool"
      : viewParam === "analytics" || viewParam === "workforce_analytics"
      ? "analytics"
      : "store";

  // Derive accountId directly from URL or user single scoped account
  const urlAccountId = searchParams.get("accountId") ?? "";
  const singleScopedId =
    currentUser?.accountScope.mode === "scoped" && currentUser.accountScope.ids.length === 1
      ? currentUser.accountScope.ids[0]
      : "";
  const accountId = urlAccountId || singleScopedId;

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
          hrco_user_id,
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
        hrcoUserId: (row.hrco_user_id as string | null) ?? null,
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

  const accountMetricsQuery = useQuery({
    queryKey: ["plantilla", "account-allocation-kpi"],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("v_account_allocation_kpi")
        .select("account_id, actual_hc, slot_vacant_hc, pipeline_count, required_hc");
      if (error) {
        console.warn("[Plantilla] Could not fetch batch account metrics from v_account_allocation_kpi:", error);
        return new Map<string, { actual: number; vacant: number; hrProcess: number; required: number; fillRate: number }>();
      }
      const map = new Map<string, { actual: number; vacant: number; hrProcess: number; required: number; fillRate: number }>();
      (data ?? []).forEach((row) => {
        const actual = Number(row.actual_hc ?? 0);
        const vacant = Math.round(Number(row.slot_vacant_hc ?? 0));
        const hrProcess = Number(row.pipeline_count ?? 0);
        const required = actual + vacant;
        const fillRate = required > 0 ? Math.round((actual / required) * 100) : 0;
        map.set(String(row.account_id), { actual, vacant, hrProcess, required, fillRate });
      });
      return map;
    },
    enabled: !!currentUser && !accountId && viewMode === "store",
    staleTime: 60000,
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

  // Stores under current account for dropdown & city/province lookup
  const storesUnderAccountQuery = useQuery({
    queryKey: ["plantilla", "account-stores", accountId],
    queryFn: async () => {
      if (!accountId) return [];
      const supabase = createClient();
      const { data, error } = await supabase
        .from("stores")
        .select("id, store_name, vcode, area_city, area_province, province")
        .eq("account_id", accountId)
        .eq("is_active", true)
        .order("store_name");
      if (error) throw error;
      return (data ?? []).map((s) => ({
        id: s.id as string,
        name: s.store_name as string,
        code: (s.vcode as string | null) ?? null,
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
    enabled: !!currentUser && !!accountId,
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

  const currentAccount = useMemo(() => {
    return (allowedAccountsQuery.data ?? []).find((a) => a.id === accountId) ?? null;
  }, [allowedAccountsQuery.data, accountId]);

  const accountHasAssignedHrco = Boolean(
    currentAccount?.hrcoUserId || (leadershipTeam.hrco && leadershipTeam.hrco !== "—" && leadershipTeam.hrco !== "-")
  );

  const effectiveTab = accountHasAssignedHrco && tab === "needs_hr" ? "active" : tab;

  // Query for active or inactive roster
  const employeeQuery = useQuery({
    queryKey: [
      "plantilla",
      "employees",
      { search, accountId, storeId, status, assignmentType, page, pageSize, tab: effectiveTab },
    ],
    queryFn: () =>
      listWebPlantillaEmployees({
        search: search.trim() || undefined,
        accountId: accountId || undefined,
        storeId: storeId || undefined,
        status: status || undefined,
        deployment: assignmentType || undefined,
        activeState: effectiveTab === "inactive" ? "inactive" : "active",
        page,
        pageSize,
      }),
    enabled: !!accountId && (effectiveTab === "active" || effectiveTab === "inactive"),
  });

  // Query for vacancies
  const vacancyListQuery = useQuery({
    queryKey: ["plantilla", "vacancies", accountId, search, page, pageSize],
    queryFn: () =>
      listVacancies({
        accountId: accountId || undefined,
        search: search.trim() || undefined,
        status: "open",
        page,
        pageSize,
      }),
    enabled: !!accountId && effectiveTab === "vacancy",
    staleTime: 30000,
  });

  // Query for occupied store IDs and VCodes under current account to strictly exclude from missing vacancies
  const occupiedStoresQuery = useQuery({
    queryKey: ["plantilla", "occupied-stores", accountId],
    queryFn: () => fetchOccupiedStoreIdentifiers(accountId),
    enabled: !!accountId && effectiveTab === "vacancy",
    staleTime: 30000,
  });

  // Query for Needs HR... employees
  const needsHrcoQuery = useQuery({
    queryKey: ["plantilla", "needs-hrco-list", accountId, search],
    queryFn: () => fetchNeedsHrcoEmployees(accountId, search),
    enabled: !!accountId && !accountHasAssignedHrco && effectiveTab === "needs_hr",
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
    enabled: !!accountId && !accountHasAssignedHrco,
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
    effectiveTab === "vacancy"
      ? vacancyListQuery.isLoading
      : effectiveTab === "needs_hr"
      ? needsHrcoQuery.isLoading
      : employeeQuery.isLoading;

  const isListError =
    effectiveTab === "vacancy"
      ? vacancyListQuery.isError && !vacancyListQuery.isLoading
      : effectiveTab === "needs_hr"
      ? needsHrcoQuery.isError && !needsHrcoQuery.isLoading
      : employeeQuery.isError && !employeeQuery.isLoading;

  const isAccessDenied = listError?.kind === "access_denied";
  const isRetryable = isListError && !isAccessDenied;

  const employeeRows = employeeQuery.data?.data ?? [];
  const vacancyRows = useMemo(() => vacancyListQuery.data?.data ?? [], [vacancyListQuery.data?.data]);
  const needsHrRows = useMemo(() => needsHrcoQuery.data ?? [], [needsHrcoQuery.data]);

  const existingVacancyVcodes = useMemo(() => {
    const set = new Set<string>();
    for (const v of vacancyRows) {
      if (v.vcode) set.add(v.vcode.trim().toUpperCase());
      if (v.cgCode) set.add(v.cgCode.trim().toUpperCase());
    }
    return set;
  }, [vacancyRows]);

  const existingVacancyStoreIds = useMemo(() => {
    const set = new Set<string>();
    for (const v of vacancyRows) {
      if (v.storeId) set.add(v.storeId);
    }
    return set;
  }, [vacancyRows]);

  const missingStoreVacancies = useMemo(() => {
    if (!storesUnderAccountQuery.data || !accountId) return [];
    const occupiedStoreIds = occupiedStoresQuery.data?.occupiedStoreIds ?? new Set<string>();
    const occupiedVcodes = occupiedStoresQuery.data?.occupiedVcodes ?? new Set<string>();
    const occupiedStoreNames = occupiedStoresQuery.data?.occupiedStoreNames ?? new Set<string>();

    return storesUnderAccountQuery.data.filter((s) => {
      const code = (s.code || "").trim().toUpperCase();
      const name = (s.name || "").trim().toUpperCase();
      const hasMatchingCode = Boolean(code && existingVacancyVcodes.has(code));
      const hasMatchingId = Boolean(s.id && existingVacancyStoreIds.has(s.id));
      const isOccupiedCode = Boolean(code && occupiedVcodes.has(code));
      const isOccupiedId = Boolean(s.id && occupiedStoreIds.has(s.id));
      const isOccupiedName = Boolean(name && occupiedStoreNames.has(name));

      // Strictly must NOT have an existing vacancy AND must NOT be occupied by an active employee
      return !hasMatchingCode && !hasMatchingId && !isOccupiedCode && !isOccupiedId && !isOccupiedName;
    });
  }, [
    storesUnderAccountQuery.data,
    accountId,
    existingVacancyVcodes,
    existingVacancyStoreIds,
    occupiedStoresQuery.data,
  ]);

  const paginatedNeedsHrRows = useMemo(() => {
    const start = (page - 1) * pageSize;
    return needsHrRows.slice(start, start + pageSize);
  }, [needsHrRows, page, pageSize]);

  const totalCount =
    effectiveTab === "vacancy"
      ? vacancyListQuery.data?.totalCount ?? 0
      : effectiveTab === "needs_hr"
      ? needsHrRows.length
      : employeeQuery.data?.totalCount ?? 0;

  const hasActiveFilters = Boolean(search.trim() || storeId || status || assignmentType);

  const activeCount = summaryData?.actual ?? 0;
  const vacancyCount = summaryData?.vacant ?? 0;
  const inactiveCount = inactiveCountQuery.data ?? 0;
  const needsHrCount = accountHasAssignedHrco
    ? 0
    : (unassignedHrcoCountQuery.data && unassignedHrcoCountQuery.data > 0
        ? unassignedHrcoCountQuery.data
        : (needsHrRows.length > 0 ? needsHrRows.length : activeCount));

  const fulfillmentRate =
    summaryData?.required && summaryData.required > 0
      ? Math.round(((summaryData.actual ?? 0) / summaryData.required) * 100)
      : 0;

  // -------------------------------------------------------------------------
  // Handlers
  // -------------------------------------------------------------------------

  function getAccountSummary(accId: string) {
    if (accountMetricsQuery.data?.has(accId)) {
      return accountMetricsQuery.data.get(accId)!;
    }
    return { required: 0, actual: 0, hrProcess: 0, vacant: 0, fillRate: 0 };
  }

  function handleSwitchView(mode: PlantillaViewMode) {
    const params = new URLSearchParams(searchParams.toString());
    if (mode === "store") {
      params.delete("view");
      params.delete("tab");
    } else {
      params.set("view", mode);
    }
    router.push(`${pathname}?${params.toString()}`);
  }

  function handleSelectAccount(accId: string) {
    const acc = allowedAccountsQuery.data?.find((a) => a.id === accId);
    if (acc?.isPoolAccount || acc?.name.trim().toLowerCase() === "moses hq") {
      handleSwitchView("moses_pool");
      return;
    }

    setSearch("");
    setStoreId("");
    setStatus("");
    setAssignmentType("");
    setTab("active");
    setPage(1);

    const params = new URLSearchParams(searchParams.toString());
    params.set("accountId", accId);
    params.delete("view");
    router.push(`${pathname}?${params.toString()}`);
  }

  function handleBackToSelection() {
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

  if (!currentUser) {
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
    if (allowedAccountsQuery.isLoading) {
      return (
        <DataState
          kind="loading"
          title="Loading Accounts"
          description="Fetching your authorized accounts..."
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
            accountMetricsQuery.refetch();
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
                      bar: "bg-pct-good-bar",
                      text: "text-pct-good-text",
                      track: "bg-surface-muted border border-border-subtle/50",
                    };
                  }
                  if (rate >= 95) {
                    return {
                      bar: "bg-pct-warn-bar",
                      text: "text-pct-warn-text",
                      track: "bg-surface-muted border border-border-subtle/50",
                    };
                  }
                  return {
                    bar: "bg-pct-bad-bar",
                    text: "text-pct-bad-text",
                    track: "bg-surface-muted border border-border-subtle/50",
                  };
                };

                const colors = getProgressColors(account.fillRate);

                return (
                  <button
                    key={account.id}
                    type="button"
                    onClick={() => handleSelectAccount(account.id)}
                    className="group relative flex w-full items-start gap-4 rounded-xl border border-border-default bg-surface-base p-5 text-left transition-all duration-300 hover:-translate-y-0.5 hover:border-brand-primary hover:shadow-md focus:outline-none focus:ring-2 focus:ring-brand-primary focus:ring-offset-2"
                  >
                    <div
                      className={`shrink-0 rounded-lg p-2.5 ${
                        account.isPoolAccount
                          ? "bg-surface-muted text-brand-primary border border-border-default"
                          : "bg-brand-50/60 text-brand-primary"
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
                                  ? formatDisplayText(account.groupName)
                                  : `Group ${formatDisplayText(account.groupName)}`}{" "}
                                •
                              </span>
                            )}
                            {formatAccountName(account.name)}
                          </h3>
                          {account.isPoolAccount && (
                            <p className="text-[10px] font-bold text-text-secondary tracking-wider mt-0.5">
                              Workforce Pool Inside Plantilla
                            </p>
                          )}
                        </div>

                        <div className="shrink-0 flex items-center gap-1.5">
                          {account.isPoolAccount ? (
                            <span className="inline-flex items-center rounded-full bg-surface-muted border border-border-default px-2 py-0.5 text-xs font-semibold text-text-primary">
                              Pool
                            </span>
                          ) : (
                            account.required > 0 && account.fillRate < 80 && (
                              <span className="inline-flex items-center rounded-full bg-surface-muted border border-border-default px-2 py-0.5 text-xs font-semibold text-text-secondary">
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
                          <span className="text-[10px] font-bold text-text-secondary shrink-0 w-8">
                            MFR
                          </span>
                          <div
                            className={`relative flex-1 h-2 rounded-full overflow-hidden ${
                              account.required > 0 ? colors.track : "bg-surface-muted border border-border-subtle/50"
                            }`}
                          >
                            {account.required > 0 && (
                              <div
                                className={`absolute left-0 top-0 h-full rounded-full transition-all duration-500 ${colors.bar}`}
                                style={{ width: `${Math.min(100, account.fillRate)}%` }}
                              />
                            )}
                          </div>
                          <span
                            className={`text-xs font-semibold shrink-0 w-8 text-right font-mono ${
                              account.required > 0 ? colors.text : "text-text-muted"
                            }`}
                          >
                            {account.required > 0 ? `${account.fillRate}%` : "—"}
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

  if (viewMode === "moses_pool") {
    return (
      <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-5 text-text-primary">
        <AdminPageHeader
          categoryTag="Admin panel"
          moduleName="Plantilla"
          title={
            <nav className="flex items-center gap-1.5 text-xs" aria-label="Breadcrumb">
              <button
                type="button"
                onClick={() => handleSwitchView("store")}
                className="inline-flex items-center gap-1 font-medium text-text-secondary hover:text-brand-600 transition-colors cursor-pointer"
              >
                <ArrowLeft className="h-3 w-3" />
                <span>Plantilla Directory</span>
              </button>
              <span className="text-text-muted/60">/</span>
              <span className="text-sm font-semibold text-text-primary leading-tight">
                Moses HQ Pool Management
              </span>
            </nav>
          }
          subtitle="Tracking, filtering, and managing non-plantilla pooled personnel (Relievers, Commandos, Seasonals)."
          icon={Users}
        />
        <MosesHqPoolView />
      </div>
    );
  }

  if (viewMode === "analytics") {
    return (
      <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-5 text-text-primary">
        <AdminPageHeader
          categoryTag="Admin panel"
          moduleName="Plantilla"
          title={
            <nav className="flex items-center gap-1.5 text-xs" aria-label="Breadcrumb">
              <button
                type="button"
                onClick={() => handleSwitchView("store")}
                className="inline-flex items-center gap-1 font-medium text-text-secondary hover:text-brand-600 transition-colors cursor-pointer"
              >
                <ArrowLeft className="h-3 w-3" />
                <span>Plantilla Directory</span>
              </button>
              <span className="text-text-muted/60">/</span>
              <span className="text-sm font-semibold text-text-primary leading-tight">
                Workforce Analytics Dashboard
              </span>
            </nav>
          }
          subtitle="7-Tab executive workforce analytics: Overview, Deployment, Coverage, Conversion, Slots, Health, Executive."
          icon={BarChart3}
        />
        <WorkforceAnalyticsView />
      </div>
    );
  }

  return (
    <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-5 text-text-primary">
      {!accountId ? (
        <>
          <AdminPageHeader
            categoryTag="Admin panel"
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
            categoryTag="Admin panel"
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
                  className="group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border border-border-default bg-surface-base px-3.5 py-2 text-xs font-semibold text-text-secondary hover:border-border-strong hover:bg-surface-hover hover:text-text-primary transition cursor-pointer shadow-2xs"
                >
                  <Building2 className="w-4 h-4 shrink-0 text-text-muted group-hover:text-text-secondary transition-colors" />
                  <span>Store Staffing</span>
                  <span className="ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold bg-surface-muted text-text-secondary border border-border-default shadow-2xs transition-colors">
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
                value={summaryData && summaryData.required > 0 ? `${fulfillmentRate}%` : "—"}
                helperText={`${summaryData?.actual ?? 0} active / ${summaryData?.required ?? 0} quota`}
                badge={summaryData && summaryData.required > 0 ? `${fulfillmentRate}%` : undefined}
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
                <span className="font-bold text-[11px] text-text-primary">
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
                  aria-selected={effectiveTab === "active"}
                  onClick={() => {
                    setTab("active");
                    setPage(1);
                  }}
                  className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                    effectiveTab === "active"
                      ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                      : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
                  }`}
                >
                  <Users
                    className={`w-4 h-4 shrink-0 transition-colors ${
                      effectiveTab === "active"
                        ? "text-tab-active-text"
                        : "text-text-muted group-hover:text-text-secondary"
                    }`}
                  />
                  <span>Active Roster</span>
                  <span
                    className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-sans tabular-nums text-xs font-semibold shadow-2xs transition-colors ${
                      effectiveTab === "active"
                        ? "bg-brand-button text-white"
                        : "bg-surface-muted text-text-secondary border border-border-default"
                    }`}
                  >
                    {activeCount}
                  </span>
                </button>

                {/* Tab 2: Vacancy */}
                <button
                  type="button"
                  role="tab"
                  aria-selected={effectiveTab === "vacancy"}
                  onClick={() => {
                    setTab("vacancy");
                    setPage(1);
                  }}
                  className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                    effectiveTab === "vacancy"
                      ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                      : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
                  }`}
                >
                  <Briefcase
                    className={`w-4 h-4 shrink-0 transition-colors ${
                      effectiveTab === "vacancy"
                        ? "text-tab-active-text"
                        : "text-text-muted group-hover:text-text-secondary"
                    }`}
                  />
                  <span>Vacancy</span>
                  <span
                    className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-sans tabular-nums text-xs font-semibold shadow-2xs transition-colors ${
                      effectiveTab === "vacancy"
                        ? "bg-brand-button text-white"
                        : "bg-surface-muted text-text-secondary border border-border-default"
                    }`}
                  >
                    {vacancyCount}
                  </span>
                </button>

                {/* Tab 3: Inactive / Floating */}
                <button
                  type="button"
                  role="tab"
                  aria-selected={effectiveTab === "inactive"}
                  onClick={() => {
                    setTab("inactive");
                    setPage(1);
                  }}
                  className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                    effectiveTab === "inactive"
                      ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                      : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
                  }`}
                >
                  <UserMinus
                    className={`w-4 h-4 shrink-0 transition-colors ${
                      effectiveTab === "inactive"
                        ? "text-tab-active-text"
                        : "text-text-muted group-hover:text-text-secondary"
                    }`}
                  />
                  <span>Inactive / Floating</span>
                  <span
                    className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-sans tabular-nums text-xs font-semibold shadow-2xs transition-colors ${
                      effectiveTab === "inactive"
                        ? "bg-brand-button text-white"
                        : "bg-surface-muted text-text-secondary border border-border-default"
                    }`}
                  >
                    {inactiveCount}
                  </span>
                </button>

                {/* Tab 4: Needs HRCO (Only visible when account has no assigned HRCO) */}
                {!accountHasAssignedHrco && (
                  <button
                    type="button"
                    role="tab"
                    aria-selected={effectiveTab === "needs_hr"}
                    onClick={() => {
                      setTab("needs_hr");
                      setPage(1);
                    }}
                    className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                      effectiveTab === "needs_hr"
                        ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                        : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
                    }`}
                  >
                    <AlertCircle
                      className={`w-4 h-4 shrink-0 transition-colors ${
                        effectiveTab === "needs_hr"
                          ? "text-tab-active-text"
                          : "text-text-muted group-hover:text-text-secondary"
                      }`}
                    />
                    <span>Needs HRCO</span>
                    <span
                      className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-sans tabular-nums text-xs font-semibold shadow-2xs transition-colors ${
                        effectiveTab === "needs_hr"
                          ? "bg-brand-button text-white"
                          : "bg-surface-muted text-text-secondary border border-border-default"
                      }`}
                    >
                      {needsHrCount}
                    </span>
                  </button>
                )}
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
                    className="inline-flex h-10 items-center gap-1.5 rounded-lg border border-border-default bg-surface-muted px-3 text-xs font-semibold text-text-primary hover:bg-surface-hover transition-colors shadow-2xs"
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
                    if (effectiveTab === "vacancy") {
                      vacancyListQuery.refetch();
                      occupiedStoresQuery.refetch();
                    } else if (effectiveTab === "needs_hr") {
                      needsHrcoQuery.refetch();
                    } else {
                      employeeQuery.refetch();
                    }
                  }}
                />
              </div>
            ) : effectiveTab === "vacancy" ? (
              vacancyRows.length === 0 && missingStoreVacancies.length === 0 ? (
                <EmptyTabState
                  hasActiveFilters={hasActiveFilters}
                  onResetFilters={handleResetFilters}
                  tabLabel="vacancies"
                />
              ) : displayView === "table" ? (
                <VacancyTable
                  rows={vacancyRows}
                  missingStores={missingStoreVacancies}
                  onSelectVacancy={(v) => setSelectedVacancyId(v.id)}
                  onDirectImport={async (item) => {
                    try {
                      await directImportMutation.mutateAsync({
                        vcode: item.code || "VCODE",
                        accountId,
                        storeId: item.id,
                        storeName: item.name,
                        position: "Merchandiser",
                        positionTitle: "Merchandiser",
                        areaCity: item.city,
                        province: item.province,
                        areaProvince: item.province,
                      });
                    } catch (err: unknown) {
                      alert(err instanceof Error ? err.message : "Failed to direct import vacancy");
                    }
                  }}
                  isDirectImportPending={directImportMutation.isPending}
                />
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3.5">
                  {vacancyRows.map((v) => (
                    <VacancyCard
                      key={v.id}
                      vacancy={v}
                      onSelect={() => setSelectedVacancyId(v.id)}
                    />
                  ))}
                </div>
              )
            ) : effectiveTab === "needs_hr" ? (
              needsHrRows.length === 0 ? (
                <EmptyTabState
                  hasActiveFilters={hasActiveFilters}
                  onResetFilters={handleResetFilters}
                  tabLabel="employees needing HRCO assignment"
                />
              ) : displayView === "table" ? (
                <EmployeeTable
                  rows={paginatedNeedsHrRows}
                  isNeedsHr
                  accountHasHrco={accountHasAssignedHrco}
                  onRowClick={setSelectedPlantillaId}
                  storeLookupMap={storeLookupMap}
                />
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3.5">
                  {paginatedNeedsHrRows.map((row) => (
                    <EmployeeCard
                      key={row.id}
                      row={row}
                      isNeedsHr
                      accountHasHrco={accountHasAssignedHrco}
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
                tabLabel={effectiveTab === "inactive" ? "inactive or floating employees" : "active deployed employees"}
              />
            ) : displayView === "table" ? (
              <EmployeeTable
                rows={employeeRows}
                isInactive={effectiveTab === "inactive"}
                accountHasHrco={accountHasAssignedHrco}
                onRowClick={setSelectedPlantillaId}
                storeLookupMap={storeLookupMap}
              />
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3.5">
                {employeeRows.map((row) => (
                  <EmployeeCard
                    key={row.id}
                    row={row}
                    isInactive={effectiveTab === "inactive"}
                    accountHasHrco={accountHasAssignedHrco}
                    onSelect={() => setSelectedPlantillaId(row.id)}
                    storeLookupMap={storeLookupMap}
                  />
                ))}
              </div>
            )}

            {/* Pagination Controls */}
            {!isListLoading && !isListError && totalCount > 0 && (
              <TablePagination
                page={page}
                pageSize={pageSize}
                totalCount={totalCount}
                pageSizeOptions={[10, 25, 50]}
                onPageChange={(p) => setPage(p)}
                onPageSizeChange={(newPageSize) => {
                  setPageSize(newPageSize);
                  setPage(1);
                }}
                isLoading={isListLoading}
                className="mt-4 pt-4 border-t border-border-default px-0"
              />
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

          <VacancyDetailDrawer
            vacancyId={selectedVacancyId}
            onClose={() => setSelectedVacancyId(null)}
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
                if (effectiveTab === "vacancy") {
                  vacancyListQuery.refetch();
                  occupiedStoresQuery.refetch();
                }
                if (effectiveTab === "needs_hr") needsHrcoQuery.refetch();
              }}
            />
          )}

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
  accountHasHrco,
  onRowClick,
  storeLookupMap,
}: {
  rows: PlantillaEmployeeListItem[];
  isInactive?: boolean;
  isNeedsHr?: boolean;
  accountHasHrco?: boolean;
  onRowClick: (id: string) => void;
  storeLookupMap: Map<string, { city: string | null; province: string | null; code: string | null }>;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs">
      <div className="overflow-x-auto">
        <table className="w-full min-w-[980px] text-left text-sm">
          <thead>
            <tr className="border-b border-table-rule bg-table-header">
              <th className="px-4 py-3 text-left text-sm font-semibold text-text-secondary whitespace-nowrap">
                Member
              </th>
              <th className="px-4 py-3 text-left text-sm font-semibold text-text-secondary whitespace-nowrap">
                Store
              </th>
              <th className="px-4 py-3 text-left text-sm font-semibold text-text-secondary whitespace-nowrap">
                Position
              </th>
              <th className="px-4 py-3 text-left text-sm font-semibold text-text-secondary whitespace-nowrap">
                Assignment
              </th>
              <th className="px-4 py-3 text-left text-sm font-semibold text-text-secondary whitespace-nowrap">
                Status
              </th>
              <th className="px-4 py-3 text-right text-sm font-semibold text-text-secondary whitespace-nowrap">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-table-rule">
            {rows.map((row) => {
              const overlay = deriveDeactivationOverlay(row.plantillaStatus);

              const rowClass = overlay.isPendingSeparation
                ? "border border-dashed border-border-default bg-surface-muted/40 opacity-80 cursor-pointer transition-colors"
                : isInactive
                ? "opacity-80 transition-colors hover:bg-table-row-hover cursor-pointer"
                : "transition-colors hover:bg-table-row-hover cursor-pointer";

              const displayName =
                formatPersonName(
                  row.firstName,
                  row.lastName,
                  null,
                  row.fullName || `${row.lastName || ""}, ${row.firstName || ""}`,
                ) || "—";

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
                      <div className="h-9 w-9 rounded-full bg-surface-muted border border-border-default text-brand-primary font-bold text-xs flex items-center justify-center shrink-0 shadow-xs">
                        {initials}
                      </div>
                      <div className="min-w-0">
                        <div className="flex items-center gap-1.5 flex-wrap">
                          <span className="font-semibold text-table-text text-sm hover:text-brand-primary transition-colors">
                            {displayName}
                          </span>
                          {row.plantillaType === "AH" && (
                            <span className="inline-flex items-center rounded border border-pct-warn-border bg-pct-warn-bg px-1.5 py-0.2 text-[10px] font-bold text-pct-warn-text">
                              AH
                            </span>
                          )}
                        </div>
                        <div className="font-mono text-xs text-table-text-muted mt-0.5">
                          {row.cgCode || row.vcode ? `${row.cgCode || row.vcode} • ${row.employeeNo}` : row.employeeNo}
                        </div>
                      </div>
                    </div>
                  </td>

                  {/* STORE */}
                  <td className="px-4 py-3 text-table-text">
                    {(() => {
                      const storeObj = formatStoreDisplay(row.primaryStoreName || row.vcode, row.assignedStores);
                      return (
                        <div className="min-w-0" title={storeObj.isMulti ? storeObj.tooltip : undefined}>
                          <div className="font-medium text-table-text flex items-center gap-1.5">
                            <span className="truncate">{formatStoreName(storeObj.displayText)}</span>
                            {storeObj.isMulti && (
                              <span className="inline-flex items-center px-1.5 py-0.2 rounded text-[10px] font-semibold bg-brand-50 text-brand-700 border border-brand-200 shrink-0">
                                +{storeObj.extraCount}
                              </span>
                            )}
                          </div>
                          {locationLabel ? (
                            <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-2 py-0.5 text-[11px] font-medium text-text-secondary border border-border-subtle mt-1">
                              <MapPin className="h-3 w-3 text-text-muted shrink-0" />
                              <span className="truncate max-w-[150px]">{formatStoreName(locationLabel)}</span>
                            </span>
                          ) : row.accountName ? (
                            <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-2 py-0.5 text-[11px] font-medium text-text-muted border border-border-subtle mt-1 truncate max-w-[150px]">
                              {formatAccountName(row.accountName)}
                            </span>
                          ) : null}
                        </div>
                      );
                    })()}
                  </td>

                  {/* POSITION */}
                  <td className="px-4 py-3">
                    <div className="flex flex-col">
                      <span className="font-medium text-table-text text-sm">
                        {row.positionTitle ? formatPosition(row.positionTitle) : "General Staff"}
                      </span>
                      <span className="text-xs text-table-text-muted mt-0.5">
                        {row.plantillaType ? `${row.plantillaType} Position` : "Standard Tier"}
                      </span>
                    </div>
                  </td>

                  {/* ASSIGNMENT */}
                  <td className="px-4 py-3">
                    {row.assignmentType?.toLowerCase() === "roving" ? (
                      <span className="inline-flex items-center gap-1 rounded-md bg-surface-muted border border-border-default px-2 py-0.5 text-xs font-semibold text-text-primary">
                        Roving{row.coveredStoresCount > 1 ? ` (${row.coveredStoresCount})` : ""}
                      </span>
                    ) : row.assignmentType?.toLowerCase() === "reliever" ? (
                      <span className="inline-flex items-center gap-1 rounded-md bg-surface-muted border border-border-default px-2 py-0.5 text-xs font-semibold text-text-primary">
                        Reliever
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1 rounded-md bg-surface-muted border border-border-default px-2 py-0.5 text-xs font-semibold text-text-secondary">
                        Stationary
                      </span>
                    )}
                  </td>

                  {/* STATUS */}
                  <td className="px-4 py-3">
                    {isNeedsHr && !accountHasHrco ? (
                      <span className="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold bg-pct-warn-bg text-pct-warn-text border border-pct-warn-border">
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
                      className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-secondary hover:text-brand-primary hover:border-border-strong hover:bg-surface-hover transition-colors shadow-xs"
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

function getAgingBadge(days: number | null | undefined) {
  if (days === null || days === undefined) {
    return <span className="text-xs text-text-muted font-mono">—</span>;
  }
  let badgeClass = "bg-pct-good-bg text-pct-good-text border-pct-good-border";
  if (days > 30) {
    badgeClass = "bg-pct-bad-bg text-pct-bad-text border-pct-bad-border";
  } else if (days > 15) {
    badgeClass = "bg-pct-warn-bg text-pct-warn-text border-pct-warn-border";
  }
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-mono font-bold border ${badgeClass}`}>
      {days} {days === 1 ? "day" : "days"}
    </span>
  );
}

function VacancyTable({
  rows,
  missingStores = [],
  onSelectVacancy,
  onDirectImport,
  isDirectImportPending = false,
}: {
  rows: VacancyListItem[];
  missingStores?: { id: string; name: string; code: string | null; city: string | null; province: string | null }[];
  onSelectVacancy: (v: VacancyListItem) => void;
  onDirectImport?: (store: { id: string; name: string; code: string | null; city: string | null; province: string | null }) => void;
  isDirectImportPending?: boolean;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs space-y-0">
      <div className="overflow-x-auto">
        <table className="w-full min-w-[980px] text-left text-sm">
          <thead>
            <tr className="border-b border-table-rule bg-table-header">
              <th className="px-4 py-3 text-left text-sm font-semibold text-text-secondary whitespace-nowrap">
                VCODE
              </th>
              <th className="px-4 py-3 text-left text-sm font-semibold text-text-secondary whitespace-nowrap">
                Position
              </th>
              <th className="px-4 py-3 text-left text-sm font-semibold text-text-secondary whitespace-nowrap">
                Store
              </th>
              <th className="px-4 py-3 text-left text-sm font-semibold text-text-secondary whitespace-nowrap">
                HC needed
              </th>
              <th className="px-4 py-3 text-left text-sm font-semibold text-text-secondary whitespace-nowrap">
                Aging
              </th>
              <th className="px-4 py-3 text-left text-sm font-semibold text-text-secondary whitespace-nowrap">
                Pipeline status
              </th>
              <th className="px-4 py-3 text-right text-sm font-semibold text-text-secondary whitespace-nowrap">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-table-rule">
            {rows.map((row) => (
              <tr
                key={row.id}
                className="transition-colors hover:bg-table-row-hover cursor-pointer"
                onClick={() => onSelectVacancy(row)}
              >
                <td className="px-4 py-3 font-mono font-bold text-brand-primary">
                  {row.cgCode || row.vcode || "Uncoded"}
                </td>
                <td className="px-4 py-3 font-medium text-table-text">
                  {row.position_title || "General Staff"}
                </td>
                <td className="px-4 py-3 text-table-text">
                  {(() => {
                    const storeObj = formatStoreDisplay(row.storeName, row.assignedStores);
                    return (
                      <div className="flex items-center gap-1.5" title={storeObj.isMulti ? storeObj.tooltip : undefined}>
                        <span className="truncate">{storeObj.displayText}</span>
                        {storeObj.isMulti && (
                          <span className="inline-flex items-center px-1.5 py-0.2 rounded text-[10px] font-semibold bg-surface-muted text-brand-primary border border-border-default shrink-0">
                            +{storeObj.extraCount}
                          </span>
                        )}
                      </div>
                    );
                  })()}
                </td>
                <td className="px-4 py-3 font-mono font-bold text-table-text">
                  {row.activeApplicantCount > 0 ? row.activeApplicantCount : 1}
                </td>
                <td className="px-4 py-3">
                  {getAgingBadge(row.agingDays)}
                </td>
                <td className="px-4 py-3">
                  <span className="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-bold bg-surface-muted text-text-primary border border-border-default">
                    {row.pipelineStatus || "Open"}
                  </span>
                </td>
                <td className="px-4 py-3 text-right">
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      onSelectVacancy(row);
                    }}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-secondary hover:text-brand-primary hover:border-border-strong hover:bg-surface-hover transition-colors shadow-xs cursor-pointer"
                    aria-label={`Inspect vacancy ${row.cgCode || row.vcode || row.id}`}
                  >
                    <Eye className="h-3.5 w-3.5" />
                    <span>Inspect</span>
                  </button>
                </td>
              </tr>
            ))}

            {/* Unlisted / Missing store vacancies eligible for direct 1-click import */}
            {missingStores.length > 0 && (
              <>
                <tr className="bg-surface-muted border-t-2 border-border-default">
                  <td colSpan={7} className="px-4 py-2 text-sm font-semibold text-text-primary">
                    <div className="flex items-center justify-between">
                      <span className="flex items-center gap-1.5">
                        <AlertCircle className="h-3.5 w-3.5 text-text-secondary" />
                        Stores without Active Vacancies ({missingStores.length}) — Click Direct Import to provision instantly without wizard
                      </span>
                    </div>
                  </td>
                </tr>
                {missingStores.map((store) => (
                  <tr
                    key={`missing-${store.id}`}
                    className="transition-colors hover:bg-surface-hover bg-surface-subtle/30"
                  >
                    <td className="px-4 py-3 font-mono font-bold text-text-secondary">
                      {store.code || "Uncoded"}
                    </td>
                    <td className="px-4 py-3 font-medium text-text-secondary">
                      Merchandiser
                    </td>
                    <td className="px-4 py-3 text-text-secondary">
                      <div className="flex items-center gap-1.5">
                        <span className="truncate">{store.name}</span>
                        {(store.city || store.province) && (
                          <span className="text-3xs text-text-muted">
                            ({[store.city, store.province].filter(Boolean).join(", ")})
                          </span>
                        )}
                      </div>
                    </td>
                    <td className="px-4 py-3 font-mono font-bold text-text-muted">
                      1
                    </td>
                    <td className="px-4 py-3 text-sm text-text-muted font-mono">
                      —
                    </td>
                    <td className="px-4 py-3">
                      <span className="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold bg-pct-warn-bg text-pct-warn-text border border-pct-warn-border">
                        Missing from Vacancies
                      </span>
                    </td>
                    <td className="px-4 py-3 text-right">
                      {onDirectImport && (
                        <button
                          type="button"
                          disabled={isDirectImportPending}
                          onClick={(e) => {
                            e.stopPropagation();
                            onDirectImport(store);
                          }}
                          className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-2.5 py-1.5 text-xs font-semibold text-brand-primary hover:bg-surface-hover hover:border-border-strong transition-colors shadow-xs cursor-pointer disabled:opacity-50"
                          title={`Directly create vacancy slot for ${store.name} (${store.code || "VCODE"}) without wizard`}
                        >
                          <Plus className="h-3.5 w-3.5" />
                          <span>Direct Import</span>
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </>
            )}
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
  accountHasHrco,
  onSelect,
  storeLookupMap,
}: {
  row: PlantillaEmployeeListItem;
  isInactive?: boolean;
  isNeedsHr?: boolean;
  accountHasHrco?: boolean;
  onSelect: () => void;
  storeLookupMap: Map<string, { city: string | null; province: string | null; code: string | null }>;
}) {
  const overlay = deriveDeactivationOverlay(row.plantillaStatus);
  const displayName =
    formatPersonName(
      row.firstName,
      row.lastName,
      null,
      row.fullName || `${row.lastName || ""}, ${row.firstName || ""}`,
    ) || "—";

  const initials = getInitials(row.firstName, row.lastName);

  const storeInfo = row.primaryStoreName
    ? storeLookupMap.get(row.primaryStoreName.toLowerCase().trim())
    : null;
  const locationLabel = [storeInfo?.city, storeInfo?.province].filter(Boolean).join(", ");

  const statusLower = (row.plantillaStatus ?? "").toLowerCase();
  const isOnLeave = statusLower === "on leave" || statusLower === "on_leave";
  const isPendingSeparation = overlay.isPendingSeparation || statusLower === "pending separation";

  const accentBorderClass = isPendingSeparation
    ? "border-l-4 border-l-border-strong bg-surface-muted/20"
    : isOnLeave
    ? "border-l-4 border-l-pct-warn-text"
    : isInactive
    ? "border-l-4 border-l-border-default"
    : isNeedsHr && !accountHasHrco
    ? "border-l-4 border-l-brand-primary"
    : "border-l-4 border-l-pct-good-text";

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
      className={`group relative flex flex-col justify-between overflow-hidden rounded-xl border border-border-default bg-surface-base p-4 text-left shadow-xs transition-all duration-200 hover:-translate-y-0.5 hover:border-brand-primary hover:shadow-md cursor-pointer focus:outline-none focus:ring-2 focus:ring-brand-primary ${accentBorderClass}`}
    >
      <div>
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 shrink-0 rounded-full bg-surface-muted border border-border-default text-brand-primary font-bold text-xs flex items-center justify-center shadow-xs">
            {initials}
          </div>

          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-1.5 flex-wrap">
              <h4 className="text-sm font-bold text-text-primary truncate group-hover:text-brand-primary transition-colors">
                {displayName}
              </h4>
              {row.plantillaType === "AH" && (
                <span className="shrink-0 rounded border border-pct-warn-border bg-pct-warn-bg px-1.5 py-0.2 text-[10px] font-bold text-pct-warn-text">
                  AH
                </span>
              )}
            </div>

            <div className="flex items-center gap-1.5 text-xs text-text-muted mt-0.5 truncate">
              <span className="font-mono text-text-secondary">
                {row.cgCode || row.vcode ? `${row.cgCode || row.vcode} • ${row.employeeNo}` : row.employeeNo || "—"}
              </span>
              <span className="text-text-muted/40">•</span>
              <span className="font-semibold text-brand-primary truncate">
                {row.positionTitle || "General Staff"}
              </span>
            </div>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            {isNeedsHr && !accountHasHrco ? (
              <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-bold bg-pct-warn-bg text-pct-warn-text border border-pct-warn-border">
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
        {(() => {
          const storeObj = formatStoreDisplay(row.primaryStoreName || row.vcode, row.assignedStores);
          return (
            <div className="flex items-center gap-1.5 truncate max-w-[70%]" title={storeObj.isMulti ? storeObj.tooltip : undefined}>
              <MapPin className="h-3.5 w-3.5 text-text-muted shrink-0" />
              <span className="truncate font-medium text-text-secondary">
                {storeObj.displayText}
                {locationLabel ? ` (${locationLabel})` : ""}
              </span>
              {storeObj.isMulti && (
                <span className="inline-flex items-center px-1.5 py-0.2 rounded text-[10px] font-semibold bg-surface-muted text-brand-primary border border-border-default shrink-0">
                  +{storeObj.extraCount}
                </span>
              )}
            </div>
          );
        })()}

        <span
          className={`inline-flex items-center px-2 py-0.5 rounded text-[11px] font-semibold border ${
            row.assignmentType?.toLowerCase() === "roving"
              ? "bg-surface-muted text-text-primary border-border-default"
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
  onSelect,
}: {
  vacancy: VacancyListItem;
  onSelect: () => void;
}) {
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
      className="group relative flex flex-col justify-between overflow-hidden rounded-xl border border-border-default bg-surface-base p-4 text-left shadow-xs transition-all duration-200 hover:-translate-y-0.5 hover:border-brand-primary hover:shadow-md cursor-pointer border-l-4 border-l-pct-warn-text focus:outline-none focus:ring-2 focus:ring-brand-primary"
    >
      <div>
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 shrink-0 rounded-xl bg-pct-warn-bg text-pct-warn-text border border-pct-warn-border flex items-center justify-center shadow-xs">
            <Briefcase className="h-5 w-5" />
          </div>

          <div className="flex-1 min-w-0">
            <h4 className="text-sm font-bold text-text-primary truncate group-hover:text-brand-primary transition-colors">
              {vacancy.position_title || "Open Position"}
            </h4>

            <div className="flex items-center gap-1.5 text-xs text-text-muted mt-0.5 truncate">
              <span className="font-mono font-bold text-brand-primary">{vacancy.cgCode || vacancy.vcode || "Uncoded"}</span>
              <span className="text-text-muted/40">•</span>
              <span className="font-medium text-text-secondary">
                HC: {vacancy.activeApplicantCount > 0 ? vacancy.activeApplicantCount : 1}
              </span>
            </div>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <span className="inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-bold bg-surface-muted text-text-primary border border-border-default">
              {vacancy.pipelineStatus || "Open"}
            </span>
            <ChevronRight className="h-5 w-5 text-text-muted/60 transition-transform group-hover:translate-x-0.5" />
          </div>
        </div>
      </div>

      <div className="mt-3.5 pt-2.5 border-t border-border-subtle flex items-center justify-between gap-2 text-xs text-text-secondary">
        {(() => {
          const storeObj = formatStoreDisplay(vacancy.storeName, vacancy.assignedStores);
          return (
            <div className="flex items-center gap-1.5 truncate max-w-[70%]" title={storeObj.isMulti ? storeObj.tooltip : undefined}>
              <MapPin className="h-3.5 w-3.5 text-text-muted shrink-0" />
              <span className="truncate font-medium text-text-secondary">
                {storeObj.displayText}
              </span>
              {storeObj.isMulti && (
                <span className="inline-flex items-center px-1.5 py-0.2 rounded text-[10px] font-semibold bg-surface-muted text-brand-primary border border-border-default shrink-0">
                  +{storeObj.extraCount}
                </span>
              )}
            </div>
          );
        })()}

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
          <span className="absolute -top-1 -right-1 flex h-5 w-5 items-center justify-center rounded-full bg-brand-button text-xs font-bold text-white shadow-xs">
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
