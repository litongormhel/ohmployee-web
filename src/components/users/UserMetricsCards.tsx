"use client";

import { MetricCard } from "@/components/shared/MetricCard";

export interface UserMetricsCardsProps {
  totalCount: number;
  activeCount: number;
  inactiveCount: number;
  isLoading?: boolean;
}

export function UserMetricsCards({
  totalCount,
  activeCount,
  inactiveCount,
  isLoading = false,
}: UserMetricsCardsProps) {
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
      <MetricCard
        label="Total Users"
        value={isLoading ? undefined : totalCount}
        isLoading={isLoading}
        helperText="All registered user profiles"
      />
      <MetricCard
        label="Active"
        value={isLoading ? undefined : activeCount}
        isLoading={isLoading}
        helperText="Users with authorized system access"
      />
      <MetricCard
        label="Inactive"
        value={isLoading ? undefined : inactiveCount}
        isLoading={isLoading}
        helperText="Suspended or soft-archived accounts"
      />
    </div>
  );
}
