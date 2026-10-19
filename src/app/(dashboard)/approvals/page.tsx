"use client";

import { Suspense, useState } from "react";
import { useSearchParams } from "next/navigation";
import { CheckCheck, RefreshCw } from "lucide-react";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { RequestCategoryNavigation } from "@/components/approvals/RequestCategoryNavigation";
import { ActiveQueueReviewPane } from "@/components/approvals/ActiveQueueReviewPane";
import {
  useRequestCategoryCounts,
  type RequestCategoryKey,
} from "@/lib/queries/requests";

const VALID_CATEGORIES = new Set<string>([
  "new_stores",
  "headcount",
  "plantilla_approvals",
  "account_requests",
  "coverage",
  "vacancy_closures",
  "hr_emploc_deletions",
  "deactivations",
  "applicant_movements",
  "account_group_transfers",
  "relievers",
]);

function ApprovalsPageContent() {
  const searchParams = useSearchParams();
  const paramTab = searchParams.get("tab") || searchParams.get("category");
  const urlCategory =
    paramTab && VALID_CATEGORIES.has(paramTab)
      ? (paramTab as RequestCategoryKey)
      : null;

  const [localCategory, setLocalCategory] =
    useState<RequestCategoryKey>("headcount");

  const selectedCategory = urlCategory ?? localCategory;

  // Clear-on-Click / Acknowledgment:
  // When a user selects/clicks a request category, temporarily clear or acknowledge
  // the count badge for that session until data reloads.
  const [acknowledgedCategories, setAcknowledgedCategories] = useState<
    Set<RequestCategoryKey>
  >(new Set());

  const {
    data: counts = {
      new_stores: 0,
      headcount: 0,
      plantilla_approvals: 0,
      account_requests: 0,
      coverage: 0,
      vacancy_closures: 0,
      hr_emploc_deletions: 0,
      deactivations: 0,
      applicant_movements: 0,
      account_group_transfers: 0,
      relievers: 0,
    },
    isLoading: isLoadingCounts,
    refetch: refetchCounts,
    isRefetching: isRefetchingCounts,
  } = useRequestCategoryCounts();

  const handleSelectCategory = (key: RequestCategoryKey) => {
    setLocalCategory(key);
    // Mark as acknowledged in current session view state to clear trailing pill badge
    setAcknowledgedCategories((prev) => {
      const next = new Set(prev);
      next.add(key);
      return next;
    });
  };

  const handleRefresh = async () => {
    setAcknowledgedCategories(new Set());
    await refetchCounts();
  };

  return (
    <div className="space-y-6">
      <AdminPageHeader
        categoryTag="ADMIN PANEL"
        moduleName="Approvals"
        title="Request Center"
        subtitle="Operational request hub and approval queue for headcount quota amendments, store additions, and workforce adjustments."
        icon={CheckCheck}
        primaryAction={{
          label: isRefetchingCounts || isLoadingCounts ? "Refreshing..." : "Refresh Counts",
          icon: RefreshCw,
          onClick: handleRefresh,
          disabled: isRefetchingCounts || isLoadingCounts,
        }}
      />

      {/* Top Horizontal Navigation Tab Strip */}
      <div className="w-full rounded-xl border border-[var(--line)] bg-[var(--surface-base)] p-2">
        <RequestCategoryNavigation
          selectedCategory={selectedCategory}
          onSelectCategory={handleSelectCategory}
          counts={counts}
          acknowledgedCategories={acknowledgedCategories}
          isLoadingCounts={isLoadingCounts}
        />
      </div>

      {/* Active Queue Review Pane - 100% Full Width */}
      <div className="w-full min-w-0 rounded-xl border border-[var(--line)] bg-[var(--surface-base)] p-6">
        <ActiveQueueReviewPane
          selectedCategory={selectedCategory}
          onSelectCategory={handleSelectCategory}
          counts={counts}
        />
      </div>
    </div>
  );
}

export default function ApprovalsPage() {
  return (
    <Suspense
      fallback={
        <div className="space-y-6">
          <div className="h-14 border-b border-border-subtle bg-surface-base animate-pulse" />
          <div className="h-64 rounded-xl border border-border-default bg-surface-base animate-pulse" />
        </div>
      }
    >
      <ApprovalsPageContent />
    </Suspense>
  );
}
