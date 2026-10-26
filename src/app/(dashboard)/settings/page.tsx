"use client";

import { Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import {
  User,
  Sliders,
  Shield,
  Activity,
  Settings as SettingsIcon,
} from "lucide-react";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { ProfileTab } from "@/components/settings/ProfileTab";
import { PreferencesTab } from "@/components/settings/PreferencesTab";
import { SecurityTab } from "@/components/settings/SecurityTab";
import { DiagnosticsTab } from "@/components/settings/DiagnosticsTab";
import { useCurrentUser } from "@/lib/auth";

type SettingsTabKey = "profile" | "preferences" | "security" | "diagnostics";

function SettingsPageContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const currentUser = useCurrentUser();

  // Super Admin Check (role level 100 or role key)
  const isSuperAdmin =
    currentUser?.roleKey?.toLowerCase() === "super_admin" ||
    currentUser?.roleName?.toLowerCase() === "super admin";

  const rawTab = searchParams.get("tab");
  const activeTab: SettingsTabKey =
    rawTab === "security" || rawTab === "security_events" || rawTab === "audit_logs"
      ? "security"
      : rawTab === "diagnostics"
      ? "diagnostics"
      : rawTab === "preferences"
      ? "preferences"
      : "profile";

  const handleTabChange = (newTab: SettingsTabKey) => {
    const params = new URLSearchParams(searchParams.toString());
    params.set("tab", newTab);
    router.replace(`/settings?${params.toString()}`, { scroll: false });
  };

  return (
    <div className="space-y-6">
      <AdminPageHeader
        categoryTag="ADMIN PANEL"
        moduleName="Settings"
        title="Settings & System Governance"
        subtitle="Manage your profile security, application preferences, device sessions, and platform diagnostics."
        icon={SettingsIcon}
      />

      {/* Settings Navigation Tabs */}
      <div className="border-b border-border-subtle pb-3">
        <nav
          className="flex items-center gap-1.5 overflow-x-auto no-scrollbar scrollbar-none"
          aria-label="Settings Tabs"
          role="tablist"
        >
          <button
            type="button"
            role="tab"
            aria-selected={activeTab === "profile"}
            onClick={() => handleTabChange("profile")}
            className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
              activeTab === "profile"
                ? "border-brand-border bg-brand-subtle text-brand-primary shadow-2xs"
                : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
            }`}
          >
            <User
              className={`w-4 h-4 shrink-0 transition-colors ${
                activeTab === "profile"
                  ? "text-brand-primary"
                  : "text-text-muted group-hover:text-text-secondary"
              }`}
            />
            <span>Profile & Security</span>
          </button>

          <button
            type="button"
            role="tab"
            aria-selected={activeTab === "preferences"}
            onClick={() => handleTabChange("preferences")}
            className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
              activeTab === "preferences"
                ? "border-brand-border bg-brand-subtle text-brand-primary shadow-2xs"
                : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
            }`}
          >
            <Sliders
              className={`w-4 h-4 shrink-0 transition-colors ${
                activeTab === "preferences"
                  ? "text-brand-primary"
                  : "text-text-muted group-hover:text-text-secondary"
              }`}
            />
            <span>Preferences & Appearance</span>
          </button>

          <button
            type="button"
            role="tab"
            aria-selected={activeTab === "security"}
            onClick={() => handleTabChange("security")}
            className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
              activeTab === "security"
                ? "border-brand-border bg-brand-subtle text-brand-primary shadow-2xs"
                : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
            }`}
          >
            <Shield
              className={`w-4 h-4 shrink-0 transition-colors ${
                activeTab === "security"
                  ? "text-brand-primary"
                  : "text-text-muted group-hover:text-text-secondary"
              }`}
            />
            <span>Security Center & Sessions</span>
          </button>

          {isSuperAdmin && (
            <button
              type="button"
              role="tab"
              aria-selected={activeTab === "diagnostics"}
              onClick={() => handleTabChange("diagnostics")}
              className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                activeTab === "diagnostics"
                  ? "border-brand-border bg-brand-subtle text-brand-primary shadow-2xs"
                  : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
              }`}
            >
              <Activity
                className={`w-4 h-4 shrink-0 transition-colors ${
                  activeTab === "diagnostics"
                    ? "text-brand-primary"
                    : "text-text-muted group-hover:text-text-secondary"
                }`}
              />
              <span>System Diagnostics</span>
              <span
                className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold shadow-2xs transition-colors ${
                  activeTab === "diagnostics"
                    ? "bg-brand-primary text-text-inverse"
                    : "bg-surface-subtle text-text-secondary border border-border-default"
                }`}
              >
                Admin
              </span>
            </button>
          )}
        </nav>
      </div>

      {/* Tab Panels */}
      <div className="pt-2">
        {activeTab === "profile" && <ProfileTab />}
        {activeTab === "preferences" && <PreferencesTab />}
        {activeTab === "security" && <SecurityTab />}
        {activeTab === "diagnostics" && isSuperAdmin && <DiagnosticsTab />}
      </div>
    </div>
  );
}

export default function SettingsPage() {
  return (
    <Suspense
      fallback={
        <div className="space-y-6">
          <div className="h-14 border-b border-border-subtle bg-surface-base animate-pulse" />
          <div className="h-64 rounded-xl border border-border-default bg-surface-base animate-pulse" />
        </div>
      }
    >
      <SettingsPageContent />
    </Suspense>
  );
}
