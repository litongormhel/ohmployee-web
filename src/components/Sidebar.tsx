"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { LogOut } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { getActiveModule, type WebModule } from "@/lib/modules";
import { useRequestCategoryCounts } from "@/lib/queries/requests";

type SidebarProps = {
  visibleModules: WebModule[];
  moduleCapabilities: Record<string, string[]>;
  userName?: string;
  userRole?: string;
};

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

  const logout = async () => {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.replace("/login");
    router.refresh();
  };

  return (
    <aside className="hidden w-[var(--sidebar-width)] shrink-0 border-r border-[var(--line)] bg-[var(--side)] text-[var(--text)] lg:flex lg:flex-col h-screen sticky top-0">
      {/* Header: Logo and subtitle with fixed height and bottom border */}
      <div className="flex h-16 shrink-0 flex-col justify-center border-b border-[var(--line)] px-4">
        <span className="text-sm font-semibold tracking-tight text-[var(--text)] leading-tight">
          OHMployee
        </span>
        <span className="text-xs text-[var(--muted)] leading-tight">
          Admin Command
        </span>
      </div>

      {/* Navigation Body: Scrollable tight container using standard vertical spacing */}
      <nav className="flex-1 overflow-y-auto px-3 py-3 space-y-1" aria-label="Main navigation">
        {visibleModules.map(({ key, href, title, icon: Icon }) => {
          const isActive = activeModule.href === href;
          const isApprovals = key === "approvals";

          return (
            <Link
              key={href}
              href={href}
              title={getCapabilitySummary(key, moduleCapabilities)}
              aria-current={isActive ? "page" : undefined}
              className={`flex h-9 items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition ${
                isActive
                  ? "bg-[var(--soft)] text-[var(--text)] font-semibold"
                  : "text-[var(--muted)] hover:bg-[var(--soft)] hover:text-[var(--text)]"
              }`}
            >
              <Icon
                className={`h-4 w-4 shrink-0 ${
                  isActive ? "text-[var(--text)]" : "text-[var(--muted)]"
                }`}
                aria-hidden="true"
              />
              <span className="truncate">{title}</span>
              {isApprovals && totalPendingCount > 0 && (
                <span className="ml-auto flex h-5 min-w-5 items-center justify-center rounded-full bg-[var(--pillbg)] px-1.5 text-xs font-semibold text-[var(--accent)]">
                  {totalPendingCount}
                </span>
              )}
            </Link>
          );
        })}
      </nav>

      {/* Footer / User Section: Pinned to the bottom */}
      <div className="mt-auto shrink-0 border-t border-[var(--line)] p-3">
        <div className="flex items-center justify-between gap-2 px-1">
          <div className="min-w-0 flex-1">
            <b className="block truncate text-xs font-semibold text-[var(--text)] leading-tight">
              {userName}
            </b>
            <span className="block truncate text-[11px] text-[var(--muted)] leading-tight">
              {userRole}
            </span>
          </div>
          <button
            onClick={logout}
            title="Sign Out"
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-[var(--muted)] transition hover:bg-[var(--soft)] hover:text-[var(--text)] cursor-pointer"
          >
            <LogOut size={16} aria-hidden="true" />
          </button>
        </div>
      </div>
    </aside>
  );
}
