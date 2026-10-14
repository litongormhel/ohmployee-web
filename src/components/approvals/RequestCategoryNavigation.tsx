"use client";

import type { ComponentType } from "react";
import {
  Archive,
  ArrowLeftRight,
  Layers,
  MapPin,
  Store,
  UserCheck,
  UserMinus,
  Users,
  UserX,
} from "lucide-react";
import {
  REQUEST_CATEGORIES,
  type RequestCategoryCounts,
  type RequestCategoryKey,
} from "@/lib/queries/requests";

const CATEGORY_ICONS: Record<RequestCategoryKey, ComponentType<{ className?: string }>> = {
  new_stores: Store,
  headcount: Users,
  coverage: MapPin,
  vacancy_closures: Archive,
  hr_emploc_deletions: UserX,
  deactivations: UserMinus,
  applicant_movements: ArrowLeftRight,
  account_group_transfers: Layers,
  relievers: UserCheck,
};

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
      aria-label="Request Center Modules"
      role="tablist"
      className="flex items-center gap-1.5 overflow-x-auto scrollbar-none py-0.5 px-0.5"
    >
      {REQUEST_CATEGORIES.map((cat) => {
        const Icon = CATEGORY_ICONS[cat.key];
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
            className={`group inline-flex shrink-0 items-center gap-2 rounded-lg px-3 py-1.5 text-xs sm:text-sm font-semibold transition-all whitespace-nowrap ${
              isSelected
                ? "bg-brand-50 border border-brand-200 text-brand-900 shadow-2xs font-bold"
                : "border border-transparent bg-transparent text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary"
            }`}
          >
            <div
              className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-md transition-colors ${
                isSelected
                  ? "bg-brand-100/80 text-brand-700"
                  : "bg-surface-subtle text-text-muted group-hover:text-text-secondary"
              }`}
            >
              <Icon className="h-3.5 w-3.5" />
            </div>

            <span className="truncate">{cat.label}</span>

            {/* Dynamic Pill Badge */}
            {showBadge && (
              <span
                className={`shrink-0 rounded-full px-2 py-0.5 font-mono text-2xs font-bold shadow-2xs transition-colors ${
                  isSelected
                    ? "bg-brand-600 text-white"
                    : "bg-blue-100 text-blue-800"
                }`}
              >
                {rawCount}
              </span>
            )}
          </button>
        );
      })}
    </nav>
  );
}
