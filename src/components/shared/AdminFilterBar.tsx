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
      className="flex flex-wrap items-center gap-2 rounded-md border border-gray-200 bg-white p-2"
      onSubmit={handleSubmit}
    >
      {onSearchChange && (
        <label className="relative min-w-[280px] flex-1">
          <Search
            className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400"
            aria-hidden="true"
          />
          <input
            aria-label={searchPlaceholder}
            className="h-9 w-full rounded-md border border-gray-200 bg-gray-50 pl-9 pr-3 text-sm text-gray-700 outline-none focus:border-blue-300 transition-colors disabled:opacity-75 disabled:cursor-not-allowed"
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
          className="inline-flex h-9 items-center gap-2 rounded-md border border-gray-200 bg-white px-3 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          disabled={disabled}
          type="submit"
        >
          <Filter className="h-4 w-4 text-gray-500" aria-hidden="true" />
          {applyLabel}
        </button>
      )}

      {showResetButton && onReset && (
        <button
          className="inline-flex h-9 items-center gap-2 rounded-md border border-gray-200 bg-white px-3 text-sm font-medium text-gray-500 shadow-sm hover:bg-gray-50 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
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
