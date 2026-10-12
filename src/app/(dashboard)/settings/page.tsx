"use client";

import { useState } from "react";
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

export default function SettingsPage() {
  const [activeTab, setActiveTab] = useState<SettingsTabKey>("profile");
  const currentUser = useCurrentUser();

  // Super Admin Check (role level 100 or role key)
  const isSuperAdmin =
    currentUser?.roleKey?.toLowerCase() === "super_admin" ||
    currentUser?.roleName?.toLowerCase() === "super admin";

  return (
    <div className="space-y-6">
      <AdminPageHeader
        title="Settings & System Governance"
        subtitle="Manage your profile security, application preferences, device sessions, and platform diagnostics."
        icon={SettingsIcon}
      />

      {/* Settings Navigation Tabs */}
      <div className="border-b border-border-default">
        <nav className="flex space-x-2" aria-label="Settings Tabs">
          <button
            type="button"
            onClick={() => setActiveTab("profile")}
            className={`inline-flex items-center gap-2 border-b-2 px-4 py-3 text-sm font-medium transition-colors ${
              activeTab === "profile"
                ? "border-blue-600 text-blue-600 font-semibold"
                : "border-transparent text-text-secondary hover:border-border-default hover:text-text-primary"
            }`}
          >
            <User className="h-4 w-4" />
            <span>Profile & Security</span>
          </button>

          <button
            type="button"
            onClick={() => setActiveTab("preferences")}
            className={`inline-flex items-center gap-2 border-b-2 px-4 py-3 text-sm font-medium transition-colors ${
              activeTab === "preferences"
                ? "border-blue-600 text-blue-600 font-semibold"
                : "border-transparent text-text-secondary hover:border-border-default hover:text-text-primary"
            }`}
          >
            <Sliders className="h-4 w-4" />
            <span>Preferences & Appearance</span>
          </button>

          <button
            type="button"
            onClick={() => setActiveTab("security")}
            className={`inline-flex items-center gap-2 border-b-2 px-4 py-3 text-sm font-medium transition-colors ${
              activeTab === "security"
                ? "border-blue-600 text-blue-600 font-semibold"
                : "border-transparent text-text-secondary hover:border-border-default hover:text-text-primary"
            }`}
          >
            <Shield className="h-4 w-4" />
            <span>Security Center & Sessions</span>
          </button>

          {isSuperAdmin && (
            <button
              type="button"
              onClick={() => setActiveTab("diagnostics")}
              className={`inline-flex items-center gap-2 border-b-2 px-4 py-3 text-sm font-medium transition-colors ${
                activeTab === "diagnostics"
                  ? "border-purple-600 text-purple-600 font-semibold"
                  : "border-transparent text-text-secondary hover:border-border-default hover:text-text-primary"
              }`}
            >
              <Activity className="h-4 w-4" />
              <span>System Diagnostics</span>
              <span className="rounded-full bg-purple-100 px-1.5 py-0.2 text-2xs font-bold text-purple-700">
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
