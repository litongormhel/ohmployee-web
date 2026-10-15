"use client";

import { useState } from "react";
import { RefreshCw, Activity, ShieldCheck } from "lucide-react";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { MetricCard } from "@/components/shared/MetricCard";
import { AdminFilterBar } from "@/components/shared/AdminFilterBar";
import {
  useCencomAllocationKpi,
  useCencomGroupKpi,
  useCencomDeploymentSummary,
  useCencomStoreStats,
} from "@/lib/queries/cencom";
import { CencomGroupTable } from "@/components/cencom/CencomGroupTable";
import { CencomDeploymentCard } from "@/components/cencom/CencomDeploymentCard";

export default function CencomPage() {
  const [searchQuery, setSearchQuery] = useState("");
  const [healthFilter, setHealthFilter] = useState("all");

  // React Query hooks
  const {
    data: kpi,
    isLoading: isLoadingKpi,
    isError: isErrorKpi,
    error: kpiError,
    refetch: refetchKpi,
    isRefetching: isRefetchingKpi,
  } = useCencomAllocationKpi();

  const {
    data: groups = [],
    isLoading: isLoadingGroups,
    isError: isErrorGroups,
    error: groupsError,
    refetch: refetchGroups,
    isRefetching: isRefetchingGroups,
  } = useCencomGroupKpi();

  const {
    data: deploymentSummary = {
      totalDepartures: 0,
      additionalHc: 0,
      deletedVcode: 0,
      deployment: 0,
    },
    isLoading: isLoadingDeployment,
    refetch: refetchDeployment,
  } = useCencomDeploymentSummary();

  const {
    data: storeStats = {
      totalStores: 0,
      activeStores: 0,
      deploymentRate: 0,
    },
    isLoading: isLoadingStores,
    refetch: refetchStores,
  } = useCencomStoreStats();

  const isRefreshingAny =
    isRefetchingKpi || isRefetchingGroups;

  const handleRefresh = async () => {
    await Promise.all([
      refetchKpi(),
      refetchGroups(),
      refetchDeployment(),
      refetchStores(),
    ]);
  };

  const handleResetFilters = () => {
    setSearchQuery("");
    setHealthFilter("all");
  };

  // MetricCard badges and status
  const mfrBadge = kpi?.isNormalized
    ? "COHERENT"
    : kpi?.healthStatus
    ? kpi.healthStatus.toUpperCase()
    : "STABLE";

  return (
    <div className="space-y-6">
      {/* 1. Header */}
      <AdminPageHeader
        categoryTag="ADMIN PANEL"
        moduleName="CENCOM"
        title="CENCOM Central Command"
        subtitle="Operational manpower fulfillment, slot-authority allocation, and group performance monitoring."
        icon={Activity}
        primaryAction={{
          label: isRefreshingAny ? "Refreshing..." : "Refresh Data",
          icon: RefreshCw,
          onClick: handleRefresh,
          disabled: isRefreshingAny,
        }}
      />

      {/* 2. Top-Level KPI Summary Grid */}
      <section aria-label="CENCOM Key Performance Indicators">
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-5">
          {/* Total Required Headcount */}
          <MetricCard
            label="Total Required"
            value={kpi?.required}
            badge="Authorized"
            helperText="Plantilla slot capacity"
            isLoading={isLoadingKpi}
            isError={isErrorKpi}
            errorText={kpiError?.message}
          />

          {/* Total Actual (Active) Headcount */}
          <MetricCard
            label="Total Actual"
            value={kpi?.actual}
            badge="Active"
            helperText="Employees on board"
            isLoading={isLoadingKpi}
            isError={isErrorKpi}
            errorText={kpiError?.message}
          />

          {/* Open Vacancies */}
          <MetricCard
            label="Open Vacancies"
            value={kpi?.vacant}
            badge={kpi?.vacant === 0 ? "Zero Vacant" : "Unfilled"}
            helperText={
              kpi?.vacant === 0
                ? "Slot authority coherent"
                : "Open headcount positions"
            }
            isLoading={isLoadingKpi}
            isError={isErrorKpi}
            errorText={kpiError?.message}
          />

          {/* Overall MFR % */}
          <MetricCard
            label="Overall MFR"
            value={kpi ? `${kpi.mfrPercent.toFixed(1)}%` : "--"}
            badge={mfrBadge}
            helperText="Fulfillment vs required"
            isLoading={isLoadingKpi}
            isError={isErrorKpi}
            errorText={kpiError?.message}
          />

          {/* Deployed Stores vs Total Stores */}
          <MetricCard
            label="Deployed Stores"
            value={
              storeStats.totalStores > 0
                ? `${storeStats.activeStores} / ${storeStats.totalStores}`
                : "--"
            }
            badge={`${storeStats.deploymentRate}%`}
            helperText="Operating stores in network"
            isLoading={isLoadingStores}
          />
        </div>
      </section>

      {/* 3. Slot Authority Coherence Callout Banner */}
      {kpi?.isNormalized && (
        <div className="flex items-center gap-3 rounded-lg border border-blue-200 bg-blue-50/70 p-4 text-blue-900 shadow-xs">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-blue-100 text-blue-700">
            <ShieldCheck className="h-5 w-5" />
          </div>
          <div className="text-sm">
            <p className="font-semibold">Slot Authority Coherence Enforced</p>
            <p className="text-xs text-blue-700">
              Plantilla slot authority active: Groups with actual headcount meeting or exceeding capacity
              have vacancies reconciled to 0 and MFR evaluated at 100%, eliminating ghost vacancy artifacts.
            </p>
          </div>
        </div>
      )}

      {/* 4. Monthly Operational Deployment Summary Card */}
      <CencomDeploymentCard
        deployment={deploymentSummary}
        storeStats={storeStats}
        isLoading={isLoadingDeployment || isLoadingStores}
      />

      {/* 5. Group Performance Breakdown Section */}
      <section className="space-y-4" aria-label="Group Performance Breakdown">
        <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-center">
          <div>
            <h2 className="text-lg font-semibold text-text-primary">
              Group Performance Breakdown
            </h2>
            <p className="text-xs text-text-muted">
              Headcount quota allocation, store counts, and manpower fulfillment rate by operational group
            </p>
          </div>
        </div>

        {/* Filter Bar */}
        <AdminFilterBar
          searchPlaceholder="Search groups or accounts (e.g. Banko, Three)..."
          searchVal={searchQuery}
          onSearchChange={setSearchQuery}
          showApplyButton={false}
          showResetButton={searchQuery.trim().length > 0 || healthFilter !== "all"}
          onReset={handleResetFilters}
          filterSlot={
            <div className="flex items-center gap-2">
              <label htmlFor="cencom-health-filter" className="sr-only">
                Health Status
              </label>
              <select
                id="cencom-health-filter"
                value={healthFilter}
                onChange={(e) => setHealthFilter(e.target.value)}
                className="h-10 rounded-md border border-border-default bg-surface-muted px-3 text-sm text-text-primary outline-none transition-colors focus:border-brand-500"
              >
                <option value="all">All Health Statuses</option>
                <option value="healthy">Healthy (&gt;=100%)</option>
                <option value="at_risk">At Risk (90-99%)</option>
                <option value="critical">Critical (&lt;90%)</option>
              </select>
            </div>
          }
        />

        {/* Group Performance Table */}
        <CencomGroupTable
          groups={groups}
          isLoading={isLoadingGroups}
          isError={isErrorGroups}
          error={groupsError}
          onRetry={refetchGroups}
          searchQuery={searchQuery}
          healthFilter={healthFilter}
        />
      </section>
    </div>
  );
}
