"use client";

import type { FormEvent, ReactNode } from "react";
import { Filter, RotateCcw, Search } from "lucide-react";

export interface AdminFilterBarProps {
  searchPlaceholder?: string;
  searchVal?: string;
  onSearchChange?: (val: string) => void;
  onSearchSubmit?: (e: FormEvent<HTMLFormElement>) => void;
  children?: ReactNode;
  filterSlot?: ReactNode;
  onApply?: () => void;
  onReset?: () => void;
  disabled?: boolean;
  showApplyButton?: boolean;
  applyLabel?: string;
  showResetButton?: boolean;
  resetLabel?: string;
  extraActionsSlot?: ReactNode;
}

export function AdminFilterBar({
  searchPlaceholder = "Search...",
  searchVal = "",
  onSearchChange,
  onSearchSubmit,
  children,
  filterSlot,
  onApply,
  onReset,
  disabled = false,
  showApplyButton = true,
  applyLabel = "Apply",
  showResetButton = false,
  resetLabel = "Reset",
  extraActionsSlot,
}: AdminFilterBarProps) {
  const handleSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (onSearchSubmit) {
      onSearchSubmit(e);
    } else if (onApply) {
      onApply();
    }
  };

  return (
    <form
      className="flex w-full flex-wrap items-center gap-2 rounded-md border border-border-default bg-surface-base p-3"
      onSubmit={handleSubmit}
    >
      {onSearchChange && (
        <label className="relative min-w-full flex-1 sm:min-w-[320px] xl:min-w-[420px]">
          <Search
            className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted"
            aria-hidden="true"
          />
          <input
            aria-label={searchPlaceholder}
            className="h-10 w-full rounded-md border border-border-default bg-surface-muted pl-9 pr-3 text-base text-text-primary outline-none transition-colors focus:border-brand-500 disabled:cursor-not-allowed disabled:opacity-75"
            disabled={disabled}
            onChange={(e) => onSearchChange(e.target.value)}
            placeholder={searchPlaceholder}
            type="search"
            value={searchVal}
          />
        </label>
      )}

      {children}
      {filterSlot}

      {showApplyButton && (
        <button
          className="inline-flex h-10 items-center gap-2 rounded-md border border-border-default bg-surface-base px-4 text-sm font-medium text-text-secondary shadow-sm transition-colors hover:bg-surface-hover disabled:cursor-not-allowed disabled:opacity-50"
          disabled={disabled}
          type="submit"
        >
          <Filter className="h-4 w-4 text-text-secondary" aria-hidden="true" />
          {applyLabel}
        </button>
      )}

      {showResetButton && onReset && (
        <button
          className="inline-flex h-10 items-center gap-2 rounded-md border border-border-default bg-surface-base px-4 text-sm font-medium text-text-muted shadow-sm transition-colors hover:bg-surface-hover disabled:cursor-not-allowed disabled:opacity-50"
          disabled={disabled}
          onClick={onReset}
          type="button"
        >
          <RotateCcw className="h-4 w-4" aria-hidden="true" />
          {resetLabel}
        </button>
      )}

      {extraActionsSlot}
    </form>
  );
}
