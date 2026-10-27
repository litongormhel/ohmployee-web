"use client";

import type { User } from "@supabase/supabase-js";
import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { webModules, type WebModule } from "@/lib/modules";
import { isModuleAllowedForUser } from "@/lib/rbac";

export type WebModuleAccess = {
  visible: boolean;
  reason?: string;
};

export type WebCurrentUserContext = {
  authUserId: string;
  profileId: string | null;
  displayName: string | null;
  email: string | null;
  roleKey: string | null;
  roleName: string | null;
  groupScope: {
    mode: "all" | "scoped" | "none";
    ids: string[];
  };
  accountScope: {
    mode: "all" | "scoped" | "none";
    ids: string[];
  };
  allowedModuleKeys: string[];
  moduleCapabilities: Record<string, string[]>;
  moduleAccess: Record<string, WebModuleAccess>;
  accessStatus: "allowed";
  source: "get_web_current_user_context";
};

type WebScopeMode = WebCurrentUserContext["groupScope"]["mode"];

export type WebBlockedAccessReason =
  | "missing_profile"
  | "inactive"
  | "disabled"
  | "unauthorized_role"
  | "rpc_failure"
  | "unknown";

export type WebBlockedAccess = {
  reason: WebBlockedAccessReason;
  title: string;
  message: string;
};

type WebCurrentUserContextRpcRow = {
  auth_user_id?: string | null;
  profile_id?: string | null;
  full_name?: string | null;
  display_name?: string | null;
  email?: string | null;
  role_key?: string | null;
  role_name?: string | null;
  group_scope?: unknown;
  account_scope?: unknown;
  access_status?: string | null;
  status?: string | null;
  allowed_module_keys?: unknown;
  module_capabilities?: unknown;
  capabilities?: unknown;
};

const VACANCY_MODULE_KEY = "vacancy";
const DASHBOARD_MODULE_KEY = "dashboard";
const KNOWN_MODULE_KEYS = new Set(webModules.map((module) => module.key));
const SAFE_MINIMAL_MODULE_KEYS = new Set([VACANCY_MODULE_KEY, DASHBOARD_MODULE_KEY]);

function buildModuleAccess(allowedModuleKeys: string[]) {
  const visibleModuleKeys =
    allowedModuleKeys.length > 0
      ? new Set(allowedModuleKeys)
      : SAFE_MINIMAL_MODULE_KEYS;

  return Object.fromEntries(
    webModules.map((module) => [
      module.key,
      {
        visible: visibleModuleKeys.has(module.key),
        reason: visibleModuleKeys.has(module.key)
          ? "Visible from backend web RBAC context."
          : "Hidden by backend web RBAC context.",
      },
    ]),
  );
}

function getDisplayName(user: User) {
  const metadata = user.user_metadata;

  return (
    metadata?.full_name ??
    metadata?.name ??
    metadata?.display_name ??
    user.email ??
    null
  );
}

function getRpcRow(data: unknown): WebCurrentUserContextRpcRow | null {
  if (Array.isArray(data)) {
    return (data[0] ?? null) as WebCurrentUserContextRpcRow | null;
  }

  if (data && typeof data === "object") {
    return data as WebCurrentUserContextRpcRow;
  }

  return null;
}

function normalizeStringArray(value: unknown) {
  if (!Array.isArray(value)) {
    return null;
  }

  return value.filter((item): item is string => typeof item === "string");
}


function normalizeCapabilities(value: unknown) {
  if (!value || Array.isArray(value) || typeof value !== "object") {
    return null;
  }

  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>).map(([key, capabilities]) => [
      key,
      Array.isArray(capabilities)
        ? capabilities.filter((item): item is string => typeof item === "string")
        : [],
    ]),
  );
}

function getBlockedAccess(status: string | null | undefined): WebBlockedAccess {
  switch (status) {
    case "missing_profile":
    case "authenticated_profile_missing":
      return {
        reason: "missing_profile",
        title: "Profile setup required",
        message:
          "Your sign-in is valid, but no active OHMployee profile is linked to this account.",
      };
    case "inactive":
      return {
        reason: "inactive",
        title: "Account inactive",
        message:
          "Your OHMployee profile is inactive. Contact an administrator if you need web access restored.",
      };
    case "disabled":
      return {
        reason: "disabled",
        title: "Account disabled",
        message:
          "This account has been disabled for OHMployee Web access.",
      };
    case "unauthorized_role":
    case "unauthorized_web":
      return {
        reason: "unauthorized_role",
        title: "Web access not authorized",
        message:
          "Your role is not authorized for the OHMployee Web admin shell.",
      };
    case "rpc_failure":
      return {
        reason: "rpc_failure",
        title: "Access check unavailable",
        message:
          "OHMployee Web could not verify your access. Please try again or contact an administrator.",
      };
    default:
      return {
        reason: "unknown",
        title: "Access blocked",
        message:
          "OHMployee Web could not confirm that this account is allowed to use the admin shell.",
      };
  }
}

export async function loadCurrentUserContext(): Promise<{
  currentUser: WebCurrentUserContext | null;
  blockedAccess?: WebBlockedAccess | null;
  error?: unknown;
}> {
  try {
    const supabase = createClient();

    console.info("[auth] Checking Supabase session...");
    const { data: sessionData, error: sessionError } =
      await supabase.auth.getSession();

    if (sessionError) {
      console.warn("[auth] Supabase session retrieval error:", sessionError);
      return { currentUser: null, error: sessionError, blockedAccess: null };
    }

    if (!sessionData?.session) {
      console.info("[auth] No active session found. User is unauthenticated.");
      return { currentUser: null, error: null, blockedAccess: null };
    }

    console.info("[auth] Active session verified for user id:", sessionData.session.user.id);
    const { data: userData, error: userError } = await supabase.auth.getUser();

    if (userError || !userData?.user) {
      console.warn("[auth] getUser failed despite active session:", userError);
      try {
        await supabase.auth.signOut();
      } catch {
        // Ignore sign-out failure
      }
      return { currentUser: null, error: userError, blockedAccess: null };
    }

    const user = userData.user;
    console.info("[auth] Invoking get_web_current_user_context RPC for:", user.id);
    const { data: rpcData, error: rpcError } = await supabase.rpc(
      "get_web_current_user_context",
    );

    if (rpcError) {
      console.error("[auth] get_web_current_user_context RPC error:", rpcError);
      return {
        currentUser: null,
        blockedAccess: getBlockedAccess("rpc_failure"),
        error: rpcError,
      };
    }

    const rpcRow = getRpcRow(rpcData);

    if (!rpcRow) {
      console.error("[auth] get_web_current_user_context returned empty/unrecognized response:", rpcData);
      return {
        currentUser: null,
        blockedAccess: getBlockedAccess("rpc_failure"),
        error: null,
      };
    }

    const accessStatus = rpcRow.access_status ?? rpcRow.status;

    if (accessStatus !== "allowed") {
      console.warn("[auth] User access status is not 'allowed':", accessStatus);
      return {
        currentUser: null,
        blockedAccess: getBlockedAccess(accessStatus),
        error: null,
      };
    }

    const allowedModuleKeys = normalizeStringArray(rpcRow.allowed_module_keys);
    const moduleCapabilities = normalizeCapabilities(
      rpcRow.module_capabilities ?? rpcRow.capabilities,
    );

    if (
      (rpcRow.auth_user_id && rpcRow.auth_user_id !== user.id) ||
      !allowedModuleKeys ||
      !moduleCapabilities ||
      allowedModuleKeys.some((moduleKey) => !KNOWN_MODULE_KEYS.has(moduleKey)) ||
      Object.keys(moduleCapabilities).some(
        (moduleKey) => !KNOWN_MODULE_KEYS.has(moduleKey),
      )
    ) {
      console.error("[auth] RPC validation failed: row payload mismatch or unrecognized modules", {
        rpcUserId: rpcRow.auth_user_id,
        authUserId: user.id,
        allowedModuleKeys,
      });
      return {
        currentUser: null,
        blockedAccess: getBlockedAccess("rpc_failure"),
        error: null,
      };
    }

    const rawGroupScope = (rpcRow.group_scope && typeof rpcRow.group_scope === "object"
      ? rpcRow.group_scope
      : {}) as Record<string, unknown>;
    const groupMode = rawGroupScope.mode as string | undefined;
    const isGlobalHQAssigned =
      Array.isArray(rawGroupScope.groups) &&
      rawGroupScope.groups.some((g) => {
        if (g && typeof g === "object") {
          const name = String((g as Record<string, unknown>).group_name || "").toLowerCase().trim();
          const code = String((g as Record<string, unknown>).group_code || "").toLowerCase().trim();
          return name === "global hq" || code === "global_hq" || code === "globalhq";
        }
        return false;
      });

    const groupScopeMode: WebScopeMode =
      isGlobalHQAssigned || groupMode === "global" || groupMode === "all"
        ? "all"
        : groupMode === "scoped"
        ? "scoped"
        : "none";
    const groupScopeIds = Array.isArray(rawGroupScope.groups)
      ? (rawGroupScope.groups
          .map((g) => (g && typeof g === "object" ? (g as Record<string, unknown>).group_id : ""))
          .filter((id): id is string => typeof id === "string" && id.length > 0))
      : [];

    const rawAccountScope = (rpcRow.account_scope && typeof rpcRow.account_scope === "object"
      ? rpcRow.account_scope
      : {}) as Record<string, unknown>;
    const accountMode = rawAccountScope.mode as string | undefined;
    const accountScopeMode: WebScopeMode =
      isGlobalHQAssigned || accountMode === "global" || accountMode === "all"
        ? "all"
        : accountMode === "scoped" ||
          accountMode === "account" ||
          accountMode === "group_all_accounts"
        ? "scoped"
        : "none";
    const accountScopeIds = Array.isArray(rawAccountScope.accounts)
      ? (rawAccountScope.accounts
          .map((a) => {
            if (a && typeof a === "object") {
              const acc = a as Record<string, unknown>;
              return (acc.account_id ?? acc.id) as string;
            }
            return "";
          })
          .filter((id): id is string => typeof id === "string" && id.length > 0))
      : [];

    console.info(
      `[auth] Workspace context loaded successfully. Role: ${rpcRow.role_name || rpcRow.role_key || "unknown"}, Modules: [${allowedModuleKeys.join(", ")}]`
    );

    return {
      currentUser: {
        authUserId: rpcRow.auth_user_id ?? user.id,
        profileId: rpcRow.profile_id ?? null,
        displayName: rpcRow.full_name ?? rpcRow.display_name ?? getDisplayName(user),
        email: rpcRow.email ?? user.email ?? null,
        roleKey: rpcRow.role_key ?? null,
        roleName: rpcRow.role_name ?? null,
        groupScope: {
          mode: groupScopeMode,
          ids: groupScopeIds,
        },
        accountScope: {
          mode: accountScopeMode,
          ids: accountScopeIds,
        },
        allowedModuleKeys,
        moduleCapabilities,
        moduleAccess: buildModuleAccess(allowedModuleKeys),
        accessStatus: "allowed",
        source: "get_web_current_user_context",
      } satisfies WebCurrentUserContext,
      error: null,
      blockedAccess: null,
    };
  } catch (err) {
    console.error("[auth] Unexpected failure during loadCurrentUserContext:", err);
    return {
      currentUser: null,
      blockedAccess: getBlockedAccess("rpc_failure"),
      error: err,
    };
  }
}

export function getVisibleModules(
  currentUser: WebCurrentUserContext | null,
): WebModule[] {
  if (!currentUser) {
    return [];
  }

  return webModules.filter(
    (module) =>
      currentUser.moduleAccess[module.key]?.visible === true &&
      isModuleAllowedForUser(module.key, currentUser),
  );
}

/**
 * Hook to retrieve the current user context from React Query cache / loader.
 */
export function useCurrentUser() {
  const { data } = useQuery({
    queryKey: ["currentUserContext"],
    queryFn: () => loadCurrentUserContext(),
    staleTime: 5 * 60 * 1000,
  });

  return data?.currentUser ?? null;
}

/**
 * Super Admin, Head Admin, and Encoder are permitted to perform direct quota overrides.
 */
export function isQuotaOverrideRole(roleKeyOrName?: string | null): boolean {
  if (!roleKeyOrName) return false;
  const normalized = roleKeyOrName.toLowerCase().replace(/[^a-z0-9]/g, "_");
  return (
    normalized === "super_admin" ||
    normalized === "head_admin" ||
    normalized === "encoder"
  );
}

/**
 * Operations roles (OM, TL, ATL, HRCO) and Admins (Super Admin, Head Admin)
 * are permitted to submit quota amendment requests.
 */
export function isOpsAmendmentRole(roleKeyOrName?: string | null): boolean {
  if (!roleKeyOrName) return false;
  const normalized = roleKeyOrName.toLowerCase().replace(/[^a-z0-9]/g, "_");
  return (
    normalized === "super_admin" ||
    normalized === "head_admin" ||
    normalized === "operations_manager" ||
    normalized === "operations" ||
    normalized === "atl" ||
    normalized === "tl" ||
    normalized === "hrco"
  );
}

/**
 * Super Admin and Head Admin roles for high-privilege governance actions.
 */
export function isHeadOrSuperAdmin(roleKeyOrName?: string | null): boolean {
  if (!roleKeyOrName) return false;
  const normalized = roleKeyOrName.toLowerCase().replace(/[^a-z0-9]/g, "_");
  return normalized === "super_admin" || normalized === "head_admin";
}

/**
 * Head Admin, Super Admin, and HRCO/Operations roles authorized for plantilla personnel lifecycle actions.
 */
export function isPlantillaLifecycleRole(roleKeyOrName?: string | null): boolean {
  if (!roleKeyOrName) return false;
  const normalized = roleKeyOrName.toLowerCase().replace(/[^a-z0-9]/g, "_");
  return (
    normalized === "super_admin" ||
    normalized === "head_admin" ||
    normalized === "hrco" ||
    normalized === "operations_manager" ||
    normalized === "operations" ||
    normalized === "atl" ||
    normalized === "tl"
  );
}

/**
 * Administrator roles authorized for unpaginated Vacancy dataset export
 * (role_level >= 80: Super Admin, Head Admin, Data Team / Encoder).
 */
export function isVacancyExportRole(roleKeyOrName?: string | null): boolean {
  if (!roleKeyOrName) return false;
  const normalized = roleKeyOrName.toLowerCase().replace(/[^a-z0-9]/g, "_");
  return (
    normalized === "super_admin" ||
    normalized.includes("super_admin") ||
    normalized === "head_admin" ||
    normalized.includes("head_admin") ||
    normalized === "data_team" ||
    normalized.includes("data_team") ||
    normalized === "encoder" ||
    normalized.includes("encoder") ||
    normalized === "admin"
  );
}

/**
 * Checks if the role is Encoder or Data Team.
 */
export function isEncoder(roleKeyOrName?: string | null): boolean {
  if (!roleKeyOrName) return false;
  const normalized = roleKeyOrName.toLowerCase().replace(/[^a-z0-9]/g, "_");
  return (
    normalized === "encoder" ||
    normalized.includes("encoder") ||
    normalized === "data_team" ||
    normalized.includes("data_team")
  );
}



