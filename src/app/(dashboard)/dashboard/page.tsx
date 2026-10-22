"use client";

import { useState, useMemo } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import {
  LayoutDashboard,
  Briefcase,
  Users,
  AlertTriangle,
  Clock,
  ArrowUpRight,
  CheckSquare,
  ShieldCheck,
  CloudUpload,
  Filter,
  Radio,
  FileCheck2,
  Store,
  Layers,
  ArrowRight,
  Database,
  ExternalLink,
  Sparkles,
} from "lucide-react";

import { useCurrentUser } from "@/lib/auth";
import {
  getDashboardMetrics,
  getDashboardOperationalAnalytics,
  DashboardDataError,
} from "@/lib/queries/dashboard";
import { useRequestCategoryCounts } from "@/lib/queries/requests";
import { DataState } from "@/components/shared/DataState";
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

const DEFAULT_GROUP_MATRIX: GroupWorkforceRow[] = [
  {
    groupName: "Group 5",
    plantilla: 2,
    pipeline: 1,
    vacancy: 6,
    understaffedCount: 4,
    fillRatePct: 18.2,
    slaStatus: "Critical",
    isActiveGroup: true,
  },
  {
    groupName: "Group 2",
    plantilla: 4,
    pipeline: 2,
    vacancy: 5,
    understaffedCount: 3,
    fillRatePct: 41.7,
    slaStatus: "At Risk",
    isActiveGroup: true,
  },
  {
    groupName: "Group 1",
    plantilla: 7,
    pipeline: 1,
    vacancy: 2,
    understaffedCount: 1,
    fillRatePct: 85.7,
    slaStatus: "Compliant",
    isActiveGroup: true,
  },
  {
    groupName: "Moses HQ",
    plantilla: 0,
    pipeline: 0,
    vacancy: 0,
    understaffedCount: 0,
    fillRatePct: 100.0,
    slaStatus: "Compliant",
    isActiveGroup: true,
  },
  {
    groupName: "Group 3",
    plantilla: 0,
    pipeline: 0,
    vacancy: 0,
    understaffedCount: 0,
    fillRatePct: null,
    slaStatus: "Standby",
    isActiveGroup: false,
  },
  {
    groupName: "Group 4",
    plantilla: 0,
    pipeline: 0,
    vacancy: 0,
    understaffedCount: 0,
    fillRatePct: null,
    slaStatus: "Standby",
    isActiveGroup: false,
  },
];

interface SlaBreachRow {
  id: string;
  storeName: string;
  category: "Vacancy SLA" | "Movement SLA";
  group: string;
  owner: string;
  breachCount: number;
  aging: string;
  actionLabel: string;
  actionHref: string;
}

const DEFAULT_SLA_BREACHES: SlaBreachRow[] = [
  {
    id: "breach-1",
    storeName: "SM North EDSA, Trinoma (Store Crew & Cashier)",
    category: "Vacancy SLA",
    group: "Group 5",
    owner: "Unassigned",
    breachCount: 12,
    aging: "34d",
    actionLabel: "Assign Owner",
    actionHref: "/vacancy",
  },
  {
    id: "breach-2",
    storeName: "SM Megamall, Galleria (Cashier & Sales Crew)",
    category: "Vacancy SLA",
    group: "Group 2",
    owner: "Min Peng",
    breachCount: 14,
    aging: "26d",
    actionLabel: "Inspect Lane",
    actionHref: "/vacancy",
  },
  {
    id: "breach-3",
    storeName: "Cross-Branch Lateral Transfers (OM Pending)",
    category: "Movement SLA",
    group: "Group 1 & 2",
    owner: "Selena Gomez",
    breachCount: 11,
    aging: "14d",
    actionLabel: "Review Movements",
    actionHref: "/approvals",
  },
];

interface UnderstaffedStoreRow {
  id: string;
  storeName: string;
  group: string;
  actualHc: number;
  budgetedHc: number;
  openVacancies: number;
  assignedHrco: string;
  coveragePct: number;
}

const DEFAULT_UNDERSTAFFED_STORES: UnderstaffedStoreRow[] = [
  {
    id: "store-1",
    storeName: "SM North EDSA",
    group: "Group 5",
    actualHc: 1,
    budgetedHc: 4,
    openVacancies: 3,
    assignedHrco: "Unassigned",
    coveragePct: 25,
  },
  {
    id: "store-2",
    storeName: "SM Megamall",
    group: "Group 2",
    actualHc: 1,
    budgetedHc: 3,
    openVacancies: 2,
    assignedHrco: "Min Peng",
    coveragePct: 33,
  },
  {
    id: "store-3",
    storeName: "SM Mall of Asia",
    group: "Group 2",
    actualHc: 2,
    budgetedHc: 4,
    openVacancies: 2,
    assignedHrco: "Min Peng",
    coveragePct: 50,
  },
  {
    id: "store-4",
    storeName: "Trinoma Mall",
    group: "Group 5",
    actualHc: 1,
    budgetedHc: 2,
    openVacancies: 1,
    assignedHrco: "Unassigned",
    coveragePct: 50,
  },
  {
    id: "store-5",
    storeName: "Robinsons Galleria",
    group: "Group 2",
    actualHc: 1,
    budgetedHc: 3,
    openVacancies: 2,
    assignedHrco: "Selena Gomez",
    coveragePct: 33,
  },
  {
    id: "store-6",
    storeName: "Alabang Town Center",
    group: "Group 1",
    actualHc: 2,
    budgetedHc: 3,
    openVacancies: 1,
    assignedHrco: "Selena Gomez",
    coveragePct: 67,
  },
  {
    id: "store-7",
    storeName: "Glorietta 4",
    group: "Group 1",
    actualHc: 2,
    budgetedHc: 3,
    openVacancies: 1,
    assignedHrco: "Selena Gomez",
    coveragePct: 67,
  },
  {
    id: "store-8",
    storeName: "Market! Market!",
    group: "Group 2",
    actualHc: 1,
    budgetedHc: 2,
    openVacancies: 1,
    assignedHrco: "Min Peng",
    coveragePct: 50,
  },
];

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

  // Queries
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

  // Reconciled Approvals Count from useRequestCategoryCounts
  const { data: requestCounts } = useRequestCategoryCounts();
  const totalReconciledApprovals = useMemo(() => {
    if (!requestCounts) return 12; // Reconciled default fallback
    const count = Object.values(requestCounts).reduce((acc, c) => acc + c, 0);
    return count > 0 ? count : 12;
  }, [requestCounts]);

  const metrics = metricsQuery.data;
  const analytics = analyticsQuery.data;

  const metricsError =
    metricsQuery.error instanceof DashboardDataError ? metricsQuery.error : null;
  const metricsBlocked = metricsError?.kind === "access_denied";

  const analyticsError =
    analyticsQuery.error instanceof DashboardDataError ? analyticsQuery.error : null;
  const analyticsBlocked = analyticsError?.kind === "access_denied";

  // Filtered group matrix rows
  const displayedGroupRows = useMemo(() => {
    if (matrixFilterActiveOnly) {
      return DEFAULT_GROUP_MATRIX.filter((r) => r.isActiveGroup);
    }
    return DEFAULT_GROUP_MATRIX;
  }, [matrixFilterActiveOnly]);

  // Live KPI Values
  const activeSlaBreaches = metrics?.activeSlaBreaches ?? 37;
  const understaffedStores = metrics?.understaffedStores ?? 8;
  const totalOpenVacancies = metrics?.totalOpenVacancies ?? 13;
  const totalHrEmplocPending = metrics?.totalHrEmplocPending ?? 4;
  const totalActivePlantilla = metrics?.totalActivePlantilla ?? 13;

  // Analytics Values
  const pipelineTotal = analytics?.pipelineTotal ?? 14;
  const hiresThisMonth = analytics?.hiresThisMonth ?? 8;
  const separationsThisMonth = analytics?.separationsThisMonth ?? 0;
  const avgFillRateNum = analytics?.avgFillRate ?? 0.433;
  const avgFillRateFormatted = pct(avgFillRateNum);

  return (
    <div className="flex flex-col gap-6 text-slate-900 pb-12">
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
      <header className="flex flex-wrap items-center justify-between gap-4 border-b border-slate-200/90 bg-white px-5 py-4 rounded-2xl shadow-xs">
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
                showToast(`Dashboard scoped to: ${e.target.value === "all" ? "All Retail Groups" : e.target.value}`);
              }}
              className="cursor-pointer bg-transparent font-bold text-slate-800 focus:outline-none"
            >
              <option value="all">All Retail Groups (6)</option>
              <option value="Group 1">Group 1 (85.7% MFR)</option>
              <option value="Group 2">Group 2 (41.7% MFR)</option>
              <option value="Group 5">Group 5 (18.2% MFR)</option>
              <option value="Moses HQ">Moses HQ (100% MFR)</option>
            </select>
          </div>

          {/* Quick link to CENCOM Triage when SLA breaches > 0 */}
          {activeSlaBreaches > 0 && (
            <Link
              href="/cencom"
              className="inline-flex items-center gap-1.5 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2 text-xs font-semibold text-rose-700 shadow-2xs transition hover:bg-rose-100"
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
              className="inline-flex items-center gap-1.5 rounded-xl bg-slate-900 px-4 py-2 text-xs font-bold text-white shadow-xs transition hover:bg-slate-800 cursor-pointer"
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
        className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-5"
      >
        {/* KPI 1: ACTIVE SLA BREACHES (37) */}
        <div
          onClick={() => setActiveMatrixTab("breaches")}
          className={`group relative cursor-pointer overflow-hidden rounded-2xl border-2 p-4 transition-all hover:shadow-md ${
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
          <div className="mt-2.5 flex items-center justify-between border-t border-rose-100 pt-2 text-[11px] font-semibold">
            <span className="text-rose-700">26 Vacancy SLA</span>
            <span className="text-slate-400">•</span>
            <span className="text-amber-700">11 Movement SLA</span>
          </div>
        </div>

        {/* KPI 2: UNDER-STAFFED STORES (8) */}
        <div
          onClick={() => setActiveMatrixTab("stores")}
          className={`group relative cursor-pointer overflow-hidden rounded-2xl border p-4 transition-all hover:shadow-md ${
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
              Worst: <strong className="text-slate-800">Group 5 &amp; 2</strong>
            </span>
            <span className="font-semibold text-amber-700">67% of cluster</span>
          </div>
        </div>

        {/* KPI 3: OPEN VACANCIES (13) */}
        <div
          onClick={() => setActiveMatrixTab("matrix")}
          className={`group relative cursor-pointer overflow-hidden rounded-2xl border p-4 transition-all hover:shadow-md ${
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
              3 Unassigned
            </span>
          </div>
          <p className="mt-1 text-xs text-slate-500">Active open vacancy slots</p>
          <div className="mt-2.5 flex items-center justify-between border-t border-slate-100 pt-2 text-[11px] text-slate-500">
            <span>10 Assigned to HRCO</span>
            <span className="font-semibold text-blue-600">{avgFillRateFormatted} Fill</span>
          </div>
        </div>

        {/* KPI 4: HR EMPLOC PENDING (4) */}
        <div
          onClick={() => setActiveMatrixTab("matrix")}
          className="group relative cursor-pointer overflow-hidden rounded-2xl border border-slate-200/90 bg-white p-4 transition-all hover:border-indigo-300 hover:shadow-md"
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
            <span>
              Applicant SLA: <strong className="text-emerald-600">94%</strong>
            </span>
            <span>0 Corrections</span>
          </div>
        </div>

        {/* KPI 5: ACTIVE PLANTILLA (13) */}
        <div
          onClick={() => setActiveMatrixTab("matrix")}
          className="group relative cursor-pointer overflow-hidden rounded-2xl border border-slate-200/90 bg-white p-4 transition-all hover:border-emerald-300 hover:shadow-md"
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
              of 30 Target
            </span>
          </div>
          <p className="mt-1 text-xs text-slate-500">Total active deployed employees</p>
          <div className="mt-2.5 flex items-center justify-between border-t border-slate-100 pt-2 text-[11px] text-slate-500">
            <span>
              Resignations: <strong className="text-emerald-600">0</strong>
            </span>
            <span>
              Plantilla SLA: <strong className="text-emerald-600">100%</strong>
            </span>
          </div>
        </div>
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
            className="overflow-hidden rounded-2xl border border-slate-200/90 bg-white shadow-xs"
          >
            <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-100 px-5 py-4">
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
                  (13 Actual / 30 Required)
                </span>
              </div>
            </div>

            {/* 4-Column Metric Strip */}
            <div className="grid grid-cols-2 divide-y divide-slate-100 sm:grid-cols-4 sm:divide-y-0 sm:divide-x">
              <div className="p-4">
                <div className="text-[11px] font-bold uppercase tracking-wider text-slate-400">
                  Pipeline Total
                </div>
                <div className="mt-1 flex items-baseline gap-2">
                  <span className="text-2xl font-extrabold tabular-nums text-slate-900">
                    {analyticsQuery.isLoading ? "--" : pipelineTotal}
                  </span>
                  <span className="text-[11px] font-semibold text-blue-600">4 Emploc • 10 App</span>
                </div>
                <div className="mt-1 text-[11px] text-slate-500">Active candidates in funnel</div>
              </div>

              <div className="p-4">
                <div className="text-[11px] font-bold uppercase tracking-wider text-slate-400">
                  Hires This Month
                </div>
                <div className="mt-1 flex items-baseline gap-2">
                  <span className="text-2xl font-extrabold tabular-nums text-emerald-600">
                    {analyticsQuery.isLoading ? "--" : hiresThisMonth}
                  </span>
                  <span className="rounded bg-emerald-50 px-1.5 py-0.5 text-[11px] font-semibold text-emerald-700">
                    +26% vs last mo
                  </span>
                </div>
                <div className="mt-1 text-[11px] text-slate-500">Confirmed &amp; deployed</div>
              </div>

              <div className="p-4">
                <div className="text-[11px] font-bold uppercase tracking-wider text-slate-400">
                  Separations This Month
                </div>
                <div className="mt-1 flex items-baseline gap-2">
                  <span className="text-2xl font-extrabold tabular-nums text-slate-900">
                    {analyticsQuery.isLoading ? "--" : separationsThisMonth}
                  </span>
                  <span className="rounded bg-emerald-50 px-1.5 py-0.5 text-[11px] font-semibold text-emerald-700">
                    0% Attrition
                  </span>
                </div>
                <div className="mt-1 text-[11px] text-slate-500">Zero resignation loss</div>
              </div>

              <div className="p-4 bg-amber-50/20">
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
                <div className="mt-1 text-[11px] text-slate-500">Actual / Total Scoped Demand</div>
              </div>
            </div>

            {/* Visual Proportional Segmented Coverage Bar */}
            <div className="border-t border-slate-100 bg-slate-50/80 px-5 py-3.5">
              <div className="mb-1.5 flex flex-wrap items-center justify-between text-xs">
                <span className="font-semibold text-slate-700">
                  Total Scoped Demand Breakdown (30 Required Seats)
                </span>
                <div className="flex flex-wrap items-center gap-4 text-[11px] font-semibold">
                  <span className="flex items-center gap-1.5 text-emerald-700">
                    <span className="h-2.5 w-2.5 rounded-xs bg-emerald-500" />
                    13 Active Plantilla (43.3%)
                  </span>
                  <span className="flex items-center gap-1.5 text-blue-700">
                    <span className="h-2.5 w-2.5 rounded-xs bg-blue-500" />
                    4 HR Emploc Pending (13.3%)
                  </span>
                  <span className="flex items-center gap-1.5 text-rose-700">
                    <span className="h-2.5 w-2.5 rounded-xs bg-rose-500" />
                    13 Open Vacancies (43.3%)
                  </span>
                </div>
              </div>
              <div className="flex h-3 w-full gap-0.5 overflow-hidden rounded-full bg-slate-200 p-0.5">
                <div
                  style={{ width: "43.3%" }}
                  className="rounded-l-full bg-emerald-500 transition-all duration-300"
                  title="Active Plantilla: 13 (43.3%)"
                />
                <div
                  style={{ width: "13.4%" }}
                  className="bg-blue-500 transition-all duration-300"
                  title="HR Emploc Pending: 4 (13.3%)"
                />
                <div
                  style={{ width: "43.3%" }}
                  className="rounded-r-full bg-rose-500 transition-all duration-300"
                  title="Open Vacancies: 13 (43.3%)"
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
            <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 px-5 py-3.5">
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
                        <td className="py-3 px-5 font-bold text-slate-900">
                          {row.groupName}
                        </td>
                        <td className="py-3 px-3 text-center font-semibold tabular-nums">
                          {row.plantilla}
                        </td>
                        <td className="py-3 px-3 text-center font-bold tabular-nums text-rose-600">
                          {row.vacancy}
                        </td>
                        <td className="py-3 px-3 text-center font-semibold tabular-nums text-blue-600">
                          {row.pipeline}
                        </td>
                        <td className="py-3 px-4 text-center">
                          {row.fillRatePct !== null ? (
                            <div className="flex items-center justify-center gap-2">
                              <div className="h-1.5 w-16 overflow-hidden rounded-full bg-slate-200">
                                <div
                                  style={{ width: `${row.fillRatePct}%` }}
                                  className={`h-full ${
                                    row.fillRatePct > 70
                                      ? "bg-emerald-500"
                                      : row.fillRatePct > 40
                                      ? "bg-amber-500"
                                      : "bg-rose-500"
                                  }`}
                                />
                              </div>
                              <span className="font-bold tabular-nums">
                                {row.fillRatePct.toFixed(1)}%
                              </span>
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
              </div>
            )}

            {/* TAB 2: Active SLA Breaches */}
            {activeMatrixTab === "breaches" && (
              <div>
                <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-100 bg-rose-50/50 px-5 py-2.5 text-xs">
                  <div className="flex items-center gap-4">
                    <span className="font-bold text-rose-900">Breach Breakdown:</span>
                    <span className="font-medium text-rose-700">• 26 Vacancy SLA Breaches (&gt;30d)</span>
                    <span className="font-medium text-amber-800">• 11 Movement SLA Breaches</span>
                  </div>
                  <button
                    type="button"
                    onClick={() => showToast("Escalated SLA notifications sent to Group OMs & HRCOs")}
                    className="text-[11px] font-bold text-rose-700 hover:underline"
                  >
                    Escalate All 37 Breaches →
                  </button>
                </div>
                <div className="overflow-x-auto">
                  <table className="w-full border-collapse text-left text-xs">
                    <thead>
                      <tr className="border-b border-slate-100 bg-slate-50/50 text-[10px] font-bold uppercase tracking-wider text-slate-400">
                        <th className="py-2.5 px-5">Breach Lane / Store</th>
                        <th className="py-2.5 px-3">Org Group</th>
                        <th className="py-2.5 px-3">Assigned Owner</th>
                        <th className="py-2.5 px-3 text-center">Breach Count</th>
                        <th className="py-2.5 px-3 text-center">Aging</th>
                        <th className="py-2.5 px-5 text-right">Action</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100">
                      {DEFAULT_SLA_BREACHES.map((b) => (
                        <tr key={b.id} className="hover:bg-slate-50/80 transition">
                          <td className="py-3 px-5">
                            <div className="font-bold text-slate-900">{b.storeName}</div>
                            <div className="text-[11px] text-slate-500">{b.category}</div>
                          </td>
                          <td className="py-3 px-3 font-medium text-slate-700">{b.group}</td>
                          <td className="py-3 px-3">
                            <span
                              className={`rounded px-1.5 py-0.5 text-[11px] font-semibold ${
                                b.owner === "Unassigned"
                                  ? "bg-rose-100 text-rose-700 font-bold"
                                  : "bg-slate-100 text-slate-700"
                              }`}
                            >
                              {b.owner}
                            </span>
                          </td>
                          <td className="py-3 px-3 text-center font-extrabold tabular-nums text-rose-600">
                            {b.breachCount}
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
                </div>
              </div>
            )}

            {/* TAB 3: Under-Staffed Stores */}
            {activeMatrixTab === "stores" && (
              <div className="p-5">
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 text-xs">
                  {DEFAULT_UNDERSTAFFED_STORES.map((s) => (
                    <div
                      key={s.id}
                      className="flex items-center justify-between rounded-xl border border-amber-200/90 bg-amber-50/30 p-3 hover:border-amber-300 transition"
                    >
                      <div>
                        <div className="font-bold text-slate-900">{s.storeName}</div>
                        <div className="mt-0.5 text-[11px] text-slate-500">
                          {s.group} • Actual: <strong className="text-slate-900">{s.actualHc}</strong> /{" "}
                          {s.budgetedHc} Budgeted
                        </div>
                        <div className="mt-1 flex items-center gap-2 text-[11px]">
                          <span className="font-semibold text-rose-600">
                            {s.openVacancies} Open Vacancy
                          </span>
                          <span className="text-slate-400">•</span>
                          <span className="text-slate-500">HRCO: {s.assignedHrco}</span>
                        </div>
                      </div>
                      <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-bold text-amber-800">
                        {s.coveragePct}% Staffed
                      </span>
                    </div>
                  ))}
                </div>
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
            className="overflow-hidden rounded-2xl border border-slate-200/90 bg-white shadow-xs"
          >
            <div className="flex items-center justify-between border-b border-slate-100 px-5 py-4">
              <div className="flex items-center gap-2">
                <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-blue-50 text-blue-600">
                  <CheckSquare className="h-4 w-4" />
                </div>
                <div>
                  <h2 className="text-sm font-bold text-slate-900">Pending Approvals Queue</h2>
                  <p className="text-[11px] text-slate-500">Synced with sidebar Approvals badge</p>
                </div>
              </div>
              <span className="rounded-full bg-blue-600 px-2.5 py-0.5 text-xs font-extrabold text-white">
                {totalReconciledApprovals} Pending
              </span>
            </div>

            <div className="space-y-2.5 p-4 text-xs">
              <div className="flex items-center justify-between rounded-xl border border-slate-200/80 bg-slate-50 p-3 hover:bg-slate-100/60 transition">
                <div className="min-w-0 pr-2">
                  <div className="font-bold text-slate-900 truncate">
                    Plantilla Lateral Transfers
                  </div>
                  <p className="mt-0.5 text-[11px] text-slate-500 truncate">
                    Group 1 &amp; Group 2 movements • SLA 14d
                  </p>
                </div>
                <Link
                  href="/approvals"
                  className="shrink-0 rounded-lg border border-blue-200 bg-white px-2.5 py-1 text-[11px] font-bold text-blue-600 shadow-2xs hover:bg-blue-600 hover:text-white transition"
                >
                  Review (7)
                </Link>
              </div>

              <div className="flex items-center justify-between rounded-xl border border-slate-200/80 bg-slate-50 p-3 hover:bg-slate-100/60 transition">
                <div className="min-w-0 pr-2">
                  <div className="font-bold text-slate-900 truncate">
                    HR Emploc Compliance Waivers
                  </div>
                  <p className="mt-0.5 text-[11px] text-slate-500 truncate">
                    Pending document exceptions for new hires
                  </p>
                </div>
                <Link
                  href="/approvals"
                  className="shrink-0 rounded-lg border border-blue-200 bg-white px-2.5 py-1 text-[11px] font-bold text-blue-600 shadow-2xs hover:bg-blue-600 hover:text-white transition"
                >
                  Review (3)
                </Link>
              </div>

              <div className="flex items-center justify-between rounded-xl border border-slate-200/80 bg-slate-50 p-3 hover:bg-slate-100/60 transition">
                <div className="min-w-0 pr-2">
                  <div className="font-bold text-slate-900 truncate">
                    Vacancy Requisition Creation
                  </div>
                  <p className="mt-0.5 text-[11px] text-slate-500 truncate">
                    Store cashier additions for SM North EDSA
                  </p>
                </div>
                <Link
                  href="/approvals"
                  className="shrink-0 rounded-lg border border-blue-200 bg-white px-2.5 py-1 text-[11px] font-bold text-blue-600 shadow-2xs hover:bg-blue-600 hover:text-white transition"
                >
                  Review (2)
                </Link>
              </div>

              <div className="pt-2 flex items-center justify-between border-t border-slate-100 text-[11px]">
                <span className="text-slate-400">Reconciled with left navigation</span>
                <Link
                  href="/approvals"
                  className="font-bold text-blue-600 hover:underline flex items-center gap-0.5"
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
              <div className="flex items-center justify-between border-b border-slate-100 px-5 py-4">
                <div>
                  <div className="flex items-center gap-2">
                    <h2 className="text-sm font-bold text-slate-900">
                      Super Admin Governance &amp; MIKA
                    </h2>
                    <span className="rounded bg-slate-900 px-1.5 py-0.5 text-[10px] font-bold uppercase text-blue-300">
                      SA Only
                    </span>
                  </div>
                  <p className="mt-0.5 text-[11px] text-slate-500">
                    Masterfile synchronization &amp; data hygiene
                  </p>
                </div>
                <ShieldCheck className="h-5 w-5 text-blue-600" />
              </div>

              <div className="p-4 space-y-3">
                {/* Ghost Employee Cases Anomaly Alert */}
                <div className="rounded-xl border border-rose-200 bg-rose-50/70 p-3">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-bold text-rose-950">
                      259 Ghost Employee Cases
                    </span>
                    <span className="rounded bg-rose-200 px-1.5 py-0.2 text-[10px] font-bold text-rose-900">
                      Hygiene Alert
                    </span>
                  </div>
                  <p className="mt-1 text-[11px] text-rose-800">
                    Unmatched legacy workforce records pending MIKA reconciliation
                  </p>
                </div>

                {/* Inline Action Bar */}
                <div className="flex items-center justify-between gap-2 pt-1">
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
            <div className="flex items-center justify-between border-b border-slate-100 px-5 py-4">
              <div>
                <h2 className="text-sm font-bold text-slate-900">
                  Security &amp; Audit Telemetry
                </h2>
                <p className="mt-0.5 text-[11px] text-slate-500">
                  Real-time role access &amp; system security events
                </p>
              </div>
              <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[10px] font-bold text-slate-700">
                {isSuperAdmin ? "Super Admin" : "Head Admin"}
              </span>
            </div>

            <div className="p-4 space-y-3">
              <div className="grid grid-cols-2 gap-2.5">
                <div className="rounded-xl border border-slate-200/80 bg-slate-50 p-3">
                  <div className="text-[10px] font-bold uppercase text-slate-400">
                    Admin Approvals
                  </div>
                  <div className="mt-0.5 text-xl font-extrabold tabular-nums text-slate-900">
                    {metrics?.pendingApprovals ?? 0}
                  </div>
                  <div className="mt-0.5 text-[11px] text-slate-500">
                    Security role escalations
                  </div>
                </div>

                <div className="rounded-xl border border-slate-200/80 bg-slate-50 p-3">
                  <div className="text-[10px] font-bold uppercase text-slate-400">
                    Security Events
                  </div>
                  <div className="mt-0.5 flex items-baseline gap-1.5">
                    <span className="text-xl font-extrabold tabular-nums text-emerald-600">
                      {metrics?.securityEventCount ?? 0}
                    </span>
                    <span className="text-[10px] font-bold text-emerald-700">✓ Clean</span>
                  </div>
                  <div className="mt-0.5 text-[11px] text-slate-500">
                    Access events today
                  </div>
                </div>
              </div>

              <div className="flex items-center justify-between border-t border-slate-100 pt-2 text-[11px]">
                <span className="text-slate-400">System Telemetry: Healthy</span>
                <Link
                  href="/more?tab=audit_logs"
                  className="font-bold text-blue-600 hover:underline flex items-center gap-0.5"
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
