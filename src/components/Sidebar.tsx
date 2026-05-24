"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { LogOut } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { getActiveModule, type WebModule } from "@/lib/modules";

export function Sidebar({ visibleModules }: { visibleModules: WebModule[] }) {
  const path = usePathname();
  const router = useRouter();
  const activeModule = getActiveModule(path, visibleModules);

  const logout = async () => {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.replace("/login");
    router.refresh();
  };

  return (
    <aside className="hidden w-72 shrink-0 border-r border-slate-200 bg-slate-950 text-white lg:flex lg:flex-col">
      <div className="border-b border-white/10 px-6 py-6">
        <p className="text-xs font-semibold uppercase tracking-[0.18em] text-sky-300">
          OHMployee Web
        </p>
        <h2 className="mt-2 text-xl font-semibold tracking-tight">
          Admin Command
        </h2>
      </div>

      <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-4">
        {visibleModules.map(({ href, title, icon: Icon }) => {
          const isActive = activeModule.href === href;

          return (
            <Link
              key={href}
              href={href}
              aria-current={isActive ? "page" : undefined}
              className={`flex items-center gap-3 rounded-md px-3 py-2.5 text-sm transition ${
                isActive
                  ? "bg-white text-slate-950 shadow-sm"
                  : "text-slate-300 hover:bg-white/10 hover:text-white"
              }`}
            >
              <Icon size={17} aria-hidden="true" />
              <span className="truncate">{title}</span>
            </Link>
          );
        })}
      </nav>

      <div className="border-t border-white/10 p-3">
        <button
          onClick={logout}
          className="flex w-full items-center gap-3 rounded-md px-3 py-2.5 text-sm text-slate-300 transition hover:bg-white/10 hover:text-white"
        >
          <LogOut size={17} aria-hidden="true" />
          Logout
        </button>
      </div>
    </aside>
  );
}
