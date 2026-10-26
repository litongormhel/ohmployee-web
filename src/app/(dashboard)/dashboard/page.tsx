"use client";

import { useState, useMemo } from "react";
import Link from "next/link";
import { useQuery, keepPreviousData } from "@tanstack/react-query";
import {
  Briefcase,
  Users,
  CheckSquare,
  ShieldCheck,
  CloudUpload,
  Radio,
  FileCheck2,
  ArrowRight,
  ExternalLink,
  CheckCircle2,
} from "lucide-react";

import { useCurrentUser } from "@/lib/auth";
import {
  getDashboardMetrics,
  getDashboardOperationalAnalytics,
  useDashboardSlaBreaches,
  useDashboardUnderstaffedStores,
} from "@/lib/queries/dashboard";
import { useRequestCategoryCounts } from "@/lib/queries/requests";
import { useCencomGroupKpi } from "@/lib/queries/cencom";
import { MikaSyncModal } from "@/components/dashboard/MikaSyncModal";
import { KpiCard } from "@/components/shared/KpiCard";
import { AnimatedNumber } from "@/components/shared/AnimatedNumber";
import { PercentageBar } from "@/components/shared/PercentageBar";
import { SegmentedTabs, type TabItem } from "@/components/shared/SegmentedTabs";
import { ScopeDropdown, type ScopeOption } from "@/components/shared/ScopeDropdown";
import { NeutralChip } from "@/components/shared/NeutralChip";
import { Toast } from "@/components/shared/Toast";
import { evaluatePercentage } from "@/lib/utils/thresholds";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function pct(value: number | null): string {
  if (value === null) return "—";
  return `${(value * 100).toFixed(1)}%`;
}

type MatrixTabKey = "matrix" | "breaches" | "stores";

interface GroupWorkforceRow {
  groupName: string;
  plantilla: number;
  pipeline: number;
  vacancy: number;
  understaffedCount: number;
  fillRatePct: number | null;
  slaStatus: "Compliant" | "At Risk" | "Critical" | "Standby";
  isActiveGroup: boolean;
}

// ---------------------------------------------------------------------------
// Page Component
// ---------------------------------------------------------------------------

export default function DashboardPage() {
  const currentUser = useCurrentUser();

  // Role Gate: Super Admin vs Head Admin
  const isSuperAdmin = useMemo(() => {
    if (!currentUser) return true; // Default during initial load
    const key = (currentUser.roleKey || "").toLowerCase();
    const name = (currentUser.roleName || "").toLowerCase();
    return key === "super_admin" || name.includes("super");
  }, [currentUser]);

  // Selected Scope Filter
  const [selectedGroupScope, setSelectedGroupScope] = useState<string>("all");
  const [activeMatrixTab, setActiveMatrixTab] = useState<MatrixTabKey>("matrix");
  const [matrixFilterActiveOnly, setMatrixFilterActiveOnly] = useState<boolean>(true);
  const [isMikaSyncModalOpen, setIsMikaSyncModalOpen] = useState<boolean>(false);
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  const showToast = (msg: string) => {
    setToastMessage(msg);
  };

  // -------------------------------------------------------------------------
  // Live Queries
  // -------------------------------------------------------------------------

  const scopeParams = {
    groupId: selectedGroupScope === "all" ? null : selectedGroupScope,
  };

  const metricsQuery = useQuery({
    queryKey: ["dashboard", "metrics", selectedGroupScope === "all" ? null : selectedGroupScope],
    queryFn: () => getDashboardMetrics(scopeParams),
    placeholderData: keepPreviousData,
  });

  const analyticsQuery = useQuery({
    queryKey: [
      "dashboard",
      "operational-analytics",
      selectedGroupScope === "all" ? null : selectedGroupScope,
    ],
    queryFn: () => getDashboardOperationalAnalytics(scopeParams),
    placeholderData: keepPreviousData,
  });

  // Live Group KPI from CENCOM view
  const { data: groupKpiData, isLoading: isGroupKpiLoading } = useCencomGroupKpi();

  // Reconciled Approvals Count from useRequestCategoryCounts
  const { data: requestCounts, isLoading: isRequestCountsLoading } = useRequestCategoryCounts();

  // Live SLA Breaches query
  const { data: slaBreachesData, isLoading: isSlaBreachesLoading } = useDashboardSlaBreaches();

  // Live Understaffed Stores query
  const { data: understaffedStoresData, isLoading: isUnderstaffedStoresLoading } =
    useDashboardUnderstaffedStores();

  // -------------------------------------------------------------------------
  // Derived Live Metrics
  // -------------------------------------------------------------------------

  const metrics = metricsQuery.data;
  const analytics = analyticsQuery.data;

  // Live KPI Values
  const activeSlaBreaches = metrics?.activeSlaBreaches ?? 0;
  const understaffedStores = metrics?.understaffedStores ?? 0;
  const totalOpenVacancies = metrics?.totalOpenVacancies ?? 0;
  const unassignedVacancies = metrics?.unassignedVacancies ?? 0;
  const assignedVacancies = metrics?.assignedVacancies ?? 0;
  const totalHrEmplocPending = metrics?.totalHrEmplocPending ?? 0;
  const totalActivePlantilla = metrics?.totalActivePlantilla ?? 0;
  const ghostEmployeeCount = metrics?.ghostEmployeeCount ?? 0;

  // Operational Analytics Values
  const pipelineTotal = analytics?.pipelineTotal ?? 0;
  const hiresThisMonth = analytics?.hiresThisMonth ?? 0;
  const separationsThisMonth = analytics?.separationsThisMonth ?? 0;
  const avgFillRateNum = analytics?.avgFillRate ?? 0;
  const avgFillRateFormatted = pct(avgFillRateNum);
  const avgFillRatePct = avgFillRateNum * 100;
  const fillRateStatus = evaluatePercentage("fill_rate", avgFillRatePct);

  // Dynamic Scoped Demand Denominator: Actual + HR Pipeline + Vacancy
  const totalScopedDemand = totalActivePlantilla + totalHrEmplocPending + totalOpenVacancies;
  const plantillaTarget = totalActivePlantilla + totalOpenVacancies;

  const activePlantillaWidthPct =
    totalScopedDemand > 0 ? ((totalActivePlantilla / totalScopedDemand) * 100).toFixed(1) : "0.0";
  const hrEmplocWidthPct =
    totalScopedDemand > 0 ? ((totalHrEmplocPending / totalScopedDemand) * 100).toFixed(1) : "0.0";
  const vacanciesWidthPct =
    totalScopedDemand > 0 ? ((totalOpenVacancies / totalScopedDemand) * 100).toFixed(1) : "0.0";

  // Reconciled Approvals Count: 100% live derived from categories, no mock fallback
  const totalReconciledApprovals = useMemo(() => {
    if (!requestCounts) return metrics?.pendingApprovals ?? 0;
    return Object.values(requestCounts).reduce((acc, c) => acc + c, 0);
  }, [requestCounts, metrics?.pendingApprovals]);

  // Live Category-level Approvals Breakdown: 100% dynamic, no fake fallback rows
  const liveApprovalItems = useMemo(() => {
    if (!requestCounts) return [];

    const items: Array<{ title: string; sub: string; count: number; href: string }> = [];

    const movements =
      (requestCounts.applicant_movements || 0) + (requestCounts.plantilla_approvals || 0);
    if (movements > 0) {
      items.push({
        title: "Plantilla Deployments & Movements",
        sub: "Cross-store candidate deployments & transfers awaiting sign-off",
        count: movements,
        href: "/approvals?tab=plantilla_approvals",
      });
    }

    const hrEmploc = requestCounts.hr_emploc_deletions || 0;
    if (hrEmploc > 0) {
      items.push({
        title: "HR Emploc Compliance & Deletions",
        sub: "Pending onboarding exceptions & deletion reviews",
        count: hrEmploc,
        href: "/approvals?tab=hr_emploc_deletions",
      });
    }

    const requisitions = (requestCounts.headcount || 0) + (requestCounts.new_stores || 0);
    if (requisitions > 0) {
      items.push({
        title: "Store Headcount & Requisitions",
        sub: "New store & plantilla quota allocation requests",
        count: requisitions,
        href: "/approvals?tab=headcount",
      });
    }

    const coverage = (requestCounts.coverage || 0) + (requestCounts.relievers || 0);
    if (coverage > 0) {
      items.push({
        title: "Coverage & Reliever Approvals",
        sub: "Roving coverage and reliever pool assignments",
        count: coverage,
        href: "/approvals?tab=coverage",
      });
    }

    const closures = requestCounts.vacancy_closures || 0;
    if (closures > 0) {
      items.push({
        title: "Vacancy Closures",
        sub: "Formal cancellation and fill closure authorizations",
        count: closures,
        href: "/approvals?tab=vacancy_closures",
      });
    }

    return items;
  }, [requestCounts]);

  // Live Group Workforce Matrix mapping: strictly from v_cencom_group_allocation_kpi
  const liveGroupRows: GroupWorkforceRow[] = useMemo(() => {
    if (!groupKpiData || groupKpiData.length === 0) return [];

    return groupKpiData.map((g) => {
      const fillPct = g.required > 0 ? Math.round((g.actual / g.required) * 1000) / 10 : null;
      const status: "Compliant" | "At Risk" | "Critical" | "Standby" =
        g.required === 0 && g.actual === 0 && g.vacant === 0
          ? "Standby"
          : g.vacant > 3
          ? "Critical"
          : g.vacant > 0
          ? "At Risk"
          : "Compliant";

      return {
        groupName: g.groupName || g.groupCode || "Group",
        plantilla: g.actual,
        pipeline: g.pipeline,
        vacancy: g.vacant,
        understaffedCount: g.vacant > 0 ? 1 : 0,
        fillRatePct: fillPct,
        slaStatus: status,
        isActiveGroup: g.required > 0 || g.actual > 0 || g.vacant > 0,
      };
    });
  }, [groupKpiData]);

  // Scope Dropdown Options
  const scopeOptions: ScopeOption[] = useMemo(() => {
    return [
      {
        value: "all",
        label: "All Retail Groups",
        badge: `${liveGroupRows.length}`,
      },
      ...liveGroupRows.map((g) => ({
        value: g.groupName,
        label: g.groupName,
        badge: g.fillRatePct !== null ? `${g.fillRatePct.toFixed(1)}% MFR` : "Standby",
      })),
    ];
  }, [liveGroupRows]);

  // Filtered group matrix rows
  const displayedGroupRows = useMemo(() => {
    if (matrixFilterActiveOnly) {
      return liveGroupRows.filter((r) => r.isActiveGroup);
    }
    return liveGroupRows;
  }, [liveGroupRows, matrixFilterActiveOnly]);

  // Dynamically compute lowest MFR group
  const worstMfrGroupName = useMemo(() => {
    const active = liveGroupRows.filter((r) => r.fillRatePct !== null && r.isActiveGroup);
    if (active.length === 0) return "N/A";
    const sorted = [...active].sort((a, b) => (a.fillRatePct ?? 0) - (b.fillRatePct ?? 0));
    return sorted[0]?.groupName ?? "N/A";
  }, [liveGroupRows]);

  // Matrix Tabs Configuration
  const matrixTabs: TabItem<MatrixTabKey>[] = useMemo(
    () => [
      {
        key: "matrix",
        label: "Group Workforce Matrix",
      },
      {
        key: "breaches",
        label: "Active SLA Breaches",
        count: activeSlaBreaches,
      },
      {
        key: "stores",
        label: "Under-Staffed Stores",
        count: understaffedStores,
      },
    ],
    [activeSlaBreaches, understaffedStores]
  );

  return (
    <div className="flex flex-col gap-6 text-text-primary pb-8 sm:pb-12">
      {/* Toast Notification */}
      {toastMessage && (
        <Toast
          isOpen={true}
          message={toastMessage}
          onClose={() => setToastMessage(null)}
        />
      )}

      {/* =================================================================== */}
      {/* 1. TOP COMMAND HEADER BAR                                           */}
      {/* =================================================================== */}
      <header className="flex flex-wrap items-center justify-between gap-4 rounded-2xl border border-border-default bg-surface-card p-4 sm:p-5 shadow-2xs">
        <div>
          <div className="flex items-center gap-2 text-xs font-semibold text-text-muted">
            <span>Admin panel</span>
            <span>/</span>
            <span className="font-semibold text-brand-500">Dashboard Overview</span>
            <NeutralChip label="Live RPC Telemetry Connected" />
          </div>
          <div className="mt-1 flex items-baseline gap-3">
            <h1 className="text-2xl sm:text-3xl font-semibold tracking-tight text-text-primary">
              Web Admin Command Center
            </h1>
            <span className="hidden text-xs text-text-muted sm:inline">
              Cross-module operational overview for the OHMployee admin workspace
            </span>
          </div>
        </div>

        {/* Right Header Action Toolbar */}
        <div className="flex flex-wrap items-center gap-2.5">
          {/* Group Scope Selector */}
          <ScopeDropdown
            label="Scope:"
            value={selectedGroupScope}
            options={scopeOptions}
            onChange={(val) => {
              setSelectedGroupScope(val);
              showToast(
                `Dashboard scoped to: ${val === "all" ? "All Retail Groups" : val}`
              );
            }}
          />

          {/* Quick link to CENCOM Triage when SLA breaches > 0 */}
          {activeSlaBreaches > 0 && (
            <Link
              href="/cencom"
              className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-muted px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs transition-colors hover:bg-surface-hover"
            >
              <Radio className="h-3.5 w-3.5 text-text-muted" />
              <span>CENCOM Triage ({activeSlaBreaches})</span>
            </Link>
          )}

          {/* STRICT BUTTON NAMING: "Sync MIKA" (Visible to Super Admin only) */}
          {isSuperAdmin && (
            <button
              type="button"
              onClick={() => setIsMikaSyncModalOpen(true)}
              className="inline-flex items-center gap-1.5 rounded-lg bg-brand-500 px-3.5 py-1.5 text-xs font-semibold text-white shadow-2xs transition-colors hover:bg-brand-600 cursor-pointer"
            >
              <CloudUpload className="h-3.5 w-3.5" />
              <span>Sync MIKA</span>
            </button>
          )}
        </div>
      </header>

      {/* =================================================================== */}
      {/* 2. TOP 5 EXECUTIVE KPI RIBBON (Interactive 5-Column Grid)           */}
      {/* =================================================================== */}
      <section
        aria-label="Executive KPI Ribbon"
        className="grid grid-cols-1 gap-3.5 sm:grid-cols-2 lg:grid-cols-5"
      >
        {/* KPI 1: ACTIVE SLA BREACHES */}
        <KpiCard
          title="Active SLA Breaches"
          value={activeSlaBreaches}
          subtitle="Pending movements or vacancy SLA breaches"
          badge={<NeutralChip label="Action Required" />}
          onClick={() => setActiveMatrixTab("breaches")}
          className={
            activeMatrixTab === "breaches"
              ? "border-brand-500 bg-surface-muted/50"
              : undefined
          }
          footer={
            <div className="flex items-center justify-between text-xs font-medium text-text-secondary">
              <span>{activeSlaBreaches} Logged Inactivity Breaches</span>
              <span className="font-sans tabular-nums text-text-muted">
                Aging: {slaBreachesData?.[0]?.aging ?? "—"}
              </span>
            </div>
          }
        />

        {/* KPI 2: UNDER-STAFFED STORES */}
        <KpiCard
          title="Under-Staffed Stores"
          value={understaffedStores}
          subtitle="Stores below budgeted plantilla target"
          badge={<NeutralChip label="At Risk" />}
          onClick={() => setActiveMatrixTab("stores")}
          className={
            activeMatrixTab === "stores"
              ? "border-brand-500 bg-surface-muted/50"
              : undefined
          }
          footer={
            <div className="flex items-center justify-between text-xs text-text-secondary">
              <span>
                Lowest MFR: <strong className="text-text-primary">{worstMfrGroupName}</strong>
              </span>
              <span className="font-semibold text-text-secondary">
                {understaffedStores > 0 ? "Staffing Deficit Alert" : "All Stores Staffed"}
              </span>
            </div>
          }
        />

        {/* KPI 3: OPEN VACANCIES */}
        <KpiCard
          title="Open Vacancies"
          value={totalOpenVacancies}
          subtitle="Active open vacancy slots"
          icon={Briefcase}
          badge={<NeutralChip label={`${unassignedVacancies} Unassigned`} />}
          onClick={() => setActiveMatrixTab("matrix")}
          className={
            activeMatrixTab === "matrix"
              ? "border-brand-500 bg-surface-muted/50"
              : undefined
          }
          footer={
            <div className="flex items-center justify-between text-xs text-text-secondary">
              <span>{assignedVacancies} Assigned to HRCO</span>
              <span className="font-semibold text-brand-500">{avgFillRateFormatted} Fill</span>
            </div>
          }
        />

        {/* KPI 4: HR EMPLOC PENDING */}
        <KpiCard
          title="HR Emploc Pending"
          value={totalHrEmplocPending}
          subtitle="Onboarding compliance items pending"
          icon={FileCheck2}
          badge={<NeutralChip label="In Motion" />}
          onClick={() => setActiveMatrixTab("matrix")}
          footer={
            <div className="flex items-center justify-between text-xs text-text-secondary">
              <span>Onboarding Pipeline</span>
              <span className="font-semibold text-text-secondary">Pending Review</span>
            </div>
          }
        />

        {/* KPI 5: ACTIVE PLANTILLA */}
        <KpiCard
          title="Active Plantilla"
          value={totalActivePlantilla}
          subtitle="Total active deployed employees"
          icon={Users}
          badge={<NeutralChip label={`of ${plantillaTarget} Target`} />}
          onClick={() => setActiveMatrixTab("matrix")}
          footer={
            <div className="flex items-center justify-between text-xs text-text-secondary">
              <span>
                Monthly Losses: <strong className="text-text-primary">{separationsThisMonth}</strong>
              </span>
              <span className="font-semibold text-text-secondary">Verified Active</span>
            </div>
          }
        />
      </section>

      {/* =================================================================== */}
      {/* 3. MAIN 2-COLUMN ASYMMETRIC COMMAND WORKSPACE (12 Columns)         */}
      {/* Left: 8 Cols (Analytics + Matrix) | Right: 4 Cols (Approvals + SA)  */}
      {/* =================================================================== */}
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-12 items-start">
        {/* ================================================================= */}
        {/* LEFT 8 COLUMNS: OPERATIONAL ANALYTICS & DRILLDOWN MATRIX          */}
        {/* ================================================================= */}
        <div className="space-y-6 lg:col-span-8">
          {/* CARD A: Operational Analytics & Fill Rate Breakdown */}
          <section
            aria-label="Operational analytics card"
            className="overflow-hidden rounded-2xl border border-border-default bg-surface-card shadow-2xs"
          >
            <div className="flex flex-wrap items-center justify-between gap-2 border-b border-border-subtle p-4 sm:p-5">
              <div>
                <h2 className="text-base font-semibold text-text-primary">
                  Operational Analytics &amp; Workforce Coverage
                </h2>
                <p className="mt-0.5 text-xs text-text-muted">
                  Real-time manpower fulfillment velocity, monthly hiring intake, and retention health
                </p>
              </div>

              {/* Exact Formula Breakdown Badge */}
              <div className="flex items-center gap-2 rounded-xl border border-border-default bg-surface-card px-3 py-1.5">
                <span className="text-xs font-semibold text-text-primary">
                  Avg Fill Rate:{" "}
                  <span
                    className={
                      fillRateStatus.status === "good"
                        ? "text-pct-good-text"
                        : fillRateStatus.status === "warn"
                        ? "text-pct-warn-text"
                        : "text-pct-bad-text"
                    }
                  >
                    {avgFillRateFormatted}
                  </span>
                </span>
                <span className="font-sans tabular-nums text-xs text-text-muted">
                  ({totalActivePlantilla} Actual / {totalScopedDemand} Required)
                </span>
              </div>
            </div>

            {/* 4-Column Metric Strip */}
            <div className="grid grid-cols-2 divide-y divide-border-subtle sm:grid-cols-4 sm:divide-y-0 sm:divide-x sm:divide-border-subtle">
              <div className="p-4">
                <div className="text-xs font-medium text-text-muted">Pipeline Total</div>
                <div className="mt-1 flex items-baseline gap-2">
                  <span className="text-2xl font-semibold tabular-nums text-text-primary">
                    <AnimatedNumber value={pipelineTotal} />
                  </span>
                  <span className="text-xs font-semibold text-brand-500">
                    {totalHrEmplocPending} Emploc • {Math.max(0, pipelineTotal - totalHrEmplocPending)} App
                  </span>
                </div>
                <div className="mt-0.5 text-xs text-text-muted">Active candidates in funnel</div>
              </div>

              <div className="p-4">
                <div className="text-xs font-medium text-text-muted">Hires This Month</div>
                <div className="mt-1 flex items-baseline gap-2">
                  <span className="text-2xl font-semibold tabular-nums text-text-primary">
                    <AnimatedNumber value={hiresThisMonth} />
                  </span>
                  <NeutralChip label="Current Intake" />
                </div>
                <div className="mt-0.5 text-xs text-text-muted">Confirmed &amp; deployed</div>
              </div>

              <div className="p-4">
                <div className="text-xs font-medium text-text-muted">Separations This Month</div>
                <div className="mt-1 flex items-baseline gap-2">
                  <span className="text-2xl font-semibold tabular-nums text-text-primary">
                    <AnimatedNumber value={separationsThisMonth} />
                  </span>
                  <NeutralChip
                    label={separationsThisMonth === 0 ? "Zero Loss" : `${separationsThisMonth} Separated`}
                  />
                </div>
                <div className="mt-0.5 text-xs text-text-muted">Recorded monthly turnover</div>
              </div>

              <div className="p-4">
                <div className="text-xs font-medium text-text-muted">Avg Fill Rate</div>
                <div className="mt-1 flex items-baseline gap-2">
                  <span
                    className={`text-2xl font-semibold tabular-nums ${
                      fillRateStatus.status === "good"
                        ? "text-pct-good-text"
                        : fillRateStatus.status === "warn"
                        ? "text-pct-warn-text"
                        : "text-pct-bad-text"
                    }`}
                  >
                    {avgFillRateFormatted}
                  </span>
                  <NeutralChip label="Target 80%" />
                </div>
                <div className="mt-0.5 text-xs text-text-muted">Actual / Total Scoped Demand</div>
              </div>
            </div>

            {/* Visual Proportional Segmented Coverage Bar */}
            <div className="border-t border-border-subtle bg-surface-muted/60 p-4 sm:p-5">
              <div className="mb-2 flex flex-wrap items-center justify-between text-xs">
                <span className="font-semibold text-text-primary">
                  Total Scoped Demand Breakdown ({totalScopedDemand} Required Seats)
                </span>
                <div className="flex flex-wrap items-center gap-4 text-xs font-medium text-text-secondary">
                  <span className="flex items-center gap-1.5">
                    <span className="h-2.5 w-2.5 rounded-xs bg-brand-500" />
                    {totalActivePlantilla} Active Plantilla ({activePlantillaWidthPct}%)
                  </span>
                  <span className="flex items-center gap-1.5">
                    <span className="h-2.5 w-2.5 rounded-xs bg-brand-600" />
                    {totalHrEmplocPending} HR Emploc Pending ({hrEmplocWidthPct}%)
                  </span>
                  <span className="flex items-center gap-1.5">
                    <span className="h-2.5 w-2.5 rounded-xs bg-border-strong" />
                    {totalOpenVacancies} Open Vacancies ({vacanciesWidthPct}%)
                  </span>
                </div>
              </div>
              <div className="flex h-2.5 w-full gap-0.5 overflow-hidden rounded-full bg-surface-muted border border-border-subtle p-0.5">
                <div
                  style={{ width: `${activePlantillaWidthPct}%` }}
                  className="rounded-l-full bg-brand-500 transition-all duration-300"
                  title={`Active Plantilla: ${totalActivePlantilla} (${activePlantillaWidthPct}%)`}
                />
                <div
                  style={{ width: `${hrEmplocWidthPct}%` }}
                  className="bg-brand-600 transition-all duration-300"
                  title={`HR Emploc Pending: ${totalHrEmplocPending} (${hrEmplocWidthPct}%)`}
                />
                <div
                  style={{ width: `${vacanciesWidthPct}%` }}
                  className="rounded-r-full bg-border-strong transition-all duration-300"
                  title={`Open Vacancies: ${totalOpenVacancies} (${vacanciesWidthPct}%)`}
                />
              </div>
            </div>
          </section>

          {/* CARD B: Cross-Module Operational Matrix (Tabbed Card Utilizing Bottom Viewport) */}
          <section
            aria-label="Cross-module operational matrix"
            className="overflow-hidden rounded-2xl border border-border-default bg-surface-card shadow-2xs"
          >
            {/* Tab Header */}
            <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border-subtle p-4 sm:p-5">
              <SegmentedTabs
                tabs={matrixTabs}
                activeKey={activeMatrixTab}
                onChange={setActiveMatrixTab}
                ariaLabel="Operational matrix views"
              />

              {/* Sub-toggle for Tab 1 */}
              {activeMatrixTab === "matrix" && (
                <div className="flex items-center gap-2">
                  <span className="text-xs text-text-muted">Filter:</span>
                  <button
                    type="button"
                    onClick={() => setMatrixFilterActiveOnly(!matrixFilterActiveOnly)}
                    className="rounded-lg border border-border-default bg-surface-muted px-2.5 py-1 text-xs font-medium text-text-secondary hover:bg-surface-hover cursor-pointer"
                  >
                    {matrixFilterActiveOnly ? "Showing Active Groups" : "Showing All Groups"}
                  </button>
                </div>
              )}
            </div>

            {/* TAB 1: Group Workforce Matrix */}
            {activeMatrixTab === "matrix" && (
              <div className="overflow-x-auto">
                {isGroupKpiLoading ? (
                  <div className="p-8 text-center text-sm text-text-muted">
                    Loading workforce groups...
                  </div>
                ) : displayedGroupRows.length === 0 ? (
                  <div className="p-8 text-center text-sm text-text-secondary">
                    No organizational groups found.
                  </div>
                ) : (
                  <table className="w-full border-collapse text-left text-sm">
                    <thead>
                      <tr className="border-b border-border-subtle bg-surface-muted/60 text-xs font-semibold uppercase text-text-muted">
                        <th className="py-2.5 px-4 sm:px-5">Group Name</th>
                        <th className="py-2.5 px-3 text-center">Plantilla</th>
                        <th className="py-2.5 px-3 text-center">Open Vacancy</th>
                        <th className="py-2.5 px-3 text-center">HR Emploc</th>
                        <th className="py-2.5 px-4 text-center">Fill Rate (MFR)</th>
                        <th className="py-2.5 px-4 sm:px-5 text-right">SLA Status</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border-subtle">
                      {displayedGroupRows.map((row) => (
                        <tr
                          key={row.groupName}
                          className="hover:bg-surface-hover transition-colors"
                        >
                          <td className="py-2.5 px-4 sm:px-5 font-semibold text-text-primary text-sm">
                            {row.groupName}
                          </td>
                          <td className="py-2.5 px-3 text-center font-medium tabular-nums text-sm">
                            {row.plantilla}
                          </td>
                          <td className="py-2.5 px-3 text-center font-semibold tabular-nums text-sm">
                            {row.vacancy}
                          </td>
                          <td className="py-2.5 px-3 text-center font-medium tabular-nums text-text-secondary text-sm">
                            {row.pipeline}
                          </td>
                          <td className="py-2.5 px-4 text-center">
                            {row.fillRatePct !== null ? (
                              <div className="flex items-center justify-center gap-2">
                                <div className="w-16">
                                  <PercentageBar
                                    percent={row.fillRatePct}
                                    scale="fill_rate"
                                    heightClass="h-1.5"
                                  />
                                </div>
                                <span className="font-semibold tabular-nums text-sm">
                                  {row.fillRatePct.toFixed(1)}%
                                </span>
                              </div>
                            ) : (
                              <span className="text-text-muted text-sm">Standby (0 Demand)</span>
                            )}
                          </td>
                          <td className="py-2.5 px-4 sm:px-5 text-right">
                            <NeutralChip label={row.slaStatus} />
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>
            )}

            {/* TAB 2: Active SLA Breaches */}
            {activeMatrixTab === "breaches" && (
              <div>
                <div className="flex flex-wrap items-center justify-between gap-2 border-b border-border-subtle bg-surface-muted/60 px-4 py-2.5 sm:px-5 text-xs">
                  <div className="flex items-center gap-3">
                    <span className="font-semibold text-text-primary">
                      Live SLA Breach Records:
                    </span>
                    <span className="text-text-secondary">
                      • {activeSlaBreaches} Logged Breaches in Audit Table
                    </span>
                  </div>
                  {activeSlaBreaches > 0 && (
                    <Link
                      href="/cencom"
                      className="font-semibold text-brand-500 hover:underline cursor-pointer"
                    >
                      Open CENCOM Triage Console →
                    </Link>
                  )}
                </div>
                <div className="overflow-x-auto">
                  {isSlaBreachesLoading ? (
                    <div className="p-8 text-center text-sm text-text-muted">
                      Loading SLA breach records...
                    </div>
                  ) : !slaBreachesData || slaBreachesData.length === 0 ? (
                    <div className="flex flex-col items-center justify-center p-8 text-center">
                      <CheckCircle2 className="h-8 w-8 text-brand-500 mb-2" />
                      <p className="text-sm font-semibold text-text-primary">
                        No active SLA breaches
                      </p>
                      <p className="text-xs text-text-muted mt-0.5">
                        All stores and movements comply with target SLAs
                      </p>
                    </div>
                  ) : (
                    <table className="w-full border-collapse text-left text-sm">
                      <thead>
                        <tr className="border-b border-border-subtle bg-surface-muted/60 text-xs font-semibold uppercase text-text-muted">
                          <th className="py-2.5 px-4 sm:px-5">Breach Lane / Account</th>
                          <th className="py-2.5 px-3">Category</th>
                          <th className="py-2.5 px-3">Scope Owner</th>
                          <th className="py-2.5 px-3 text-center">Aging</th>
                          <th className="py-2.5 px-4 sm:px-5 text-right">Action</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-border-subtle">
                        {slaBreachesData.map((b) => (
                          <tr
                            key={b.id}
                            className="hover:bg-surface-hover transition-colors"
                          >
                            <td className="py-2.5 px-4 sm:px-5">
                              <div className="font-semibold text-text-primary text-sm">
                                {b.storeName}
                              </div>
                              <div className="text-xs text-text-muted">{b.group}</div>
                            </td>
                            <td className="py-2.5 px-3">
                              <NeutralChip label={b.category} />
                            </td>
                            <td className="py-2.5 px-3">
                              <span className="text-xs font-medium text-text-secondary">
                                {b.owner}
                              </span>
                            </td>
                            <td className="py-2.5 px-3 text-center font-sans font-semibold tabular-nums text-sm">
                              {b.aging}
                            </td>
                            <td className="py-2.5 px-4 sm:px-5 text-right">
                              <Link
                                href={b.actionHref}
                                className="inline-flex items-center gap-1 rounded-lg border border-border-default bg-surface-card px-2.5 py-1 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition-colors"
                              >
                                <span>{b.actionLabel}</span>
                                <ExternalLink className="h-3 w-3 text-text-muted" />
                              </Link>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>
              </div>
            )}

            {/* TAB 3: Under-Staffed Stores */}
            {activeMatrixTab === "stores" && (
              <div className="p-4 sm:p-5">
                {isUnderstaffedStoresLoading ? (
                  <div className="p-8 text-center text-sm text-text-muted">
                    Loading understaffed stores...
                  </div>
                ) : !understaffedStoresData || understaffedStoresData.length === 0 ? (
                  <div className="flex flex-col items-center justify-center p-8 text-center">
                    <CheckCircle2 className="h-8 w-8 text-brand-500 mb-2" />
                    <p className="text-sm font-semibold text-text-primary">
                      All stores adequately staffed
                    </p>
                    <p className="text-xs text-text-muted mt-0.5">
                      Zero open vacancies across all active store units
                    </p>
                  </div>
                ) : (
                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 text-sm">
                    {understaffedStoresData.map((s) => (
                      <div
                        key={s.id}
                        className="flex items-center justify-between rounded-xl border border-border-default bg-surface-muted/40 p-3.5 hover:border-border-strong transition-colors"
                      >
                        <div>
                          <div className="font-semibold text-text-primary text-sm">
                            {s.storeName}
                          </div>
                          <div className="mt-0.5 text-xs text-text-secondary">
                            {s.group} • Open Vacancies:{" "}
                            <strong className="text-text-primary">{s.openVacancies}</strong>
                          </div>
                          <div className="mt-1 text-xs text-text-muted">
                            <span>HRCO: {s.assignedHrco}</span>
                          </div>
                        </div>
                        <Link
                          href="/vacancy"
                          className="shrink-0 rounded-lg border border-border-default bg-surface-card px-2.5 py-1 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition-colors"
                        >
                          Fill Slot →
                        </Link>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}
          </section>
        </div>

        {/* ================================================================= */}
        {/* RIGHT 4 COLUMNS: RECONCILED APPROVALS, SA GOVERNANCE & SECURITY   */}
        {/* ================================================================= */}
        <div className="space-y-6 lg:col-span-4">
          {/* CARD C: Pending Approvals & Action Queue (Reconciled with Sidebar) */}
          <section
            aria-label="Pending approvals queue"
            className="overflow-hidden rounded-2xl border border-border-default bg-surface-card shadow-2xs"
          >
            <div className="flex items-center justify-between border-b border-border-subtle p-4">
              <div className="flex items-center gap-2.5">
                <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-surface-muted text-brand-500">
                  <CheckSquare className="h-4 w-4" />
                </div>
                <div>
                  <h2 className="text-sm font-semibold text-text-primary leading-tight">
                    Pending Approvals Queue
                  </h2>
                  <p className="text-xs text-text-muted">Synced with sidebar Approvals badge</p>
                </div>
              </div>
              <NeutralChip label={`${totalReconciledApprovals} Pending`} />
            </div>

            <div className="space-y-2 p-3 sm:p-4 text-xs">
              {isRequestCountsLoading ? (
                <div className="p-4 text-center text-xs text-text-muted">
                  Loading approvals queue...
                </div>
              ) : liveApprovalItems.length === 0 ? (
                <div className="flex flex-col items-center justify-center py-4 text-center">
                  <CheckCircle2 className="h-6 w-6 text-brand-500 mb-1" />
                  <p className="text-xs font-semibold text-text-primary">All approvals cleared</p>
                  <p className="text-[11px] text-text-muted">
                    Zero pending requests in operational queues
                  </p>
                </div>
              ) : (
                liveApprovalItems.map((item, idx) => (
                  <div
                    key={idx}
                    className="flex items-center justify-between rounded-xl border border-border-subtle bg-surface-muted/50 p-3 hover:bg-surface-hover transition-colors"
                  >
                    <div className="min-w-0 pr-2">
                      <div className="font-semibold text-text-primary truncate text-sm">
                        {item.title}
                      </div>
                      <p className="text-xs text-text-muted truncate leading-tight mt-0.5">
                        {item.sub}
                      </p>
                    </div>
                    <Link
                      href={item.href}
                      className="shrink-0 rounded-lg border border-border-default bg-surface-card px-2.5 py-1 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition-colors"
                    >
                      Review ({item.count})
                    </Link>
                  </div>
                ))
              )}

              <div className="pt-2 flex items-center justify-between border-t border-border-subtle text-xs">
                <span className="text-xs text-text-muted">Reconciled with left navigation</span>
                <Link
                  href="/approvals"
                  className="font-semibold text-brand-500 hover:underline flex items-center gap-0.5 text-xs"
                >
                  Review All ({totalReconciledApprovals}) <ArrowRight className="h-3 w-3" />
                </Link>
              </div>
            </div>
          </section>

          {/* CARD D: Super Admin Governance & MIKA Sync Card (Strictly Super Admin Only) */}
          {isSuperAdmin && (
            <section
              aria-label="Super Admin governance card"
              className="overflow-hidden rounded-2xl border border-border-default bg-surface-card shadow-2xs"
            >
              <div className="flex items-center justify-between border-b border-border-subtle p-4">
                <div>
                  <div className="flex items-center gap-2">
                    <h2 className="text-sm font-semibold text-text-primary leading-tight">
                      Super Admin Governance &amp; MIKA
                    </h2>
                    <NeutralChip label="SA Only" />
                  </div>
                  <p className="text-xs text-text-muted mt-0.5">
                    Masterfile synchronization &amp; data hygiene
                  </p>
                </div>
                <ShieldCheck className="h-5 w-5 text-brand-500" />
              </div>

              <div className="p-4 space-y-3">
                {/* Ghost Employee Cases Live Alert */}
                <div className="rounded-xl border border-border-default bg-surface-muted p-3">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-text-primary">
                      {ghostEmployeeCount} Ghost Employee Cases
                    </span>
                    <NeutralChip label="Hygiene Alert" />
                  </div>
                  <p className="mt-1 text-xs text-text-secondary leading-tight">
                    Unmatched legacy workforce records pending MIKA reconciliation
                  </p>
                </div>

                {/* Inline Action Bar */}
                <div className="flex items-center justify-between gap-2 pt-0.5">
                  <Link
                    href="/plantilla"
                    className="text-xs font-semibold text-text-secondary hover:text-text-primary hover:underline"
                  >
                    Resolve Anomalies →
                  </Link>

                  {/* STRICT BUTTON NAMING: "Sync MIKA" */}
                  <button
                    type="button"
                    onClick={() => setIsMikaSyncModalOpen(true)}
                    className="inline-flex items-center gap-1.5 rounded-lg bg-brand-500 px-3 py-1.5 text-xs font-semibold text-white shadow-2xs hover:bg-brand-600 transition-colors cursor-pointer"
                  >
                    <CloudUpload className="h-3.5 w-3.5" />
                    <span>Sync MIKA</span>
                  </button>
                </div>
              </div>
            </section>
          )}

          {/* CARD E: Compact Security & Audit Telemetry Card */}
          <section
            aria-label="Security and audit telemetry"
            className="overflow-hidden rounded-2xl border border-border-default bg-surface-card shadow-2xs"
          >
            <div className="flex items-center justify-between border-b border-border-subtle p-4">
              <div>
                <h2 className="text-sm font-semibold text-text-primary leading-tight">
                  Security &amp; Audit Telemetry
                </h2>
                <p className="text-xs text-text-muted mt-0.5">
                  Real-time role access &amp; system security events
                </p>
              </div>
              <NeutralChip label={isSuperAdmin ? "Super Admin" : "Head Admin"} />
            </div>

            <div className="p-4 space-y-3">
              <div className="grid grid-cols-2 gap-2">
                <div className="rounded-xl border border-border-subtle bg-surface-muted/50 p-3">
                  <div className="text-xs font-medium text-text-muted">Admin Approvals</div>
                  <div className="text-lg font-semibold tabular-nums text-text-primary mt-1">
                    <AnimatedNumber value={metrics?.adminSecurityApprovals ?? 0} />
                  </div>
                  <div className="text-xs text-text-muted leading-tight mt-0.5">
                    Security role escalations
                  </div>
                </div>

                <div className="rounded-xl border border-border-subtle bg-surface-muted/50 p-3">
                  <div className="text-xs font-medium text-text-muted">Security Events</div>
                  <div className="flex items-baseline gap-1.5 mt-1">
                    <span className="text-lg font-semibold tabular-nums text-text-primary">
                      <AnimatedNumber value={metrics?.securityEventCount ?? 0} />
                    </span>
                    <NeutralChip label="Clean" />
                  </div>
                  <div className="text-xs text-text-muted leading-tight mt-0.5">
                    Access events today
                  </div>
                </div>
              </div>

              <div className="flex items-center justify-between border-t border-border-subtle pt-2 text-xs">
                <span className="text-xs text-text-muted">System Telemetry: Healthy</span>
                <Link
                  href="/more?tab=audit_logs"
                  className="font-semibold text-brand-500 hover:underline flex items-center gap-0.5 text-xs"
                >
                  Audit Logs <ArrowRight className="h-3 w-3" />
                </Link>
              </div>
            </div>
          </section>
        </div>
      </div>

      {/* =================================================================== */}
      {/* 4. MODALS & DRAWERS: MIKA SYNC MODAL                                */}
      {/* =================================================================== */}
      <MikaSyncModal
        isOpen={isMikaSyncModalOpen}
        onClose={() => setIsMikaSyncModalOpen(false)}
        onSuccess={() => {
          metricsQuery.refetch();
          analyticsQuery.refetch();
          showToast("Sync MIKA completed — Plantilla & SLA metrics verified");
        }}
      />
    </div>
  );
}
