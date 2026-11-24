"use client";

import { MetricCard } from "@/components/shared/MetricCard";

export interface UserMetricsCardsProps {
  totalCount: number;
  activeCount: number;
  inactiveCount: number;
  isLoading?: boolean;
  activeTab?: "all" | "active" | "inactive";
  onSelectTab?: (tab: "all" | "active" | "inactive") => void;
}

export function UserMetricsCards({
  totalCount,
  activeCount,
  inactiveCount,
  isLoading = false,
  activeTab,
  onSelectTab,
}: UserMetricsCardsProps) {
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
      <div
        onClick={() => onSelectTab?.("all")}
        className={onSelectTab ? "cursor-pointer transition-transform active:scale-[0.99]" : ""}
        role={onSelectTab ? "button" : undefined}
        tabIndex={onSelectTab ? 0 : undefined}
        aria-label="Filter by All Users"
      >
        <MetricCard
          label="Total Users"
          value={isLoading ? undefined : totalCount}
          isLoading={isLoading}
          helperText="All registered user profiles"
          className={
            activeTab === "all"
              ? "ring-2 ring-brand-500/60 border-brand-500/40 shadow-xs transition-all"
              : "hover:border-border-strong hover:shadow-xs transition-all"
          }
        />
      </div>
      <div
        onClick={() => onSelectTab?.("active")}
        className={onSelectTab ? "cursor-pointer transition-transform active:scale-[0.99]" : ""}
        role={onSelectTab ? "button" : undefined}
        tabIndex={onSelectTab ? 0 : undefined}
        aria-label="Filter by Active Users"
      >
        <MetricCard
          label="Active"
          value={isLoading ? undefined : activeCount}
          isLoading={isLoading}
          helperText="Users with authorized system access"
          className={
            activeTab === "active"
              ? "ring-2 ring-brand-500/60 border-brand-500/40 shadow-xs transition-all"
              : "hover:border-border-strong hover:shadow-xs transition-all"
          }
        />
      </div>
      <div
        onClick={() => onSelectTab?.("inactive")}
        className={onSelectTab ? "cursor-pointer transition-transform active:scale-[0.99]" : ""}
        role={onSelectTab ? "button" : undefined}
        tabIndex={onSelectTab ? 0 : undefined}
        aria-label="Filter by Inactive Users"
      >
        <MetricCard
          label="Inactive"
          value={isLoading ? undefined : inactiveCount}
          isLoading={isLoading}
          helperText="Suspended or soft-archived accounts"
          className={
            activeTab === "inactive"
              ? "ring-2 ring-brand-500/60 border-brand-500/40 shadow-xs transition-all"
              : "hover:border-border-strong hover:shadow-xs transition-all"
          }
        />
      </div>
    </div>
  );
}
