import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

// ============================================================================
// Types & Interfaces
// ============================================================================

export type TempPermissionScopeType = "group" | "account" | "module";

export interface TempPermissionOverride {
  id: string;
  userId: string;
  userFullName: string;
  userEmail?: string;
  userRole: string;
  grantedBy: string;
  additionalGroups: string[];
  reason: string | null;
  expiresAt: string;
  isActive: boolean;
  notifyUser: boolean;
  createdAt: string;
  revokedAt: string | null;
  revokedBy: string | null;
  isExpired: boolean;
  expiresLabel: string;
  scopeType: TempPermissionScopeType;
  scopeItems: string[];
  displayReason: string;
}

export interface GrantTempPermissionParams {
  userId: string;
  scopeType?: TempPermissionScopeType;
  additionalGroups: string[];
  scopeItems?: string[];
  expiresAt: string;
  reason: string;
  notifyUser?: boolean;
  grantedBy?: string;
}

export interface RevokeTempPermissionParams {
  overrideId: string;
  revokedBy?: string;
  revokeReason?: string;
  userId?: string;
}

export interface TempPermissionsQueryResult {
  active: TempPermissionOverride[];
  history: TempPermissionOverride[];
  all: TempPermissionOverride[];
}

type RawTempOverrideRow = {
  id: string;
  user_id: string;
  additional_groups: unknown;
  reason: string | null;
  expires_at: string;
  is_active: boolean | null;
  notify_user: boolean | null;
  created_at: string;
  revoked_at: string | null;
  revoked_by: string | null;
  granted_by: string | null;
  users_profile: {
    id?: string;
    full_name?: string | null;
    email?: string | null;
    roles?: {
      role_name?: string | null;
    } | { role_name?: string | null }[] | null;
  } | null;
};

// ============================================================================
// Helpers
// ============================================================================

export function computeExpiresLabel(
  expiresAt: string,
  isActive: boolean,
  revokedAt?: string | null,
): string {
  if (!isActive || revokedAt) return "Revoked";
  const now = Date.now();
  const exp = new Date(expiresAt).getTime();
  const diffMs = exp - now;
  if (diffMs <= 0) return "Expired";

  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
  const diffHours = Math.floor(
    (diffMs % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60),
  );
  const diffMins = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60));

  if (diffDays > 0) {
    return `Expires in ${diffDays}d ${diffHours > 0 ? `${diffHours}h` : ""}`.trim();
  }
  if (diffHours > 0) {
    return `Expires in ${diffHours}h ${diffMins > 0 ? `${diffMins}m` : ""}`.trim();
  }
  if (diffMins > 0) {
    return `Expires in ${diffMins}m`;
  }
  return "Expires soon";
}

function parseScopeTypeAndReason(
  rawReason: string | null,
  groups: string[],
): {
  scopeType: TempPermissionScopeType;
  displayReason: string;
  scopeItems: string[];
} {
  if (!rawReason) {
    return {
      scopeType: "group",
      displayReason: "No audit justification provided.",
      scopeItems: groups,
    };
  }

  const reason = rawReason.trim();

  if (reason.startsWith("[Account Scope]")) {
    const cleanReason = reason.replace("[Account Scope]", "").trim();
    return {
      scopeType: "account",
      displayReason: cleanReason || "Account delegation override.",
      scopeItems: groups,
    };
  }

  if (reason.startsWith("[Module Scope]")) {
    const cleanReason = reason.replace("[Module Scope]", "").trim();
    return {
      scopeType: "module",
      displayReason: cleanReason || "Module delegation override.",
      scopeItems: groups,
    };
  }

  return {
    scopeType: "group",
    displayReason: reason,
    scopeItems: groups,
  };
}

// ============================================================================
// Fetchers
// ============================================================================

export async function fetchTempPermissions(
  userId?: string,
): Promise<TempPermissionsQueryResult> {
  const supabase = createClient();

  let query = supabase
    .from("temp_permission_overrides")
    .select(`
      id,
      user_id,
      additional_groups,
      reason,
      expires_at,
      is_active,
      notify_user,
      created_at,
      revoked_at,
      revoked_by,
      granted_by,
      users_profile (
        id,
        full_name,
        email,
        roles (
          role_name
        )
      )
    `)
    .order("created_at", { ascending: false });

  if (userId) {
    query = query.eq("user_id", userId);
  }

  const { data, error } = await query;
  if (error) {
    throw new Error(error.message);
  }

  const now = Date.now();
  const rows = (data ?? []) as unknown as RawTempOverrideRow[];

  const all: TempPermissionOverride[] = rows.map((row) => {
    const user = row.users_profile;
    const roleObj = Array.isArray(user?.roles) ? user?.roles[0] : user?.roles;
    const roleName = roleObj?.role_name ?? "User";
    const userFullName = user?.full_name ?? "Unknown User";
    const userEmail = user?.email ?? undefined;

    const additionalGroups = Array.isArray(row.additional_groups)
      ? row.additional_groups.map(String)
      : [];

    const isExpired = new Date(row.expires_at).getTime() < now;
    const isActive = row.is_active === true && !isExpired && !row.revoked_at;
    const expiresLabel = computeExpiresLabel(
      row.expires_at,
      Boolean(row.is_active),
      row.revoked_at,
    );

    const { scopeType, displayReason, scopeItems } = parseScopeTypeAndReason(
      row.reason,
      additionalGroups,
    );

    return {
      id: row.id,
      userId: row.user_id,
      userFullName,
      userEmail,
      userRole: roleName,
      grantedBy: row.granted_by ?? "System Administrator",
      additionalGroups,
      reason: row.reason,
      expiresAt: row.expires_at,
      isActive,
      notifyUser: row.notify_user ?? true,
      createdAt: row.created_at,
      revokedAt: row.revoked_at,
      revokedBy: row.revoked_by,
      isExpired,
      expiresLabel,
      scopeType,
      scopeItems,
      displayReason,
    };
  });

  const active = all.filter((item) => item.isActive);
  const history = all.filter((item) => !item.isActive);

  return { active, history, all };
}

export async function fetchActiveTempPermissions(
  userId?: string,
): Promise<TempPermissionOverride[]> {
  const result = await fetchTempPermissions(userId);
  return result.active;
}

export async function grantTempPermissionOverride({
  userId,
  scopeType = "group",
  additionalGroups,
  scopeItems = [],
  expiresAt,
  reason,
  notifyUser = true,
  grantedBy,
}: GrantTempPermissionParams): Promise<string> {
  const supabase = createClient();

  if (!userId) {
    throw new Error("Target user ID is required.");
  }
  if (!additionalGroups || additionalGroups.length === 0) {
    throw new Error("At least one group or operational scope must be selected.");
  }
  if (!reason.trim()) {
    throw new Error("A justification reason is mandatory for security auditing.");
  }

  // Format reason tag according to scope type
  let formattedReason = reason.trim();
  if (scopeType === "account") {
    formattedReason = `[Account Scope] ${formattedReason}`;
  } else if (scopeType === "module") {
    formattedReason = `[Module Scope] ${formattedReason}`;
  }

  const { data, error } = await supabase.rpc("grant_temp_permission_override", {
    p_user_id: userId,
    p_additional_groups: additionalGroups,
    p_expires_at: expiresAt,
    p_reason: formattedReason,
    p_notify_user: notifyUser,
    p_granted_by: grantedBy || null,
  });

  if (error) {
    throw new Error(error.message);
  }

  // Log to audit trail
  try {
    const { data: authData } = await supabase.auth.getUser();
    await supabase.from("audit_logs").insert({
      actor_id: authData?.user?.id || null,
      module: "temp_permission_overrides",
      action: "INSERT",
      record_id: userId,
      new_data: {
        override_id: data,
        scope_type: scopeType,
        additional_groups: additionalGroups,
        scope_items: scopeItems,
        expires_at: expiresAt,
        reason: formattedReason,
        granted_by: grantedBy,
      },
      role: "Super Admin",
    });
  } catch {
    // Non-blocking for audit log
  }

  return String(data);
}

export async function revokeTempPermissionOverride({
  overrideId,
  revokedBy,
  revokeReason,
  userId,
}: RevokeTempPermissionParams): Promise<void> {
  const supabase = createClient();

  if (!overrideId) {
    throw new Error("Override ID is required for revocation.");
  }

  const { error } = await supabase.rpc("revoke_temp_permission_override", {
    p_override_id: overrideId,
    p_revoked_by: revokedBy || null,
  });

  if (error) {
    throw new Error(error.message);
  }

  // Log to audit trail
  try {
    const { data: authData } = await supabase.auth.getUser();
    await supabase.from("audit_logs").insert({
      actor_id: authData?.user?.id || null,
      module: "temp_permission_overrides",
      action: "UPDATE",
      record_id: userId || overrideId,
      new_data: {
        override_id: overrideId,
        revoked_at: new Date().toISOString(),
        revoked_by: revokedBy,
        revoke_reason: revokeReason || "Revoked by administrator",
      },
      role: "Super Admin",
    });
  } catch {
    // Non-blocking
  }
}

// ============================================================================
// React Query Hooks
// ============================================================================

export function useTempPermissionsQuery(userId?: string) {
  return useQuery({
    queryKey: ["temp-permissions", userId ?? "all"],
    queryFn: () => fetchTempPermissions(userId),
    staleTime: 30 * 1000,
  });
}

export function useActiveTempPermissionsQuery(userId?: string) {
  return useQuery({
    queryKey: ["temp-permissions-active", userId ?? "all"],
    queryFn: () => fetchActiveTempPermissions(userId),
    staleTime: 30 * 1000,
  });
}

export function useGrantTempPermissionMutation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: grantTempPermissionOverride,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["temp-permissions"] });
      queryClient.invalidateQueries({ queryKey: ["temp-permissions-active"] });
      queryClient.invalidateQueries({ queryKey: ["active-temp-permission"] });
      queryClient.invalidateQueries({ queryKey: ["users-list"] });
      queryClient.invalidateQueries({ queryKey: ["users-counts"] });
      queryClient.invalidateQueries({ queryKey: ["users-audit-logs"] });
    },
  });
}

export function useRevokeTempPermissionMutation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: revokeTempPermissionOverride,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["temp-permissions"] });
      queryClient.invalidateQueries({ queryKey: ["temp-permissions-active"] });
      queryClient.invalidateQueries({ queryKey: ["active-temp-permission"] });
      queryClient.invalidateQueries({ queryKey: ["users-list"] });
      queryClient.invalidateQueries({ queryKey: ["users-counts"] });
      queryClient.invalidateQueries({ queryKey: ["users-audit-logs"] });
    },
  });
}
