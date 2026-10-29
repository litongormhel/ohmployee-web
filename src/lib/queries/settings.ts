import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

// ============================================================================
// Types & Models
// ============================================================================

export interface OwnProfileData {
  profileId: string;
  authUserId: string;
  fullName: string;
  email: string;
  roleName: string;
  roleLevel: number | null;
  mobileNumber: string | null;
  avatarPath: string | null;
  signedAvatarUrl: string | null;
  groups: string[];
  accounts: string[];
}

export interface UserSettingsData {
  userId: string;
  pushNotificationsEnabled: boolean;
  vacancyAlertsEnabled: boolean;
  approvalAlertsEnabled: boolean;
  slaBreachAlertsEnabled: boolean;
  reduceMotionEnabled: boolean;
  textSize: "Default" | "Large";
  themeMode: "system" | "light" | "dark";
  autoLogoutMinutes: number;
  biometricEnabled: boolean;
  fontFamily: string;
  updatedAt: string;
}

export interface ActiveUserSession {
  id: string;
  userId: string;
  devicePlatform: string;
  appVersion: string;
  ipAddress: string | null;
  loginAt: string;
  lastSeenAt: string;
  revokedAt: string | null;
  revokeReason: string | null;
  isSuspicious: boolean;
}

export interface SecurityAuditLog {
  id: string;
  userId: string;
  sessionId: string | null;
  action:
    | "LOGIN"
    | "LOGOUT"
    | "REMOTE_REVOKE"
    | "REVOKE"
    | "SECURITY_SETTINGS_CHANGED"
    | "SUSPICIOUS_LOGIN";
  ipAddress: string | null;
  devicePlatform: string | null;
  details: Record<string, unknown>;
  createdAt: string;
}

export interface GovernanceControl {
  controlKey: string;
  enabled: boolean;
  updatedAt: string;
  reason: string | null;
  updatedByName: string | null;
}

export interface LatencyPingResult {
  latencyMs: number;
  status: "connected" | "failed";
  timestamp: string;
}

// Storage bucket constant
export const PROFILE_PHOTOS_BUCKET = "profile_photos";
export const SIGNED_URL_TTL = 3600; // 1 hour

// ============================================================================
// Session Tracking (localStorage)
// ============================================================================

export const CURRENT_SESSION_STORAGE_KEY = "ohmployee.security.currentSessionId";

export function getCachedCurrentSessionId(): string | null {
  if (typeof window === "undefined") return null;
  try {
    return localStorage.getItem(CURRENT_SESSION_STORAGE_KEY);
  } catch {
    return null;
  }
}

export function setCachedCurrentSessionId(sessionId: string): void {
  if (typeof window === "undefined") return;
  try {
    localStorage.setItem(CURRENT_SESSION_STORAGE_KEY, sessionId);
  } catch {
    // ignore
  }
}

export function clearCachedCurrentSessionId(): void {
  if (typeof window === "undefined") return;
  try {
    localStorage.removeItem(CURRENT_SESSION_STORAGE_KEY);
  } catch {
    // ignore
  }
}

// ============================================================================
// Image Compression Utility (Canvas to WebP <= 500 KB)
// ============================================================================

export async function compressImageToWebP(
  file: File,
  maxDimension = 512,
  quality = 0.85
): Promise<Blob> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const reader = new FileReader();

    reader.onload = (e) => {
      img.src = e.target?.result as string;
    };

    reader.onerror = (err) => reject(new Error(`Failed to read file: ${err}`));

    img.onload = () => {
      let { width, height } = img;

      // Scale down to maxDimension
      if (width > maxDimension || height > maxDimension) {
        if (width > height) {
          height = Math.round((height * maxDimension) / width);
          width = maxDimension;
        } else {
          width = Math.round((width * maxDimension) / height);
          height = maxDimension;
        }
      }

      const canvas = document.createElement("canvas");
      canvas.width = width;
      canvas.height = height;

      const ctx = canvas.getContext("2d");
      if (!ctx) {
        reject(new Error("Canvas context is unavailable."));
        return;
      }

      ctx.drawImage(img, 0, 0, width, height);

      canvas.toBlob(
        (blob) => {
          if (!blob) {
            reject(new Error("Image conversion to WebP failed."));
            return;
          }
          resolve(blob);
        },
        "image/webp",
        quality
      );
    };

    img.onerror = (err) => reject(new Error(`Failed to load image: ${err}`));

    reader.readAsDataURL(file);
  });
}

// ============================================================================
// Queries: Profile
// ============================================================================

const PROFILE_TIMEOUT_MS = 15000;

async function _fetchOwnProfileInternal(): Promise<OwnProfileData> {
  const supabase = createClient();
  const { data: authData, error: authErr } = await supabase.auth.getUser();

  if (authErr || !authData.user) {
    throw new Error("Not authenticated.");
  }

  const uid = authData.user.id;

  const { data, error } = await supabase
    .from("users_profile")
    .select(
      `id, full_name, email, mobile_number, avatar_path, auth_user_id,
       roles(role_name, role_level),
       groups(group_name),
       accounts!users_profile_account_id_fkey(account_name),
       user_scopes(
         groups(group_name),
         accounts(account_name)
       )`
    )
    .eq("auth_user_id", uid)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to fetch profile: ${error.message}`);
  }

  if (!data) {
    throw new Error("Profile not found. Please contact your administrator.");
  }

  type RoleRel = { role_name?: string | null; role_level?: number | null } | null;
  type GroupRel = { group_name?: string | null } | null;
  type AccountRel = { account_name?: string | null } | null;
  type ScopeRel = {
    groups?: { group_name?: string | null } | null;
    accounts?: { account_name?: string | null } | null;
  };

  const role = (data.roles ?? null) as RoleRel;
  const directGroup = ((data.groups ?? null) as GroupRel)?.group_name;
  const directAccount = ((data.accounts ?? null) as AccountRel)?.account_name;
  const scopesRaw = (data.user_scopes ?? []) as unknown as ScopeRel[];

  const groupsSet = new Set<string>();
  if (directGroup && directGroup.trim()) groupsSet.add(directGroup.trim());
  for (const s of scopesRaw) {
    const gn = s.groups?.group_name;
    if (gn && gn.trim()) groupsSet.add(gn.trim());
  }

  const accountsSet = new Set<string>();
  if (directAccount && directAccount.trim()) accountsSet.add(directAccount.trim());
  for (const s of scopesRaw) {
    const an = s.accounts?.account_name;
    if (an && an.trim()) accountsSet.add(an.trim());
  }

  const groups = Array.from(groupsSet);
  const accounts = Array.from(accountsSet);

  const avatarPath = (data.avatar_path as string | null) ?? null;
  let signedAvatarUrl: string | null = null;

  if (avatarPath && avatarPath.trim().length > 0) {
    try {
      const { data: signedData } = await supabase.storage
        .from(PROFILE_PHOTOS_BUCKET)
        .createSignedUrl(avatarPath, SIGNED_URL_TTL);

      if (signedData?.signedUrl) {
        const v = Date.now();
        signedAvatarUrl = signedData.signedUrl.includes("?")
          ? `${signedData.signedUrl}&v=${v}`
          : `${signedData.signedUrl}?v=${v}`;
      }
    } catch (e) {
      console.warn("[settings] Failed to create signed avatar URL:", e);
    }
  }

  return {
    profileId: data.id,
    authUserId: data.auth_user_id ?? uid,
    fullName: data.full_name ?? "",
    email: data.email ?? authData.user.email ?? "",
    roleName: role?.role_name ?? "Member",
    roleLevel: role?.role_level ?? null,
    mobileNumber: data.mobile_number ?? null,
    avatarPath,
    signedAvatarUrl,
    groups,
    accounts,
  };
}

export async function fetchOwnProfile(): Promise<OwnProfileData> {
  const timeoutPromise = new Promise<never>((_, reject) =>
    setTimeout(
      () =>
        reject(
          new Error("Request timed out. Couldn't load profile information.")
        ),
      PROFILE_TIMEOUT_MS
    )
  );

  return Promise.race([_fetchOwnProfileInternal(), timeoutPromise]);
}

export function useOwnProfile() {
  return useQuery({
    queryKey: ["settings", "own-profile"],
    queryFn: fetchOwnProfile,
    staleTime: 60 * 1000,
    retry: 1,
  });
}

// ============================================================================
// Mutations: Profile & Avatar
// ============================================================================

export async function updateOwnProfileRpc(params: {
  mobileNumber?: string | null;
  avatarPath?: string | null;
}): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("update_own_profile", {
    p_mobile_number: params.mobileNumber ?? null,
    p_avatar_path: params.avatarPath ?? null,
  });

  if (error) {
    throw new Error(error.message);
  }
}

export async function uploadOwnAvatar(file: File, currentMobileNumber?: string | null): Promise<string> {
  const supabase = createClient();
  const { data: authData, error: authErr } = await supabase.auth.getUser();

  if (authErr || !authData.user) {
    throw new Error("Not authenticated.");
  }

  const uid = authData.user.id;
  const storagePath = `${uid}/avatar.webp`;

  // 1. Compress image to WebP (512x512, <= 500 KB)
  let blob = await compressImageToWebP(file, 512, 0.85);

  // If still > 500 KB, compress more aggressively
  if (blob.size > 512000) {
    blob = await compressImageToWebP(file, 400, 0.75);
  }

  if (blob.size > 512000) {
    throw new Error("Compressed avatar exceeds 500 KB limit. Please choose a smaller photo.");
  }

  // 2. Upload binary to profile_photos bucket
  const { error: uploadError } = await supabase.storage
    .from(PROFILE_PHOTOS_BUCKET)
    .upload(storagePath, blob, {
      contentType: "image/webp",
      upsert: true,
    });

  if (uploadError) {
    throw new Error(`Failed to upload avatar: ${uploadError.message}`);
  }

  // 3. Update database via update_own_profile RPC
  await updateOwnProfileRpc({
    avatarPath: storagePath,
    mobileNumber: currentMobileNumber,
  });

  // 4. Update auth metadata with cache buster
  const timestamp = Date.now();
  const publicUrl = `${supabase.storage.from(PROFILE_PHOTOS_BUCKET).getPublicUrl(storagePath).data.publicUrl}?v=${timestamp}`;

  try {
    await supabase.auth.updateUser({
      data: { avatar_url: publicUrl },
    });
  } catch (e) {
    console.warn("[settings] Auth user metadata update warning:", e);
  }

  // 5. Generate fresh signed URL
  const { data: signedData } = await supabase.storage
    .from(PROFILE_PHOTOS_BUCKET)
    .createSignedUrl(storagePath, SIGNED_URL_TTL);

  return signedData?.signedUrl ? `${signedData.signedUrl}&v=${timestamp}` : publicUrl;
}

export async function deleteOwnAvatar(currentMobileNumber?: string | null): Promise<void> {
  const supabase = createClient();
  const { data: authData, error: authErr } = await supabase.auth.getUser();

  if (authErr || !authData.user) {
    throw new Error("Not authenticated.");
  }

  const uid = authData.user.id;
  const storagePath = `${uid}/avatar.webp`;

  try {
    await supabase.storage.from(PROFILE_PHOTOS_BUCKET).remove([storagePath]);
  } catch (e) {
    console.warn("[settings] Storage remove warning:", e);
  }

  await updateOwnProfileRpc({
    avatarPath: null,
    mobileNumber: currentMobileNumber,
  });

  try {
    await supabase.auth.updateUser({
      data: { avatar_url: null },
    });
  } catch {
    // ignore
  }
}

export function useUpdateOwnProfile() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({
      mobileNumber,
      avatarPath,
    }: {
      mobileNumber?: string | null;
      avatarPath?: string | null;
    }) => {
      await updateOwnProfileRpc({ mobileNumber, avatarPath });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["settings", "own-profile"] });
      queryClient.invalidateQueries({ queryKey: ["currentUserContext"] });
    },
  });
}

// ============================================================================
// Queries & Mutations: User Settings (Preferences)
// ============================================================================

export async function fetchUserSettings(): Promise<UserSettingsData> {
  const supabase = createClient();
  const { data: authData } = await supabase.auth.getUser();

  if (!authData.user) {
    throw new Error("Not authenticated.");
  }

  // Find profile id
  const { data: prof } = await supabase
    .from("users_profile")
    .select("id")
    .eq("auth_user_id", authData.user.id)
    .maybeSingle();

  if (!prof) {
    throw new Error("User profile not found.");
  }

  const { data, error } = await supabase
    .from("user_settings")
    .select("*")
    .eq("user_id", prof.id)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to fetch user settings: ${error.message}`);
  }

  if (!data) {
    // Return standard defaults if no row yet
    return {
      userId: prof.id,
      pushNotificationsEnabled: true,
      vacancyAlertsEnabled: true,
      approvalAlertsEnabled: true,
      slaBreachAlertsEnabled: true,
      reduceMotionEnabled: false,
      textSize: "Default",
      themeMode: "light",
      autoLogoutMinutes: 30,
      biometricEnabled: false,
      fontFamily: "Inter",
      updatedAt: new Date().toISOString(),
    };
  }

  return {
    userId: data.user_id,
    pushNotificationsEnabled: data.push_notifications_enabled ?? true,
    vacancyAlertsEnabled: data.vacancy_alerts_enabled ?? true,
    approvalAlertsEnabled: data.approval_alerts_enabled ?? true,
    slaBreachAlertsEnabled: data.sla_breach_alerts_enabled ?? true,
    reduceMotionEnabled: data.reduce_motion_enabled ?? false,
    textSize: (data.text_size as "Default" | "Large") ?? "Default",
    themeMode: (data.theme_mode as "system" | "light" | "dark") ?? "light",
    autoLogoutMinutes: data.auto_logout_minutes ?? 30,
    biometricEnabled: data.biometric_enabled ?? false,
    fontFamily: data.font_family ?? "Inter",
    updatedAt: data.updated_at ?? new Date().toISOString(),
  };
}

export function useUserSettings() {
  return useQuery({
    queryKey: ["settings", "user-settings"],
    queryFn: fetchUserSettings,
    staleTime: 60 * 1000,
  });
}

export async function updateUserSettings(
  settings: Partial<Omit<UserSettingsData, "userId" | "updatedAt">>
): Promise<void> {
  const supabase = createClient();
  const { data: authData } = await supabase.auth.getUser();

  if (!authData.user) {
    throw new Error("Not authenticated.");
  }

  const { data: prof } = await supabase
    .from("users_profile")
    .select("id")
    .eq("auth_user_id", authData.user.id)
    .maybeSingle();

  if (!prof) {
    throw new Error("User profile not found.");
  }

  const payload: Record<string, unknown> = {
    user_id: prof.id,
    updated_at: new Date().toISOString(),
  };

  if (settings.pushNotificationsEnabled !== undefined) {
    payload.push_notifications_enabled = settings.pushNotificationsEnabled;
  }
  if (settings.vacancyAlertsEnabled !== undefined) {
    payload.vacancy_alerts_enabled = settings.vacancyAlertsEnabled;
  }
  if (settings.approvalAlertsEnabled !== undefined) {
    payload.approval_alerts_enabled = settings.approvalAlertsEnabled;
  }
  if (settings.slaBreachAlertsEnabled !== undefined) {
    payload.sla_breach_alerts_enabled = settings.slaBreachAlertsEnabled;
  }
  if (settings.reduceMotionEnabled !== undefined) {
    payload.reduce_motion_enabled = settings.reduceMotionEnabled;
  }
  if (settings.textSize !== undefined) {
    payload.text_size = settings.textSize;
  }
  if (settings.themeMode !== undefined) {
    payload.theme_mode = settings.themeMode;
  }
  if (settings.autoLogoutMinutes !== undefined) {
    payload.auto_logout_minutes = settings.autoLogoutMinutes;
  }
  if (settings.biometricEnabled !== undefined) {
    payload.biometric_enabled = settings.biometricEnabled;
  }
  if (settings.fontFamily !== undefined) {
    payload.font_family = settings.fontFamily;
  }

  const { error } = await supabase
    .from("user_settings")
    .upsert(payload, { onConflict: "user_id" });

  if (error) {
    throw new Error(`Failed to save settings: ${error.message}`);
  }
}

export function useUpdateUserSettings() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: updateUserSettings,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["settings", "user-settings"] });
    },
  });
}

// ============================================================================
// Queries & Mutations: Security & Active Sessions
// ============================================================================

export async function heartbeatSessionRpc(params: {
  sessionId?: string | null;
  devicePlatform?: string;
  appVersion?: string;
}): Promise<string | null> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("heartbeat_session", {
    p_session_id: params.sessionId ?? null,
    p_device_platform: params.devicePlatform ?? "Web Browser",
    p_app_version: params.appVersion ?? "1.0.0-web",
  });

  if (error) {
    if (error.message.includes("SESSION_REVOKED")) {
      throw new Error("SESSION_REVOKED");
    }
    console.warn("[settings] heartbeat error:", error);
    return null;
  }

  return (data as string) ?? null;
}

export async function fetchActiveSessions(): Promise<ActiveUserSession[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("active_user_sessions")
    .select("*")
    .order("last_seen_at", { ascending: false });

  if (error) {
    throw new Error(error.message);
  }

  return ((data ?? []) as Record<string, unknown>[]).map((row) => ({
    id: row.id as string,
    userId: row.user_id as string,
    devicePlatform: (row.device_platform as string) ?? "Unknown",
    appVersion: (row.app_version as string) ?? "1.0.0",
    ipAddress: (row.ip_address as string | null) ?? null,
    loginAt: (row.login_at as string) ?? new Date().toISOString(),
    lastSeenAt: (row.last_seen_at as string) ?? new Date().toISOString(),
    revokedAt: (row.revoked_at as string | null) ?? null,
    revokeReason: (row.revoke_reason as string | null) ?? null,
    isSuspicious: Boolean(row.is_suspicious),
  }));
}

export function useActiveSessions() {
  return useQuery({
    queryKey: ["settings", "active-sessions"],
    queryFn: fetchActiveSessions,
    staleTime: 30 * 1000,
  });
}

export async function fetchSecurityAuditLogs(): Promise<SecurityAuditLog[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("security_audit_logs")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(50);

  if (error) {
    throw new Error(error.message);
  }

  return ((data ?? []) as Record<string, unknown>[]).map((row) => ({
    id: row.id as string,
    userId: row.user_id as string,
    sessionId: (row.session_id as string | null) ?? null,
    action: (row.action as SecurityAuditLog["action"]) ?? "LOGIN",
    ipAddress: (row.ip_address as string | null) ?? null,
    devicePlatform: (row.device_platform as string | null) ?? null,
    details: (row.details as Record<string, unknown>) ?? {},
    createdAt: (row.created_at as string) ?? new Date().toISOString(),
  }));
}

export function useSecurityAuditLogs() {
  return useQuery({
    queryKey: ["settings", "security-audit-logs"],
    queryFn: fetchSecurityAuditLogs,
    staleTime: 60 * 1000,
  });
}

export async function revokeSessionRpc(sessionId: string): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("revoke_session", {
    p_session_id: sessionId,
  });

  if (error) {
    throw new Error(error.message);
  }
}

export function useRevokeSession() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: revokeSessionRpc,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["settings", "active-sessions"] });
      queryClient.invalidateQueries({ queryKey: ["settings", "security-audit-logs"] });
    },
  });
}

export async function revokeOtherSessionsRpc(currentSessionId: string): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("revoke_other_sessions", {
    p_current_session_id: currentSessionId,
  });

  if (error) {
    throw new Error(error.message);
  }
}

export function useRevokeOtherSessions() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: revokeOtherSessionsRpc,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["settings", "active-sessions"] });
      queryClient.invalidateQueries({ queryKey: ["settings", "security-audit-logs"] });
    },
  });
}

// ============================================================================
// Queries & Health Probes: Diagnostics (Super Admin)
// ============================================================================

export async function pingSupabaseLatency(): Promise<LatencyPingResult> {
  const start = performance.now();
  const supabase = createClient();

  try {
    // Lightweight check
    await supabase.rpc("fn_check_governance_control", {
      p_control_key: "account_registration",
    });

    const duration = Math.round(performance.now() - start);
    return {
      latencyMs: duration,
      status: "connected",
      timestamp: new Date().toLocaleTimeString(),
    };
  } catch {
    const duration = Math.round(performance.now() - start);
    return {
      latencyMs: duration,
      status: "failed",
      timestamp: new Date().toLocaleTimeString(),
    };
  }
}

export async function fetchGovernanceControlsRpc(): Promise<GovernanceControl[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_get_governance_controls");

  if (error) {
    throw new Error(`fn_get_governance_controls: ${error.message}`);
  }

  return ((data ?? []) as Record<string, unknown>[]).map((row) => ({
    controlKey: (row.control_key as string) ?? "",
    enabled: Boolean(row.enabled),
    updatedAt: (row.updated_at as string) ?? new Date().toISOString(),
    reason: (row.reason as string | null) ?? null,
    updatedByName: (row.updated_by_name as string | null) ?? null,
  }));
}

export async function fetchFreezeModesRpc(): Promise<GovernanceControl[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_get_freeze_modes");

  if (error) {
    throw new Error(`fn_get_freeze_modes: ${error.message}`);
  }

  return ((data ?? []) as Record<string, unknown>[]).map((row) => ({
    controlKey: (row.control_key as string) ?? "",
    enabled: Boolean(row.enabled),
    updatedAt: (row.updated_at as string) ?? new Date().toISOString(),
    reason: (row.reason as string | null) ?? null,
    updatedByName: (row.updated_by_name as string | null) ?? null,
  }));
}
