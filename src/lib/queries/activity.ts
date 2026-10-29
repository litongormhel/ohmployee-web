/**
 * src/lib/queries/activity.ts
 *
 * Query layer for Recent Activity Feed (Phase 2B-1).
 * Calls the SECURITY DEFINER RPC public.fn_get_recent_activity with
 * client-side caching (60s staleTime).
 */

import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

export type ActivityEventType =
  | "user_approved"
  | "user_rejected"
  | "user_role_updated"
  | "user_archived"
  | "plantilla_deployed"
  | "plantilla_separation"
  | "plantilla_on_leave"
  | "plantilla_deactivation_requested"
  | "plantilla_deactivated"
  | "vacancy_opened"
  | "vacancy_filled"
  | "vacancy_closed"
  | "vacancy_reopened"
  | "emploc_created"
  | "emploc_for_correction"
  | "emploc_for_review"
  | "emploc_approved"
  | "emploc_deployed"
  | "emploc_reverted";

export interface RecentActivityDetails {
  subject?: string | null;
  employee_no?: string | null;
  account_name?: string | null;
  store_name?: string | null;
  position?: string | null;
  vcode?: string | null;
  target_role?: string | null;
  is_pool?: boolean;
}

export interface RecentActivityItem {
  id: string;
  timestamp: string;
  module: string;
  action: string;
  eventType: ActivityEventType;
  recordId: string | null;
  actorName: string;
  actorRole: string;
  details: RecentActivityDetails;
}

export interface FetchRecentActivityParams {
  groupId?: string | null;
  accountId?: string | null;
  limit?: number;
}

export async function fetchRecentActivity(
  params?: FetchRecentActivityParams
): Promise<RecentActivityItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_get_recent_activity", {
    p_group_id: params?.groupId || null,
    p_account_id: params?.accountId || null,
    p_limit: params?.limit ?? 10,
  });

  if (error) {
    console.error("[fetchRecentActivity] Error fetching recent activity:", error);
    return [];
  }

  const raw = (data ?? []) as Array<{
    id: string;
    timestamp: string;
    module: string;
    action: string;
    event_type: string;
    record_id: string | null;
    actor_name: string;
    actor_role: string;
    details: RecentActivityDetails;
  }>;

  return raw.map((r) => ({
    id: r.id,
    timestamp: r.timestamp,
    module: r.module,
    action: r.action,
    eventType: r.event_type as ActivityEventType,
    recordId: r.record_id,
    actorName: r.actor_name,
    actorRole: r.actor_role,
    details: r.details || {},
  }));
}

export function useRecentActivity(params?: FetchRecentActivityParams) {
  return useQuery({
    queryKey: ["recent-activity", params?.groupId, params?.accountId, params?.limit],
    queryFn: () => fetchRecentActivity(params),
    staleTime: 60 * 1000, // 60s per specification
    refetchOnWindowFocus: false,
  });
}
