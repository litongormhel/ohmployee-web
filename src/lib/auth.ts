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
  roleKey: "unresolved";
  groupScope: "none";
  accountScope: "none";
  moduleAccess: Record<string, WebModuleAccess>;
  status: "authenticated_profile_unresolved";
  source: "supabase_auth_only";
};

const SAFE_MINIMAL_MODULE_KEYS = new Set(["dashboard"]);

function buildMinimalModuleAccess() {
  return Object.fromEntries(
    webModules.map((module) => [
      module.key,
      {
        visible: SAFE_MINIMAL_MODULE_KEYS.has(module.key),
        reason: SAFE_MINIMAL_MODULE_KEYS.has(module.key)
          ? "Minimal authenticated shell access."
          : "Hidden until backend RBAC context is available.",
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

  return {
    currentUser: {
      authUserId: user.id,
      profileId: null,
      displayName: getDisplayName(user),
      email: user.email ?? null,
      roleKey: "unresolved",
      groupScope: "none",
      accountScope: "none",
      moduleAccess: buildMinimalModuleAccess(),
      status: "authenticated_profile_unresolved",
      source: "supabase_auth_only",
    } satisfies WebCurrentUserContext,
    error: null,
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
