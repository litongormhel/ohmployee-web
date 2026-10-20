"use client";

import { usePathname, useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import { AdminTopbar } from "@/components/AdminTopbar";
import { Sidebar } from "@/components/Sidebar";
import { IdleWarningModal } from "@/components/IdleWarningModal";
import { useIdleTimer } from "@/hooks/useIdleTimer";
import {
  getVisibleModules,
  loadCurrentUserContext,
  type WebBlockedAccess,
  type WebCurrentUserContext,
} from "@/lib/auth";
import { getActiveModule, getMatchedModule } from "@/lib/modules";
import { isModuleAllowedForUser } from "@/lib/rbac";
import { createClient } from "@/lib/supabase/client";
import { useActiveActingSession, useStopActingSession } from "@/lib/queries/more";

// ── Idle timer inner shell ─────────────────────────────────────────────────────

/**
 * Inner component rendered only when a user is confirmed authenticated.
 * Owns the idle timer and warning modal so they only run for authenticated sessions.
 */
function AuthenticatedShell({
  currentUser,
  children,
}: {
  currentUser: WebCurrentUserContext;
  children: React.ReactNode;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const [idleWarningOpen, setIdleWarningOpen] = useState(false);

  const { data: activeActingSession } = useActiveActingSession();
  const stopActingMutation = useStopActingSession();

  const handleStopActing = useCallback(async () => {
    try {
      await stopActingMutation.mutateAsync();
    } catch (err) {
      console.error("[acting_session] Failed to stop acting session:", err);
    }
  }, [stopActingMutation]);

  const visibleModules = useMemo(
    () => getVisibleModules(currentUser),
    [currentUser],
  );

  const matchedModule = useMemo(
    () => getMatchedModule(pathname),
    [pathname],
  );

  const activeModule = useMemo(
    () => getActiveModule(pathname, visibleModules),
    [pathname, visibleModules],
  );

  const canViewActiveModule = useMemo(() => {
    if (!matchedModule) {
      return true;
    }
    const isVisibleInList = visibleModules.some(
      (module) => module.key === matchedModule.key,
    );
    const isAllowedByRbac = isModuleAllowedForUser(matchedModule.key, currentUser);
    return isVisibleInList && isAllowedByRbac;
  }, [matchedModule, visibleModules, currentUser]);

  useEffect(() => {
    if (visibleModules.length > 0 && !canViewActiveModule) {
      const fallbackTarget = visibleModules[0]?.href ?? "/dashboard";
      if (pathname !== fallbackTarget) {
        router.replace(fallbackTarget);
      }
    }
  }, [canViewActiveModule, pathname, router, visibleModules]);

  // Perform idle logout: sign out from Supabase then redirect to login.
  // Do NOT use router.replace here before signOut — let signOut complete first.
  const handleIdleLogout = useCallback(async () => {
    setIdleWarningOpen(false);
    try {
      const supabase = createClient();
      await supabase.auth.signOut();
    } finally {
      router.replace("/login");
    }
  }, [router]);

  // Wire the idle timer. Only document-level user events reset the clock.
  // React Query refetches, Supabase realtime, and API fetches must NOT
  // call resetTimers — they are not user activity.
  const { resetTimers } = useIdleTimer({
    onWarn: () => setIdleWarningOpen(true),
    onLogout: handleIdleLogout,
  });

  const handleStaySignedIn = useCallback(() => {
    setIdleWarningOpen(false);
    resetTimers();
  }, [resetTimers]);

  if (visibleModules.length === 0) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-100 px-6">
        <section className="w-full max-w-md rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">
            OHMployee Web
          </p>
          <h1 className="mt-3 text-xl font-semibold text-slate-950">
            No Module Access
          </h1>
          <p className="mt-3 text-sm leading-6 text-slate-600">
            Your account is verified, but no web workspace modules are assigned to your role.
            Please contact an administrator to provision access.
          </p>
          <div className="mt-6">
            <button
              type="button"
              onClick={handleIdleLogout}
              className="inline-flex w-full items-center justify-center rounded-md border border-slate-300 bg-white px-4 py-2.5 text-sm font-semibold text-slate-700 shadow-xs hover:bg-slate-50 cursor-pointer"
            >
              Sign Out
            </button>
          </div>
        </section>
      </div>
    );
  }

  if (!canViewActiveModule) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-100 px-6 text-sm font-medium text-slate-600">
        Redirecting to authorized module...
      </div>
    );
  }

  return (
    <>
      <IdleWarningModal
        isOpen={idleWarningOpen}
        onStaySignedIn={handleStaySignedIn}
        onSignOut={handleIdleLogout}
      />
      <div className="flex min-h-screen bg-[var(--bg)]">
        <Sidebar
          visibleModules={visibleModules}
          moduleCapabilities={currentUser.moduleCapabilities}
          userName={currentUser.displayName || currentUser.email || "Admin"}
          userRole={currentUser.roleName || currentUser.roleKey || "Super admin"}
        />
        <div className="flex min-w-0 flex-1 flex-col">
          <AdminTopbar
            visibleModules={visibleModules}
            moduleCapabilities={currentUser.moduleCapabilities}
          />
          {activeActingSession && !activeActingSession.isExpired && (
            <div className="bg-amber-500 text-slate-950 px-4 py-2 text-xs font-semibold flex items-center justify-between border-b border-amber-600 shadow-xs z-10">
              <div className="flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-slate-950 animate-pulse" />
                <span>
                  ACTING MODE ACTIVE: Previewing scoped access as <strong>{activeActingSession.actingRole}</strong>
                  {activeActingSession.reason ? ` (“${activeActingSession.reason}”)` : ""}
                </span>
              </div>
              <button
                type="button"
                onClick={handleStopActing}
                disabled={stopActingMutation.isPending}
                className="px-2.5 py-1 rounded bg-slate-950 text-white text-[11px] font-bold hover:bg-slate-900 transition-colors shadow-2xs"
              >
                Revert to Super Admin
              </button>
            </div>
          )}
          <main className="flex-1 overflow-auto">
            <div className="w-full px-4 py-5 sm:px-5 lg:px-6 2xl:px-8">
              {children}
            </div>
          </main>
        </div>
      </div>
    </>
  );
}

// ── DashboardAuthShell ─────────────────────────────────────────────────────────

const WORKSPACE_BOOTSTRAP_TIMEOUT_MS = 8000;

export function DashboardAuthShell({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const [currentUser, setCurrentUser] = useState<WebCurrentUserContext | null>(
    null,
  );
  const [blockedAccess, setBlockedAccess] = useState<WebBlockedAccess | null>(
    null,
  );
  const [isLoading, setIsLoading] = useState(true);
  const [isTimedOut, setIsTimedOut] = useState(false);
  const [isRedirecting, setIsRedirecting] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [retryKey, setRetryKey] = useState(0);

  useEffect(() => {
    let isMounted = true;
    let timerId: ReturnType<typeof setTimeout> | null = null;

    // Safety timeout: dismiss spinner after 8 seconds if context resolution stalls
    timerId = setTimeout(() => {
      if (isMounted) {
        console.warn(
          `[DashboardAuthShell] Workspace bootstrap timed out after ${WORKSPACE_BOOTSTRAP_TIMEOUT_MS}ms.`
        );
        setIsTimedOut(true);
        setIsLoading(false);
      }
    }, WORKSPACE_BOOTSTRAP_TIMEOUT_MS);

    async function loadUser() {
      try {
        console.info("[DashboardAuthShell] Resolving session & web current user context...");
        const { currentUser: loadedUser, blockedAccess: loadedBlockedAccess, error } =
          await loadCurrentUserContext();

        if (!isMounted) {
          return;
        }

        if (timerId) {
          clearTimeout(timerId);
        }

        if (error) {
          console.warn("[DashboardAuthShell] loadCurrentUserContext returned non-blocking error:", error);
        }

        if (loadedBlockedAccess) {
          console.warn("[DashboardAuthShell] User access blocked by backend policy:", loadedBlockedAccess.reason);
          setBlockedAccess(loadedBlockedAccess);
          setIsLoading(false);
          return;
        }

        if (!loadedUser) {
          console.info("[DashboardAuthShell] No valid session or user context found. Immediately redirecting to /login...");
          setIsLoading(false);
          setIsRedirecting(true);
          router.replace("/login");
          return;
        }

        console.info("[DashboardAuthShell] Authenticated user loaded:", loadedUser.displayName || loadedUser.email);
        setCurrentUser(loadedUser);
        setBlockedAccess(null);
        setIsLoading(false);
      } catch (err) {
        if (!isMounted) {
          return;
        }
        if (timerId) {
          clearTimeout(timerId);
        }
        console.error("[DashboardAuthShell] Critical failure during loadUser bootstrap:", err);
        setLoadError(
          err instanceof Error ? err.message : "An unexpected error occurred while loading your workspace."
        );
        setIsLoading(false);
      }
    }

    loadUser();

    return () => {
      isMounted = false;
      if (timerId) {
        clearTimeout(timerId);
      }
    };
  }, [router, retryKey]);

  const handleRetry = useCallback(() => {
    console.info("[DashboardAuthShell] User triggered workspace bootstrap retry.");
    setIsLoading(true);
    setIsTimedOut(false);
    setIsRedirecting(false);
    setLoadError(null);
    setRetryKey((prev) => prev + 1);
  }, []);

  const handleGoToLogin = useCallback(() => {
    setIsRedirecting(true);
    router.replace("/login");
  }, [router]);

  if (blockedAccess) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-100 px-6">
        <section className="w-full max-w-md rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">
            OHMployee Web
          </p>
          <h1 className="mt-3 text-xl font-semibold text-slate-950">
            {blockedAccess.title}
          </h1>
          <p className="mt-3 text-sm leading-6 text-slate-600">
            {blockedAccess.message}
          </p>
          <p className="mt-5 rounded-md bg-slate-100 px-3 py-2 text-xs font-medium text-slate-600">
            Access state: {blockedAccess.reason.replaceAll("_", " ")}
          </p>
          <div className="mt-6">
            <button
              type="button"
              onClick={handleGoToLogin}
              className="inline-flex w-full items-center justify-center rounded-md border border-slate-300 bg-white px-4 py-2.5 text-sm font-semibold text-slate-700 shadow-xs hover:bg-slate-50 cursor-pointer"
            >
              Back to Login
            </button>
          </div>
        </section>
      </div>
    );
  }

  if (isTimedOut) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-100 px-6">
        <section className="w-full max-w-md rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">
            OHMployee Web
          </p>
          <h1 className="mt-3 text-xl font-semibold text-slate-950">
            Workspace Loading Delayed
          </h1>
          <p className="mt-3 text-sm leading-6 text-slate-600">
            Connecting to the secure workspace is taking longer than expected. This can happen on slow connections or during server cold-starts.
          </p>
          <div className="mt-6 flex flex-col gap-3 sm:flex-row">
            <button
              type="button"
              onClick={handleRetry}
              className="inline-flex flex-1 items-center justify-center rounded-md bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white shadow-xs hover:bg-blue-500 cursor-pointer"
            >
              Retry Connection
            </button>
            <button
              type="button"
              onClick={handleGoToLogin}
              className="inline-flex flex-1 items-center justify-center rounded-md border border-slate-300 bg-white px-4 py-2.5 text-sm font-semibold text-slate-700 shadow-xs hover:bg-slate-50 cursor-pointer"
            >
              Back to Login
            </button>
          </div>
        </section>
      </div>
    );
  }

  if (loadError) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-100 px-6">
        <section className="w-full max-w-md rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">
            OHMployee Web
          </p>
          <h1 className="mt-3 text-xl font-semibold text-slate-950">
            Workspace Connection Error
          </h1>
          <p className="mt-3 text-sm leading-6 text-slate-600">
            {loadError}
          </p>
          <div className="mt-6 flex flex-col gap-3 sm:flex-row">
            <button
              type="button"
              onClick={handleRetry}
              className="inline-flex flex-1 items-center justify-center rounded-md bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white shadow-xs hover:bg-blue-500 cursor-pointer"
            >
              Try Again
            </button>
            <button
              type="button"
              onClick={handleGoToLogin}
              className="inline-flex flex-1 items-center justify-center rounded-md border border-slate-300 bg-white px-4 py-2.5 text-sm font-semibold text-slate-700 shadow-xs hover:bg-slate-50 cursor-pointer"
            >
              Back to Login
            </button>
          </div>
        </section>
      </div>
    );
  }

  if (isRedirecting) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-100 px-6 text-sm font-medium text-slate-600">
        Redirecting to login...
      </div>
    );
  }

  if (isLoading || !currentUser) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-100 px-6 text-sm font-medium text-slate-600">
        Loading secure workspace...
      </div>
    );
  }

  return <AuthenticatedShell currentUser={currentUser}>{children}</AuthenticatedShell>;
}
