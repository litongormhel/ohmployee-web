"use client";

import React from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { LogOut, Sparkles, Sun, Moon, Laptop, Search, Settings } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { getActiveModule, type WebModule } from "@/lib/modules";
import { useCurrentUser } from "@/lib/auth";
import { canViewApprovalsHub, hasFullAccess } from "@/lib/rbac";
import { useRequestCategoryCounts } from "@/lib/queries/requests";
import { useMyRequests, calculateMyRequestsCounts } from "@/lib/queries/my_requests";
import { useUnreadNotificationsCount } from "@/lib/queries/notifications";
import { useTheme } from "@/providers/ThemeProvider";

type SidebarProps = {
  visibleModules: WebModule[];
  moduleCapabilities: Record<string, string[]>;
  userName?: string;
  userRole?: string;
  onOpenOhmni?: () => void;
  onOpenGlobalSearch?: () => void;
};

const MAIN_MODULE_KEYS = new Set(["vacancy", "hr_emploc", "plantilla"]);

function getCapabilitySummary(moduleKey: string, capabilities: Record<string, string[]>) {
  const capabilityCount = capabilities[moduleKey]?.length ?? 0;

  return capabilityCount > 0
    ? `${capabilityCount} capabilities available`
    : "No module actions available";
}

export function Sidebar({
  visibleModules,
  moduleCapabilities,
  userName = "Admin",
  userRole = "Super admin",
  onOpenOhmni,
  onOpenGlobalSearch,
}: SidebarProps) {
  const path = usePathname();
  const router = useRouter();
  const queryClient = useQueryClient();
  const activeModule = getActiveModule(path, visibleModules);

  const currentUser = useCurrentUser();
  const canViewApprovals = Boolean(
    currentUser && (hasFullAccess(currentUser) || canViewApprovalsHub(currentUser))
  );

  const { data: requestCounts } = useRequestCategoryCounts({ enabled: canViewApprovals });
  const totalPendingCount = requestCounts
    ? Object.values(requestCounts).reduce((acc, c) => acc + c, 0)
    : 0;

  const { data: unreadNotificationsCount = 0 } = useUnreadNotificationsCount();

  const { data: myRequestsData } = useMyRequests(currentUser);
  const myRequestsPendingCount = myRequestsData
    ? calculateMyRequestsCounts(myRequestsData).pending
    : 0;

  const hasSettings = visibleModules.some((m) => m.key === "settings");
  const mainModules = visibleModules.filter((m) => MAIN_MODULE_KEYS.has(m.key));
  const secondaryModules = visibleModules.filter(
    (m) => !MAIN_MODULE_KEYS.has(m.key) && m.key !== "settings"
  );

  const hasCencom = secondaryModules.some((m) => m.key === "cencom");
  const fallbackSecondaryKey = secondaryModules.some((m) => m.key === "dashboard")
    ? "dashboard"
    : secondaryModules[0]?.key;

  const { theme, resolvedTheme, setTheme } = useTheme();

  const cycleTheme = () => {
    if (theme === "light") {
      setTheme("dark");
    } else if (theme === "dark") {
      setTheme("system");
    } else {
      setTheme("light");
    }
  };

  const logout = async () => {
    queryClient.cancelQueries();
    queryClient.clear();
    try {
      localStorage.setItem("ohmployee_theme_mode", "light");
      window.dispatchEvent(new Event("ohmployee-theme-change"));
    } catch {}
    const supabase = createClient();
    await supabase.auth.signOut();
    router.replace("/login");
    router.refresh();
  };

  return (
    <aside className="hidden w-[var(--sidebar-width)] shrink-0 border-r border-[var(--line)] bg-[var(--side)] text-[var(--text)] lg:flex lg:flex-col p-4 h-screen sticky top-0 overflow-y-auto">
      {/* Brand Header */}
      <Link
        href="/vacancy"
        className="px-2.5 pb-3 pt-1 font-semibold text-[15px] text-[var(--text)] block hover:opacity-90 outline-none focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 rounded-lg"
      >
        OHMployee
        <small className="block text-[13px] font-normal text-[var(--muted)]">Admin Command</small>
      </Link>

      {/* Global Search Quick Bar */}
      {onOpenGlobalSearch && (
        <button
          type="button"
          onClick={onOpenGlobalSearch}
          title="Search records across all modules (⌘K / Ctrl+K)"
          className="mb-3 mx-0 flex items-center justify-between rounded-lg border border-[var(--line)] bg-[var(--card)] px-2.5 py-1.5 text-xs text-[var(--muted)] hover:border-[var(--line-strong)] hover:text-[var(--text)] transition cursor-pointer shadow-2xs group"
        >
          <span className="flex items-center gap-2 truncate">
            <Search size={13} className="text-[var(--muted)] group-hover:text-brand-500 transition-colors" />
            <span className="truncate">Search records…</span>
          </span>
          <kbd className="inline-flex items-center gap-0.5 rounded border border-[var(--line)] bg-[var(--soft)] px-1.5 py-0.5 text-[10px] font-mono text-[var(--muted)] font-medium">
            ⌘K
          </kbd>
        </button>
      )}

      {/* Main Group: Vacancy, HR Emploc, Plantilla */}
      <nav className="flex flex-col gap-0.5" aria-label="Main modules">
        {mainModules.map(({ key, href, title }) => {
          const isActive = activeModule.href === href;

          return (
            <Link
              key={href}
              href={href}
              title={getCapabilitySummary(key, moduleCapabilities)}
              aria-current={isActive ? "page" : undefined}
              className={`flex items-center justify-between rounded-[10px] px-2.5 py-2 text-[15px] transition outline-none focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 ${
                isActive
                  ? "bg-[var(--soft)] text-[var(--text)] font-semibold"
                  : "text-[var(--text)] hover:bg-[var(--soft)]"
              }`}
            >
              <span className="truncate">{title}</span>
            </Link>
          );
        })}
      </nav>

      {/* 1px divider */}
      <div className="my-4 mx-2.5 h-px bg-[var(--line)]" />

      {/* Secondary Group */}
      <nav className="flex flex-col gap-0.5" aria-label="Other modules">
        {secondaryModules.map(({ key, href, title }) => {
          const isActive = activeModule.href === href;
          const isApprovals = key === "approvals";
          const isMyRequests = key === "my_requests";
          const isNotifications = key === "notifications";
          const displayTitle =
            key === "users"
              ? "User management"
              : key === "team_directory"
              ? "Team directory"
              : key === "more"
              ? "Operations Hub"
              : title;

          const shouldRenderOhmniHere =
            (hasCencom && key === "cencom") ||
            (!hasCencom && key === fallbackSecondaryKey);

          return (
            <React.Fragment key={href}>
              <Link
                href={href}
                title={getCapabilitySummary(key, moduleCapabilities)}
                aria-current={isActive ? "page" : undefined}
                className={`flex items-center justify-between rounded-[10px] px-2.5 py-2 text-[13.5px] transition outline-none focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 ${
                  isActive
                    ? "bg-[var(--soft)] text-[var(--text)] font-semibold"
                    : "text-[var(--muted)] hover:bg-[var(--soft)] hover:text-[var(--text)]"
                }`}
              >
                <span className="truncate">{displayTitle}</span>
                {isApprovals && totalPendingCount > 0 && (
                  <span className="ml-auto text-xs font-semibold text-[var(--accent)]">
                    {totalPendingCount}
                  </span>
                )}
                {isMyRequests && myRequestsPendingCount > 0 && (
                  <span className="ml-auto text-xs font-semibold text-[var(--accent)]">
                    {myRequestsPendingCount}
                  </span>
                )}
                {isNotifications && unreadNotificationsCount > 0 && (
                  <span className="ml-auto text-xs font-semibold text-[var(--accent)]">
                    {unreadNotificationsCount}
                  </span>
                )}
              </Link>

              {/* OHMni AI Co-Pilot: Positioned below CENCOM (or fallback below Dashboard/first module for non-CENCOM roles) */}
              {shouldRenderOhmniHere && (
                <button
                  type="button"
                  onClick={onOpenOhmni}
                  title="Ask OHMni AI Co-Pilot (⌘J)"
                  className="flex items-center justify-between rounded-[10px] px-2.5 py-2 text-[13.5px] transition outline-none focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 text-[var(--accent)] hover:bg-[var(--soft)] font-medium group cursor-pointer"
                >
                  <span className="flex items-center gap-2 truncate">
                    <Sparkles size={14} className="text-amber-500 group-hover:rotate-12 transition-transform" />
                    <span>OHMni Co-Pilot</span>
                  </span>
                  <span className="rounded bg-brand-500/10 px-1.5 py-0.5 text-[10px] font-mono text-[var(--accent)] font-semibold">
                    ⌘J
                  </span>
                </button>
              )}
            </React.Fragment>
          );
        })}
      </nav>

      {/* Footer: User Profile + Settings Link + Theme Toggle + Logout */}
      <div className="mt-auto pt-6 px-2.5 text-xs text-[var(--muted)] flex items-center justify-between gap-1">
        {hasSettings ? (
          <Link
            href="/settings"
            title="Account & Security Settings"
            className="truncate pr-1 min-w-0 group hover:opacity-85 transition cursor-pointer outline-none focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 rounded"
          >
            <b className="block font-medium text-[var(--text)] truncate text-[13.5px] leading-snug group-hover:text-brand-500 transition-colors">
              {userName}
            </b>
            <span className="truncate block text-[12px] leading-snug">{userRole}</span>
          </Link>
        ) : (
          <div className="truncate pr-1 min-w-0">
            <b className="block font-medium text-[var(--text)] truncate text-[13.5px] leading-snug">
              {userName}
            </b>
            <span className="truncate block text-[12px] leading-snug">{userRole}</span>
          </div>
        )}
        <div className="flex items-center gap-0.5 shrink-0">
          {hasSettings && (
            <Link
              href="/settings"
              title="Settings (Profile, Preferences, Security)"
              aria-label="Settings"
              className={`rounded-md p-1.5 transition cursor-pointer outline-none focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 ${
                path === "/settings"
                  ? "bg-[var(--soft)] text-[var(--text)] font-semibold"
                  : "text-[var(--muted)] hover:text-[var(--text)] hover:bg-[var(--soft)]"
              }`}
            >
              <Settings size={15} aria-hidden="true" />
            </Link>
          )}
          <button
            type="button"
            onClick={cycleTheme}
            title={`Current theme: ${theme} (resolved: ${resolvedTheme}). Click to cycle.`}
            aria-label="Toggle theme mode"
            className="rounded-md p-1.5 text-[var(--muted)] hover:text-[var(--text)] hover:bg-[var(--soft)] transition cursor-pointer outline-none focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500"
          >
            {theme === "system" ? (
              <Laptop size={15} aria-hidden="true" />
            ) : resolvedTheme === "dark" ? (
              <Moon size={15} aria-hidden="true" />
            ) : (
              <Sun size={15} aria-hidden="true" />
            )}
          </button>
          <button
            onClick={logout}
            title="Sign Out"
            className="rounded-md p-1.5 text-[var(--muted)] hover:text-[var(--text)] hover:bg-[var(--soft)] transition cursor-pointer outline-none focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500"
          >
            <LogOut size={15} aria-hidden="true" />
          </button>
        </div>
      </div>
    </aside>
  );
}
