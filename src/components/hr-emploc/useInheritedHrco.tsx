// components/hr-emploc/useInheritedHrco.tsx
"use client";

import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { formatPersonName } from "@/lib/utils/displayText";

export interface HrcoScopeInfo {
  profileId: string;
  fullName: string;
  email?: string | null;
  accountIds: string[];
  groupIds: string[];
  isGlobal: boolean;
}

export function useInheritedHrcoMap() {
  const query = useQuery({
    queryKey: ["inherited-hrco-map"],
    queryFn: async (): Promise<HrcoScopeInfo[]> => {
      const supabase = createClient();

      // 1. Try batch RPC first (SECURITY DEFINER)
      try {
        const { data: rpcData, error: rpcError } = await supabase.rpc(
          "get_all_account_group_hrcos_map"
        );
        if (!rpcError && Array.isArray(rpcData)) {
          return rpcData.map((item: Record<string, unknown>) => ({
            profileId: String(item.profile_id ?? ""),
            fullName: String(item.full_name ?? ""),
            email: item.email ? String(item.email) : null,
            accountIds: Array.isArray(item.account_ids) ? (item.account_ids as string[]) : [],
            groupIds: Array.isArray(item.group_ids) ? (item.group_ids as string[]) : [],
            isGlobal: Boolean(item.hrco_global_visibility),
          }));
        }
      } catch {
        // Fall back to client query
      }

      // 2. Client-side query
      try {
        const { data, error } = await supabase
          .from("users_profile")
          .select(`
            id,
            full_name,
            email,
            hrco_global_visibility,
            roles!inner(role_name),
            user_scopes(account_id, group_id)
          `)
          .is("archived_at", null)
          .eq("is_active", true)
          .eq("roles.role_name", "HRCO");

        if (error || !data) return [];

        return data.map((u: Record<string, unknown>) => {
          const rawScopes = Array.isArray(u.user_scopes) ? u.user_scopes : [];
          const accountIds: string[] = [];
          const groupIds: string[] = [];

          for (const s of rawScopes as Array<Record<string, unknown>>) {
            if (s.account_id) accountIds.push(String(s.account_id));
            if (s.group_id) groupIds.push(String(s.group_id));
          }

          return {
            profileId: String(u.id),
            fullName: String(u.full_name ?? ""),
            email: u.email ? String(u.email) : null,
            accountIds,
            groupIds,
            isGlobal: Boolean(u.hrco_global_visibility),
          };
        });
      } catch (err) {
        console.warn("Failed to query inherited HRCO map:", err);
        return [];
      }
    },
    staleTime: 60_000,
  });

  const hrcoUsers = useMemo(() => query.data ?? [], [query.data]);

  const getHrcosForRecord = useMemo(() => {
    return (record: { accountId?: string | null; groupId?: string | null }): string[] => {
      const { accountId, groupId } = record;
      const matched = new Set<string>();

      for (const hrco of hrcoUsers) {
        if (hrco.isGlobal) {
          matched.add(hrco.fullName);
          continue;
        }
        if (accountId && hrco.accountIds.includes(accountId)) {
          matched.add(hrco.fullName);
          continue;
        }
        if (groupId && hrco.groupIds.includes(groupId)) {
          matched.add(hrco.fullName);
          continue;
        }
      }

      return Array.from(matched);
    };
  }, [hrcoUsers]);

  return {
    hrcoUsers,
    getHrcosForRecord,
    isLoading: query.isLoading,
  };
}

export interface InheritedHrcoBadgeProps {
  hrcos?: string[];
  accountId?: string | null;
  groupId?: string | null;
  fallbackName?: string | null;
  className?: string;
}

export function InheritedHrcoBadge({
  hrcos: providedHrcos,
  accountId,
  groupId,
  fallbackName,
  className = "",
}: InheritedHrcoBadgeProps) {
  const { getHrcosForRecord } = useInheritedHrcoMap();

  const resolvedHrcos = useMemo(() => {
    if (providedHrcos) return providedHrcos;
    if (accountId || groupId) {
      return getHrcosForRecord({ accountId, groupId });
    }
    return [];
  }, [providedHrcos, accountId, groupId, getHrcosForRecord]);

  if (resolvedHrcos.length === 1) {
    return (
      <span className={`text-table-text-sub truncate ${className}`} title={formatPersonName(resolvedHrcos[0])}>
        {formatPersonName(resolvedHrcos[0])}
      </span>
    );
  }

  if (resolvedHrcos.length > 1) {
    const primaryName = formatPersonName(resolvedHrcos[0]);
    const allNames = resolvedHrcos.map((name) => formatPersonName(name)).join(", ");
    return (
      <div className={`flex items-center gap-1.5 ${className}`} title={allNames}>
        <span className="text-table-text-sub truncate max-w-[120px]">{primaryName}</span>
        <span className="shrink-0 rounded-full bg-brand-50 border border-brand-200 px-1.5 py-0.2 text-[10px] font-semibold text-brand-700 cursor-help">
          +{resolvedHrcos.length - 1}
        </span>
      </div>
    );
  }

  // If no HRCO found in matrix, check if fallbackName is valid
  if (fallbackName && fallbackName !== "--" && fallbackName !== "Unassigned") {
    return (
      <span className={`text-table-text-sub truncate ${className}`} title={formatPersonName(fallbackName)}>
        {formatPersonName(fallbackName)}
      </span>
    );
  }

  return (
    <span
      className={`inline-flex items-center rounded-md px-1.5 py-0.5 text-[11px] font-medium bg-amber-50 text-amber-800 border border-amber-200 ${className}`}
      title="No HRCO assigned in User Management for this Group/Account"
    >
      No HRCO in Group
    </span>
  );
}
