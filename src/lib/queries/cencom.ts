import { useQuery } from "@tanstack/react-query";
import type { PostgrestError } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";

// ---------------------------------------------------------------------------
// Error Handling & Types
// ---------------------------------------------------------------------------

export type CencomDataErrorKind = "access_denied" | "retryable";

export class CencomDataError extends Error {
  kind: CencomDataErrorKind;

  constructor(kind: CencomDataErrorKind, message: string) {
    super(message);
    this.name = "CencomDataError";
    this.kind = kind;
  }
}

function getErrorKind(error: PostgrestError): CencomDataErrorKind {
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

function throwCencomError(error: PostgrestError): never {
  throw new CencomDataError(getErrorKind(error), error.message);
}

// ---------------------------------------------------------------------------
// Slot Authority Normalization
// ---------------------------------------------------------------------------

export type NormalizedSlotAuthority = {
  required: number;
  actual: number;
  vacant: number;
  mfr: number; // 0.0 to 1.0
  mfrPercent: number; // 0 to 100
  isNormalized: boolean;
  healthStatus: "healthy" | "at_risk" | "critical";
};

/**
 * Enforces the Plantilla Slot Authority and Mathematical Coherence rules:
 *   If Actual >= Required => Vacant = 0, Required = Actual, MFR = 100% (1.0)
 *
 * Specific slot authority overrides:
 *   - Group 1 (BANKO): Authorized capacity is fully filled (12/12). Legacy unclosed ghost
 *     vacancies must not report false openings or depress MFR.
 *   - Group 2 (THREE): Authorized capacity is fully filled (4/4). Legacy unclosed ghost
 *     vacancies must not report false openings or depress MFR.
 */
export function normalizeSlotAuthorityMetrics(
  rawRequired: number,
  rawActual: number,
  rawVacant: number,
  options?: {
    groupCode?: string | null;
    groupName?: string | null;
    accountNames?: string[];
  }
): NormalizedSlotAuthority {
  const actual = Math.max(0, Math.round(Number(rawActual) || 0));
  let required = Math.max(0, Math.round(Number(rawRequired) || 0));
  let vacant = Math.max(0, Math.round(Number(rawVacant) || 0));

  const code = (options?.groupCode ?? "").trim().toUpperCase();
  const name = (options?.groupName ?? "").trim().toUpperCase();
  const accounts = (options?.accountNames ?? []).map((a) => a.trim().toUpperCase());

  const isGroup1 = code === "G1" || name.includes("GROUP 1") || accounts.includes("BANKO");
  const isGroup2 = code === "G2" || name.includes("GROUP 2") || accounts.includes("THREE");

  let isNormalized = false;

  if (isGroup1 && actual >= 12 && vacant > 0) {
    vacant = 0;
    required = actual;
    isNormalized = true;
  } else if (isGroup2 && actual >= 4 && vacant > 0) {
    vacant = 0;
    required = actual;
    isNormalized = true;
  } else if (vacant > 0 && actual > 0 && required > 0 && actual >= required) {
    vacant = 0;
    required = actual;
    isNormalized = true;
  } else if (actual >= required && required > 0) {
    vacant = 0;
    required = actual;
    isNormalized = true;
  } else if (required === 0 && actual > 0 && vacant === 0) {
    required = actual;
    isNormalized = true;
  }

  let mfr = 0;
  if (required === 0) {
    mfr = 0;
  } else if (vacant === 0 && actual >= required) {
    mfr = 1.0;
  } else {
    mfr = Math.min(1.0, Math.max(0, actual / required));
  }

  const mfrPercent = Math.round(mfr * 1000) / 10;

  let healthStatus: "healthy" | "at_risk" | "critical" = "critical";
  if ((vacant === 0 && actual >= required && required > 0) || mfr >= 1.0) {
    healthStatus = "healthy";
  } else if (mfr >= 0.9) {
    healthStatus = "at_risk";
  } else {
    healthStatus = "critical";
  }

  return {
    required,
    actual,
    vacant,
    mfr,
    mfrPercent,
    isNormalized,
    healthStatus,
  };
}

// ---------------------------------------------------------------------------
// Data Models
// ---------------------------------------------------------------------------

export type CencomAllocationKpi = {
  required: number;
  actual: number;
  vacant: number;
  mfr: number;
  mfrPercent: number;
  projectedMfr: number;
  projectedMfrPercent: number;
  pipelineCount: number;
  openHc: number;
  slotVacantHc: number;
  filledHc: number;
  healthStatus: "healthy" | "at_risk" | "critical";
  isNormalized: boolean;
};

export type CencomGroupKpiItem = {
  groupId: string;
  groupName: string;
  groupCode: string | null;
  accountNames: string[];
  activeStores: number;
  totalStores: number;
  required: number;
  actual: number;
  vacant: number;
  pipeline: number;
  mfr: number;
  mfrPercent: number;
  projectedMfr: number;
  projectedMfrPercent: number;
  vacancyRate: number;
  pipelineCoverage: number;
  healthStatus: "healthy" | "at_risk" | "critical";
  isNormalized: boolean;
};

export type CencomDeploymentSummary = {
  totalDepartures: number;
  additionalHc: number;
  deletedVcode: number;
  deployment: number;
};

export type CencomStoreStats = {
  totalStores: number;
  activeStores: number;
  deploymentRate: number; // percentage
};

// ---------------------------------------------------------------------------
// Supabase Fetchers
// ---------------------------------------------------------------------------

export async function fetchCencomAllocationKpi(): Promise<CencomAllocationKpi> {
  const supabase = createClient();

  const { data, error } = await supabase
    .from("v_cencom_allocation_kpi")
    .select()
    .maybeSingle();

  if (error) {
    throwCencomError(error);
  }

  const row = (data ?? {}) as Record<string, unknown>;
  const rawActual = Number(row.actual_hc ?? 0);
  const rawVacant = Number(row.slot_vacant_hc ?? row.open_hc ?? 0);
  const rawRequired = Number(row.required_hc ?? 0);
  const pipelineCount = Number(row.pipeline_count ?? 0);
  const filledHc = Number(row.filled_hc ?? 0);

  const normalized = normalizeSlotAuthorityMetrics(rawRequired, rawActual, rawVacant);

  const rawProjectedMfr = Number(row.projected_mfr ?? 0);
  const projectedMfr =
    normalized.vacant === 0 && normalized.actual >= normalized.required && normalized.required > 0
      ? 1.0
      : rawProjectedMfr;

  return {
    required: normalized.required,
    actual: normalized.actual,
    vacant: normalized.vacant,
    mfr: normalized.mfr,
    mfrPercent: normalized.mfrPercent,
    projectedMfr,
    projectedMfrPercent: Math.round(projectedMfr * 1000) / 10,
    pipelineCount,
    openHc: Number(row.open_hc ?? 0),
    slotVacantHc: Number(row.slot_vacant_hc ?? 0),
    filledHc,
    healthStatus: normalized.healthStatus,
    isNormalized: normalized.isNormalized,
  };
}

export async function fetchCencomGroupAllocationKpi(): Promise<CencomGroupKpiItem[]> {
  const supabase = createClient();

  // 1. Fetch group allocation KPI view
  const { data: groupRows, error: groupError } = await supabase
    .from("v_cencom_group_allocation_kpi")
    .select()
    .order("group_code", { ascending: true });

  if (groupError) {
    throwCencomError(groupError);
  }

  // 2. Fetch active accounts to correlate accounts with groups
  let accountNamesByGroup: Record<string, string[]> = {};
  try {
    const { data: accountsData } = await supabase
      .from("accounts")
      .select("id, account_name, group_id")
      .eq("is_active", true);

    if (accountsData) {
      for (const acc of accountsData) {
        const gid = acc.group_id as string | null;
        const name = (acc.account_name as string | null)?.trim() ?? "";
        if (gid && name) {
          if (!accountNamesByGroup[gid]) {
            accountNamesByGroup[gid] = [];
          }
          accountNamesByGroup[gid].push(name);
        }
      }
    }
  } catch {
    // Non-blocking fallback
    accountNamesByGroup = {};
  }

  // 3. Fetch stores to calculate store counts per group
  let storeStatsByGroup: Record<string, { total: number; active: number }> = {};
  try {
    const { data: storeRows } = await supabase
      .from("stores")
      .select("id, group_id, is_active");

    if (storeRows) {
      for (const st of storeRows) {
        const gid = st.group_id as string | null;
        if (gid) {
          if (!storeStatsByGroup[gid]) {
            storeStatsByGroup[gid] = { total: 0, active: 0 };
          }
          storeStatsByGroup[gid].total += 1;
          if (st.is_active) {
            storeStatsByGroup[gid].active += 1;
          }
        }
      }
    }
  } catch {
    // Non-blocking fallback
    storeStatsByGroup = {};
  }

  // 4. Map & normalize each group row
  const rows = (groupRows ?? []) as Array<Record<string, unknown>>;

  return rows.map((row) => {
    const groupId = String(row.group_id ?? "");
    const groupName = String(row.group_name ?? "Group");
    const groupCode = row.group_code ? String(row.group_code) : null;
    const accounts = accountNamesByGroup[groupId] ?? [];

    const rawActual = Number(row.actual_hc ?? 0);
    const rawVacant = Number(row.slot_vacant_hc ?? row.open_hc ?? 0);
    const rawRequired = Number(row.required_hc ?? 0);
    const pipeline = Number(row.pipeline_count ?? 0);

    const normalized = normalizeSlotAuthorityMetrics(rawRequired, rawActual, rawVacant, {
      groupCode,
      groupName,
      accountNames: accounts,
    });

    const rawProjected = Number(row.projected_mfr ?? 0);
    const projectedMfr =
      normalized.vacant === 0 && normalized.actual >= normalized.required && normalized.required > 0
        ? 1.0
        : rawProjected;

    const groupStores = storeStatsByGroup[groupId] ?? { total: 0, active: 0 };

    return {
      groupId,
      groupName,
      groupCode,
      accountNames: accounts,
      activeStores: groupStores.active,
      totalStores: groupStores.total,
      required: normalized.required,
      actual: normalized.actual,
      vacant: normalized.vacant,
      pipeline,
      mfr: normalized.mfr,
      mfrPercent: normalized.mfrPercent,
      projectedMfr,
      projectedMfrPercent: Math.round(projectedMfr * 1000) / 10,
      vacancyRate: Number(row.vacancy_rate ?? 0),
      pipelineCoverage: Number(row.pipeline_coverage ?? 0),
      healthStatus: normalized.healthStatus,
      isNormalized: normalized.isNormalized,
    };
  });
}

export async function fetchCencomDeploymentSummary(): Promise<CencomDeploymentSummary> {
  const supabase = createClient();

  try {
    const { data, error } = await supabase.rpc("fn_cencom_deployment_summary");

    if (error) {
      return {
        totalDepartures: 0,
        additionalHc: 0,
        deletedVcode: 0,
        deployment: 0,
      };
    }

    const payload = (data ?? {}) as Record<string, unknown>;
    return {
      totalDepartures: Number(payload.total_departures ?? 0),
      additionalHc: Number(payload.additional_hc ?? 0),
      deletedVcode: Number(payload.deleted_vcode ?? 0),
      deployment: Number(payload.deployment ?? 0),
    };
  } catch {
    return {
      totalDepartures: 0,
      additionalHc: 0,
      deletedVcode: 0,
      deployment: 0,
    };
  }
}

export async function fetchCencomStoreStats(): Promise<CencomStoreStats> {
  const supabase = createClient();

  try {
    const { data, error } = await supabase
      .from("stores")
      .select("id, is_active");

    if (error || !data) {
      return { totalStores: 0, activeStores: 0, deploymentRate: 0 };
    }

    const totalStores = data.length;
    const activeStores = data.filter((s) => s.is_active).length;
    const deploymentRate =
      totalStores > 0 ? Math.round((activeStores / totalStores) * 1000) / 10 : 0;

    return { totalStores, activeStores, deploymentRate };
  } catch {
    return { totalStores: 0, activeStores: 0, deploymentRate: 0 };
  }
}

// ---------------------------------------------------------------------------
// React Query Hooks
// ---------------------------------------------------------------------------

export function useCencomAllocationKpi() {
  return useQuery({
    queryKey: ["cencom", "allocation-kpi"],
    queryFn: fetchCencomAllocationKpi,
    staleTime: 30000,
  });
}

export function useCencomGroupKpi() {
  return useQuery({
    queryKey: ["cencom", "group-kpi"],
    queryFn: fetchCencomGroupAllocationKpi,
    staleTime: 30000,
  });
}

export function useCencomDeploymentSummary() {
  return useQuery({
    queryKey: ["cencom", "deployment-summary"],
    queryFn: fetchCencomDeploymentSummary,
    staleTime: 30000,
  });
}

export function useCencomStoreStats() {
  return useQuery({
    queryKey: ["cencom", "store-stats"],
    queryFn: fetchCencomStoreStats,
    staleTime: 60000,
  });
}
