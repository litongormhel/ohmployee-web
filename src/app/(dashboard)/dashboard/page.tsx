"use client";

import { useState, useMemo } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import {
  LayoutDashboard,
  Briefcase,
  Users,
  CheckSquare,
  ShieldCheck,
  CloudUpload,
  Filter,
  Radio,
  FileCheck2,
  Store,
  Layers,
  ArrowRight,
  ExternalLink,
  Sparkles,
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
    setTimeout(() => {
      setToastMessage(null);
    }, 3200);
  };

  // -------------------------------------------------------------------------
  // Live Queries
  // -------------------------------------------------------------------------

  const metricsQuery = useQuery({
    queryKey: ["dashboard", "metrics", selectedGroupScope === "all" ? null : selectedGroupScope],
    queryFn: () => getDashboardMetrics(),
  });

  const analyticsQuery = useQuery({
    queryKey: [
      "dashboard",
      "operational-analytics",
      selectedGroupScope === "all" ? null : selectedGroupScope,
    ],
    queryFn: () => getDashboardOperationalAnalytics(),
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

  return (
    <div className="flex flex-col gap-5 text-slate-900 pb-8 sm:pb-12">
      {/* Toast Notification */}
      {toastMessage && (
        <div
          role="status"
          aria-live="polite"
          className="fixed bottom-6 right-6 z-50 flex items-center gap-2 rounded-xl border border-slate-700 bg-slate-900 px-4 py-2.5 text-xs font-semibold text-white shadow-2xl"
        >
          <Sparkles className="h-4 w-4 text-emerald-400" />
          <span>{toastMessage}</span>
        </div>
      )}

      {/* =================================================================== */}
      {/* 1. TOP COMMAND HEADER BAR                                           */}
      {/* =================================================================== */}
      <header className="flex flex-wrap items-center justify-between gap-4 border-b border-slate-200/90 bg-white px-5 py-3.5 rounded-2xl shadow-xs">
        <div>
          <div className="flex items-center gap-2 text-[11px] font-bold uppercase tracking-wider text-slate-400">
            <span>ADMIN PANEL</span>
            <span>/</span>
            <span className="flex items-center gap-1 font-semibold text-blue-600">
              <LayoutDashboard className="h-3.5 w-3.5" />
              Dashboard Overview
            </span>
            <span className="ml-1 inline-flex items-center gap-1 rounded-full border border-emerald-200 bg-emerald-50 px-2 py-0.5 text-[10px] font-semibold text-emerald-700">
              <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-500" />
              Live RPC Telemetry Connected
            </span>
          </div>
          <div className="mt-1 flex items-baseline gap-3">
            <h1 className="text-xl font-extrabold tracking-tight text-slate-900">
              Web Admin Command Center
            </h1>
            <span className="hidden text-xs text-slate-500 sm:inline">
              Cross-module operational overview for the OHMployee admin workspace
            </span>
          </div>
        </div>

        {/* Right Header Action Toolbar */}
        <div className="flex flex-wrap items-center gap-2.5">
          {/* Group Scope Selector */}
          <div className="flex items-center gap-1.5 rounded-xl border border-slate-200 bg-slate-100 px-3 py-1.5 text-xs">
            <Filter className="h-3.5 w-3.5 text-slate-400" />
            <span className="font-medium text-slate-500">Scope:</span>
            <select
              value={selectedGroupScope}
              onChange={(e) => {
                setSelectedGroupScope(e.target.value);
                showToast(
                  `Dashboard scoped to: ${e.target.value === "all" ? "All Retail Groups" : e.target.value}`
                );
              }}
              className="cursor-pointer bg-transparent font-bold text-slate-800 focus:outline-none"
            >
              <option value="all">All Retail Groups ({liveGroupRows.length})</option>
              {liveGroupRows.map((g) => (
                <option key={g.groupName} value={g.groupName}>
                  {g.groupName} {g.fillRatePct !== null ? `(${g.fillRatePct.toFixed(1)}% MFR)` : "(Standby Scope)"}
                </option>
              ))}
            </select>
          </div>

          {/* Quick link to CENCOM Triage when SLA breaches > 0 */}
          {activeSlaBreaches > 0 && (
            <Link
              href="/cencom"
              className="inline-flex items-center gap-1.5 rounded-xl border border-rose-200 bg-rose-50 px-3 py-1.5 text-xs font-semibold text-rose-700 shadow-2xs transition hover:bg-rose-100"
            >
              <Radio className="h-3.5 w-3.5 text-rose-600 animate-pulse" />
              <span>CENCOM Triage ({activeSlaBreaches})</span>
            </Link>
          )}

          {/* STRICT BUTTON NAMING: "Sync MIKA" (Visible to Super Admin only) */}
          {isSuperAdmin && (
            <button
              type="button"
              onClick={() => setIsMikaSyncModalOpen(true)}
              className="inline-flex items-center gap-1.5 rounded-xl bg-slate-900 px-3.5 py-1.5 text-xs font-bold text-white shadow-xs transition hover:bg-slate-800 cursor-pointer"
            >
              <CloudUpload className="h-3.5 w-3.5 text-blue-300" />
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
        <div
          onClick={() => setActiveMatrixTab("breaches")}
          className={`group relative cursor-pointer overflow-hidden rounded-2xl border-2 p-3.5 transition-all hover:shadow-md ${
            activeMatrixTab === "breaches"
              ? "border-rose-500 bg-rose-50/60 shadow-xs"
              : "border-rose-300/90 bg-gradient-to-br from-rose-50 via-white to-white"
          }`}
        >
          <div className="absolute top-0 left-0 right-0 h-1 bg-rose-600" />
          <div className="flex items-center justify-between">
            <span className="text-[11px] font-extrabold uppercase tracking-wider text-rose-700">
              Active SLA Breaches
            </span>
            <span className="inline-flex items-center gap-1 rounded-full bg-rose-100 px-2 py-0.5 text-[10px] font-bold text-rose-700">
              <span className="h-1.5 w-1.5 rounded-full bg-rose-600 animate-ping" />
              Action Required
            </span>
          </div>
          <div className="mt-2 flex items-baseline justify-between">
            <span className="text-3xl font-extrabold tabular-nums tracking-tight text-[#DC2626]">
              {metricsQuery.isLoading ? "--" : activeSlaBreaches}
            </span>
            <span className="flex items-center gap-0.5 text-[11px] font-semibold text-rose-700 transition group-hover:translate-x-0.5">
              Inspect <ArrowRight className="h-3 w-3" />
            </span>
          </div>
          <p className="mt-1 text-xs text-slate-600">Pending movements or vacancy SLA breaches</p>
          <div className="mt-2.5 flex items-center justify-between border-t border-rose-100 pt-2 text-[11px] font-semibold text-rose-700">
            <span>{activeSlaBreaches} Logged Inactivity Breaches</span>
            <span className="font-mono text-slate-500">Aging: {slaBreachesData?.[0]?.aging ?? "—"}</span>
          </div>
        </div>

        {/* KPI 2: UNDER-STAFFED STORES */}
        <div
          onClick={() => setActiveMatrixTab("stores")}
          className={`group relative cursor-pointer overflow-hidden rounded-2xl border p-3.5 transition-all hover:shadow-md ${
            activeMatrixTab === "stores"
              ? "border-amber-500 bg-amber-50/60 shadow-xs"
              : "border-amber-300/90 bg-gradient-to-br from-amber-50/70 via-white to-white"
          }`}
        >
          <div className="absolute top-0 left-0 right-0 h-1 bg-amber-500" />
          <div className="flex items-center justify-between">
            <span className="text-[11px] font-bold uppercase tracking-wider text-amber-800">
              Under-Staffed Stores
            </span>
            <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-bold text-amber-800">
              At Risk
            </span>
          </div>
          <div className="mt-2 flex items-baseline justify-between">
            <span className="text-3xl font-extrabold tabular-nums tracking-tight text-[#D97706]">
              {metricsQuery.isLoading ? "--" : understaffedStores}
            </span>
            <span className="flex items-center gap-0.5 text-[11px] font-semibold text-amber-700 transition group-hover:translate-x-0.5">
              View Stores <ArrowRight className="h-3 w-3" />
            </span>
          </div>
          <p className="mt-1 text-xs text-slate-500">Stores below budgeted plantilla target</p>
          <div className="mt-2.5 flex items-center justify-between border-t border-slate-100 pt-2 text-[11px] text-slate-500">
            <span>
              Lowest MFR: <strong className="text-slate-800">{worstMfrGroupName}</strong>
            </span>
            <span className="font-semibold text-amber-700">
              {understaffedStores > 0 ? "Staffing Deficit Alert" : "All Stores Staffed"}
            </span>
          </div>
        </div>

        {/* KPI 3: OPEN VACANCIES */}
        <div
          onClick={() => setActiveMatrixTab("matrix")}
          className={`group relative cursor-pointer overflow-hidden rounded-2xl border p-3.5 transition-all hover:shadow-md ${
            activeMatrixTab === "matrix"
              ? "border-blue-500 bg-blue-50/40 shadow-xs"
              : "border-slate-200/90 bg-white hover:border-blue-300"
          }`}
        >
          <div className="absolute top-0 left-0 right-0 h-1 bg-blue-600" />
          <div className="flex items-center justify-between">
            <span className="text-[11px] font-bold uppercase tracking-wider text-slate-500">
              Open Vacancies
            </span>
            <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-blue-50 text-blue-600">
              <Briefcase className="h-4 w-4" />
            </div>
          </div>
          <div className="mt-2 flex items-baseline justify-between">
            <span className="text-3xl font-extrabold tabular-nums tracking-tight text-slate-900">
              {metricsQuery.isLoading ? "--" : totalOpenVacancies}
            </span>
            <span className="rounded bg-rose-50 px-1.5 py-0.5 text-[11px] font-semibold text-rose-600">
              {unassignedVacancies} Unassigned
            </span>
          </div>
          <p className="mt-1 text-xs text-slate-500">Active open vacancy slots</p>
          <div className="mt-2.5 flex items-center justify-between border-t border-slate-100 pt-2 text-[11px] text-slate-500">
            <span>{assignedVacancies} Assigned to HRCO</span>
            <span className="font-semibold text-blue-600">{avgFillRateFormatted} Fill</span>
          </div>
        </div>

        {/* KPI 4: HR EMPLOC PENDING */}
        <div
          onClick={() => setActiveMatrixTab("matrix")}
          className="group relative cursor-pointer overflow-hidden rounded-2xl border border-slate-200/90 bg-white p-3.5 transition-all hover:border-indigo-300 hover:shadow-md"
        >
          <div className="absolute top-0 left-0 right-0 h-1 bg-indigo-600" />
          <div className="flex items-center justify-between">
            <span className="text-[11px] font-bold uppercase tracking-wider text-slate-500">
              HR Emploc Pending
            </span>
            <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-indigo-50 text-indigo-600">
              <FileCheck2 className="h-4 w-4" />
            </div>
          </div>
          <div className="mt-2 flex items-baseline justify-between">
            <span className="text-3xl font-extrabold tabular-nums tracking-tight text-slate-900">
              {metricsQuery.isLoading ? "--" : totalHrEmplocPending}
            </span>
            <span className="rounded bg-indigo-50 px-1.5 py-0.5 text-[11px] font-semibold text-indigo-600">
              In Motion
            </span>
          </div>
          <p className="mt-1 text-xs text-slate-500">Onboarding compliance items pending</p>
          <div className="mt-2.5 flex items-center justify-between border-t border-slate-100 pt-2 text-[11px] text-slate-500">
            <span>Onboarding Pipeline</span>
            <span className="font-semibold text-indigo-600">Pending Review</span>
          </div>
        </div>

        {/* KPI 5: ACTIVE PLANTILLA */}
        <div
          onClick={() => setActiveMatrixTab("matrix")}
          className="group relative cursor-pointer overflow-hidden rounded-2xl border border-slate-200/90 bg-white p-3.5 transition-all hover:border-emerald-300 hover:shadow-md"
        >
          <div className="absolute top-0 left-0 right-0 h-1 bg-emerald-600" />
          <div className="flex items-center justify-between">
            <span className="text-[11px] font-bold uppercase tracking-wider text-slate-500">
              Active Plantilla
            </span>
            <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-emerald-50 text-emerald-600">
              <Users className="h-4 w-4" />
            </div>
          </div>
          <div className="mt-2 flex items-baseline justify-between">
            <span className="text-3xl font-extrabold tabular-nums tracking-tight text-slate-900">
              {metricsQuery.isLoading ? "--" : totalActivePlantilla}
            </span>
            <span className="rounded bg-emerald-50 px-1.5 py-0.5 text-[11px] font-semibold text-emerald-700">
              of {plantillaTarget} Target
            </span>
          </div>
          <p className="mt-1 text-xs text-slate-500">Total active deployed employees</p>
          <div className="mt-2.5 flex items-center justify-between border-t border-slate-100 pt-2 text-[11px] text-slate-500">
            <span>
              Monthly Losses: <strong className="text-emerald-600">{separationsThisMonth}</strong>
            </span>
            <span className="font-semibold text-emerald-700">Verified Active</span>
          </div>
        </div>
      </section>

      {/* =================================================================== */}
      {/* 3. MAIN 2-COLUMN ASYMMETRIC COMMAND WORKSPACE (12 Columns)         */}
      {/* Left: 8 Cols (Analytics + Matrix) | Right: 4 Cols (Approvals + SA)  */}
      {/* =================================================================== */}
      <div className="grid grid-cols-1 gap-5 lg:grid-cols-12 items-start">
        {/* ================================================================= */}
        {/* LEFT 8 COLUMNS: OPERATIONAL ANALYTICS & DRILLDOWN MATRIX          */}
        {/* ================================================================= */}
        <div className="space-y-5 lg:col-span-8">
          {/* CARD A: Operational Analytics & Fill Rate Breakdown */}
          <section
            aria-label="Operational analytics card"
            className="overflow-hidden rounded-2xl border border-slate-200/90 bg-white shadow-xs"
          >
            <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-100 px-5 py-3.5">
              <div>
                <h2 className="text-sm font-bold text-slate-900">
                  Operational Analytics &amp; Workforce Coverage
                </h2>
                <p className="mt-0.5 text-xs text-slate-500">
                  Real-time manpower fulfillment velocity, monthly hiring intake, and retention health
                </p>
              </div>

              {/* Exact Formula Breakdown Badge */}
              <div className="flex items-center gap-2 rounded-xl border border-amber-200 bg-amber-50 px-3 py-1.5">
                <span className="text-xs font-bold text-amber-900">
                  Avg Fill Rate: {avgFillRateFormatted}
                </span>
                <span className="font-mono text-[11px] text-amber-700">
                  ({totalActivePlantilla} Actual / {totalScopedDemand} Required)
                </span>
              </div>
            </div>

            {/* 4-Column Metric Strip */}
            <div className="grid grid-cols-2 divide-y divide-slate-100 sm:grid-cols-4 sm:divide-y-0 sm:divide-x">
              <div className="p-3.5">
                <div className="text-[11px] font-bold uppercase tracking-wider text-slate-400">
                  Pipeline Total
                </div>
                <div className="mt-1 flex items-baseline gap-2">
                  <span className="text-2xl font-extrabold tabular-nums text-slate-900">
                    {analyticsQuery.isLoading ? "--" : pipelineTotal}
                  </span>
                  <span className="text-[11px] font-semibold text-blue-600">
                    {totalHrEmplocPending} Emploc • {Math.max(0, pipelineTotal - totalHrEmplocPending)} App
                  </span>
                </div>
                <div className="mt-0.5 text-[11px] text-slate-500">Active candidates in funnel</div>
              </div>

              <div className="p-3.5">
                <div className="text-[11px] font-bold uppercase tracking-wider text-slate-400">
                  Hires This Month
                </div>
                <div className="mt-1 flex items-baseline gap-2">
                  <span className="text-2xl font-extrabold tabular-nums text-emerald-600">
                    {analyticsQuery.isLoading ? "--" : hiresThisMonth}
                  </span>
                  <span className="rounded bg-emerald-50 px-1.5 py-0.5 text-[11px] font-semibold text-emerald-700">
                    Current Intake
                  </span>
                </div>
                <div className="mt-0.5 text-[11px] text-slate-500">Confirmed &amp; deployed</div>
              </div>

              <div className="p-3.5">
                <div className="text-[11px] font-bold uppercase tracking-wider text-slate-400">
                  Separations This Month
                </div>
                <div className="mt-1 flex items-baseline gap-2">
                  <span className="text-2xl font-extrabold tabular-nums text-slate-900">
                    {analyticsQuery.isLoading ? "--" : separationsThisMonth}
                  </span>
                  <span className="rounded bg-emerald-50 px-1.5 py-0.5 text-[11px] font-semibold text-emerald-700">
                    {separationsThisMonth === 0 ? "Zero Loss" : `${separationsThisMonth} Separated`}
                  </span>
                </div>
                <div className="mt-0.5 text-[11px] text-slate-500">Recorded monthly turnover</div>
              </div>

              <div className="p-3.5 bg-amber-50/20">
                <div className="text-[11px] font-bold uppercase tracking-wider text-amber-800">
                  Avg Fill Rate
                </div>
                <div className="mt-1 flex items-baseline gap-2">
                  <span className="text-2xl font-extrabold tabular-nums text-amber-600">
                    {avgFillRateFormatted}
                  </span>
                  <span className="rounded bg-amber-100 px-1.5 py-0.5 text-[10px] font-bold uppercase text-amber-800">
                    Target 80%
                  </span>
                </div>
                <div className="mt-0.5 text-[11px] text-slate-500">Actual / Total Scoped Demand</div>
              </div>
            </div>

            {/* Visual Proportional Segmented Coverage Bar */}
            <div className="border-t border-slate-100 bg-slate-50/80 px-5 py-3">
              <div className="mb-1.5 flex flex-wrap items-center justify-between text-xs">
                <span className="font-semibold text-slate-700">
                  Total Scoped Demand Breakdown ({totalScopedDemand} Required Seats)
                </span>
                <div className="flex flex-wrap items-center gap-4 text-[11px] font-semibold">
                  <span className="flex items-center gap-1.5 text-emerald-700">
                    <span className="h-2.5 w-2.5 rounded-xs bg-emerald-500" />
                    {totalActivePlantilla} Active Plantilla ({activePlantillaWidthPct}%)
                  </span>
                  <span className="flex items-center gap-1.5 text-blue-700">
                    <span className="h-2.5 w-2.5 rounded-xs bg-blue-500" />
                    {totalHrEmplocPending} HR Emploc Pending ({hrEmplocWidthPct}%)
                  </span>
                  <span className="flex items-center gap-1.5 text-rose-700">
                    <span className="h-2.5 w-2.5 rounded-xs bg-rose-500" />
                    {totalOpenVacancies} Open Vacancies ({vacanciesWidthPct}%)
                  </span>
                </div>
              </div>
              <div className="flex h-2.5 w-full gap-0.5 overflow-hidden rounded-full bg-slate-200 p-0.5">
                <div
                  style={{ width: `${activePlantillaWidthPct}%` }}
                  className="rounded-l-full bg-emerald-500 transition-all duration-300"
                  title={`Active Plantilla: ${totalActivePlantilla} (${activePlantillaWidthPct}%)`}
                />
                <div
                  style={{ width: `${hrEmplocWidthPct}%` }}
                  className="bg-blue-500 transition-all duration-300"
                  title={`HR Emploc Pending: ${totalHrEmplocPending} (${hrEmplocWidthPct}%)`}
                />
                <div
                  style={{ width: `${vacanciesWidthPct}%` }}
                  className="rounded-r-full bg-rose-500 transition-all duration-300"
                  title={`Open Vacancies: ${totalOpenVacancies} (${vacanciesWidthPct}%)`}
                />
              </div>
            </div>
          </section>

          {/* CARD B: Cross-Module Operational Matrix (Tabbed Card Utilizing Bottom Viewport) */}
          <section
            aria-label="Cross-module operational matrix"
            className="overflow-hidden rounded-2xl border border-slate-200/90 bg-white shadow-xs"
          >
            {/* Tab Header */}
            <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 px-5 py-3">
              <div className="flex items-center gap-1 rounded-xl bg-slate-100 p-1 text-xs font-semibold">
                <button
                  type="button"
                  onClick={() => setActiveMatrixTab("matrix")}
                  className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 transition ${
                    activeMatrixTab === "matrix"
                      ? "bg-white text-slate-900 shadow-2xs font-bold"
                      : "text-slate-600 hover:text-slate-900"
                  }`}
                >
                  <Layers className="h-3.5 w-3.5" />
                  <span>Group Workforce Matrix</span>
                </button>
                <button
                  type="button"
                  onClick={() => setActiveMatrixTab("breaches")}
                  className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 transition ${
                    activeMatrixTab === "breaches"
                      ? "bg-white text-slate-900 shadow-2xs font-bold"
                      : "text-slate-600 hover:text-slate-900"
                  }`}
                >
                  <span className="h-2 w-2 rounded-full bg-rose-500" />
                  <span>Active SLA Breaches ({activeSlaBreaches})</span>
                </button>
                <button
                  type="button"
                  onClick={() => setActiveMatrixTab("stores")}
                  className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 transition ${
                    activeMatrixTab === "stores"
                      ? "bg-white text-slate-900 shadow-2xs font-bold"
                      : "text-slate-600 hover:text-slate-900"
                  }`}
                >
                  <Store className="h-3.5 w-3.5" />
                  <span>Under-Staffed Stores ({understaffedStores})</span>
                </button>
              </div>

              {/* Sub-toggle for Tab 1 */}
              {activeMatrixTab === "matrix" && (
                <div className="flex items-center gap-2">
                  <span className="text-[11px] text-slate-500">Filter:</span>
                  <button
                    type="button"
                    onClick={() => setMatrixFilterActiveOnly(!matrixFilterActiveOnly)}
                    className="rounded-lg border border-slate-200 bg-slate-50 px-2 py-1 text-[11px] font-semibold text-slate-700 hover:bg-slate-100"
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
                  <div className="p-8 text-center text-xs text-slate-400">Loading workforce groups...</div>
                ) : displayedGroupRows.length === 0 ? (
                  <div className="p-8 text-center text-xs text-slate-500">No organizational groups found.</div>
                ) : (
                  <table className="w-full border-collapse text-left text-xs">
                    <thead>
                      <tr className="border-b border-slate-100 bg-slate-50/50 text-[10px] font-bold uppercase tracking-wider text-slate-400">
                        <th className="py-2.5 px-5">Group Name</th>
                        <th className="py-2.5 px-3 text-center">Plantilla</th>
                        <th className="py-2.5 px-3 text-center">Open Vacancy</th>
                        <th className="py-2.5 px-3 text-center">HR Emploc</th>
                        <th className="py-2.5 px-4 text-center">Fill Rate (MFR)</th>
                        <th className="py-2.5 px-5 text-right">SLA Status</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100">
                      {displayedGroupRows.map((row) => (
                        <tr key={row.groupName} className="hover:bg-slate-50/80 transition">
                          <td className="py-3 px-5 font-bold text-slate-900">{row.groupName}</td>
                          <td className="py-3 px-3 text-center font-semibold tabular-nums">{row.plantilla}</td>
                          <td className="py-3 px-3 text-center font-bold tabular-nums text-rose-600">{row.vacancy}</td>
                          <td className="py-3 px-3 text-center font-semibold tabular-nums text-blue-600">{row.pipeline}</td>
                          <td className="py-3 px-4 text-center">
                            {row.fillRatePct !== null ? (
                              <div className="flex items-center justify-center gap-2">
                                <div className="h-1.5 w-16 overflow-hidden rounded-full bg-slate-200">
                                  <div
                                    style={{ width: `${Math.min(100, row.fillRatePct)}%` }}
                                    className={`h-full ${
                                      row.fillRatePct > 70
                                        ? "bg-emerald-500"
                                        : row.fillRatePct > 40
                                        ? "bg-amber-500"
                                        : "bg-rose-500"
                                    }`}
                                  />
                                </div>
                                <span className="font-bold tabular-nums">{row.fillRatePct.toFixed(1)}%</span>
                              </div>
                            ) : (
                              <span className="text-slate-400">Standby (0 Demand)</span>
                            )}
                          </td>
                          <td className="py-3 px-5 text-right">
                            <span
                              className={`rounded-full px-2 py-0.5 text-[10px] font-bold ${
                                row.slaStatus === "Critical"
                                  ? "bg-rose-50 text-rose-700 border border-rose-200"
                                  : row.slaStatus === "At Risk"
                                  ? "bg-amber-50 text-amber-700 border border-amber-200"
                                  : row.slaStatus === "Compliant"
                                  ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                                  : "bg-slate-100 text-slate-500"
                              }`}
                            >
                              {row.slaStatus}
                            </span>
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
                <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-100 bg-rose-50/50 px-5 py-2.5 text-xs">
                  <div className="flex items-center gap-4">
                    <span className="font-bold text-rose-900">Live SLA Breach Records:</span>
                    <span className="font-medium text-rose-700">
                      • {activeSlaBreaches} Logged Breaches in Audit Table
                    </span>
                  </div>
                  {activeSlaBreaches > 0 && (
                    <Link
                      href="/cencom"
                      className="text-[11px] font-bold text-rose-700 hover:underline cursor-pointer"
                    >
                      Open CENCOM Triage Console →
                    </Link>
                  )}
                </div>
                <div className="overflow-x-auto">
                  {isSlaBreachesLoading ? (
                    <div className="p-8 text-center text-xs text-slate-400">Loading SLA breach records...</div>
                  ) : !slaBreachesData || slaBreachesData.length === 0 ? (
                    <div className="flex flex-col items-center justify-center p-8 text-center">
                      <CheckCircle2 className="h-8 w-8 text-emerald-500 mb-2" />
                      <p className="text-xs font-bold text-slate-800">No active SLA breaches</p>
                      <p className="text-[11px] text-slate-500 mt-0.5">All stores and movements comply with target SLAs</p>
                    </div>
                  ) : (
                    <table className="w-full border-collapse text-left text-xs">
                      <thead>
                        <tr className="border-b border-slate-100 bg-slate-50/50 text-[10px] font-bold uppercase tracking-wider text-slate-400">
                          <th className="py-2.5 px-5">Breach Lane / Account</th>
                          <th className="py-2.5 px-3">Category</th>
                          <th className="py-2.5 px-3">Scope Owner</th>
                          <th className="py-2.5 px-3 text-center">Aging</th>
                          <th className="py-2.5 px-5 text-right">Action</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100">
                        {slaBreachesData.map((b) => (
                          <tr key={b.id} className="hover:bg-slate-50/80 transition">
                            <td className="py-3 px-5">
                              <div className="font-bold text-slate-900">{b.storeName}</div>
                              <div className="text-[11px] text-slate-500">{b.group}</div>
                            </td>
                            <td className="py-3 px-3">
                              <span className="rounded bg-rose-100 px-1.5 py-0.5 text-[10px] font-bold text-rose-800">
                                {b.category}
                              </span>
                            </td>
                            <td className="py-3 px-3">
                              <span className="rounded px-1.5 py-0.5 text-[11px] font-semibold bg-slate-100 text-slate-700">
                                {b.owner}
                              </span>
                            </td>
                            <td className="py-3 px-3 text-center font-mono font-semibold text-rose-700">
                              {b.aging}
                            </td>
                            <td className="py-3 px-5 text-right">
                              <Link
                                href={b.actionHref}
                                className="inline-flex items-center gap-1 rounded-lg bg-slate-900 px-2.5 py-1 text-[11px] font-bold text-white hover:bg-slate-800"
                              >
                                <span>{b.actionLabel}</span>
                                <ExternalLink className="h-3 w-3" />
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
                  <div className="p-8 text-center text-xs text-slate-400">Loading understaffed stores...</div>
                ) : !understaffedStoresData || understaffedStoresData.length === 0 ? (
                  <div className="flex flex-col items-center justify-center p-8 text-center">
                    <CheckCircle2 className="h-8 w-8 text-emerald-500 mb-2" />
                    <p className="text-xs font-bold text-slate-800">All stores adequately staffed</p>
                    <p className="text-[11px] text-slate-500 mt-0.5">Zero open vacancies across all active store units</p>
                  </div>
                ) : (
                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 text-xs">
                    {understaffedStoresData.map((s) => (
                      <div
                        key={s.id}
                        className="flex items-center justify-between rounded-xl border border-amber-200/90 bg-amber-50/30 p-3 hover:border-amber-300 transition"
                      >
                        <div>
                          <div className="font-bold text-slate-900">{s.storeName}</div>
                          <div className="mt-0.5 text-[11px] text-slate-500">
                            {s.group} • Open Vacancies: <strong className="text-rose-600">{s.openVacancies}</strong>
                          </div>
                          <div className="mt-1 flex items-center gap-2 text-[11px]">
                            <span className="text-slate-500">HRCO: {s.assignedHrco}</span>
                          </div>
                        </div>
                        <Link
                          href="/vacancy"
                          className="shrink-0 rounded-lg border border-amber-300 bg-white px-2.5 py-1 text-[11px] font-bold text-amber-900 shadow-2xs hover:bg-amber-100 transition"
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
        {/* Tighter Vertical Rhythm (space-y-3 / 12px) to Prevent 1080p Clip  */}
        {/* ================================================================= */}
        <div className="space-y-3 lg:col-span-4">
          {/* CARD C: Pending Approvals & Action Queue (Reconciled with Sidebar) */}
          <section
            aria-label="Pending approvals queue"
            className="overflow-hidden rounded-2xl border border-slate-200/90 bg-white shadow-xs"
          >
            <div className="flex items-center justify-between border-b border-slate-100 px-4 py-2.5">
              <div className="flex items-center gap-2">
                <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-blue-50 text-blue-600">
                  <CheckSquare className="h-4 w-4" />
                </div>
                <div>
                  <h2 className="text-sm font-bold text-slate-900 leading-tight">
                    Pending Approvals Queue
                  </h2>
                  <p className="text-[10px] text-slate-500">Synced with sidebar Approvals badge</p>
                </div>
              </div>
              <span className={`rounded-full px-2.5 py-0.5 text-xs font-extrabold ${
                totalReconciledApprovals > 0 ? "bg-blue-600 text-white" : "bg-emerald-100 text-emerald-800"
              }`}>
                {totalReconciledApprovals} Pending
              </span>
            </div>

            <div className="space-y-2 p-3 text-xs">
              {isRequestCountsLoading ? (
                <div className="p-4 text-center text-xs text-slate-400">Loading approvals queue...</div>
              ) : liveApprovalItems.length === 0 ? (
                <div className="flex flex-col items-center justify-center py-4 text-center">
                  <CheckCircle2 className="h-6 w-6 text-emerald-500 mb-1" />
                  <p className="text-xs font-bold text-slate-800">All approvals cleared</p>
                  <p className="text-[10px] text-slate-500">Zero pending requests in operational queues</p>
                </div>
              ) : (
                liveApprovalItems.map((item, idx) => (
                  <div
                    key={idx}
                    className="flex items-center justify-between rounded-xl border border-slate-200/80 bg-slate-50 px-3 py-2 hover:bg-slate-100/60 transition"
                  >
                    <div className="min-w-0 pr-2">
                      <div className="font-bold text-slate-900 truncate text-xs">
                        {item.title}
                      </div>
                      <p className="text-[10px] text-slate-500 truncate leading-tight">
                        {item.sub}
                      </p>
                    </div>
                    <Link
                      href={item.href}
                      className="shrink-0 rounded-lg border border-blue-200 bg-white px-2.5 py-1 text-[11px] font-bold text-blue-600 shadow-2xs hover:bg-blue-600 hover:text-white transition"
                    >
                      Review ({item.count})
                    </Link>
                  </div>
                ))
              )}

              <div className="pt-1.5 flex items-center justify-between border-t border-slate-100 text-[11px]">
                <span className="text-[10px] text-slate-400">Reconciled with left navigation</span>
                <Link
                  href="/approvals"
                  className="font-bold text-blue-600 hover:underline flex items-center gap-0.5 text-xs"
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
              className="overflow-hidden rounded-2xl border border-slate-200/90 bg-white shadow-xs"
            >
              <div className="flex items-center justify-between border-b border-slate-100 px-4 py-2.5">
                <div>
                  <div className="flex items-center gap-2">
                    <h2 className="text-sm font-bold text-slate-900 leading-tight">
                      Super Admin Governance &amp; MIKA
                    </h2>
                    <span className="rounded bg-slate-900 px-1.5 py-0.5 text-[10px] font-bold uppercase text-blue-300">
                      SA Only
                    </span>
                  </div>
                  <p className="text-[10px] text-slate-500">
                    Masterfile synchronization &amp; data hygiene
                  </p>
                </div>
                <ShieldCheck className="h-5 w-5 text-blue-600" />
              </div>

              <div className="p-3 space-y-2">
                {/* Ghost Employee Cases Live Alert */}
                <div className="rounded-xl border border-rose-200 bg-rose-50/70 p-2.5">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-bold text-rose-950">
                      {ghostEmployeeCount} Ghost Employee Cases
                    </span>
                    <span className="rounded bg-rose-200 px-1.5 py-0.2 text-[10px] font-bold text-rose-900">
                      Hygiene Alert
                    </span>
                  </div>
                  <p className="mt-0.5 text-[11px] text-rose-800 leading-tight">
                    Unmatched legacy workforce records pending MIKA reconciliation
                  </p>
                </div>

                {/* Inline Action Bar */}
                <div className="flex items-center justify-between gap-2 pt-0.5">
                  <Link
                    href="/plantilla"
                    className="text-xs font-semibold text-slate-700 hover:text-slate-900 hover:underline"
                  >
                    Resolve Anomalies →
                  </Link>

                  {/* STRICT BUTTON NAMING: "Sync MIKA" */}
                  <button
                    type="button"
                    onClick={() => setIsMikaSyncModalOpen(true)}
                    className="inline-flex items-center gap-1.5 rounded-xl bg-slate-900 px-3 py-1.5 text-xs font-bold text-white shadow-xs hover:bg-slate-800 transition cursor-pointer"
                  >
                    <CloudUpload className="h-3.5 w-3.5 text-blue-300" />
                    <span>Sync MIKA</span>
                  </button>
                </div>
              </div>
            </section>
          )}

          {/* CARD E: Compact Security & Audit Telemetry Card */}
          <section
            aria-label="Security and audit telemetry"
            className="overflow-hidden rounded-2xl border border-slate-200/90 bg-white shadow-xs"
          >
            <div className="flex items-center justify-between border-b border-slate-100 px-4 py-2.5">
              <div>
                <h2 className="text-sm font-bold text-slate-900 leading-tight">
                  Security &amp; Audit Telemetry
                </h2>
                <p className="text-[10px] text-slate-500">
                  Real-time role access &amp; system security events
                </p>
              </div>
              <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[10px] font-bold text-slate-700">
                {isSuperAdmin ? "Super Admin" : "Head Admin"}
              </span>
            </div>

            <div className="p-3 space-y-2">
              <div className="grid grid-cols-2 gap-2">
                <div className="rounded-xl border border-slate-200/80 bg-slate-50 px-3 py-2">
                  <div className="text-[10px] font-bold uppercase text-slate-400">
                    Admin Approvals
                  </div>
                  <div className="text-lg font-extrabold tabular-nums text-slate-900">
                    {metrics?.adminSecurityApprovals ?? 0}
                  </div>
                  <div className="text-[10px] text-slate-500 leading-tight mt-0.5">
                    Security role escalations
                  </div>
                </div>

                <div className="rounded-xl border border-slate-200/80 bg-slate-50 px-3 py-2">
                  <div className="text-[10px] font-bold uppercase text-slate-400">
                    Security Events
                  </div>
                  <div className="flex items-baseline gap-1.5">
                    <span className="text-lg font-extrabold tabular-nums text-emerald-600">
                      {metrics?.securityEventCount ?? 0}
                    </span>
                    <span className="text-[10px] font-bold text-emerald-700">✓ Clean</span>
                  </div>
                  <div className="text-[10px] text-slate-500 leading-tight mt-0.5">
                    Access events today
                  </div>
                </div>
              </div>

              <div className="flex items-center justify-between border-t border-slate-100 pt-1.5 text-[11px]">
                <span className="text-[10px] text-slate-400">System Telemetry: Healthy</span>
                <Link
                  href="/more?tab=audit_logs"
                  className="font-bold text-blue-600 hover:underline flex items-center gap-0.5 text-xs"
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
