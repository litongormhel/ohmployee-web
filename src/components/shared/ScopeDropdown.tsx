"use client";

import { memo, useId } from "react";
import { ChevronDown } from "lucide-react";

export interface ScopeOption {
  value: string;
  label: string;
  badge?: string;
}

export interface ScopeDropdownProps {
  label?: string;
  value: string;
  options: ScopeOption[];
  onChange: (value: string) => void;
  className?: string;
  ariaLabel?: string;
}

export const ScopeDropdown = memo(function ScopeDropdown({
  label,
  value,
  options,
  onChange,
  className = "",
  ariaLabel = "Filter scope",
}: ScopeDropdownProps) {
  const id = useId();

  return (
    <div className={`relative inline-flex items-center gap-2 ${className}`}>
      {label && (
        <label
          htmlFor={id}
          className="text-xs font-medium text-text-secondary whitespace-nowrap"
        >
          {label}
        </label>
      )}
      <div className="relative">
        <select
          id={id}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          aria-label={ariaLabel}
          className="h-9 w-full appearance-none rounded-lg border border-border-default bg-surface-card py-1.5 pl-3 pr-8 text-xs font-semibold text-text-primary shadow-2xs transition-colors hover:border-border-strong focus:border-brand-500 focus:outline-hidden focus:ring-1 focus:ring-brand-500 cursor-pointer"
        >
          {options.map((opt) => (
            <option key={opt.value} value={opt.value}>
              {opt.label} {opt.badge ? `(${opt.badge})` : ""}
            </option>
          ))}
        </select>
        <ChevronDown
          className="pointer-events-none absolute right-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-text-muted"
          aria-hidden="true"
        />
      </div>
    </div>
  );
});
