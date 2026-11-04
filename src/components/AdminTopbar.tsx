"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Sparkles, Sun, Moon, Laptop } from "lucide-react";
import { getActiveModule, type WebModule } from "@/lib/modules";
import { useTheme } from "@/providers/ThemeProvider";

type AdminTopbarProps = {
  visibleModules: WebModule[];
  moduleCapabilities: Record<string, string[]>;
  onOpenOhmni?: () => void;
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
  onOpenOhmni,
}: AdminTopbarProps) {
  const pathname = usePathname();
  const activeModule = getActiveModule(pathname, visibleModules);
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

  return (
    <header className="sticky top-0 z-20 border-b border-[var(--line)] bg-[var(--bg)] lg:hidden">
      <div className="flex min-h-14 items-center justify-between gap-3 px-4 py-2">
        <div className="flex items-center gap-2 min-w-0">
          <Link
            href="/vacancy"
            className="text-xs font-semibold text-text-muted shrink-0 hover:text-text-primary"
          >
            Admin panel
          </Link>
          <span className="text-text-muted/60 text-xs shrink-0">/</span>
          <h1 className="text-sm font-bold text-text-primary truncate">
            {activeModule.title}
          </h1>
        </div>

        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={cycleTheme}
            title={`Current theme: ${theme} (resolved: ${resolvedTheme}). Click to cycle.`}
            aria-label="Toggle theme mode"
            className="flex items-center justify-center rounded-lg border border-border-default bg-surface-base p-1.5 text-text-secondary hover:bg-surface-hover hover:text-text-primary transition cursor-pointer"
          >
            {theme === "system" ? (
              <Laptop size={14} aria-hidden="true" />
            ) : resolvedTheme === "dark" ? (
              <Moon size={14} aria-hidden="true" />
            ) : (
              <Sun size={14} aria-hidden="true" />
            )}
          </button>

          {onOpenOhmni && (
            <button
              type="button"
              onClick={onOpenOhmni}
              title="Ask OHMni AI Co-Pilot"
              className="flex items-center gap-1.5 rounded-lg border border-amber-300 bg-amber-50 px-2 py-1 text-xs font-medium text-amber-800 hover:bg-amber-100 transition cursor-pointer"
            >
              <Sparkles size={12} className="text-amber-600" />
              <span>OHMni</span>
            </button>
          )}

          <nav className="flex max-w-[40vw] gap-2 overflow-x-auto no-scrollbar scrollbar-none">
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
      </div>
    </header>
  );
}
