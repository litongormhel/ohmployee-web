import React from "react";
import { Users, RotateCcw } from "lucide-react";

export function EmptyTabState({
  hasActiveFilters,
  onResetFilters,
  tabLabel,
}: {
  hasActiveFilters: boolean;
  onResetFilters: () => void;
  tabLabel: string;
}) {
  return (
    <div className="flex flex-col items-center justify-center py-16 px-4 text-center rounded-2xl border border-dashed border-border-default bg-surface-muted/20">
      <div className="relative mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-brand-50 border border-brand-100 shadow-xs dark:bg-brand-950/40 dark:border-brand-900">
        <Users className="h-8 w-8 text-brand-600 dark:text-brand-400" />
        {hasActiveFilters && (
          <span className="absolute -top-1 -right-1 flex h-5 w-5 items-center justify-center rounded-full bg-brand-button text-xs font-bold text-white shadow-xs">
            !
          </span>
        )}
      </div>
      <h3 className="text-base font-bold text-text-primary">
        {hasActiveFilters ? "No matching records found" : `No ${tabLabel}`}
      </h3>
      <p className="mt-1.5 max-w-sm text-xs text-text-muted leading-relaxed">
        {hasActiveFilters
          ? "We couldn't find any records matching your current filter criteria. Try adjusting your parameters."
          : `There are currently no ${tabLabel} listed under this account.`}
      </p>
      {hasActiveFilters && (
        <button
          type="button"
          onClick={onResetFilters}
          className="mt-4 inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3.5 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary transition-colors shadow-xs cursor-pointer"
        >
          <RotateCcw className="h-3.5 w-3.5" />
          <span>Reset all filters</span>
        </button>
      )}
    </div>
  );
}
