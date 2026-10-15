"use client";

import { useEffect } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

// ============================================================================
// Types & Contracts
// ============================================================================

export interface NotificationItem {
  id: string;
  recipient_role: string;
  recipient_user_id: string | null;
  title: string;
  message: string;
  reference_type: string | null;
  reference_id: string | null;
  is_read: boolean;
  created_at: string;
  read_at: string | null;
  deep_link_route: string | null;
  notification_type: string;
  event_type: string;
  sla_level: number | null;
  is_archived: boolean;
  archived_at: string | null;
  data?: Record<string, unknown> | null;
}

export type NotificationTabFilter =
  | "all"
  | "unread"
  | "requests"
  | "alerts"
  | "system";

export interface NotificationFilter {
  tab: NotificationTabFilter;
  limit?: number;
}

export interface NotificationCounts {
  all: number;
  unread: number;
  requests: number;
  alerts: number;
  system: number;
}

export interface ParsedDeepLink {
  route: string;
  referenceId?: string | null;
  requestId?: string | null;
  label: string;
}

// ============================================================================
// Categorization Helpers
// ============================================================================

const REQUEST_REFERENCE_TYPES = new Set([
  "headcount_request",
  "new_store_request",
  "coverage_request",
  "vacancy_closure",
  "deactivation_request",
  "deactivation_batch",
  "hr_emploc_deletion",
  "applicant_movement",
  "account_group_transfer_request",
  "account_request",
  "workforce_pool_request",
  "plantilla_import_batch",
  "vacancy_import_batch",
  "mika_import",
  "store_import",
]);

const REQUEST_NOTIFICATION_TYPES = new Set([
  "submission",
  "approval",
  "rejection",
  "approval_required",
  "approved",
  "rejected",
  "new_store_request",
  "coverage_request",
  "account_transfer",
  "deactivation",
  "workforce_pool_request",
  "plantilla_import",
  "vacancy_import",
  "deactivation_request",
]);

export function isRequestNotification(item: NotificationItem): boolean {
  if (item.reference_type && REQUEST_REFERENCE_TYPES.has(item.reference_type)) {
    return true;
  }
  if (REQUEST_NOTIFICATION_TYPES.has(item.notification_type)) {
    return true;
  }
  const event = (item.event_type || "").toUpperCase();
  if (
    event.includes("_REQUEST_") ||
    event.includes("_SUBMITTED") ||
    event.includes("_APPROVED") ||
    event.includes("_REJECTED") ||
    event.includes("CLOSURE")
  ) {
    return true;
  }
  return false;
}

export function isAlertNotification(item: NotificationItem): boolean {
  if (item.sla_level !== null && item.sla_level !== undefined && item.sla_level > 0) {
    return true;
  }
  const type = (item.notification_type || "").toLowerCase();
  const event = (item.event_type || "").toLowerCase();
  const title = (item.title || "").toLowerCase();

  return (
    type === "escalation" ||
    type === "alert" ||
    type === "breach" ||
    type === "warning" ||
    type === "incident" ||
    event.includes("sla") ||
    event.includes("escalat") ||
    event.includes("breach") ||
    title.includes("sla") ||
    title.includes("breach") ||
    title.includes("urgent") ||
    title.includes("overdue")
  );
}

export function isSystemNotification(item: NotificationItem): boolean {
  return !isRequestNotification(item) && !isAlertNotification(item);
}

export function matchesTabFilter(item: NotificationItem, tab: NotificationTabFilter): boolean {
  switch (tab) {
    case "unread":
      return !item.is_read;
    case "requests":
      return isRequestNotification(item);
    case "alerts":
      return isAlertNotification(item);
    case "system":
      return isSystemNotification(item);
    case "all":
    default:
      return true;
  }
}

// ============================================================================
// Deep-Link Payload Parser
// ============================================================================

export function parseNotificationDeepLink(item: NotificationItem): ParsedDeepLink | null {
  const payload = (item.data || {}) as Record<string, unknown>;
  const rawRoute = (payload.route as string) || (payload.deep_link_route as string) || item.deep_link_route || "";
  const refId = (payload.reference_id as string) || (payload.request_id as string) || item.reference_id || "";
  const reqId = (payload.request_id as string) || (payload.reference_id as string) || item.reference_id || "";
  const refType = item.reference_type || "";

  // 1. New Store Requests
  if (refType === "new_store_request" || rawRoute.includes("new_store_request")) {
    return {
      route: "/approvals?tab=new_stores",
      referenceId: refId || null,
      requestId: reqId || null,
      label: "View in Approvals →",
    };
  }

  // 2. Headcount Requests
  if (refType === "headcount_request" || rawRoute.includes("headcount-request") || rawRoute.includes("headcount")) {
    return {
      route: "/approvals?tab=headcount",
      referenceId: refId || null,
      requestId: reqId || null,
      label: "View in Approvals →",
    };
  }

  // 3. Coverage Requests
  if (refType === "coverage_request" || rawRoute.includes("coverage")) {
    return {
      route: "/approvals?tab=coverage",
      referenceId: refId || null,
      requestId: reqId || null,
      label: "View in Approvals →",
    };
  }

  // 4. Vacancy Closure Requests
  if (refType === "vacancy_closure" || rawRoute.includes("closure-request") || rawRoute.includes("vacancy_closure")) {
    return {
      route: "/approvals?tab=vacancy_closures",
      referenceId: refId || null,
      requestId: reqId || null,
      label: "View in Approvals →",
    };
  }

  // 5. HR Emploc Deletions
  if (refType === "hr_emploc_deletion" || rawRoute.includes("deletion")) {
    return {
      route: "/approvals?tab=hr_emploc_deletions",
      referenceId: refId || null,
      requestId: reqId || null,
      label: "View in Approvals →",
    };
  }

  // 6. Deactivations
  if (
    refType === "deactivation_request" ||
    refType === "deactivation_batch" ||
    rawRoute.includes("deactivation")
  ) {
    return {
      route: "/approvals?tab=deactivations",
      referenceId: refId || null,
      requestId: reqId || null,
      label: "View in Approvals →",
    };
  }

  // 7. Applicant Movements
  if (refType === "applicant_movement" || rawRoute.includes("applicant_movement")) {
    return {
      route: "/approvals?tab=applicant_movements",
      referenceId: refId || null,
      requestId: reqId || null,
      label: "View in Approvals →",
    };
  }

  // 8. Account Group Transfers
  if (
    refType === "account_group_transfer_request" ||
    rawRoute.includes("account_transfer") ||
    rawRoute.includes("account-transfer")
  ) {
    return {
      route: "/approvals?tab=account_group_transfers",
      referenceId: refId || null,
      requestId: reqId || null,
      label: "View in Approvals →",
    };
  }

  // 9. Workforce Pool / Relievers
  if (refType === "workforce_pool_request" || rawRoute.includes("pool_request")) {
    return {
      route: "/approvals?tab=relievers",
      referenceId: refId || null,
      requestId: reqId || null,
      label: "View in Approvals →",
    };
  }

  // 10. Account Requests
  if (refType === "account_request" || rawRoute.includes("account-request")) {
    return {
      route: "/users",
      referenceId: refId || null,
      requestId: reqId || null,
      label: "Review User Requests →",
    };
  }

  // 11. Vacancy / Vcode
  if (refType === "vacancy" || rawRoute.startsWith("/vacancies")) {
    const vcode = refId || (rawRoute.split("/vacancies/")[1]?.split("/")[0] ?? "");
    const cleanVcode = vcode ? encodeURIComponent(vcode) : "";
    return {
      route: cleanVcode ? `/vacancy?q=${cleanVcode}` : "/vacancy",
      referenceId: refId || null,
      requestId: reqId || null,
      label: "Inspect Vacancy →",
    };
  }

  // 12. Plantilla
  if (refType === "plantilla" || rawRoute.includes("plantilla")) {
    return {
      route: "/plantilla",
      referenceId: refId || null,
      requestId: reqId || null,
      label: "Inspect Plantilla →",
    };
  }

  // 13. HR Emploc
  if (refType === "hr_emploc" || rawRoute.includes("hr-emploc")) {
    return {
      route: "/hr-emploc",
      referenceId: refId || null,
      requestId: reqId || null,
      label: "Inspect Emploc →",
    };
  }

  // 14. Import Batches
  if (
    refType === "plantilla_import_batch" ||
    refType === "vacancy_import_batch" ||
    refType === "mika_import" ||
    refType === "store_import"
  ) {
    return {
      route: "/hr-emploc/import",
      referenceId: refId || null,
      requestId: reqId || null,
      label: "Inspect Import Batch →",
    };
  }

  // 15. Generic fallback with explicit valid relative route
  if (rawRoute.startsWith("/")) {
    return {
      route: rawRoute,
      referenceId: refId || null,
      requestId: reqId || null,
      label: "View Details →",
    };
  }

  return null;
}

// ============================================================================
// Query Hooks
// ============================================================================

/**
 * Primary notifications query hook supporting active tab filtering.
 */
export function useNotifications(filter: NotificationFilter = { tab: "all" }) {
  const { tab = "all", limit = 150 } = filter;

  return useQuery({
    queryKey: ["notifications", { tab, limit }],
    queryFn: async (): Promise<NotificationItem[]> => {
      const supabase = createClient();

      let query = supabase
        .from("notifications")
        .select(
          "id, recipient_role, recipient_user_id, title, message, reference_type, reference_id, is_read, created_at, read_at, deep_link_route, notification_type, event_type, sla_level, is_archived, archived_at"
        )
        .eq("is_archived", false)
        .order("created_at", { ascending: false })
        .limit(limit);

      if (tab === "unread") {
        query = query.eq("is_read", false);
      }

      const { data, error } = await query;

      if (error) {
        console.error("[useNotifications] Query error:", error);
        throw error;
      }

      const rawItems = (data || []).map((row) => ({
        ...row,
        is_read: Boolean(row.is_read),
        is_archived: Boolean(row.is_archived),
        data: {
          route: row.deep_link_route,
          reference_id: row.reference_id,
          request_id: row.reference_id,
        },
      })) as NotificationItem[];

      // Filter in-memory for tab-specific categories
      return rawItems.filter((item) => matchesTabFilter(item, tab));
    },
    staleTime: 15 * 1000,
  });
}

/**
 * Returns exact unread notification count for the current session.
 */
export function useUnreadNotificationsCount() {
  return useQuery({
    queryKey: ["notifications-unread-count"],
    queryFn: async (): Promise<number> => {
      const supabase = createClient();
      const { count, error } = await supabase
        .from("notifications")
        .select("id", { count: "exact", head: true })
        .eq("is_read", false)
        .eq("is_archived", false);

      if (error) {
        console.error("[useUnreadNotificationsCount] Error:", error);
        return 0;
      }

      return count ?? 0;
    },
    staleTime: 15 * 1000,
  });
}

/**
 * Computes category breakdown counts across all active tabs.
 */
export function useNotificationCounts() {
  return useQuery({
    queryKey: ["notifications-counts"],
    queryFn: async (): Promise<NotificationCounts> => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("notifications")
        .select(
          "id, recipient_role, reference_type, notification_type, event_type, sla_level, is_read, is_archived"
        )
        .eq("is_archived", false)
        .limit(500);

      if (error) {
        console.error("[useNotificationCounts] Error:", error);
        return { all: 0, unread: 0, requests: 0, alerts: 0, system: 0 };
      }

      const items = (data || []).map((row) => ({
        ...row,
        is_read: Boolean(row.is_read),
      })) as unknown as NotificationItem[];

      let unread = 0;
      let requests = 0;
      let alerts = 0;
      let system = 0;

      for (const item of items) {
        if (!item.is_read) unread++;
        if (isRequestNotification(item)) requests++;
        else if (isAlertNotification(item)) alerts++;
        else system++;
      }

      return {
        all: items.length,
        unread,
        requests,
        alerts,
        system,
      };
    },
    staleTime: 15 * 1000,
  });
}

// ============================================================================
// Realtime Hook
// ============================================================================

/**
 * Subscribes to Supabase postgres_changes on public.notifications to keep
 * lists and unread badges synchronized in realtime across clients.
 */
export function useNotificationsRealtime() {
  const queryClient = useQueryClient();

  useEffect(() => {
    const supabase = createClient();
    const channel = supabase
      .channel("notifications-realtime-sync")
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "notifications",
        },
        () => {
          queryClient.invalidateQueries({ queryKey: ["notifications"] });
          queryClient.invalidateQueries({ queryKey: ["notifications-unread-count"] });
          queryClient.invalidateQueries({ queryKey: ["notifications-counts"] });
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [queryClient]);
}

// ============================================================================
// Mutation Hooks
// ============================================================================

/**
 * Marks an individual notification as read with optimistic query cache updates.
 */
export function useMarkAsRead() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (notificationId: string) => {
      const supabase = createClient();

      // 1. Try secure RPC first
      const { error: rpcError } = await supabase.rpc("mark_notification_read", {
        p_notification_id: notificationId,
      });

      // 2. Direct client update fallback for full access / RLS
      const { error: updateError } = await supabase
        .from("notifications")
        .update({
          is_read: true,
          read_at: new Date().toISOString(),
        })
        .eq("id", notificationId);

      if (rpcError && updateError) {
        console.warn("[useMarkAsRead] Update notice:", { rpcError, updateError });
      }
    },
    onMutate: async (notificationId: string) => {
      await queryClient.cancelQueries({ queryKey: ["notifications"] });
      await queryClient.cancelQueries({ queryKey: ["notifications-unread-count"] });

      // Optimistically update notifications lists
      queryClient.setQueriesData<NotificationItem[]>(
        { queryKey: ["notifications"] },
        (old) => {
          if (!old) return [];
          return old.map((n) =>
            n.id === notificationId ? { ...n, is_read: true, read_at: new Date().toISOString() } : n
          );
        }
      );

      // Optimistically decrement unread count
      queryClient.setQueryData<number>(["notifications-unread-count"], (prev) =>
        Math.max(0, (prev ?? 1) - 1)
      );

      queryClient.setQueryData<NotificationCounts>(["notifications-counts"], (prev) => {
        if (!prev) return prev;
        return {
          ...prev,
          unread: Math.max(0, prev.unread - 1),
        };
      });
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ["notifications"] });
      queryClient.invalidateQueries({ queryKey: ["notifications-unread-count"] });
      queryClient.invalidateQueries({ queryKey: ["notifications-counts"] });
    },
  });
}

/**
 * Toggles an individual notification between read and unread status.
 */
export function useToggleNotificationRead() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ id, isRead }: { id: string; isRead: boolean }) => {
      const supabase = createClient();

      if (isRead) {
        await supabase.rpc("mark_notification_read", { p_notification_id: id });
      }

      const { error } = await supabase
        .from("notifications")
        .update({
          is_read: isRead,
          read_at: isRead ? new Date().toISOString() : null,
        })
        .eq("id", id);

      if (error) {
        console.warn("[useToggleNotificationRead] Update error:", error);
      }
    },
    onMutate: async ({ id, isRead }) => {
      await queryClient.cancelQueries({ queryKey: ["notifications"] });
      await queryClient.cancelQueries({ queryKey: ["notifications-unread-count"] });

      queryClient.setQueriesData<NotificationItem[]>(
        { queryKey: ["notifications"] },
        (old) => {
          if (!old) return [];
          return old.map((n) =>
            n.id === id ? { ...n, is_read: isRead, read_at: isRead ? new Date().toISOString() : null } : n
          );
        }
      );

      queryClient.setQueryData<number>(["notifications-unread-count"], (prev) => {
        const current = prev ?? 0;
        return isRead ? Math.max(0, current - 1) : current + 1;
      });

      queryClient.setQueryData<NotificationCounts>(["notifications-counts"], (prev) => {
        if (!prev) return prev;
        return {
          ...prev,
          unread: isRead ? Math.max(0, prev.unread - 1) : prev.unread + 1,
        };
      });
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ["notifications"] });
      queryClient.invalidateQueries({ queryKey: ["notifications-unread-count"] });
      queryClient.invalidateQueries({ queryKey: ["notifications-counts"] });
    },
  });
}

/**
 * Updates all unread notifications for the current authenticated user/role.
 */
export function useMarkAllAsRead() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async () => {
      const supabase = createClient();

      // 1. Try secure RPC
      const { error: rpcError } = await supabase.rpc("mark_all_notifications_read");

      // 2. Direct client update fallback for full access / RLS
      const { error: updateError } = await supabase
        .from("notifications")
        .update({
          is_read: true,
          read_at: new Date().toISOString(),
        })
        .eq("is_read", false);

      if (rpcError && updateError) {
        console.warn("[useMarkAllAsRead] Notice:", { rpcError, updateError });
      }
    },
    onMutate: async () => {
      await queryClient.cancelQueries({ queryKey: ["notifications"] });
      await queryClient.cancelQueries({ queryKey: ["notifications-unread-count"] });

      queryClient.setQueriesData<NotificationItem[]>(
        { queryKey: ["notifications"] },
        (old) => {
          if (!old) return [];
          return old.map((n) => ({
            ...n,
            is_read: true,
            read_at: n.read_at || new Date().toISOString(),
          }));
        }
      );

      queryClient.setQueryData<number>(["notifications-unread-count"], 0);

      queryClient.setQueryData<NotificationCounts>(["notifications-counts"], (prev) => {
        if (!prev) return prev;
        return {
          ...prev,
          unread: 0,
        };
      });
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ["notifications"] });
      queryClient.invalidateQueries({ queryKey: ["notifications-unread-count"] });
      queryClient.invalidateQueries({ queryKey: ["notifications-counts"] });
    },
  });
}
