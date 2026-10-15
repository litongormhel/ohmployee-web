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
          <Loader2 className="h-5 w-5 animate-spin text-blue-600" />
          <span>Loading application preferences...</span>
        </div>
      </div>
    );
  }

  if (error || !settings) {
    return (
      <div className="rounded-xl border border-red-200 bg-red-50 p-6 text-center">
        <AlertCircle className="mx-auto h-8 w-8 text-red-600" />
        <h3 className="mt-2 text-sm font-semibold text-red-900">
          Could not load preferences
        </h3>
        <p className="mt-1 text-xs text-red-700">
          {(error as Error)?.message || "Preferences are temporarily unavailable."}
        </p>
      </div>
    );
  }

  const currentTheme = pendingOverrides.themeMode ?? formState.themeMode ?? theme ?? "light";

  return (
    <div className="space-y-6">
      {saveToast && (
        <div className="fixed bottom-6 right-6 z-50 flex items-center gap-2 rounded-xl border border-emerald-200 dark:border-emerald-800 bg-emerald-50 dark:bg-emerald-950/80 px-4 py-3 text-sm font-medium text-emerald-800 dark:text-emerald-200 shadow-lg">
          <Check className="h-4 w-4 text-emerald-600 dark:text-emerald-400" />
          <span>Preference updated successfully!</span>
        </div>
      )}

      {/* Grid: Appearance & Security Policies */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Appearance & Theme Selector */}
        <div className="rounded-xl border border-border-default bg-surface-card p-6 shadow-xs space-y-4">
          <div className="flex items-center gap-2 border-b border-border-default pb-3">
            <Sun className="h-4 w-4 text-amber-500" />
            <h3 className="text-sm font-semibold uppercase tracking-wider text-text-primary">
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
                  ? "border-blue-600 dark:border-blue-500 bg-blue-50/50 dark:bg-blue-950/40 text-blue-700 dark:text-blue-300 ring-2 ring-blue-600/20 dark:ring-blue-500/30"
                  : "border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover"
              }`}
            >
              <Sun className={`h-6 w-6 ${currentTheme === "light" ? "text-blue-600 dark:text-blue-400" : "text-text-muted"}`} />
              <span className="text-xs font-semibold">Light Mode</span>
            </button>

            {/* Dark */}
            <button
              type="button"
              onClick={() => handleThemeChange("dark")}
              className={`flex flex-col items-center justify-center gap-2 rounded-xl border p-4 text-center transition-all cursor-pointer ${
                currentTheme === "dark"
                  ? "border-blue-600 dark:border-blue-500 bg-blue-50/50 dark:bg-blue-950/40 text-blue-700 dark:text-blue-300 ring-2 ring-blue-600/20 dark:ring-blue-500/30"
                  : "border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover"
              }`}
            >
              <Moon className={`h-6 w-6 ${currentTheme === "dark" ? "text-blue-600 dark:text-blue-400" : "text-text-muted"}`} />
              <span className="text-xs font-semibold">Dark Mode</span>
            </button>

            {/* System */}
            <button
              type="button"
              onClick={() => handleThemeChange("system")}
              className={`flex flex-col items-center justify-center gap-2 rounded-xl border p-4 text-center transition-all cursor-pointer ${
                currentTheme === "system"
                  ? "border-blue-600 dark:border-blue-500 bg-blue-50/50 dark:bg-blue-950/40 text-blue-700 dark:text-blue-300 ring-2 ring-blue-600/20 dark:ring-blue-500/30"
                  : "border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover"
              }`}
            >
              <Laptop className={`h-6 w-6 ${currentTheme === "system" ? "text-blue-600 dark:text-blue-400" : "text-text-muted"}`} />
              <span className="text-xs font-semibold">System Default</span>
            </button>
          </div>

          <div className="pt-2 text-xs text-text-muted">
            <span className="font-semibold text-text-secondary">Note:</span> OHMployee supports high-contrast Light, Dark, and System themes.
          </div>
        </div>


        {/* Security Policy Notice: 30-minute idle auto logout */}
        <div className="rounded-xl border border-border-default bg-surface-card p-6 shadow-xs space-y-4">
          <div className="flex items-center gap-2 border-b border-border-default pb-3">
            <Clock className="h-4 w-4 text-blue-600" />
            <h3 className="text-sm font-semibold uppercase tracking-wider text-text-primary">
              Session Governance Policy
            </h3>
          </div>

          <div className="rounded-xl border border-blue-200 dark:border-blue-900/50 bg-blue-50/60 dark:bg-blue-950/30 p-4 space-y-3">
            <div className="flex items-center gap-2 text-blue-900 dark:text-blue-200 font-semibold text-sm">
              <Clock className="h-4 w-4 text-blue-600 dark:text-blue-400" />
              <span>Fixed 30-Minute Inactivity Timeout</span>
            </div>
            <p className="text-xs leading-relaxed text-blue-800 dark:text-blue-300">
              In accordance with company-wide compliance and workforce privacy standards, all active sessions automatically terminate after <strong>30 minutes</strong> of inactivity.
            </p>
            <div className="border-t border-blue-200/60 dark:border-blue-900/50 pt-2 text-xs text-blue-700 dark:text-blue-300 space-y-1">
              <div className="flex items-center gap-1.5">
                <span className="inline-block h-1.5 w-1.5 rounded-full bg-blue-600 dark:bg-blue-400" />
                <span><strong>25 Minutes:</strong> Inactivity warning dialog is prompted.</span>
              </div>
              <div className="flex items-center gap-1.5">
                <span className="inline-block h-1.5 w-1.5 rounded-full bg-blue-600 dark:bg-blue-400" />
                <span><strong>30 Minutes:</strong> Automatic session logout and cache eviction.</span>
              </div>
            </div>
          </div>

          <div className="rounded-lg bg-surface-hover/60 p-3 text-xs text-text-secondary flex items-start gap-2">
            <Info className="h-4 w-4 text-text-muted shrink-0 mt-0.5" />
            <span>
              This policy is mandatory and cannot be disabled. To refresh your timer, interact with the screen or click &ldquo;Stay Signed In&rdquo; when the warning appears.
            </span>
          </div>
        </div>
      </div>

      {/* Notification Preferences Card */}
      <div className="rounded-xl border border-border-default bg-surface-card p-6 shadow-xs space-y-4">
        <div className="flex items-center gap-2 border-b border-border-default pb-3">
          <Bell className="h-4 w-4 text-blue-600 dark:text-blue-400" />
          <h3 className="text-sm font-semibold uppercase tracking-wider text-text-primary">
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
              <div className="w-11 h-6 bg-slate-200 dark:bg-slate-700 peer-focus:outline-hidden rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-slate-300 dark:after:border-slate-600 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600"></div>
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
              <div className="w-11 h-6 bg-slate-200 dark:bg-slate-700 peer-focus:outline-hidden rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-slate-300 dark:after:border-slate-600 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600"></div>
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
              <div className="w-11 h-6 bg-slate-200 dark:bg-slate-700 peer-focus:outline-hidden rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-slate-300 dark:after:border-slate-600 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600"></div>
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
              <div className="w-11 h-6 bg-slate-200 dark:bg-slate-700 peer-focus:outline-hidden rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-slate-300 dark:after:border-slate-600 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600"></div>
            </label>
          </div>
        </div>
      </div>


      {/* Typography & Accessibility Section */}
      <div className="rounded-xl border border-border-default bg-surface-card p-6 shadow-xs space-y-4">
        <div className="flex items-center gap-2 border-b border-border-default pb-3">
          <Type className="h-4 w-4 text-purple-600" />
          <h3 className="text-sm font-semibold uppercase tracking-wider text-text-primary">
            Typography & Accessibility
          </h3>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          {/* Text Size */}
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-text-secondary">
              Text Scaling
            </label>
            <select
              value={formState.textSize ?? "Default"}
              onChange={(e) => handleUpdate("textSize", e.target.value)}
              className="mt-1.5 w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-blue-500 focus:outline-hidden focus:ring-1 focus:ring-blue-500"
            >
              <option value="Default">Default (Standard Admin Density)</option>
              <option value="Large">Large (Enhanced Readability)</option>
            </select>
          </div>

          {/* Font Family */}
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-text-secondary">
              Font Family
            </label>
            <select
              value={formState.fontFamily ?? "Inter"}
              onChange={(e) => handleUpdate("fontFamily", e.target.value)}
              className="mt-1.5 w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-blue-500 focus:outline-hidden focus:ring-1 focus:ring-blue-500"
            >
              <option value="Inter">Inter (System Default)</option>
              <option value="SF Pro">SF Pro</option>
              <option value="Helvetica Neue">Helvetica Neue</option>
              <option value="Plus Jakarta Sans">Plus Jakarta Sans</option>
              <option value="Manrope">Manrope</option>
              <option value="System Default">System Default</option>
            </select>
          </div>

          {/* Reduce Motion Toggle */}
          <div className="flex items-center justify-between md:flex-col md:items-start md:justify-center">
            <div>
              <h4 className="text-xs font-semibold uppercase tracking-wider text-text-secondary">
                Reduce Motion
              </h4>
              <p className="text-xs text-text-muted mt-0.5">
                Disable UI drawer and modal animations
              </p>
            </div>
            <label className="relative inline-flex items-center cursor-pointer mt-2">
              <input
                type="checkbox"
                checked={formState.reduceMotionEnabled ?? false}
                onChange={(e) => handleUpdate("reduceMotionEnabled", e.target.checked)}
                className="sr-only peer"
              />
              <div className="w-11 h-6 bg-slate-200 dark:bg-slate-700 peer-focus:outline-hidden rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-slate-300 dark:after:border-slate-600 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600"></div>

            </label>
          </div>
        </div>
      </div>

      {/* About & Telemetry Card */}
      <div className="rounded-xl border border-border-default bg-surface-card p-6 shadow-xs">
        <div className="flex items-center gap-2 border-b border-border-default pb-3">
          <Eye className="h-4 w-4 text-text-muted" />
          <h3 className="text-sm font-semibold uppercase tracking-wider text-text-primary">
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
            <p className="font-semibold text-emerald-600 mt-0.5">Production Ready</p>
          </div>
        </div>
      </div>
    </div>
  );
}
