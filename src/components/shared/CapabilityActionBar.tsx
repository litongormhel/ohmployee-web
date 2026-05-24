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
    <div className="rounded-md border border-gray-100 bg-gray-50 p-4 space-y-3">
      <div className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-gray-400">
        <Lock className="h-4 w-4 text-gray-400" aria-hidden="true" />
        <span>{title}</span>
      </div>
      <div className="grid gap-2">
        {actions.map((action) => (
          <button
            key={action.label}
            className="flex w-full items-center justify-between rounded-md border border-gray-200 bg-white px-3 py-2 text-left text-xs font-medium text-gray-400 shadow-sm cursor-not-allowed hover:bg-gray-50 transition-colors"
            disabled
            onClick={action.onClick}
            type="button"
          >
            <span>{action.label}</span>
            <span
              className={`inline-flex rounded-full px-2 py-0.5 text-[9px] font-semibold border ${
                action.isAvailable
                  ? "border-green-200 bg-green-50 text-green-700"
                  : "border-gray-200 bg-gray-100 text-gray-500"
              }`}
            >
              {action.isAvailable ? "available" : "not exposed"}
            </span>
          </button>
        ))}
      </div>
      {helperText && (
        <p className="text-[10px] leading-relaxed text-gray-400">
          {helperText}
        </p>
      )}
    </div>
  );
}
