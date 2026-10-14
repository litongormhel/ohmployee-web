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
  totalHrEmplocPending: number;
  totalActivePlantilla: number;
  understaffedStores: number;
  activeSlaBreaches: number;
  // Security KPIs — null when backend gates by caller role
  pendingApprovals: number | null;
  securityEventCount: number | null;
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
    totalHrEmplocPending: asCount(row.total_hr_emploc_pending),
    totalActivePlantilla: asCount(row.total_active_plantilla),
    understaffedStores: asCount(row.understaffed_stores),
    activeSlaBreaches: asCount(row.active_sla_breaches),
    // Security KPIs gated by backend role check
    pendingApprovals: asNullableCount(row.pending_approvals),
    securityEventCount: asNullableCount(row.security_event_count),
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

