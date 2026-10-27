"use client";

import { useState, useMemo, useCallback, Suspense } from "react";
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
  UserCheck,
  RotateCw,
} from "lucide-react";
import { useSearchParams, useRouter, usePathname } from "next/navigation";
import { useCurrentUser, isOpsAmendmentRole } from "@/lib/auth";
import { createClient } from "@/lib/supabase/client";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { DataState } from "@/components/shared/DataState";
import { TablePagination } from "@/components/shared/TablePagination";
import { StatusBadge } from "@/components/ui/StatusBadge";
import type { BadgeVariant } from "@/components/ui/StatusBadge";
import {
  getPlantillaSummary,
  listWebPlantillaEmployees,
  listWebPlantillaStoreStaffing,
  fetchActiveCoverageForAccount,
  fetchPlantillaScopedAccounts,
  deriveDeactivationOverlay,
  type PlantillaEmployeeListItem,
  type ActiveCoverageItem,
} from "@/lib/queries/plantilla";
import { fetchTeamDirectory, type TeamDirectoryUser } from "@/lib/queries/team_directory";
import {
  listVacancies,
  type VacancyListItem,
} from "@/lib/queries/vacancy";
import {
  formatPersonName,
  formatPosition,
  formatStoreName,
  formatAccountName,
  formatDisplayText,
} from "@/lib/utils/displayText";
import { PlantillaDetailDrawer } from "@/components/plantilla/PlantillaDetailDrawer";
import { VacancyDetailDrawer } from "@/components/vacancy/VacancyDetailDrawer";
import { RequestHeadcountModal } from "@/components/modals/RequestHeadcountModal";
import { MosesHqPoolView } from "@/components/plantilla/MosesHqPoolView";
import { WorkforceAnalyticsView } from "@/components/plantilla/WorkforceAnalyticsView";
import { AssignRelieverModal } from "@/components/plantilla/AssignRelieverModal";
import { ReturnToActiveModal } from "@/components/plantilla/ReturnToActiveModal";
import { AssignStoreModal } from "@/components/plantilla/AssignStoreModal";

// ---------------------------------------------------------------------------
// Types & Constants
// ---------------------------------------------------------------------------

export type PlantillaViewMode = "store" | "moses_pool" | "analytics";
export type MainViewToggle = "employee" | "store";
export type StatusSubTab = "active" | "on_leave" | "vacancy" | "floating" | "deactivation";
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
// Circular SVG MFR Donut (CENCOM Style)
// ---------------------------------------------------------------------------

function OverallMfrDonut({
  percent,
  size = 72,
  strokeWidth = 7.5,
}: {
  percent: number;
  size?: number;
  strokeWidth?: number;
}) {
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const sweepFraction = Math.min(1, Math.max(0, percent / 100));
  const strokeDashoffset = circumference * (1 - sweepFraction);

  // Dynamic stroke color based on percentage:
  // Red (#dc2626) for < 75%
  // Amber (#d97706) for 75%–89.9%
  // Emerald (#16a34a) for >= 90%
  const strokeColor =
    percent >= 90 ? "#16a34a" : percent >= 75 ? "#d97706" : "#dc2626";

  return (
    <div
      className="relative inline-flex items-center justify-center my-0.5"
      style={{ width: size, height: size }}
      role="progressbar"
      aria-valuenow={Math.round(percent)}
      aria-valuemin={0}
      aria-valuemax={100}
    >
      <svg
        width={size}
        height={size}
        className="-rotate-90 transform"
        aria-hidden="true"
      >
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          stroke="currentColor"
          strokeWidth={strokeWidth}
          fill="transparent"
          className="text-slate-100 dark:text-surface-muted"
        />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          stroke={strokeColor}
          strokeWidth={strokeWidth}
          fill="transparent"
          strokeDasharray={circumference}
          strokeDashoffset={strokeDashoffset}
          strokeLinecap="round"
          className="transition-all duration-500 ease-out"
        />
      </svg>
      <div className="absolute inset-0 flex items-center justify-center">
        <span className="text-sm font-bold tracking-tight text-text-primary tabular-nums">
          {percent.toFixed(1)}%
        </span>
      </div>
    </div>
  );
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
  // Main view toggle: "employee" vs "store"
  const [mainView, setMainView] = useState<MainViewToggle>("employee");

  // 5 Status Sub-Tabs
  const [statusTab, setStatusTab] = useState<StatusSubTab>("active");
  const [displayView, setDisplayView] = useState<DisplayView>("table");

  // Table pagination state
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState<number>(10);

  // Detail drawers and modals
  const [selectedPlantillaId, setSelectedPlantillaId] = useState<string | null>(null);
  const [selectedVacancyId, setSelectedVacancyId] = useState<string | null>(null);
  const [isRequestHeadcountOpen, setIsRequestHeadcountOpen] = useState(false);

  // Workflow modals
  const [relieverTargetEmployee, setRelieverTargetEmployee] = useState<{
    id: string;
    displayName: string;
    employeeNo: string;
    storeId?: string | null;
    storeName?: string | null;
  } | null>(null);

  const [returnToActiveTarget, setReturnToActiveTarget] = useState<{
    employee: {
      id: string;
      displayName: string;
      employeeNo: string;
      storeName?: string | null;
    };
    reliever: {
      id: string;
      name: string;
      employeeNumber: string;
    } | null;
  } | null>(null);

  const [assignStoreTargetEmployee, setAssignStoreTargetEmployee] = useState<{
    id: string;
    displayName: string;
    employeeNo: string;
    positionTitle?: string | null;
  } | null>(null);

  // Search parameters and router
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();

  // Search query specifically for the account selector list
  const [accountSearch, setAccountSearch] = useState("");
  const [selectorGroupId, setSelectorGroupId] = useState("");

  // Directory filter state
  const [search, setSearch] = useState("");
  const [areaCityFilter, setAreaCityFilter] = useState(""); // "" | "area:Name" | "city:Name"
  const [assignmentType, setAssignmentType] = useState(""); // "" | "stationary" | "roving"

  // -------------------------------------------------------------------------
  // User Context and Account Lists
  // -------------------------------------------------------------------------

  const currentUser = useCurrentUser();
  const userRole = currentUser?.roleKey ?? currentUser?.roleName;
  const canRequestAdjustment = isOpsAmendmentRole(userRole);

  // Derive viewMode directly from searchParams
  const viewParam = searchParams.get("view") || searchParams.get("tab");
  const viewMode: PlantillaViewMode =
    viewParam === "moses_pool" || viewParam === "pool" || viewParam === "moses"
      ? "moses_pool"
      : viewParam === "analytics" || viewParam === "workforce_analytics"
      ? "analytics"
      : "store";

  // Check whether user explicitly holds company-wide "All Scope" permissions
  const hasAllScope = useMemo(() => {
    if (!currentUser) return false;
    return (
      currentUser.groupScope.mode === "all" &&
      currentUser.accountScope.mode === "all"
    );
  }, [currentUser]);

  const allowedAccountsQuery = useQuery({
    queryKey: [
      "plantilla",
      "allowed-accounts",
      currentUser?.accountScope,
      currentUser?.groupScope,
      hasAllScope,
    ],
    queryFn: () => fetchPlantillaScopedAccounts(currentUser),
    enabled: !!currentUser,
  });

  // Derive accountId directly from URL or user single scoped account
  const urlAccountId = searchParams.get("accountId") ?? "";
  const singleScopedId = useMemo(() => {
    if (hasAllScope) return "";
    const accounts = allowedAccountsQuery.data ?? [];
    if (accounts.length === 1) {
      return accounts[0].id;
    }
    return "";
  }, [hasAllScope, allowedAccountsQuery.data]);
  const accountId = urlAccountId || singleScopedId;

  // Verify that accountId is authorized for the current user
  const isAccountAuthorized = useMemo(() => {
    if (!accountId) return true;
    if (hasAllScope) return true;
    if (!allowedAccountsQuery.isSuccess) return true;
    return (allowedAccountsQuery.data ?? []).some((a) => a.id === accountId);
  }, [accountId, hasAllScope, allowedAccountsQuery.isSuccess, allowedAccountsQuery.data]);

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
        if (hasAllScope || (currentUser?.groupScope.ids.includes(a.groupId))) {
          map.set(a.groupId, a.groupName);
        }
      }
    }
    return Array.from(map.entries()).map(([id, name]) => ({ id, name }));
  }, [allowedAccountsQuery.data, hasAllScope, currentUser?.groupScope]);

  const effectiveSelectorGroupId =
    selectorGroupId && uniqueGroups.some((g) => g.id === selectorGroupId)
      ? selectorGroupId
      : "";

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
    enabled: !!accountId && isAccountAuthorized,
    staleTime: 30000,
  });

  const storeLookupMap = useMemo(() => {
    const map = new Map<string, { id?: string; city: string | null; province: string | null; code: string | null }>();
    (storesUnderAccountQuery.data ?? []).forEach((s) => {
      const info = { id: s.id, city: s.city, province: s.province, code: s.code };
      map.set(s.name.toLowerCase().trim(), info);
      map.set(s.id, info);
    });
    return map;
  }, [storesUnderAccountQuery.data]);

  // Hierarchical Area -> City options for dropdown
  const hierarchicalAreaOptions = useMemo(() => {
    const stores = storesUnderAccountQuery.data ?? [];
    const areaMap = new Map<string, Set<string>>();

    stores.forEach((s) => {
      const area = (s.province || "Unspecified Area").trim();
      if (!areaMap.has(area)) {
        areaMap.set(area, new Set());
      }
      if (s.city) {
        areaMap.get(area)!.add(s.city.trim());
      }
    });

    const sortedAreas = Array.from(areaMap.keys()).sort();
    return sortedAreas.map((area) => ({
      area,
      cities: Array.from(areaMap.get(area)!).sort(),
    }));
  }, [storesUnderAccountQuery.data]);

  // -------------------------------------------------------------------------
  // Queries (Gated behind accountId)
  // -------------------------------------------------------------------------

  const summaryQuery = useQuery({
    queryKey: ["plantilla", "summary", { search, accountId, effectiveSelectorGroupId }],
    queryFn: () =>
      getPlantillaSummary({
        search: accountId ? (search || undefined) : undefined,
        accountId: accountId || undefined,
        groupId: effectiveSelectorGroupId || undefined,
      }),
    enabled: !!currentUser && !!accountId && isAccountAuthorized,
  });

  // Query for leadership roles: OM, TL, ATL, HRCO
  const teamDirectoryQuery = useQuery({
    queryKey: ["team-directory", "plantilla-account", accountId],
    queryFn: () => fetchTeamDirectory({ accountId }),
    enabled: !!accountId && isAccountAuthorized,
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

  // Query all plantilla employees under current account
  const employeeQuery = useQuery({
    queryKey: ["plantilla", "employees-all", accountId],
    queryFn: () =>
      listWebPlantillaEmployees({
        accountId,
        activeState: "all",
        page: 1,
        pageSize: 500,
      }),
    enabled: !!accountId && isAccountAuthorized,
    staleTime: 30000,
  });

  // Query active temporary coverages (relievers covering on-leave)
  const coverageQuery = useQuery({
    queryKey: ["plantilla", "active-temporary-coverage", accountId],
    queryFn: () => fetchActiveCoverageForAccount(accountId),
    enabled: !!accountId && isAccountAuthorized,
    staleTime: 15000,
  });

  const activeCoverageMap = useMemo(() => {
    const map = new Map<string, ActiveCoverageItem>();
    (coverageQuery.data ?? []).forEach((c) => {
      map.set(c.coveredPlantillaId, c);
    });
    return map;
  }, [coverageQuery.data]);

  // Query for vacancies
  const vacancyListQuery = useQuery({
    queryKey: ["plantilla", "vacancies", accountId],
    queryFn: () =>
      listVacancies({
        accountId: accountId || undefined,
        status: "open",
        page: 1,
        pageSize: 200,
      }),
    enabled: !!accountId && isAccountAuthorized,
    staleTime: 30000,
  });

  // Store staffing query for Store Capacity Table
  const storeStaffingQuery = useQuery({
    queryKey: ["plantilla", "store-staffing-capacity", accountId],
    queryFn: () =>
      listWebPlantillaStoreStaffing({
        accountId,
        page: 1,
        pageSize: 200,
      }),
    enabled: !!accountId && isAccountAuthorized && mainView === "store",
    staleTime: 30000,
  });

  // -------------------------------------------------------------------------
  // Filtering & Partitioning into 5 Status Tabs
  // -------------------------------------------------------------------------

  const allEmployees = useMemo(() => employeeQuery.data?.data ?? [], [employeeQuery.data?.data]);

  // Match search & area/city filter & assignment type
  const filterEmployee = useCallback((emp: PlantillaEmployeeListItem) => {
    if (search.trim()) {
      const q = search.toLowerCase().trim();
      const name = (emp.fullName || `${emp.lastName || ""}, ${emp.firstName || ""}`).toLowerCase();
      const empNo = (emp.employeeNo || "").toLowerCase();
      const storeName = (emp.primaryStoreName || "").toLowerCase();
      const vcode = (emp.vcode || emp.cgCode || "").toLowerCase();
      if (!name.includes(q) && !empNo.includes(q) && !storeName.includes(q) && !vcode.includes(q)) {
        return false;
      }
    }

    if (areaCityFilter) {
      const storeInfo = emp.primaryStoreName
        ? storeLookupMap.get(emp.primaryStoreName.toLowerCase().trim())
        : null;
      if (areaCityFilter.startsWith("area:")) {
        const area = areaCityFilter.replace("area:", "").toLowerCase().trim();
        const storeArea = (storeInfo?.province || "").toLowerCase().trim();
        if (storeArea !== area) return false;
      } else if (areaCityFilter.startsWith("city:")) {
        const city = areaCityFilter.replace("city:", "").toLowerCase().trim();
        const storeCity = (storeInfo?.city || "").toLowerCase().trim();
        if (storeCity !== city) return false;
      }
    }

    if (assignmentType) {
      const isRoving = emp.assignmentType?.toLowerCase() === "roving";
      if (assignmentType === "roving" && !isRoving) return false;
      if (assignmentType === "stationary" && isRoving) return false;
    }

    return true;
  }, [search, areaCityFilter, assignmentType, storeLookupMap]);

  // Helper check for deactivation statuses
  const isDeactivationRecord = (emp: PlantillaEmployeeListItem) => {
    const s = (emp.plantillaStatus || "").toLowerCase();
    const overlay = deriveDeactivationOverlay(emp.plantillaStatus);
    return (
      overlay.isPendingSeparation ||
      overlay.showDeactivatedBanner ||
      s === "pending for deactivation" ||
      s === "pending_for_deactivation" ||
      s === "pending deactivation" ||
      s === "for deactivation" ||
      s === "deactivated" ||
      s === "inactive" ||
      s === "terminated"
    );
  };

  // Helper check for floating status
  const isFloatingRecord = (emp: PlantillaEmployeeListItem) => {
    const s = (emp.plantillaStatus || "").toLowerCase();
    return s === "floating";
  };

  // Helper check for on-leave status
  const isOnLeaveRecord = (emp: PlantillaEmployeeListItem) => {
    const s = (emp.plantillaStatus || "").toLowerCase();
    return s === "on leave" || s === "on_leave";
  };

  // Tab 1: Active
  const activeEmployees = useMemo(() => {
    return allEmployees.filter((emp) => {
      const s = (emp.plantillaStatus || "").toLowerCase();
      return (
        s === "active" &&
        !isDeactivationRecord(emp) &&
        !isFloatingRecord(emp) &&
        !isOnLeaveRecord(emp)
      );
    });
  }, [allEmployees]);

  // Tab 2: On-Leave
  const onLeaveEmployees = useMemo(() => {
    return allEmployees.filter(isOnLeaveRecord);
  }, [allEmployees]);

  // Tab 4: Floating
  const floatingEmployees = useMemo(() => {
    return allEmployees.filter(isFloatingRecord);
  }, [allEmployees]);

  // Tab 5: Deactivation
  const deactivationEmployees = useMemo(() => {
    return allEmployees.filter(isDeactivationRecord);
  }, [allEmployees]);

  // Tab 3: Vacancy Rows
  const allVacancies = useMemo(() => vacancyListQuery.data?.data ?? [], [vacancyListQuery.data?.data]);

  const vacantStoreIds = useMemo(() => {
    const set = new Set<string>();
    allVacancies.forEach((v) => {
      if (v.storeId) set.add(v.storeId);
    });
    return set;
  }, [allVacancies]);

  // Filtered lists for the active status sub-tab
  const filteredActiveEmployees = useMemo(() => activeEmployees.filter(filterEmployee), [activeEmployees, filterEmployee]);
  const filteredOnLeaveEmployees = useMemo(() => onLeaveEmployees.filter(filterEmployee), [onLeaveEmployees, filterEmployee]);
  const filteredFloatingEmployees = useMemo(() => floatingEmployees.filter(filterEmployee), [floatingEmployees, filterEmployee]);
  const filteredDeactivationEmployees = useMemo(() => deactivationEmployees.filter(filterEmployee), [deactivationEmployees, filterEmployee]);

  const filteredVacancies = useMemo(() => {
    return allVacancies.filter((v) => {
      if (search.trim()) {
        const q = search.toLowerCase().trim();
        const store = (v.storeName || "").toLowerCase();
        const pos = (v.position_title || "").toLowerCase();
        const vcode = (v.vcode || v.cgCode || "").toLowerCase();
        if (!store.includes(q) && !pos.includes(q) && !vcode.includes(q)) return false;
      }

      if (areaCityFilter) {
        const storeInfo = v.storeId
          ? storeLookupMap.get(v.storeId)
          : v.storeName
          ? storeLookupMap.get(v.storeName.toLowerCase().trim())
          : null;
        if (areaCityFilter.startsWith("area:")) {
          const area = areaCityFilter.replace("area:", "").toLowerCase().trim();
          const storeArea = (storeInfo?.province || "").toLowerCase().trim();
          if (storeArea !== area) return false;
        } else if (areaCityFilter.startsWith("city:")) {
          const city = areaCityFilter.replace("city:", "").toLowerCase().trim();
          const storeCity = (storeInfo?.city || "").toLowerCase().trim();
          if (storeCity !== city) return false;
        }
      }

      return true;
    });
  }, [allVacancies, search, areaCityFilter, storeLookupMap]);

  // Store Capacity Table Data (for mainView === "store")
  const storeCapacityRows = useMemo(() => {
    const stores = storesUnderAccountQuery.data ?? [];
    const staffingList = storeStaffingQuery.data?.data ?? [];
    const staffingMap = new Map<string, typeof staffingList[0]>();
    staffingList.forEach((s) => {
      staffingMap.set(s.storeId, s);
    });

    // Counts per store from employees
    const storeActiveCountMap = new Map<string, number>();
    const storeOnLeaveCountMap = new Map<string, number>();

    allEmployees.forEach((emp) => {
      const storeKey = emp.primaryStoreName?.toLowerCase().trim();
      const s = (emp.plantillaStatus || "").toLowerCase();
      if (!storeKey) return;

      if (s === "active" && !isDeactivationRecord(emp) && !isFloatingRecord(emp) && !isOnLeaveRecord(emp)) {
        storeActiveCountMap.set(storeKey, (storeActiveCountMap.get(storeKey) ?? 0) + 1);
      } else if (s === "on leave" || s === "on_leave") {
        storeOnLeaveCountMap.set(storeKey, (storeOnLeaveCountMap.get(storeKey) ?? 0) + 1);
      }
    });

    // Count open vacancies per store
    const storeVacancyCountMap = new Map<string, number>();
    allVacancies.forEach((v) => {
      const key = (v.storeName || "").toLowerCase().trim();
      if (key) {
        storeVacancyCountMap.set(key, (storeVacancyCountMap.get(key) ?? 0) + 1);
      }
    });

    return stores.map((st) => {
      const key = st.name.toLowerCase().trim();
      const staffRow = staffingMap.get(st.id);

      const activeDeployed = storeActiveCountMap.get(key) ?? staffRow?.onboardCount ?? 0;
      const onLeave = storeOnLeaveCountMap.get(key) ?? 0;
      const openVacancy = storeVacancyCountMap.get(key) ?? staffRow?.openHeadcount ?? 0;
      const required = staffRow?.requiredHeadcount ?? Math.max(activeDeployed + openVacancy, 1);
      const isFulfilled = activeDeployed >= required && required > 0;

      return {
        id: st.id,
        storeBranch: st.name,
        code: st.code,
        city: st.city,
        province: st.province,
        plantillaRequired: required,
        activeDeployed,
        onLeave,
        openVacancy,
        isFulfilled,
      };
    });
  }, [storesUnderAccountQuery.data, storeStaffingQuery.data?.data, allEmployees, allVacancies]);

  const filteredStoreCapacityRows = useMemo(() => {
    return storeCapacityRows.filter((st) => {
      if (search.trim()) {
        const q = search.toLowerCase().trim();
        const name = st.storeBranch.toLowerCase();
        const code = (st.code || "").toLowerCase();
        const city = (st.city || "").toLowerCase();
        const prov = (st.province || "").toLowerCase();
        if (!name.includes(q) && !code.includes(q) && !city.includes(q) && !prov.includes(q)) {
          return false;
        }
      }

      if (areaCityFilter) {
        if (areaCityFilter.startsWith("area:")) {
          const area = areaCityFilter.replace("area:", "").toLowerCase().trim();
          if ((st.province || "").toLowerCase().trim() !== area) return false;
        } else if (areaCityFilter.startsWith("city:")) {
          const city = areaCityFilter.replace("city:", "").toLowerCase().trim();
          if ((st.city || "").toLowerCase().trim() !== city) return false;
        }
      }

      return true;
    });
  }, [storeCapacityRows, search, areaCityFilter]);

  // Derived counts for KPI cards and badges
  const summaryData = summaryQuery.data;
  const activeCount = activeEmployees.length;
  const onLeaveCount = onLeaveEmployees.length;
  const floatingCount = floatingEmployees.length;
  const deactivationCount = deactivationEmployees.length;
  const vacancyCount = allVacancies.length > 0 ? allVacancies.length : (summaryData?.vacant ?? 0);
  const requiredCount = summaryData?.required && summaryData.required > 0 ? summaryData.required : activeCount + vacancyCount;
  const fulfillmentRate =
    requiredCount > 0 ? Math.round((activeCount / requiredCount) * 100) : 0;

  // Active view pagination
  const currentTabRows =
    statusTab === "active"
      ? filteredActiveEmployees
      : statusTab === "on_leave"
      ? filteredOnLeaveEmployees
      : statusTab === "vacancy"
      ? filteredVacancies
      : statusTab === "floating"
      ? filteredFloatingEmployees
      : filteredDeactivationEmployees;

  const currentTotalCount =
    mainView === "store" ? filteredStoreCapacityRows.length : currentTabRows.length;

  const paginatedRows = useMemo(() => {
    const start = (page - 1) * pageSize;
    return currentTabRows.slice(start, start + pageSize);
  }, [currentTabRows, page, pageSize]);

  const paginatedStoreRows = useMemo(() => {
    const start = (page - 1) * pageSize;
    return filteredStoreCapacityRows.slice(start, start + pageSize);
  }, [filteredStoreCapacityRows, page, pageSize]);

  const hasActiveFilters = Boolean(search.trim() || areaCityFilter || assignmentType);

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
    setAreaCityFilter("");
    setAssignmentType("");
    setStatusTab("active");
    setPage(1);

    const params = new URLSearchParams(searchParams.toString());
    params.set("accountId", accId);
    params.delete("view");
    router.push(`${pathname}?${params.toString()}`);
  }

  function handleBackToSelection() {
    setSearch("");
    setAreaCityFilter("");
    setAssignmentType("");
    setStatusTab("active");
    setPage(1);

    const params = new URLSearchParams(searchParams.toString());
    params.delete("accountId");
    router.push(`${pathname}?${params.toString()}`);
  }

  function handleResetFilters() {
    setSearch("");
    setAreaCityFilter("");
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
      const matchesGroup = !effectiveSelectorGroupId || a.groupId === effectiveSelectorGroupId;
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
              value={effectiveSelectorGroupId}
              onChange={(e) => setSelectorGroupId(e.target.value)}
              className="h-10 rounded-lg border border-border-default bg-surface-base px-3 text-sm text-text-primary outline-none focus:border-brand-500 transition-colors"
              aria-label="Filter accounts by group"
            >
              <option value="">{hasAllScope ? "All Groups" : "All Assigned Groups"}</option>
              {uniqueGroups.map((g) => (
                <option key={g.id} value={g.id}>
                  {g.name}
                </option>
              ))}
            </select>
          )}
          {(accountSearch || effectiveSelectorGroupId) && (
            <button
              type="button"
              onClick={() => {
                setAccountSearch("");
                setSelectorGroupId("");
              }}
              className="text-sm font-semibold text-brand-600 hover:text-brand-700 px-2 cursor-pointer"
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
                  const isAMoses = a.name.trim().toLowerCase() === "moses hq";
                  const isBMoses = b.name.trim().toLowerCase() === "moses hq";
                  if (isAMoses && !isBMoses) return -1;
                  if (!isAMoses && isBMoses) return 1;

                  const isAFillRateZero = a.fillRate === 0;
                  const isBFillRateZero = b.fillRate === 0;
                  if (isAFillRateZero && !isBFillRateZero) return 1;
                  if (!isAFillRateZero && isBFillRateZero) return -1;

                  if (a.fillRate !== b.fillRate) {
                    return a.fillRate - b.fillRate;
                  }
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
                    className="group relative flex w-full items-start gap-4 rounded-xl border border-border-default bg-surface-base p-5 text-left transition-all duration-300 hover:-translate-y-0.5 hover:border-brand-primary hover:shadow-md focus:outline-none focus:ring-2 focus:ring-brand-primary focus:ring-offset-2 cursor-pointer"
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
    hasAllScope || (allowedAccountsQuery.data && allowedAccountsQuery.data.length > 1);

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
    <div className="flex min-h-0 flex-col gap-2 text-text-primary lg:h-[calc(100vh-5.5rem)] lg:overflow-hidden">
      {!accountId ? (
        <div className="flex flex-col gap-5 overflow-y-auto">
          <AdminPageHeader
            categoryTag="Admin panel"
            moduleName="Plantilla"
            title="Plantilla Directory"
            subtitle="Select a billing account to audit roster allocations, capacity targets, and staffing governance."
            icon={Building2}
          />
          {renderAccountSelectionContent()}
        </div>
      ) : !isAccountAuthorized ? (
        <div className="flex flex-col items-center justify-center gap-4 p-8">
          <DataState
            kind="access_denied"
            title="Access Denied"
            description="You do not have permission to access this account or its plantilla records."
          />
          {showBackToSelection && (
            <button
              type="button"
              onClick={handleBackToSelection}
              className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-primary hover:bg-surface-hover transition cursor-pointer"
            >
              <ArrowLeft className="h-3.5 w-3.5" />
              <span>Return to Accounts</span>
            </button>
          )}
        </div>
      ) : (
        <>
          {/* 1. Header & Context Action Bar (Enterprise Web Header) */}
          <div className="shrink-0">
            <AdminPageHeader
              categoryTag="Admin panel"
              moduleName="Plantilla"
              title={
                <nav className="flex items-center gap-1.5 text-xs" aria-label="Breadcrumb">
                  {showBackToSelection ? (
                    <button
                      type="button"
                      onClick={handleBackToSelection}
                      className="inline-flex items-center gap-1 font-medium text-text-secondary hover:text-brand-600 transition-colors cursor-pointer"
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
                  {/* Main View Segmented Toggle: [ 👥 Employee View | 🏬 Store View ] */}
                  <div className="flex h-8 items-center rounded-lg border border-border-default bg-surface-muted p-0.5 shadow-2xs">
                    <button
                      type="button"
                      onClick={() => {
                        setMainView("employee");
                        setPage(1);
                      }}
                      className={`inline-flex h-full items-center gap-1.5 rounded-md px-2.5 text-xs font-semibold transition-colors cursor-pointer ${
                        mainView === "employee"
                          ? "bg-surface-base text-text-primary shadow-xs"
                          : "text-text-muted hover:text-text-primary"
                      }`}
                    >
                      <Users className="h-3.5 w-3.5" />
                      <span>👥 Employee View</span>
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setMainView("store");
                        setPage(1);
                      }}
                      className={`inline-flex h-full items-center gap-1.5 rounded-md px-2.5 text-xs font-semibold transition-colors cursor-pointer ${
                        mainView === "store"
                          ? "bg-surface-base text-text-primary shadow-xs"
                          : "text-text-muted hover:text-text-primary"
                      }`}
                    >
                      <Building2 className="h-3.5 w-3.5" />
                      <span>🏬 Store View</span>
                    </button>
                  </div>

                  {/* Primary button: + Request Headcount */}
                  {canRequestAdjustment && (
                    <button
                      type="button"
                      onClick={() => setIsRequestHeadcountOpen(true)}
                      className="inline-flex h-8 items-center gap-1.5 rounded-lg bg-brand-600 px-3 py-1.5 text-xs font-semibold text-white shadow-2xs hover:bg-brand-700 transition cursor-pointer focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
                    >
                      <Plus className="w-3.5 h-3.5 shrink-0" />
                      <span>Request Headcount</span>
                    </button>
                  )}
                </div>
              }
            />
          </div>

          {/* 2. Top 5 KPI & Leadership Cards (grid-cols-5, Centered Content) */}
          <section aria-label="Plantilla summary metrics" className="shrink-0">
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3">
              {/* Card 1: Overall MFR (CENCOM Donut Style) */}
              <div className="rounded-xl border border-slate-200 dark:border-border-default bg-surface-base px-3 py-2 flex flex-col items-center justify-center text-center shadow-xs">
                <div className="text-[11px] font-semibold text-text-muted uppercase tracking-wider">
                  Overall MFR
                </div>
                <OverallMfrDonut percent={fulfillmentRate} size={68} strokeWidth={7} />
                <div className="text-[11px] font-medium text-text-secondary mt-0.5">
                  {activeCount} active / {requiredCount} required
                </div>
              </div>

              {/* Card 2: Active Deployed */}
              <div className="rounded-xl border border-slate-200 dark:border-border-default bg-surface-base px-3 py-2 flex flex-col items-center justify-between text-center shadow-xs">
                <div className="text-[11px] font-semibold text-text-muted uppercase tracking-wider">
                  Active Deployed
                </div>
                <div className="text-2xl font-bold font-mono text-text-primary my-0.5">
                  {activeCount}
                </div>
                <div className="text-[11px] text-text-muted leading-tight">
                  Active deployed personnel
                </div>
              </div>

              {/* Card 3: Open Vacancies */}
              <div className="rounded-xl border border-slate-200 dark:border-border-default bg-surface-base px-3 py-2 flex flex-col items-center justify-between text-center shadow-xs">
                <div className="text-[11px] font-semibold text-text-muted uppercase tracking-wider">
                  Open Vacancies
                </div>
                <div className="text-2xl font-bold font-mono text-text-primary my-0.5">
                  {vacancyCount}
                </div>
                <div className="text-[11px] text-text-muted leading-tight">
                  Approved open vacancy slots
                </div>
              </div>

              {/* Card 4: HR Pipeline */}
              <div className="rounded-xl border border-slate-200 dark:border-border-default bg-surface-base px-3 py-2 flex flex-col items-center justify-between text-center shadow-xs">
                <div className="text-[11px] font-semibold text-text-muted uppercase tracking-wider">
                  HR Pipeline
                </div>
                <div className="text-2xl font-bold font-mono text-text-primary my-0.5">
                  {summaryData?.hrProcess ?? 0}
                </div>
                <div className="text-[11px] text-text-muted leading-tight">
                  Candidate onboarding pipeline
                </div>
              </div>

              {/* Card 5: Leadership Team (Simple Card, Conditional Row Rendering) */}
              <div className="rounded-xl border border-slate-200 dark:border-border-default bg-surface-base px-3 py-2 flex flex-col items-center justify-between text-center shadow-xs w-full">
                <div className="text-[11px] font-semibold text-text-muted uppercase tracking-wider">
                  Leadership Team
                </div>
                <div className="w-full space-y-0.5 text-xs text-left my-auto px-1">
                  <div className="flex items-center justify-between gap-1">
                    <span className="text-text-muted font-medium shrink-0">OM:</span>
                    <span className="font-semibold text-text-primary truncate" title={leadershipTeam.om}>
                      {leadershipTeam.om}
                    </span>
                  </div>
                  {leadershipTeam.tl && leadershipTeam.tl !== "—" && leadershipTeam.tl.trim() !== "" && (
                    <div className="flex items-center justify-between gap-1">
                      <span className="text-text-muted font-medium shrink-0">TL:</span>
                      <span className="font-semibold text-text-primary truncate" title={leadershipTeam.tl}>
                        {leadershipTeam.tl}
                      </span>
                    </div>
                  )}
                  {leadershipTeam.atl && leadershipTeam.atl !== "—" && leadershipTeam.atl.trim() !== "" && (
                    <div className="flex items-center justify-between gap-1">
                      <span className="text-text-muted font-medium shrink-0">ATL:</span>
                      <span className="font-semibold text-text-primary truncate" title={leadershipTeam.atl}>
                        {leadershipTeam.atl}
                      </span>
                    </div>
                  )}
                  <div className="flex items-center justify-between gap-1">
                    <span className="text-text-muted font-medium shrink-0">HRCO:</span>
                    <span className="font-semibold text-text-primary truncate" title={leadershipTeam.hrco}>
                      {leadershipTeam.hrco}
                    </span>
                  </div>
                </div>
                <div className="text-[10px] text-text-muted leading-tight">Assigned Account Leadership</div>
              </div>
            </div>
          </section>

          {/* 3. Search & Hierarchical Area -> City Filter Bar */}
          <div className="flex flex-1 min-h-0 flex-col gap-2">
            {/* Employee View Sub-Tabs (Hidden when mainView === "store") */}
            {mainView === "employee" && (
              <div className="flex flex-wrap items-center justify-between gap-2 border-b border-border-subtle pb-2 shrink-0">
                <div
                  role="tablist"
                  aria-label="Plantilla Directory Tabs"
                  className="flex items-center gap-1.5 overflow-x-auto no-scrollbar scrollbar-none"
                >
                  {/* Tab 1: Active */}
                  <button
                    type="button"
                    role="tab"
                    aria-selected={statusTab === "active"}
                    onClick={() => {
                      setStatusTab("active");
                      setPage(1);
                    }}
                    className={`group inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border px-3 py-1 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                      statusTab === "active"
                        ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                        : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
                    }`}
                  >
                    <Users className="w-3.5 h-3.5 shrink-0" />
                    <span>Active</span>
                    <span
                      className={`ml-1 shrink-0 rounded-full px-1.5 py-0.2 font-sans tabular-nums text-[11px] font-semibold shadow-2xs transition-colors ${
                        statusTab === "active"
                          ? "bg-brand-button text-white"
                          : "bg-surface-muted text-text-secondary border border-border-default"
                      }`}
                    >
                      {activeCount}
                    </span>
                  </button>

                  {/* Tab 2: On-Leave */}
                  <button
                    type="button"
                    role="tab"
                    aria-selected={statusTab === "on_leave"}
                    onClick={() => {
                      setStatusTab("on_leave");
                      setPage(1);
                    }}
                    className={`group inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border px-3 py-1 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                      statusTab === "on_leave"
                        ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                        : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
                    }`}
                  >
                    <UserMinus className="w-3.5 h-3.5 shrink-0" />
                    <span>On-Leave</span>
                    <span
                      className={`ml-1 shrink-0 rounded-full px-1.5 py-0.2 font-sans tabular-nums text-[11px] font-semibold shadow-2xs transition-colors ${
                        statusTab === "on_leave"
                          ? "bg-brand-button text-white"
                          : "bg-surface-muted text-text-secondary border border-border-default"
                      }`}
                    >
                      {onLeaveCount}
                    </span>
                  </button>

                  {/* Tab 3: Vacancy */}
                  <button
                    type="button"
                    role="tab"
                    aria-selected={statusTab === "vacancy"}
                    onClick={() => {
                      setStatusTab("vacancy");
                      setPage(1);
                    }}
                    className={`group inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border px-3 py-1 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                      statusTab === "vacancy"
                        ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                        : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
                    }`}
                  >
                    <Briefcase className="w-3.5 h-3.5 shrink-0" />
                    <span>Vacancy</span>
                    <span
                      className={`ml-1 shrink-0 rounded-full px-1.5 py-0.2 font-sans tabular-nums text-[11px] font-semibold shadow-2xs transition-colors ${
                        statusTab === "vacancy"
                          ? "bg-brand-button text-white"
                          : "bg-surface-muted text-text-secondary border border-border-default"
                      }`}
                    >
                      {vacancyCount}
                    </span>
                  </button>

                  {/* Tab 4: Floating */}
                  <button
                    type="button"
                    role="tab"
                    aria-selected={statusTab === "floating"}
                    onClick={() => {
                      setStatusTab("floating");
                      setPage(1);
                    }}
                    className={`group inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border px-3 py-1 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                      statusTab === "floating"
                        ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                        : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
                    }`}
                  >
                    <Share2 className="w-3.5 h-3.5 shrink-0" />
                    <span>Floating</span>
                    <span
                      className={`ml-1 shrink-0 rounded-full px-1.5 py-0.2 font-sans tabular-nums text-[11px] font-semibold shadow-2xs transition-colors ${
                        statusTab === "floating"
                          ? "bg-brand-button text-white"
                          : "bg-surface-muted text-text-secondary border border-border-default"
                      }`}
                    >
                      {floatingCount}
                    </span>
                  </button>

                  {/* Tab 5: Deactivation */}
                  <button
                    type="button"
                    role="tab"
                    aria-selected={statusTab === "deactivation"}
                    onClick={() => {
                      setStatusTab("deactivation");
                      setPage(1);
                    }}
                    className={`group inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border px-3 py-1 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                      statusTab === "deactivation"
                        ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                        : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
                    }`}
                  >
                    <AlertCircle className="w-3.5 h-3.5 shrink-0" />
                    <span>Deactivation</span>
                    <span
                      className={`ml-1 shrink-0 rounded-full px-1.5 py-0.2 font-sans tabular-nums text-[11px] font-semibold shadow-2xs transition-colors ${
                        statusTab === "deactivation"
                          ? "bg-brand-button text-white"
                          : "bg-surface-muted text-text-secondary border border-border-default"
                      }`}
                    >
                      {deactivationCount}
                    </span>
                  </button>
                </div>

                {/* View switch: Table vs Cards (Employee view) */}
                <div className="flex h-8 items-center rounded-lg border border-border-default bg-surface-muted p-0.5">
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
            )}

            {/* Unified Web Search & Filter Toolbar */}
            <div className="flex flex-col lg:flex-row items-stretch lg:items-center gap-2 rounded-xl border border-border-default bg-surface-base px-3 py-2 shadow-xs shrink-0">
              <div className="relative flex-1 min-w-[200px]">
                <Search className="pointer-events-none absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-text-muted" />
                <input
                  type="text"
                  placeholder="Search employee, emploc no, name, store..."
                  value={search}
                  onChange={(e) => {
                    setSearch(e.target.value);
                    setPage(1);
                  }}
                  className="h-8.5 w-full rounded-lg border border-border-default bg-surface-muted pl-8 pr-8 text-xs text-text-primary outline-none transition-colors focus:border-brand-500 focus:bg-surface-base"
                  aria-label="Search plantilla roster"
                />
                {search && (
                  <button
                    type="button"
                    onClick={() => {
                      setSearch("");
                      setPage(1);
                    }}
                    className="absolute right-2.5 top-1/2 -translate-y-1/2 rounded-full p-1 text-text-muted hover:text-text-primary hover:bg-surface-hover transition-colors cursor-pointer"
                    aria-label="Clear search"
                  >
                    <X className="h-3 w-3" />
                  </button>
                )}
              </div>

              {/* Hierarchical Area -> City Dropdown */}
              <div className="flex flex-wrap items-center gap-2">
                <div className="min-w-[190px] flex-1 sm:flex-initial">
                  <select
                    value={areaCityFilter}
                    onChange={(e) => {
                      setAreaCityFilter(e.target.value);
                      setPage(1);
                    }}
                    className="h-8.5 w-full rounded-lg border border-border-default bg-surface-base px-2.5 text-xs text-text-primary outline-none transition-colors focus:border-brand-500 cursor-pointer"
                    aria-label="Filter by store area or city"
                  >
                    <option value="">All Stores (All Areas & Cities)</option>
                    {hierarchicalAreaOptions.map(({ area, cities }) => (
                      <optgroup key={area} label={area}>
                        <option value={`area:${area}`}>All {area} Stores</option>
                        {cities.map((city) => (
                          <option key={`${area}:${city}`} value={`city:${city}`}>
                            {city}, {area}
                          </option>
                        ))}
                      </optgroup>
                    ))}
                  </select>
                </div>

                {/* Assignment Type Dropdown (Stationary / Roving) */}
                <div className="min-w-[115px] flex-1 sm:flex-initial">
                  <select
                    value={assignmentType}
                    onChange={(e) => {
                      setAssignmentType(e.target.value);
                      setPage(1);
                    }}
                    className="h-8.5 w-full rounded-lg border border-border-default bg-surface-base px-2.5 text-xs text-text-primary outline-none transition-colors focus:border-brand-500 cursor-pointer"
                    aria-label="Filter by assignment type"
                  >
                    <option value="">All Types</option>
                    <option value="stationary">Stationary</option>
                    <option value="roving">Roving</option>
                  </select>
                </div>

                {hasActiveFilters && (
                  <button
                    type="button"
                    onClick={handleResetFilters}
                    className="inline-flex h-8.5 items-center gap-1 rounded-lg border border-border-default bg-surface-muted px-2.5 text-xs font-semibold text-text-primary hover:bg-surface-hover transition-colors shadow-2xs cursor-pointer"
                  >
                    <RotateCcw className="h-3 w-3" />
                    <span>Reset</span>
                  </button>
                )}
              </div>
            </div>

            {/* 4. Main Data Area: Employee 5 Tabs View OR Store Capacity Table */}
            <div className="flex-1 min-h-0 flex flex-col">
            {employeeQuery.isLoading ? (
              <div className="rounded-xl border border-border-default bg-surface-base p-8">
                <DataState
                  kind="loading"
                  title="Loading plantilla records"
                  description="Fetching roster personnel through Supabase RPCs..."
                />
              </div>
            ) : employeeQuery.isError ? (
              <div className="rounded-xl border border-border-default bg-surface-base p-8">
                <DataState
                  kind="error"
                  title="Fetch Failed"
                  description={employeeQuery.error instanceof Error ? employeeQuery.error.message : "The plantilla query failed."}
                  onRetry={() => employeeQuery.refetch()}
                />
              </div>
            ) : mainView === "store" ? (
              /* Store View: Store Capacity Table */
              filteredStoreCapacityRows.length === 0 ? (
                <EmptyTabState
                  hasActiveFilters={hasActiveFilters}
                  onResetFilters={handleResetFilters}
                  tabLabel="stores"
                />
              ) : (
                <StoreCapacityTable
                  rows={paginatedStoreRows}
                />
              )
            ) : statusTab === "active" ? (
              /* Tab 1: Active */
              filteredActiveEmployees.length === 0 ? (
                <EmptyTabState
                  hasActiveFilters={hasActiveFilters}
                  onResetFilters={handleResetFilters}
                  tabLabel="active employees"
                />
              ) : displayView === "table" ? (
                <EmployeeActiveTable
                  rows={paginatedRows as PlantillaEmployeeListItem[]}
                  onRowClick={setSelectedPlantillaId}
                  storeLookupMap={storeLookupMap}
                />
              ) : (
                <div className="flex-1 min-h-0 overflow-y-auto pr-1">
                  <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
                    {(paginatedRows as PlantillaEmployeeListItem[]).map((row) => (
                      <EmployeeCard
                        key={row.id}
                        row={row}
                        onSelect={() => setSelectedPlantillaId(row.id)}
                        storeLookupMap={storeLookupMap}
                      />
                    ))}
                  </div>
                </div>
              )
            ) : statusTab === "on_leave" ? (
              /* Tab 2: On-Leave */
              filteredOnLeaveEmployees.length === 0 ? (
                <EmptyTabState
                  hasActiveFilters={hasActiveFilters}
                  onResetFilters={handleResetFilters}
                  tabLabel="on-leave employees"
                />
              ) : (
                <EmployeeOnLeaveTable
                  rows={paginatedRows as PlantillaEmployeeListItem[]}
                  activeCoverageMap={activeCoverageMap}
                  onRowClick={setSelectedPlantillaId}
                  storeLookupMap={storeLookupMap}
                  onAssignReliever={(emp) => {
                    const storeInfo = emp.primaryStoreName ? storeLookupMap.get(emp.primaryStoreName.toLowerCase().trim()) : null;
                    setRelieverTargetEmployee({
                      id: emp.id,
                      displayName: formatPersonName(emp.firstName, emp.lastName, null, emp.fullName) || emp.employeeNo,
                      employeeNo: emp.employeeNo,
                      storeId: storeInfo?.id ?? null,
                      storeName: emp.primaryStoreName,
                    });
                  }}
                  onReturnToActive={(emp, reliever) => {
                    setReturnToActiveTarget({
                      employee: {
                        id: emp.id,
                        displayName: formatPersonName(emp.firstName, emp.lastName, null, emp.fullName) || emp.employeeNo,
                        employeeNo: emp.employeeNo,
                        storeName: emp.primaryStoreName,
                      },
                      reliever: reliever
                        ? {
                            id: reliever.employeeId,
                            name: reliever.employeeName,
                            employeeNumber: reliever.employeeNumber,
                          }
                        : null,
                    });
                  }}
                />
              )
            ) : statusTab === "vacancy" ? (
              /* Tab 3: Vacancy */
              filteredVacancies.length === 0 ? (
                <EmptyTabState
                  hasActiveFilters={hasActiveFilters}
                  onResetFilters={handleResetFilters}
                  tabLabel="vacant stores"
                />
              ) : (
                <StoreVacancyTable
                  rows={paginatedRows as VacancyListItem[]}
                  onSelectVacancy={(v) => setSelectedVacancyId(v.id)}
                />
              )
            ) : statusTab === "floating" ? (
              /* Tab 4: Floating */
              filteredFloatingEmployees.length === 0 ? (
                <EmptyTabState
                  hasActiveFilters={hasActiveFilters}
                  onResetFilters={handleResetFilters}
                  tabLabel="floating employees"
                />
              ) : (
                <EmployeeFloatingTable
                  rows={paginatedRows as PlantillaEmployeeListItem[]}
                  onRowClick={setSelectedPlantillaId}
                  storeLookupMap={storeLookupMap}
                  onAssignStore={(emp) => {
                    setAssignStoreTargetEmployee({
                      id: emp.id,
                      displayName: formatPersonName(emp.firstName, emp.lastName, null, emp.fullName) || emp.employeeNo,
                      employeeNo: emp.employeeNo,
                      positionTitle: emp.positionTitle,
                    });
                  }}
                />
              )
            ) : (
              /* Tab 5: Deactivation */
              filteredDeactivationEmployees.length === 0 ? (
                <EmptyTabState
                  hasActiveFilters={hasActiveFilters}
                  onResetFilters={handleResetFilters}
                  tabLabel="pending or deactivated personnel"
                />
              ) : (
                <EmployeeDeactivationTable
                  rows={paginatedRows as PlantillaEmployeeListItem[]}
                  onRowClick={setSelectedPlantillaId}
                  storeLookupMap={storeLookupMap}
                />
              )
            )}
            </div>

            {/* Pagination Controls */}
            {currentTotalCount > 0 && (
              <TablePagination
                page={page}
                pageSize={pageSize}
                totalCount={currentTotalCount}
                pageSizeOptions={[10, 25, 50]}
                onPageChange={(p) => setPage(p)}
                onPageSizeChange={(newPageSize) => {
                  setPageSize(newPageSize);
                  setPage(1);
                }}
                isLoading={employeeQuery.isLoading}
                className="mt-2 pt-2 border-t border-border-default px-0 shrink-0"
              />
            )}
          </div>

          {/* Drawers & Modals */}
          <PlantillaDetailDrawer
            plantillaId={selectedPlantillaId}
            onClose={() => setSelectedPlantillaId(null)}
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
                vacancyListQuery.refetch();
              }}
            />
          )}

          {/* Assign Reliever Modal (from On-Leave Tab) */}
          {relieverTargetEmployee && (
            <AssignRelieverModal
              isOpen={Boolean(relieverTargetEmployee)}
              onClose={() => setRelieverTargetEmployee(null)}
              employee={relieverTargetEmployee}
              accountId={accountId}
              onSuccess={() => {
                employeeQuery.refetch();
                coverageQuery.refetch();
                summaryQuery.refetch();
              }}
            />
          )}

          {/* Return to Active Modal (from On-Leave Tab) */}
          {returnToActiveTarget && (
            <ReturnToActiveModal
              isOpen={Boolean(returnToActiveTarget)}
              onClose={() => setReturnToActiveTarget(null)}
              employee={returnToActiveTarget.employee}
              assignedReliever={returnToActiveTarget.reliever}
              onSuccess={() => {
                employeeQuery.refetch();
                coverageQuery.refetch();
                summaryQuery.refetch();
              }}
            />
          )}

          {/* Assign Store Modal (from Floating Tab) */}
          {assignStoreTargetEmployee && (
            <AssignStoreModal
              isOpen={Boolean(assignStoreTargetEmployee)}
              onClose={() => setAssignStoreTargetEmployee(null)}
              employee={assignStoreTargetEmployee}
              stores={storesUnderAccountQuery.data ?? []}
              vacantStoreIds={vacantStoreIds}
              onSuccess={() => {
                employeeQuery.refetch();
                summaryQuery.refetch();
                vacancyListQuery.refetch();
              }}
            />
          )}
        </>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tab 1: Active Employees Table
// ---------------------------------------------------------------------------

function EmployeeActiveTable({
  rows,
  onRowClick,
  storeLookupMap,
}: {
  rows: PlantillaEmployeeListItem[];
  onRowClick: (id: string) => void;
  storeLookupMap: Map<string, { city: string | null; province: string | null; code: string | null }>;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs flex-1 min-h-0 flex flex-col">
      <div className="overflow-auto flex-1 min-h-0">
        <table className="w-full min-w-[980px] text-left text-xs">
          <thead className="sticky top-0 z-10 bg-table-header shadow-2xs">
            <tr className="border-b border-table-rule">
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Member
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Store
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Position
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Assignment
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Status
              </th>
              <th className="px-3.5 py-2 text-right text-xs font-semibold text-text-secondary whitespace-nowrap">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-table-rule">
            {rows.map((row) => {
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
                  className="transition-colors hover:bg-table-row-hover cursor-pointer"
                  onClick={() => onRowClick(row.id)}
                  tabIndex={0}
                  role="button"
                  aria-label={`View details for ${displayName}`}
                >
                  <td className="px-3.5 py-2">
                    <div className="flex items-center gap-2.5">
                      <div className="h-7.5 w-7.5 rounded-full bg-surface-muted border border-border-default text-brand-primary font-bold text-[11px] flex items-center justify-center shrink-0 shadow-xs">
                        {initials}
                      </div>
                      <div className="min-w-0">
                        <span className="font-semibold text-table-text text-xs hover:text-brand-primary transition-colors">
                          {displayName}
                        </span>
                        <div className="font-mono text-[11px] text-table-text-muted mt-0.5">
                          {row.cgCode || row.vcode ? `${row.cgCode || row.vcode} • ${row.employeeNo}` : row.employeeNo}
                        </div>
                      </div>
                    </div>
                  </td>

                  <td className="px-3.5 py-2 text-table-text">
                    <div className="min-w-0">
                      <div className="font-medium text-table-text text-xs">
                        {formatStoreName(row.primaryStoreName || row.vcode || "—")}
                      </div>
                      {locationLabel && (
                        <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-1.5 py-0.2 text-[10px] font-medium text-text-secondary border border-border-subtle mt-0.5">
                          <MapPin className="h-2.5 w-2.5 text-text-muted shrink-0" />
                          <span className="truncate max-w-[150px]">{locationLabel}</span>
                        </span>
                      )}
                    </div>
                  </td>

                  <td className="px-3.5 py-2">
                    <div className="flex flex-col">
                      <span className="font-medium text-table-text text-xs">
                        {row.positionTitle ? formatPosition(row.positionTitle) : "General Staff"}
                      </span>
                      <span className="text-[11px] text-table-text-muted mt-0.5">
                        {row.plantillaType ? `${row.plantillaType} Position` : "Standard Tier"}
                      </span>
                    </div>
                  </td>

                  <td className="px-3.5 py-2">
                    <span className="inline-flex items-center gap-1 rounded-md bg-surface-muted border border-border-default px-1.5 py-0.5 text-xs font-semibold text-text-secondary">
                      {row.assignmentType?.toLowerCase() === "roving" ? "Roving" : "Stationary"}
                    </span>
                  </td>

                  <td className="px-3.5 py-2">
                    <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold bg-emerald-100 text-emerald-800 border border-emerald-300 dark:bg-emerald-950 dark:text-emerald-200 dark:border-emerald-800">
                      Active
                    </span>
                  </td>

                  <td className="px-3.5 py-2 text-right">
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        onRowClick(row.id);
                      }}
                      className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-base px-2.5 py-1 text-xs font-semibold text-text-secondary hover:text-brand-primary hover:border-border-strong hover:bg-surface-hover transition-colors shadow-2xs cursor-pointer"
                      aria-label={`View details for ${displayName}`}
                    >
                      <Eye className="h-3 w-3" />
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
// Tab 2: On-Leave Employees Table (Leave Details & Reliever Flows)
// ---------------------------------------------------------------------------

function EmployeeOnLeaveTable({
  rows,
  activeCoverageMap,
  onRowClick,
  storeLookupMap,
  onAssignReliever,
  onReturnToActive,
}: {
  rows: PlantillaEmployeeListItem[];
  activeCoverageMap: Map<string, ActiveCoverageItem>;
  onRowClick: (id: string) => void;
  storeLookupMap: Map<string, { city: string | null; province: string | null; code: string | null }>;
  onAssignReliever: (emp: PlantillaEmployeeListItem) => void;
  onReturnToActive: (emp: PlantillaEmployeeListItem, reliever: ActiveCoverageItem | null) => void;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs flex-1 min-h-0 flex flex-col">
      <div className="overflow-auto flex-1 min-h-0">
        <table className="w-full min-w-[1020px] text-left text-xs">
          <thead className="sticky top-0 z-10 bg-table-header shadow-2xs">
            <tr className="border-b border-table-rule">
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Member
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Store
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Position
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Leave Details
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Reliever (Moses HQ)
              </th>
              <th className="px-3.5 py-2 text-right text-xs font-semibold text-text-secondary whitespace-nowrap">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-table-rule">
            {rows.map((row) => {
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
              const assignedReliever = activeCoverageMap.get(row.id) ?? null;

              return (
                <tr
                  key={row.id}
                  className="transition-colors hover:bg-table-row-hover cursor-pointer"
                  onClick={() => onRowClick(row.id)}
                  tabIndex={0}
                  role="button"
                  aria-label={`View on-leave record for ${displayName}`}
                >
                  {/* 1. Member */}
                  <td className="px-3.5 py-2">
                    <div className="flex items-center gap-2.5">
                      <div className="h-7.5 w-7.5 rounded-full bg-amber-50 border border-amber-200 text-amber-700 font-bold text-[11px] flex items-center justify-center shrink-0 shadow-xs dark:bg-amber-950/40 dark:border-amber-800 dark:text-amber-300">
                        {initials}
                      </div>
                      <div className="min-w-0">
                        <span className="font-semibold text-table-text text-xs hover:text-brand-primary transition-colors">
                          {displayName}
                        </span>
                        <div className="font-mono text-[11px] text-table-text-muted mt-0.5">
                          {row.cgCode || row.vcode ? `${row.cgCode || row.vcode} • ${row.employeeNo}` : row.employeeNo}
                        </div>
                      </div>
                    </div>
                  </td>

                  {/* 2. Store */}
                  <td className="px-3.5 py-2 text-table-text">
                    <div className="min-w-0">
                      <div className="font-medium text-table-text text-xs">
                        {formatStoreName(row.primaryStoreName || row.vcode || "—")}
                      </div>
                      {locationLabel && (
                        <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-1.5 py-0.2 text-[10px] font-medium text-text-secondary border border-border-subtle mt-0.5">
                          <MapPin className="h-2.5 w-2.5 text-text-muted shrink-0" />
                          <span className="truncate max-w-[150px]">{locationLabel}</span>
                        </span>
                      )}
                    </div>
                  </td>

                  {/* 3. Position */}
                  <td className="px-3.5 py-2">
                    <div className="flex flex-col">
                      <span className="font-medium text-table-text text-xs">
                        {row.positionTitle ? formatPosition(row.positionTitle) : "General Staff"}
                      </span>
                      <span className="text-[11px] text-table-text-muted mt-0.5">
                        {row.plantillaType ? `${row.plantillaType} Position` : "Standard Tier"}
                      </span>
                    </div>
                  </td>

                  {/* 4. Leave Details */}
                  <td className="px-3.5 py-2">
                    <div className="flex flex-col">
                      <span className="inline-flex items-center px-1.5 py-0.2 rounded text-[11px] font-semibold bg-amber-100 text-amber-800 border border-amber-300 dark:bg-amber-950 dark:text-amber-200 dark:border-amber-800 w-fit">
                        On-Leave
                      </span>
                      <span className="text-[10px] text-table-text-muted mt-0.5">
                        Active Leave Coverage
                      </span>
                    </div>
                  </td>

                  {/* 5. Reliever (Moses HQ) */}
                  <td className="px-3.5 py-2">
                    {assignedReliever ? (
                      <div className="flex flex-col">
                        <span className="font-semibold text-emerald-700 dark:text-emerald-300 text-xs flex items-center gap-1">
                          <UserCheck className="h-3 w-3" />
                          {assignedReliever.employeeName}
                        </span>
                        <span className="font-mono text-[10px] text-text-muted">
                          {assignedReliever.employeeNumber}
                        </span>
                      </div>
                    ) : (
                      <div className="flex items-center gap-1.5">
                        <span className="italic text-text-muted text-xs">Unassigned</span>
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            onAssignReliever(row);
                          }}
                          className="inline-flex items-center gap-1 rounded border border-brand-200 bg-brand-50 px-1.5 py-0.5 text-xs font-semibold text-brand-700 hover:bg-brand-100 transition shadow-2xs cursor-pointer dark:bg-brand-950 dark:border-brand-800 dark:text-brand-300"
                        >
                          <Plus className="h-2.5 w-2.5" />
                          <span>+ Assign Reliever</span>
                        </button>
                      </div>
                    )}
                  </td>

                  {/* 6. Actions */}
                  <td className="px-3.5 py-2 text-right">
                    <div className="flex items-center justify-end gap-1.5">
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          onReturnToActive(row, assignedReliever);
                        }}
                        className="inline-flex items-center gap-1 rounded-md bg-emerald-600 px-2 py-1 text-xs font-semibold text-white shadow-2xs hover:bg-emerald-700 transition cursor-pointer"
                      >
                        <RotateCw className="h-3 w-3" />
                        <span>Return to Active</span>
                      </button>
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          onRowClick(row.id);
                        }}
                        className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-base px-2 py-1 text-xs font-semibold text-text-secondary hover:text-brand-primary hover:border-border-strong hover:bg-surface-hover transition-colors shadow-2xs cursor-pointer"
                        aria-label={`View details for ${displayName}`}
                      >
                        <Eye className="h-3 w-3" />
                        <span>Details</span>
                      </button>
                    </div>
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
// Tab 3: Vacancy Table (All Vacant Stores Only)
// ---------------------------------------------------------------------------

function StoreVacancyTable({
  rows,
  onSelectVacancy,
}: {
  rows: VacancyListItem[];
  onSelectVacancy: (v: VacancyListItem) => void;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs flex-1 min-h-0 flex flex-col">
      <div className="overflow-auto flex-1 min-h-0">
        <table className="w-full min-w-[980px] text-left text-xs">
          <thead className="sticky top-0 z-10 bg-table-header shadow-2xs">
            <tr className="border-b border-table-rule">
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Store Branch
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Area & City
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Required Position
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Open Slots
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Remarks
              </th>
              <th className="px-3.5 py-2 text-right text-xs font-semibold text-text-secondary whitespace-nowrap">
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
                tabIndex={0}
                role="button"
                aria-label={`Inspect vacancy for ${row.storeName || "store"}`}
              >
                <td className="px-3.5 py-2 font-medium text-table-text">
                  <div className="flex items-center gap-1.5">
                    <span className="font-bold text-xs">{formatStoreName(row.storeName || "Unnamed Store")}</span>
                    {(row.vcode || row.cgCode) && (
                      <span className="font-mono text-[11px] text-text-muted">
                        ({row.vcode || row.cgCode})
                      </span>
                    )}
                  </div>
                </td>

                <td className="px-3.5 py-2 text-table-text">
                  <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-1.5 py-0.2 text-[10px] font-medium text-text-secondary border border-border-subtle">
                    <MapPin className="h-2.5 w-2.5 text-text-muted shrink-0" />
                    <span>{row.storeLocation || "Unassigned Area"}</span>
                  </span>
                </td>

                <td className="px-3.5 py-2 font-medium text-table-text text-xs">
                  {row.position_title || "General Staff"}
                </td>

                <td className="px-3.5 py-2">
                  <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[11px] font-bold bg-red-100 text-red-700 border border-red-300 dark:bg-red-950 dark:text-red-200 dark:border-red-800">
                    {row.activeApplicantCount > 0 ? row.activeApplicantCount : 1} Vacant
                  </span>
                </td>

                <td className="px-3.5 py-2 text-[11px] text-text-muted">
                  {row.agingDays != null ? `${row.agingDays}d aging • ${row.pipelineStatus || "Open"}` : row.pipelineStatus || "Approved open vacancy"}
                </td>

                <td className="px-3.5 py-2 text-right">
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      onSelectVacancy(row);
                    }}
                    className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-base px-2.5 py-1 text-xs font-semibold text-text-secondary hover:text-brand-primary hover:border-border-strong hover:bg-surface-hover transition-colors shadow-2xs cursor-pointer"
                  >
                    <Eye className="h-3 w-3" />
                    <span>Details</span>
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
// Tab 4: Floating Employees Table
// ---------------------------------------------------------------------------

function EmployeeFloatingTable({
  rows,
  onRowClick,
  storeLookupMap,
  onAssignStore,
}: {
  rows: PlantillaEmployeeListItem[];
  onRowClick: (id: string) => void;
  storeLookupMap: Map<string, { city: string | null; province: string | null; code: string | null }>;
  onAssignStore: (emp: PlantillaEmployeeListItem) => void;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs flex-1 min-h-0 flex flex-col">
      <div className="overflow-auto flex-1 min-h-0">
        <table className="w-full min-w-[980px] text-left text-xs">
          <thead className="sticky top-0 z-10 bg-table-header shadow-2xs">
            <tr className="border-b border-table-rule">
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Member
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Store
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Position
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Assignment
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Status
              </th>
              <th className="px-3.5 py-2 text-right text-xs font-semibold text-text-secondary whitespace-nowrap">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-table-rule">
            {rows.map((row) => {
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
                  className="transition-colors hover:bg-table-row-hover cursor-pointer"
                  onClick={() => onRowClick(row.id)}
                  tabIndex={0}
                  role="button"
                  aria-label={`View floating personnel ${displayName}`}
                >
                  <td className="px-3.5 py-2">
                    <div className="flex items-center gap-2.5">
                      <div className="h-7.5 w-7.5 rounded-full bg-blue-50 border border-blue-200 text-blue-700 font-bold text-[11px] flex items-center justify-center shrink-0 shadow-xs dark:bg-blue-950/40 dark:border-blue-800 dark:text-blue-300">
                        {initials}
                      </div>
                      <div className="min-w-0">
                        <span className="font-semibold text-table-text text-xs hover:text-brand-primary transition-colors">
                          {displayName}
                        </span>
                        <div className="font-mono text-[11px] text-table-text-muted mt-0.5">
                          {row.cgCode || row.vcode ? `${row.cgCode || row.vcode} • ${row.employeeNo}` : row.employeeNo}
                        </div>
                      </div>
                    </div>
                  </td>

                  <td className="px-3.5 py-2 text-table-text">
                    <div className="min-w-0">
                      <div className="font-medium text-text-muted italic text-xs">Unassigned</div>
                      {locationLabel ? (
                        <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-1.5 py-0.2 text-[10px] font-medium text-text-secondary border border-border-subtle mt-0.5">
                          <MapPin className="h-2.5 w-2.5 text-text-muted shrink-0" />
                          <span className="truncate max-w-[150px]">{locationLabel}</span>
                        </span>
                      ) : null}
                    </div>
                  </td>

                  <td className="px-3.5 py-2">
                    <div className="flex flex-col">
                      <span className="font-medium text-table-text text-xs">
                        {row.positionTitle ? formatPosition(row.positionTitle) : "General Staff"}
                      </span>
                      <span className="text-[11px] text-table-text-muted mt-0.5">
                        {row.plantillaType ? `${row.plantillaType} Position` : "Standard Tier"}
                      </span>
                    </div>
                  </td>

                  <td className="px-3.5 py-2">
                    <span className="inline-flex items-center gap-1 rounded-md bg-surface-muted border border-border-default px-1.5 py-0.5 text-xs font-semibold text-text-secondary">
                      {row.assignmentType?.toLowerCase() === "roving" ? "Roving" : "Stationary"}
                    </span>
                  </td>

                  <td className="px-3.5 py-2">
                    <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-bold bg-blue-100 text-blue-800 border border-blue-300 dark:bg-blue-950 dark:text-blue-300 dark:border-blue-800">
                      Floating
                    </span>
                  </td>

                  <td className="px-3.5 py-2 text-right">
                    <div className="flex items-center justify-end gap-1.5">
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          onAssignStore(row);
                        }}
                        className="inline-flex items-center gap-1 rounded-md bg-brand-600 px-2 py-1 text-xs font-semibold text-white shadow-2xs hover:bg-brand-700 transition cursor-pointer"
                      >
                        <Building2 className="h-3 w-3" />
                        <span>Assign Store</span>
                      </button>
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          onRowClick(row.id);
                        }}
                        className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-base px-2 py-1 text-xs font-semibold text-text-secondary hover:text-brand-primary hover:border-border-strong hover:bg-surface-hover transition-colors shadow-2xs cursor-pointer"
                        aria-label={`View details for ${displayName}`}
                      >
                        <Eye className="h-3 w-3" />
                        <span>Details</span>
                      </button>
                    </div>
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
// Tab 5: Deactivation Table (Pending & Deactivated)
// ---------------------------------------------------------------------------

function EmployeeDeactivationTable({
  rows,
  onRowClick,
  storeLookupMap,
}: {
  rows: PlantillaEmployeeListItem[];
  onRowClick: (id: string) => void;
  storeLookupMap: Map<string, { city: string | null; province: string | null; code: string | null }>;
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs flex-1 min-h-0 flex flex-col">
      <div className="overflow-auto flex-1 min-h-0">
        <table className="w-full min-w-[980px] text-left text-xs">
          <thead className="sticky top-0 z-10 bg-table-header shadow-2xs">
            <tr className="border-b border-table-rule">
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Member
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Store
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Position
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Assignment
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Status
              </th>
              <th className="px-3.5 py-2 text-right text-xs font-semibold text-text-secondary whitespace-nowrap">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-table-rule">
            {rows.map((row) => {
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

              const s = (row.plantillaStatus || "").toLowerCase();
              const isDeactivated = s === "deactivated" || row.plantillaStatus?.toLowerCase().includes("deactivated");

              return (
                <tr
                  key={row.id}
                  className="transition-colors hover:bg-table-row-hover cursor-pointer opacity-85"
                  onClick={() => onRowClick(row.id)}
                  tabIndex={0}
                  role="button"
                  aria-label={`View deactivation details for ${displayName}`}
                >
                  <td className="px-3.5 py-2">
                    <div className="flex items-center gap-2.5">
                      <div className="h-7.5 w-7.5 rounded-full bg-surface-muted border border-border-default text-text-muted font-bold text-[11px] flex items-center justify-center shrink-0 shadow-xs">
                        {initials}
                      </div>
                      <div className="min-w-0">
                        <span className="font-semibold text-table-text text-xs hover:text-brand-primary transition-colors">
                          {displayName}
                        </span>
                        <div className="font-mono text-[11px] text-table-text-muted mt-0.5">
                          {row.cgCode || row.vcode ? `${row.cgCode || row.vcode} • ${row.employeeNo}` : row.employeeNo}
                        </div>
                      </div>
                    </div>
                  </td>

                  <td className="px-3.5 py-2 text-table-text">
                    <div className="min-w-0">
                      <div className="font-medium text-table-text text-xs">
                        {formatStoreName(row.primaryStoreName || row.vcode || "—")}
                      </div>
                      {locationLabel && (
                        <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-1.5 py-0.2 text-[10px] font-medium text-text-secondary border border-border-subtle mt-0.5">
                          <MapPin className="h-2.5 w-2.5 text-text-muted shrink-0" />
                          <span className="truncate max-w-[150px]">{locationLabel}</span>
                        </span>
                      )}
                    </div>
                  </td>

                  <td className="px-3.5 py-2">
                    <div className="flex flex-col">
                      <span className="font-medium text-table-text text-xs">
                        {row.positionTitle ? formatPosition(row.positionTitle) : "General Staff"}
                      </span>
                      <span className="text-[11px] text-table-text-muted mt-0.5">
                        {row.plantillaType ? `${row.plantillaType} Position` : "Standard Tier"}
                      </span>
                    </div>
                  </td>

                  <td className="px-3.5 py-2">
                    <span className="inline-flex items-center gap-1 rounded-md bg-surface-muted border border-border-default px-1.5 py-0.5 text-xs font-semibold text-text-secondary">
                      {row.assignmentType?.toLowerCase() === "roving" ? "Roving" : "Stationary"}
                    </span>
                  </td>

                  <td className="px-3.5 py-2">
                    {isDeactivated ? (
                      <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[11px] font-semibold bg-red-100 text-red-700 border border-red-300 dark:bg-red-950 dark:text-red-200 dark:border-red-800">
                        Deactivated
                      </span>
                    ) : (
                      <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[11px] font-semibold bg-amber-100 text-amber-800 border border-amber-300 dark:bg-amber-950 dark:text-amber-200 dark:border-amber-800">
                        Pending for Deactivation
                      </span>
                    )}
                  </td>

                  <td className="px-3.5 py-2 text-right">
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        onRowClick(row.id);
                      }}
                      className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-base px-2.5 py-1 text-xs font-semibold text-text-secondary hover:text-brand-primary hover:border-border-strong hover:bg-surface-hover transition-colors shadow-2xs cursor-pointer"
                      aria-label={`View details for ${displayName}`}
                    >
                      <Eye className="h-3 w-3" />
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
// 5. Store View: Store Capacity Table
// ---------------------------------------------------------------------------

function StoreCapacityTable({
  rows,
}: {
  rows: {
    id: string;
    storeBranch: string;
    code: string | null;
    city: string | null;
    province: string | null;
    plantillaRequired: number;
    activeDeployed: number;
    onLeave: number;
    openVacancy: number;
    isFulfilled: boolean;
  }[];
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs flex-1 min-h-0 flex flex-col">
      <div className="overflow-auto flex-1 min-h-0">
        <table className="w-full min-w-[980px] text-left text-xs">
          <thead className="sticky top-0 z-10 bg-table-header shadow-2xs">
            <tr className="border-b border-table-rule">
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Store Branch
              </th>
              <th className="px-3.5 py-2 text-left text-xs font-semibold text-text-secondary whitespace-nowrap">
                Area & City
              </th>
              <th className="px-3.5 py-2 text-center text-xs font-semibold text-text-secondary whitespace-nowrap">
                Plantilla Required
              </th>
              <th className="px-3.5 py-2 text-center text-xs font-semibold text-text-secondary whitespace-nowrap">
                Active Deployed
              </th>
              <th className="px-3.5 py-2 text-center text-xs font-semibold text-text-secondary whitespace-nowrap">
                On-Leave
              </th>
              <th className="px-3.5 py-2 text-center text-xs font-semibold text-text-secondary whitespace-nowrap">
                Open Vacancy
              </th>
              <th className="px-3.5 py-2 text-center text-xs font-semibold text-text-secondary whitespace-nowrap">
                Fulfillment Status
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-table-rule">
            {rows.map((store) => {
              const locationLabel = [store.city, store.province].filter(Boolean).join(", ");
              return (
                <tr key={store.id} className="transition-colors hover:bg-table-row-hover">
                  {/* 1. Store Branch */}
                  <td className="px-3.5 py-2 font-medium text-table-text">
                    <div className="flex items-center gap-1.5">
                      <span className="font-bold text-xs">{formatStoreName(store.storeBranch)}</span>
                      {store.code && (
                        <span className="font-mono text-[11px] text-text-muted">
                          ({store.code})
                        </span>
                      )}
                    </div>
                  </td>

                  {/* 2. Area & City */}
                  <td className="px-3.5 py-2 text-table-text">
                    <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-1.5 py-0.2 text-[10px] font-medium text-text-secondary border border-border-subtle">
                      <MapPin className="h-2.5 w-2.5 text-text-muted shrink-0" />
                      <span>{locationLabel || "Unassigned Area"}</span>
                    </span>
                  </td>

                  {/* 3. Plantilla Required (centered) */}
                  <td className="px-3.5 py-2 text-center font-mono font-bold text-text-primary text-xs">
                    {store.plantillaRequired}
                  </td>

                  {/* 4. Active Deployed (centered, emerald) */}
                  <td className="px-3.5 py-2 text-center font-mono font-bold text-emerald-600 dark:text-emerald-400 text-xs">
                    {store.activeDeployed}
                  </td>

                  {/* 5. On-Leave (centered, amber) */}
                  <td className="px-3.5 py-2 text-center font-mono font-bold text-amber-600 dark:text-amber-400 text-xs">
                    {store.onLeave}
                  </td>

                  {/* 6. Open Vacancy (centered, red if > 0) */}
                  <td className="px-3.5 py-2 text-center font-mono font-bold text-xs">
                    {store.openVacancy > 0 ? (
                      <span className="text-red-600 dark:text-red-400">{store.openVacancy}</span>
                    ) : (
                      <span className="text-text-muted">0</span>
                    )}
                  </td>

                  {/* 7. Fulfillment Status */}
                  <td className="px-3.5 py-2 text-center">
                    {store.isFulfilled ? (
                      <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[11px] font-semibold bg-emerald-100 text-emerald-800 border border-emerald-300 dark:bg-emerald-950 dark:text-emerald-200 dark:border-emerald-800">
                        100% Fulfilled
                      </span>
                    ) : (
                      <span className="inline-flex items-center px-1.5 py-0.2 rounded-full text-[11px] font-semibold bg-red-100 text-red-700 border border-red-300 dark:bg-red-950 dark:text-red-200 dark:border-red-800">
                        Understaffed
                      </span>
                    )}
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
// Employee Card Component (Optional Cards View)
// ---------------------------------------------------------------------------

function EmployeeCard({
  row,
  onSelect,
  storeLookupMap,
}: {
  row: PlantillaEmployeeListItem;
  onSelect: () => void;
  storeLookupMap: Map<string, { city: string | null; province: string | null; code: string | null }>;
}) {
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
      className="group relative flex flex-col justify-between overflow-hidden rounded-xl border border-border-default bg-surface-base p-4 text-left shadow-xs transition-all duration-200 hover:-translate-y-0.5 hover:border-brand-primary hover:shadow-md cursor-pointer focus:outline-none focus:ring-2 focus:ring-brand-primary border-l-4 border-l-emerald-600"
    >
      <div>
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 shrink-0 rounded-full bg-surface-muted border border-border-default text-brand-primary font-bold text-xs flex items-center justify-center shadow-xs">
            {initials}
          </div>

          <div className="flex-1 min-w-0">
            <h4 className="text-sm font-bold text-text-primary truncate group-hover:text-brand-primary transition-colors">
              {displayName}
            </h4>

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
            {row.plantillaStatus && (
              <StatusBadge
                variant={plantillaStatusVariant(row.plantillaStatus)}
                text={row.plantillaStatus}
              />
            )}
            <ChevronRight className="h-5 w-5 text-text-muted/60 transition-transform group-hover:translate-x-0.5" />
          </div>
        </div>
      </div>

      <div className="mt-3.5 pt-2.5 border-t border-border-subtle flex flex-wrap items-center justify-between gap-2 text-xs text-text-secondary">
        <div className="flex items-center gap-1.5 truncate max-w-[70%]">
          <MapPin className="h-3.5 w-3.5 text-text-muted shrink-0" />
          <span className="truncate font-medium text-text-secondary">
            {formatStoreName(row.primaryStoreName || "—")}
            {locationLabel ? ` (${locationLabel})` : ""}
          </span>
        </div>

        <span className="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-semibold border bg-surface-muted text-text-secondary border-border-default">
          {row.assignmentType || "Stationary"}
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
      <div className="relative mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-brand-50 border border-brand-100 shadow-xs dark:bg-brand-950/40 dark:border-brand-900">
        <Users className="h-8 w-8 text-brand-600 dark:text-brand-400" />
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
          className="mt-4 inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3.5 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary transition-colors shadow-xs cursor-pointer"
        >
          <RotateCcw className="h-3.5 w-3.5" />
          <span>Reset all filters</span>
        </button>
      )}
    </div>
  );
}
