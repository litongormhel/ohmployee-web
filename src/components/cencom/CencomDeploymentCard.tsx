"use client";

import {
  TrendingUp,
  UserMinus,
  UserPlus,
  Trash2,
  Store,
} from "lucide-react";
import type { CencomDeploymentSummary, CencomStoreStats } from "@/lib/queries/cencom";

export interface CencomDeploymentCardProps {
  deployment: CencomDeploymentSummary;
  storeStats: CencomStoreStats;
  isLoading?: boolean;
}

export function CencomDeploymentCard({
  deployment,
  storeStats,
  isLoading = false,
}: CencomDeploymentCardProps) {
  return (
    <div className="rounded-lg border border-border-default bg-surface-base p-5 shadow-xs">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-border-default pb-3">
        <div>
          <h3 className="text-sm font-semibold uppercase tracking-wider text-text-secondary">
            Operational Deployment Summary
          </h3>
          <p className="mt-0.5 text-xs text-text-muted">
            Current month deployment metrics and active store distribution
          </p>
        </div>
        <div className="inline-flex items-center gap-1.5 rounded-full bg-slate-100 px-2.5 py-1 text-xs font-medium text-slate-700 border border-slate-200">
          <Store className="h-3.5 w-3.5 text-slate-500" />
          <span>
            {storeStats.activeStores} Active Stores ({storeStats.deploymentRate}% of {storeStats.totalStores})
          </span>
        </div>
      </div>

      <div className="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-4">
        {/* New Deployments */}
        <div className="flex items-center gap-3 rounded-md border border-emerald-100 bg-emerald-50/50 p-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-emerald-100 text-emerald-700">
            <TrendingUp className="h-5 w-5" />
          </div>
          <div>
            <div className="text-xs font-medium text-emerald-800">New Deployments</div>
            <div className="text-xl font-bold font-mono text-emerald-950">
              {isLoading ? "--" : deployment.deployment}
            </div>
            <div className="text-[11px] text-emerald-600">Onboarded this month</div>
          </div>
        </div>

        {/* Additional HC */}
        <div className="flex items-center gap-3 rounded-md border border-blue-100 bg-blue-50/50 p-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-blue-100 text-blue-700">
            <UserPlus className="h-5 w-5" />
          </div>
          <div>
            <div className="text-xs font-medium text-blue-800">Additional HC</div>
            <div className="text-xl font-bold font-mono text-blue-950">
              {isLoading ? "--" : deployment.additionalHc}
            </div>
            <div className="text-[11px] text-blue-600">Approved slots</div>
          </div>
        </div>

        {/* Departures */}
        <div className="flex items-center gap-3 rounded-md border border-rose-100 bg-rose-50/50 p-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-rose-100 text-rose-700">
            <UserMinus className="h-5 w-5" />
          </div>
          <div>
            <div className="text-xs font-medium text-rose-800">Total Departures</div>
            <div className="text-xl font-bold font-mono text-rose-950">
              {isLoading ? "--" : deployment.totalDepartures}
            </div>
            <div className="text-[11px] text-rose-600">Separations processed</div>
          </div>
        </div>

        {/* Deleted VCodes */}
        <div className="flex items-center gap-3 rounded-md border border-slate-200 bg-slate-50/60 p-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-slate-200 text-slate-700">
            <Trash2 className="h-5 w-5" />
          </div>
          <div>
            <div className="text-xs font-medium text-slate-800">Deleted VCodes</div>
            <div className="text-xl font-bold font-mono text-slate-950">
              {isLoading ? "--" : deployment.deletedVcode}
            </div>
            <div className="text-[11px] text-slate-500">Archived vacancies</div>
          </div>
        </div>
      </div>
    </div>
  );
}
