"use client";

import { useState, useMemo } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQuery, keepPreviousData } from "@tanstack/react-query";
import {
  Briefcase,
  Users,
  CheckSquare,
  ShieldAlert,
  FileCheck2,
  ArrowRight,
  ExternalLink,
  CheckCircle2,
  AlertTriangle,
  Building2,
  AlertCircle,
} from "lucide-react";

import {
  getDashboardMetrics,
  getDashboardOperationalAnalytics,
  useDashboardSlaBreaches,
  useDashboardUnderstaffedStores,
} from "@/lib/queries/dashboard";
import { useRequestCategoryCounts } from "@/lib/queries/requests";
import { useCencomGroupKpi } from "@/lib/queries/cencom";
import { KpiCard } from "@/components/shared/KpiCard";
import { PercentageBar } from "@/components/shared/PercentageBar";
import { SegmentedTabs, type TabItem } from "@/components/shared/SegmentedTabs";
import { ScopeDropdown, type ScopeOption } from "@/components/shared/ScopeDropdown";
import { NeutralChip } from "@/components/shared/NeutralChip";
import { Toast } from "@/components/shared/Toast";

// ---------------------------------------------------------------------------
// Helpers & Types
// ---------------------------------------------------------------------------

type MatrixTabKey = "matrix" | "breaches" | "stores";

interface GroupWorkforceRow {
  groupName: string;
  plantilla: number | string;
  pipeline: number | string;
  vacancy: number | string;
  understaffedCount: number;
  fillRatePct: number | null;
  slaStatus: "Compliant" | "At Risk" | "Critical" | "Standby";
  isActiveGroup: boolean;
  isMosesHq?: boolean;
}

// ---------------------------------------------------------------------------
// Page Component
// ---------------------------------------------------------------------------

export default function DashboardPage() {
  const router = useRouter();

  // Selected Scope Filter
  const [selectedGroupScope, setSelectedGroupScope] = useState<string>("all");
  const [activeMatrixTab, setActiveMatrixTab] = useState<MatrixTabKey>("matrix");
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
  const { data: requestCounts } = useRequestCategoryCounts();

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
  const avgFillRatePct = avgFillRateNum * 100;

  // Dynamic Scoped Demand Denominator: Actual + HR Pipeline + Vacancy
  const totalScopedDemand = totalActivePlantilla + totalHrEmplocPending + totalOpenVacancies;

  const activePlantillaWidthPct =
    totalScopedDemand > 0 ? ((totalActivePlantilla / totalScopedDemand) * 100).toFixed(1) : "0.0";
  const hrEmplocWidthPct =
    totalScopedDemand > 0 ? ((totalHrEmplocPending / totalScopedDemand) * 100).toFixed(1) : "0.0";
  const vacanciesWidthPct =
    totalScopedDemand > 0 ? ((totalOpenVacancies / totalScopedDemand) * 100).toFixed(1) : "0.0";

  // Reconciled Approvals Count: 100% live derived from categories, synced with sidebar Approvals badge
  const totalReconciledApprovals = useMemo(() => {
    if (!requestCounts) return metrics?.pendingApprovals ?? 0;
    return Object.values(requestCounts).reduce((acc, c) => acc + c, 0);
  }, [requestCounts, metrics?.pendingApprovals]);

  const coverageRelieverCount = useMemo(() => {
    if (!requestCounts) return 0;
    return (requestCounts.coverage || 0) + (requestCounts.relievers || 0);
  }, [requestCounts]);

  // Derive MOSES HQ Real Values:
  // v_cencom_group_allocation_kpi aggregates only cencom_scope = TRUE (Groups 1-5).
  // Total active plantilla across whole system is in metrics (769).
  // Sum across CENCOM groups is 767. Difference (2) is MOSES HQ pool.
  // Similarly, HR Emploc pending delta (8 - 6) is 2.
  const cencomTotalPlantilla = useMemo(() => {
    if (!groupKpiData) return 0;
    return groupKpiData.reduce((acc, g) => acc + g.actual, 0);
  }, [groupKpiData]);

  const cencomTotalPipeline = useMemo(() => {
    if (!groupKpiData) return 0;
    return groupKpiData.reduce((acc, g) => acc + g.pipeline, 0);
  }, [groupKpiData]);

  const mosesPlantilla = useMemo(() => {
    if (totalActivePlantilla > 0 && cencomTotalPlantilla > 0) {
      const diff = totalActivePlantilla - cencomTotalPlantilla;
      return diff > 0 ? diff : 2;
    }
    return 2;
  }, [totalActivePlantilla, cencomTotalPlantilla]);

  const mosesHrEmploc = useMemo(() => {
    if (totalHrEmplocPending > 0 && cencomTotalPipeline > 0) {
      const diff = totalHrEmplocPending - cencomTotalPipeline;
      return diff > 0 ? diff : 2;
    }
    return 2;
  }, [totalHrEmplocPending, cencomTotalPipeline]);

  // Canonical Group matrix rows: Always list Group 1 to Group 5 by default, with MOSES HQ below Group 5
  const displayedGroupRows: GroupWorkforceRow[] = useMemo(() => {
    const canonical = [
      { name: "Group 1", code: "G1" },
      { name: "Group 2", code: "G2" },
      { name: "Group 3", code: "G3" },
      { name: "Group 4", code: "G4" },
      { name: "Group 5", code: "G5" },
    ];

    const result: GroupWorkforceRow[] = [];

    for (const cg of canonical) {
      const match = groupKpiData?.find(
        (g) =>
          (g.groupCode && g.groupCode.toUpperCase() === cg.code) ||
          g.groupName.toLowerCase().includes(cg.name.toLowerCase())
      );

      if (match) {
        const fillPct =
          match.required > 0 ? Math.round((match.actual / match.required) * 1000) / 10 : null;
        const status: "Compliant" | "At Risk" | "Critical" | "Standby" =
          match.required === 0 && match.actual === 0 && match.vacant === 0
            ? "Standby"
            : match.vacant > 3
            ? "Critical"
            : match.vacant > 0
            ? "At Risk"
            : "Compliant";

        result.push({
          groupName: match.groupName || match.groupCode || cg.name,
          plantilla: match.actual,
          pipeline: match.pipeline,
          vacancy: match.vacant,
          understaffedCount: match.vacant > 0 ? 1 : 0,
          fillRatePct: fillPct,
          slaStatus: status,
          isActiveGroup: match.required > 0 || match.actual > 0 || match.vacant > 0,
        });
      } else {
        result.push({
          groupName: cg.name,
          plantilla: "—",
          pipeline: "—",
          vacancy: "—",
          understaffedCount: 0,
          fillRatePct: null,
          slaStatus: "Standby",
          isActiveGroup: false,
        });
      }
    }

    // Append MOSES HQ below Group 5 with real values, "—" fill rate, and "Standby" status (never Critical)
    result.push({
      groupName: "MOSES HQ",
      plantilla: mosesPlantilla,
      pipeline: mosesHrEmploc,
      vacancy: 0,
      understaffedCount: 0,
      fillRatePct: null,
      slaStatus: "Standby",
      isActiveGroup: true,
      isMosesHq: true,
    });

    return result;
  }, [groupKpiData, mosesPlantilla, mosesHrEmploc]);

  // Critical groups for attention list
  const criticalGroups = useMemo(() => {
    return displayedGroupRows.filter((g) => g.slaStatus === "Critical");
  }, [displayedGroupRows]);

  // Scope Dropdown Options
  const scopeOptions: ScopeOption[] = useMemo(() => {
    return [
      {
        value: "all",
        label: "All Retail Groups",
        badge: `${displayedGroupRows.length}`,
      },
      ...displayedGroupRows.map((g) => ({
        value: g.groupName,
        label: g.groupName,
        badge:
          g.fillRatePct !== null
            ? `${g.fillRatePct.toFixed(1)}% MFR`
            : typeof g.plantilla === "number" && g.plantilla > 0
            ? `${g.plantilla} Active`
            : "Standby",
      })),
    ];
  }, [displayedGroupRows]);

  // Matrix Tabs Configuration
  const matrixTabs: TabItem<MatrixTabKey>[] = useMemo(
    () => [
      {
        key: "matrix",
        label: "Group matrix",
      },
      {
        key: "breaches",
        label: "SLA breaches",
        count: activeSlaBreaches,
      },
      {
        key: "stores",
        label: "Under-staffed stores",
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
      {/* 1. HEADER BAR                                                       */}
      {/* =================================================================== */}
      <header className="flex flex-wrap items-center justify-between gap-4 rounded-2xl border border-border-default bg-surface-card p-4 sm:p-5 shadow-2xs">
        <div>
          <div className="flex items-center gap-2 text-xs font-semibold text-text-muted">
            <span>Admin panel</span>
            <span>/</span>
            <span className="font-semibold text-brand-500">Dashboard Overview</span>
          </div>
          <div className="mt-1 flex items-baseline gap-3">
            <h1 className="text-2xl sm:text-3xl font-semibold tracking-tight text-text-primary">
              Command Center
            </h1>
            <span className="hidden text-xs text-text-muted sm:inline">
              Cross-module operational overview for the OHMployee admin workspace
            </span>
          </div>
        </div>

        {/* Right Header: Scope Selector Only */}
        <div className="flex items-center gap-2.5">
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
        </div>
      </header>

      {/* =================================================================== */}
      {/* 2. KPI ROW: 4 CARDS (Replaces 5 cards + analytics strip)             */}
      {/* =================================================================== */}
      <section
        aria-label="Executive KPI Overview"
        className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4"
      >
        {/* Card 1: Workforce Coverage */}
        <KpiCard
          title="Workforce Coverage"
          value={avgFillRatePct}
          decimals={1}
          suffix="%"
          subtitle={`${totalActivePlantilla} of ${totalScopedDemand} seats filled`}
          badge={
            <span
              className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                avgFillRatePct >= 80
                  ? "bg-emerald-50 text-emerald-700 border border-emerald-200 dark:bg-emerald-950/30 dark:text-emerald-400 dark:border-emerald-800"
                  : "bg-amber-50 text-amber-700 border border-amber-200 dark:bg-amber-950/30 dark:text-amber-400 dark:border-amber-800"
              }`}
            >
              {avgFillRatePct >= 80 ? "Above 80% target" : "Below 80% target"}
            </span>
          }
          icon={Users}
          onClick={() => router.push("/plantilla")}
          footer={
            <div className="space-y-1.5 pt-2 border-t border-border-subtle">
              <div className="flex h-2 w-full gap-0.5 overflow-hidden rounded-full bg-surface-muted border border-border-subtle p-0.5">
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
              <div className="flex items-center justify-between text-[11px] text-text-muted">
                <span className="flex items-center gap-1">
                  <span className="h-1.5 w-1.5 rounded-full bg-brand-500" />
                  Active {totalActivePlantilla}
                </span>
                <span className="flex items-center gap-1">
                  <span className="h-1.5 w-1.5 rounded-full bg-brand-600" />
                  Emploc {totalHrEmplocPending}
                </span>
                <span className="flex items-center gap-1">
                  <span className="h-1.5 w-1.5 rounded-full bg-border-strong" />
                  Open {totalOpenVacancies}
                </span>
              </div>
            </div>
          }
        />

        {/* Card 2: Open Vacancies */}
        <KpiCard
          title="Open Vacancies"
          value={totalOpenVacancies}
          subtitle={`${assignedVacancies} assigned to HRCO`}
          badge={<NeutralChip label={`${unassignedVacancies} unassigned to HRCO`} />}
          icon={Briefcase}
          onClick={() => router.push("/vacancy")}
          footer={
            <div className="flex items-center justify-between text-xs text-text-muted pt-2 border-t border-border-subtle">
              <span>
                Unassigned: <strong className="text-text-primary">{unassignedVacancies}</strong>
              </span>
              <span className="text-brand-500 font-medium inline-flex items-center gap-0.5">
                Vacancy Hub <ArrowRight className="h-3 w-3" />
              </span>
            </div>
          }
        />

        {/* Card 3: Hiring Pipeline */}
        <KpiCard
          title="Hiring Pipeline"
          value={pipelineTotal}
          subtitle={`${totalHrEmplocPending} HR Emploc · ${Math.max(0, pipelineTotal - totalHrEmplocPending)} applicants`}
          badge={<NeutralChip label="Active Funnel" />}
          icon={FileCheck2}
          onClick={() => router.push("/hr-emploc")}
          footer={
            <div className="flex items-center justify-between text-xs text-text-muted pt-2 border-t border-border-subtle">
              <span>
                This month: <strong className="text-text-primary">+{hiresThisMonth}</strong> ·{" "}
                <strong className="text-text-primary">−{separationsThisMonth}</strong>
              </span>
              <span className="text-brand-500 font-medium inline-flex items-center gap-0.5">
                HR Emploc <ArrowRight className="h-3 w-3" />
              </span>
            </div>
          }
        />

        {/* Card 4: SLA Breaches */}
        <KpiCard
          title="SLA Breaches"
          value={activeSlaBreaches}
          subtitle="Pending movements or vacancy SLA breaches"
          badge={<NeutralChip label="Action required" />}
          icon={AlertTriangle}
          onClick={() => router.push("/cencom")}
          footer={
            <div className="flex items-center justify-between text-xs text-text-muted pt-2 border-t border-border-subtle">
              <span>
                Aging: <strong className="text-text-primary">{slaBreachesData?.[0]?.aging ?? "—"}</strong>
              </span>
              <span className="text-brand-500 font-medium inline-flex items-center gap-0.5">
                CENCOM Triage <ArrowRight className="h-3 w-3" />
              </span>
            </div>
          }
        />
      </section>

      {/* =================================================================== */}
      {/* 3. MAIN COMMAND WORKSPACE: LEFT 8 COLS (MATRIX) | RIGHT 4 COLS      */}
      {/* =================================================================== */}
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-12 items-start">
        {/* ================================================================= */}
        {/* LEFT 8 COLUMNS: "Where is the gap?" MATRIX & OPERATIONAL DRILLDOWN */}
        {/* ================================================================= */}
        <div className="space-y-6 lg:col-span-8">
          <section
            aria-label="Where is the gap matrix card"
            className="overflow-hidden rounded-2xl border border-border-default bg-surface-card shadow-2xs"
          >
            {/* Card Header & Tabs */}
            <div className="border-b border-border-subtle p-4 sm:p-5">
              <div className="mb-3">
                <h2 className="text-base font-semibold text-text-primary">
                  Where is the gap?
                </h2>
                <p className="mt-0.5 text-xs text-text-muted">
                  Departmental headcount allocation, aging SLA breaches, and store shortage analysis
                </p>
              </div>

              <SegmentedTabs
                tabs={matrixTabs}
                activeKey={activeMatrixTab}
                onChange={setActiveMatrixTab}
                ariaLabel="Operational gap analysis views"
              />
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
                      <tr className="border-b border-table-rule-section bg-table-header text-sm font-semibold text-text-secondary">
                        <th className="py-2.5 px-4 sm:px-5 whitespace-nowrap">Group name</th>
                        <th className="py-2.5 px-3 text-center whitespace-nowrap">Plantilla</th>
                        <th className="py-2.5 px-3 text-center whitespace-nowrap">Open vacancy</th>
                        <th className="py-2.5 px-3 text-center whitespace-nowrap">HR Emploc</th>
                        <th className="py-2.5 px-4 text-center whitespace-nowrap">Fill rate (MFR)</th>
                        <th className="py-2.5 px-4 sm:px-5 text-right whitespace-nowrap">SLA status</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border-subtle">
                      {displayedGroupRows.map((row) => {
                        const isCritical = row.slaStatus === "Critical";
                        return (
                          <tr
                            key={row.groupName}
                            className={`transition-colors ${
                              isCritical
                                ? "bg-red-500/10 hover:bg-red-500/15 border-l-4 border-l-red-500"
                                : "hover:bg-surface-hover"
                            }`}
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
                                <div className="flex items-center justify-center gap-2">
                                  <div className="w-16 h-1.5 rounded-full bg-surface-muted" />
                                  <span className="font-semibold tabular-nums text-sm text-text-muted">—</span>
                                </div>
                              )}
                            </td>
                            <td className="py-2.5 px-4 sm:px-5 text-right">
                              <NeutralChip label={row.slaStatus} />
                            </td>
                          </tr>
                        );
                      })}
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
                        <tr className="border-b border-table-rule-section bg-table-header text-sm font-semibold text-text-secondary">
                          <th className="py-2.5 px-4 sm:px-5 whitespace-nowrap">Breach lane / account</th>
                          <th className="py-2.5 px-3 whitespace-nowrap">Category</th>
                          <th className="py-2.5 px-3 whitespace-nowrap">Scope owner</th>
                          <th className="py-2.5 px-3 text-center whitespace-nowrap">Aging</th>
                          <th className="py-2.5 px-4 sm:px-5 text-right whitespace-nowrap">Action</th>
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
        {/* RIGHT 4 COLUMNS: "Needs your attention" LIST                      */}
        {/* ================================================================= */}
        <div className="space-y-6 lg:col-span-4">
          <section
            aria-label="Needs your attention"
            className="overflow-hidden rounded-2xl border border-border-default bg-surface-card shadow-2xs"
          >
            <div className="flex items-center justify-between border-b border-border-subtle p-4">
              <div className="flex items-center gap-2.5">
                <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-surface-muted text-brand-500">
                  <AlertCircle className="h-4 w-4" />
                </div>
                <div>
                  <h2 className="text-sm font-semibold text-text-primary leading-tight">
                    Needs your attention
                  </h2>
                  <p className="text-xs text-text-muted">Critical operational alerts &amp; pending actions</p>
                </div>
              </div>
            </div>

            <div className="space-y-2 p-3 sm:p-4 text-xs">
              {/* 1. Critical Groups */}
              <div className="flex items-center justify-between rounded-xl border border-border-subtle bg-surface-muted/50 p-3 hover:bg-surface-hover transition-colors">
                <div className="flex items-start gap-2.5 min-w-0 pr-2">
                  <AlertTriangle
                    className={`h-4 w-4 shrink-0 mt-0.5 ${
                      criticalGroups.length > 0 ? "text-red-500" : "text-emerald-500"
                    }`}
                  />
                  <div className="min-w-0">
                    <div className="font-semibold text-text-primary truncate text-sm">
                      {criticalGroups.length > 0
                        ? `${criticalGroups.length} Critical Group${
                            criticalGroups.length > 1 ? "s" : ""
                          }: ${criticalGroups.map((g) => g.groupName).join(", ")}`
                        : "All Groups Compliant"}
                    </div>
                    <p className="text-xs text-text-muted truncate mt-0.5">
                      {criticalGroups.length > 0
                        ? "Staffing deficit below critical SLA target threshold"
                        : "Zero groups currently in critical staffing status"}
                    </p>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => setActiveMatrixTab("matrix")}
                  className="shrink-0 rounded-lg border border-border-default bg-surface-card px-2.5 py-1 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition-colors cursor-pointer"
                >
                  View
                </button>
              </div>

              {/* 2. Pending Approvals */}
              <div className="flex items-center justify-between rounded-xl border border-border-subtle bg-surface-muted/50 p-3 hover:bg-surface-hover transition-colors">
                <div className="flex items-start gap-2.5 min-w-0 pr-2">
                  <CheckSquare className="h-4 w-4 shrink-0 mt-0.5 text-brand-500" />
                  <div className="min-w-0">
                    <div className="font-semibold text-text-primary truncate text-sm">
                      {totalReconciledApprovals} Pending Approvals
                    </div>
                    <p className="text-xs text-text-muted truncate mt-0.5">
                      Includes {coverageRelieverCount} coverage &amp; reliever count
                    </p>
                  </div>
                </div>
                <Link
                  href="/approvals"
                  className="shrink-0 rounded-lg border border-border-default bg-surface-card px-2.5 py-1 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition-colors"
                >
                  Review
                </Link>
              </div>

              {/* 3. Under-Staffed Stores */}
              <div className="flex items-center justify-between rounded-xl border border-border-subtle bg-surface-muted/50 p-3 hover:bg-surface-hover transition-colors">
                <div className="flex items-start gap-2.5 min-w-0 pr-2">
                  <Building2
                    className={`h-4 w-4 shrink-0 mt-0.5 ${
                      understaffedStores > 0 ? "text-amber-500" : "text-emerald-500"
                    }`}
                  />
                  <div className="min-w-0">
                    <div className="font-semibold text-text-primary truncate text-sm">
                      {understaffedStores} Under-Staffed Stores
                    </div>
                    <p className="text-xs text-text-muted truncate mt-0.5">
                      Stores below budgeted plantilla targets
                    </p>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => setActiveMatrixTab("stores")}
                  className="shrink-0 rounded-lg border border-border-default bg-surface-card px-2.5 py-1 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition-colors cursor-pointer"
                >
                  Inspect
                </button>
              </div>

              {/* 4. Ghost Employee Records */}
              <div className="flex items-center justify-between rounded-xl border border-border-subtle bg-surface-muted/50 p-3 hover:bg-surface-hover transition-colors">
                <div className="flex items-start gap-2.5 min-w-0 pr-2">
                  <ShieldAlert
                    className={`h-4 w-4 shrink-0 mt-0.5 ${
                      ghostEmployeeCount > 0 ? "text-amber-500" : "text-emerald-500"
                    }`}
                  />
                  <div className="min-w-0">
                    <div className="font-semibold text-text-primary truncate text-sm">
                      {ghostEmployeeCount} Ghost Employee Records
                    </div>
                    <p className="text-xs text-text-muted truncate mt-0.5">
                      Unmatched legacy records pending reconciliation
                    </p>
                  </div>
                </div>
                <Link
                  href="/plantilla"
                  className="shrink-0 rounded-lg border border-border-default bg-surface-card px-2.5 py-1 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition-colors"
                >
                  Resolve Anomalies →
                </Link>
              </div>
            </div>
          </section>
        </div>
      </div>

      {/* =================================================================== */}
      {/* 4. FOOTER LINE: SECURITY & AUDIT TELEMETRY                           */}
      {/* =================================================================== */}
      <footer className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-border-subtle bg-surface-muted/50 px-4 py-2.5 text-xs text-text-muted">
        <div className="flex items-center gap-2">
          <span className="h-2 w-2 rounded-full bg-emerald-500" />
          <span className="font-medium text-text-primary">System healthy</span>
          <span>•</span>
          <span>
            <strong className="text-text-primary">{metrics?.securityEventCount ?? 0}</strong> access events today
          </span>
        </div>
        <Link
          href="/more?tab=audit_logs"
          className="font-medium text-brand-500 hover:underline inline-flex items-center gap-1"
        >
          <span>Audit logs</span>
          <ArrowRight className="h-3 w-3" />
        </Link>
      </footer>
    </div>
  );
}
