"use client";

import { memo } from "react";
import { Store } from "lucide-react";
import type { CencomDeploymentSummary, CencomStoreStats } from "@/lib/queries/cencom";
import { CencomAnimatedNumber } from "./CencomAnimatedNumber";

export interface CencomDeploymentCardProps {
  deployment: CencomDeploymentSummary;
  storeStats: CencomStoreStats;
  isScopedGroup?: boolean;
  isLoading?: boolean;
}

export const CencomDeploymentCard = memo(function CencomDeploymentCard({
  deployment,
  storeStats,
  isScopedGroup = false,
  isLoading = false,
}: CencomDeploymentCardProps) {
  return (
    <div className="rounded-xl border border-border-default bg-surface-base p-5 shadow-xs">
      {/* Header Bar */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border-default pb-3.5">
        <div>
          <h3 className="text-sm font-semibold text-text-primary">
            Deployment summary
          </h3>
          <p className="mt-0.5 text-xs text-text-muted">
            Current calendar month operational movements and network footprint
          </p>
        </div>
        <div className="inline-flex items-center gap-1.5 rounded-full border border-border-default bg-surface-muted px-2.5 py-1 text-xs font-medium text-text-secondary">
          <Store className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
          <span>
            {storeStats.activeStores} active stores ({storeStats.deploymentRate}% of {storeStats.totalStores})
          </span>
        </div>
      </div>

      {/* 4 Equal Tiles Separated by Dividers */}
      <div className="mt-4 grid grid-cols-2 divide-y divide-border-default sm:grid-cols-4 sm:divide-x sm:divide-y-0">
        {/* Tile 1: New deployments */}
        <div className="p-3 sm:px-4 sm:py-2">
          <div className="flex items-center gap-2">
            <span
              className="h-2 w-2 rounded-full bg-status-success-text shrink-0"
              aria-hidden="true"
            />
            <span className="text-xs font-medium text-text-secondary">
              New deployments
            </span>
          </div>
          <div className="mt-2 text-2xl font-semibold leading-none tracking-tight text-text-primary tabular-nums">
            {isLoading ? (
              "--"
            ) : isScopedGroup ? (
              "—"
            ) : (
              <CencomAnimatedNumber value={deployment.deployment} />
            )}
          </div>
          <div className="mt-1 text-[11px] text-text-muted">
            {isScopedGroup ? "All groups only" : "Onboarded this month"}
          </div>
        </div>

        {/* Tile 2: Additional HC */}
        <div className="p-3 sm:px-4 sm:py-2">
          <div className="flex items-center gap-2">
            <span
              className="h-2 w-2 rounded-full bg-status-info-text shrink-0"
              aria-hidden="true"
            />
            <span className="text-xs font-medium text-text-secondary">
              Additional HC
            </span>
          </div>
          <div className="mt-2 text-2xl font-semibold leading-none tracking-tight text-text-primary tabular-nums">
            {isLoading ? (
              "--"
            ) : isScopedGroup ? (
              "—"
            ) : (
              <CencomAnimatedNumber value={deployment.additionalHc} />
            )}
          </div>
          <div className="mt-1 text-[11px] text-text-muted">
            {isScopedGroup ? "All groups only" : "Approved slots"}
          </div>
        </div>

        {/* Tile 3: Total departures */}
        <div className="p-3 sm:px-4 sm:py-2">
          <div className="flex items-center gap-2">
            <span
              className="h-2 w-2 rounded-full bg-status-danger-text shrink-0"
              aria-hidden="true"
            />
            <span className="text-xs font-medium text-text-secondary">
              Total departures
            </span>
          </div>
          <div className="mt-2 text-2xl font-semibold leading-none tracking-tight text-text-primary tabular-nums">
            {isLoading ? (
              "--"
            ) : isScopedGroup ? (
              "—"
            ) : (
              <CencomAnimatedNumber value={deployment.totalDepartures} />
            )}
          </div>
          <div className="mt-1 text-[11px] text-text-muted">
            {isScopedGroup ? "All groups only" : "Separations processed"}
          </div>
        </div>

        {/* Tile 4: Deleted VCodes */}
        <div className="p-3 sm:px-4 sm:py-2">
          <div className="flex items-center gap-2">
            <span
              className="h-2 w-2 rounded-full bg-status-neutral-text shrink-0"
              aria-hidden="true"
            />
            <span className="text-xs font-medium text-text-secondary">
              Deleted VCodes
            </span>
          </div>
          <div className="mt-2 text-2xl font-semibold leading-none tracking-tight text-text-primary tabular-nums">
            {isLoading ? (
              "--"
            ) : isScopedGroup ? (
              "—"
            ) : (
              <CencomAnimatedNumber value={deployment.deletedVcode} />
            )}
          </div>
          <div className="mt-1 text-[11px] text-text-muted">
            {isScopedGroup ? "All groups only" : "Archived vacancies"}
          </div>
        </div>
      </div>
    </div>
  );
});
