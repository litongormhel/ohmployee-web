import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

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
