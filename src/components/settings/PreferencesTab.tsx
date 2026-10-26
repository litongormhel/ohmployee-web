"use client";

import { useState } from "react";
import {
  Moon,
  Sun,
  Laptop,
  Bell,
  Clock,
  Type,
  Eye,
  Info,
  Check,
  Loader2,
  AlertCircle,
} from "lucide-react";
import {
  useUserSettings,
  useUpdateUserSettings,
  type UserSettingsData,
} from "@/lib/queries/settings";
import { useTheme, type ThemeMode } from "@/providers/ThemeProvider";

export function PreferencesTab() {
  const { data: settings, isLoading, error } = useUserSettings();
  const updateSettingsMutation = useUpdateUserSettings();
  const { theme, setTheme } = useTheme();

  const [pendingOverrides, setPendingOverrides] = useState<Partial<UserSettingsData>>({});
  const [saveToast, setSaveToast] = useState(false);

  const formState = { ...settings, ...pendingOverrides };

  const handleUpdate = async (field: keyof UserSettingsData, value: unknown) => {
    setPendingOverrides((prev) => ({ ...prev, [field]: value }));

    try {
      await updateSettingsMutation.mutateAsync({
        [field]: value,
      });
      setSaveToast(true);
      setTimeout(() => setSaveToast(false), 2500);
    } catch (err) {
      console.error("Failed to persist user settings:", err);
    }
  };

  const handleThemeChange = (newTheme: ThemeMode) => {
    setTheme(newTheme);
    handleUpdate("themeMode", newTheme);
  };

  if (isLoading) {
    return (
      <div className="flex h-64 items-center justify-center">
        <div className="flex items-center gap-2 text-sm text-text-secondary">
          <Loader2 className="h-5 w-5 animate-spin text-brand-primary" />
          <span>Loading application preferences...</span>
        </div>
      </div>
    );
  }

  if (error || !settings) {
    return (
      <div className="rounded-xl border border-danger-border bg-danger-subtle p-6 text-center">
        <AlertCircle className="mx-auto h-8 w-8 text-danger" />
        <h3 className="mt-2 text-sm font-semibold text-danger">
          Could not load preferences
        </h3>
        <p className="mt-1 text-xs text-text-muted">
          {(error as Error)?.message || "Preferences are temporarily unavailable."}
        </p>
      </div>
    );
  }

  const currentTheme = pendingOverrides.themeMode ?? formState.themeMode ?? theme ?? "light";

  return (
    <div className="space-y-6">
      {saveToast && (
        <div className="fixed bottom-6 right-6 z-50 flex items-center gap-2 rounded-xl border border-border-default bg-surface-subtle px-4 py-3 text-sm font-medium text-text-primary shadow-lg">
          <Check className="h-4 w-4 text-brand-primary" />
          <span>Preference updated successfully!</span>
        </div>
      )}

      {/* Grid: Appearance & Security Policies */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Appearance & Theme Selector */}
        <div className="rounded-xl border border-border-default bg-surface-base p-6 shadow-2xs space-y-4">
          <div className="flex items-center gap-2 border-b border-border-default pb-3">
            <Sun className="h-4 w-4 text-text-secondary" />
            <h3 className="text-sm font-semibold text-text-primary">
              Appearance & Theme
            </h3>
          </div>

          <p className="text-xs text-text-secondary">
            Select your preferred visual style for the OHMployee web console.
          </p>

          <div className="grid grid-cols-3 gap-3 pt-1">
            {/* Light */}
            <button
              type="button"
              onClick={() => handleThemeChange("light")}
              className={`flex flex-col items-center justify-center gap-2 rounded-xl border p-4 text-center transition-all cursor-pointer ${
                currentTheme === "light"
                  ? "border-brand-default bg-brand-subtle text-brand-primary ring-2 ring-brand-default/20"
                  : "border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover"
              }`}
            >
              <Sun className={`h-6 w-6 ${currentTheme === "light" ? "text-brand-primary" : "text-text-muted"}`} />
              <span className="text-xs font-semibold">Light Mode</span>
            </button>

            {/* Dark */}
            <button
              type="button"
              onClick={() => handleThemeChange("dark")}
              className={`flex flex-col items-center justify-center gap-2 rounded-xl border p-4 text-center transition-all cursor-pointer ${
                currentTheme === "dark"
                  ? "border-brand-default bg-brand-subtle text-brand-primary ring-2 ring-brand-default/20"
                  : "border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover"
              }`}
            >
              <Moon className={`h-6 w-6 ${currentTheme === "dark" ? "text-brand-primary" : "text-text-muted"}`} />
              <span className="text-xs font-semibold">Dark Mode</span>
            </button>

            {/* System */}
            <button
              type="button"
              onClick={() => handleThemeChange("system")}
              className={`flex flex-col items-center justify-center gap-2 rounded-xl border p-4 text-center transition-all cursor-pointer ${
                currentTheme === "system"
                  ? "border-brand-default bg-brand-subtle text-brand-primary ring-2 ring-brand-default/20"
                  : "border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover"
              }`}
            >
              <Laptop className={`h-6 w-6 ${currentTheme === "system" ? "text-brand-primary" : "text-text-muted"}`} />
              <span className="text-xs font-semibold">System Default</span>
            </button>
          </div>

          <div className="pt-2 text-xs text-text-muted">
            <span className="font-semibold text-text-secondary">Note:</span> OHMployee supports high-contrast Light, Dark, and System themes.
          </div>
        </div>

        {/* Security Policy Notice: 30-minute idle auto logout */}
        <div className="rounded-xl border border-border-default bg-surface-base p-6 shadow-2xs space-y-4">
          <div className="flex items-center gap-2 border-b border-border-default pb-3">
            <Clock className="h-4 w-4 text-brand-primary" />
            <h3 className="text-sm font-semibold text-text-primary">
              Session Governance Policy
            </h3>
          </div>

          <div className="rounded-xl border border-border-default bg-surface-subtle p-4 space-y-3">
            <div className="flex items-center gap-2 text-text-primary font-semibold text-sm">
              <Clock className="h-4 w-4 text-brand-primary" />
              <span>Fixed 30-Minute Inactivity Timeout</span>
            </div>
            <p className="text-xs leading-relaxed text-text-secondary">
              In accordance with company-wide compliance and workforce privacy standards, all active sessions automatically terminate after <strong>30 minutes</strong> of inactivity.
            </p>
            <div className="border-t border-border-default pt-2 text-xs text-text-secondary space-y-1">
              <div className="flex items-center gap-1.5">
                <span className="inline-block h-1.5 w-1.5 rounded-full bg-brand-primary" />
                <span><strong>25 Minutes:</strong> Inactivity warning dialog is prompted.</span>
              </div>
              <div className="flex items-center gap-1.5">
                <span className="inline-block h-1.5 w-1.5 rounded-full bg-brand-primary" />
                <span><strong>30 Minutes:</strong> Automatic session logout and cache eviction.</span>
              </div>
            </div>
          </div>

          <div className="rounded-lg bg-surface-muted/60 p-3 text-xs text-text-secondary flex items-start gap-2">
            <Info className="h-4 w-4 text-text-muted shrink-0 mt-0.5" />
            <span>
              This policy is mandatory and cannot be disabled. To refresh your timer, interact with the screen or click &ldquo;Stay Signed In&rdquo; when the warning appears.
            </span>
          </div>
        </div>
      </div>

      {/* Notification Preferences Card */}
      <div className="rounded-xl border border-border-default bg-surface-base p-6 shadow-2xs space-y-4">
        <div className="flex items-center gap-2 border-b border-border-default pb-3">
          <Bell className="h-4 w-4 text-brand-primary" />
          <h3 className="text-sm font-semibold text-text-primary">
            Notification Alert Preferences
          </h3>
        </div>

        <div className="divide-y divide-border-default">
          {/* Push Notifications Master Toggle */}
          <div className="flex items-center justify-between py-3.5">
            <div>
              <h4 className="text-sm font-semibold text-text-primary">
                Web & Push Notifications
              </h4>
              <p className="text-xs text-text-secondary">
                Receive important system broadcasts and administrative notices.
              </p>
            </div>
            <label className="relative inline-flex items-center cursor-pointer">
              <input
                type="checkbox"
                checked={formState.pushNotificationsEnabled ?? true}
                onChange={(e) => handleUpdate("pushNotificationsEnabled", e.target.checked)}
                className="sr-only peer"
              />
              <div className="w-11 h-6 bg-surface-muted peer-focus:outline-hidden rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-[var(--border-subtle)] after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-[var(--surface-base)] after:border-border-default after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-brand-primary"></div>
            </label>
          </div>

          {/* Vacancy Alerts Toggle */}
          <div className="flex items-center justify-between py-3.5">
            <div>
              <h4 className="text-sm font-semibold text-text-primary">
                Vacancy Requisition Alerts
              </h4>
              <p className="text-xs text-text-secondary">
                Alerts when new vacancies are created, filled, or submitted for closure.
              </p>
            </div>
            <label className="relative inline-flex items-center cursor-pointer">
              <input
                type="checkbox"
                checked={formState.vacancyAlertsEnabled ?? true}
                onChange={(e) => handleUpdate("vacancyAlertsEnabled", e.target.checked)}
                className="sr-only peer"
              />
              <div className="w-11 h-6 bg-surface-muted peer-focus:outline-hidden rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-[var(--border-subtle)] after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-[var(--surface-base)] after:border-border-default after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-brand-primary"></div>
            </label>
          </div>

          {/* Approvals Alerts Toggle */}
          <div className="flex items-center justify-between py-3.5">
            <div>
              <h4 className="text-sm font-semibold text-text-primary">
                Approvals Center Alerts
              </h4>
              <p className="text-xs text-text-secondary">
                Real-time alerts when requests require your review or endorsement.
              </p>
            </div>
            <label className="relative inline-flex items-center cursor-pointer">
              <input
                type="checkbox"
                checked={formState.approvalAlertsEnabled ?? true}
                onChange={(e) => handleUpdate("approvalAlertsEnabled", e.target.checked)}
                className="sr-only peer"
              />
              <div className="w-11 h-6 bg-surface-muted peer-focus:outline-hidden rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-[var(--border-subtle)] after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-[var(--surface-base)] after:border-border-default after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-brand-primary"></div>
            </label>
          </div>

          {/* SLA Breach Alerts Toggle */}
          <div className="flex items-center justify-between py-3.5">
            <div>
              <h4 className="text-sm font-semibold text-text-primary">
                SLA Breach & Escalation Alerts
              </h4>
              <p className="text-xs text-text-secondary">
                Immediate warnings when vacancy aging or review queues exceed SLA thresholds.
              </p>
            </div>
            <label className="relative inline-flex items-center cursor-pointer">
              <input
                type="checkbox"
                checked={formState.slaBreachAlertsEnabled ?? true}
                onChange={(e) => handleUpdate("slaBreachAlertsEnabled", e.target.checked)}
                className="sr-only peer"
              />
              <div className="w-11 h-6 bg-surface-muted peer-focus:outline-hidden rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-[var(--border-subtle)] after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-[var(--surface-base)] after:border-border-default after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-brand-primary"></div>
            </label>
          </div>
        </div>
      </div>

      {/* Typography & Accessibility Section */}
      <div className="rounded-xl border border-border-default bg-surface-base p-6 shadow-2xs space-y-4">
        <div className="flex items-center gap-2 border-b border-border-default pb-3">
          <Type className="h-4 w-4 text-brand-primary" />
          <h3 className="text-sm font-semibold text-text-primary">
            Typography & Accessibility
          </h3>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          {/* Text Size */}
          <div>
            <label className="block text-xs font-semibold text-text-secondary">
              Text Scaling
            </label>
            <select
              value={formState.textSize ?? "Default"}
              onChange={(e) => handleUpdate("textSize", e.target.value)}
              className="mt-1.5 w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default cursor-pointer"
            >
              <option value="Default">Default (Standard Admin Density)</option>
              <option value="Large">Large (Enhanced Readability)</option>
            </select>
          </div>

          {/* Font Family */}
          <div>
            <label className="block text-xs font-semibold text-text-secondary">
              Font Family
            </label>
            <select
              value={formState.fontFamily ?? "Inter"}
              onChange={(e) => handleUpdate("fontFamily", e.target.value)}
              className="mt-1.5 w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default cursor-pointer"
            >
              <option value="Inter">Inter (System Default)</option>
              <option value="SF Pro">SF Pro</option>
              <option value="Helvetica Neue">Helvetica Neue</option>
              <option value="Plus Jakarta Sans">Plus Jakarta Sans</option>
              <option value="Manrope">Manrope</option>
              <option value="System Default">System Default</option>
            </select>
          </div>

          {/* Motion Experience Control (Full / Lite / Off) */}
          <div className="space-y-2 md:col-span-2">
            <div>
              <h4 className="text-xs font-semibold text-text-secondary">
                Motion Experience
              </h4>
              <p className="text-xs text-text-muted mt-0.5">
                Control UI animation velocity, page transitions, and numerical value tweens.
              </p>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-2 pt-1">
              {[
                { level: "full", title: "Full", desc: "200ms transitions & tweens" },
                { level: "lite", title: "Lite", desc: "≤ 150ms fades (low-power auto)" },
                { level: "off", title: "Off", desc: "0ms instant (reduced motion)" },
              ].map(({ level, title, desc }) => {
                const currentMotionLevel = formState.reduceMotionEnabled
                  ? "off"
                  : (typeof window !== "undefined" && localStorage.getItem("ohm_motion_preference")) || "full";
                const isSelected = currentMotionLevel === level;

                return (
                  <button
                    key={level}
                    type="button"
                    onClick={() => {
                      if (level === "off") {
                        handleUpdate("reduceMotionEnabled", true);
                        if (typeof window !== "undefined") {
                          localStorage.setItem("ohm_motion_preference", "off");
                          document.documentElement.setAttribute("data-motion", "off");
                        }
                      } else {
                        handleUpdate("reduceMotionEnabled", false);
                        if (typeof window !== "undefined") {
                          localStorage.setItem("ohm_motion_preference", level);
                          document.documentElement.setAttribute("data-motion", level);
                        }
                      }
                    }}
                    className={`flex flex-col items-start p-2.5 rounded-lg border text-left transition-colors cursor-pointer ${
                      isSelected
                        ? "border-brand-primary bg-surface-selected text-text-primary ring-1 ring-brand-primary"
                        : "border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover"
                    }`}
                  >
                    <span className="text-xs font-bold text-text-primary">{title}</span>
                    <span className="text-[10px] text-text-muted mt-0.5 leading-tight">{desc}</span>
                  </button>
                );
              })}
            </div>
          </div>
        </div>
      </div>

      {/* About & Telemetry Card */}
      <div className="rounded-xl border border-border-default bg-surface-base p-6 shadow-2xs">
        <div className="flex items-center gap-2 border-b border-border-default pb-3">
          <Eye className="h-4 w-4 text-text-muted" />
          <h3 className="text-sm font-semibold text-text-primary">
            Application Telemetry
          </h3>
        </div>

        <div className="mt-4 grid grid-cols-2 sm:grid-cols-4 gap-4 text-xs">
          <div>
            <span className="text-text-muted">Application</span>
            <p className="font-semibold text-text-primary mt-0.5">OHMployee Web</p>
          </div>
          <div>
            <span className="text-text-muted">Version</span>
            <p className="font-semibold text-text-primary mt-0.5">v1.0.0-web</p>
          </div>
          <div>
            <span className="text-text-muted">Framework</span>
            <p className="font-semibold text-text-primary mt-0.5">Next.js 16 (App Router)</p>
          </div>
          <div>
            <span className="text-text-muted">Environment</span>
            <p className="font-semibold text-text-primary mt-0.5">Production Ready</p>
          </div>
        </div>
      </div>
    </div>
  );
}
