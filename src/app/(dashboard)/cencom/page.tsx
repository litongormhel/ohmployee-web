"use client";

import { Suspense, useMemo, useState, useTransition } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import {
  Activity,
  ArrowRight,
  MapPin,
  RefreshCw,
  ShieldCheck,
  TrendingUp,
  Users,
} from "lucide-react";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { AdminFilterBar } from "@/components/shared/AdminFilterBar";
import { useCurrentUser } from "@/lib/auth";
import {
  useCencomAllocationKpi,
  useCencomGroupKpi,
  useCencomDeploymentSummary,
  useCencomStoreStats,
} from "@/lib/queries/cencom";
import { CencomOverviewHeroCard } from "@/components/cencom/CencomOverviewHeroCard";
import { CencomKpiCard } from "@/components/cencom/CencomKpiCard";
import { CencomGroupScopeDropdown } from "@/components/cencom/CencomGroupScopeDropdown";
import { CencomGroupTable } from "@/components/cencom/CencomGroupTable";
import { CencomDeploymentCard } from "@/components/cencom/CencomDeploymentCard";
import { CencomTargetDeploymentTab } from "@/components/cencom/CencomTargetDeploymentTab";
import { CencomDeploymentActivityTab } from "@/components/cencom/CencomDeploymentActivityTab";
import { CencomQuickReportsTab } from "@/components/cencom/CencomQuickReportsTab";
import { SegmentedTabs, type TabItem } from "@/components/shared/SegmentedTabs";

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

  // State for Group scope dropdown (Overview tab only)
  const [selectedGroupId, setSelectedGroupId] = useState<string>("all");

  // State for Groups tab filters
  const [groupSearchQuery, setGroupSearchQuery] = useState("");
  const [groupHealthFilter, setGroupHealthFilter] = useState("all");

  // User context for role scope resolution
  const currentUser = useCurrentUser();
  const allowedGroupIds =
    currentUser?.groupScope?.mode === "scoped"
      ? currentUser.groupScope.ids
      : null;

  // React Query hooks for Overview and Groups
  const {
    data: kpi,
    isLoading: isLoadingKpi,
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

  // Selected group resolution
  const selectedGroup = useMemo(() => {
    if (selectedGroupId === "all") return null;
    return groups.find((g) => g.groupId === selectedGroupId) ?? null;
  }, [groups, selectedGroupId]);

  const isScoped = selectedGroupId !== "all" && !!selectedGroup;

  // Overview metrics scoped resolution
  const displayedRequired = isScoped ? selectedGroup.required : (kpi?.required ?? 0);
  const displayedActual = isScoped ? selectedGroup.actual : (kpi?.actual ?? 0);
  const displayedVacant = isScoped ? selectedGroup.vacant : (kpi?.vacant ?? 0);
  const displayedMfrPercent = isScoped ? selectedGroup.mfrPercent : (kpi?.mfrPercent ?? 0);
  const displayedHealthStatus = isScoped ? selectedGroup.healthStatus : (kpi?.healthStatus ?? "critical");
  const displayedIsNormalized = isScoped ? selectedGroup.isNormalized : (kpi?.isNormalized ?? false);
  const displayedActiveStores = isScoped ? selectedGroup.activeStores : storeStats.activeStores;
  const displayedTotalStores = isScoped ? selectedGroup.totalStores : storeStats.totalStores;
  const displayedDeploymentRate =
    displayedTotalStores > 0
      ? Math.round((displayedActiveStores / displayedTotalStores) * 1000) / 10
      : 0;

  const cencomTabs: TabItem<CencomTab>[] = useMemo(
    () => [
      { key: "overview", label: "Overview" },
      { key: "groups", label: "Groups", count: groups.length },
      {
        key: "target_deployment",
        label: "Target Deployment",
        count: kpi?.vacant && kpi.vacant > 0 ? kpi.vacant : undefined,
      },
      { key: "deployments", label: "Deployment Activity" },
      { key: "reports", label: "Quick Reports", count: groups.length > 0 ? 18 : 0 },
    ],
    [groups.length, kpi?.vacant]
  );

  return (
    <div className="space-y-6">
      {/* 1. Header */}
      <AdminPageHeader
        categoryTag="Admin panel"
        moduleName="CENCOM"
        title={
          <span className="text-[28px] sm:text-[34px] lg:text-[40px] font-semibold tracking-[-0.035em] leading-tight text-text-primary">
            CENCOM Central Command
          </span>
        }
        subtitle="Operational manpower fulfillment, slot-authority allocation, vacancy aging, and deployment monitoring."
        icon={Activity}
        primaryAction={{
          label: isRefreshingAny ? "Refreshing..." : "Refresh Data",
          icon: RefreshCw,
          onClick: handleGlobalRefresh,
          disabled: isRefreshingAny,
        }}
      />

      {/* 2. 5-Tab Command Center Navigation Bar with Sliding Pill and Rightmost Group Dropdown */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border-subtle pb-2">
        <SegmentedTabs
          tabs={cencomTabs}
          activeKey={activeTab}
          onChange={(t) => handleTabChange(t as CencomTab)}
        />

        {/* Right: Group Dropdown (Overview Tab only, hidden on all other tabs) */}
        {activeTab === "overview" && (
          <div className="shrink-0 animate-in fade-in duration-[200ms]">
            <CencomGroupScopeDropdown
              groups={groups}
              allowedGroupIds={allowedGroupIds}
              selectedGroupId={selectedGroupId}
              onSelectGroup={setSelectedGroupId}
              disabled={isRefreshingAny}
            />
          </div>
        )}
      </div>

      {/* 3. Tab Body Views */}

      {/* ---------------- Tab 1: Overview ---------------- */}
      {activeTab === "overview" && (
        <div className="space-y-6 animate-in fade-in duration-[280ms]">
          {/* Top-Level KPI Summary Grid: 2-row Hero card on left + 4 Neutral KPI Cards on right */}
          <section aria-label="CENCOM Key Performance Indicators">
            <div className="grid grid-cols-1 gap-4 lg:grid-cols-12">
              {/* Hero: Overall MFR Gauge (Left, spans 2 rows on desktop) */}
              <div className="lg:col-span-4 lg:row-span-2">
                <CencomOverviewHeroCard
                  mfrPercent={displayedMfrPercent}
                  healthStatus={displayedHealthStatus}
                  isNormalized={displayedIsNormalized}
                  actual={displayedActual}
                  required={displayedRequired}
                  isLoading={isLoadingKpi || isLoadingGroups}
                />
              </div>

              {/* Four Neutral KPI Cards: 2x2 grid */}
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:col-span-8">
                <CencomKpiCard
                  label="Total required"
                  value={displayedRequired}
                  subtitle="Plantilla slot capacity"
                  badge="Authorized"
                  isLoading={isLoadingKpi || isLoadingGroups}
                />
                <CencomKpiCard
                  label="Total actual"
                  value={displayedActual}
                  subtitle="Employees on board"
                  badge="Active"
                  isLoading={isLoadingKpi || isLoadingGroups}
                />
                <CencomKpiCard
                  label="Open vacancies"
                  value={displayedVacant}
                  subtitle={
                    displayedVacant === 0
                      ? "Slot authority coherent"
                      : "Open headcount positions"
                  }
                  badge={displayedVacant === 0 ? "Zero vacant" : "Unfilled"}
                  isLoading={isLoadingKpi || isLoadingGroups}
                />
                <CencomKpiCard
                  label="Deployed stores"
                  value={displayedActiveStores}
                  subtitle="Operating stores in network"
                  progressRatio={{
                    current: displayedActiveStores,
                    total: displayedTotalStores,
                    ratePercent: displayedDeploymentRate,
                  }}
                  isLoading={isLoadingStores || isLoadingGroups}
                />
              </div>
            </div>
          </section>

          {/* Slot Authority Coherence Callout Banner */}
          {displayedIsNormalized && (
            <div className="flex items-center gap-3 rounded-xl border border-status-info-border bg-status-info-bg p-4 text-status-info-text shadow-xs">
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-status-info-border bg-surface-base text-status-info-text">
                <ShieldCheck className="h-5 w-5" aria-hidden="true" />
              </div>
              <div className="text-sm">
                <p className="font-semibold text-text-primary">
                  Slot Authority Coherence Enforced
                </p>
                <p className="mt-0.5 text-xs text-text-secondary">
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
            isScopedGroup={isScoped}
            isLoading={isLoadingDeployment || isLoadingStores}
          />

          {/* Quick Shortcuts to other Tabs (Neutral tokens, no TAB 2/3/4 labels or tinted links) */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div
              onClick={() => handleTabChange("groups")}
              className="group flex flex-col justify-between rounded-xl border border-border-default bg-surface-base p-5 transition-colors hover:border-border-strong hover:shadow-xs cursor-pointer"
            >
              <div>
                <div className="flex items-center justify-between">
                  <div className="rounded-lg bg-surface-muted p-2 text-text-primary">
                    <Users className="h-4 w-4" aria-hidden="true" />
                  </div>
                </div>
                <h4 className="mt-3 text-base font-semibold text-text-primary transition-colors group-hover:text-brand-600">
                  Group Performance Roster
                </h4>
                <p className="mt-1 text-xs text-text-secondary">
                  Inspect {groups.length} operational groups, headcount quota allocations, and store distribution.
                </p>
              </div>
              <div className="mt-4 flex items-center justify-between text-xs font-semibold text-text-secondary transition-colors group-hover:text-brand-600">
                <span>View Groups Table</span>
                <ArrowRight className="h-3.5 w-3.5 transition-transform group-hover:translate-x-1" aria-hidden="true" />
              </div>
            </div>

            <div
              onClick={() => handleTabChange("target_deployment")}
              className="group flex flex-col justify-between rounded-xl border border-border-default bg-surface-base p-5 transition-colors hover:border-border-strong hover:shadow-xs cursor-pointer"
            >
              <div>
                <div className="flex items-center justify-between">
                  <div className="rounded-lg bg-surface-muted p-2 text-text-primary">
                    <MapPin className="h-4 w-4" aria-hidden="true" />
                  </div>
                </div>
                <h4 className="mt-3 text-base font-semibold text-text-primary transition-colors group-hover:text-brand-600">
                  Target Deployment & Aging
                </h4>
                <p className="mt-1 text-xs text-text-secondary">
                  Area & province vacancy aging brackets (&lt;30d, 30–60d, &gt;60d) and store outlet drilldowns.
                </p>
              </div>
              <div className="mt-4 flex items-center justify-between text-xs font-semibold text-text-secondary transition-colors group-hover:text-brand-600">
                <span>View Target Deployment</span>
                <ArrowRight className="h-3.5 w-3.5 transition-transform group-hover:translate-x-1" aria-hidden="true" />
              </div>
            </div>

            <div
              onClick={() => handleTabChange("deployments")}
              className="group flex flex-col justify-between rounded-xl border border-border-default bg-surface-base p-5 transition-colors hover:border-border-strong hover:shadow-xs cursor-pointer"
            >
              <div>
                <div className="flex items-center justify-between">
                  <div className="rounded-lg bg-surface-muted p-2 text-text-primary">
                    <TrendingUp className="h-4 w-4" aria-hidden="true" />
                  </div>
                </div>
                <h4 className="mt-3 text-base font-semibold text-text-primary transition-colors group-hover:text-brand-600">
                  Deployment Activity Roster
                </h4>
                <p className="mt-1 text-xs text-text-secondary">
                  Chronological candidate endorsements, plantilla transitions, and monthly placement logs.
                </p>
              </div>
              <div className="mt-4 flex items-center justify-between text-xs font-semibold text-text-secondary transition-colors group-hover:text-brand-600">
                <span>View Deployment Activity</span>
                <ArrowRight className="h-3.5 w-3.5 transition-transform group-hover:translate-x-1" aria-hidden="true" />
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
                <Users className="h-5 w-5 text-brand-500" />
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
