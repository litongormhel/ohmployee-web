"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { getActiveModule, type WebModule } from "@/lib/modules";

type AdminTopbarProps = {
  visibleModules: WebModule[];
  moduleCapabilities: Record<string, string[]>;
};

function getCapabilitySummary(moduleKey: string, capabilities: Record<string, string[]>) {
  const capabilityCount = capabilities[moduleKey]?.length ?? 0;

  return capabilityCount > 0
    ? `${capabilityCount} capabilities available`
    : "No module actions available";
}

export function AdminTopbar({
  visibleModules,
  moduleCapabilities,
}: AdminTopbarProps) {
  const pathname = usePathname();
  const activeModule = getActiveModule(pathname, visibleModules);

  return (
    <header className="sticky top-0 z-20 border-b border-[var(--line)] bg-[var(--bg)]">
      <div className="flex min-h-16 items-center justify-between gap-4 px-5 py-3 lg:px-8">
        <div className="flex items-center gap-4">
          <div>
            <p className="text-xs uppercase tracking-[0.06em] text-[var(--muted)]">
              Admin panel
            </p>
            <h1 className="text-[19px] font-semibold text-[var(--text)]">
              {activeModule.title}
            </h1>
          </div>
          {activeModule.key === "approvals" && (
            <div className="hidden border-l border-[var(--line)] pl-4 sm:block">
              <p className="text-xs font-semibold text-[var(--text)]">
                Request Center
              </p>
              <p className="text-xs text-[var(--muted)] max-w-xl truncate lg:max-w-2xl">
                Operational request hub and approval queue for headcount quota amendments, store additions, and workforce adjustments.
              </p>
            </div>
          )}
        </div>

        <nav className="flex max-w-[52vw] gap-2 overflow-x-auto lg:hidden">
          {visibleModules.map((module) => {
            const isActive = activeModule.href === module.href;

            return (
              <Link
                key={module.href}
                href={module.href}
                title={getCapabilitySummary(module.key, moduleCapabilities)}
                className={`whitespace-nowrap rounded-[8px] px-3 py-1.5 text-xs transition ${
                  isActive
                    ? "bg-[var(--soft)] text-[var(--text)] font-semibold border border-[var(--line)]"
                    : "text-[var(--muted)] hover:text-[var(--text)] hover:bg-[var(--soft)]"
                }`}
              >
                {module.title}
              </Link>
            );
          })}
        </nav>
      </div>
    </header>
  );
}
