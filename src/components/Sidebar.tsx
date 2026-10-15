"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { LogOut } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { getActiveModule, type WebModule } from "@/lib/modules";
import { useRequestCategoryCounts } from "@/lib/queries/requests";
import { useUnreadNotificationsCount } from "@/lib/queries/notifications";

type SidebarProps = {
  visibleModules: WebModule[];
  moduleCapabilities: Record<string, string[]>;
  userName?: string;
  userRole?: string;
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
}: SidebarProps) {
  const path = usePathname();
  const router = useRouter();
  const activeModule = getActiveModule(path, visibleModules);

  const { data: requestCounts } = useRequestCategoryCounts();
  const totalPendingCount = requestCounts
    ? Object.values(requestCounts).reduce((acc, c) => acc + c, 0)
    : 0;

  const { data: unreadNotificationsCount = 0 } = useUnreadNotificationsCount();

  const mainModules = visibleModules.filter((m) => MAIN_MODULE_KEYS.has(m.key));
  const secondaryModules = visibleModules.filter((m) => !MAIN_MODULE_KEYS.has(m.key));

  const logout = async () => {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.replace("/login");
    router.refresh();
  };

  return (
    <aside className="hidden w-[var(--sidebar-width)] shrink-0 border-r border-[var(--line)] bg-[var(--side)] text-[var(--text)] lg:flex lg:flex-col p-4 h-screen sticky top-0 overflow-y-auto">
      {/* Brand Header */}
      <div className="px-2.5 pb-6 pt-1 font-semibold text-[15px] text-[var(--text)]">
        OHMployee
        <small className="block text-[13px] font-normal text-[var(--muted)]">Admin Command</small>
      </div>

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
              className={`flex items-center justify-between rounded-[10px] px-2.5 py-2 text-[15px] transition ${
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
          const isNotifications = key === "notifications";
          const displayTitle =
            key === "users"
              ? "User management"
              : key === "team_directory"
              ? "Team directory"
              : title;

          return (
            <Link
              key={href}
              href={href}
              title={getCapabilitySummary(key, moduleCapabilities)}
              aria-current={isActive ? "page" : undefined}
              className={`flex items-center justify-between rounded-[10px] px-2.5 py-2 text-[13.5px] transition ${
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
              {isNotifications && unreadNotificationsCount > 0 && (
                <span className="ml-auto text-xs font-semibold text-[var(--accent)]">
                  {unreadNotificationsCount}
                </span>
              )}
            </Link>
          );
        })}
      </nav>

      {/* Footer: User Name + Role + Logout */}
      <div className="mt-auto pt-6 px-2.5 text-xs text-[var(--muted)] flex items-center justify-between">
        <div className="truncate pr-2">
          <b className="block font-medium text-[var(--text)] truncate text-[13.5px] leading-snug">
            {userName}
          </b>
          <span className="truncate block text-[12px] leading-snug">{userRole}</span>
        </div>
        <button
          onClick={logout}
          title="Sign Out"
          className="rounded-md p-1.5 text-[var(--muted)] hover:text-[var(--text)] hover:bg-[var(--soft)] transition shrink-0 cursor-pointer"
        >
          <LogOut size={15} aria-hidden="true" />
        </button>
      </div>
    </aside>
  );
}
