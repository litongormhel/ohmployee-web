"use client";

import {
  REQUEST_CATEGORIES,
  type RequestCategoryCounts,
  type RequestCategoryKey,
} from "@/lib/queries/requests";

interface RequestCategoryNavigationProps {
  selectedCategory: RequestCategoryKey;
  onSelectCategory: (key: RequestCategoryKey) => void;
  counts: RequestCategoryCounts;
  acknowledgedCategories: Set<RequestCategoryKey>;
  isLoadingCounts?: boolean;
}

export function RequestCategoryNavigation({
  selectedCategory,
  onSelectCategory,
  counts,
  acknowledgedCategories,
  isLoadingCounts = false,
}: RequestCategoryNavigationProps) {
  return (
    <nav
      aria-label="Approval types"
      role="tablist"
      className="flex items-center gap-1 overflow-x-auto scrollbar-none p-1"
    >
      {REQUEST_CATEGORIES.map((cat) => {
        const isSelected = selectedCategory === cat.key;
        const rawCount = counts[cat.key] ?? 0;
        const isAcknowledged = acknowledgedCategories.has(cat.key);
        // Trailing count badge: only render when count > 0 and not acknowledged in this session
        const showBadge = !isLoadingCounts && rawCount > 0 && !isAcknowledged;

        return (
          <button
            key={cat.key}
            type="button"
            role="tab"
            aria-selected={isSelected}
            onClick={() => onSelectCategory(cat.key)}
            className={`group inline-flex h-9 shrink-0 items-center justify-center rounded-[9px] px-3.5 py-2 text-xs whitespace-nowrap transition cursor-pointer ${
              isSelected
                ? "border border-[var(--text)] bg-transparent text-[var(--text)] font-semibold"
                : "border border-transparent bg-transparent text-[var(--muted)] hover:text-[var(--text)]"
            }`}
          >
            <span className="truncate">{cat.label}</span>

            {/* Dynamic Pill Badge - restyled small, quiet, accent */}
            {showBadge && (
              <span className="ml-1.5 shrink-0 rounded-full px-1.5 py-0.2 text-[11px] font-mono font-medium bg-[var(--pillbg)] text-[var(--accent)] border border-[var(--status-accent-border)]">
                {rawCount}
              </span>
            )}
          </button>
        );
      })}
    </nav>
  );
}
