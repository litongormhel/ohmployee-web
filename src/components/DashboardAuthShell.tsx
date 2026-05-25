"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { AdminTopbar } from "@/components/AdminTopbar";
import { Sidebar } from "@/components/Sidebar";
import {
  getVisibleModules,
  loadCurrentUserContext,
  type WebBlockedAccess,
  type WebCurrentUserContext,
} from "@/lib/auth";
import { getActiveModule } from "@/lib/modules";

export function DashboardAuthShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const [currentUser, setCurrentUser] = useState<WebCurrentUserContext | null>(
    null,
  );
  const [blockedAccess, setBlockedAccess] = useState<WebBlockedAccess | null>(
    null,
  );
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let isMounted = true;

    async function loadUser() {
      const { currentUser: loadedUser, blockedAccess: loadedBlockedAccess } =
        await loadCurrentUserContext();

      if (!isMounted) {
        return;
      }

      if (!loadedUser) {
        if (loadedBlockedAccess) {
          setBlockedAccess(loadedBlockedAccess);
          setIsLoading(false);
          return;
        }

        router.replace("/login");
        return;
      }

      setCurrentUser(loadedUser);
      setBlockedAccess(null);
      setIsLoading(false);
    }

    loadUser();

    return () => {
      isMounted = false;
    };
  }, [router]);

  const visibleModules = useMemo(
    () => getVisibleModules(currentUser),
    [currentUser],
  );
  const activeModule = getActiveModule(pathname, visibleModules);
  const canViewActiveModule = visibleModules.some(
    (module) => module.key === activeModule.key,
  );

  useEffect(() => {
    if (
      !isLoading &&
      currentUser &&
      visibleModules.length > 0 &&
      !canViewActiveModule
    ) {
      router.replace("/dashboard");
    }
  }, [canViewActiveModule, currentUser, isLoading, router, visibleModules.length]);

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
        </section>
      </div>
    );
  }

  if (isLoading || !currentUser || !canViewActiveModule) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-100 px-6 text-sm font-medium text-slate-600">
        Loading secure workspace...
      </div>
    );
  }

  return (
    <div className="flex min-h-screen bg-slate-100">
      <Sidebar
        visibleModules={visibleModules}
        moduleCapabilities={currentUser.moduleCapabilities}
      />
      <div className="flex min-w-0 flex-1 flex-col">
        <AdminTopbar
          visibleModules={visibleModules}
          moduleCapabilities={currentUser.moduleCapabilities}
        />
        <main className="flex-1 overflow-auto">
          <div className="w-full px-4 py-5 sm:px-5 lg:px-6 2xl:px-8">
            {children}
          </div>
        </main>
      </div>
    </div>
  );
}
