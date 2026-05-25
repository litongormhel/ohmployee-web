"use client";

import { Lock } from "lucide-react";

export interface ActionItem {
  label: string;
  isAvailable: boolean;
  onClick?: () => void;
}

export interface CapabilityActionBarProps {
  actions: ActionItem[];
  title?: string;
  helperText?: string;
}

export function CapabilityActionBar({
  actions,
  title = "Capability-Aware Actions",
  helperText = "Actions remain read-only. Availability indices display current RBAC permissions. Supabase final verification remains authoritative.",
}: CapabilityActionBarProps) {
  return (
    <div className="rounded-md border border-border-subtle bg-surface-muted p-4 space-y-3">
      <div className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-text-muted">
        <Lock className="h-4 w-4 text-text-muted" aria-hidden="true" />
        <span>{title}</span>
      </div>
      <div className="grid gap-2">
        {actions.map((action) => (
          <button
            key={action.label}
            className="flex w-full items-center justify-between rounded-md border border-border-default bg-surface-base px-3 py-2 text-left text-xs font-medium text-text-muted shadow-sm cursor-not-allowed hover:bg-surface-hover transition-colors"
            disabled
            onClick={action.onClick}
            type="button"
          >
            <span>{action.label}</span>
            <span
              className={`inline-flex rounded-full px-2 py-0.5 text-[9px] font-semibold border ${
                action.isAvailable
                  ? "border-green-200 bg-green-50 text-green-700"
                  : "border-border-default bg-surface-muted text-text-secondary"
              }`}
            >
              {action.isAvailable ? "available" : "not exposed"}
            </span>
          </button>
        ))}
      </div>
      {helperText && (
        <p className="text-[10px] leading-relaxed text-text-muted">
          {helperText}
        </p>
      )}
    </div>
  );
}
