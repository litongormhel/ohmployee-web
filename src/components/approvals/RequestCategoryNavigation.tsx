import type { ComponentType } from "react";
import {
  Archive,
  ArrowLeftRight,
  Briefcase,
  Layers,
  MapPin,
  Store,
  UserCheck,
  UserMinus,
  UserPlus,
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
  plantilla_approvals: Briefcase,
  account_requests: UserPlus,
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
  allowedCategories?: RequestCategoryKey[];
}

export function RequestCategoryNavigation({
  selectedCategory,
  onSelectCategory,
  counts,
  acknowledgedCategories,
  isLoadingCounts = false,
  allowedCategories,
}: RequestCategoryNavigationProps) {
  const categories = allowedCategories
    ? REQUEST_CATEGORIES.filter((cat) => allowedCategories.includes(cat.key))
    : REQUEST_CATEGORIES;

  return (
    <nav
      aria-label="Approval types"
      role="tablist"
      className="flex items-center gap-1.5 overflow-x-auto no-scrollbar scrollbar-none p-1"
    >
      {categories.map((cat) => {
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
            className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
              isSelected
                ? "border-border-brand bg-brand-subtle text-text-brand-bold shadow-2xs"
                : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
            }`}
          >
            {Icon && (
              <Icon
                className={`w-4 h-4 shrink-0 transition-colors ${
                  isSelected
                    ? "text-brand-600"
                    : "text-text-muted group-hover:text-text-secondary"
                }`}
              />
            )}
            <span className="truncate">{cat.label}</span>

            {/* Dynamic Pill Badge */}
            {showBadge && (
              <span
                className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold shadow-2xs transition-colors ${
                  isSelected
                    ? "bg-brand-500 text-white"
                    : "bg-surface-subtle text-text-secondary border border-border-default"
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
