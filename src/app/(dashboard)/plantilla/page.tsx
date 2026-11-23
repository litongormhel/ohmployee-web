"use client";

import { useState, useEffect, useMemo, useCallback, Suspense } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  Users,
  ArrowLeft,
  ArrowRightLeft,
  Building2,
  Plus,
  Store,
  Users2,
  BarChart3,
} from "lucide-react";
import { useSearchParams, useRouter, usePathname } from "next/navigation";
import { useCurrentUser, isOpsAmendmentRole, isHeadOrSuperAdmin } from "@/lib/auth";
import { isDataTeam, canSubmitNewStoreRequest } from "@/lib/rbac";
import { createClient } from "@/lib/supabase/client";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { DataState } from "@/components/shared/DataState";
import { TablePagination } from "@/components/shared/TablePagination";
import type { ToastVariant } from "@/components/shared/Toast";
import {
  getPlantillaSummary,
  listWebPlantillaEmployees,
  listWebPlantillaStoreStaffing,
  fetchAccountStoreAllocations,
  fetchActiveCoverageForAccount,
  fetchPlantillaScopedAccounts,
  usePlantillaInactiveRemarks,
  type PlantillaEmployeeListItem,
  type ActiveCoverageItem,
  type PlantillaScopedAccountItem,
} from "@/lib/queries/plantilla";
import {
  listVacancies,
  type VacancyListItem,
} from "@/lib/queries/vacancy";
import {
  formatPersonName,
  formatAccountName,
} from "@/lib/utils/displayText";
import { MosesHqPoolView } from "@/components/plantilla/MosesHqPoolView";
import { WorkforceAnalyticsView } from "@/components/plantilla/WorkforceAnalyticsView";

// Modular Directory Presentation Containers (SRP Decomposition)
import {
  type PlantillaViewMode,
  type MainViewToggle,
  type StatusSubTab,
  type DisplayView,
  type VacancyWorkflowStage,
  type StoreCapacityRow,
  type RelieverTargetEmployee,
  type ReturnToActiveTarget,
  type AssignStoreTargetEmployee,
  type UpdateStatusTargetEmployee,
  type DeactivationTargetEmployee,
  type ArchiveModalAccount,
  type AbsorbModalAccount,
  type StoreWithAvailableSlots,
  resolveVacancyWorkflowStage,
  isHrPipelineWorkflowStage,
  getVacancyRemainingCapacity,
  renderVacancyStatusBadge,
  isDeactivationRecord,
  isFloatingRecord,
  isInactiveRecord,
  isOnLeaveRecord,
} from "@/components/plantilla/directory/types";
import { EmptyTabState } from "@/components/plantilla/directory/EmptyTabState";
import { PlantillaFilterToolbar } from "@/components/plantilla/directory/PlantillaFilterToolbar";
import { PlantillaAccountSelection } from "@/components/plantilla/directory/PlantillaAccountSelection";
import {
  EmployeeActiveTable,
  EmployeeOnLeaveTable,
  StoreVacancyTable,
  EmployeeFloatingTable,
  EmployeeDeactivationTable,
  EmployeeInactiveTable,
  StoreCapacityTable,
} from "@/components/plantilla/directory/PlantillaTableViews";
import {
  EmployeeCard,
  EmployeeOnLeaveCard,
  VacancyCard,
  EmployeeFloatingCard,
  EmployeeDeactivationCard,
  EmployeeInactiveCard,
} from "@/components/plantilla/directory/PlantillaCardViews";
import {
  PlantillaModalsHub,
  type RequestHeadcountConfig,
} from "@/components/plantilla/directory/PlantillaModalsHub";

// Re-export types and helpers for backward compatibility
export type {
  PlantillaViewMode,
  MainViewToggle,
  StatusSubTab,
  DisplayView,
  VacancyWorkflowStage,
};
export {
  resolveVacancyWorkflowStage,
  isHrPipelineWorkflowStage,
  getVacancyRemainingCapacity,
  renderVacancyStatusBadge,
};

// ---------------------------------------------------------------------------
// Page Component Wrapper (Suspense Boundary)
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

// ---------------------------------------------------------------------------
// Master Page Orchestrator Content
// ---------------------------------------------------------------------------

function PlantillaPageContent() {
  // Search parameters and router
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();

  // Main view toggle: "employee" vs "store"
  const [mainView, setMainView] = useState<MainViewToggle>("employee");

  // 6 Status Sub-Tabs with reactive URL search param synchronization
  const [internalStatusTab, setInternalStatusTab] = useState<StatusSubTab>("active");
  const urlStatusParam = (
    searchParams.get("status") ||
    searchParams.get("statusTab") ||
    searchParams.get("fromTab")
  )?.toLowerCase();
  const statusTab: StatusSubTab =
    urlStatusParam &&
    (["active", "on_leave", "vacancy", "floating", "deactivation", "inactive"] as string[]).includes(
      urlStatusParam
    )
      ? (urlStatusParam as StatusSubTab)
      : internalStatusTab;

  const [vacancySubFilter] = useState<"all" | "open" | "pipeline">("all");

  const urlDisplayParam = (
    searchParams.get("display") ||
    searchParams.get("displayView") ||
    searchParams.get("viewMode")
  )?.toLowerCase();
  const [displayView, setDisplayView] = useState<DisplayView>(
    urlDisplayParam === "cards" ? "cards" : "table"
  );

  function handleSetDisplayView(view: DisplayView) {
    setDisplayView(view);
    const params = new URLSearchParams(searchParams.toString());
    params.set("display", view);
    router.replace(`${pathname}?${params.toString()}`, { scroll: false });
  }

  function handleSelectStatusTab(tab: StatusSubTab) {
    setInternalStatusTab(tab);
    setPage(1);
    const params = new URLSearchParams(searchParams.toString());
    params.set("status", tab);
    params.delete("page");
    router.replace(`${pathname}?${params.toString()}`, { scroll: false });
  }

  // Table pagination state with URL synchronization
  const urlPageParam = searchParams.get("page");
  const initialPage = urlPageParam ? Math.max(1, parseInt(urlPageParam, 10) || 1) : 1;
  const [page, setPage] = useState(initialPage);
  const [pageSize, setPageSize] = useState<number>(10);

  // Store View table pagination (default 15 rows per page)
  const [storePage, setStorePage] = useState<number>(1);
  const [storePageSize, setStorePageSize] = useState<number>(15);

  function handlePageChange(newPage: number) {
    setPage(newPage);
    const params = new URLSearchParams(searchParams.toString());
    if (newPage > 1) {
      params.set("page", newPage.toString());
    } else {
      params.delete("page");
    }
    router.replace(`${pathname}?${params.toString()}`, { scroll: false });
  }

  // Detail drawers and modals
  const [selectedVacancyId, setSelectedVacancyId] = useState<string | null>(null);
  const [requestHeadcountConfig, setRequestHeadcountConfig] = useState<RequestHeadcountConfig | null>(null);
  const [isNewStoreModalOpen, setIsNewStoreModalOpen] = useState(false);

  // Workflow modals
  const [relieverTargetEmployee, setRelieverTargetEmployee] = useState<RelieverTargetEmployee | null>(null);
  const [returnToActiveTarget, setReturnToActiveTarget] = useState<ReturnToActiveTarget | null>(null);
  const [assignStoreTargetEmployee, setAssignStoreTargetEmployee] = useState<AssignStoreTargetEmployee | null>(null);
  const [updateStatusTargetEmployee, setUpdateStatusTargetEmployee] = useState<UpdateStatusTargetEmployee | null>(null);
  const [deactivationTargetEmployee, setDeactivationTargetEmployee] = useState<DeactivationTargetEmployee | null>(null);

  // Account selector state
  const [accountSearch, setAccountSearch] = useState("");
  const [selectorGroupId, setSelectorGroupId] = useState("");

  // Directory actions & modals
  const [isAddAccountOpen, setIsAddAccountOpen] = useState(false);
  const [isCreateCoverageGroupOpen, setIsCreateCoverageGroupOpen] = useState(false);
  const [archiveModalAccount, setArchiveModalAccount] = useState<ArchiveModalAccount | null>(null);
  const [absorbModalAccount, setAbsorbModalAccount] = useState<AbsorbModalAccount | null>(null);
  const [transferGroupModalAccount, setTransferGroupModalAccount] = useState<PlantillaScopedAccountItem | null>(null);

  // Card context menu state
  const [activeMenuAccountId, setActiveMenuAccountId] = useState<string | null>(null);

  // Feedback Toast state
  const [toastMessage, setToastMessage] = useState<string | null>(null);
  const [toastVariant, setToastVariant] = useState<ToastVariant>("success");

  const showToast = useCallback((msg: string, variant: ToastVariant = "success") => {
    setToastMessage(msg);
    setToastVariant(variant);
    setTimeout(() => {
      setToastMessage((current) => (current === msg ? null : current));
    }, 4500);
  }, [setToastMessage, setToastVariant]);

  // Directory filter state with URL restoration
  const urlSearchParam = searchParams.get("search") ?? "";
  const [search, setSearch] = useState(urlSearchParam);
  const [areaCityFilter, setAreaCityFilter] = useState(""); // "" | "area:Name" | "city:Name"
  const [assignmentType, setAssignmentType] = useState(""); // "" | "stationary" | "roving"

  // -------------------------------------------------------------------------
  // User Context and Account Lists
  // -------------------------------------------------------------------------

  const currentUser = useCurrentUser();
  const userRole = currentUser?.roleKey ?? currentUser?.roleName;
  const canRequestAdjustment = isOpsAmendmentRole(userRole);
  const canRequestNewStore = canSubmitNewStoreRequest(currentUser);

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

  // Close card action menu on outside click
  useEffect(() => {
    if (!activeMenuAccountId) return;
    const handleOutsideClick = () => setActiveMenuAccountId(null);
    window.addEventListener("click", handleOutsideClick);
    return () => window.removeEventListener("click", handleOutsideClick);
  }, [activeMenuAccountId]);

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

  // Navigation to Dedicated Full-Page Employee Profile (/plantilla/[id]) with context preservation
  const handleNavigateToEmployee = useCallback((empId: string) => {
    const params = new URLSearchParams(searchParams.toString());
    params.set("status", statusTab);
    params.set("display", displayView);
    if (page > 1) {
      params.set("page", page.toString());
    } else {
      params.delete("page");
    }
    if (search.trim()) {
      params.set("search", search.trim());
    } else {
      params.delete("search");
    }
    if (accountId) {
      params.set("accountId", accountId);
    }
    router.push(`/plantilla/${empId}?${params.toString()}`);
  }, [searchParams, statusTab, displayView, page, search, accountId, router]);

  // Verify that accountId is authorized for the current user
  const isAccountAuthorized = useMemo(() => {
    if (!accountId) return true;
    if (hasAllScope) return true;
    if (!allowedAccountsQuery.isSuccess) return true;
    return (allowedAccountsQuery.data ?? []).some((a) => a.id === accountId);
  }, [accountId, hasAllScope, allowedAccountsQuery.isSuccess, allowedAccountsQuery.data]);

  const accountMetricsQuery = useQuery({
    queryKey: [
      "plantilla",
      "account-allocation-kpi",
      allowedAccountsQuery.data?.map((a) => a.id).join(","),
    ],
    queryFn: async () => {
      const supabase = createClient();
      const [kpiRes, leaveRes, activeEmpRes, poolSlotsRes, slotsRes] = await Promise.all([
        supabase
          .from("v_account_allocation_kpi")
          .select("account_id, actual_hc, slot_vacant_hc, pipeline_count, required_hc"),
        supabase
          .from("plantilla")
          .select("account_id")
          .in("status", ["On Leave", "on_leave"])
          .is("deactivated_at", null)
          .is("date_of_separation", null)
          .or("is_deleted.is.null,is_deleted.eq.false")
          .or("is_archived.is.null,is_archived.eq.false"),
        supabase
          .from("plantilla")
          .select("id, account_id, account, is_pool_employee")
          .eq("status", "Active")
          .is("deactivated_at", null)
          .is("date_of_separation", null)
          .or("is_deleted.is.null,is_deleted.eq.false")
          .or("is_archived.is.null,is_archived.eq.false"),
        supabase
          .from("workforce_pool_slots")
          .select("id, status")
          .eq("is_active", true)
          .is("deleted_at", null),
        supabase
          .from("plantilla_slots")
          .select("account_id, slot_status")
          .neq("slot_status", "closed")
          .is("closed_at", null),
      ]);

      if (kpiRes.error) {
        console.warn("[Plantilla] Could not fetch batch account metrics from v_account_allocation_kpi:", kpiRes.error);
        return new Map<string, { actual: number; vacant: number; hrProcess: number; required: number; fillRate: number; leave: number }>();
      }

      const leaveMap = new Map<string, number>();
      if (!leaveRes.error && Array.isArray(leaveRes.data)) {
        for (const row of leaveRes.data) {
          if (row.account_id) {
            const accId = String(row.account_id);
            leaveMap.set(accId, (leaveMap.get(accId) ?? 0) + 1);
          }
        }
      }

      const totalSlotsMap = new Map<string, number>();
      const openSlotsMap = new Map<string, number>();
      if (!slotsRes.error && Array.isArray(slotsRes.data)) {
        for (const slot of slotsRes.data) {
          if (slot.account_id) {
            const accId = String(slot.account_id);
            totalSlotsMap.set(accId, (totalSlotsMap.get(accId) ?? 0) + 1);
            if (slot.slot_status === "open") {
              openSlotsMap.set(accId, (openSlotsMap.get(accId) ?? 0) + 1);
            }
          }
        }
      }

      const activeEmpMap = new Map<string, number>();
      const activeEmployees = !activeEmpRes.error && Array.isArray(activeEmpRes.data) ? activeEmpRes.data : [];
      for (const emp of activeEmployees) {
        if (emp.account_id) {
          const accId = String(emp.account_id);
          activeEmpMap.set(accId, (activeEmpMap.get(accId) ?? 0) + 1);
        }
      }

      const map = new Map<string, { actual: number; vacant: number; hrProcess: number; required: number; fillRate: number; leave: number }>();
      const processedAccountIds = new Set<string>();

      (kpiRes.data ?? []).forEach((row) => {
        const accId = String(row.account_id);
        processedAccountIds.add(accId);

        const actual = Number(row.actual_hc ?? 0);
        const hrProcess = Number(row.pipeline_count ?? 0);
        const vacant = Math.round(Number(row.slot_vacant_hc ?? 0));
        const required = Number(row.required_hc ?? (actual + vacant + hrProcess));
        const leave = leaveMap.get(accId) ?? 0;

        const fillRate = required > 0 ? (actual / required) * 100 : 0;
        map.set(accId, { actual, vacant, hrProcess, required, fillRate, leave });
      });

      // Handle accounts present in allowedAccountsQuery but absent from v_account_allocation_kpi
      (allowedAccountsQuery.data ?? []).forEach((a) => {
        const accId = String(a.id);
        if (!processedAccountIds.has(accId) && !a.isPoolAccount && a.name.trim().toLowerCase() !== "moses hq") {
          const actual = activeEmpMap.get(accId) ?? 0;
          const leave = leaveMap.get(accId) ?? 0;
          const openSlots = openSlotsMap.get(accId) ?? 0;
          const vacant = openSlots;
          const hrProcess = 0;
          const required = actual + leave + vacant + hrProcess;
          const fillRate = required > 0 ? (actual / required) * 100 : 0;
          map.set(accId, { actual, vacant, hrProcess, required, fillRate, leave });
        }
      });

      // Workforce Pool Account KPI integration (e.g. Moses HQ, is_pool_account: true)
      const poolAccountIds = new Set<string>();
      (allowedAccountsQuery.data ?? []).forEach((a) => {
        if (a.isPoolAccount || a.name.trim().toLowerCase() === "moses hq") {
          poolAccountIds.add(String(a.id));
        }
      });

      const poolSlots = !poolSlotsRes.error && Array.isArray(poolSlotsRes.data) ? poolSlotsRes.data : [];
      const openPoolSlotsCount = poolSlots.filter((s) => s.status === "open").length;

      for (const poolId of poolAccountIds) {
        const poolActiveHc = activeEmployees.filter(
          (e) =>
            String(e.account_id) === poolId ||
            (e.is_pool_employee && String(e.account_id) === poolId) ||
            String(e.account ?? "").trim().toLowerCase() === "moses hq",
        ).length;
        const vacant = poolSlots.length > 0 ? openPoolSlotsCount : 0;
        const required = poolSlots.length > 0 ? poolSlots.length : poolActiveHc;
        const fillRate = required > 0 ? (poolActiveHc / required) * 100 : 0;
        const leave = leaveMap.get(poolId) ?? 0;

        map.set(poolId, {
          actual: poolActiveHc,
          vacant,
          hrProcess: 0,
          required,
          fillRate,
          leave,
        });
      }

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
        .eq("is_archived", false)
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
    queryKey: [
      "plantilla",
      "summary",
      { search, accountId, effectiveSelectorGroupId: accountId ? undefined : effectiveSelectorGroupId },
    ],
    queryFn: () =>
      getPlantillaSummary({
        search: accountId ? (search || undefined) : undefined,
        accountId: accountId || undefined,
        groupId: accountId ? undefined : (effectiveSelectorGroupId || undefined),
      }),
    enabled: !!currentUser && !!accountId && isAccountAuthorized,
  });

  const selectedAccount = useMemo(() => {
    return (allowedAccountsQuery.data ?? []).find((a) => a.id === accountId);
  }, [allowedAccountsQuery.data, accountId]);

  // Query all plantilla employees under current account
  const employeeQuery = useQuery({
    queryKey: ["plantilla", "employees-all", accountId, selectedAccount?.name],
    queryFn: () =>
      listWebPlantillaEmployees({
        accountId,
        accountName: selectedAccount?.name,
        activeState: "all",
        page: 1,
        pageSize: 2000,
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
        page: 1,
        pageSize: 2000,
        consolidateCoverageGroups: false,
      }),
    enabled: !!accountId && isAccountAuthorized,
    staleTime: 30000,
  });

  // Query closed/archived vacancy codes under current account so synthetic vacancies never resurrect dead slots
  const closedVcodesQuery = useQuery({
    queryKey: ["plantilla", "closed-vcodes", accountId],
    queryFn: async () => {
      if (!accountId) return new Set<string>();
      const supabase = createClient();
      const { data } = await supabase
        .from("vacancies")
        .select("vcode")
        .eq("account_id", accountId)
        .or("is_archived.eq.true,status.in.(Closed,Archived)");
      const set = new Set<string>();
      (data ?? []).forEach((r) => {
        if (r.vcode) set.add(r.vcode.trim().toUpperCase());
      });
      return set;
    },
    enabled: !!accountId && isAccountAuthorized,
    staleTime: 60000,
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

  // Store allocations query for accurate roving fractional headcount in Store View
  const storeAllocationsQuery = useQuery({
    queryKey: ["plantilla", "account-store-allocations", accountId],
    queryFn: () => fetchAccountStoreAllocations(accountId),
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

  // Tab 1: Active
  const activeEmployees = useMemo(() => {
    return allEmployees.filter((emp) => {
      if (
        isInactiveRecord(emp) ||
        isDeactivationRecord(emp) ||
        isFloatingRecord(emp) ||
        isOnLeaveRecord(emp)
      ) {
        return false;
      }
      const s = (emp.plantillaStatus || "").toLowerCase().trim();
      return (
        emp.isActive === true ||
        s === "active" ||
        s === "active deployed" ||
        s === "deployed" ||
        s === "" ||
        !emp.plantillaStatus
      );
    });
  }, [allEmployees]);

  // Tab 2: On-Leave
  const rawOnLeaveEmployees = useMemo(() => {
    return allEmployees.filter(isOnLeaveRecord);
  }, [allEmployees]);

  const onLeaveEmployeeIds = useMemo(() => {
    return rawOnLeaveEmployees.map((e) => e.id);
  }, [rawOnLeaveEmployees]);

  const onLeaveRemarksQuery = usePlantillaInactiveRemarks(onLeaveEmployeeIds);
  const onLeaveRemarksMap = onLeaveRemarksQuery.data;

  const onLeaveEmployees = useMemo(() => {
    if (!onLeaveRemarksMap || onLeaveRemarksMap.size === 0) return rawOnLeaveEmployees;
    return rawOnLeaveEmployees.map((emp) => {
      const rem = onLeaveRemarksMap.get(emp.id);
      return rem ? { ...emp, separationRemarks: rem } : emp;
    });
  }, [rawOnLeaveEmployees, onLeaveRemarksMap]);

  // Tab 4: Floating
  const floatingEmployees = useMemo(() => {
    return allEmployees.filter(isFloatingRecord);
  }, [allEmployees]);

  // Tab 5: Deactivation
  const deactivationEmployees = useMemo(() => {
    return allEmployees.filter(isDeactivationRecord);
  }, [allEmployees]);

  // Tab 6: Inactive (Resigned / AWOL / Terminated)
  const baseInactiveEmployees = useMemo(() => {
    return allEmployees.filter(isInactiveRecord);
  }, [allEmployees]);

  const inactiveEmployeeIds = useMemo(() => {
    return baseInactiveEmployees.map((e) => e.id);
  }, [baseInactiveEmployees]);

  const inactiveRemarksQuery = usePlantillaInactiveRemarks(inactiveEmployeeIds);
  const inactiveRemarksMap = inactiveRemarksQuery.data;

  const inactiveEmployees = useMemo(() => {
    if (!inactiveRemarksMap || inactiveRemarksMap.size === 0) return baseInactiveEmployees;
    return baseInactiveEmployees.map((emp) => {
      const rem = inactiveRemarksMap.get(emp.id);
      return rem ? { ...emp, separationRemarks: rem } : emp;
    });
  }, [baseInactiveEmployees, inactiveRemarksMap]);

  // Active employees' occupied VCodes
  const activeOccupiedVcodes = useMemo(() => {
    const map = new Map<string, number>();
    activeEmployees.forEach((emp) => {
      const vk = emp.vcode?.trim().toUpperCase();
      if (vk) {
        map.set(vk, (map.get(vk) ?? 0) + 1);
      }
      const cg = emp.cgCode?.trim().toUpperCase();
      if (cg) {
        map.set(cg, (map.get(cg) ?? 0) + 1);
      }
    });
    return map;
  }, [activeEmployees]);

  // Tab 3: Vacancy Rows
  const allVacancies = useMemo(() => {
    const raw = vacancyListQuery.data?.data ?? [];
    const seenVcodes = new Set<string>();
    const seenStoreNames = new Set<string>();

    const filtered = raw.filter((v) => {
      const vk = (v.vcode || "").trim().toUpperCase();
      const cg = (v.cgCode || "").trim().toUpperCase();
      const isFilled =
        v.vacancyStatus?.toLowerCase() === "filled" ||
        v.pipelineStatus?.toLowerCase() === "hired" ||
        v.derivedStatus?.toLowerCase() === "hired";
      if (isFilled) return false;

      const registerSeenKeys = () => {
        if (vk) seenVcodes.add(vk);
        if (v.storeName) seenStoreNames.add(v.storeName.replace(/\s*\[Roving\]/i, "").toLowerCase().trim());
      };

      if (v.hcTotal != null && v.hcFilled != null && v.hcFilled < v.hcTotal) {
        registerSeenKeys();
        return true;
      }

      if ((vk && activeOccupiedVcodes.has(vk)) || (cg && activeOccupiedVcodes.has(cg))) {
        const activeCount = (cg ? activeOccupiedVcodes.get(cg) : 0) || (vk ? activeOccupiedVcodes.get(vk) : 0) || 0;
        const required = v.hcTotal ?? v.headcount ?? 1;
        if (activeCount >= required && required > 0) return false;
      }
      registerSeenKeys();
      return true;
    });

    const closedVcodes = closedVcodesQuery.data ?? new Set<string>();
    const synthesized: VacancyListItem[] = [];
    inactiveEmployees.forEach((emp) => {
      const vk = (emp.vcode || "").trim().toUpperCase();
      if (!vk || closedVcodes.has(vk)) return;

      const storeNameKey = (emp.primaryStoreName || "").toLowerCase().trim();
      const storeInfo = storeNameKey ? storeLookupMap.get(storeNameKey) : null;
      if (!storeInfo) return;
      if (storeNameKey && seenStoreNames.has(storeNameKey)) return;

      const isOccupiedByActive = activeOccupiedVcodes.has(vk);
      const alreadyInVacancies = seenVcodes.has(vk);

      if (!isOccupiedByActive && !alreadyInVacancies) {
        seenVcodes.add(vk);
        synthesized.push({
          id: `vac-inactive-${emp.id}`,
          vcode: emp.vcode || `VC-${emp.id.substring(0, 8).toUpperCase()}`,
          cgCode: null,
          accountId: accountId || null,
          accountName: emp.accountName || selectedAccount?.name || null,
          groupId: null,
          groupName: null,
          storeId: storeInfo.id || null,
          storeName: emp.primaryStoreName || null,
          storeLocation: [storeInfo.city, storeInfo.province].filter(Boolean).join(" • ") || null,
          position_title: emp.positionTitle || "Motorized Collector",
          department: null,
          employmentType: emp.assignmentType || "Stationary",
          vacancyStatus: "Open",
          pipelineStatus: "Vacancy - Open",
          derivedStatus: "Open",
          activeApplicantCount: 0,
          confirmedOnboardCount: 0,
          hasRecentHire: false,
          hasPendingClosure: false,
          closureRequestStatus: null,
          vacantDate: emp.separationDate || new Date().toISOString().substring(0, 10),
          agingDays: null,
          agingBucket: null,
          targetFillDate: null,
          urgencyLevel: "Standard",
          hrcoName: "—",
          applicantName: null,
          hasPenalty: false,
          penaltyExposure: 0,
          penaltyAmount: null,
          headcount: 1,
          hcFilled: 0,
          hcTotal: 1,
          hcDisplay: "0/1",
          lastActivityAt: null,
          remarks: emp.separationRemarks || emp.remarks || null,
          stageBadge: "Vacancy - Open",
          rowCapabilities: {
            canViewDetail: true,
            canApprove: false,
            canUpdateApplicantStatus: true,
            canRequestClosure: true,
            raw: {},
          },
          totalCount: 1,
        });
      }
    });

    return [...filtered, ...synthesized];
  }, [
    vacancyListQuery.data?.data,
    activeOccupiedVcodes,
    inactiveEmployees,
    closedVcodesQuery.data,
    storeLookupMap,
    accountId,
    selectedAccount?.name,
  ]);

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
  const filteredInactiveEmployees = useMemo(() => inactiveEmployees.filter(filterEmployee), [inactiveEmployees, filterEmployee]);

  const totalVacanciesSlots = useMemo(() => {
    return allVacancies.reduce((sum, v) => sum + getVacancyRemainingCapacity(v), 0);
  }, [allVacancies]);

  const filteredVacancies = useMemo(() => {
    return allVacancies.filter((v) => {
      const stage = resolveVacancyWorkflowStage(v);
      if (vacancySubFilter === "open") {
        if (stage !== "Vacancy - Open" && stage !== "Vacancy - Pipeline") return false;
      } else if (vacancySubFilter === "pipeline") {
        if (!isHrPipelineWorkflowStage(stage)) return false;
      }

      if (search.trim()) {
        const q = search.toLowerCase().trim();
        const store = (v.storeName || "").toLowerCase();
        const pos = (v.position_title || "").toLowerCase();
        const vcode = (v.vcode || v.cgCode || "").toLowerCase();
        const applicant = (v.applicantName || "").toLowerCase();
        const remarks = (v.remarks || v.opsRemarks || v.recruitmentRemarks || v.hrRemarks || "").toLowerCase();
        const stageStr = stage.toLowerCase();
        if (!store.includes(q) && !pos.includes(q) && !vcode.includes(q) && !applicant.includes(q) && !remarks.includes(q) && !stageStr.includes(q)) return false;
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
  }, [allVacancies, vacancySubFilter, search, areaCityFilter, storeLookupMap]);

  // Discover stores deployed to employees or vacancies not directly under account_id in stores table
  const unmappedStoreNames = useMemo(() => {
    const knownKeys = new Set((storesUnderAccountQuery.data ?? []).map((s) => s.name.toLowerCase().trim()));
    const missing = new Set<string>();
    allEmployees.forEach((emp) => {
      const name = emp.primaryStoreName?.trim();
      if (name && !knownKeys.has(name.toLowerCase())) {
        missing.add(name);
      }
    });
    allVacancies.forEach((v) => {
      const name = v.storeName?.trim();
      if (name && !knownKeys.has(name.toLowerCase())) {
        missing.add(name);
      }
    });
    return Array.from(missing);
  }, [storesUnderAccountQuery.data, allEmployees, allVacancies]);

  const unmappedStoresQuery = useQuery({
    queryKey: ["plantilla", "unmapped-stores", unmappedStoreNames.sort().join(",")],
    queryFn: async () => {
      if (unmappedStoreNames.length === 0) return [];
      const supabase = createClient();
      const { data, error } = await supabase
        .from("stores")
        .select("id, store_name, vcode, area_city, area_province, province")
        .in("store_name", unmappedStoreNames)
        .eq("is_active", true)
        .eq("is_archived", false)
        .limit(50);
      if (error) {
        console.warn("Could not fetch unmapped stores metadata:", error);
        return [];
      }
      return (data ?? []).map((s) => ({
        id: s.id as string,
        name: s.store_name as string,
        code: (s.vcode as string | null) ?? null,
        city: (s.area_city as string | null) ?? null,
        province: ((s.area_province ?? s.province) as string | null) ?? null,
      }));
    },
    enabled: unmappedStoreNames.length > 0,
    staleTime: 60000,
  });

  const effectiveStoreLookupMap = useMemo(() => {
    const map = new Map<string, { id?: string; city: string | null; province: string | null; code: string | null }>();
    const combined = [
      ...(storesUnderAccountQuery.data ?? []),
      ...(unmappedStoresQuery.data ?? []),
    ];
    combined.forEach((s) => {
      const info = { id: s.id, city: s.city, province: s.province, code: s.code };
      map.set(s.name.toLowerCase().trim(), info);
      map.set(s.id, info);
    });
    return map;
  }, [storesUnderAccountQuery.data, unmappedStoresQuery.data]);

  // Store Capacity Table Data (for mainView === "store")
  const storeCapacityRows = useMemo(() => {
    const staffingList = storeStaffingQuery.data?.data ?? [];
    const staffingMap = new Map<string, typeof staffingList[0]>();
    staffingList.forEach((s) => {
      staffingMap.set(s.storeId, s);
    });

    const activeAllocations = storeAllocationsQuery.data ?? [];
    const hasAllocations = activeAllocations.length > 0;

    const storeActiveCountMap = new Map<string, number>();
    const storeOnLeaveCountMap = new Map<string, number>();

    // Build map of employee status from allEmployees
    const employeeMap = new Map<string, PlantillaEmployeeListItem>();
    allEmployees.forEach((emp) => {
      if (emp.id) employeeMap.set(emp.id, emp);
      if (emp.employeeNo) employeeMap.set(emp.employeeNo, emp);
    });

    // Track which employees were processed via allocations
    const processedEmployeeKeys = new Set<string>();

    if (hasAllocations) {
      activeAllocations.forEach((alloc) => {
        const emp = (alloc.plantillaId ? employeeMap.get(alloc.plantillaId) : null) ??
          (alloc.employeeNo ? employeeMap.get(alloc.employeeNo) : null);

        const s = (emp?.plantillaStatus || "active").toLowerCase();
        const storeKey = alloc.storeName?.toLowerCase().trim();
        if (!storeKey) return;

        if (emp) {
          processedEmployeeKeys.add(emp.id);
          if (emp.employeeNo) processedEmployeeKeys.add(emp.employeeNo);
        } else if (alloc.employeeNo) {
          processedEmployeeKeys.add(alloc.employeeNo);
        }

        const hc = alloc.filledHc > 0 ? alloc.filledHc : 1;

        if (s === "active" && (!emp || (!isDeactivationRecord(emp) && !isFloatingRecord(emp) && !isOnLeaveRecord(emp)))) {
          storeActiveCountMap.set(storeKey, (storeActiveCountMap.get(storeKey) ?? 0) + hc);
        } else if (s === "on leave" || s === "on_leave") {
          storeOnLeaveCountMap.set(storeKey, (storeOnLeaveCountMap.get(storeKey) ?? 0) + hc);
        }
      });
    }

    // Fallback: for employees without allocations in employee_store_allocations
    allEmployees.forEach((emp) => {
      if (processedEmployeeKeys.has(emp.id) || (emp.employeeNo && processedEmployeeKeys.has(emp.employeeNo))) {
        return;
      }
      const storeKey = emp.primaryStoreName?.toLowerCase().trim();
      const s = (emp.plantillaStatus || "").toLowerCase();
      if (!storeKey) return;

      const hc = emp.coveredStoresCount > 1 ? (1 / emp.coveredStoresCount) : 1;

      if (s === "active" && !isDeactivationRecord(emp) && !isFloatingRecord(emp) && !isOnLeaveRecord(emp)) {
        storeActiveCountMap.set(storeKey, (storeActiveCountMap.get(storeKey) ?? 0) + hc);
      } else if (s === "on leave" || s === "on_leave") {
        storeOnLeaveCountMap.set(storeKey, (storeOnLeaveCountMap.get(storeKey) ?? 0) + hc);
      }
    });

    const storeVacancyCountMap = new Map<string, number>();
    allVacancies.forEach((v) => {
      const key = (v.storeName || "").toLowerCase().trim();
      if (key) {
        const remainingCapacity = getVacancyRemainingCapacity(v);
        const isRoving = Boolean(
          v.employmentType?.toLowerCase().includes("roving") ||
          v.cgCode ||
          v.vcode?.startsWith("CG-")
        );
        const assignedCount = v.assignedStoreDetails?.length || v.assignedStores?.length || 0;
        const rovingShare =
          v.slotShare ?? (isRoving && assignedCount > 1 ? 1 / assignedCount : 1);
        storeVacancyCountMap.set(
          key,
          (storeVacancyCountMap.get(key) ?? 0) + remainingCapacity * rovingShare
        );
      }
    });

    const candidateStoreMap = new Map<
      string,
      {
        id: string;
        name: string;
        code: string | null;
        city: string | null;
        province: string | null;
      }
    >();

    (storesUnderAccountQuery.data ?? []).forEach((st) => {
      candidateStoreMap.set(st.name.toLowerCase().trim(), {
        id: st.id,
        name: st.name,
        code: st.code,
        city: st.city,
        province: st.province,
      });
    });

    (unmappedStoresQuery.data ?? []).forEach((st) => {
      const key = st.name.toLowerCase().trim();
      if (!candidateStoreMap.has(key)) {
        candidateStoreMap.set(key, {
          id: st.id,
          name: st.name,
          code: st.code,
          city: st.city,
          province: st.province,
        });
      }
    });

    // Ensure all stores with active allocations are in candidateStoreMap
    activeAllocations.forEach((alloc) => {
      const rawName = alloc.storeName?.trim();
      if (rawName) {
        const key = rawName.toLowerCase();
        if (!candidateStoreMap.has(key)) {
          const info = effectiveStoreLookupMap.get(key);
          candidateStoreMap.set(key, {
            id: alloc.storeId || info?.id || `alloc-${key}`,
            name: rawName,
            code: alloc.vcode || info?.code || null,
            city: info?.city || null,
            province: info?.province || null,
          });
        }
      }
    });

    allEmployees.forEach((emp) => {
      const rawName = emp.primaryStoreName?.trim();
      if (rawName) {
        const key = rawName.toLowerCase();
        if (!candidateStoreMap.has(key)) {
          const info = effectiveStoreLookupMap.get(key);
          candidateStoreMap.set(key, {
            id: info?.id || `temp-emp-${key}`,
            name: rawName,
            code: info?.code || null,
            city: info?.city || null,
            province: info?.province || null,
          });
        }
      }
    });

    allVacancies.forEach((v) => {
      const rawName = v.storeName?.trim();
      if (rawName) {
        const key = rawName.toLowerCase();
        if (!candidateStoreMap.has(key)) {
          const info = effectiveStoreLookupMap.get(key);
          candidateStoreMap.set(key, {
            id: v.storeId || info?.id || `temp-vac-${key}`,
            name: rawName,
            code: info?.code || null,
            city: info?.city || null,
            province: info?.province || null,
          });
        }
      }
    });

    const rows: StoreCapacityRow[] = [];

    candidateStoreMap.forEach((storeObj, storeKey) => {
      const rawActive = storeActiveCountMap.get(storeKey) ?? 0;
      const rawOnLeave = storeOnLeaveCountMap.get(storeKey) ?? 0;
      const rawVacancy = storeVacancyCountMap.get(storeKey) ?? 0;

      const activeDeployed = Math.round(rawActive * 100) / 100;
      const onLeave = Math.round(rawOnLeave * 100) / 100;
      const openVacancy = Math.round(rawVacancy * 100) / 100;

      if (activeDeployed === 0 && onLeave === 0 && openVacancy === 0) {
        return;
      }

      const derivedRequired = Math.round((activeDeployed + openVacancy) * 100) / 100;
      const staffing = staffingMap.get(storeObj.id);
      const plantillaRequired = derivedRequired > 0
        ? derivedRequired
        : (staffing?.requiredHeadcount ?? derivedRequired);
      const isFulfilled = activeDeployed >= plantillaRequired - 0.01 && openVacancy === 0;

      rows.push({
        id: storeObj.id,
        storeBranch: storeObj.name,
        code: storeObj.code,
        city: storeObj.city,
        province: storeObj.province,
        plantillaRequired,
        activeDeployed,
        onLeave,
        openVacancy,
        isFulfilled,
      });
    });

    return rows.sort((a, b) => a.storeBranch.localeCompare(b.storeBranch));
  }, [
    storeStaffingQuery.data?.data,
    storeAllocationsQuery.data,
    storesUnderAccountQuery.data,
    unmappedStoresQuery.data,
    effectiveStoreLookupMap,
    allEmployees,
    allVacancies,
  ]);

  const filteredStoreCapacityRows = useMemo(() => {
    return storeCapacityRows.filter((st) => {
      if (search.trim()) {
        const q = search.toLowerCase().trim();
        const branch = st.storeBranch.toLowerCase();
        const code = (st.code || "").toLowerCase();
        const city = (st.city || "").toLowerCase();
        const province = (st.province || "").toLowerCase();
        if (!branch.includes(q) && !code.includes(q) && !city.includes(q) && !province.includes(q)) {
          return false;
        }
      }

      if (areaCityFilter) {
        if (areaCityFilter.startsWith("area:")) {
          const area = areaCityFilter.replace("area:", "").toLowerCase().trim();
          const storeArea = (st.province || "").toLowerCase().trim();
          if (storeArea !== area) return false;
        } else if (areaCityFilter.startsWith("city:")) {
          const city = areaCityFilter.replace("city:", "").toLowerCase().trim();
          const storeCity = (st.city || "").toLowerCase().trim();
          if (storeCity !== city) return false;
        }
      }

      return true;
    });
  }, [storeCapacityRows, search, areaCityFilter]);

  const storesWithAvailableSlots = useMemo<StoreWithAvailableSlots[]>(() => {
    const rawStores = storesUnderAccountQuery.data ?? [];
    const capacityMap = new Map<string, StoreCapacityRow>();
    storeCapacityRows.forEach((sc) => {
      capacityMap.set(sc.id, sc);
      capacityMap.set(sc.storeBranch.toLowerCase().trim(), sc);
    });

    const vacancySlotMap = new Map<string, { remaining: number; total: number }>();
    allVacancies.forEach((v) => {
      const remaining = getVacancyRemainingCapacity(v);
      const total = v.hcTotal ?? v.headcount ?? 1;
      if (v.storeId) {
        const curr = vacancySlotMap.get(v.storeId) ?? { remaining: 0, total: 0 };
        vacancySlotMap.set(v.storeId, {
          remaining: curr.remaining + remaining,
          total: curr.total + total,
        });
      }
      if (v.storeName) {
        const k = v.storeName.toLowerCase().trim();
        const curr = vacancySlotMap.get(k) ?? { remaining: 0, total: 0 };
        vacancySlotMap.set(k, {
          remaining: curr.remaining + remaining,
          total: curr.total + total,
        });
      }
    });

    return rawStores
      .map((st) => {
        const cap = capacityMap.get(st.id) || capacityMap.get(st.name.toLowerCase().trim());
        const vac = vacancySlotMap.get(st.id) || vacancySlotMap.get(st.name.toLowerCase().trim());

        let openSlots = cap ? cap.openVacancy : 0;
        let hcTotal = cap ? cap.plantillaRequired : 1;
        let hcFilled = cap ? cap.activeDeployed : 0;

        if (vac && vac.remaining > 0) {
          openSlots = Math.max(openSlots, vac.remaining);
          hcTotal = vac.total;
          hcFilled = Math.max(0, hcTotal - openSlots);
        }

        return {
          id: st.id,
          name: st.name,
          city: st.city,
          province: st.province,
          code: st.code,
          hcFilled,
          hcTotal,
          openSlots,
        };
      })
      .filter((st) => st.openSlots > 0 || st.hcFilled < st.hcTotal);
  }, [storesUnderAccountQuery.data, storeCapacityRows, allVacancies]);

  // Derived counts for KPI cards and badges
  const summaryData = summaryQuery.data;
  const activeCount = activeEmployees.length > 0 ? activeEmployees.length : (summaryData?.actual ?? 0);
  const onLeaveCount = onLeaveEmployees.length;
  const floatingCount = floatingEmployees.length;
  const deactivationCount = deactivationEmployees.length;
  const inactiveCount = inactiveEmployees.length;
  const vacancyCount = allVacancies.length > 0 ? allVacancies.length : (summaryData?.vacant ?? 0);

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
      : statusTab === "deactivation"
      ? filteredDeactivationEmployees
      : filteredInactiveEmployees;

  const currentTotalCount =
    mainView === "store" ? filteredStoreCapacityRows.length : currentTabRows.length;

  const paginatedRows = useMemo(() => {
    const start = (page - 1) * pageSize;
    return currentTabRows.slice(start, start + pageSize);
  }, [currentTabRows, page, pageSize]);

  const paginatedStoreRows = useMemo(() => {
    const start = (storePage - 1) * storePageSize;
    return filteredStoreCapacityRows.slice(start, start + storePageSize);
  }, [filteredStoreCapacityRows, storePage, storePageSize]);

  const hasActiveFilters = Boolean(search.trim() || areaCityFilter || assignmentType);

  // -------------------------------------------------------------------------
  // Handlers
  // -------------------------------------------------------------------------

  function getAccountSummary(accId: string) {
    if (accountMetricsQuery.data?.has(accId)) {
      return accountMetricsQuery.data.get(accId)!;
    }
    return { required: 0, actual: 0, hrProcess: 0, vacant: 0, fillRate: 0, leave: 0 };
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
    setInternalStatusTab("active");
    setPage(1);
    setStorePage(1);
    setSelectorGroupId("");
    setAccountSearch("");

    const params = new URLSearchParams(searchParams.toString());
    params.set("accountId", accId);
    params.delete("view");
    params.delete("status");
    router.push(`${pathname}?${params.toString()}`);
  }

  function handleBackToSelection() {
    setSearch("");
    setAreaCityFilter("");
    setAssignmentType("");
    setInternalStatusTab("active");
    setPage(1);
    setStorePage(1);

    const params = new URLSearchParams(searchParams.toString());
    params.delete("accountId");
    params.delete("status");
    router.push(`${pathname}?${params.toString()}`);
  }

  function handleResetFilters() {
    setSearch("");
    setAreaCityFilter("");
    setAssignmentType("");
    setPage(1);
    setStorePage(1);
  }

  // -------------------------------------------------------------------------
  // Workspace Guard & Module View Modes
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
                MOSES HQ Pool Management
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

  const selectedAccountName = allowedAccountsQuery.data?.find((a) => a.id === accountId)?.name ?? "Account";
  const showBackToSelection =
    hasAllScope || (allowedAccountsQuery.data && allowedAccountsQuery.data.length > 1);

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
            actionSlot={
              isHeadOrSuperAdmin(userRole) || isDataTeam(currentUser) || isOpsAmendmentRole(userRole) ? (
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => setIsCreateCoverageGroupOpen(true)}
                    className="inline-flex h-9 items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3.5 py-2 text-xs font-semibold text-text-primary shadow-xs hover:bg-surface-hover hover:border-border-strong transition cursor-pointer"
                  >
                    <Users2 className="h-3.5 w-3.5 shrink-0 text-brand-600" />
                    <span>+ Create Coverage Group</span>
                  </button>
                  {isHeadOrSuperAdmin(userRole) && (
                    <button
                      type="button"
                      onClick={() => setIsAddAccountOpen(true)}
                      className="inline-flex h-9 items-center gap-1.5 rounded-lg bg-brand-button px-3.5 py-2 text-xs font-semibold text-white shadow-xs hover:bg-brand-button-hover transition cursor-pointer"
                    >
                      <Plus className="h-3.5 w-3.5 shrink-0" />
                      <span>+ Add Account</span>
                    </button>
                  )}
                </div>
              ) : undefined
            }
          />
          <PlantillaAccountSelection
            allowedAccounts={allowedAccountsQuery.data ?? []}
            isLoading={allowedAccountsQuery.isLoading}
            isError={allowedAccountsQuery.isError}
            onRetry={() => {
              allowedAccountsQuery.refetch();
              accountMetricsQuery.refetch();
            }}
            accountSearch={accountSearch}
            onAccountSearchChange={setAccountSearch}
            uniqueGroups={uniqueGroups}
            effectiveSelectorGroupId={effectiveSelectorGroupId}
            onSelectorGroupIdChange={setSelectorGroupId}
            hasAllScope={hasAllScope}
            getAccountSummary={getAccountSummary}
            onSelectAccount={handleSelectAccount}
            activeMenuAccountId={activeMenuAccountId}
            setActiveMenuAccountId={setActiveMenuAccountId}
            onAbsorbClick={(acc) => setAbsorbModalAccount(acc)}
            onArchiveClick={(acc) => setArchiveModalAccount(acc)}
            canTransferGroup={isHeadOrSuperAdmin(userRole)}
            onTransferGroupClick={(acc) => setTransferGroupModalAccount(acc)}
          />
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
                    {formatAccountName(selectedAccountName)}
                  </span>
                </nav>
              }
              subtitle="Viewing: Store Employees • Managing roster allocations, capacity targets, and staffing governance."
              actionSlot={
                <div className="flex flex-wrap items-center gap-2">
                  {/* Main View Segmented Toggle: [ Employee View | Store View ] */}
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
                      <span>Employee View</span>
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setMainView("store");
                        setStorePage(1);
                      }}
                      className={`inline-flex h-full items-center gap-1.5 rounded-md px-2.5 text-xs font-semibold transition-colors cursor-pointer ${
                        mainView === "store"
                          ? "bg-surface-base text-text-primary shadow-xs"
                          : "text-text-muted hover:text-text-primary"
                      }`}
                    >
                      <Building2 className="h-3.5 w-3.5" />
                      <span>Store View</span>
                    </button>
                  </div>

                  {/* Primary button: + Request Roving HC (existing stores) */}
                  {canRequestAdjustment && (
                    <button
                      type="button"
                      onClick={() => setRequestHeadcountConfig({ mode: "roving_existing" })}
                      className="inline-flex h-8 items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover hover:border-border-strong transition cursor-pointer"
                      title="Request a roving headcount across 2–20 existing stores (use Store View -> Request HC for stationary)"
                    >
                      <Plus className="w-3.5 h-3.5 shrink-0 text-brand-600" />
                      <span>Request Roving HC</span>
                    </button>
                  )}

                  {/* Independent button: + Request New Store (Stationary or Roving Multi-Door) */}
                  {canRequestNewStore && (
                    <button
                      type="button"
                      onClick={() => setIsNewStoreModalOpen(true)}
                      className="inline-flex h-8 items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover hover:border-border-strong transition cursor-pointer"
                      title="Register a new opening store (Stationary or Roving multi-door)"
                    >
                      <Store className="w-3.5 h-3.5 shrink-0 text-brand-600" />
                      <span>Request New Store</span>
                    </button>
                  )}

                  {/* Action button: Create Coverage Group */}
                  {(isHeadOrSuperAdmin(userRole) || isDataTeam(currentUser) || isOpsAmendmentRole(userRole)) && (
                    <button
                      type="button"
                      onClick={() => setIsCreateCoverageGroupOpen(true)}
                      className="inline-flex h-8 items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover hover:border-border-strong transition cursor-pointer"
                      title="Create a roving coverage group cluster for this account"
                    >
                      <Users2 className="w-3.5 h-3.5 shrink-0 text-brand-600" />
                      <span>+ Coverage Group</span>
                    </button>
                  )}

                  {/* Action button: Absorb Employees */}
                  <button
                    type="button"
                    onClick={() =>
                      setAbsorbModalAccount({
                        id: accountId,
                        name: selectedAccountName,
                      })
                    }
                    className="inline-flex h-8 items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover hover:border-border-strong transition cursor-pointer"
                    title="Absorb and reassign employees to another billing account"
                  >
                    <ArrowRightLeft className="w-3.5 h-3.5 shrink-0 text-brand-600" />
                    <span>Absorb Employees</span>
                  </button>
                </div>
              }
            />
          </div>

          {/* 2. Filter Bar & Data Views Container */}
          <div className="flex flex-1 min-h-0 flex-col gap-2">
            <PlantillaFilterToolbar
              mainView={mainView}
              statusTab={statusTab}
              onSelectStatusTab={handleSelectStatusTab}
              activeCount={activeCount}
              onLeaveCount={onLeaveCount}
              vacancyCount={vacancyCount}
              totalVacanciesSlots={totalVacanciesSlots}
              floatingCount={floatingCount}
              deactivationCount={deactivationCount}
              inactiveCount={inactiveCount}
              displayView={displayView}
              onSetDisplayView={handleSetDisplayView}
              search={search}
              onSearchChange={(val) => {
                setSearch(val);
                setPage(1);
              }}
              areaCityFilter={areaCityFilter}
              onAreaCityFilterChange={(val) => {
                setAreaCityFilter(val);
                setPage(1);
              }}
              hierarchicalAreaOptions={hierarchicalAreaOptions}
              assignmentType={assignmentType}
              onAssignmentTypeChange={(val) => {
                setAssignmentType(val);
                setPage(1);
              }}
              hasActiveFilters={hasActiveFilters}
              onResetFilters={handleResetFilters}
            />

            {/* 3. Main Data Area: Employee 5 Tabs View OR Store Capacity Table */}
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
                    canRequestHeadcount={canRequestAdjustment}
                    onRequestHeadcount={(store) =>
                      setRequestHeadcountConfig({ mode: "stationary_locked", store })
                    }
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
                    onRowClick={handleNavigateToEmployee}
                    storeLookupMap={storeLookupMap}
                    onUpdateStatus={(emp) => {
                      setUpdateStatusTargetEmployee({
                        id: emp.id,
                        displayName: formatPersonName(emp.firstName, emp.lastName, null, emp.fullName) || emp.employeeNo,
                        employeeNo: emp.employeeNo,
                        currentStatus: emp.plantillaStatus || "Active",
                      });
                    }}
                  />
                ) : (
                  <div className="flex-1 min-h-0 overflow-y-auto pr-1">
                    <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
                      {(paginatedRows as PlantillaEmployeeListItem[]).map((row) => (
                        <EmployeeCard
                          key={row.id}
                          row={row}
                          onSelect={() => handleNavigateToEmployee(row.id)}
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
                ) : displayView === "table" ? (
                  <EmployeeOnLeaveTable
                    rows={paginatedRows as PlantillaEmployeeListItem[]}
                    activeCoverageMap={activeCoverageMap}
                    onRowClick={handleNavigateToEmployee}
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
                ) : (
                  <div className="flex-1 min-h-0 overflow-y-auto pr-1">
                    <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
                      {(paginatedRows as PlantillaEmployeeListItem[]).map((row) => (
                        <EmployeeOnLeaveCard
                          key={row.id}
                          row={row}
                          coverageItem={activeCoverageMap.get(row.id)}
                          onSelect={() => handleNavigateToEmployee(row.id)}
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
                      ))}
                    </div>
                  </div>
                )
              ) : statusTab === "vacancy" ? (
                /* Tab 3: Vacancy */
                filteredVacancies.length === 0 ? (
                  <EmptyTabState
                    hasActiveFilters={hasActiveFilters}
                    onResetFilters={handleResetFilters}
                    tabLabel="vacancies"
                  />
                ) : displayView === "table" ? (
                  <StoreVacancyTable
                    rows={paginatedRows as VacancyListItem[]}
                    onSelectVacancy={(v) => setSelectedVacancyId(v.id)}
                  />
                ) : (
                  <div className="flex-1 min-h-0 overflow-y-auto pr-1">
                    <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
                      {(paginatedRows as VacancyListItem[]).map((row) => (
                        <VacancyCard
                          key={row.id}
                          row={row}
                          onSelect={() => setSelectedVacancyId(row.id)}
                          storeLookupMap={storeLookupMap}
                        />
                      ))}
                    </div>
                  </div>
                )
              ) : statusTab === "floating" ? (
                /* Tab 4: Floating */
                filteredFloatingEmployees.length === 0 ? (
                  <EmptyTabState
                    hasActiveFilters={hasActiveFilters}
                    onResetFilters={handleResetFilters}
                    tabLabel="floating personnel"
                  />
                ) : displayView === "table" ? (
                  <EmployeeFloatingTable
                    rows={paginatedRows as PlantillaEmployeeListItem[]}
                    onRowClick={handleNavigateToEmployee}
                    storeLookupMap={storeLookupMap}
                    onAssignStore={(emp) => {
                      setAssignStoreTargetEmployee({
                        id: emp.id,
                        displayName: formatPersonName(emp.firstName, emp.lastName, null, emp.fullName) || emp.employeeNo,
                        employeeNo: emp.employeeNo,
                      });
                    }}
                  />
                ) : (
                  <div className="flex-1 min-h-0 overflow-y-auto pr-1">
                    <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
                      {(paginatedRows as PlantillaEmployeeListItem[]).map((row) => (
                        <EmployeeFloatingCard
                          key={row.id}
                          row={row}
                          onSelect={() => handleNavigateToEmployee(row.id)}
                          storeLookupMap={storeLookupMap}
                          onAssignStore={(emp) => {
                            setAssignStoreTargetEmployee({
                              id: emp.id,
                              displayName: formatPersonName(emp.firstName, emp.lastName, null, emp.fullName) || emp.employeeNo,
                              employeeNo: emp.employeeNo,
                            });
                          }}
                        />
                      ))}
                    </div>
                  </div>
                )
              ) : statusTab === "deactivation" ? (
                /* Tab 5: Deactivation */
                filteredDeactivationEmployees.length === 0 ? (
                  <EmptyTabState
                    hasActiveFilters={hasActiveFilters}
                    onResetFilters={handleResetFilters}
                    tabLabel="deactivation records"
                  />
                ) : displayView === "table" ? (
                  <EmployeeDeactivationTable
                    rows={paginatedRows as PlantillaEmployeeListItem[]}
                    onRowClick={handleNavigateToEmployee}
                    storeLookupMap={storeLookupMap}
                  />
                ) : (
                  <div className="flex-1 min-h-0 overflow-y-auto pr-1">
                    <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
                      {(paginatedRows as PlantillaEmployeeListItem[]).map((row) => (
                        <EmployeeDeactivationCard
                          key={row.id}
                          row={row}
                          onSelect={() => handleNavigateToEmployee(row.id)}
                          storeLookupMap={storeLookupMap}
                        />
                      ))}
                    </div>
                  </div>
                )
              ) : (
                /* Tab 6: Inactive (Resigned / AWOL / Terminated) */
                filteredInactiveEmployees.length === 0 ? (
                  <EmptyTabState
                    hasActiveFilters={hasActiveFilters}
                    onResetFilters={handleResetFilters}
                    tabLabel="inactive or separated personnel"
                  />
                ) : displayView === "table" ? (
                  <EmployeeInactiveTable
                    rows={paginatedRows as PlantillaEmployeeListItem[]}
                    onRowClick={handleNavigateToEmployee}
                    storeLookupMap={storeLookupMap}
                    onRequestDeactivation={(emp) => {
                      setDeactivationTargetEmployee({
                        id: emp.id,
                        displayName: formatPersonName(emp.firstName, emp.lastName, null, emp.fullName) || emp.employeeNo,
                        employeeNo: emp.employeeNo,
                        currentStatus: emp.plantillaStatus || emp.separationType || "Inactive",
                      });
                    }}
                  />
                ) : (
                  <div className="flex-1 min-h-0 overflow-y-auto pr-1">
                    <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
                      {(paginatedRows as PlantillaEmployeeListItem[]).map((row) => (
                        <EmployeeInactiveCard
                          key={row.id}
                          row={row}
                          onSelect={() => handleNavigateToEmployee(row.id)}
                          storeLookupMap={storeLookupMap}
                          onRequestDeactivation={(emp) => {
                            setDeactivationTargetEmployee({
                              id: emp.id,
                              displayName: formatPersonName(emp.firstName, emp.lastName, null, emp.fullName) || emp.employeeNo,
                              employeeNo: emp.employeeNo,
                              currentStatus: emp.plantillaStatus || emp.separationType || "Inactive",
                            });
                          }}
                        />
                      ))}
                    </div>
                  </div>
                )
              )}
            </div>

            {/* Pagination Controls */}
            {currentTotalCount > 0 && (
              <TablePagination
                page={mainView === "store" ? storePage : page}
                pageSize={mainView === "store" ? storePageSize : pageSize}
                totalCount={currentTotalCount}
                pageSizeOptions={mainView === "store" ? [15, 30, 50] : [10, 15, 25, 50]}
                onPageChange={(newPage) => {
                  if (mainView === "store") {
                    setStorePage(newPage);
                  } else {
                    handlePageChange(newPage);
                  }
                }}
                onPageSizeChange={(newPageSize) => {
                  if (mainView === "store") {
                    setStorePageSize(newPageSize);
                    setStorePage(1);
                  } else {
                    setPageSize(newPageSize);
                    setPage(1);
                  }
                }}
                isLoading={mainView === "store" ? (storesUnderAccountQuery.isLoading || employeeQuery.isLoading) : employeeQuery.isLoading}
                className="mt-2 pt-2 border-t border-border-default px-0 shrink-0"
              />
            )}
          </div>

          {/* Drawers & Modals Hub */}
          <PlantillaModalsHub
            selectedVacancyId={selectedVacancyId}
            onCloseVacancyDrawer={() => {
              setSelectedVacancyId(null);
              vacancyListQuery.refetch();
              summaryQuery.refetch();
            }}
            requestHeadcountConfig={requestHeadcountConfig}
            onCloseRequestHeadcount={() => setRequestHeadcountConfig(null)}
            accountId={accountId}
            selectedAccountName={selectedAccountName}
            onRequestHeadcountSuccess={() => {
              employeeQuery.refetch();
              summaryQuery.refetch();
              vacancyListQuery.refetch();
              showToast("Headcount requisition submitted for approval.", "success");
            }}
            isNewStoreModalOpen={isNewStoreModalOpen}
            onCloseNewStoreModal={() => setIsNewStoreModalOpen(false)}
            onNewStoreSuccess={(res) => {
              showToast(
                `New Store request submitted for "${res.storeName}" (pending review).`,
                "success"
              );
            }}
            relieverTargetEmployee={relieverTargetEmployee}
            onCloseAssignReliever={() => setRelieverTargetEmployee(null)}
            onAssignRelieverSuccess={() => {
              employeeQuery.refetch();
              coverageQuery.refetch();
              summaryQuery.refetch();
            }}
            returnToActiveTarget={returnToActiveTarget}
            onCloseReturnToActive={() => setReturnToActiveTarget(null)}
            onReturnToActiveSuccess={() => {
              employeeQuery.refetch();
              coverageQuery.refetch();
              summaryQuery.refetch();
            }}
            assignStoreTargetEmployee={assignStoreTargetEmployee}
            onCloseAssignStore={() => setAssignStoreTargetEmployee(null)}
            storesWithAvailableSlots={storesWithAvailableSlots}
            vacantStoreIds={vacantStoreIds}
            onAssignStoreSuccess={() => {
              employeeQuery.refetch();
              summaryQuery.refetch();
              vacancyListQuery.refetch();
            }}
            updateStatusTargetEmployee={updateStatusTargetEmployee}
            onCloseUpdateStatus={() => setUpdateStatusTargetEmployee(null)}
            onUpdateStatusSuccess={() => {
              employeeQuery.refetch();
              summaryQuery.refetch();
              vacancyListQuery.refetch();
            }}
            onNavigateStatusTab={(tab) => {
              handleSelectStatusTab(tab);
            }}
            deactivationTargetEmployee={deactivationTargetEmployee}
            onCloseDeactivation={() => setDeactivationTargetEmployee(null)}
            onDeactivationSuccess={() => {
              employeeQuery.refetch();
              summaryQuery.refetch();
            }}
            isAddAccountOpen={isAddAccountOpen}
            onCloseAddAccount={() => setIsAddAccountOpen(false)}
            onAddAccountSuccess={(createdName) =>
              showToast(`Account "${createdName}" created successfully.`, "success")
            }
            isCreateCoverageGroupOpen={isCreateCoverageGroupOpen}
            onCloseCreateCoverageGroup={() => setIsCreateCoverageGroupOpen(false)}
            onCreateCoverageGroupSuccess={(code) =>
              showToast(`Coverage Group "${code || "Cluster"}" created successfully.`, "success")
            }
            archiveModalAccount={archiveModalAccount}
            onCloseArchiveModal={() => setArchiveModalAccount(null)}
            onRouteArchiveToAbsorption={(acc) => {
              setArchiveModalAccount(null);
              setAbsorbModalAccount(acc);
            }}
            onArchiveSuccess={(name) =>
              showToast(
                `Archive request submitted for "${name}". Pending Super Admin approval.`,
                "success",
              )
            }
            absorbModalAccount={absorbModalAccount}
            onCloseAbsorbModal={() => setAbsorbModalAccount(null)}
            onAbsorbSuccess={(result) => {
              if (result.direct) {
                showToast(
                  `Successfully absorbed ${result.count} employee${
                    result.count === 1 ? "" : "s"
                  } into ${result.targetAccountName}.`,
                  "success",
                );
              } else {
                showToast(
                  `Absorption request for ${result.count} employee${
                    result.count === 1 ? "" : "s"
                  } submitted for SA/HA approval.`,
                  "info",
                );
              }
            }}
            transferGroupModalAccount={transferGroupModalAccount}
            onCloseTransferGroupModal={() => setTransferGroupModalAccount(null)}
            onTransferGroupSuccess={(accountName, targetGroupName) =>
              showToast(
                `Account "${accountName}" successfully transferred to ${targetGroupName}.`,
                "success",
              )
            }
            uniqueGroups={uniqueGroups}
            toastMessage={toastMessage}
            toastVariant={toastVariant}
            onCloseToast={() => setToastMessage(null)}
          />
        </>
      )}
    </div>
  );
}
