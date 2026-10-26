import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import {
  canViewCencom,
  canViewVacancy,
  canViewHrEmploc,
  canViewPlantilla,
  canViewReports,
  canManageUsers,
} from "@/lib/rbac";

// ============================================================================
// Types: Active Temp Permission
// ============================================================================

export interface ActiveTempPermission {
  id: string;
  userId: string;
  additionalGroups: string[];
  reason: string | null;
  expiresAt: string;
  isExpired: boolean;
  isActive: boolean;
  grantedBy: string;
  createdAt: string;
}

export interface TempPermissionRecord {
  id: string;
  userId: string;
  userFullName: string;
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
}

// ============================================================================
// Types: Edit Lock Status
// ============================================================================

export interface EditLockStatus {
  module: string;
  isLocked: boolean;
  lockType: string;
  scheduleText: string;
  lockedByName: string | null;
  reason: string | null;
  updatedAt: string | null;
  canEdit: boolean;
  canOverride: boolean;
  isOverrideActive: boolean;
  overrideByName: string | null;
  overrideUntil: string | null;
}

// ============================================================================
// Types: Data Archival Center & Recovery
// ============================================================================

export interface ArchivedPlantillaItem {
  id: string;
  employeeName: string;
  employeeNo: string;
  account: string;
  storeName: string;
  position: string;
  status: string;
  archiveReason: string | null;
  archivedByName: string | null;
  archivedAt: string | null;
}

export interface ArchivedVacancyItem {
  id: string;
  vcode: string;
  account: string;
  storeName: string;
  position: string;
  status: string;
  archiveReason: string | null;
  archivedByName: string | null;
  archivedAt: string | null;
}

export interface ArchivalAuditLogItem {
  id: string;
  module: string;
  recordId: string;
  actionType: string;
  reason: string | null;
  payloadSnapshot: Record<string, unknown> | null;
  createdAt: string;
}

export interface ArchiveObservationSnapshot {
  plantilla: ArchivedPlantillaItem[];
  vacancies: ArchivedVacancyItem[];
  auditLogs: ArchivalAuditLogItem[];
}

// ============================================================================
// Queries: Active Temp Permission Override for current user
// ============================================================================

export async function fetchActiveTempPermission(
  profileId: string | null
): Promise<ActiveTempPermission | null> {
  if (!profileId) return null;
  const supabase = createClient();

  try {
    const { data, error } = await supabase
      .from("temp_permission_overrides")
      .select("id, user_id, additional_groups, reason, expires_at, is_active, granted_by, created_at")
      .eq("user_id", profileId)
      .eq("is_active", true)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error || !data) return null;

    const expiresDate = data.expires_at ? new Date(data.expires_at) : null;
    const isExpired = expiresDate ? Date.now() > expiresDate.getTime() : false;

    return {
      id: data.id,
      userId: data.user_id,
      additionalGroups: Array.isArray(data.additional_groups)
        ? data.additional_groups.map(String)
        : [],
      reason: data.reason ?? null,
      expiresAt: data.expires_at,
      isExpired,
      isActive: data.is_active === true,
      grantedBy: data.granted_by ?? "Admin",
      createdAt: data.created_at,
    };
  } catch {
    return null;
  }
}

// ============================================================================
// Queries: All Temp Permissions (for Management Modal)
// ============================================================================

type TempPermissionDbRow = {
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
    full_name: string | null;
    roles: {
      role_name: string | null;
    } | null;
  } | null;
};

export async function fetchAllTempPermissions(): Promise<{
  active: TempPermissionRecord[];
  history: TempPermissionRecord[];
}> {
  const supabase = createClient();

  try {
    const { data, error } = await supabase
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
          full_name,
          roles (
            role_name
          )
        )
      `)
      .order("created_at", { ascending: false });

    if (error || !data) return { active: [], history: [] };

    const records: TempPermissionRecord[] = (data as unknown as TempPermissionDbRow[]).map((row) => {
      const userProfile = row.users_profile;
      const userRole = userProfile?.roles?.role_name ?? "User";
      const userFullName = userProfile?.full_name ?? "Unknown User";

      return {
        id: row.id,
        userId: row.user_id,
        userFullName,
        userRole,
        grantedBy: row.granted_by ?? "System Admin",
        additionalGroups: Array.isArray(row.additional_groups)
          ? row.additional_groups.map(String)
          : [],
        reason: row.reason ?? null,
        expiresAt: row.expires_at,
        isActive: row.is_active === true,
        notifyUser: row.notify_user ?? true,
        createdAt: row.created_at,
        revokedAt: row.revoked_at ?? null,
        revokedBy: row.revoked_by ?? null,
      };
    });

    const now = Date.now();
    const active = records.filter(
      (r) => r.isActive && new Date(r.expiresAt).getTime() > now
    );
    const history = records.filter(
      (r) => !r.isActive || new Date(r.expiresAt).getTime() <= now
    );

    return { active, history };
  } catch {
    return { active: [], history: [] };
  }
}

// ============================================================================
// Queries: Edit Lock Status
// ============================================================================

export async function fetchEditLockStatus(): Promise<EditLockStatus> {
  const supabase = createClient();
  const defaultStatus: EditLockStatus = {
    module: "Vacancy",
    isLocked: false,
    lockType: "Scheduled",
    scheduleText: "Monday 5:00 PM to Tuesday 2:00 PM PH time",
    lockedByName: null,
    reason: null,
    updatedAt: null,
    canEdit: true,
    canOverride: false,
    isOverrideActive: false,
    overrideByName: null,
    overrideUntil: null,
  };

  try {
    const { data, error } = await supabase.rpc("get_vacancy_edit_lock_status");
    if (error || !data) return defaultStatus;

    const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
    if (!row) return defaultStatus;

    return {
      module: "Vacancy",
      isLocked: row.is_locked === true,
      lockType: row.mode ? String(row.mode) : "Scheduled",
      scheduleText: row.schedule_description
        ? String(row.schedule_description)
        : "Monday 5:00 PM to Tuesday 2:00 PM PH time",
      lockedByName: row.locked_by_name ? String(row.locked_by_name) : null,
      reason: row.reason ? String(row.reason) : null,
      updatedAt: row.locked_at ? String(row.locked_at) : null,
      canEdit: row.can_edit === true,
      canOverride: row.can_override === true,
      isOverrideActive: row.is_override_active === true,
      overrideByName: row.override_by_name ? String(row.override_by_name) : null,
      overrideUntil: row.override_until ? String(row.override_until) : null,
    };
  } catch {
    return defaultStatus;
  }
}

// ============================================================================
// Queries: Data Archival Observation Snapshot
// ============================================================================

type ArchivedPlantillaDbRow = {
  id: string | number;
  employee_name?: string | null;
  employee_name_snapshot?: string | null;
  first_name?: string | null;
  last_name?: string | null;
  employee_no?: string | null;
  account?: string | null;
  store_name?: string | null;
  position?: string | null;
  status?: string | null;
  archive_reason?: string | null;
  archived_by_name?: string | null;
  archived_at?: string | null;
};

type ArchivedVacancyDbRow = {
  id: string | number;
  vcode?: string | null;
  vacancy_code?: string | null;
  account?: string | null;
  store_name?: string | null;
  store_branch?: string | null;
  position?: string | null;
  status?: string | null;
  archive_reason?: string | null;
  archived_by_name?: string | null;
  archived_at?: string | null;
};

type ArchivalAuditDbRow = {
  id: string | number;
  module?: string | null;
  record_id?: string | number | null;
  action_type?: string | null;
  reason?: string | null;
  payload_snapshot?: unknown;
  created_at: string;
};

export async function fetchArchiveSnapshot(limit = 80): Promise<ArchiveObservationSnapshot> {
  const supabase = createClient();

  const [plantillaRes, vacanciesRes, auditRes] = await Promise.allSettled([
    supabase
      .from("vw_archived_plantilla")
      .select("*")
      .order("archived_at", { ascending: false })
      .limit(limit),
    supabase
      .from("vw_archived_vacancies")
      .select("*")
      .order("archived_at", { ascending: false })
      .limit(limit),
    supabase
      .from("archival_audit_logs")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(limit),
  ]);

  const plantilla: ArchivedPlantillaItem[] =
    plantillaRes.status === "fulfilled" && plantillaRes.value.data
      ? (plantillaRes.value.data as ArchivedPlantillaDbRow[]).map((r) => ({
          id: String(r.id),
          employeeName:
            r.employee_name ||
            r.employee_name_snapshot ||
            [r.last_name, r.first_name].filter(Boolean).join(", ") ||
            "Unnamed employee",
          employeeNo: r.employee_no || "No employee no",
          account: r.account || "No account",
          storeName: r.store_name || "No store",
          position: r.position || "No position",
          status: r.status || "Archived",
          archiveReason: r.archive_reason ?? null,
          archivedByName: r.archived_by_name ?? null,
          archivedAt: r.archived_at ?? null,
        }))
      : [];

  const vacancies: ArchivedVacancyItem[] =
    vacanciesRes.status === "fulfilled" && vacanciesRes.value.data
      ? (vacanciesRes.value.data as ArchivedVacancyDbRow[]).map((r) => ({
          id: String(r.id),
          vcode: r.vcode || r.vacancy_code || "No VCODE",
          account: r.account || "No account",
          storeName: r.store_name || r.store_branch || "No store",
          position: r.position || "No position",
          status: r.status || "Archived",
          archiveReason: r.archive_reason ?? null,
          archivedByName: r.archived_by_name ?? null,
          archivedAt: r.archived_at ?? null,
        }))
      : [];

  const auditLogs: ArchivalAuditLogItem[] =
    auditRes.status === "fulfilled" && auditRes.value.data
      ? (auditRes.value.data as ArchivalAuditDbRow[]).map((r) => ({
          id: String(r.id),
          module: r.module || "unknown",
          recordId: String(r.record_id || ""),
          actionType: r.action_type || "audit",
          reason: r.reason ?? null,
          payloadSnapshot: (r.payload_snapshot as Record<string, unknown>) ?? null,
          createdAt: r.created_at,
        }))
      : [];

  return { plantilla, vacancies, auditLogs };
}

// ============================================================================
// Queries: Encoders and Operational Groups for Grant Temp Permission
// ============================================================================

export async function fetchEncodersAndGroups(): Promise<{
  encoders: Array<{ id: string; fullName: string }>;
  groups: Array<{ id: string; groupName: string; groupCode: string }>;
}> {
  const supabase = createClient();

  try {
    const [rolesRes, groupsRes] = await Promise.all([
      supabase.from("roles").select("id").eq("role_name", "Encoder").maybeSingle(),
      supabase.from("groups").select("id, group_name, group_code").order("group_name"),
    ]);

    let encoders: Array<{ id: string; fullName: string }> = [];
    if (rolesRes.data?.id) {
      const { data: users } = await supabase
        .from("users_profile")
        .select("id, full_name")
        .eq("role_id", rolesRes.data.id)
        .eq("is_active", true)
        .order("full_name");
      if (users) {
        encoders = users.map((u: { id: string; full_name: string | null }) => ({
          id: u.id,
          fullName: u.full_name || "Unknown",
        }));
      }
    }

    const groups = groupsRes.data
      ? groupsRes.data.map((g: { id: string; group_name: string | null; group_code: string | null }) => ({
          id: g.id,
          groupName: g.group_name || "Unnamed Group",
          groupCode: g.group_code || "",
        }))
      : [];

    return { encoders, groups };
  } catch {
    return { encoders: [], groups: [] };
  }
}

// ============================================================================
// Mutations
// ============================================================================

export async function lockVacancyEditing({ reason }: { reason: string }) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("lock_vacancy_editing", {
    p_reason: reason.trim(),
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function unlockVacancyEditing({ reason }: { reason: string }) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("unlock_vacancy_editing", {
    p_reason: reason.trim(),
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function grantTempPermission({
  userId,
  additionalGroups,
  expiresAt,
  reason,
  grantedBy,
}: {
  userId: string;
  additionalGroups: string[];
  expiresAt: string;
  reason?: string;
  grantedBy: string;
}) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("grant_temp_permission_override", {
    p_user_id: userId,
    p_additional_groups: additionalGroups,
    p_expires_at: expiresAt,
    p_reason: reason?.trim() || null,
    p_notify_user: true,
    p_granted_by: grantedBy,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function revokeTempPermission({
  overrideId,
  revokedBy,
}: {
  overrideId: string;
  revokedBy: string;
}) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("revoke_temp_permission_override", {
    p_override_id: overrideId,
    p_revoked_by: revokedBy,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function restoreArchivedPlantilla({
  plantillaId,
  reason,
}: {
  plantillaId: string;
  reason: string;
}) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("restore_plantilla_record", {
    p_plantilla_id: plantillaId,
    p_reason: reason.trim(),
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function restoreArchivedVacancy({
  vacancyId,
  reason,
}: {
  vacancyId: string;
  reason: string;
}) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("restore_vacancy_record", {
    p_vacancy_id: vacancyId,
    p_reason: reason.trim(),
  });
  if (error) throw new Error(error.message);
  return data;
}

// ============================================================================
// React Query Hooks
// ============================================================================

export function useActiveTempPermission(profileId: string | null) {
  return useQuery({
    queryKey: ["active-temp-permission", profileId],
    queryFn: () => fetchActiveTempPermission(profileId),
    enabled: !!profileId,
    refetchInterval: 60000,
  });
}

export function useAllTempPermissions() {
  return useQuery({
    queryKey: ["all-temp-permissions"],
    queryFn: () => fetchAllTempPermissions(),
  });
}

export function useEditLockStatus() {
  return useQuery({
    queryKey: ["vacancy-edit-lock-status"],
    queryFn: () => fetchEditLockStatus(),
    refetchInterval: 30000,
  });
}

export function useArchiveSnapshot() {
  return useQuery({
    queryKey: ["archive-observation-snapshot"],
    queryFn: () => fetchArchiveSnapshot(),
  });
}

export function useEncodersAndGroups() {
  return useQuery({
    queryKey: ["encoders-and-groups"],
    queryFn: () => fetchEncodersAndGroups(),
  });
}

export function useLockVacancyEditing() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: lockVacancyEditing,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["vacancy-edit-lock-status"] });
    },
  });
}

export function useUnlockVacancyEditing() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: unlockVacancyEditing,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["vacancy-edit-lock-status"] });
    },
  });
}

export function useGrantTempPermission() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: grantTempPermission,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["all-temp-permissions"] });
      queryClient.invalidateQueries({ queryKey: ["active-temp-permission"] });
    },
  });
}

export function useRevokeTempPermission() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: revokeTempPermission,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["all-temp-permissions"] });
      queryClient.invalidateQueries({ queryKey: ["active-temp-permission"] });
    },
  });
}

export function useRestorePlantilla() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: restoreArchivedPlantilla,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["archive-observation-snapshot"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
    },
  });
}

export function useRestoreVacancy() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: restoreArchivedVacancy,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["archive-observation-snapshot"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
    },
  });
}

// ============================================================================
// Access Control Center (Module Visibility Overrides)
// ============================================================================

export interface AccUser {
  id: string;
  fullName: string;
  roleName: string;
  roleLevel: number;
  groups: string[];
  accounts: string[];
}

export interface ModuleOverrideAuditItem {
  id: string;
  changedBy: string | null;
  changedByName: string | null;
  permissionKey: string;
  previousValue: string;
  newValue: string;
  reason: string;
  createdAt: string;
}

export const ACC_MODULE_KEYS = [
  "cencom.view",
  "vacancy.view",
  "hr_emploc.view",
  "plantilla.view",
  "reports.view",
  "user_management.view",
  "imports.view",
  "security.view",
] as const;

export const ACC_MODULE_LABELS: Record<string, string> = {
  "cencom.view": "CENCOM",
  "vacancy.view": "Vacancy",
  "hr_emploc.view": "HR Emploc",
  "plantilla.view": "Plantilla",
  "reports.view": "Reports",
  "user_management.view": "User Management",
  "imports.view": "Imports",
  "security.view": "Security",
};

export function getRoleModuleDefault(roleName: string, roleLevel: number, key: string): boolean {
  const normRole = roleName.toLowerCase().replace(/[^a-z0-9]/g, "_");
  const isSuperAdmin = normRole.includes("super_admin") || normRole === "owner" || roleLevel >= 100;
  const isHeadAdmin = isSuperAdmin || normRole.includes("head_admin") || roleLevel >= 90;

  const userContext = { roleName, roleLevel };

  switch (key) {
    case "cencom.view":
      return canViewCencom(userContext);
    case "vacancy.view":
      return canViewVacancy(userContext);
    case "hr_emploc.view":
      return canViewHrEmploc(userContext);
    case "plantilla.view":
      return canViewPlantilla(userContext);
    case "reports.view":
      return canViewReports(userContext);
    case "user_management.view":
      return canManageUsers(userContext);
    case "imports.view":
      return isHeadAdmin || normRole === "encoder" || roleLevel === 30;
    case "security.view":
      return isSuperAdmin;
    default:
      return false;
  }
}

export async function fetchAccUsers(): Promise<AccUser[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("users_profile")
    .select(`
      id,
      full_name,
      is_active,
      roles (role_name, role_level),
      user_scopes (
        groups (group_name),
        accounts (account_name)
      )
    `)
    .eq("is_active", true)
    .order("full_name");

  if (error || !data) return [];

  return (data as unknown as Record<string, unknown>[]).map((r) => {
    const role = (r.roles as Record<string, unknown> | null) ?? null;
    const scopes = Array.isArray(r.user_scopes) ? (r.user_scopes as Record<string, unknown>[]) : [];
    const groupsSet = new Set<string>();
    const accountsSet = new Set<string>();

    for (const s of scopes) {
      const g = s.groups as { group_name?: string } | null;
      const a = s.accounts as { account_name?: string } | null;
      if (g?.group_name) groupsSet.add(g.group_name);
      if (a?.account_name) accountsSet.add(a.account_name);
    }

    return {
      id: String(r.id),
      fullName: String(r.full_name || "Unknown"),
      roleName: String(role?.role_name || "Viewer"),
      roleLevel: Number(role?.role_level || 0),
      groups: Array.from(groupsSet).sort(),
      accounts: Array.from(accountsSet).sort(),
    };
  });
}

export async function fetchUserModuleOverrides(userId: string): Promise<Record<string, string>> {
  if (!userId) return {};
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_get_module_overrides_for_user", {
    p_target_user: userId,
  });

  if (error || !data) return {};
  return typeof data === "object" ? (data as Record<string, string>) : {};
}

export async function fetchUserModuleOverrideAudit(userId: string): Promise<ModuleOverrideAuditItem[]> {
  if (!userId) return [];
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_module_override_audit", {
    p_target_user: userId,
    p_limit: 50,
  });

  if (error || !data) return [];
  const rows = (data as unknown as Record<string, unknown>[]) || [];

  return rows.map((r) => ({
    id: String(r.id),
    changedBy: r.changed_by ? String(r.changed_by) : null,
    changedByName: r.changed_by_name ? String(r.changed_by_name) : null,
    permissionKey: String(r.permission_key || ""),
    previousValue: String(r.previous_value || "inherit"),
    newValue: String(r.new_value || "inherit"),
    reason: String(r.reason || ""),
    createdAt: String(r.created_at || ""),
  }));
}

export async function setModuleVisibilityOverride(payload: {
  userId: string;
  permissionKey: string;
  state: "allow" | "deny" | "inherit";
  reason: string;
}): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("fn_set_module_visibility_override", {
    p_target_user: payload.userId,
    p_permission_key: payload.permissionKey,
    p_new_state: payload.state,
    p_reason: payload.reason.trim(),
  });

  if (error) {
    throw new Error(error.message || "Failed to update module visibility override");
  }
}

export function useAccUsers() {
  return useQuery({
    queryKey: ["acc-users"],
    queryFn: fetchAccUsers,
  });
}

export function useUserModuleOverrides(userId: string | null) {
  return useQuery<Record<string, string>>({
    queryKey: ["acc-overrides", userId],
    queryFn: () => (userId ? fetchUserModuleOverrides(userId) : Promise.resolve({} as Record<string, string>)),
    enabled: !!userId,
  });
}

export function useUserModuleOverrideAudit(userId: string | null) {
  return useQuery({
    queryKey: ["acc-audit", userId],
    queryFn: () => (userId ? fetchUserModuleOverrideAudit(userId) : Promise.resolve([])),
    enabled: !!userId,
  });
}

export function useSetModuleVisibilityOverride() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: setModuleVisibilityOverride,
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ["acc-overrides", variables.userId] });
      queryClient.invalidateQueries({ queryKey: ["acc-audit", variables.userId] });
    },
  });
}

// ============================================================================
// Global Store Transfer
// ============================================================================

export interface StoreTransferGroupOption {
  id: string;
  name: string;
}

export interface StoreTransferAccountOption {
  id: string;
  groupId: string;
  name: string;
}

export interface StoreTransferEmployeeOption {
  id: string;
  displayName: string;
  employeeNo: string;
  currentVcode: string;
  position: string;
  currentStore: string;
  storeId: string | null;
  groupId: string;
  groupName: string;
  accountId: string;
  accountName: string;
}

export interface StoreTransferStoreOption {
  id: string;
  accountId: string;
  name: string;
}

export interface StoreTransferVacantSlotOption {
  id: string;
  vcode: string;
  position: string;
  storeId: string;
  storeName: string;
  accountName: string;
  groupName: string;
}

export async function fetchStoreTransferGroups(): Promise<StoreTransferGroupOption[]> {
  const supabase = createClient();
  try {
    const { data, error } = await supabase.rpc("get_plantilla_scope_menu");
    if (error || !data) {
      // Fallback to groups table if RPC fails or not accessible
      const { data: rawGroups } = await supabase.from("groups").select("id, group_name").order("group_name");
      return (rawGroups || []).map((g: { id: string; group_name: string }) => ({
        id: g.id,
        name: g.group_name,
      }));
    }

    const unique = new Map<string, { id: string; name: string; order: number }>();
    for (const row of data as Record<string, unknown>[]) {
      if (row.can_view === false) continue;
      const id = String(row.scope_id || row.group_id || "");
      const name = String(row.label || row.group_name || "");
      if (!id || !name) continue;
      const sortOrder = typeof row.sort_order === "number" ? row.sort_order : 0;
      if (!unique.has(id) || sortOrder < unique.get(id)!.order) {
        unique.set(id, { id, name, order: sortOrder });
      }
    }

    return Array.from(unique.values())
      .sort((a, b) => a.order - b.order)
      .map(({ id, name }) => ({ id, name }));
  } catch {
    const { data: rawGroups } = await supabase.from("groups").select("id, group_name").order("group_name");
    return (rawGroups || []).map((g: { id: string; group_name: string }) => ({
      id: g.id,
      name: g.group_name,
    }));
  }
}

export async function fetchStoreTransferAccounts(groupId: string): Promise<StoreTransferAccountOption[]> {
  if (!groupId) return [];
  const supabase = createClient();
  try {
    const { data, error } = await supabase.rpc("get_accounts_by_group", {
      p_group_id: groupId,
    });

    if (error || !data) {
      const { data: rawAccounts } = await supabase
        .from("accounts")
        .select("id, account_name, group_id")
        .eq("group_id", groupId)
        .order("account_name");
      return (rawAccounts || []).map((a: { id: string; account_name: string; group_id: string }) => ({
        id: a.id,
        groupId: a.group_id || groupId,
        name: a.account_name,
      }));
    }

    return (data as Record<string, unknown>[]).map((row) => ({
      id: String(row.account_id || row.id || ""),
      groupId: String(row.group_id || groupId),
      name: String(row.account_name || ""),
    })).filter((a) => a.id && a.name);
  } catch {
    const { data: rawAccounts } = await supabase
      .from("accounts")
      .select("id, account_name, group_id")
      .eq("group_id", groupId)
      .order("account_name");
    return (rawAccounts || []).map((a: { id: string; account_name: string; group_id: string }) => ({
      id: a.id,
      groupId: a.group_id || groupId,
      name: a.account_name,
    }));
  }
}

export async function fetchStoreTransferEmployees(params: {
  groupId: string;
  groupName: string;
  accountId: string;
  accountName: string;
}): Promise<StoreTransferEmployeeOption[]> {
  if (!params.groupId || !params.accountId) return [];
  const supabase = createClient();

  const { data, error } = await supabase
    .from("v_plantilla_safe")
    .select(
      "id, employee_name, employee_no, vcode, position, store_id, store_name, account_id, account, status, source_headcount_request_id"
    )
    .eq("account_id", params.accountId)
    .eq("status", "Active")
    .is("source_headcount_request_id", null)
    .order("employee_name");

  if (error || !data) return [];

  return (data as Record<string, unknown>[]).map((row) => ({
    id: String(row.id || ""),
    displayName: String(row.employee_name || ""),
    employeeNo: String(row.employee_no || ""),
    currentVcode: String(row.vcode || ""),
    position: String(row.position || ""),
    currentStore: String(row.store_name || ""),
    storeId: row.store_id ? String(row.store_id) : null,
    groupId: params.groupId,
    groupName: params.groupName,
    accountId: params.accountId,
    accountName: row.account ? String(row.account) : params.accountName,
  })).filter((e) => e.id);
}

export async function fetchStoreTransferStores(params: {
  groupId: string;
  accountId: string;
}): Promise<StoreTransferStoreOption[]> {
  if (!params.groupId || !params.accountId) return [];
  const supabase = createClient();

  const { data, error } = await supabase
    .from("stores")
    .select("id, account_id, store_name")
    .eq("group_id", params.groupId)
    .eq("account_id", params.accountId)
    .eq("is_active", true)
    .order("store_name");

  if (error || !data) return [];

  return (data as Record<string, unknown>[]).map((row) => ({
    id: String(row.id || ""),
    accountId: String(row.account_id || params.accountId),
    name: String(row.store_name || ""),
  })).filter((s) => s.id && s.name);
}

export async function fetchStoreTransferVacantSlots(params: {
  storeId: string;
  storeName: string;
  accountName: string;
  groupName: string;
}): Promise<StoreTransferVacantSlotOption[]> {
  if (!params.storeId) return [];
  const supabase = createClient();

  const { data, error } = await supabase
    .from("v_plantilla_safe")
    .select(
      "id, vcode, position, store_id, store_name, account, status, source_headcount_request_id"
    )
    .eq("store_id", params.storeId)
    .eq("status", "Active")
    .not("source_headcount_request_id", "is", null)
    .order("vcode");

  if (error || !data) return [];

  return (data as Record<string, unknown>[]).map((row) => ({
    id: String(row.id || ""),
    vcode: String(row.vcode || ""),
    position: String(row.position || ""),
    storeId: row.store_id ? String(row.store_id) : params.storeId,
    storeName: row.store_name ? String(row.store_name) : params.storeName,
    accountName: row.account ? String(row.account) : params.accountName,
    groupName: params.groupName,
  })).filter((s) => s.id && s.vcode);
}

export async function submitGlobalStoreTransferRequest(payload: {
  sourceScope: string;
  targetScope: string;
  reason: string;
  employees: Array<{
    employeeId: string;
    employeeName: string;
    employeeNo: string;
    sourceVcode: string;
    sourceStore: string;
    targetSlotId: string;
    targetVcode: string;
    targetStore: string;
    position: string;
  }>;
}): Promise<void> {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Insert into requests table or audit log as a pending store transfer request
  // Matches store transfer request pattern
  const { error } = await supabase.from("audit_logs").insert({
    action: "STORE_TRANSFER_REQUEST",
    module: "Transfer",
    new_data: {
      source_scope: payload.sourceScope,
      target_scope: payload.targetScope,
      reason: payload.reason,
      employees: payload.employees,
      status: "pending_sa_approval",
      requested_by: user?.id,
      requested_at: new Date().toISOString(),
    },
  });

  if (error) {
    throw new Error(error.message || "Failed to submit store transfer request");
  }
}

export function useStoreTransferGroups() {
  return useQuery({
    queryKey: ["store-transfer-groups"],
    queryFn: fetchStoreTransferGroups,
  });
}

export function useStoreTransferAccounts(groupId: string | null) {
  return useQuery({
    queryKey: ["store-transfer-accounts", groupId],
    queryFn: () => (groupId ? fetchStoreTransferAccounts(groupId) : Promise.resolve([])),
    enabled: !!groupId,
  });
}

export function useStoreTransferEmployees(params: {
  groupId: string | null;
  groupName: string;
  accountId: string | null;
  accountName: string;
}) {
  return useQuery({
    queryKey: ["store-transfer-employees", params.groupId, params.accountId],
    queryFn: () =>
      params.groupId && params.accountId
        ? fetchStoreTransferEmployees({
            groupId: params.groupId,
            groupName: params.groupName,
            accountId: params.accountId,
            accountName: params.accountName,
          })
        : Promise.resolve([]),
    enabled: !!params.groupId && !!params.accountId,
  });
}

export function useStoreTransferStores(params: {
  groupId: string | null;
  accountId: string | null;
}) {
  return useQuery({
    queryKey: ["store-transfer-stores", params.groupId, params.accountId],
    queryFn: () =>
      params.groupId && params.accountId
        ? fetchStoreTransferStores({
            groupId: params.groupId,
            accountId: params.accountId,
          })
        : Promise.resolve([]),
    enabled: !!params.groupId && !!params.accountId,
  });
}

export function useStoreTransferVacantSlots(params: {
  storeId: string | null;
  storeName: string;
  accountName: string;
  groupName: string;
}) {
  return useQuery({
    queryKey: ["store-transfer-vacant-slots", params.storeId],
    queryFn: () =>
      params.storeId
        ? fetchStoreTransferVacantSlots({
            storeId: params.storeId,
            storeName: params.storeName,
            accountName: params.accountName,
            groupName: params.groupName,
          })
        : Promise.resolve([]),
    enabled: !!params.storeId,
  });
}

export function useSubmitGlobalStoreTransfer() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: submitGlobalStoreTransferRequest,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["requests"] });
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
    },
  });
}

// ============================================================================
// Governance & Safespace Controls Types & Queries
// ============================================================================

export interface GovernanceControlItem {
  controlKey: string;
  enabled: boolean;
  updatedAt: string;
  reason: string | null;
  updatedByName: string | null;
}

export interface GovernanceAuditRecordItem {
  id: string;
  controlKey: string;
  action: string;
  beforeValue: Record<string, unknown> | null;
  afterValue: Record<string, unknown> | null;
  changedAt: string;
  reason: string | null;
  changedByName: string | null;
}

export async function fetchGovernanceControls(): Promise<GovernanceControlItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_get_governance_controls");
  if (error || !data) return [];
  return (data as Record<string, unknown>[]).map((r) => ({
    controlKey: String(r.control_key || ""),
    enabled: r.enabled === true,
    updatedAt: String(r.updated_at || new Date().toISOString()),
    reason: r.reason ? String(r.reason) : null,
    updatedByName: r.updated_by_name ? String(r.updated_by_name) : null,
  }));
}

export async function fetchGovernanceAuditLogs(): Promise<GovernanceAuditRecordItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_get_governance_audit_log");
  if (error || !data) return [];
  return (data as Record<string, unknown>[]).map((r) => ({
    id: String(r.id || ""),
    controlKey: String(r.control_key || ""),
    action: String(r.action || ""),
    beforeValue: (r.before_value as Record<string, unknown>) ?? null,
    afterValue: (r.after_value as Record<string, unknown>) ?? null,
    changedAt: String(r.changed_at || new Date().toISOString()),
    reason: r.reason ? String(r.reason) : null,
    changedByName: r.changed_by_name ? String(r.changed_by_name) : null,
  }));
}

export async function fetchRiskControls(): Promise<GovernanceControlItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_get_risk_controls");
  if (error || !data) return [];
  return (data as Record<string, unknown>[]).map((r) => ({
    controlKey: String(r.control_key || ""),
    enabled: r.enabled === true,
    updatedAt: String(r.updated_at || new Date().toISOString()),
    reason: r.reason ? String(r.reason) : null,
    updatedByName: r.updated_by_name ? String(r.updated_by_name) : null,
  }));
}

export async function fetchFreezeModes(): Promise<GovernanceControlItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_get_freeze_modes");
  if (error || !data) return [];
  return (data as Record<string, unknown>[]).map((r) => ({
    controlKey: String(r.control_key || ""),
    enabled: r.enabled === true,
    updatedAt: String(r.updated_at || new Date().toISOString()),
    reason: r.reason ? String(r.reason) : null,
    updatedByName: r.updated_by_name ? String(r.updated_by_name) : null,
  }));
}

export async function updateGovernanceControl({
  controlKey,
  enabled,
  reason,
  actorId,
}: {
  controlKey: string;
  enabled: boolean;
  reason?: string;
  actorId: string;
}) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_update_governance_control", {
    p_control_key: controlKey,
    p_enabled: enabled,
    p_reason: reason?.trim() || null,
    p_actor_id: actorId,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function updateFreezeMode({
  controlKey,
  enabled,
  reason,
  actorId,
}: {
  controlKey: string;
  enabled: boolean;
  reason: string;
  actorId: string;
}) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_update_freeze_mode", {
    p_control_key: controlKey,
    p_enabled: enabled,
    p_reason: reason.trim(),
    p_actor_id: actorId,
  });
  if (error) throw new Error(error.message);
  return data;
}

export function useGovernanceControls() {
  return useQuery({
    queryKey: ["governance-controls"],
    queryFn: fetchGovernanceControls,
  });
}

export function useGovernanceAuditLogs() {
  return useQuery({
    queryKey: ["governance-audit-logs"],
    queryFn: fetchGovernanceAuditLogs,
  });
}

export function useRiskControls() {
  return useQuery({
    queryKey: ["risk-controls"],
    queryFn: fetchRiskControls,
  });
}

export function useFreezeModes() {
  return useQuery({
    queryKey: ["freeze-modes"],
    queryFn: fetchFreezeModes,
  });
}

export function useUpdateGovernanceControl() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: updateGovernanceControl,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["governance-controls"] });
      queryClient.invalidateQueries({ queryKey: ["risk-controls"] });
      queryClient.invalidateQueries({ queryKey: ["governance-audit-logs"] });
    },
  });
}

export function useUpdateFreezeMode() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: updateFreezeMode,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["freeze-modes"] });
      queryClient.invalidateQueries({ queryKey: ["governance-controls"] });
      queryClient.invalidateQueries({ queryKey: ["governance-audit-logs"] });
    },
  });
}

// ============================================================================
// Acting Session (Switch Role) Types & Queries
// ============================================================================

export interface ActingSessionResult {
  id: string;
  actingRole: string;
  actingGroupIds: string[];
  actingAccountIds: string[];
  reason: string | null;
  startedAt: string;
  expiresAt: string;
  isExpired: boolean;
}

export interface ScopeGroupItem {
  id: string;
  groupCode: string;
  groupName: string;
}

export interface ScopeAccountItem {
  id: string;
  accountName: string;
  accountCode: string | null;
  groupId: string | null;
}

export async function fetchActiveActingSession(): Promise<ActingSessionResult | null> {
  const supabase = createClient();
  try {
    const { data, error } = await supabase.rpc("get_active_acting_session");
    if (error || !data) return null;
    const r = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
    if (!r || !r.id) return null;

    const expiresAt = String(r.expires_at || "");
    const isExpired = expiresAt ? Date.now() > new Date(expiresAt).getTime() : false;

    return {
      id: String(r.id),
      actingRole: String(r.acting_role || ""),
      actingGroupIds: Array.isArray(r.acting_group_ids)
        ? r.acting_group_ids.map(String)
        : [],
      actingAccountIds: Array.isArray(r.acting_account_ids)
        ? r.acting_account_ids.map(String)
        : [],
      reason: r.reason ? String(r.reason) : null,
      startedAt: String(r.started_at || ""),
      expiresAt,
      isExpired,
    };
  } catch {
    return null;
  }
}

export async function fetchScopeGroups(): Promise<ScopeGroupItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("groups")
    .select("id, group_code, group_name")
    .order("group_name");
  if (error || !data) return [];
  return (data as Record<string, unknown>[]).map((r) => ({
    id: String(r.id || ""),
    groupCode: String(r.group_code || ""),
    groupName: String(r.group_name || ""),
  }));
}

export async function fetchScopeAccounts(groupIds?: string[]): Promise<ScopeAccountItem[]> {
  const supabase = createClient();
  let query = supabase
    .from("accounts")
    .select("id, account_name, account_code, group_id")
    .eq("is_active", true);

  if (groupIds && groupIds.length > 0) {
    query = query.in("group_id", groupIds);
  }

  const { data, error } = await query.order("account_name");
  if (error || !data) return [];
  return (data as Record<string, unknown>[]).map((r) => ({
    id: String(r.id || ""),
    accountName: String(r.account_name || ""),
    accountCode: r.account_code ? String(r.account_code) : null,
    groupId: r.group_id ? String(r.group_id) : null,
  }));
}

export async function startActingSession({
  role,
  groupIds,
  accountIds,
  reason,
}: {
  role: string;
  groupIds?: string[];
  accountIds?: string[];
  reason: string;
}) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("start_acting_session", {
    p_acting_role: role,
    p_group_ids: groupIds && groupIds.length > 0 ? groupIds : null,
    p_account_ids: accountIds && accountIds.length > 0 ? accountIds : null,
    p_reason: reason.trim(),
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function stopActingSession() {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("stop_acting_session");
  if (error) throw new Error(error.message);
  return data;
}

export function useActiveActingSession() {
  return useQuery({
    queryKey: ["active-acting-session"],
    queryFn: fetchActiveActingSession,
    refetchInterval: 30000,
  });
}

export function useScopeGroups() {
  return useQuery({
    queryKey: ["scope-groups"],
    queryFn: fetchScopeGroups,
  });
}

export function useScopeAccounts(groupIds?: string[]) {
  return useQuery({
    queryKey: ["scope-accounts", groupIds?.join(",") || "all"],
    queryFn: () => fetchScopeAccounts(groupIds),
  });
}

export function useStartActingSession() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: startActingSession,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["active-acting-session"] });
      queryClient.invalidateQueries({ queryKey: ["currentUserContext"] });
    },
  });
}

export function useStopActingSession() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: stopActingSession,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["active-acting-session"] });
      queryClient.invalidateQueries({ queryKey: ["currentUserContext"] });
    },
  });
}

// ============================================================================
// Roving Coverage Groups Types & Queries
// ============================================================================

export interface CoverageGroupSummaryItem {
  coverageGroupId: string;
  coverageCode: string;
  accountId: string;
  accountName: string;
  groupId: string | null;
  groupName: string | null;
  positionId: string;
  positionName: string;
  employmentType: string;
  areaName: string | null;
  groupStatus: string;
  createdAt: string | null;
  requiredHc: number;
  openCount: number;
  pipelineCount: number;
  hrProcessingCount: number;
  activeCount: number;
  closedCount: number;
  mfrPct: number;
  isMfrMet: boolean;
  vacancyTab: string;
  activeStoreCount: number;
  anchorStoreId: string | null;
  anchorStoreName: string | null;
  storePreview: string | null;
}

export interface CoverageGroupDetailItem {
  id: string;
  coverageCode: string;
  accountId: string;
  accountName: string;
  groupId: string | null;
  groupName: string | null;
  positionId: string;
  positionName: string;
  employmentType: string;
  areaName: string | null;
  groupStatus: string;
  createdAt: string | null;
  requiredHc: number;
  stores: Array<{
    id: string;
    storeId: string;
    storeName: string;
    isAnchor: boolean;
    areaCity?: string | null;
    areaProvince?: string | null;
  }>;
  slots: Array<{
    id: string;
    vcode: string;
    slotStatus: string;
    assignedEmployeeName?: string | null;
  }>;
}

export async function fetchCoverageGroups(accountId?: string): Promise<CoverageGroupSummaryItem[]> {
  const supabase = createClient();
  const params: Record<string, string> = {};
  if (accountId) {
    params.p_account_id = accountId;
  }
  const { data, error } = await supabase.rpc("list_coverage_groups", params);
  if (error || !data) return [];
  return (data as Record<string, unknown>[]).map((r) => ({
    coverageGroupId: String(r.coverage_group_id || r.id || ""),
    coverageCode: String(r.coverage_code || ""),
    accountId: String(r.account_id || ""),
    accountName: String(r.account_name || ""),
    groupId: r.group_id ? String(r.group_id) : null,
    groupName: r.group_name ? String(r.group_name) : null,
    positionId: String(r.position_id || ""),
    positionName: String(r.position_name || ""),
    employmentType: String(r.employment_type || "Reliever"),
    areaName: r.area_name ? String(r.area_name) : null,
    groupStatus: String(r.group_status || "Active"),
    createdAt: r.created_at ? String(r.created_at) : null,
    requiredHc: Number(r.required_hc ?? 0),
    openCount: Number(r.open_count ?? 0),
    pipelineCount: Number(r.pipeline_count ?? 0),
    hrProcessingCount: Number(r.hr_processing_count ?? 0),
    activeCount: Number(r.active_count ?? 0),
    closedCount: Number(r.closed_count ?? 0),
    mfrPct: Number(r.mfr_pct ?? 0),
    isMfrMet: r.is_mfr_met === true,
    vacancyTab: String(r.vacancy_tab || "open"),
    activeStoreCount: Number(r.active_store_count ?? 0),
    anchorStoreId: r.anchor_store_id ? String(r.anchor_store_id) : null,
    anchorStoreName: r.anchor_store_name ? String(r.anchor_store_name) : null,
    storePreview: r.store_preview ? String(r.store_preview) : null,
  }));
}

export async function fetchCoverageGroupDetail(coverageGroupId: string): Promise<CoverageGroupDetailItem | null> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_coverage_group_detail", {
    p_coverage_group_id: coverageGroupId,
  });
  if (error || !data) return null;
  const d = data as Record<string, unknown>;
  const rawStores = Array.isArray(d.stores) ? (d.stores as Record<string, unknown>[]) : [];
  const rawSlots = Array.isArray(d.slots) ? (d.slots as Record<string, unknown>[]) : [];

  return {
    id: String(d.id || coverageGroupId),
    coverageCode: String(d.coverage_code || ""),
    accountId: String(d.account_id || ""),
    accountName: String(d.account_name || ""),
    groupId: d.group_id ? String(d.group_id) : null,
    groupName: d.group_name ? String(d.group_name) : null,
    positionId: String(d.position_id || ""),
    positionName: String(d.position_name || ""),
    employmentType: String(d.employment_type || "Reliever"),
    areaName: d.area_name ? String(d.area_name) : null,
    groupStatus: String(d.group_status || "Active"),
    createdAt: d.created_at ? String(d.created_at) : null,
    requiredHc: Number(d.required_hc ?? 0),
    stores: rawStores.map((s) => ({
      id: String(s.id || ""),
      storeId: String(s.store_id || ""),
      storeName: String(s.store_name || ""),
      isAnchor: s.is_anchor === true,
      areaCity: s.area_city ? String(s.area_city) : null,
      areaProvince: s.area_province ? String(s.area_province) : null,
    })),
    slots: rawSlots.map((sl) => ({
      id: String(sl.id || ""),
      vcode: String(sl.vcode || ""),
      slotStatus: String(sl.slot_status || "Open"),
      assignedEmployeeName: sl.assigned_employee_name ? String(sl.assigned_employee_name) : null,
    })),
  };
}

export async function createDirectCoverageGroup(params: {
  accountId: string;
  positionId: string;
  employmentType: string;
  areaName?: string;
  storeIds: string[];
  anchorStoreId: string;
}) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("create_coverage_group", {
    p_account_id: params.accountId,
    p_position_id: params.positionId,
    p_employment_type: params.employmentType,
    p_area_name: params.areaName || null,
    p_store_ids: params.storeIds,
    p_anchor_store_id: params.anchorStoreId,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function archiveDirectCoverageGroup({
  coverageGroupId,
  reason,
}: {
  coverageGroupId: string;
  reason?: string;
}) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("archive_coverage_group", {
    p_coverage_group_id: coverageGroupId,
    p_archive_reason: reason?.trim() || null,
  });
  if (error) throw new Error(error.message);
  return data;
}

export function useCoverageGroups(accountId?: string) {
  return useQuery({
    queryKey: ["coverage-groups", accountId || "all"],
    queryFn: () => fetchCoverageGroups(accountId),
  });
}

export function useCoverageGroupDetail(coverageGroupId: string | null) {
  return useQuery({
    queryKey: ["coverage-group-detail", coverageGroupId],
    queryFn: () => (coverageGroupId ? fetchCoverageGroupDetail(coverageGroupId) : Promise.resolve(null)),
    enabled: !!coverageGroupId,
  });
}

export function useCreateDirectCoverageGroup() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: createDirectCoverageGroup,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["coverage-groups"] });
    },
  });
}

export function useArchiveDirectCoverageGroup() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: archiveDirectCoverageGroup,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["coverage-groups"] });
    },
  });
}

// ============================================================================
// Bulk Archival Execution & History Types & Queries
// ============================================================================

export interface ArchiveImpactPreviewItem {
  plantillaCount: number;
  vacancyCount: number;
  hrEmplocCount: number;
  mosesHqPoolCount: number;
  mosesHqAssignmentCount: number;
  mosesHqOpenSlotCount: number;
  mosesHqRequestCount: number;
  total: number;
  mosesHqTotal: number;
}

export interface ArchiveBatchRecordItem {
  id: string;
  archiveBatchId: string;
  actionType: string;
  reason: string;
  executedByName: string;
  executedAt: string;
  rollbackDeadline: string;
  plantillaCount: number;
  vacancyCount: number;
  hrEmplocCount: number;
  mosesHqCount: number;
  totalCount: number;
  status: string;
  canRollback: boolean;
  rolledBackByName: string | null;
  rolledBackAt: string | null;
}

export async function fetchArchiveImpactPreview(): Promise<ArchiveImpactPreviewItem> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_get_archive_impact_preview");
  if (error || !data) {
    return {
      plantillaCount: 0,
      vacancyCount: 0,
      hrEmplocCount: 0,
      mosesHqPoolCount: 0,
      mosesHqAssignmentCount: 0,
      mosesHqOpenSlotCount: 0,
      mosesHqRequestCount: 0,
      total: 0,
      mosesHqTotal: 0,
    };
  }

  const d = (Array.isArray(data) ? data[0] : data) as Record<string, unknown>;
  const pc = Number(d.plantilla_count ?? 0);
  const vc = Number(d.vacancy_count ?? 0);
  const hc = Number(d.hr_emploc_count ?? 0);
  const mPool = Number(d.moses_hq_pool_count ?? 0);
  const mAssign = Number(d.moses_hq_assignment_count ?? 0);
  const mSlot = Number(d.moses_hq_open_slot_count ?? 0);
  const mReq = Number(d.moses_hq_request_count ?? 0);

  return {
    plantillaCount: pc,
    vacancyCount: vc,
    hrEmplocCount: hc,
    mosesHqPoolCount: mPool,
    mosesHqAssignmentCount: mAssign,
    mosesHqOpenSlotCount: mSlot,
    mosesHqRequestCount: mReq,
    total: pc + vc + hc,
    mosesHqTotal: mAssign + mSlot + mReq,
  };
}

export async function fetchArchiveBatchHistory(): Promise<ArchiveBatchRecordItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_get_archive_batch_history");
  if (error || !data) return [];

  const now = Date.now();
  return (data as Record<string, unknown>[]).map((r) => {
    const deadline = String(r.rollback_deadline || "");
    const status = String(r.status || "ACTIVE");
    const canRollback = status === "ACTIVE" && deadline ? now < new Date(deadline).getTime() : false;

    return {
      id: String(r.id || ""),
      archiveBatchId: String(r.archive_batch_id || ""),
      actionType: String(r.action_type || ""),
      reason: String(r.reason || ""),
      executedByName: String(r.executed_by_name || "Unknown"),
      executedAt: String(r.executed_at || ""),
      rollbackDeadline: deadline,
      plantillaCount: Number(r.plantilla_count ?? 0),
      vacancyCount: Number(r.vacancy_count ?? 0),
      hrEmplocCount: Number(r.hr_emploc_count ?? 0),
      mosesHqCount: Number(r.moses_hq_count ?? 0),
      totalCount: Number(r.total_count ?? 0),
      status,
      canRollback,
      rolledBackByName: r.rolled_back_by_name ? String(r.rolled_back_by_name) : null,
      rolledBackAt: r.rolled_back_at ? String(r.rolled_back_at) : null,
    };
  });
}

export async function executeBulkArchive({
  actionType,
  reason,
}: {
  actionType: "qa_reset" | "plantilla" | "vacancy" | "hr_emploc" | "moses_hq";
  reason: string;
}) {
  const supabase = createClient();
  let rpcName = "fn_archive_all_operational_data";
  if (actionType === "plantilla") rpcName = "fn_archive_plantilla_data";
  else if (actionType === "vacancy") rpcName = "fn_archive_vacancy_data";
  else if (actionType === "hr_emploc") rpcName = "fn_archive_hr_emploc_data";
  else if (actionType === "moses_hq") rpcName = "fn_archive_moses_hq_data";

  const { data, error } = await supabase.rpc(rpcName, {
    p_reason: reason.trim(),
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function rollbackArchiveBatch({
  batchId,
  reason,
}: {
  batchId: string;
  reason: string;
}) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_rollback_archive_batch", {
    p_batch_id: batchId,
    p_reason: reason.trim(),
  });
  if (error) throw new Error(error.message);
  return data;
}

export function useArchiveImpactPreview() {
  return useQuery({
    queryKey: ["archive-impact-preview"],
    queryFn: fetchArchiveImpactPreview,
  });
}

export function useArchiveBatchHistory() {
  return useQuery({
    queryKey: ["archive-batch-history"],
    queryFn: fetchArchiveBatchHistory,
  });
}

export function useExecuteBulkArchive() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: executeBulkArchive,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["archive-batch-history"] });
      queryClient.invalidateQueries({ queryKey: ["archive-impact-preview"] });
      queryClient.invalidateQueries({ queryKey: ["archive-observation-snapshot"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["dashboard"] });
      queryClient.invalidateQueries({ queryKey: ["cencom"] });
      queryClient.invalidateQueries({ queryKey: ["cencom-allocation-kpi"] });
      queryClient.invalidateQueries({ queryKey: ["cencom-group-kpi"] });
      queryClient.invalidateQueries({ queryKey: ["cencom-deployment-summary"] });
      queryClient.invalidateQueries({ queryKey: ["cencom-store-stats"] });
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["request-counts"] });
      queryClient.invalidateQueries({ queryKey: ["requests"] });
      queryClient.invalidateQueries({ queryKey: ["notifications"] });
      queryClient.invalidateQueries({ queryKey: ["notifications-unread-count"] });
      queryClient.invalidateQueries({ queryKey: ["notifications-counts"] });
      queryClient.invalidateQueries({ queryKey: ["stores"] });
      queryClient.invalidateQueries({ queryKey: ["operational-groups"] });
      queryClient.invalidateQueries({ queryKey: ["groups"] });
      queryClient.invalidateQueries({ queryKey: ["applicants"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc"] });
    },
  });
}

export function useRollbackArchiveBatch() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: rollbackArchiveBatch,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["archive-batch-history"] });
      queryClient.invalidateQueries({ queryKey: ["archive-impact-preview"] });
      queryClient.invalidateQueries({ queryKey: ["archive-observation-snapshot"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["dashboard"] });
      queryClient.invalidateQueries({ queryKey: ["cencom"] });
      queryClient.invalidateQueries({ queryKey: ["cencom-allocation-kpi"] });
      queryClient.invalidateQueries({ queryKey: ["cencom-group-kpi"] });
      queryClient.invalidateQueries({ queryKey: ["cencom-deployment-summary"] });
      queryClient.invalidateQueries({ queryKey: ["cencom-store-stats"] });
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["request-counts"] });
      queryClient.invalidateQueries({ queryKey: ["requests"] });
      queryClient.invalidateQueries({ queryKey: ["notifications"] });
      queryClient.invalidateQueries({ queryKey: ["notifications-unread-count"] });
      queryClient.invalidateQueries({ queryKey: ["notifications-counts"] });
      queryClient.invalidateQueries({ queryKey: ["stores"] });
      queryClient.invalidateQueries({ queryKey: ["operational-groups"] });
      queryClient.invalidateQueries({ queryKey: ["groups"] });
      queryClient.invalidateQueries({ queryKey: ["applicants"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc"] });
    },
  });
}

// Re-export governance queries & types
export * from "./governance";

