"use client";

import { useEffect } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

export type AnnouncementPriority = "info" | "important" | "urgent";

export interface Announcement {
  id: string;
  title: string;
  content: string;
  priority: AnnouncementPriority;
  is_pinned: boolean;
  status: "active" | "archived";
  target_roles: string[] | null;
  target_group_ids: string[] | null;
  expires_at: string | null;
  created_by: string;
  created_at: string;
  updated_at: string;
  author_name?: string | null;
  author_role?: string | null;
}

export interface CreateAnnouncementInput {
  title: string;
  content: string;
  priority: AnnouncementPriority;
  is_pinned?: boolean;
  target_roles?: string[] | null;
  target_group_ids?: string[] | null;
  expires_at?: string | null;
}

export interface UpdateAnnouncementInput {
  id: string;
  title?: string;
  content?: string;
  priority?: AnnouncementPriority;
  is_pinned?: boolean;
  status?: "active" | "archived";
  target_roles?: string[] | null;
  target_group_ids?: string[] | null;
  expires_at?: string | null;
}

/**
 * Fetch all active, non-expired announcements visible to the current user.
 */
export async function fetchActiveAnnouncements(): Promise<Announcement[]> {
  const supabase = createClient();

  const { data, error } = await supabase
    .from("announcements")
    .select(`
      id,
      title,
      content,
      priority,
      is_pinned,
      status,
      target_roles,
      target_group_ids,
      expires_at,
      created_by,
      created_at,
      updated_at,
      author:users_profile!created_by(full_name, role)
    `)
    .eq("status", "active")
    .or(`expires_at.is.null,expires_at.gt.${new Date().toISOString()}`)
    .order("is_pinned", { ascending: false })
    .order("created_at", { ascending: false });

  if (error) {
    console.error("[PostgREST Schema Error] [announcements] Error fetching announcements:", error);
    return [];
  }

  interface QueryAnnouncementRow {
    id: string;
    title: string;
    content: string;
    priority: string;
    is_pinned: boolean;
    status: "active" | "archived";
    target_roles: string[] | null;
    target_group_ids: string[] | null;
    expires_at: string | null;
    created_by: string;
    created_at: string;
    updated_at: string;
    author: { full_name: string | null; role: string | null } | null;
  }

  const rows = (data || []) as unknown as QueryAnnouncementRow[];

  return rows.map((row) => ({
    id: row.id,
    title: row.title,
    content: row.content,
    priority: row.priority as AnnouncementPriority,
    is_pinned: row.is_pinned,
    status: row.status,
    target_roles: row.target_roles,
    target_group_ids: row.target_group_ids,
    expires_at: row.expires_at,
    created_by: row.created_by,
    created_at: row.created_at,
    updated_at: row.updated_at,
    author_name: row.author?.full_name || null,
    author_role: row.author?.role || null,
  }));
}

/**
 * Check if the user has unacknowledged urgent announcements.
 */
export async function fetchUnacknowledgedUrgentAnnouncement(
  profileId?: string | null
): Promise<Announcement | null> {
  if (!profileId) return null;
  const supabase = createClient();

  // 1. Fetch active urgent announcements
  const { data: urgentItems, error } = await supabase
    .from("announcements")
    .select("id, title, content, priority, is_pinned, created_at")
    .eq("status", "active")
    .eq("priority", "urgent")
    .or(`expires_at.is.null,expires_at.gt.${new Date().toISOString()}`)
    .order("created_at", { ascending: false });

  if (error || !urgentItems || urgentItems.length === 0) {
    return null;
  }

  // 2. Check which ones have been acknowledged
  const urgentIds = urgentItems.map((u) => u.id);
  const { data: acks, error: ackError } = await supabase
    .from("announcement_acknowledgements")
    .select("announcement_id")
    .eq("user_id", profileId)
    .in("announcement_id", urgentIds);

  if (ackError) {
    console.error("[announcements] Error checking acks:", ackError);
    return urgentItems[0] as unknown as Announcement;
  }

  const ackSet = new Set((acks || []).map((a) => a.announcement_id));
  const unacked = urgentItems.find((u) => !ackSet.has(u.id));

  return (unacked as unknown as Announcement) || null;
}

/**
 * Acknowledge an urgent announcement.
 */
export async function acknowledgeUrgentAnnouncement(
  announcementId: string,
  profileId: string
): Promise<boolean> {
  const supabase = createClient();

  const { error } = await supabase
    .from("announcement_acknowledgements")
    .insert({
      announcement_id: announcementId,
      user_id: profileId,
    });

  if (error && error.code !== "23505") { // Ignore unique constraint violation
    console.error("[announcements] Error acknowledging urgent announcement:", error);
    return false;
  }

  return true;
}

/**
 * Create a new announcement (Super Admin & Head Admin).
 */
export async function createAnnouncement(
  input: CreateAnnouncementInput,
  profileId?: string | null
): Promise<Announcement | null> {
  const supabase = createClient();

  // 1. Try dedicated RPC first
  try {
    const { data: rpcData, error: rpcError } = await supabase.rpc("create_announcement", {
      p_title: input.title.trim(),
      p_content: input.content.trim(),
      p_priority: input.priority || "info",
      p_is_pinned: !!input.is_pinned,
      p_target_roles: input.target_roles && input.target_roles.length > 0 ? input.target_roles : null,
      p_target_group_ids: input.target_group_ids && input.target_group_ids.length > 0 ? input.target_group_ids : null,
      p_expires_at: input.expires_at || null,
    });

    if (!rpcError && rpcData) {
      return rpcData as unknown as Announcement;
    }

    if (rpcError && rpcError.code !== "PGRST202" && !rpcError.message.includes("function create_announcement")) {
      console.error("[PostgREST Schema Error] [announcements] create_announcement RPC error:", rpcError);
      throw new Error(rpcError.message || "Failed to create announcement");
    }
  } catch (err) {
    if (err instanceof Error && !err.message.includes("function create_announcement") && !err.message.includes("PGRST202")) {
      throw err;
    }
  }

  // 2. Direct insert fallback
  let resolvedProfileId = profileId?.trim() || null;
  if (!resolvedProfileId) {
    const { data: authData } = await supabase.auth.getUser();
    if (authData?.user?.id) {
      const { data: profile } = await supabase
        .from("users_profile")
        .select("id")
        .eq("auth_user_id", authData.user.id)
        .maybeSingle();
      if (profile?.id) {
        resolvedProfileId = profile.id;
      }
    }
  }

  const insertPayload: Record<string, unknown> = {
    title: input.title.trim(),
    content: input.content.trim(),
    priority: input.priority || "info",
    is_pinned: !!input.is_pinned,
    status: "active",
    target_roles: input.target_roles && input.target_roles.length > 0 ? input.target_roles : null,
    target_group_ids: input.target_group_ids && input.target_group_ids.length > 0 ? input.target_group_ids : null,
    expires_at: input.expires_at || null,
  };

  if (resolvedProfileId) {
    insertPayload.created_by = resolvedProfileId;
  }

  const { data, error } = await supabase
    .from("announcements")
    .insert(insertPayload)
    .select()
    .single();

  if (error) {
    console.error("[PostgREST Schema Error] [announcements] Error creating announcement:", error);
    throw new Error(error.message || "Failed to create announcement");
  }

  return data;
}

/**
 * Archive an announcement (soft delete).
 */
export async function archiveAnnouncement(id: string): Promise<boolean> {
  const supabase = createClient();

  const { error } = await supabase
    .from("announcements")
    .update({ status: "archived", updated_at: new Date().toISOString() })
    .eq("id", id);

  if (error) {
    console.error("[PostgREST Schema Error] [announcements] Error archiving announcement:", error);
    throw new Error(error.message || "Failed to archive announcement");
  }

  return true;
}

/**
 * React Query Hook for active announcements with Supabase Realtime subscription.
 */
export function useAnnouncements() {
  const queryClient = useQueryClient();

  useEffect(() => {
    const supabase = createClient();

    const channel = supabase
      .channel("realtime:announcements")
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "announcements",
        },
        () => {
          queryClient.invalidateQueries({ queryKey: ["dashboard", "announcements"] });
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [queryClient]);

  return useQuery({
    queryKey: ["dashboard", "announcements"],
    queryFn: fetchActiveAnnouncements,
    staleTime: 60 * 1000,
  });
}
