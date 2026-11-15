import type { PostgrestError } from "@supabase/supabase-js";
import type { useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import {
  type VacancyStatus,
  type VacancyAgingBucket,
  type VacancySortField,
  type VacancySortDirection,
  type VacancyRowCapabilities,
  type VacancyListItem,
  type VacancyDataErrorKind,
  VacancyDataError,
} from "./types";

export const MAX_PAGE_SIZE = 5000;

export const supportedAgingBuckets = new Set<VacancyAgingBucket>([
  "advance",
  "1_15",
  "16_30",
  "31_60",
  "61_120",
  "gt121",
]);

export const supportedUrgencyLevels = new Set(["High", "Medium", "Normal"]);

export const supportedSortFields = new Set<VacancySortField>([
  "aging_days",
  "vacant_date",
  "target_fill_date",
  "urgency",
  "account_name",
  "group_name",
  "store_name",
  "position_title",
  "vacancy_status",
  "pipeline_status",
  "vcode",
]);

export function asObject(value: unknown): Record<string, unknown> {
  return value && !Array.isArray(value) && typeof value === "object"
    ? (value as Record<string, unknown>)
    : {};
}

export function asString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

export function asTrimmedString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

export function asDateFilter(value: unknown): string | null {
  const date = asTrimmedString(value);
  if (!date) return null;
  return /^\d{4}-\d{2}-\d{2}$/.test(date) ? date : null;
}

export function asUuidFilter(value: unknown): string | null {
  const uuid = asTrimmedString(value);
  if (!uuid) return null;
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(uuid)
    ? uuid
    : null;
}

export function asNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

export function asBoolean(value: unknown): boolean {
  return value === true;
}

export function asCount(value: unknown): number {
  return Math.max(0, Math.trunc(asNumber(value) ?? 0));
}

export function normalizeCapabilities(value: unknown): VacancyRowCapabilities {
  const raw = Object.fromEntries(
    Object.entries(asObject(value))
      .filter(([, item]) => typeof item === "boolean")
      .map(([key, item]) => [key, item === true]),
  );

  return {
    canViewDetail: raw.can_view_detail === true,
    canApprove: raw.can_approve === true,
    canUpdateApplicantStatus: raw.can_update_applicant_status === true,
    canRequestClosure: raw.can_request_closure_hint === true || raw.can_request_closure === true,
    raw,
  };
}

export function normalizeAgingBucket(value: unknown): VacancyAgingBucket | null {
  return supportedAgingBuckets.has(value as VacancyAgingBucket)
    ? (value as VacancyAgingBucket)
    : null;
}

export function normalizeUrgency(value: unknown): string | null {
  return supportedUrgencyLevels.has(value as string) ? (value as string) : null;
}

export function normalizeSortField(value: unknown): VacancySortField {
  return supportedSortFields.has(value as VacancySortField)
    ? (value as VacancySortField)
    : "aging_days";
}

export function normalizeSortDirection(value: unknown): VacancySortDirection {
  return value === "asc" ? "asc" : "desc";
}

export function getTotalCount(rows: VacancyListItem[]): number {
  return rows[0]?.totalCount ?? 0;
}

export function getErrorKind(error: PostgrestError): VacancyDataErrorKind {
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
    if (combined.includes("does not exist") || combined.includes("not found")) {
      return "not_found";
    }
    return "access_denied";
  }

  return "retryable";
}

export function throwVacancyError(error: PostgrestError): never {
  if (process.env.NODE_ENV !== "production") {
    console.error("[vacancy rpc error]", error.code, error.message, error.details, error.hint);
  }
  throw new VacancyDataError(getErrorKind(error), error.message);
}

export function calculateDaysToFill(
  vacantDate?: string | null,
  onboardDate?: string | null,
): number | null {
  if (!vacantDate || !onboardDate) return null;
  const vClean = vacantDate.substring(0, 10);
  const oClean = onboardDate.substring(0, 10);
  const vTime = Date.parse(`${vClean}T00:00:00Z`);
  const oTime = Date.parse(`${oClean}T00:00:00Z`);
  if (isNaN(vTime) || isNaN(oTime)) return null;
  const diffDays = Math.round((oTime - vTime) / 86400000);
  return Math.max(0, diffDays);
}

export function formatGroupName(groupName?: string | null, accountName?: string | null): string {
  if (accountName && accountName.trim().toLowerCase() === "moses hq") {
    return "MOSES HQ";
  }
  if (!groupName) return "";
  const trimmed = groupName.trim();
  if (trimmed.toLowerCase() === "global hq" || trimmed.toLowerCase() === "ghq") {
    return "MOSES HQ";
  }
  return trimmed;
}

export async function fetchGroupMap(supabase: ReturnType<typeof createClient>): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  try {
    const { data } = await supabase.from("groups").select("id, group_name");
    if (Array.isArray(data)) {
      for (const g of data) {
        if (g.id && g.group_name) {
          map.set(String(g.id), String(g.group_name));
        }
      }
    }
  } catch {
    // Graceful fallback
  }
  return map;
}

export function invalidateVacancyEcosystem(
  queryClient: ReturnType<typeof useQueryClient>,
  vcode?: string,
): void {
  queryClient.invalidateQueries({ queryKey: ["vacancies"] });
  queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
  queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
  queryClient.invalidateQueries({ queryKey: ["vacancy-counts"] });
  queryClient.invalidateQueries({ queryKey: ["vacancy-detail"] });
  if (vcode) {
    queryClient.invalidateQueries({ queryKey: ["vacancy-detail", vcode] });
  }
  queryClient.invalidateQueries({ queryKey: ["hired-applicants"] });
  queryClient.invalidateQueries({ queryKey: ["plantilla"] });
  queryClient.invalidateQueries({ queryKey: ["store-vacancies"] });
  queryClient.invalidateQueries({ queryKey: ["cencom"] });
  queryClient.invalidateQueries({ queryKey: ["cencom-allocation-kpi"] });
  queryClient.invalidateQueries({ queryKey: ["cencom-group-kpi"] });
  queryClient.invalidateQueries({ queryKey: ["dashboard"] });
  queryClient.invalidateQueries({ queryKey: ["dashboard-metrics"] });
  queryClient.invalidateQueries({ queryKey: ["dashboard-operational-analytics"] });
  queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
  queryClient.invalidateQueries({ queryKey: ["vacancy-closure-requests"] });
  queryClient.invalidateQueries({ queryKey: ["pending-vacancy-closure-requests"] });
  queryClient.invalidateQueries({ queryKey: ["vacancy-closure-counts"] });
}

export function tabToRpcStatus(tab?: VacancyStatus): string | null {
  if (!tab) return null;
  switch (tab) {
    case "open":           return "Open";
    case "pipeline":       return "Pipeline";
    case "with_applicant": return "Pipeline";
    case "hired":          return "Hired";
    case "closure":        return "Closure";
    case "failed_backout": return null;
    case "rejected":       return null;
    case "backout":        return null;
    default:               return null;
  }
}
