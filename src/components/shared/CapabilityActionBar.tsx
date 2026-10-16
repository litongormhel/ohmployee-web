"use client";

import type { ComponentType } from "react";
import { Lock, ShieldOff } from "lucide-react";

export interface ActionItem {
  label: string;
  isAvailable: boolean;
  onClick?: () => void;
  variant?: "primary" | "secondary" | "danger" | "warning" | "success" | "default";
  icon?: ComponentType<{ className?: string }>;
}

export interface CapabilityActionBarProps {
  actions: ActionItem[];
  title?: string;
  helperText?: string;
  isReadOnlyEmergencyActive?: boolean;
  variant?: "list" | "toolbar";
  className?: string;
}

export function CapabilityActionBar({
  actions,
  title = "Capability-Aware Actions",
  helperText,
  isReadOnlyEmergencyActive = false,
  variant = "list",
  className = "",
}: CapabilityActionBarProps) {
  if (variant === "toolbar") {
    const availableActions = actions.filter((a) => a.isAvailable);

    return (
      <div className={`space-y-2 ${className}`}>
        {isReadOnlyEmergencyActive && (
          <div className="flex items-center gap-2 rounded-md border border-red-200 bg-red-50 px-2.5 py-1.5 text-xs text-red-700">
            <ShieldOff className="h-4 w-4 shrink-0 text-red-600" aria-hidden="true" />
            <span className="font-medium">
              Read-Only Emergency Mode active. Write actions disabled.
            </span>
          </div>
        )}

        <div className="flex flex-wrap items-center gap-2">
          {availableActions.length > 0 ? (
            availableActions.map((action) => {
              const isEnabled = !isReadOnlyEmergencyActive && !!action.onClick;
              const Icon = action.icon;

              let buttonStyle =
                "border border-border-default bg-surface-base text-text-primary hover:bg-surface-hover active:bg-surface-muted";
              if (action.variant === "primary") {
                buttonStyle =
                  "border border-transparent bg-brand-600 text-white hover:bg-brand-700 active:bg-brand-800 shadow-xs";
              } else if (action.variant === "success") {
                buttonStyle =
                  "border border-transparent bg-emerald-600 text-white hover:bg-emerald-700 active:bg-emerald-800 shadow-xs";
              } else if (action.variant === "danger") {
                buttonStyle =
                  "border border-rose-200 bg-rose-50 text-rose-700 hover:bg-rose-100 active:bg-rose-200";
              } else if (action.variant === "warning") {
                buttonStyle =
                  "border border-amber-200 bg-amber-50 text-amber-800 hover:bg-amber-100 active:bg-amber-200";
              }

              return (
                <button
                  key={action.label}
                  disabled={!isEnabled}
                  onClick={action.onClick}
                  type="button"
                  className={`inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-semibold transition-colors ${
                    isEnabled
                      ? `${buttonStyle} cursor-pointer`
                      : "border border-border-default bg-surface-muted text-text-muted cursor-not-allowed opacity-60"
                  }`}
                >
                  {Icon && <Icon className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />}
                  <span>{action.label}</span>
                </button>
              );
            })
          ) : (
            <div className="flex items-center gap-1.5 text-xs text-text-muted py-1">
              <Lock className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
              <span>No write actions available for current role.</span>
            </div>
          )}
        </div>
        {helperText && (
          <p className="text-[10px] leading-relaxed text-text-muted">
            {helperText}
          </p>
        )}
      </div>
    );
  }
  return (
    <div className="rounded-md border border-border-subtle bg-surface-muted p-4 space-y-3">
      <div className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-text-muted">
        <Lock className="h-4 w-4 text-text-muted" aria-hidden="true" />
        <span>{title}</span>
      </div>

      {isReadOnlyEmergencyActive && (
        <div className="flex items-start gap-2 rounded-md border border-red-200 bg-red-50 px-3 py-2.5 text-xs text-red-700">
          <ShieldOff className="h-4 w-4 shrink-0 mt-0.5 text-red-600" aria-hidden="true" />
          <span className="font-medium">
            Read-Only Emergency Mode is active. Write actions are temporarily disabled.
          </span>
        </div>
      )}

      <div className="grid gap-2">
        {actions.map((action) => {
          const isEnabled = !isReadOnlyEmergencyActive && action.isAvailable && !!action.onClick;
          const badgeLabel = isReadOnlyEmergencyActive
            ? "read-only mode"
            : action.isAvailable
            ? "available"
            : "not exposed";
          const badgeClass = isReadOnlyEmergencyActive
            ? "border-red-200 bg-red-50 text-red-600"
            : action.isAvailable
            ? "border-green-200 bg-green-50 text-green-700"
            : "border-border-default bg-surface-muted text-text-secondary";

          return (
            <button
              key={action.label}
              className={`flex w-full items-center justify-between rounded-md border border-border-default bg-surface-base px-3 py-2 text-left text-xs font-medium shadow-sm transition-colors ${
                isEnabled
                  ? "text-text-primary cursor-pointer hover:bg-surface-hover"
                  : "text-text-muted cursor-not-allowed hover:bg-surface-hover"
              }`}
              disabled={!isEnabled}
              onClick={action.onClick}
              type="button"
            >
              <span>{action.label}</span>
              <span
                className={`inline-flex rounded-full px-2 py-0.5 text-[9px] font-semibold border ${badgeClass}`}
              >
                {badgeLabel}
              </span>
            </button>
          );
        })}
      </div>
      {helperText && (
        <p className="text-[10px] leading-relaxed text-text-muted">
          {helperText}
        </p>
      )}
    </div>
  );
}
