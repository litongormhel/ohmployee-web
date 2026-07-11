"use client";

import { useQuery } from "@tanstack/react-query";
import { LayoutDashboard, LockKeyhole } from "lucide-react";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { MetricCard } from "@/components/shared/MetricCard";
import { DataState } from "@/components/shared/DataState";
import {
  getDashboardMetrics,
  getDashboardOperationalAnalytics,
  DashboardDataError,
} from "@/lib/queries/dashboard";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function pct(value: number | null): string {
  if (value === null) return "—";
  return `${(value * 100).toFixed(1)}%`;
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function DashboardPage() {
  const metricsQuery = useQuery({
    queryKey: ["dashboard", "metrics"],
    queryFn: getDashboardMetrics,
  });

  const analyticsQuery = useQuery({
    queryKey: ["dashboard", "operational-analytics"],
    queryFn: getDashboardOperationalAnalytics,
  });

  const metrics = metricsQuery.data;
  const analytics = analyticsQuery.data;

  const metricsError =
    metricsQuery.error instanceof DashboardDataError ? metricsQuery.error : null;
  const metricsBlocked = metricsError?.kind === "access_denied";

  const analyticsError =
    analyticsQuery.error instanceof DashboardDataError ? analyticsQuery.error : null;
  const analyticsBlocked = analyticsError?.kind === "access_denied";

  // Security KPIs are null when the backend gates them by caller role.
  // Show the section only when at least one field comes back non-null.
  const hasSecurityKpis =
    metrics !== undefined &&
    (metrics.pendingApprovals !== null || metrics.securityEventCount !== null);

  const securityBlocked =
    !metricsQuery.isLoading &&
    !metricsQuery.isError &&
    metrics !== undefined &&
    metrics.pendingApprovals === null &&
    metrics.securityEventCount === null;

  return (
    <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-5 text-gray-900">
      <AdminPageHeader
        title="Dashboard"
        subtitle="Cross-module operational overview for the OHMployee admin workspace."
        icon={LayoutDashboard}
        readOnly
      />

      {/* Operational KPI row */}
      <section
        aria-label="Operational summary metrics"
        className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5"
      >
        <MetricCard
          label="Open Vacancies"
          value={metrics?.totalOpenVacancies}
          helperText="Active open vacancy slots"
          isLoading={metricsQuery.isLoading}
          isBlocked={metricsBlocked}
          isError={!metricsBlocked && metricsQuery.isError}
          errorText="Dashboard metrics unavailable"
          badgeLabel="RPC"
        />
        <MetricCard
          label="HR Emploc Pending"
          value={metrics?.totalHrEmplocPending}
          helperText="Onboarding compliance items pending"
          isLoading={metricsQuery.isLoading}
          isBlocked={metricsBlocked}
          isError={!metricsBlocked && metricsQuery.isError}
          errorText="Dashboard metrics unavailable"
          badgeLabel="RPC"
        />
        <MetricCard
          label="Active Plantilla"
          value={metrics?.totalActivePlantilla}
          helperText="Total active deployed employees"
          isLoading={metricsQuery.isLoading}
          isBlocked={metricsBlocked}
          isError={!metricsBlocked && metricsQuery.isError}
          errorText="Dashboard metrics unavailable"
          badgeLabel="RPC"
        />
        <MetricCard
          label="Under-Staffed Stores"
          value={metrics?.understaffedStores}
          helperText="Stores below budgeted plantilla target"
          isLoading={metricsQuery.isLoading}
          isBlocked={metricsBlocked}
          isError={!metricsBlocked && metricsQuery.isError}
          errorText="Dashboard metrics unavailable"
          badgeLabel="RPC"
        />
        <MetricCard
          label="Active SLA Breaches"
          value={metrics?.activeSlaBreaches}
          helperText="Pending movements or vacancy SLA breaches"
          isLoading={metricsQuery.isLoading}
          isBlocked={metricsBlocked}
          isError={!metricsBlocked && metricsQuery.isError}
          errorText="Dashboard metrics unavailable"
          badgeLabel="RPC"
        />
      </section>

      {/* Operational analytics */}
      <section
        aria-label="Operational analytics"
        className="rounded-md border border-border-default bg-surface-base"
      >
        <div className="border-b border-border-default px-5 py-3">
          <h2 className="text-sm font-semibold text-text-primary">Operational Analytics</h2>
          <p className="mt-0.5 text-xs text-text-muted">
            Sourced from <code className="rounded bg-mono-pill-surface px-1 font-mono text-[11px]">fn_dashboard_operational_analytics</code>
          </p>
        </div>

        {analyticsQuery.isLoading && (
          <div className="px-5 py-6">
            <DataState
              kind="loading"
              title="Loading operational analytics"
              description="Fetching pipeline and hire metrics."
            />
          </div>
        )}

        {!analyticsQuery.isLoading && analyticsBlocked && (
          <div className="px-5 py-6">
            <DataState
              kind="access_denied"
              title="Analytics Restricted"
              description="You are not authorized to view operational analytics for the current scope."
            />
          </div>
        )}

        {!analyticsQuery.isLoading && !analyticsQuery.isError && analytics && (
          <div className="grid gap-0 divide-x divide-border-default sm:grid-cols-2 xl:grid-cols-4">
            <AnalyticStat label="Pipeline Total" value={analytics.pipelineTotal} />
            <AnalyticStat label="Hires This Month" value={analytics.hiresThisMonth} />
            <AnalyticStat label="Separations This Month" value={analytics.separationsThisMonth} />
            <AnalyticStat
              label="Avg Fill Rate"
              value={analytics.avgFillRate !== null ? pct(analytics.avgFillRate) : "—"}
              sub="Actual / (Actual + HR Pipeline + Vacancy)"
            />
          </div>
        )}

        {!analyticsQuery.isLoading && analyticsQuery.isError && !analyticsBlocked && (
          <div className="px-5 py-6">
            <DataState
              kind="error"
              title="Analytics Unavailable"
              description={
                analyticsError?.message ??
                "Operational analytics failed to load. Please retry."
              }
              onRetry={() => analyticsQuery.refetch()}
            />
          </div>
        )}
      </section>

      {/* Security Dashboard KPIs — gated by backend role */}
      <section
        aria-label="Security dashboard metrics"
        className="rounded-md border border-border-default bg-surface-base"
      >
        <div className="border-b border-border-default px-5 py-3">
          <h2 className="text-sm font-semibold text-text-primary">Security Dashboard</h2>
          <p className="mt-0.5 text-xs text-text-muted">
            Admin-gated KPIs from <code className="rounded bg-mono-pill-surface px-1 font-mono text-[11px]">fn_dashboard_metrics</code>
          </p>
        </div>

        {metricsQuery.isLoading && (
          <div className="px-5 py-6">
            <DataState
              kind="loading"
              title="Loading security metrics"
              description="Checking role authorization for security KPIs."
            />
          </div>
        )}

        {!metricsQuery.isLoading && securityBlocked && (
          <div className="px-5 py-6">
            <DataState
              kind="access_denied"
              title="Security KPIs Restricted"
              description="Security dashboard metrics are available to administrators only. Your role does not have access to this section."
            />
          </div>
        )}

        {!metricsQuery.isLoading && hasSecurityKpis && (
          <div className="grid gap-3 p-5 sm:grid-cols-2">
            <MetricCard
              label="Pending Approvals"
              value={metrics?.pendingApprovals ?? undefined}
              helperText="Approval requests awaiting admin review"
              isLoading={false}
              isBlocked={metrics?.pendingApprovals === null}
              isError={false}
              badgeLabel="Admin"
            />
            <MetricCard
              label="Security Events"
              value={metrics?.securityEventCount ?? undefined}
              helperText="Access and audit events logged today"
              isLoading={false}
              isBlocked={metrics?.securityEventCount === null}
              isError={false}
              badgeLabel="Admin"
            />
          </div>
        )}

        {!metricsQuery.isLoading && metricsQuery.isError && !metricsBlocked && (
          <div className="px-5 py-6">
            <DataState
              kind="error"
              title="Security Metrics Unavailable"
              description={
                metricsError?.message ??
                "Dashboard metrics failed to load. Please retry."
              }
              onRetry={() => metricsQuery.refetch()}
            />
          </div>
        )}
      </section>

      {/* Footer boundary notice */}
      <section className="rounded-md border border-dashed border-gray-300 bg-gray-50 p-3">
        <div className="flex items-start gap-2 text-xs text-gray-600">
          <LockKeyhole className="mt-0.5 h-4 w-4 shrink-0 text-gray-400" aria-hidden="true" />
          <div>
            <span className="font-semibold text-gray-700">Read-Only Boundary:</span> Dashboard
            reads use{" "}
            <code className="rounded bg-gray-100 px-1 font-mono text-[11px]">fn_dashboard_metrics</code>{" "}
            and{" "}
            <code className="rounded bg-gray-100 px-1 font-mono text-[11px]">fn_dashboard_operational_analytics</code>.
            Security KPIs are gated server-side by the caller&apos;s role. No mutations are
            available from this page.
          </div>
        </div>
      </section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function AnalyticStat({
  label,
  value,
  sub,
}: {
  label: string;
  value: string | number;
  sub?: string;
}) {
  return (
    <div className="flex flex-col gap-0.5 px-5 py-4">
      <span className="text-xs font-semibold uppercase tracking-wide text-text-muted">
        {label}
      </span>
      <span className="text-2xl font-semibold tabular-nums text-text-primary">{value}</span>
      {sub && <span className="text-[10px] text-text-muted">{sub}</span>}
    </div>
  );
}
