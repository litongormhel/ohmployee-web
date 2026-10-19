"use client";

import { Suspense, useState, useTransition } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import {
  Activity,
  ArrowRight,
  FileBarChart2,
  MapPin,
  RefreshCw,
  ShieldCheck,
  TrendingUp,
  Users,
} from "lucide-react";
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
import { CencomTargetDeploymentTab } from "@/components/cencom/CencomTargetDeploymentTab";
import { CencomDeploymentActivityTab } from "@/components/cencom/CencomDeploymentActivityTab";
import { CencomQuickReportsTab } from "@/components/cencom/CencomQuickReportsTab";

export type CencomTab =
  | "overview"
  | "groups"
  | "target_deployment"
  | "deployments"
  | "reports";

function CencomPageContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [, startTransition] = useTransition();

  const tabParam = searchParams.get("tab") as CencomTab | null;

  const activeTab: CencomTab =
    tabParam === "groups" ||
    tabParam === "target_deployment" ||
    tabParam === "deployments" ||
    tabParam === "reports"
      ? tabParam
      : "overview";

  const handleTabChange = (newTab: string | CencomTab) => {
    startTransition(() => {
      const params = new URLSearchParams(searchParams.toString());
      if (newTab === "overview") {
        params.delete("tab");
      } else {
        params.set("tab", newTab);
      }
      const query = params.toString();
      router.push(`/cencom${query ? `?${query}` : ""}`);
    });
  };

  // State for Groups tab filters
  const [groupSearchQuery, setGroupSearchQuery] = useState("");
  const [groupHealthFilter, setGroupHealthFilter] = useState("all");

  // React Query hooks for Overview and Groups
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

  const isRefreshingAny = isRefetchingKpi || isRefetchingGroups;

  const handleGlobalRefresh = async () => {
    await Promise.all([
      refetchKpi(),
      refetchGroups(),
      refetchDeployment(),
      refetchStores(),
    ]);
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
        subtitle="Operational manpower fulfillment, slot-authority allocation, vacancy aging, and deployment monitoring."
        icon={Activity}
        primaryAction={{
          label: isRefreshingAny ? "Refreshing..." : "Refresh Data",
          icon: RefreshCw,
          onClick: handleGlobalRefresh,
          disabled: isRefreshingAny,
        }}
      />

      {/* 2. 5-Tab Command Center Navigation Bar */}
      <div className="flex items-center gap-1.5 overflow-x-auto no-scrollbar border-b border-border-subtle pb-2">
        {/* Tab 1: Overview */}
        <button
          onClick={() => handleTabChange("overview")}
          className={`flex items-center gap-2 px-3.5 py-2 text-xs font-semibold rounded-lg transition whitespace-nowrap cursor-pointer ${
            activeTab === "overview"
              ? "bg-brand-50 text-brand-900 border border-brand-200 shadow-2xs font-bold"
              : "text-text-secondary hover:text-text-primary hover:bg-surface-hover border border-transparent"
          }`}
        >
          <Activity className="w-3.5 h-3.5 text-brand-600" />
          <span>Overview</span>
          {kpi?.isNormalized && (
            <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
          )}
        </button>

        {/* Tab 2: Groups */}
        <button
          onClick={() => handleTabChange("groups")}
          className={`flex items-center gap-2 px-3.5 py-2 text-xs font-semibold rounded-lg transition whitespace-nowrap cursor-pointer ${
            activeTab === "groups"
              ? "bg-brand-50 text-brand-900 border border-brand-200 shadow-2xs font-bold"
              : "text-text-secondary hover:text-text-primary hover:bg-surface-hover border border-transparent"
          }`}
        >
          <Users className="w-3.5 h-3.5 text-blue-600" />
          <span>Groups</span>
          <span className="rounded bg-slate-100 px-1.5 py-0.2 text-[10px] text-slate-600 font-mono">
            {groups.length}
          </span>
        </button>

        {/* Tab 3: Target Deployment */}
        <button
          onClick={() => handleTabChange("target_deployment")}
          className={`flex items-center gap-2 px-3.5 py-2 text-xs font-semibold rounded-lg transition whitespace-nowrap cursor-pointer ${
            activeTab === "target_deployment"
              ? "bg-brand-50 text-brand-900 border border-brand-200 shadow-2xs font-bold"
              : "text-text-secondary hover:text-text-primary hover:bg-surface-hover border border-transparent"
          }`}
        >
          <MapPin className="w-3.5 h-3.5 text-purple-600" />
          <span>Target Deployment</span>
          {kpi?.vacant && kpi.vacant > 0 ? (
            <span className="rounded bg-rose-100 px-1.5 py-0.2 text-[10px] text-rose-700 font-mono font-bold">
              {kpi.vacant}
            </span>
          ) : null}
        </button>

        {/* Tab 4: Deployment Activity */}
        <button
          onClick={() => handleTabChange("deployments")}
          className={`flex items-center gap-2 px-3.5 py-2 text-xs font-semibold rounded-lg transition whitespace-nowrap cursor-pointer ${
            activeTab === "deployments"
              ? "bg-brand-50 text-brand-900 border border-brand-200 shadow-2xs font-bold"
              : "text-text-secondary hover:text-text-primary hover:bg-surface-hover border border-transparent"
          }`}
        >
          <TrendingUp className="w-3.5 h-3.5 text-emerald-600" />
          <span>Deployment Activity</span>
        </button>

        {/* Tab 5: Quick Reports */}
        <button
          onClick={() => handleTabChange("reports")}
          className={`flex items-center gap-2 px-3.5 py-2 text-xs font-semibold rounded-lg transition whitespace-nowrap cursor-pointer ${
            activeTab === "reports"
              ? "bg-brand-50 text-brand-900 border border-brand-200 shadow-2xs font-bold"
              : "text-text-secondary hover:text-text-primary hover:bg-surface-hover border border-transparent"
          }`}
        >
          <FileBarChart2 className="w-3.5 h-3.5 text-indigo-600" />
          <span>Quick Reports</span>
          <span className="rounded bg-slate-100 px-1.5 py-0.2 text-[10px] text-slate-600 font-mono">
            18
          </span>
        </button>
      </div>

      {/* 3. Tab Body Views */}

      {/* ---------------- Tab 1: Overview ---------------- */}
      {activeTab === "overview" && (
        <div className="space-y-6 animate-in fade-in duration-150">
          {/* Top-Level KPI Summary Grid */}
          <section aria-label="CENCOM Key Performance Indicators">
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-5">
              <MetricCard
                label="Total Required"
                value={kpi?.required}
                badge="Authorized"
                helperText="Plantilla slot capacity"
                isLoading={isLoadingKpi}
                isError={isErrorKpi}
                errorText={kpiError?.message}
              />
              <MetricCard
                label="Total Actual"
                value={kpi?.actual}
                badge="Active"
                helperText="Employees on board"
                isLoading={isLoadingKpi}
                isError={isErrorKpi}
                errorText={kpiError?.message}
              />
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
              <MetricCard
                label="Overall MFR"
                value={kpi ? `${kpi.mfrPercent.toFixed(1)}%` : "--"}
                badge={mfrBadge}
                helperText="Fulfillment vs required"
                isLoading={isLoadingKpi}
                isError={isErrorKpi}
                errorText={kpiError?.message}
              />
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

          {/* Slot Authority Coherence Callout Banner */}
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

          {/* Monthly Operational Deployment Summary Card */}
          <CencomDeploymentCard
            deployment={deploymentSummary}
            storeStats={storeStats}
            isLoading={isLoadingDeployment || isLoadingStores}
          />

          {/* Quick Shortcuts to other Tabs */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div
              onClick={() => handleTabChange("groups")}
              className="group p-4 rounded-xl border border-border-default bg-surface-base hover:border-brand-300 hover:shadow-xs transition cursor-pointer flex flex-col justify-between"
            >
              <div>
                <div className="flex items-center justify-between">
                  <div className="p-2 rounded-lg bg-blue-50 text-blue-600">
                    <Users className="w-4 h-4" />
                  </div>
                  <span className="text-[10px] font-bold uppercase text-text-muted">
                    Tab 2
                  </span>
                </div>
                <h4 className="text-sm font-bold text-text-primary mt-2 group-hover:text-brand-600 transition">
                  Group Performance Roster
                </h4>
                <p className="text-xs text-text-secondary mt-1">
                  Inspect {groups.length} operational groups, headcount quota allocations, and store distribution.
                </p>
              </div>
              <div className="mt-3 flex items-center justify-between text-xs font-semibold text-brand-600">
                <span>View Groups Table</span>
                <ArrowRight className="w-3.5 h-3.5 group-hover:translate-x-1 transition" />
              </div>
            </div>

            <div
              onClick={() => handleTabChange("target_deployment")}
              className="group p-4 rounded-xl border border-border-default bg-surface-base hover:border-purple-300 hover:shadow-xs transition cursor-pointer flex flex-col justify-between"
            >
              <div>
                <div className="flex items-center justify-between">
                  <div className="p-2 rounded-lg bg-purple-50 text-purple-600">
                    <MapPin className="w-4 h-4" />
                  </div>
                  <span className="text-[10px] font-bold uppercase text-text-muted">
                    Tab 3
                  </span>
                </div>
                <h4 className="text-sm font-bold text-text-primary mt-2 group-hover:text-purple-600 transition">
                  Target Deployment & Aging
                </h4>
                <p className="text-xs text-text-secondary mt-1">
                  Area & province vacancy aging brackets (&lt;30d, 30–60d, &gt;60d) and store outlet drilldowns.
                </p>
              </div>
              <div className="mt-3 flex items-center justify-between text-xs font-semibold text-purple-600">
                <span>Open Target Deployment</span>
                <ArrowRight className="w-3.5 h-3.5 group-hover:translate-x-1 transition" />
              </div>
            </div>

            <div
              onClick={() => handleTabChange("deployments")}
              className="group p-4 rounded-xl border border-border-default bg-surface-base hover:border-emerald-300 hover:shadow-xs transition cursor-pointer flex flex-col justify-between"
            >
              <div>
                <div className="flex items-center justify-between">
                  <div className="p-2 rounded-lg bg-emerald-50 text-emerald-600">
                    <TrendingUp className="w-4 h-4" />
                  </div>
                  <span className="text-[10px] font-bold uppercase text-text-muted">
                    Tab 4
                  </span>
                </div>
                <h4 className="text-sm font-bold text-text-primary mt-2 group-hover:text-emerald-600 transition">
                  Deployment Activity Roster
                </h4>
                <p className="text-xs text-text-secondary mt-1">
                  Track newly deployed candidates, monthly movements, and store-level onboarding velocity.
                </p>
              </div>
              <div className="mt-3 flex items-center justify-between text-xs font-semibold text-emerald-600">
                <span>View Deployment Logs</span>
                <ArrowRight className="w-3.5 h-3.5 group-hover:translate-x-1 transition" />
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ---------------- Tab 2: Groups ---------------- */}
      {activeTab === "groups" && (
        <section className="space-y-4 animate-in fade-in duration-150" aria-label="Group Performance Breakdown">
          <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-center">
            <div>
              <h2 className="text-lg font-bold text-text-primary flex items-center gap-2">
                <Users className="h-5 w-5 text-blue-600" />
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
            searchVal={groupSearchQuery}
            onSearchChange={setGroupSearchQuery}
            showApplyButton={false}
            showResetButton={groupSearchQuery.trim().length > 0 || groupHealthFilter !== "all"}
            onReset={() => {
              setGroupSearchQuery("");
              setGroupHealthFilter("all");
            }}
            filterSlot={
              <div className="flex items-center gap-2">
                <label htmlFor="cencom-health-filter" className="sr-only">
                  Health Status
                </label>
                <select
                  id="cencom-health-filter"
                  value={groupHealthFilter}
                  onChange={(e) => setGroupHealthFilter(e.target.value)}
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
            searchQuery={groupSearchQuery}
            healthFilter={groupHealthFilter}
          />
        </section>
      )}

      {/* ---------------- Tab 3: Target Deployment / Vacancy Aging ---------------- */}
      {activeTab === "target_deployment" && (
        <CencomTargetDeploymentTab
          onRefresh={handleGlobalRefresh}
          isRefreshing={isRefreshingAny}
        />
      )}

      {/* ---------------- Tab 4: Deployment Activity ---------------- */}
      {activeTab === "deployments" && (
        <CencomDeploymentActivityTab
          onRefresh={handleGlobalRefresh}
          isRefreshing={isRefreshingAny}
        />
      )}

      {/* ---------------- Tab 5: Quick Reports ---------------- */}
      {activeTab === "reports" && (
        <CencomQuickReportsTab onSwitchTab={handleTabChange} />
      )}
    </div>
  );
}

export default function CencomPage() {
  return (
    <Suspense
      fallback={
        <div className="space-y-6">
          <div className="h-20 animate-pulse rounded-xl bg-surface-base" />
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-5">
            {[1, 2, 3, 4, 5].map((i) => (
              <div
                key={i}
                className="h-28 animate-pulse rounded-xl bg-surface-base"
              />
            ))}
          </div>
        </div>
      }
    >
      <CencomPageContent />
    </Suspense>
  );
}
