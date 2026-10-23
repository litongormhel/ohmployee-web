import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

// ---------------------------------------------------------------------------
// Error Handling & Helpers
// ---------------------------------------------------------------------------

export type UserDataErrorKind = "access_denied" | "validation" | "retryable";

export class UserDataError extends Error {
  kind: UserDataErrorKind;
  code?: string;

  constructor(kind: UserDataErrorKind, message: string, code?: string) {
    super(message);
    this.name = "UserDataError";
    this.kind = kind;
    this.code = code;
  }
}

export function friendlyUserError(error: unknown): string {
  if (error instanceof UserDataError) {
    return error.message;
  }

  const err = error as { code?: string; message?: string; details?: string };
  const message = (err?.message ?? "").toLowerCase();
  const code = err?.code ?? "";

  if (
    message.includes("permission denied") ||
    message.includes("not authorized") ||
    message.includes("not allowed") ||
    code === "42501"
  ) {
    return "You are not authorized to perform this action.";
  }
  if (message.includes("hrco_global_visibility only applies")) {
    return "Global Visibility only applies to the HRCO role.";
  }
  if (message.includes("last active super admin") || code === "22023") {
    return "This action is blocked because at least one active Super Admin must remain.";
  }
  if (message.includes("duplicate") || code === "23505") {
    return "A user with the same details already exists.";
  }
  if (message.includes("violates foreign key") || code === "23503") {
    return "One of the selected role or group values is no longer available.";
  }
  if (message.includes("no email address")) {
    return "This account does not have an email address for password reset.";
  }
  if (message.includes("network")) {
    return "Network error. Check your connection and try again.";
  }

  return err?.message || "Something went wrong. Please try again.";
}

// ---------------------------------------------------------------------------
// Models & Interfaces
// ---------------------------------------------------------------------------

export interface UserScopeItem {
  groupId: string;
  groupName: string;
  accountId?: string | null;
  accountName?: string | null;
}

export interface UserProfileItem {
  id: string;
  fullName: string;
  normalizedName: string;
  email: string;
  roleId: string;
  roleName: string;
  isActive: boolean;
  isLinked: boolean;
  isArchived: boolean;
  scopedGroupIds: string[];
  scopeLabel: string;
  scopes: UserScopeItem[];
  hrcoGlobalVisibility: boolean;
  status: "Active" | "Suspended" | "Archived";
  scopeSummaries: string[];
  authUserId?: string | null;
}

export interface UserCounts {
  total: number;
  active: number;
  inactive: number;
}

export interface RoleOption {
  id: string;
  name: string;
  level?: number;
}

export interface GroupOption {
  id: string;
  name: string;
}

export interface AccountOption {
  id: string;
  account_name: string;
  group_id: string;
}

export interface AuditLogEntry {
  id: string;
  actorId?: string | null;
  actorName?: string | null;
  actorRole?: string | null;
  module: string;
  action: string;
  recordId?: string | null;
  oldData?: Record<string, unknown> | null;
  newData?: Record<string, unknown> | null;
  timestamp: string;
}

// Database Row Types
type RawRole = {
  id: string;
  role_name: string;
  role_level?: number | null;
};

type RawGroup = {
  group_name?: string | null;
};

type RawAccount = {
  account_name?: string | null;
};

type RawUserScope = {
  group_id?: string | null;
  groups?: RawGroup | RawGroup[] | null;
  account_id?: string | null;
  accounts?: RawAccount | RawAccount[] | null;
};

type RawUserProfile = {
  id: string;
  full_name?: string | null;
  email?: string | null;
  auth_user_id?: string | null;
  is_active?: boolean | null;
  archived_at?: string | null;
  role_id?: string | null;
  hrco_global_visibility?: boolean | null;
  roles?: RawRole | RawRole[] | null;
  user_scopes?: RawUserScope[] | null;
};

type RawAuditLog = {
  id?: string | number | null;
  actor_id?: string | null;
  actor_name?: string | null;
  actor_role?: string | null;
  role?: string | null;
  module?: string | null;
  action?: string | null;
  record_id?: string | null;
  old_data?: Record<string, unknown> | null;
  new_data?: Record<string, unknown> | null;
  timestamp?: string | null;
};

type RawProfileLookup = {
  id?: string | null;
  auth_user_id?: string | null;
  full_name?: string | null;
  roles?: RawRole | RawRole[] | null;
};

// ---------------------------------------------------------------------------
// String & Data Normalizers
// ---------------------------------------------------------------------------

export function normalizeName(fullName: string): string {
  const trimmed = fullName.trim().replace(/\s+/g, " ");
  if (!trimmed) return "";

  let lastName = "";
  let restName = "";

  if (trimmed.includes(",")) {
    const parts = trimmed.split(",");
    lastName = parts[0].trim();
    if (parts.length > 1) {
      restName = parts.slice(1).join(",").trim();
    }
  } else {
    const words = trimmed.split(" ");
    if (words.length === 1) {
      lastName = words[0];
    } else {
      lastName = words[words.length - 1];
      restName = words.slice(0, words.length - 1).join(" ");
    }
  }

  const toProperCase = (s: string) => {
    if (!s) return "";
    return s
      .split(" ")
      .map((word) => {
        if (!word) return "";
        if (word.includes("-")) {
          return word
            .split("-")
            .map((w) => (w ? w.charAt(0).toUpperCase() + w.slice(1).toLowerCase() : ""))
            .join("-");
        }
        return word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
      })
      .join(" ");
  };

  const normalizedLast = toProperCase(lastName);
  const normalizedRest = toProperCase(restName);

  if (!normalizedRest) {
    return normalizedLast;
  }
  return `${normalizedLast}, ${normalizedRest}`;
}

export function computeScopeSummaries(scopes: UserScopeItem[]): string[] {
  if (scopes.length === 0) {
    return ["Global HQ • All Accounts"];
  }

  const grouped: Record<string, UserScopeItem[]> = {};
  for (const s of scopes) {
    if (!grouped[s.groupId]) {
      grouped[s.groupId] = [];
    }
    grouped[s.groupId].push(s);
  }

  const summaries: string[] = [];
  for (const groupId of Object.keys(grouped)) {
    const list = grouped[groupId];
    const groupName = list[0]?.groupName || "Group";
    const hasAllAccounts = list.some((s) => !s.accountId);

    if (hasAllAccounts) {
      summaries.push(`${groupName} • All Accounts`);
    } else {
      const count = list.length;
      summaries.push(`${groupName} • ${count} Account Scope${count === 1 ? "" : "s"}`);
    }
  }

  return summaries;
}

// ---------------------------------------------------------------------------
// Data Fetching Functions
// ---------------------------------------------------------------------------

export async function fetchUsersList(): Promise<UserProfileItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("users_profile")
    .select(`
      id,
      full_name,
      email,
      auth_user_id,
      is_active,
      archived_at,
      role_id,
      hrco_global_visibility,
      roles (
        id,
        role_name,
        role_level
      ),
      user_scopes (
        group_id,
        groups (
          group_name
        ),
        account_id,
        accounts (
          account_name
        )
      )
    `)
    .order("full_name");

  if (error) {
    throw new UserDataError(
      error.code === "42501" ? "access_denied" : "retryable",
      friendlyUserError(error),
      error.code,
    );
  }

  const list: UserProfileItem[] = [];
  const rows = (data ?? []) as unknown as RawUserProfile[];

  for (const row of rows) {
    const profileId = row.id;
    const roleObj = Array.isArray(row.roles) ? row.roles[0] : row.roles;
    const roleName = roleObj?.role_name ?? "";
    const isArchived = Boolean(row.archived_at);
    const isActive = row.is_active ?? true;

    const rawScopes = row.user_scopes ?? [];
    const groupIds: string[] = [];
    const groupNames: string[] = [];
    const userScopes: UserScopeItem[] = [];

    for (const s of rawScopes) {
      const gid = s.group_id;
      const gGroup = Array.isArray(s.groups) ? s.groups[0] : s.groups;
      const gname = gGroup?.group_name;
      const aid = s.account_id;
      const aAcc = Array.isArray(s.accounts) ? s.accounts[0] : s.accounts;
      const aname = aAcc?.account_name;

      if (gid) {
        if (!groupIds.includes(gid)) {
          groupIds.push(gid);
        }
        if (gname && !groupNames.includes(gname)) {
          groupNames.push(gname);
        }
        userScopes.push({
          groupId: gid,
          groupName: gname ?? "",
          accountId: aid ?? null,
          accountName: aname ?? null,
        });
      }
    }

    const status: "Active" | "Suspended" | "Archived" = isArchived
      ? "Archived"
      : !isActive
      ? "Suspended"
      : "Active";

    const fullName = row.full_name ?? "";

    list.push({
      id: profileId,
      fullName,
      normalizedName: normalizeName(fullName),
      email: row.email ?? "",
      roleId: row.role_id ?? "",
      roleName,
      isActive,
      isLinked: row.auth_user_id !== null && row.auth_user_id !== undefined,
      authUserId: row.auth_user_id ?? null,
      isArchived,
      scopedGroupIds: groupIds,
      scopeLabel: groupNames.join(", "),
      scopes: userScopes,
      hrcoGlobalVisibility: row.hrco_global_visibility ?? false,
      status,
      scopeSummaries: computeScopeSummaries(userScopes),
    });
  }

  return list;
}

export async function fetchUserCounts(): Promise<UserCounts> {
  const users = await fetchUsersList();
  const total = users.length;
  const active = users.filter((u) => u.status === "Active").length;
  const inactive = users.filter((u) => u.status !== "Active").length;
  return { total, active, inactive };
}

export async function fetchRoles(): Promise<RoleOption[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("roles")
    .select("id, role_name, role_level")
    .order("role_name");

  if (error) {
    throw new UserDataError(
      error.code === "42501" ? "access_denied" : "retryable",
      friendlyUserError(error),
      error.code,
    );
  }

  const rows = (data ?? []) as unknown as RawRole[];
  return rows.map((r) => ({
    id: r.id,
    name: r.role_name,
    level: r.role_level ?? 0,
  }));
}

export async function fetchGroups(): Promise<GroupOption[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("groups")
    .select("id, group_name")
    .order("group_name");

  if (error) {
    throw new UserDataError(
      error.code === "42501" ? "access_denied" : "retryable",
      friendlyUserError(error),
      error.code,
    );
  }

  const rows = (data ?? []) as unknown as { id: string; group_name: string }[];
  return rows.map((g) => ({
    id: g.id,
    name: g.group_name,
  }));
}

export async function fetchAccountsByGroups(
  groupIds: string[],
): Promise<AccountOption[]> {
  if (groupIds.length === 0) return [];
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_get_accounts_by_groups", {
    p_group_ids: groupIds,
  });

  if (error) {
    throw new UserDataError(
      error.code === "42501" ? "access_denied" : "retryable",
      friendlyUserError(error),
      error.code,
    );
  }

  return (data ?? []) as AccountOption[];
}

export async function fetchUserAuditLogs(userId: string): Promise<AuditLogEntry[]> {
  if (!userId) return [];
  const supabase = createClient();
  const { data, error } = await supabase
    .from("audit_logs")
    .select("*")
    .eq("record_id", userId)
    .order("timestamp", { ascending: false });

  if (error) {
    throw new UserDataError(
      error.code === "42501" ? "access_denied" : "retryable",
      friendlyUserError(error),
      error.code,
    );
  }

  const rawLogs = (data ?? []) as unknown as RawAuditLog[];
  if (rawLogs.length === 0) return [];

  // Collect actor IDs for readable display
  const actorIds = Array.from(
    new Set(rawLogs.map((l) => l.actor_id).filter((id): id is string => Boolean(id))),
  );

  const actorLookup: Record<string, { fullName: string; roleName: string }> = {};
  if (actorIds.length > 0) {
    try {
      const { data: profiles } = await supabase
        .from("users_profile")
        .select("id, auth_user_id, full_name, roles(role_name)")
        .or(`id.in.(${actorIds.join(",")}),auth_user_id.in.(${actorIds.join(",")})`);

      if (profiles) {
        const profileRows = profiles as unknown as RawProfileLookup[];
        for (const p of profileRows) {
          const roleObj = Array.isArray(p.roles) ? p.roles[0] : p.roles;
          const roleName = roleObj?.role_name ?? "User";
          const fullName = p.full_name ?? "User";
          if (p.id) actorLookup[p.id] = { fullName, roleName };
          if (p.auth_user_id) actorLookup[p.auth_user_id] = { fullName, roleName };
        }
      }
    } catch {
      // Lookup error should not fail audit log load
    }
  }

  return rawLogs.map((item) => {
    const actor = item.actor_id ? actorLookup[item.actor_id] : null;
    return {
      id: String(item.id ?? ""),
      actorId: item.actor_id ?? null,
      actorName: item.actor_name || actor?.fullName || "System Admin",
      actorRole: item.actor_role || item.role || actor?.roleName || "Admin",
      module: item.module ?? "users",
      action: item.action ?? "",
      recordId: item.record_id ?? null,
      oldData: item.old_data ?? null,
      newData: item.new_data ?? null,
      timestamp: item.timestamp ?? new Date().toISOString(),
    };
  });
}

// ---------------------------------------------------------------------------
// Backend Mutations & RPC Handlers
// ---------------------------------------------------------------------------

export interface UpsertUserParams {
  fullName: string;
  email: string;
  roleId: string;
  groupIds: string[];
  accountIds: string[];
  existingProfileId?: string | null;
}

export async function upsertUserProfileAndScopes({
  fullName,
  email,
  roleId,
  groupIds,
  accountIds,
  existingProfileId,
}: UpsertUserParams): Promise<string> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("upsert_user_profile_and_scopes", {
    p_full_name: fullName,
    p_email: email,
    p_role_id: roleId,
    p_group_ids: groupIds,
    p_account_ids: accountIds,
    p_profile_id: existingProfileId || null,
  });

  if (error) {
    throw new UserDataError(
      error.code === "42501" ? "access_denied" : "validation",
      friendlyUserError(error),
      error.code,
    );
  }

  return data ? String(data) : "";
}

export async function setUserActive(
  profileId: string,
  isActive: boolean,
): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("set_user_active", {
    p_profile_id: profileId,
    p_is_active: isActive,
  });

  if (error) {
    throw new UserDataError(
      error.code === "42501" ? "access_denied" : "validation",
      friendlyUserError(error),
      error.code,
    );
  }
}

export async function archiveUserAccount(profileId: string): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("fn_archive_user_account", {
    p_profile_id: profileId,
  });

  if (error) {
    throw new UserDataError(
      error.code === "42501" ? "access_denied" : "validation",
      friendlyUserError(error),
      error.code,
    );
  }
}

export async function requestPasswordReset(profileId: string): Promise<string> {
  const supabase = createClient();
  const { data: targetEmail, error: rpcError } = await supabase.rpc(
    "fn_log_password_reset_request",
    {
      p_profile_id: profileId,
    },
  );

  if (rpcError) {
    throw new UserDataError(
      rpcError.code === "42501" ? "access_denied" : "validation",
      friendlyUserError(rpcError),
      rpcError.code,
    );
  }

  const emailStr = targetEmail ? String(targetEmail).trim() : "";
  if (!emailStr) {
    throw new UserDataError(
      "validation",
      "No email address is registered for this account.",
    );
  }

  const { error: resetError } = await supabase.auth.resetPasswordForEmail(
    emailStr,
  );
  if (resetError) {
    throw new UserDataError("retryable", resetError.message);
  }

  return emailStr;
}

export async function setHrcoGlobalVisibility(
  profileId: string,
  enabled: boolean,
): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("set_hrco_global_visibility", {
    p_profile_id: profileId,
    p_enabled: enabled,
  });

  if (error) {
    throw new UserDataError(
      error.code === "42501" ? "access_denied" : "validation",
      friendlyUserError(error),
      error.code,
    );
  }
}

// ---------------------------------------------------------------------------
// React Query Hooks
// ---------------------------------------------------------------------------

export function useUsersList() {
  return useQuery({
    queryKey: ["users-list"],
    queryFn: () => fetchUsersList(),
    staleTime: 60 * 1000,
  });
}

export function useUserCounts() {
  return useQuery({
    queryKey: ["users-counts"],
    queryFn: () => fetchUserCounts(),
    staleTime: 60 * 1000,
  });
}

export function useRolesQuery() {
  return useQuery({
    queryKey: ["users-roles"],
    queryFn: () => fetchRoles(),
    staleTime: 5 * 60 * 1000,
  });
}

export function useGroupsQuery() {
  return useQuery({
    queryKey: ["users-groups"],
    queryFn: () => fetchGroups(),
    staleTime: 5 * 60 * 1000,
  });
}

export function useAccountsByGroupsQuery(groupIds: string[]) {
  return useQuery({
    queryKey: ["users-accounts-by-groups", groupIds.sort().join(",")],
    queryFn: () => fetchAccountsByGroups(groupIds),
    enabled: groupIds.length > 0,
    staleTime: 5 * 60 * 1000,
  });
}

export function useUserAuditLogs(userId?: string | null) {
  return useQuery({
    queryKey: ["users-audit-logs", userId],
    queryFn: () => fetchUserAuditLogs(userId!),
    enabled: Boolean(userId),
    staleTime: 30 * 1000,
  });
}

export function useUpsertUser() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (params: UpsertUserParams) => upsertUserProfileAndScopes(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["users-list"] });
      queryClient.invalidateQueries({ queryKey: ["users-counts"] });
    },
  });
}

export function useToggleUserStatus() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      profileId,
      isActive,
    }: {
      profileId: string;
      isActive: boolean;
    }) => setUserActive(profileId, isActive),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["users-list"] });
      queryClient.invalidateQueries({ queryKey: ["users-counts"] });
    },
  });
}

export function useArchiveUser() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (profileId: string) => archiveUserAccount(profileId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["users-list"] });
      queryClient.invalidateQueries({ queryKey: ["users-counts"] });
    },
  });
}

export function useResetUserPassword() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (profileId: string) => requestPasswordReset(profileId),
    onSuccess: (_data, profileId) => {
      queryClient.invalidateQueries({ queryKey: ["users-audit-logs", profileId] });
    },
  });
}

export function useSetHrcoGlobalVisibility() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      profileId,
      enabled,
    }: {
      profileId: string;
      enabled: boolean;
    }) => setHrcoGlobalVisibility(profileId, enabled),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["users-list"] });
    },
  });
}

// ---------------------------------------------------------------------------
// Temporary Permission Overrides (Parity Re-exports)
// ---------------------------------------------------------------------------
export * from "./tempPermissions";

