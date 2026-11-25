import { createClient } from "@/lib/supabase/client";
import { useQuery } from "@tanstack/react-query";

export type GlobalSearchResultType =
  | "vacancy"
  | "hr_emploc"
  | "plantilla"
  | "applicant"
  | "store"
  | string;

export interface GlobalSearchResultItem {
  resultType: GlobalSearchResultType;
  recordId: string;
  primaryLabel: string;
  secondaryLabel: string;
  status: string;
  matchedField: string;
  groupName: string;
  accountName: string;
  createdAt: string | null;
  navigationTarget: string;
  navigationId: string;
}

export const RECENT_SEARCHES_STORAGE_KEY = "ohm_global_search_recent_v1";
const MAX_RECENT_SEARCHES = 8;

export function getRecentSearches(): string[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = localStorage.getItem(RECENT_SEARCHES_STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter((s): s is string => typeof s === "string" && s.trim().length > 0) : [];
  } catch {
    return [];
  }
}

export function saveRecentSearch(query: string): string[] {
  if (typeof window === "undefined") return [];
  const clean = query.trim();
  if (clean.length < 2) return getRecentSearches();

  try {
    const current = getRecentSearches();
    const updated = [clean, ...current.filter((item) => item.toLowerCase() !== clean.toLowerCase())].slice(
      0,
      MAX_RECENT_SEARCHES
    );
    localStorage.setItem(RECENT_SEARCHES_STORAGE_KEY, JSON.stringify(updated));
    return updated;
  } catch {
    return getRecentSearches();
  }
}

export function clearRecentSearches(): void {
  if (typeof window === "undefined") return;
  try {
    localStorage.removeItem(RECENT_SEARCHES_STORAGE_KEY);
  } catch {
    // Non-blocking storage reset
  }
}

export function getTypeBadgeInfo(resultType: string): { label: string; badgeClass: string } {
  switch (resultType) {
    case "vacancy":
      return {
        label: "Vacancy",
        badgeClass:
          "bg-amber-50 text-amber-700 border-amber-200 dark:bg-amber-950/40 dark:text-amber-300 dark:border-amber-800",
      };
    case "plantilla":
      return {
        label: "Plantilla",
        badgeClass:
          "bg-blue-50 text-blue-700 border-blue-200 dark:bg-blue-950/40 dark:text-blue-300 dark:border-blue-800",
      };
    case "hr_emploc":
      return {
        label: "HR Emploc",
        badgeClass:
          "bg-purple-50 text-purple-700 border-purple-200 dark:bg-purple-950/40 dark:text-purple-300 dark:border-purple-800",
      };
    case "applicant":
      return {
        label: "Applicant",
        badgeClass:
          "bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-950/40 dark:text-emerald-300 dark:border-emerald-800",
      };
    case "store":
      return {
        label: "Store",
        badgeClass:
          "bg-cyan-50 text-cyan-700 border-cyan-200 dark:bg-cyan-950/40 dark:text-cyan-300 dark:border-cyan-800",
      };
    default:
      return {
        label: resultType.charAt(0).toUpperCase() + resultType.slice(1),
        badgeClass:
          "bg-slate-50 text-slate-700 border-slate-200 dark:bg-slate-800 dark:text-slate-300 dark:border-slate-700",
      };
  }
}

export function getMatchedFieldLabel(matchedField: string): string {
  switch (matchedField) {
    case "vcode":
      return "Matched by VCODE";
    case "emploc_no":
      return "Matched by Emploc #";
    case "employee_no":
      return "Matched by Employee #";
    case "employee_name":
    case "applicant_name":
      return "Matched by Name";
    case "position":
      return "Matched by Position";
    case "account":
      return "Matched by Account";
    case "store_name":
      return "Matched by Store";
    default:
      return `Matched by ${matchedField}`;
  }
}

export function getNavigationUrl(result: GlobalSearchResultItem): string {
  const target = (result.navigationTarget || result.resultType).toLowerCase();
  const searchParam = encodeURIComponent(result.navigationId || result.primaryLabel);

  switch (target) {
    case "vacancy": {
      const vcode = encodeURIComponent(result.navigationId || result.primaryLabel);
      const idParam = result.recordId ? `&id=${encodeURIComponent(result.recordId)}` : "";
      const statusParam = result.status
        ? `&status=${encodeURIComponent(result.status.toLowerCase().replace(/\s+/g, "_"))}`
        : "";
      return `/vacancy?search=${vcode}&vcode=${vcode}${idParam}${statusParam}`;
    }
    case "plantilla": {
      if (result.recordId) {
        return `/plantilla/${encodeURIComponent(result.recordId)}`;
      }
      const statusParam = result.status
        ? `&status=${encodeURIComponent(result.status.toLowerCase().replace(/\s+/g, "_"))}`
        : "";
      return `/plantilla?search=${searchParam}${statusParam}`;
    }
    case "hr_emploc": {
      const idParam = result.recordId ? `&id=${encodeURIComponent(result.recordId)}` : "";
      const queueParam = result.status
        ? `&queue=${encodeURIComponent(result.status.toLowerCase().replace(/\s+/g, "_"))}`
        : "";
      return `/hr-emploc?search=${searchParam}${idParam}${queueParam}`;
    }
    case "applicant":
      return `/vacancy?tab=pipeline&search=${searchParam}&vcode=${searchParam}`;
    case "cencom":
      return `/cencom?search=${searchParam}`;
    default:
      return `/${target}?search=${searchParam}`;
  }
}

/**
 * Authoritative global search invocation calling public.search_global_index
 */
export async function searchGlobalIndex(
  query: string,
  limit = 50
): Promise<GlobalSearchResultItem[]> {
  const cleanQuery = query.trim();
  if (cleanQuery.length < 2 || ["na", "n/a"].includes(cleanQuery.toLowerCase())) {
    return [];
  }

  const supabase = createClient();
  const { data, error } = await supabase.rpc("search_global_index", {
    p_query: cleanQuery,
    p_limit: limit,
  });

  if (error) {
    console.error("[PostgREST Schema Error] search_global_index:", error);
    if (error.code === "42501") {
      throw new Error("Access restricted: Global Search is reserved for authorized operations roles.");
    }
    throw new Error(error.message || "Failed to execute global search");
  }

  return ((data as unknown as Record<string, unknown>[]) ?? []).map((row) => ({
    resultType: String(row.result_type ?? ""),
    recordId: String(row.record_id ?? ""),
    primaryLabel: String(row.primary_label ?? ""),
    secondaryLabel: String(row.secondary_label ?? ""),
    status: String(row.status ?? ""),
    matchedField: String(row.matched_field ?? ""),
    groupName: String(row.group_name ?? ""),
    accountName: String(row.account_name ?? ""),
    createdAt: row.created_at ? String(row.created_at) : null,
    navigationTarget: String(row.navigation_target ?? ""),
    navigationId: String(row.navigation_id ?? ""),
  }));
}

export function useGlobalSearch(query: string, enabled = true) {
  const clean = query.trim();
  return useQuery({
    queryKey: ["global-search", clean],
    queryFn: () => searchGlobalIndex(clean),
    enabled: enabled && clean.length >= 2,
    staleTime: 60 * 1000,
  });
}
