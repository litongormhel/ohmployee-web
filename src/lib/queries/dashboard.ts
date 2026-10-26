import type { PostgrestError } from "@supabase/supabase-js";
import { useQuery, type UseQueryResult } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/**
 * Operational KPIs returned by fn_dashboard_metrics().
 * Security-gated fields are null when the backend role check restricts access.
 */
export type DashboardMetrics = {
  // Operational (all authorized web roles)
  totalOpenVacancies: number;
  unassignedVacancies: number;
  assignedVacancies: number;
  totalHrEmplocPending: number;
  totalActivePlantilla: number;
  understaffedStores: number;
  activeSlaBreaches: number;
  // Security KPIs — null when backend gates by caller role
  pendingApprovals: number | null;
  adminSecurityApprovals: number | null;
  securityEventCount: number | null;
  ghostEmployeeCount: number;
};

/**
 * Operational analytics returned by fn_dashboard_operational_analytics().
 */
export type DashboardOperationalAnalytics = {
  pipelineTotal: number;
  hiresThisMonth: number;
  separationsThisMonth: number;
  avgFillRate: number | null;
};

// ---------------------------------------------------------------------------
// Error class
// ---------------------------------------------------------------------------

export type DashboardDataErrorKind = "access_denied" | "retryable";

export class DashboardDataError extends Error {
  kind: DashboardDataErrorKind;

  constructor(kind: DashboardDataErrorKind, message: string) {
    super(message);
    this.name = "DashboardDataError";
    this.kind = kind;
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

type DashboardRpcRow = Record<string, unknown>;

function asNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function asCount(value: unknown): number {
  return Math.max(0, Math.trunc(asNumber(value) ?? 0));
}

function asNullableCount(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  const n = asNumber(value);
  return n === null ? null : Math.max(0, Math.trunc(n));
}

function asNullableNumber(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  return asNumber(value);
}

function asObject(value: unknown): DashboardRpcRow {
  return value && !Array.isArray(value) && typeof value === "object"
    ? (value as DashboardRpcRow)
    : {};
}

function getErrorKind(error: PostgrestError): DashboardDataErrorKind {
  const combined = `${error.code ?? ""} ${error.message ?? ""} ${error.details ?? ""}`
    .toLowerCase()
    .trim();

  if (
    combined.includes("permission denied") ||
    combined.includes("not authorized") ||
    combined.includes("unauthorized") ||
    combined.includes("forbidden") ||
    combined.includes("rls") ||
    error.code === "42501"
  ) {
    return "access_denied";
  }

  return "retryable";
}

function throwDashboardError(error: PostgrestError): never {
  throw new DashboardDataError(getErrorKind(error), error.message);
}

// ---------------------------------------------------------------------------
// Normalizers
// ---------------------------------------------------------------------------

function normalizeMetrics(data: unknown): DashboardMetrics {
  const row = Array.isArray(data) ? asObject(data[0]) : asObject(data);

  return {
    totalOpenVacancies: asCount(row.total_open_vacancies),
    unassignedVacancies: asCount(row.unassigned_vacancies),
    assignedVacancies: asCount(row.assigned_vacancies),
    totalHrEmplocPending: asCount(row.total_hr_emploc_pending),
    totalActivePlantilla: asCount(row.total_active_plantilla),
    understaffedStores: asCount(row.understaffed_stores),
    activeSlaBreaches: asCount(row.active_sla_breaches),
    // Security KPIs gated by backend role check
    pendingApprovals: asNullableCount(row.pending_approvals),
    adminSecurityApprovals: asNullableCount(row.admin_security_approvals),
    securityEventCount: asNullableCount(row.security_event_count),
    ghostEmployeeCount: asCount(row.ghost_employee_count),
  };
}

function normalizeOperationalAnalytics(data: unknown): DashboardOperationalAnalytics {
  const row = Array.isArray(data) ? asObject(data[0]) : asObject(data);

  return {
    pipelineTotal: asCount(row.pipeline_total),
    hiresThisMonth: asCount(row.hires_this_month),
    separationsThisMonth: asCount(row.separations_this_month),
    avgFillRate: asNullableNumber(row.avg_fill_rate),
  };
}

// ---------------------------------------------------------------------------
// Public RPC wrappers
// ---------------------------------------------------------------------------

export type DashboardFilterParams = {
  accountId?: string | null;
  groupId?: string | null;
};

export async function getDashboardMetrics(
  params?: DashboardFilterParams
): Promise<DashboardMetrics> {
  const supabase = createClient();
  const rpcArgs = params
    ? {
        p_account_id: params.accountId ?? null,
        p_group_id: params.groupId ?? null,
      }
    : undefined;
  const { data, error } = await supabase.rpc("fn_dashboard_metrics", rpcArgs);

  if (error) {
    throwDashboardError(error);
  }

  return normalizeMetrics(data);
}

export async function getDashboardOperationalAnalytics(
  params?: DashboardFilterParams
): Promise<DashboardOperationalAnalytics> {
  const supabase = createClient();
  const rpcArgs = params
    ? {
        p_account_id: params.accountId ?? null,
        p_group_id: params.groupId ?? null,
      }
    : undefined;
  const { data, error } = await supabase.rpc("fn_dashboard_operational_analytics", rpcArgs);

  if (error) {
    throwDashboardError(error);
  }

  return normalizeOperationalAnalytics(data);
}

// ---------------------------------------------------------------------------
// React Query hooks
// ---------------------------------------------------------------------------

export function useDashboardMetrics(
  params?: DashboardFilterParams
): UseQueryResult<DashboardMetrics, DashboardDataError> {
  return useQuery({
    queryKey: ["dashboard", "metrics", params?.accountId ?? null, params?.groupId ?? null],
    queryFn: () => getDashboardMetrics(params),
  });
}

export function useDashboardOperationalAnalytics(
  params?: DashboardFilterParams
): UseQueryResult<DashboardOperationalAnalytics, DashboardDataError> {
  return useQuery({
    queryKey: [
      "dashboard",
      "operational-analytics",
      params?.accountId ?? null,
      params?.groupId ?? null,
    ],
    queryFn: () => getDashboardOperationalAnalytics(params),
  });
}

// ---------------------------------------------------------------------------
// SLA Breaches & Understaffed Stores Live Queries
// ---------------------------------------------------------------------------

export interface DashboardSlaBreachItem {
  id: string;
  storeName: string;
  category: "Vacancy SLA" | "Movement SLA" | "Deactivation SLA";
  group: string;
  owner: string;
  breachCount: number;
  aging: string;
  actionLabel: string;
  actionHref: string;
}

export async function fetchDashboardSlaBreaches(): Promise<DashboardSlaBreachItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("sla_breach_logs")
    .select("id, account, breach_type, days_elapsed, vcode, created_at")
    .or("is_archived.is.null,is_archived.eq.false")
    .is("suppressed_by_batch_id", null)
    .order("days_elapsed", { ascending: false })
    .limit(30);

  if (error || !data) return [];

  return data.map((b) => {
    const isMovement =
      b.breach_type?.includes("movement") || b.breach_type?.includes("transfer");
    const isDeac =
      b.breach_type?.includes("deactivation") || b.breach_type?.includes("inactive");
    const category: "Vacancy SLA" | "Movement SLA" | "Deactivation SLA" = isMovement
      ? "Movement SLA"
      : isDeac
      ? "Deactivation SLA"
      : "Vacancy SLA";
    const days = b.days_elapsed ?? 0;

    return {
      id: b.id,
      storeName: `${b.account ?? "Store"} (${b.vcode ?? "General Staff"})`,
      category,
      group: b.account ?? "Retail Scope",
      owner: "Operations OM",
      breachCount: 1,
      aging: `${days}d`,
      actionLabel: isDeac ? "Review Deactivations" : isMovement ? "Review Movements" : "Inspect Lane",
      actionHref: isDeac || isMovement ? "/approvals" : "/vacancy",
    };
  });
}

export function useDashboardSlaBreaches() {
  return useQuery({
    queryKey: ["dashboard", "sla-breaches"],
    queryFn: fetchDashboardSlaBreaches,
    staleTime: 30000,
  });
}

export interface DashboardUnderstaffedStoreItem {
  id: string;
  storeName: string;
  group: string;
  actualHc: number;
  budgetedHc: number;
  openVacancies: number;
  assignedHrco: string;
  coveragePct: number;
}

export async function fetchDashboardUnderstaffedStores(): Promise<DashboardUnderstaffedStoreItem[]> {
  const supabase = createClient();
  const { data: vacancies, error } = await supabase
    .from("vacancies")
    .select(`
      id,
      store_id,
      hrco_name,
      stores (
        id,
        store_name,
        account_id,
        accounts (
          account_name,
          groups (
            group_name
          )
        )
      )
    `)
    .eq("status", "Open")
    .eq("is_archived", false)
    .is("suppressed_by_batch_id", null)
    .is("deleted_at", null)
    .not("store_id", "is", null);

  if (error || !vacancies) return [];

  const storeMap = new Map<string, DashboardUnderstaffedStoreItem>();

  type StoreRelation = {
    id?: string;
    store_name?: string | null;
    accounts?: {
      account_name?: string | null;
      groups?: {
        group_name?: string | null;
      } | null;
    } | null;
  } | null;

  for (const v of vacancies) {
    const s = v.stores as StoreRelation;
    if (!s || !s.id) continue;
    const storeId = s.id;
    const storeName = s.store_name ?? "Store";
    const acc = s.accounts;
    const groupName =
      acc?.groups?.group_name ?? acc?.account_name ?? "Retail Group";
    const hrco = v.hrco_name && v.hrco_name.trim().length > 0 ? v.hrco_name.trim() : "Unassigned";

    if (!storeMap.has(storeId)) {
      storeMap.set(storeId, {
        id: storeId,
        storeName,
        group: groupName,
        actualHc: 0,
        budgetedHc: 0,
        openVacancies: 0,
        assignedHrco: hrco,
        coveragePct: 0,
      });
    }

    const item = storeMap.get(storeId)!;
    item.openVacancies += 1;
    item.budgetedHc = item.actualHc + item.openVacancies;
    item.coveragePct =
      item.budgetedHc > 0 ? Math.round((item.actualHc / item.budgetedHc) * 100) : 0;
  }

  return Array.from(storeMap.values());
}

export function useDashboardUnderstaffedStores() {
  return useQuery({
    queryKey: ["dashboard", "understaffed-stores"],
    queryFn: fetchDashboardUnderstaffedStores,
    staleTime: 30000,
  });
}

