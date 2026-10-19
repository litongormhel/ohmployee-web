import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

// ---------------------------------------------------------------------------
// TypeScript Interfaces
// ---------------------------------------------------------------------------

export interface WfAnalyticsFilter {
  accountId?: string | null;
  dateFrom?: string | null;
  dateTo?: string | null;
}

export interface WfPoolTypeBreakdown {
  poolTypeId: string;
  poolTypeName: string;
  poolTypeCode?: string | null;
  total: number;
  available: number;
  deployed: number;
  inReview: number;
  inactive: number;
}

export interface WfPoolOverview {
  total: number;
  available: number;
  deployed: number;
  reserved: number;
  inReview: number;
  inactive: number;
  longTermDeployments: number;
  pendingCoverageRequests: number;
  byPoolType: WfPoolTypeBreakdown[];
}

export interface WfLoadDistribution {
  low: number;
  medium: number;
  high: number;
  critical: number;
}

export interface WfAgingBuckets {
  days0to7: number;
  days8to14: number;
  days15to30: number;
  days30plus: number;
}

export interface WfDeploymentAnalytics {
  activeDeploymentCount: number;
  multiStoreCount: number;
  avgStoresPerReliever: number;
  highLoadCount: number;
  overdueCount: number;
  avgDeploymentDays?: number | null;
  loadDistribution: WfLoadDistribution;
  agingBuckets: WfAgingBuckets;
}

export interface WfPoolTypeCount {
  poolType: string;
  count: number;
}

export interface WfCoverageDemandAnalytics {
  totalRequests: number;
  pending: number;
  approved: number;
  rejected: number;
  rejectionRatePct: number;
  avgRequestAgeDays?: number | null;
  escalatedCount: number;
  criticalSlaCount: number;
  topRequestingPools: WfPoolTypeCount[];
}

export interface WfConversionAnalytics {
  total: number;
  pending: number;
  approved: number;
  rejected: number;
  approvalRatePct: number;
  rejectionRatePct: number;
  avgDaysToDecision?: number | null;
}

export interface WfSlotReviewAnalytics {
  total: number;
  pending: number;
  resolved: number;
  reopened: number;
  staleCount: number;
  avgResolutionDays?: number | null;
}

export interface WfHealthSummary {
  overdueDeployments: number;
  longTermAssignments: number;
  highLoadRelievers: number;
  criticalLoadRelievers: number;
  escalatedRequests: number;
  staleSlotReviews: number;
  pendingConversions: number;
  totalPoolEmployees: number;
  healthScore: number;
}

export interface WfExecutiveSummary {
  totalPoolEmployees: number;
  utilizationPct: number;
  availabilityPct: number;
  poolCapacityPct: number;
  coverageEfficiencyPct: number;
  activeDeployments: number;
  pendingRequests: number;
  escalatedRequests: number;
  pendingConversions: number;
  healthScore: number;
}

export interface ImportIncident {
  id: string;
  batchId?: string | null;
  severity: string;
  incidentType: string;
  message: string;
  isResolved: boolean;
  resolvedAt?: string | null;
  createdAt: string;
  metadata?: Record<string, unknown> | null;
}

export interface ImportIncidentFeed {
  total: number;
  critical: number;
  warning: number;
  info: number;
  unresolved: number;
  incidents: ImportIncident[];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function buildFilterParams(filter?: WfAnalyticsFilter): Record<string, unknown> {
  const params: Record<string, unknown> = {};
  if (filter?.accountId) {
    params.p_account_id = filter.accountId;
  }
  if (filter?.dateFrom) {
    params.p_date_from = filter.dateFrom.substring(0, 10);
  }
  if (filter?.dateTo) {
    params.p_date_to = filter.dateTo.substring(0, 10);
  }
  return params;
}

function buildAccountParam(filter?: WfAnalyticsFilter): Record<string, unknown> {
  const params: Record<string, unknown> = {};
  if (filter?.accountId) {
    params.p_account_id = filter.accountId;
  }
  return params;
}

// ---------------------------------------------------------------------------
// Query Functions
// ---------------------------------------------------------------------------

export async function fetchWorkforcePoolOverview(filter?: WfAnalyticsFilter): Promise<WfPoolOverview> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_workforce_pool_overview", buildAccountParam(filter));
  if (error) {
    console.error("[WorkforceAnalytics] fn_workforce_pool_overview error:", error);
    throw error;
  }

  const raw = (data ?? {}) as Record<string, unknown>;
  const totals = (raw.totals ?? {}) as Record<string, unknown>;
  const byTypeRaw = (raw.by_pool_type ?? []) as Record<string, unknown>[];

  const byPoolType: WfPoolTypeBreakdown[] = byTypeRaw.map((m) => ({
    poolTypeId: String(m.pool_type_id ?? ""),
    poolTypeName: String(m.pool_type_name ?? ""),
    poolTypeCode: m.pool_type_code ? String(m.pool_type_code) : null,
    total: Number(m.total ?? 0),
    available: Number(m.available ?? 0),
    deployed: Number(m.deployed ?? 0),
    inReview: Number(m.in_review ?? 0),
    inactive: Number(m.inactive ?? 0),
  }));

  return {
    total: Number(totals.total ?? 0),
    available: Number(totals.available ?? 0),
    deployed: Number(totals.deployed ?? 0),
    reserved: Number(totals.reserved ?? 0),
    inReview: Number(totals.in_review ?? 0),
    inactive: Number(totals.inactive ?? 0),
    longTermDeployments: Number(totals.long_term_deployments ?? 0),
    pendingCoverageRequests: Number(totals.pending_coverage_requests ?? 0),
    byPoolType,
  };
}

export async function fetchWorkforceDeploymentAnalytics(filter?: WfAnalyticsFilter): Promise<WfDeploymentAnalytics> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_workforce_deployment_analytics", buildFilterParams(filter));
  if (error) {
    console.error("[WorkforceAnalytics] fn_workforce_deployment_analytics error:", error);
    throw error;
  }

  const m = (data ?? {}) as Record<string, unknown>;
  const ld = (m.load_distribution ?? {}) as Record<string, unknown>;
  const ab = (m.aging_buckets ?? {}) as Record<string, unknown>;

  return {
    activeDeploymentCount: Number(m.active_deployment_count ?? 0),
    multiStoreCount: Number(m.multi_store_count ?? 0),
    avgStoresPerReliever: Number(m.avg_stores_per_reliever ?? 0),
    highLoadCount: Number(m.high_load_count ?? 0),
    overdueCount: Number(m.overdue_count ?? 0),
    avgDeploymentDays: m.avg_deployment_days != null ? Number(m.avg_deployment_days) : null,
    loadDistribution: {
      low: Number(ld.low ?? 0),
      medium: Number(ld.medium ?? 0),
      high: Number(ld.high ?? 0),
      critical: Number(ld.critical ?? 0),
    },
    agingBuckets: {
      days0to7: Number(ab.days_0_7 ?? 0),
      days8to14: Number(ab.days_8_14 ?? 0),
      days15to30: Number(ab.days_15_30 ?? 0),
      days30plus: Number(ab.days_30_plus ?? 0),
    },
  };
}

export async function fetchWorkforceCoverageDemandAnalytics(filter?: WfAnalyticsFilter): Promise<WfCoverageDemandAnalytics> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_workforce_coverage_demand_analytics", buildFilterParams(filter));
  if (error) {
    console.error("[WorkforceAnalytics] fn_workforce_coverage_demand_analytics error:", error);
    throw error;
  }

  const m = (data ?? {}) as Record<string, unknown>;
  const poolsRaw = (m.top_requesting_pools ?? []) as Record<string, unknown>[];

  return {
    totalRequests: Number(m.total_requests ?? 0),
    pending: Number(m.pending ?? 0),
    approved: Number(m.approved ?? 0),
    rejected: Number(m.rejected ?? 0),
    rejectionRatePct: Number(m.rejection_rate_pct ?? 0),
    avgRequestAgeDays: m.avg_request_age_days != null ? Number(m.avg_request_age_days) : null,
    escalatedCount: Number(m.escalated_count ?? 0),
    criticalSlaCount: Number(m.critical_sla_count ?? 0),
    topRequestingPools: poolsRaw.map((p) => ({
      poolType: String(p.pool_type ?? ""),
      count: Number(p.count ?? 0),
    })),
  };
}

export async function fetchWorkforceConversionAnalytics(filter?: WfAnalyticsFilter): Promise<WfConversionAnalytics> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_workforce_conversion_analytics", buildFilterParams(filter));
  if (error) {
    console.error("[WorkforceAnalytics] fn_workforce_conversion_analytics error:", error);
    throw error;
  }

  const m = (data ?? {}) as Record<string, unknown>;
  return {
    total: Number(m.total ?? 0),
    pending: Number(m.pending ?? 0),
    approved: Number(m.approved ?? 0),
    rejected: Number(m.rejected ?? 0),
    approvalRatePct: Number(m.approval_rate_pct ?? 0),
    rejectionRatePct: Number(m.rejection_rate_pct ?? 0),
    avgDaysToDecision: m.avg_days_to_decision != null ? Number(m.avg_days_to_decision) : null,
  };
}

export async function fetchWorkforceSlotReviewAnalytics(filter?: WfAnalyticsFilter): Promise<WfSlotReviewAnalytics> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_workforce_slot_review_analytics", buildAccountParam(filter));
  if (error) {
    console.error("[WorkforceAnalytics] fn_workforce_slot_review_analytics error:", error);
    throw error;
  }

  const m = (data ?? {}) as Record<string, unknown>;
  return {
    total: Number(m.total ?? 0),
    pending: Number(m.pending ?? 0),
    resolved: Number(m.resolved ?? 0),
    reopened: Number(m.reopened ?? 0),
    staleCount: Number(m.stale_count ?? 0),
    avgResolutionDays: m.avg_resolution_days != null ? Number(m.avg_resolution_days) : null,
  };
}

export async function fetchWorkforceHealthSummary(filter?: WfAnalyticsFilter): Promise<WfHealthSummary> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_workforce_health_summary", buildAccountParam(filter));
  if (error) {
    console.error("[WorkforceAnalytics] fn_workforce_health_summary error:", error);
    throw error;
  }

  const m = (data ?? {}) as Record<string, unknown>;
  return {
    overdueDeployments: Number(m.overdue_deployments ?? 0),
    longTermAssignments: Number(m.long_term_assignments ?? 0),
    highLoadRelievers: Number(m.high_load_relievers ?? 0),
    criticalLoadRelievers: Number(m.critical_load_relievers ?? 0),
    escalatedRequests: Number(m.escalated_requests ?? 0),
    staleSlotReviews: Number(m.stale_slot_reviews ?? 0),
    pendingConversions: Number(m.pending_conversions ?? 0),
    totalPoolEmployees: Number(m.total_pool_employees ?? 0),
    healthScore: Number(m.health_score ?? 100),
  };
}

export async function fetchWorkforceExecutiveSummary(filter?: WfAnalyticsFilter): Promise<WfExecutiveSummary> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_workforce_executive_summary", buildAccountParam(filter));
  if (error) {
    console.error("[WorkforceAnalytics] fn_workforce_executive_summary error:", error);
    throw error;
  }

  const m = (data ?? {}) as Record<string, unknown>;
  return {
    totalPoolEmployees: Number(m.total_pool_employees ?? 0),
    utilizationPct: Number(m.utilization_pct ?? 0),
    availabilityPct: Number(m.availability_pct ?? 0),
    poolCapacityPct: Number(m.pool_capacity_pct ?? 0),
    coverageEfficiencyPct: Number(m.coverage_efficiency_pct ?? 0),
    activeDeployments: Number(m.active_deployments ?? 0),
    pendingRequests: Number(m.pending_requests ?? 0),
    escalatedRequests: Number(m.escalated_requests ?? 0),
    pendingConversions: Number(m.pending_conversions ?? 0),
    healthScore: Number(m.health_score ?? 100),
  };
}

export async function fetchPlantillaImportIncidents(days = 7): Promise<ImportIncidentFeed> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_plantilla_import_incidents", { p_days: days });
  if (error) {
    console.error("[WorkforceAnalytics] get_plantilla_import_incidents error:", error);
    return {
      total: 0,
      critical: 0,
      warning: 0,
      info: 0,
      unresolved: 0,
      incidents: [],
    };
  }

  const m = (data ?? {}) as Record<string, unknown>;
  const listRaw = (m.incidents ?? []) as Record<string, unknown>[];

  return {
    total: Number(m.total ?? 0),
    critical: Number(m.critical ?? 0),
    warning: Number(m.warning ?? 0),
    info: Number(m.info ?? 0),
    unresolved: Number(m.unresolved ?? 0),
    incidents: listRaw.map((i) => ({
      id: String(i.id ?? ""),
      batchId: i.batch_id ? String(i.batch_id) : null,
      severity: String(i.severity ?? "info"),
      incidentType: String(i.incident_type ?? ""),
      message: String(i.message ?? ""),
      isResolved: Boolean(i.is_resolved),
      resolvedAt: i.resolved_at ? String(i.resolved_at) : null,
      createdAt: String(i.created_at ?? ""),
      metadata: i.metadata && typeof i.metadata === "object" ? (i.metadata as Record<string, unknown>) : null,
    })),
  };
}

// ---------------------------------------------------------------------------
// TanStack Query Hooks
// ---------------------------------------------------------------------------

export function useWorkforcePoolOverview(filter?: WfAnalyticsFilter) {
  return useQuery({
    queryKey: ["workforce-analytics", "overview", filter],
    queryFn: () => fetchWorkforcePoolOverview(filter),
    staleTime: 30000,
  });
}

export function useWorkforceDeploymentAnalytics(filter?: WfAnalyticsFilter) {
  return useQuery({
    queryKey: ["workforce-analytics", "deployment", filter],
    queryFn: () => fetchWorkforceDeploymentAnalytics(filter),
    staleTime: 30000,
  });
}

export function useWorkforceCoverageDemandAnalytics(filter?: WfAnalyticsFilter) {
  return useQuery({
    queryKey: ["workforce-analytics", "coverage-demand", filter],
    queryFn: () => fetchWorkforceCoverageDemandAnalytics(filter),
    staleTime: 30000,
  });
}

export function useWorkforceConversionAnalytics(filter?: WfAnalyticsFilter) {
  return useQuery({
    queryKey: ["workforce-analytics", "conversion", filter],
    queryFn: () => fetchWorkforceConversionAnalytics(filter),
    staleTime: 30000,
  });
}

export function useWorkforceSlotReviewAnalytics(filter?: WfAnalyticsFilter) {
  return useQuery({
    queryKey: ["workforce-analytics", "slot-review", filter],
    queryFn: () => fetchWorkforceSlotReviewAnalytics(filter),
    staleTime: 30000,
  });
}

export function useWorkforceHealthSummary(filter?: WfAnalyticsFilter) {
  return useQuery({
    queryKey: ["workforce-analytics", "health", filter],
    queryFn: () => fetchWorkforceHealthSummary(filter),
    staleTime: 30000,
  });
}

export function useWorkforceExecutiveSummary(filter?: WfAnalyticsFilter) {
  return useQuery({
    queryKey: ["workforce-analytics", "executive", filter],
    queryFn: () => fetchWorkforceExecutiveSummary(filter),
    staleTime: 30000,
  });
}

export function usePlantillaImportIncidents(days = 7) {
  return useQuery({
    queryKey: ["workforce-analytics", "import-incidents", days],
    queryFn: () => fetchPlantillaImportIncidents(days),
    staleTime: 30000,
  });
}
