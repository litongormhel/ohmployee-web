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
          <div className="flex items-center gap-2 rounded-md border border-[var(--danger-border)] bg-[var(--danger-bg)] px-2.5 py-1.5 text-xs text-[var(--danger)]">
            <ShieldOff className="h-4 w-4 shrink-0 text-[var(--danger)]" aria-hidden="true" />
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
                "border border-[var(--border-subtle)] bg-[var(--card)] text-[var(--foreground)] hover:bg-[var(--surface-muted)]";
              if (action.variant === "primary") {
                buttonStyle =
                  "border border-transparent bg-[var(--primary)] text-white hover:opacity-90 shadow-xs";
              } else if (action.variant === "success") {
                buttonStyle =
                  "border border-transparent bg-[var(--foreground)] text-[var(--card)] hover:opacity-90 shadow-xs";
              } else if (action.variant === "danger") {
                buttonStyle =
                  "border border-[var(--danger-border)] bg-[var(--danger-bg)] text-[var(--danger)] hover:opacity-90";
              } else if (action.variant === "warning") {
                buttonStyle =
                  "border border-[var(--border-subtle)] bg-[var(--surface-sunken)] text-[var(--foreground)] hover:bg-[var(--surface-muted)]";
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
                      : "border border-[var(--border-subtle)] bg-[var(--surface-muted)] text-[var(--text-muted)] cursor-not-allowed opacity-60"
                  }`}
                >
                  {Icon && <Icon className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />}
                  <span>{action.label}</span>
                </button>
              );
            })
          ) : (
            <div className="flex items-center gap-1.5 text-xs text-[var(--text-muted)] py-1">
              <Lock className="h-3.5 w-3.5 text-[var(--text-muted)]" aria-hidden="true" />
              <span>No write actions available for current role.</span>
            </div>
          )}
        </div>
        {helperText && (
          <p className="text-xs leading-relaxed text-[var(--text-muted)]">
            {helperText}
          </p>
        )}
      </div>
    );
  }

  return (
    <div className="rounded-md border border-[var(--border-subtle)] bg-[var(--surface-muted)] p-4 space-y-3">
      <div className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">
        <Lock className="h-4 w-4 text-[var(--text-muted)]" aria-hidden="true" />
        <span>{title}</span>
      </div>

      {isReadOnlyEmergencyActive && (
        <div className="flex items-start gap-2 rounded-md border border-[var(--danger-border)] bg-[var(--danger-bg)] px-3 py-2.5 text-xs text-[var(--danger)]">
          <ShieldOff className="h-4 w-4 shrink-0 mt-0.5 text-[var(--danger)]" aria-hidden="true" />
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
            ? "border-[var(--danger-border)] bg-[var(--danger-bg)] text-[var(--danger)]"
            : action.isAvailable
            ? "border-[var(--border-subtle)] bg-[var(--surface-sunken)] text-[var(--foreground)]"
            : "border-[var(--border-subtle)] bg-[var(--surface-muted)] text-[var(--text-muted)]";

          return (
            <button
              key={action.label}
              className={`flex w-full items-center justify-between rounded-md border border-[var(--border-subtle)] bg-[var(--card)] px-3 py-2 text-left text-xs font-medium shadow-xs transition-colors ${
                isEnabled
                  ? "text-[var(--foreground)] cursor-pointer hover:bg-[var(--surface-muted)]"
                  : "text-[var(--text-muted)] cursor-not-allowed hover:bg-[var(--surface-muted)]"
              }`}
              disabled={!isEnabled}
              onClick={action.onClick}
              type="button"
            >
              <span>{action.label}</span>
              <span
                className={`inline-flex rounded-full px-2 py-0.5 text-xs font-semibold border ${badgeClass}`}
              >
                {badgeLabel}
              </span>
            </button>
          );
        })}
      </div>
      {helperText && (
        <p className="text-xs leading-relaxed text-[var(--text-muted)]">
          {helperText}
        </p>
      )}
    </div>
  );
}
