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
    <header className="sticky top-0 z-20 border-b border-slate-200 bg-white/95 backdrop-blur">
      <div className="flex min-h-16 items-center justify-between gap-4 px-5 py-3 lg:px-8">
        <div className="flex items-center gap-4">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">
              Admin panel
            </p>
            <h1 className="text-lg font-semibold text-slate-950">
              {activeModule.title}
            </h1>
          </div>
          {activeModule.key === "approvals" && (
            <div className="hidden border-l border-slate-200 pl-4 sm:block">
              <p className="text-xs font-semibold text-slate-900">
                Request Center
              </p>
              <p className="text-xs text-slate-500 max-w-xl truncate lg:max-w-2xl">
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
                className={`whitespace-nowrap rounded-md px-3 py-2 text-sm ${
                  isActive
                    ? "bg-slate-950 text-white"
                    : "bg-slate-100 text-slate-700"
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
