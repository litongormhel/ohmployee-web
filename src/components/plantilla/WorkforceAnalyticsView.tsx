"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  Activity,
  AlertCircle,
  AlertTriangle,
  ArrowRightLeft,
  BarChart3,
  Calendar,
  CheckCircle2,
  Clock,
  Download,
  Layers,
  MapPin,
  RefreshCw,
  ShieldAlert,
  Sparkles,
  TrendingUp,
  UserCheck,
  Users,
  XCircle,
} from "lucide-react";
import { useCurrentUser } from "@/lib/auth";
import { fetchPlantillaScopedAccounts } from "@/lib/queries/plantilla";
import { MetricCard } from "@/components/shared/MetricCard";
import { DataState } from "@/components/shared/DataState";
import { exportToXlsx } from "@/lib/utils/reports_export";
import {
  useWorkforcePoolOverview,
  useWorkforceDeploymentAnalytics,
  useWorkforceCoverageDemandAnalytics,
  useWorkforceConversionAnalytics,
  useWorkforceSlotReviewAnalytics,
  useWorkforceHealthSummary,
  useWorkforceExecutiveSummary,
  usePlantillaImportIncidents,
  type WfAnalyticsFilter,
} from "@/lib/queries/workforceAnalytics";

export type WorkforceAnalyticsTab =
  | "overview"
  | "deployment"
  | "coverage"
  | "conversion"
  | "slots"
  | "health"
  | "executive";

const TABS: { id: WorkforceAnalyticsTab; label: string; icon: React.ComponentType<{ className?: string }> }[] = [
  { id: "overview", label: "Overview", icon: Users },
  { id: "deployment", label: "Deployment", icon: MapPin },
  { id: "coverage", label: "Coverage", icon: UserCheck },
  { id: "conversion", label: "Conversion", icon: ArrowRightLeft },
  { id: "slots", label: "Slots", icon: Layers },
  { id: "health", label: "Health", icon: Activity },
  { id: "executive", label: "Executive", icon: BarChart3 },
];

function HorizontalBarRow({
  label,
  value,
  maxValue,
  colorClass = "bg-accent",
  textClass = "text-text-primary",
}: {
  label: string;
  value: number;
  maxValue: number;
  colorClass?: string;
  textClass?: string;
}) {
  const pct = maxValue > 0 ? Math.min(100, Math.round((value / maxValue) * 100)) : 0;
  return (
    <div className="flex items-center gap-3 py-1.5 text-xs">
      <span className="w-28 truncate font-medium text-text-secondary text-right">{label}</span>
      <div className="flex-1 bg-surface-muted rounded-full h-4 overflow-hidden relative">
        <div
          className={`h-full rounded-full transition-all duration-300 ${colorClass}`}
          style={{ width: `${pct}%` }}
        />
      </div>
      <span className={`w-12 text-right font-bold ${textClass}`}>{value}</span>
    </div>
  );
}

function ProgressDonut({
  pct,
  label,
  color = "var(--accent)",
}: {
  pct: number;
  label: string;
  color?: string;
}) {
  const cleanPct = Math.min(100, Math.max(0, Math.round(pct)));
  const circumference = 2 * Math.PI * 34;
  const strokeDashoffset = circumference - (cleanPct / 100) * circumference;

  return (
    <div className="flex flex-col items-center justify-center p-3">
      <div className="relative w-20 h-20 flex items-center justify-center">
        <svg className="w-full h-full transform -rotate-90" viewBox="0 0 80 80">
          <circle
            cx="40"
            cy="40"
            r="34"
            className="stroke-surface-muted"
            strokeWidth="8"
            fill="transparent"
          />
          <circle
            cx="40"
            cy="40"
            r="34"
            stroke={color}
            strokeWidth="8"
            strokeDasharray={circumference}
            strokeDashoffset={strokeDashoffset}
            strokeLinecap="round"
            fill="transparent"
            className="transition-all duration-500 ease-out"
          />
        </svg>
        <div className="absolute inset-0 flex items-center justify-center font-black text-sm text-text-primary">
          {cleanPct}%
        </div>
      </div>
      <span className="text-xs font-semibold text-text-secondary mt-2 text-center">{label}</span>
    </div>
  );
}

export function WorkforceAnalyticsView() {
  const [activeTab, setActiveTab] = useState<WorkforceAnalyticsTab>("overview");
  const [accountId, setAccountId] = useState<string>("");
  const [dateFrom, setDateFrom] = useState<string>("");
  const [dateTo, setDateTo] = useState<string>("");

  const currentUser = useCurrentUser();
  const hasAllScope =
    currentUser?.groupScope.mode === "all" &&
    currentUser?.accountScope.mode === "all";

  // Accounts list strictly scoped to the user's assigned scope
  const accountsQuery = useQuery({
    queryKey: [
      "plantilla",
      "analytics-accounts",
      currentUser?.accountScope,
      currentUser?.groupScope,
      hasAllScope,
    ],
    queryFn: () => fetchPlantillaScopedAccounts(currentUser),
    enabled: !!currentUser,
  });

  const filter: WfAnalyticsFilter = {
    accountId: accountId || null,
    dateFrom: dateFrom || null,
    dateTo: dateTo || null,
  };

  // Queries for all tabs
  const overviewQuery = useWorkforcePoolOverview(filter);
  const deploymentQuery = useWorkforceDeploymentAnalytics(filter);
  const coverageQuery = useWorkforceCoverageDemandAnalytics(filter);
  const conversionQuery = useWorkforceConversionAnalytics(filter);
  const slotReviewQuery = useWorkforceSlotReviewAnalytics(filter);
  const healthQuery = useWorkforceHealthSummary(filter);
  const executiveQuery = useWorkforceExecutiveSummary(filter);
  const incidentsQuery = usePlantillaImportIncidents(7);

  const handleRefresh = () => {
    switch (activeTab) {
      case "overview":
        overviewQuery.refetch();
        break;
      case "deployment":
        deploymentQuery.refetch();
        break;
      case "coverage":
        coverageQuery.refetch();
        break;
      case "conversion":
        conversionQuery.refetch();
        break;
      case "slots":
        slotReviewQuery.refetch();
        break;
      case "health":
        healthQuery.refetch();
        incidentsQuery.refetch();
        break;
      case "executive":
        executiveQuery.refetch();
        break;
    }
  };

  const handleExport = () => {
    const ts = new Date().toISOString().substring(0, 10);
    if (activeTab === "overview" && overviewQuery.data) {
      const d = overviewQuery.data;
      const rows = [
        { Metric: "Total Pool", Value: d.total },
        { Metric: "Available", Value: d.available },
        { Metric: "Deployed", Value: d.deployed },
        { Metric: "Reserved", Value: d.reserved },
        { Metric: "In Review", Value: d.inReview },
        { Metric: "Inactive", Value: d.inactive },
        { Metric: "Long Term Deployments", Value: d.longTermDeployments },
        { Metric: "Pending Coverage Requests", Value: d.pendingCoverageRequests },
        ...d.byPoolType.map((t) => ({
          Metric: `Pool Type: ${t.poolTypeName}`,
          Value: `Total: ${t.total}, Avail: ${t.available}, Deployed: ${t.deployed}`,
        })),
      ];
      exportToXlsx(rows, `Workforce_Overview_${ts}`);
    } else if (activeTab === "deployment" && deploymentQuery.data) {
      const d = deploymentQuery.data;
      const rows = [
        { Metric: "Active Deployments", Value: d.activeDeploymentCount },
        { Metric: "Multi-Store Relievers", Value: d.multiStoreCount },
        { Metric: "Avg Stores per Reliever", Value: d.avgStoresPerReliever },
        { Metric: "High Load Count", Value: d.highLoadCount },
        { Metric: "Overdue Deployments", Value: d.overdueCount },
        { Metric: "Avg Deployment Days", Value: d.avgDeploymentDays ?? "—" },
        { Metric: "Load Distribution - Low", Value: d.loadDistribution.low },
        { Metric: "Load Distribution - Medium", Value: d.loadDistribution.medium },
        { Metric: "Load Distribution - High", Value: d.loadDistribution.high },
        { Metric: "Load Distribution - Critical", Value: d.loadDistribution.critical },
      ];
      exportToXlsx(rows, `Workforce_Deployment_${ts}`);
    } else if (activeTab === "executive" && executiveQuery.data) {
      const d = executiveQuery.data;
      const rows = [
        { Metric: "Total Pool Employees", Value: d.totalPoolEmployees },
        { Metric: "Utilization %", Value: `${d.utilizationPct}%` },
        { Metric: "Availability %", Value: `${d.availabilityPct}%` },
        { Metric: "Pool Capacity %", Value: `${d.poolCapacityPct}%` },
        { Metric: "Coverage Efficiency %", Value: `${d.coverageEfficiencyPct}%` },
        { Metric: "Active Deployments", Value: d.activeDeployments },
        { Metric: "Pending Requests", Value: d.pendingRequests },
        { Metric: "Escalated Requests", Value: d.escalatedRequests },
        { Metric: "Health Score", Value: `${d.healthScore}/100` },
      ];
      exportToXlsx(rows, `Workforce_Executive_${ts}`);
    } else {
      // General export fallback
      exportToXlsx(
        [{ Tab: activeTab, Account: accountId || "All Accounts", ExportedAt: new Date().toISOString() }],
        `Workforce_Analytics_${activeTab}_${ts}`
      );
    }
  };

  return (
    <div className="space-y-6">
      {/* Top Header & Interactive Filter Bar */}
      <div className="p-5 rounded-xl border border-border-default bg-surface shadow-xs space-y-4">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div>
            <h2 className="text-base font-bold text-text-primary flex items-center gap-2">
              <BarChart3 className="h-5 w-5 text-accent" />
              Workforce Analytics Dashboard
            </h2>
            <p className="text-xs text-text-secondary">
              Live executive KPIs, deployment load distribution, request SLAs, and operational health score
            </p>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleRefresh}
              className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-text-primary bg-surface-muted border border-border-default rounded-lg hover:bg-surface-hover transition cursor-pointer"
            >
              <RefreshCw className="h-3.5 w-3.5" /> Refresh
            </button>
            <button
              type="button"
              onClick={handleExport}
              className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-accent bg-status-accent-bg border border-status-accent-border rounded-lg hover:opacity-90 transition cursor-pointer"
            >
              <Download className="h-3.5 w-3.5" /> Export XLSX
            </button>
          </div>
        </div>

        {/* Filters */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 pt-3 border-t border-border-subtle">
          <div>
            <label className="block text-[11px] font-bold text-text-muted mb-1">Account Scope</label>
            <select
              value={accountId}
              onChange={(e) => setAccountId(e.target.value)}
              className="w-full text-xs rounded-lg border border-border-default py-2 px-3 bg-surface text-text-primary focus:outline-none focus:border-accent"
            >
              <option value="">{hasAllScope ? "All Scoped Accounts (Global)" : "All Assigned Accounts"}</option>
              {(accountsQuery.data ?? []).map((acc) => (
                <option key={acc.id} value={acc.id}>
                  {acc.name}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-[11px] font-bold text-text-muted mb-1">Date From</label>
            <input
              type="date"
              value={dateFrom}
              onChange={(e) => setDateFrom(e.target.value)}
              className="w-full text-xs rounded-lg border border-border-default py-2 px-3 bg-surface text-text-primary focus:outline-none focus:border-accent"
            />
          </div>

          <div>
            <label className="block text-[11px] font-bold text-text-muted mb-1">Date To</label>
            <input
              type="date"
              value={dateTo}
              onChange={(e) => setDateTo(e.target.value)}
              className="w-full text-xs rounded-lg border border-border-default py-2 px-3 bg-surface text-text-primary focus:outline-none focus:border-accent"
            />
          </div>
        </div>
      </div>

      {/* 7-Tab Navigation Bar */}
      <div className="flex border-b border-border-default bg-surface rounded-t-xl px-2 overflow-x-auto">
        {TABS.map((tab) => {
          const Icon = tab.icon;
          const isActive = activeTab === tab.id;
          return (
            <button
              key={tab.id}
              type="button"
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-2 py-3 px-4 text-xs font-bold border-b-2 whitespace-nowrap transition cursor-pointer ${
                isActive
                  ? "border-accent text-accent bg-status-accent-bg"
                  : "border-transparent text-text-secondary hover:text-text-primary hover:bg-surface-muted"
              }`}
            >
              <Icon className="h-4 w-4" />
              {tab.label}
            </button>
          );
        })}
      </div>

      {/* Tab Panels */}
      <div className="rounded-b-xl border border-t-0 border-border-default bg-surface p-6 shadow-xs">
        {/* TAB 1: OVERVIEW */}
        {activeTab === "overview" && (
          <div className="space-y-6">
            {overviewQuery.isLoading ? (
              <DataState state="loading" message="Loading workforce overview metrics..." />
            ) : overviewQuery.data ? (
              <>
                <div className="space-y-2">
                  <h3 className="text-xs font-bold text-text-muted">
                    Workforce Headcount Breakdown
                  </h3>
                  <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
                    <MetricCard label="Total Pool" value={overviewQuery.data.total} variant="default" icon={Users} />
                    <MetricCard label="Available" value={overviewQuery.data.available} variant="positive" icon={CheckCircle2} />
                    <MetricCard label="Deployed" value={overviewQuery.data.deployed} variant="info" icon={UserCheck} />
                    <MetricCard label="Reserved" value={overviewQuery.data.reserved} variant="warning" icon={Clock} />
                    <MetricCard label="In Review" value={overviewQuery.data.inReview} variant="neutral" icon={AlertCircle} />
                    <MetricCard label="Inactive" value={overviewQuery.data.inactive} variant="neutral" icon={XCircle} />
                  </div>
                </div>

                <div className="space-y-2">
                  <h3 className="text-xs font-bold text-text-muted">
                    Operational Indicators
                  </h3>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <MetricCard
                      label="Long-term Deployments (30d+)"
                      value={overviewQuery.data.longTermDeployments}
                      variant="warning"
                      icon={Clock}
                    />
                    <MetricCard
                      label="Pending Coverage Requests"
                      value={overviewQuery.data.pendingCoverageRequests}
                      variant={overviewQuery.data.pendingCoverageRequests > 0 ? "warning" : "positive"}
                      icon={AlertTriangle}
                    />
                  </div>
                </div>

                {overviewQuery.data.byPoolType.length > 0 && (
                  <div className="space-y-4 pt-2">
                    <h3 className="text-xs font-bold text-text-muted">
                      Distribution by Pool Type
                    </h3>
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                      {overviewQuery.data.byPoolType.map((pt) => {
                        const maxVal = Math.max(pt.total, 1);
                        return (
                          <div key={pt.poolTypeId} className="p-4 rounded-xl border border-border-default bg-surface-muted/50 space-y-3">
                            <div className="flex items-center justify-between border-b border-border-subtle pb-2">
                              <span className="font-bold text-sm text-text-primary">{pt.poolTypeName}</span>
                              <span className="text-xs font-mono font-semibold text-accent bg-status-accent-bg border border-status-accent-border px-2 py-0.5 rounded">
                                {pt.total} total
                              </span>
                            </div>
                            <div className="space-y-1">
                              <HorizontalBarRow label="Available" value={pt.available} maxValue={maxVal} colorClass="bg-pct-good-text" textClass="text-pct-good-text" />
                              <HorizontalBarRow label="Deployed" value={pt.deployed} maxValue={maxVal} colorClass="bg-accent" textClass="text-accent" />
                              <HorizontalBarRow label="In Review" value={pt.inReview} maxValue={maxVal} colorClass="bg-pct-warn-text" textClass="text-pct-warn-text" />
                              <HorizontalBarRow label="Inactive" value={pt.inactive} maxValue={maxVal} colorClass="bg-text-muted" textClass="text-text-secondary" />
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                )}
              </>
            ) : null}
          </div>
        )}

        {/* TAB 2: DEPLOYMENT */}
        {activeTab === "deployment" && (
          <div className="space-y-6">
            {deploymentQuery.isLoading ? (
              <DataState state="loading" message="Loading deployment load analytics..." />
            ) : deploymentQuery.data ? (
              <>
                <div className="space-y-2">
                  <h3 className="text-xs font-bold text-text-muted">
                    Deployment KPIs
                  </h3>
                  <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
                    <MetricCard label="Active Deployments" value={deploymentQuery.data.activeDeploymentCount} variant="info" icon={MapPin} />
                    <MetricCard label="Multi-Store Staff" value={deploymentQuery.data.multiStoreCount} variant="default" icon={Users} />
                    <MetricCard label="High/Critical Load" value={deploymentQuery.data.highLoadCount} variant="warning" icon={AlertTriangle} />
                    <MetricCard label="Overdue (Past End)" value={deploymentQuery.data.overdueCount} variant="danger" icon={Clock} />
                    <MetricCard label="Avg Stores / Staff" value={deploymentQuery.data.avgStoresPerReliever.toFixed(1)} variant="default" icon={TrendingUp} />
                    <MetricCard
                      label="Avg Days Active"
                      value={deploymentQuery.data.avgDeploymentDays != null ? deploymentQuery.data.avgDeploymentDays.toFixed(1) : "—"}
                      variant="default"
                      icon={Calendar}
                    />
                  </div>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6 pt-2">
                  {/* Load Distribution */}
                  <div className="p-5 rounded-xl border border-border-default bg-surface space-y-3">
                    <h4 className="text-xs font-bold text-text-secondary">
                      Deployment Load Distribution
                    </h4>
                    {(() => {
                      const ld = deploymentQuery.data.loadDistribution;
                      const maxLd = Math.max(ld.low + ld.medium + ld.high + ld.critical, 1);
                      return (
                        <div className="space-y-1.5 pt-2">
                          <HorizontalBarRow label="Low (1 Store)" value={ld.low} maxValue={maxLd} colorClass="bg-pct-good-text" textClass="text-pct-good-text" />
                          <HorizontalBarRow label="Medium (2 Stores)" value={ld.medium} maxValue={maxLd} colorClass="bg-pct-warn-text" textClass="text-pct-warn-text" />
                          <HorizontalBarRow label="High (3 Stores)" value={ld.high} maxValue={maxLd} colorClass="bg-pct-warn-text" textClass="text-pct-warn-text" />
                          <HorizontalBarRow label="Critical (4+ Stores)" value={ld.critical} maxValue={maxLd} colorClass="bg-danger-text" textClass="text-danger-text" />
                        </div>
                      );
                    })()}
                  </div>

                  {/* Aging Buckets */}
                  <div className="p-5 rounded-xl border border-border-default bg-surface space-y-3">
                    <h4 className="text-xs font-bold text-text-secondary">
                      Deployment Duration (Aging Buckets)
                    </h4>
                    {(() => {
                      const ab = deploymentQuery.data.agingBuckets;
                      const maxAb = Math.max(ab.days0to7 + ab.days8to14 + ab.days15to30 + ab.days30plus, 1);
                      return (
                        <div className="space-y-1.5 pt-2">
                          <HorizontalBarRow label="0 – 7 days" value={ab.days0to7} maxValue={maxAb} colorClass="bg-pct-good-text" textClass="text-pct-good-text" />
                          <HorizontalBarRow label="8 – 14 days" value={ab.days8to14} maxValue={maxAb} colorClass="bg-accent" textClass="text-accent" />
                          <HorizontalBarRow label="15 – 30 days" value={ab.days15to30} maxValue={maxAb} colorClass="bg-pct-warn-text" textClass="text-pct-warn-text" />
                          <HorizontalBarRow label="30+ days (Prolonged)" value={ab.days30plus} maxValue={maxAb} colorClass="bg-danger-text" textClass="text-danger-text" />
                        </div>
                      );
                    })()}
                  </div>
                </div>
              </>
            ) : null}
          </div>
        )}

        {/* TAB 3: COVERAGE DEMAND */}
        {activeTab === "coverage" && (
          <div className="space-y-6">
            {coverageQuery.isLoading ? (
              <DataState state="loading" message="Loading coverage demand analytics..." />
            ) : coverageQuery.data ? (
              <>
                <div className="space-y-2">
                  <h3 className="text-xs font-bold text-text-muted">
                    Request Pipeline & SLAs
                  </h3>
                  <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
                    <MetricCard label="Total Requests" value={coverageQuery.data.totalRequests} variant="default" icon={UserCheck} />
                    <MetricCard label="Pending Approval" value={coverageQuery.data.pending} variant="warning" icon={Clock} />
                    <MetricCard label="Approved" value={coverageQuery.data.approved} variant="positive" icon={CheckCircle2} />
                    <MetricCard label="Rejected" value={coverageQuery.data.rejected} variant="danger" icon={XCircle} />
                    <MetricCard label="Escalated (>48h)" value={coverageQuery.data.escalatedCount} variant="warning" icon={AlertTriangle} />
                    <MetricCard label="Critical SLA (>72h)" value={coverageQuery.data.criticalSlaCount} variant="danger" icon={ShieldAlert} />
                  </div>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6 pt-2">
                  {/* Rejection Rate & Age */}
                  <div className="p-5 rounded-xl border border-border-default bg-surface space-y-4">
                    <h4 className="text-xs font-bold text-text-secondary">
                      Approval & Rejection Performance
                    </h4>
                    <div className="grid grid-cols-2 gap-4">
                      <div className="p-4 bg-surface-muted rounded-xl text-center space-y-1">
                        <span className="text-xs text-text-secondary block">Rejection Rate</span>
                        <span className="text-2xl font-black text-danger-text">
                          {coverageQuery.data.rejectionRatePct.toFixed(1)}%
                        </span>
                      </div>
                      <div className="p-4 bg-surface-muted rounded-xl text-center space-y-1">
                        <span className="text-xs text-text-secondary block">Avg Request Age</span>
                        <span className="text-2xl font-black text-pct-warn-text">
                          {coverageQuery.data.avgRequestAgeDays != null ? `${coverageQuery.data.avgRequestAgeDays.toFixed(1)}d` : "—"}
                        </span>
                      </div>
                    </div>
                  </div>

                  {/* Top Requesting Pools */}
                  <div className="p-5 rounded-xl border border-border-default bg-surface space-y-3">
                    <h4 className="text-xs font-bold text-text-secondary">
                      Top Requesting Workforce Pools
                    </h4>
                    {coverageQuery.data.topRequestingPools.length === 0 ? (
                      <p className="text-xs text-text-muted py-4 text-center">No pool requests recorded.</p>
                    ) : (
                      <div className="space-y-1.5 pt-2">
                        {(() => {
                          const maxPool = Math.max(
                            ...coverageQuery.data.topRequestingPools.map((p) => p.count),
                            1
                          );
                          return coverageQuery.data.topRequestingPools.map((p) => (
                            <HorizontalBarRow
                              key={p.poolType}
                              label={p.poolType}
                              value={p.count}
                              maxValue={maxPool}
                              colorClass="bg-accent"
                              textClass="text-accent"
                            />
                          ));
                        })()}
                      </div>
                    )}
                  </div>
                </div>
              </>
            ) : null}
          </div>
        )}

        {/* TAB 4: CONVERSION */}
        {activeTab === "conversion" && (
          <div className="space-y-6">
            {conversionQuery.isLoading ? (
              <DataState state="loading" message="Loading conversion funnel..." />
            ) : conversionQuery.data ? (
              <>
                <div className="space-y-2">
                  <h3 className="text-xs font-bold text-text-muted">
                    Pool-to-Plantilla Conversion Funnel
                  </h3>
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                    <MetricCard label="Total Submissions" value={conversionQuery.data.total} variant="default" icon={ArrowRightLeft} />
                    <MetricCard label="Pending Review" value={conversionQuery.data.pending} variant="warning" icon={Clock} />
                    <MetricCard label="Approved Conversions" value={conversionQuery.data.approved} variant="positive" icon={CheckCircle2} />
                    <MetricCard label="Rejected" value={conversionQuery.data.rejected} variant="danger" icon={XCircle} />
                  </div>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-3 gap-6 pt-2">
                  <div className="p-5 rounded-xl border border-border-default bg-surface flex flex-col items-center justify-center">
                    <ProgressDonut pct={conversionQuery.data.approvalRatePct} label="Approval Rate" color="var(--pct-good-text)" />
                  </div>
                  <div className="p-5 rounded-xl border border-border-default bg-surface flex flex-col items-center justify-center">
                    <ProgressDonut pct={conversionQuery.data.rejectionRatePct} label="Rejection Rate" color="var(--danger-text)" />
                  </div>
                  <div className="p-5 rounded-xl border border-border-default bg-surface flex flex-col items-center justify-center space-y-2 text-center">
                    <span className="text-xs font-bold text-text-muted tracking-wider">Decision Speed</span>
                    <span className="text-3xl font-black text-accent">
                      {conversionQuery.data.avgDaysToDecision != null ? `${conversionQuery.data.avgDaysToDecision.toFixed(1)} days` : "—"}
                    </span>
                    <span className="text-xs text-text-secondary">Average time to Data Team sign-off</span>
                  </div>
                </div>
              </>
            ) : null}
          </div>
        )}

        {/* TAB 5: SLOTS */}
        {activeTab === "slots" && (
          <div className="space-y-6">
            {slotReviewQuery.isLoading ? (
              <DataState state="loading" message="Loading slot review queue analytics..." />
            ) : slotReviewQuery.data ? (
              <>
                <div className="space-y-2">
                  <h3 className="text-xs font-bold text-text-muted">
                    Slot Review Pipeline
                  </h3>
                  <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
                    <MetricCard label="Total Reviews" value={slotReviewQuery.data.total} variant="default" icon={Layers} />
                    <MetricCard label="Pending Decision" value={slotReviewQuery.data.pending} variant="warning" icon={Clock} />
                    <MetricCard label="Resolved" value={slotReviewQuery.data.resolved} variant="positive" icon={CheckCircle2} />
                    <MetricCard label="Reopened for Hiring" value={slotReviewQuery.data.reopened} variant="info" icon={Sparkles} />
                    <MetricCard label="Stale (>30d)" value={slotReviewQuery.data.staleCount} variant="danger" icon={AlertTriangle} />
                    <MetricCard
                      label="Avg Resolution"
                      value={slotReviewQuery.data.avgResolutionDays != null ? `${slotReviewQuery.data.avgResolutionDays.toFixed(1)}d` : "—"}
                      variant="default"
                      icon={Calendar}
                    />
                  </div>
                </div>

                <div className="p-5 rounded-xl border border-border-default bg-surface space-y-3">
                  <h4 className="text-xs font-bold text-text-secondary">
                    Review Status Volume Breakdown
                  </h4>
                  {(() => {
                    const sr = slotReviewQuery.data;
                    const maxSr = Math.max(sr.total, 1);
                    return (
                      <div className="space-y-2 pt-2">
                        <HorizontalBarRow label="Pending" value={sr.pending} maxValue={maxSr} colorClass="bg-pct-warn-text" textClass="text-pct-warn-text" />
                        <HorizontalBarRow label="Resolved" value={sr.resolved} maxValue={maxSr} colorClass="bg-pct-good-text" textClass="text-pct-good-text" />
                        <HorizontalBarRow label="Reopened" value={sr.reopened} maxValue={maxSr} colorClass="bg-accent" textClass="text-accent" />
                        <HorizontalBarRow label="Stale (30d+)" value={sr.staleCount} maxValue={maxSr} colorClass="bg-danger-text" textClass="text-danger-text" />
                      </div>
                    );
                  })()}
                </div>
              </>
            ) : null}
          </div>
        )}

        {/* TAB 6: HEALTH */}
        {activeTab === "health" && (
          <div className="space-y-6">
            {healthQuery.isLoading ? (
              <DataState state="loading" message="Loading workforce operational health score..." />
            ) : healthQuery.data ? (
              <>
                {/* Health Meter Banner */}
                <div className="p-6 rounded-xl border border-border-default bg-surface-muted/30 flex flex-col sm:flex-row items-center gap-6">
                  <ProgressDonut
                    pct={healthQuery.data.healthScore}
                    label="Health Score"
                    color={
                      healthQuery.data.healthScore >= 80
                        ? "var(--pct-good-text)"
                        : healthQuery.data.healthScore >= 60
                        ? "var(--pct-warn-text)"
                        : "var(--danger-text)"
                    }
                  />
                  <div className="space-y-1 text-center sm:text-left">
                    <span
                      className={`inline-block text-xs font-bold  px-2.5 py-0.5 rounded-full border ${
                        healthQuery.data.healthScore >= 80
                          ? "bg-pct-good-bg text-pct-good-text border-pct-good-border"
                          : healthQuery.data.healthScore >= 60
                          ? "bg-pct-warn-bg text-pct-warn-text border-pct-warn-border"
                          : "bg-danger-bg text-danger-text border-danger-border"
                      }`}
                    >
                      {healthQuery.data.healthScore >= 80
                        ? "Optimal Operational Health"
                        : healthQuery.data.healthScore >= 60
                        ? "Moderate Operational Drift"
                        : "Critical Action Required"}
                    </span>
                    <h3 className="text-base font-bold text-text-primary">
                      Workforce Health Score: {healthQuery.data.healthScore}/100
                    </h3>
                    <p className="text-xs text-text-secondary max-w-lg">
                      Calculated from overdue deployments, escalated coverage requests, stale reviews, and
                      critical-load multi-store strain across {healthQuery.data.totalPoolEmployees} pooled staff.
                    </p>
                  </div>
                </div>

                {/* Warning Indicators Grid */}
                <div className="space-y-2">
                  <h4 className="text-xs font-bold text-text-muted">
                    Warning & Risk Indicators
                  </h4>
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                    <MetricCard label="Overdue Deployments" value={healthQuery.data.overdueDeployments} variant="danger" icon={Clock} />
                    <MetricCard label="Long-term Deployments" value={healthQuery.data.longTermAssignments} variant="warning" icon={Calendar} />
                    <MetricCard label="High Load Staff" value={healthQuery.data.highLoadRelievers} variant="warning" icon={AlertCircle} />
                    <MetricCard label="Critical Load Staff" value={healthQuery.data.criticalLoadRelievers} variant="danger" icon={AlertTriangle} />
                    <MetricCard label="Escalated Requests" value={healthQuery.data.escalatedRequests} variant="warning" icon={ShieldAlert} />
                    <MetricCard label="Stale Reviews (30d+)" value={healthQuery.data.staleSlotReviews} variant="danger" icon={Layers} />
                    <MetricCard label="Pending Conversions" value={healthQuery.data.pendingConversions} variant="info" icon={ArrowRightLeft} />
                    <MetricCard label="Total Pool Personnel" value={healthQuery.data.totalPoolEmployees} variant="default" icon={Users} />
                  </div>
                </div>

                {/* Recent Import Incidents Feed */}
                <div className="space-y-3 pt-2">
                  <div className="flex items-center justify-between">
                    <h4 className="text-xs font-bold text-text-muted">
                      Recent Plantilla Import Incidents (Last 7 Days)
                    </h4>
                    {incidentsQuery.data && (
                      <div className="flex items-center gap-2 text-xs">
                        {incidentsQuery.data.critical > 0 && (
                          <span className="text-[11px] font-bold text-danger-text bg-danger-bg border border-danger-border px-2 py-0.5 rounded">
                            {incidentsQuery.data.critical} Critical
                          </span>
                        )}
                        {incidentsQuery.data.warning > 0 && (
                          <span className="text-[11px] font-bold text-pct-warn-text bg-pct-warn-bg border border-pct-warn-border px-2 py-0.5 rounded">
                            {incidentsQuery.data.warning} Warnings
                          </span>
                        )}
                        <span className="text-[11px] font-medium text-text-secondary">
                          {incidentsQuery.data.unresolved} Unresolved
                        </span>
                      </div>
                    )}
                  </div>

                  {incidentsQuery.isLoading ? (
                    <DataState state="loading" message="Loading incident feed..." />
                  ) : !incidentsQuery.data || incidentsQuery.data.incidents.length === 0 ? (
                    <div className="p-4 rounded-xl border border-dashed border-border-default text-center text-xs text-text-muted bg-surface-muted/30">
                      No import incidents reported in the last 7 days.
                    </div>
                  ) : (
                    <div className="divide-y divide-border-subtle border border-border-default rounded-xl overflow-hidden bg-surface text-sm">
                      {incidentsQuery.data.incidents.map((inc) => (
                        <div key={inc.id} className="p-3.5 space-y-1">
                          <div className="flex items-center justify-between">
                            <span
                              className={`font-bold ${
                                inc.severity === "critical"
                                  ? "text-danger-text"
                                  : inc.severity === "warning"
                                  ? "text-pct-warn-text"
                                  : "text-accent"
                              }`}
                            >
                              [{inc.incidentType}] {inc.message}
                            </span>
                            <span className="text-[11px] text-text-muted font-mono">
                              {inc.createdAt ? new Date(inc.createdAt).toLocaleString("en-PH") : "—"}
                            </span>
                          </div>
                          {inc.isResolved && (
                            <span className="inline-block text-[10px] font-semibold text-pct-good-text bg-pct-good-bg border border-pct-good-border px-2 py-0.5 rounded">
                              Resolved
                            </span>
                          )}
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </>
            ) : null}
          </div>
        )}

        {/* TAB 7: EXECUTIVE */}
        {activeTab === "executive" && (
          <div className="space-y-6">
            {executiveQuery.isLoading ? (
              <DataState state="loading" message="Loading executive workforce summary..." />
            ) : executiveQuery.data ? (
              <>
                <div className="space-y-2">
                  <h3 className="text-xs font-bold text-text-muted">
                    Utilization & Capacity Metrics
                  </h3>
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
                    <div className="p-4 rounded-xl border border-border-default bg-surface flex flex-col items-center">
                      <ProgressDonut pct={executiveQuery.data.utilizationPct} label="Pool Utilization" color="var(--accent)" />
                    </div>
                    <div className="p-4 rounded-xl border border-border-default bg-surface flex flex-col items-center">
                      <ProgressDonut pct={executiveQuery.data.availabilityPct} label="Staff Availability" color="var(--pct-good-text)" />
                    </div>
                    <div className="p-4 rounded-xl border border-border-default bg-surface flex flex-col items-center">
                      <ProgressDonut pct={executiveQuery.data.poolCapacityPct} label="Pool Capacity" color="var(--accent)" />
                    </div>
                    <div className="p-4 rounded-xl border border-border-default bg-surface flex flex-col items-center">
                      <ProgressDonut pct={executiveQuery.data.coverageEfficiencyPct} label="Coverage Efficiency" color="var(--accent)" />
                    </div>
                  </div>
                </div>

                <div className="space-y-2">
                  <h3 className="text-xs font-bold text-text-muted">
                    Executive Operational KPIs
                  </h3>
                  <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
                    <MetricCard label="Total Pool Personnel" value={executiveQuery.data.totalPoolEmployees} variant="default" icon={Users} />
                    <MetricCard label="Active Deployments" value={executiveQuery.data.activeDeployments} variant="info" icon={UserCheck} />
                    <MetricCard label="Pending Requests" value={executiveQuery.data.pendingRequests} variant="warning" icon={Clock} />
                    <MetricCard label="Escalated Requests" value={executiveQuery.data.escalatedRequests} variant="danger" icon={AlertTriangle} />
                    <MetricCard label="Pending Conversions" value={executiveQuery.data.pendingConversions} variant="default" icon={ArrowRightLeft} />
                    <MetricCard label="Health Score" value={`${executiveQuery.data.healthScore}/100`} variant="positive" icon={Activity} />
                  </div>
                </div>
              </>
            ) : null}
          </div>
        )}
      </div>
    </div>
  );
}
