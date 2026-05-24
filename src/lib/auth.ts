"use client";

import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { webModules, type WebModule } from "@/lib/modules";

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
  group_scope_mode?: string | null;
  group_scope_ids?: unknown;
  account_scope_mode?: string | null;
  account_scope_ids?: unknown;
  access_status?: string | null;
  status?: string | null;
  allowed_module_keys?: unknown;
  module_capabilities?: unknown;
  capabilities?: unknown;
};

const DASHBOARD_MODULE_KEY = "dashboard";
const KNOWN_MODULE_KEYS = new Set(webModules.map((module) => module.key));
const SAFE_MINIMAL_MODULE_KEYS = new Set([DASHBOARD_MODULE_KEY]);
const VALID_SCOPE_MODES = new Set<WebScopeMode>(["all", "scoped", "none"]);

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

function normalizeScopeMode(value: string | null | undefined): WebScopeMode {
  return value && VALID_SCOPE_MODES.has(value as WebScopeMode)
    ? (value as WebScopeMode)
    : "none";
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

export async function loadCurrentUserContext() {
  const supabase = createClient();
  const { data: sessionData, error: sessionError } =
    await supabase.auth.getSession();

  if (sessionError || !sessionData.session) {
    return { currentUser: null, error: sessionError };
  }

  const { data: userData, error: userError } = await supabase.auth.getUser();

  if (userError || !userData.user) {
    await supabase.auth.signOut();
    return { currentUser: null, error: userError };
  }

  const user = userData.user;
  const { data: rpcData, error: rpcError } = await supabase.rpc(
    "get_web_current_user_context",
  );

  if (rpcError) {
    return {
      currentUser: null,
      blockedAccess: getBlockedAccess("rpc_failure"),
      error: rpcError,
    };
  }

  const rpcRow = getRpcRow(rpcData);

  if (!rpcRow) {
    return {
      currentUser: null,
      blockedAccess: getBlockedAccess("rpc_failure"),
      error: null,
    };
  }

  const accessStatus = rpcRow.access_status ?? rpcRow.status;

  if (accessStatus !== "allowed") {
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
    return {
      currentUser: null,
      blockedAccess: getBlockedAccess("rpc_failure"),
      error: null,
    };
  }

  return {
    currentUser: {
      authUserId: rpcRow.auth_user_id ?? user.id,
      profileId: rpcRow.profile_id ?? null,
      displayName: rpcRow.full_name ?? rpcRow.display_name ?? getDisplayName(user),
      email: rpcRow.email ?? user.email ?? null,
      roleKey: rpcRow.role_key ?? null,
      roleName: rpcRow.role_name ?? null,
      groupScope: {
        mode: normalizeScopeMode(rpcRow.group_scope_mode),
        ids: normalizeStringArray(rpcRow.group_scope_ids) ?? [],
      },
      accountScope: {
        mode: normalizeScopeMode(rpcRow.account_scope_mode),
        ids: normalizeStringArray(rpcRow.account_scope_ids) ?? [],
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
}

export function getVisibleModules(
  currentUser: WebCurrentUserContext | null,
): WebModule[] {
  if (!currentUser) {
    return [];
  }

  return webModules.filter(
    (module) => currentUser.moduleAccess[module.key]?.visible === true,
  );
}
