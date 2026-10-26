"use client";

import { usePathname, useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import { AdminTopbar } from "@/components/AdminTopbar";
import { Sidebar } from "@/components/Sidebar";
import { IdleWarningModal } from "@/components/IdleWarningModal";
import { useIdleTimer } from "@/hooks/useIdleTimer";
import { useMotionLevel } from "@/hooks/useMotionLevel";
import {
  getVisibleModules,
  loadCurrentUserContext,
  type WebBlockedAccess,
  type WebCurrentUserContext,
} from "@/lib/auth";
import { getMatchedModule } from "@/lib/modules";
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
  const motionLevel = useMotionLevel();
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
      <div className="flex min-h-screen items-center justify-center bg-[var(--surface-muted)] px-6">
        <section className="w-full max-w-md rounded-xl border border-[var(--border-subtle)] bg-[var(--card)] p-6 shadow-xs">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[var(--text-muted)]">
            OHMployee Web
          </p>
          <h1 className="mt-3 text-xl font-semibold text-[var(--foreground)]">
            No Module Access
          </h1>
          <p className="mt-3 text-sm leading-6 text-[var(--text-muted)]">
            Your account is verified, but no web workspace modules are assigned to your role.
            Please contact an administrator to provision access.
          </p>
          <div className="mt-6">
            <button
              type="button"
              onClick={handleIdleLogout}
              className="inline-flex w-full items-center justify-center rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] px-4 py-2.5 text-sm font-semibold text-[var(--foreground)] shadow-xs hover:bg-[var(--surface-muted)] cursor-pointer transition-colors"
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
      <div className="flex min-h-screen items-center justify-center bg-[var(--surface-muted)] px-6 text-sm font-medium text-[var(--text-muted)]">
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
      <div className="flex min-h-screen bg-[var(--background)]">
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
            <div className="bg-[var(--surface-sunken)] text-[var(--foreground)] px-4 py-2 text-xs font-semibold flex items-center justify-between border-b border-[var(--border-subtle)] shadow-xs z-10">
              <div className="flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-[var(--foreground)] animate-pulse" />
                <span>
                  ACTING MODE ACTIVE: Previewing scoped access as <strong>{activeActingSession.actingRole}</strong>
                  {activeActingSession.reason ? ` (“${activeActingSession.reason}”)` : ""}
                </span>
              </div>
              <button
                type="button"
                onClick={handleStopActing}
                disabled={stopActingMutation.isPending}
                className="px-2.5 py-1 rounded-md bg-brand-button text-white text-xs font-bold hover:bg-brand-button-hover transition-colors shadow-2xs cursor-pointer"
              >
                Revert to Super Admin
              </button>
            </div>
          )}
          <main
            key={pathname}
            className={`flex-1 overflow-auto ${
              motionLevel === "off" ? "" : "page-enter"
            }`}
          >
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
      <div className="flex min-h-screen items-center justify-center bg-[var(--surface-muted)] px-6">
        <section className="w-full max-w-md rounded-xl border border-[var(--border-subtle)] bg-[var(--card)] p-6 shadow-xs">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[var(--text-muted)]">
            OHMployee Web
          </p>
          <h1 className="mt-3 text-xl font-semibold text-[var(--foreground)]">
            {blockedAccess.title}
          </h1>
          <p className="mt-3 text-sm leading-6 text-[var(--text-muted)]">
            {blockedAccess.message}
          </p>
          <p className="mt-5 rounded-md bg-[var(--surface-sunken)] px-3 py-2 text-xs font-medium text-[var(--text-muted)] border border-[var(--border-subtle)]">
            Access state: {blockedAccess.reason.replaceAll("_", " ")}
          </p>
          <div className="mt-6">
            <button
              type="button"
              onClick={handleGoToLogin}
              className="inline-flex w-full items-center justify-center rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] px-4 py-2.5 text-sm font-semibold text-[var(--foreground)] shadow-xs hover:bg-[var(--surface-muted)] cursor-pointer transition-colors"
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
      <div className="flex min-h-screen items-center justify-center bg-[var(--surface-muted)] px-6">
        <section className="w-full max-w-md rounded-xl border border-[var(--border-subtle)] bg-[var(--card)] p-6 shadow-xs">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[var(--text-muted)]">
            OHMployee Web
          </p>
          <h1 className="mt-3 text-xl font-semibold text-[var(--foreground)]">
            Workspace Loading Delayed
          </h1>
          <p className="mt-3 text-sm leading-6 text-[var(--text-muted)]">
            Connecting to the secure workspace is taking longer than expected. This can happen on slow connections or during server cold-starts.
          </p>
          <div className="mt-6 flex flex-col gap-3 sm:flex-row">
            <button
              type="button"
              onClick={handleRetry}
              className="inline-flex flex-1 items-center justify-center rounded-lg bg-[var(--primary)] text-white px-4 py-2.5 text-sm font-semibold shadow-xs hover:opacity-90 cursor-pointer transition-colors"
            >
              Retry Connection
            </button>
            <button
              type="button"
              onClick={handleGoToLogin}
              className="inline-flex flex-1 items-center justify-center rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] px-4 py-2.5 text-sm font-semibold text-[var(--foreground)] shadow-xs hover:bg-[var(--surface-muted)] cursor-pointer transition-colors"
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
      <div className="flex min-h-screen items-center justify-center bg-[var(--surface-muted)] px-6">
        <section className="w-full max-w-md rounded-xl border border-[var(--border-subtle)] bg-[var(--card)] p-6 shadow-xs">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[var(--text-muted)]">
            OHMployee Web
          </p>
          <h1 className="mt-3 text-xl font-semibold text-[var(--foreground)]">
            Workspace Connection Error
          </h1>
          <p className="mt-3 text-sm leading-6 text-[var(--text-muted)]">
            {loadError}
          </p>
          <div className="mt-6 flex flex-col gap-3 sm:flex-row">
            <button
              type="button"
              onClick={handleRetry}
              className="inline-flex flex-1 items-center justify-center rounded-lg bg-[var(--primary)] text-white px-4 py-2.5 text-sm font-semibold shadow-xs hover:opacity-90 cursor-pointer transition-colors"
            >
              Try Again
            </button>
            <button
              type="button"
              onClick={handleGoToLogin}
              className="inline-flex flex-1 items-center justify-center rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] px-4 py-2.5 text-sm font-semibold text-[var(--foreground)] shadow-xs hover:bg-[var(--surface-muted)] cursor-pointer transition-colors"
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
      <div className="flex min-h-screen items-center justify-center bg-[var(--surface-muted)] px-6 text-sm font-medium text-[var(--text-muted)]">
        Redirecting to login...
      </div>
    );
  }

  if (isLoading || !currentUser) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-[var(--surface-muted)] px-6 text-sm font-medium text-[var(--text-muted)]">
        Loading secure workspace...
      </div>
    );
  }

  return <AuthenticatedShell currentUser={currentUser}>{children}</AuthenticatedShell>;
}
