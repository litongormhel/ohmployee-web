"use client";

import type { ComponentType } from "react";
import {
  Archive,
  ArrowLeftRight,
  Layers,
  MapPin,
  Store,
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
      className="flex flex-col gap-1.5"
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
            onClick={() => onSelectCategory(cat.key)}
            className={`group relative flex w-full items-center justify-between rounded-lg p-3 text-left transition-all ${
              isSelected
                ? "bg-brand-50/70 border border-brand-200 text-brand-900 shadow-2xs"
                : "border border-transparent bg-transparent text-text-primary hover:border-slate-200 hover:bg-surface-hover"
            }`}
          >
            <div className="flex items-center gap-3 min-w-0 pr-2">
              <div
                className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-md border transition-colors ${
                  isSelected
                    ? "border-brand-200 bg-brand-100/70 text-brand-700"
                    : "border-border-default bg-surface-base text-text-muted group-hover:border-slate-300 group-hover:text-text-secondary"
                }`}
              >
                <Icon className="h-4.5 w-4.5" />
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-1.5">
                  <span
                    className={`truncate text-sm font-semibold ${
                      isSelected ? "text-brand-900" : "text-text-primary"
                    }`}
                  >
                    {cat.label}
                  </span>
                </div>
                <p className="truncate text-xs text-text-muted mt-0.5">
                  {cat.description}
                </p>
              </div>
            </div>

            {/* Dynamic Trailing Count Badge - No static SIM/NEW/BETA badges */}
            {showBadge && (
              <span
                className={`shrink-0 rounded-full px-2.5 py-0.5 font-mono text-xs font-semibold shadow-2xs ${
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
