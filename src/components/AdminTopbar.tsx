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
    <header className="sticky top-0 z-20 border-b border-[var(--line)] bg-[var(--bg)] lg:hidden">
      <div className="flex min-h-14 items-center justify-between gap-3 px-4 py-2">
        <div className="flex items-center gap-2 min-w-0">
          <p className="text-[10px] font-bold uppercase tracking-wider text-text-muted shrink-0">
            Admin panel
          </p>
          <span className="text-text-muted/60 text-xs shrink-0">/</span>
          <h1 className="text-sm font-bold text-text-primary truncate">
            {activeModule.title}
          </h1>
        </div>

        <nav className="flex max-w-[55vw] gap-2 overflow-x-auto no-scrollbar scrollbar-none">
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
