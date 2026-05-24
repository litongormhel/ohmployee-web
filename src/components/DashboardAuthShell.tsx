"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { AdminTopbar } from "@/components/AdminTopbar";
import { Sidebar } from "@/components/Sidebar";
import {
  getVisibleModules,
  loadCurrentUserContext,
  type WebCurrentUserContext,
} from "@/lib/auth";
import { getActiveModule } from "@/lib/modules";

export function DashboardAuthShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const [currentUser, setCurrentUser] = useState<WebCurrentUserContext | null>(
    null,
  );
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let isMounted = true;

    async function loadUser() {
      const { currentUser: loadedUser } = await loadCurrentUserContext();

      if (!isMounted) {
        return;
      }

      if (!loadedUser) {
        router.replace("/login");
        return;
      }

      setCurrentUser(loadedUser);
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
  const activeModule = getActiveModule(pathname);
  const canViewActiveModule = visibleModules.some(
    (module) => module.key === activeModule.key,
  );

  useEffect(() => {
    if (!isLoading && currentUser && !canViewActiveModule) {
      router.replace("/dashboard");
    }
  }, [canViewActiveModule, currentUser, isLoading, router]);

  if (isLoading || !currentUser || !canViewActiveModule) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-100 px-6 text-sm font-medium text-slate-600">
        Loading secure workspace...
      </div>
    );
  }

  return (
    <div className="flex min-h-screen bg-slate-100">
      <Sidebar visibleModules={visibleModules} />
      <div className="flex min-w-0 flex-1 flex-col">
        <AdminTopbar visibleModules={visibleModules} />
        <main className="flex-1 overflow-auto">
          <div className="mx-auto w-full max-w-7xl px-5 py-6 lg:px-8">
            {children}
          </div>
        </main>
      </div>
    </div>
  );
}
