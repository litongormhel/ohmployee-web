import { useQuery, keepPreviousData } from "@tanstack/react-query";
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
    placeholderData: keepPreviousData,
  });
}

export function useCencomStoreStats() {
  return useQuery({
    queryKey: ["cencom", "store-stats"],
    queryFn: fetchCencomStoreStats,
    staleTime: 60000,
    placeholderData: keepPreviousData,
  });
}

// ---------------------------------------------------------------------------
// Target Deployment & Vacancy Aging Models & Fetchers
// ---------------------------------------------------------------------------

export type CencomAgingBucket =
  | "1_15"
  | "16_30"
  | "31_60"
  | "61_120"
  | "gt121"
  | "advance";

export interface CencomOperationalVacancy {
  id: string;
  vcode: string;
  account: string;
  position: string;
  storeName: string;
  areaName: string;
  province: string;
  vacantDate: string | null;
  targetFillDate: string | null;
  urgencyLevel: string | null;
  hrcoName: string | null;
  status: string;
  agingDays: number | null;
  bucket: CencomAgingBucket;
  hasReliever: boolean;
  hasCommando: boolean;
  riskScore: number;
}

export interface CencomGroupedOutletVacancy {
  key: string;
  province: string;
  area: string;
  store: string;
  hrco: string;
  oldestAging: number;
  relieverStatus: "Has Reliever" | "No Reliever" | "Mixed";
  vacancies: CencomOperationalVacancy[];
}

export interface CencomProvinceAgingSummary {
  province: string;
  provinceKey: string;
  total: number;
  advanceCount: number;
  bucket1_15: number;
  bucket16_30: number;
  bucket31_60: number;
  bucket61_120: number;
  bucketGt121: number;
  storeCount: number;
  vacancies: CencomOperationalVacancy[];
}

export interface CencomTargetDeploymentData {
  operationalTotal: number;
  advanceCount: number;
  grandTotal: number;
  bucket1_15: number;
  bucket16_30: number;
  bucket31_60: number;
  bucket61_120: number;
  bucketGt121: number;
  avgAgingDays: number;
  maxAgingDays: number;
  pctCriticalAging: number;
  provinces: CencomProvinceAgingSummary[];
  groupedOutlets: CencomGroupedOutletVacancy[];
  allVacancies: CencomOperationalVacancy[];
}

export function computeAgingBucket(vacantDate: string | null): {
  days: number | null;
  bucket: CencomAgingBucket;
} {
  if (!vacantDate) {
    return { days: null, bucket: "advance" };
  }
  const dateText = vacantDate.length > 10 ? vacantDate.slice(0, 10) : vacantDate;
  const parsed = new Date(dateText);
  if (isNaN(parsed.getTime())) {
    return { days: null, bucket: "advance" };
  }

  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const normalizedParsed = new Date(parsed.getFullYear(), parsed.getMonth(), parsed.getDate());

  if (normalizedParsed.getTime() > today.getTime()) {
    return { days: null, bucket: "advance" };
  }

  const diffMs = today.getTime() - normalizedParsed.getTime();
  const days = Math.floor(diffMs / (1000 * 60 * 60 * 24)) + 1;

  if (days <= 15) return { days, bucket: "1_15" };
  if (days <= 30) return { days, bucket: "16_30" };
  if (days <= 60) return { days, bucket: "31_60" };
  if (days <= 120) return { days, bucket: "61_120" };
  return { days, bucket: "gt121" };
}

export async function fetchCencomTargetDeployment(): Promise<CencomTargetDeploymentData> {
  const supabase = createClient();

  // 1. Query open vacancies with location and dates
  const { data: vacancyRows, error: vacancyError } = await supabase
    .from("vacancies")
    .select(
      "id, vcode, account, position, store_name, store_branch, area_name, area_city, province, vacant_date, target_fill_date, urgency_level, hrco_name, status, required_headcount"
    )
    .in("status", ["Open", "For Sourcing", "open", "for sourcing"])
    .is("deleted_at", null)
    .order("vacant_date", { ascending: true });

  if (vacancyError) {
    throwCencomError(vacancyError);
  }

  // 2. Fetch reliever indicators if available
  let relieverMap: Record<string, { hasReliever: boolean; hasCommando: boolean }> = {};
  try {
    const { data: indicatorRows } = await supabase
      .from("v_vacancy_deployment_indicators")
      .select("vacancy_id, has_reliever, has_commando");

    if (indicatorRows) {
      for (const row of indicatorRows) {
        if (row.vacancy_id) {
          relieverMap[row.vacancy_id] = {
            hasReliever: Boolean(row.has_reliever),
            hasCommando: Boolean(row.has_commando),
          };
        }
      }
    }
  } catch {
    relieverMap = {};
  }

  const operationalVacancies: CencomOperationalVacancy[] = [];

  for (const raw of (vacancyRows ?? []) as Array<Record<string, unknown>>) {
    const id = String(raw.id ?? "");
    const vcode = String(raw.vcode ?? "VCODE");
    const account = String(raw.account ?? "Unassigned Account");
    const position = String(raw.position ?? "Staff");
    const storeName = String(raw.store_name ?? raw.store_branch ?? "Unassigned Store");
    const province = String(raw.province ?? "Unassigned Province");
    const areaName = String(raw.area_name ?? raw.area_city ?? province);
    const vacantDate = raw.vacant_date ? String(raw.vacant_date) : null;
    const targetFillDate = raw.target_fill_date ? String(raw.target_fill_date) : null;
    const urgencyLevel = raw.urgency_level ? String(raw.urgency_level) : "Normal";
    const hrcoName = raw.hrco_name ? String(raw.hrco_name) : "Unassigned";
    const status = String(raw.status ?? "Open");

    const { days: agingDays, bucket } = computeAgingBucket(vacantDate);

    const rel = relieverMap[id] ?? { hasReliever: false, hasCommando: false };

    // Urgency & coverage risk scoring matching Mobile logic
    const urgency = (urgencyLevel ?? "").toLowerCase();
    const urgencyScore =
      urgency.includes("critical") || urgency.includes("high")
        ? 40
        : urgency.includes("urgent")
        ? 30
        : urgency.includes("medium")
        ? 20
        : 0;
    const coveragePenalty = rel.hasReliever || rel.hasCommando ? 0 : 12;
    const riskScore = (agingDays ?? 0) + urgencyScore + coveragePenalty;

    operationalVacancies.push({
      id,
      vcode,
      account,
      position,
      storeName,
      areaName,
      province,
      vacantDate,
      targetFillDate,
      urgencyLevel,
      hrcoName,
      status,
      agingDays,
      bucket,
      hasReliever: rel.hasReliever,
      hasCommando: rel.hasCommando,
      riskScore,
    });
  }

  // 3. Accumulate bucket totals
  let bucket1_15 = 0;
  let bucket16_30 = 0;
  let bucket31_60 = 0;
  let bucket61_120 = 0;
  let bucketGt121 = 0;
  let advanceCount = 0;
  let maxAgingDays = 0;
  let totalAgingDaysSum = 0;
  let operationalCount = 0;

  for (const v of operationalVacancies) {
    if (v.bucket === "advance") {
      advanceCount += 1;
    } else {
      operationalCount += 1;
      const days = v.agingDays ?? 0;
      if (days > maxAgingDays) maxAgingDays = days;
      totalAgingDaysSum += days;

      if (v.bucket === "1_15") bucket1_15 += 1;
      else if (v.bucket === "16_30") bucket16_30 += 1;
      else if (v.bucket === "31_60") bucket31_60 += 1;
      else if (v.bucket === "61_120") bucket61_120 += 1;
      else if (v.bucket === "gt121") bucketGt121 += 1;
    }
  }

  const avgAgingDays =
    operationalCount > 0 ? Math.round((totalAgingDaysSum / operationalCount) * 10) / 10 : 0;
  const criticalCount = bucket31_60 + bucket61_120 + bucketGt121;
  const pctCriticalAging =
    operationalCount > 0 ? Math.round((criticalCount / operationalCount) * 1000) / 10 : 0;

  // 4. Group by Province
  const provinceMap: Record<string, CencomOperationalVacancy[]> = {};
  for (const v of operationalVacancies) {
    const key = (v.province || "Unassigned Province").trim();
    if (!provinceMap[key]) provinceMap[key] = [];
    provinceMap[key].push(v);
  }

  const provinces: CencomProvinceAgingSummary[] = Object.entries(provinceMap).map(
    ([prov, list]) => {
      let b1_15 = 0;
      let b16_30 = 0;
      let b31_60 = 0;
      let b61_120 = 0;
      let bGt121 = 0;
      let adv = 0;
      let op = 0;
      let maxDays = 0;
      const storesSet = new Set<string>();

      for (const item of list) {
        storesSet.add(item.storeName.toLowerCase());
        if (item.bucket === "advance") {
          adv += 1;
        } else {
          op += 1;
          const d = item.agingDays ?? 0;
          if (d > maxDays) maxDays = d;
          if (item.bucket === "1_15") b1_15 += 1;
          else if (item.bucket === "16_30") b16_30 += 1;
          else if (item.bucket === "31_60") b31_60 += 1;
          else if (item.bucket === "61_120") b61_120 += 1;
          else if (item.bucket === "gt121") bGt121 += 1;
        }
      }

      return {
        province: prov,
        provinceKey: prov.toLowerCase().replace(/\s+/g, " "),
        total: op,
        advanceCount: adv,
        bucket1_15: b1_15,
        bucket16_30: b16_30,
        bucket31_60: b31_60,
        bucket61_120: b61_120,
        bucketGt121: bGt121,
        storeCount: storesSet.size,
        vacancies: list,
      };
    }
  );

  // Sort provinces by total operational vacancies desc
  provinces.sort((a, b) => b.total - a.total);

  // 5. Group by Store / Outlet for drilldowns
  const storeGroupMap: Record<string, CencomOperationalVacancy[]> = {};
  for (const v of operationalVacancies) {
    const cleanProvince = v.province.trim().toLowerCase();
    const cleanArea = v.areaName.trim().toLowerCase();
    const cleanStore = v.storeName.trim().toLowerCase();
    const cleanHrco = (v.hrcoName || "Unassigned").trim().toLowerCase();
    const key = `${cleanProvince}||${cleanArea}||${cleanStore}||${cleanHrco}`;
    if (!storeGroupMap[key]) storeGroupMap[key] = [];
    storeGroupMap[key].push(v);
  }

  const groupedOutlets: CencomGroupedOutletVacancy[] = Object.entries(storeGroupMap).map(
    ([key, items]) => {
      const first = items[0];
      let oldest = 0;
      for (const item of items) {
        const d = item.agingDays ?? 0;
        if (d > oldest) oldest = d;
      }

      const hasReliever = items.some((item) => item.hasReliever || item.hasCommando);
      const hasNoReliever = items.some((item) => !item.hasReliever && !item.hasCommando);
      let relieverStatus: "Has Reliever" | "No Reliever" | "Mixed" = "No Reliever";
      if (hasReliever && hasNoReliever) relieverStatus = "Mixed";
      else if (hasReliever) relieverStatus = "Has Reliever";

      return {
        key,
        province: first.province,
        area: first.areaName,
        store: first.storeName,
        hrco: first.hrcoName || "Unassigned",
        oldestAging: oldest,
        relieverStatus,
        vacancies: items,
      };
    }
  );

  groupedOutlets.sort((a, b) => b.oldestAging - a.oldestAging);

  return {
    operationalTotal: operationalCount,
    advanceCount,
    grandTotal: operationalCount + advanceCount,
    bucket1_15,
    bucket16_30,
    bucket31_60,
    bucket61_120,
    bucketGt121,
    avgAgingDays,
    maxAgingDays,
    pctCriticalAging,
    provinces,
    groupedOutlets,
    allVacancies: operationalVacancies,
  };
}

export function useCencomTargetDeployment() {
  return useQuery({
    queryKey: ["cencom", "target-deployment"],
    queryFn: fetchCencomTargetDeployment,
    staleTime: 30000,
  });
}

// ---------------------------------------------------------------------------
// Deployment Activity Models & Fetchers
// ---------------------------------------------------------------------------

export interface CencomDeploymentRecord {
  id: string;
  applicantName: string;
  employeeNo: string | null;
  emplocNo: string | null;
  account: string;
  storeName: string;
  position: string;
  status: string;
  hiredDate: string | null;
  area: string;
  vcode: string | null;
  createdAt: string | null;
}

export interface CencomDeploymentActivityStats {
  totalRecords: number;
  thisMonthCount: number;
  lastMonthCount: number;
  pendingEmplocCount: number;
  movedToPlantillaCount: number;
  topAccount: string;
  topStore: string;
  topPosition: string;
}

export interface CencomDeploymentActivityResult {
  stats: CencomDeploymentActivityStats;
  records: CencomDeploymentRecord[];
}

export type CencomDeploymentPeriod = "month" | "last_month" | "last_90_days" | "all";

export async function fetchCencomDeploymentActivity(
  period: CencomDeploymentPeriod = "month"
): Promise<CencomDeploymentActivityResult> {
  const supabase = createClient();

  const now = new Date();
  const currentYear = now.getFullYear();
  const currentMonth = now.getMonth();

  const startOfCurrentMonth = new Date(currentYear, currentMonth, 1).toISOString().split("T")[0];
  const startOfLastMonth = new Date(currentYear, currentMonth - 1, 1).toISOString().split("T")[0];
  const endOfLastMonth = new Date(currentYear, currentMonth, 0).toISOString().split("T")[0];
  const ninetyDaysAgo = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000).toISOString().split("T")[0];

  let query = supabase
    .from("hr_emploc")
    .select(
      "id, applicant_name, employee_no, emploc_no, account, store_name, position, status, hired_date, area_name_snapshot, vcode, created_at"
    )
    .is("deleted_at", null)
    .order("hired_date", { ascending: false, nullsFirst: false });

  if (period === "month") {
    query = query.gte("hired_date", startOfCurrentMonth);
  } else if (period === "last_month") {
    query = query.gte("hired_date", startOfLastMonth).lte("hired_date", endOfLastMonth);
  } else if (period === "last_90_days") {
    query = query.gte("hired_date", ninetyDaysAgo);
  }

  const { data, error } = await query;

  if (error) {
    throwCencomError(error);
  }

  const records: CencomDeploymentRecord[] = (data ?? []).map((row: Record<string, unknown>) => ({
    id: String(row.id ?? ""),
    applicantName: String(row.applicant_name ?? "Unknown Candidate"),
    employeeNo: row.employee_no ? String(row.employee_no) : null,
    emplocNo: row.emploc_no ? String(row.emploc_no) : null,
    account: String(row.account ?? "Unassigned Account"),
    storeName: String(row.store_name ?? "Unassigned Store"),
    position: String(row.position ?? "Staff"),
    status: String(row.status ?? "Pending Emploc"),
    hiredDate: row.hired_date ? String(row.hired_date) : null,
    area: String(row.area_name_snapshot ?? "General Area"),
    vcode: row.vcode ? String(row.vcode) : null,
    createdAt: row.created_at ? String(row.created_at) : null,
  }));

  // Velocity KPI calculations
  const accountCounts: Record<string, number> = {};
  const storeCounts: Record<string, number> = {};
  const positionCounts: Record<string, number> = {};
  let pendingCount = 0;
  let movedCount = 0;
  let thisMonthCount = 0;
  let lastMonthCount = 0;

  for (const rec of records) {
    accountCounts[rec.account] = (accountCounts[rec.account] ?? 0) + 1;
    storeCounts[rec.storeName] = (storeCounts[rec.storeName] ?? 0) + 1;
    positionCounts[rec.position] = (positionCounts[rec.position] ?? 0) + 1;

    const lowerStatus = rec.status.toLowerCase();
    if (lowerStatus.includes("pending")) pendingCount += 1;
    if (lowerStatus.includes("plantilla") || lowerStatus.includes("moved")) movedCount += 1;

    if (rec.hiredDate) {
      if (rec.hiredDate >= startOfCurrentMonth) thisMonthCount += 1;
      else if (rec.hiredDate >= startOfLastMonth && rec.hiredDate <= endOfLastMonth) lastMonthCount += 1;
    }
  }

  const topAccount = Object.entries(accountCounts).sort((a, b) => b[1] - a[1])[0]?.[0] ?? "--";
  const topStore = Object.entries(storeCounts).sort((a, b) => b[1] - a[1])[0]?.[0] ?? "--";
  const topPosition = Object.entries(positionCounts).sort((a, b) => b[1] - a[1])[0]?.[0] ?? "--";

  return {
    stats: {
      totalRecords: records.length,
      thisMonthCount,
      lastMonthCount,
      pendingEmplocCount: pendingCount,
      movedToPlantillaCount: movedCount,
      topAccount,
      topStore,
      topPosition,
    },
    records,
  };
}

export function useCencomDeploymentActivity(period: CencomDeploymentPeriod = "month") {
  return useQuery({
    queryKey: ["cencom", "deployment-activity", period],
    queryFn: () => fetchCencomDeploymentActivity(period),
    staleTime: 30000,
  });
}

