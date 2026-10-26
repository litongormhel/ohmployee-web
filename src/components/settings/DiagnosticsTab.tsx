"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  Activity,
  Copy,
  Check,
  RefreshCw,
  Server,
  Lock,
  Database,
  Flame,
  ShieldCheck,
  Zap,
} from "lucide-react";
import {
  pingSupabaseLatency,
  fetchGovernanceControlsRpc,
  fetchFreezeModesRpc,
} from "@/lib/queries/settings";

export function DiagnosticsTab() {
  const {
    data: latencyResult,
    isFetching: isPinging,
    refetch: refetchLatency,
  } = useQuery({
    queryKey: ["diagnostics", "latency"],
    queryFn: pingSupabaseLatency,
  });

  const {
    data: controls = [],
    isLoading: isLoadingControls,
    isError: isControlsError,
    error: controlsErrorObj,
    refetch: refetchControls,
  } = useQuery({
    queryKey: ["diagnostics", "controls"],
    queryFn: fetchGovernanceControlsRpc,
  });

  const {
    data: freezeModes = [],
    isLoading: isLoadingFreeze,
    isError: isFreezeError,
    error: freezeErrorObj,
    refetch: refetchFreeze,
  } = useQuery({
    queryKey: ["diagnostics", "freeze-modes"],
    queryFn: fetchFreezeModesRpc,
  });

  const [copiedSql, setCopiedSql] = useState(false);

  const runAllDiagnostics = () => {
    refetchLatency();
    refetchControls();
    refetchFreeze();
  };

  const controlsStatus: "checking" | "healthy" | "failed" = isLoadingControls
    ? "checking"
    : isControlsError
    ? "failed"
    : "healthy";
  const controlsError = controlsErrorObj ? (controlsErrorObj as Error).message : null;

  const activeFreezeCount = freezeModes.filter((f) => f.enabled).length;
  const freezeStatus: "checking" | "active" | "inactive" | "failed" = isLoadingFreeze
    ? "checking"
    : isFreezeError
    ? "failed"
    : activeFreezeCount > 0
    ? "active"
    : "inactive";
  const freezeError = freezeErrorObj ? (freezeErrorObj as Error).message : null;

  const copySchemaReloadCommand = () => {
    const cmd = "NOTIFY pgrst, 'reload schema';";
    navigator.clipboard.writeText(cmd);
    setCopiedSql(true);
    setTimeout(() => setCopiedSql(false), 3000);
  };

  return (
    <div className="space-y-6">
      {/* Diagnostics Header & Action */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <h2 className="text-base font-semibold text-text-primary">
              System Diagnostics & Governance Probes
            </h2>
            <span className="rounded-md bg-brand-subtle px-2 py-0.5 text-xs font-bold text-brand-primary border border-brand-border">
              Super Admin Only
            </span>
          </div>
          <p className="text-xs text-text-secondary mt-0.5">
            Real-time infrastructure health, PostgREST schema cache sync, and operational freeze flags.
          </p>
        </div>

        <button
          type="button"
          onClick={runAllDiagnostics}
          disabled={isPinging}
          className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3.5 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover disabled:opacity-50 cursor-pointer"
        >
          <RefreshCw className={`h-3.5 w-3.5 ${isPinging ? "animate-spin text-brand-primary" : "text-text-muted"}`} />
          Run Health Probes
        </button>
      </div>

      {/* Grid: 3 Health Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {/* Card 1: Supabase Connectivity & Latency */}
        <div className="rounded-xl border border-border-default bg-surface-base p-5 shadow-2xs space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Zap className="h-4 w-4 text-brand-primary" />
              <h3 className="text-xs font-bold text-text-secondary">
                Supabase Connectivity
              </h3>
            </div>
            {latencyResult ? (
              <span
                className={`inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-xs font-bold ${
                  latencyResult.status === "connected"
                    ? "bg-surface-subtle text-text-primary border border-border-default"
                    : "bg-danger-subtle text-danger border border-danger-border"
                }`}
              >
                {latencyResult.status === "connected" ? "CONNECTED" : "FAILED"}
              </span>
            ) : (
              <span className="text-xs text-text-muted">Probing...</span>
            )}
          </div>

          <div className="pt-2">
            <div className="flex items-baseline gap-2">
              <span className="text-3xl font-extrabold text-text-primary">
                {latencyResult ? `${latencyResult.latencyMs} ms` : "—"}
              </span>
              <span className="text-xs text-text-muted">roundtrip ping</span>
            </div>
            <p className="mt-1 text-xs text-text-secondary">
              {latencyResult?.latencyMs && latencyResult.latencyMs < 200
                ? "Optimal connection speed (< 200ms)."
                : latencyResult?.latencyMs && latencyResult.latencyMs < 500
                ? "Acceptable network latency."
                : "Degraded connection or high latency."}
            </p>
          </div>

          <div className="border-t border-border-default pt-2.5 text-xs text-text-muted flex items-center justify-between">
            <span>Target: RPC fn_check_governance_control</span>
            <span>{latencyResult?.timestamp ?? ""}</span>
          </div>
        </div>

        {/* Card 2: Governance RPC Health */}
        <div className="rounded-xl border border-border-default bg-surface-base p-5 shadow-2xs space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Server className="h-4 w-4 text-brand-primary" />
              <h3 className="text-xs font-bold text-text-secondary">
                Governance Controls
              </h3>
            </div>
            <span
              className={`inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-xs font-bold ${
                controlsStatus === "healthy"
                  ? "bg-surface-subtle text-text-primary border border-border-default"
                  : controlsStatus === "failed"
                  ? "bg-danger-subtle text-danger border border-danger-border"
                  : "bg-brand-subtle text-brand-primary border border-brand-border"
              }`}
            >
              {controlsStatus === "healthy" ? "HEALTHY" : controlsStatus === "failed" ? "DEGRADED" : "PROBING"}
            </span>
          </div>

          <div className="pt-2">
            <div className="flex items-baseline gap-2">
              <span className="text-3xl font-extrabold text-text-primary">
                {controls.length}
              </span>
              <span className="text-xs text-text-muted">registered controls</span>
            </div>
            <p className="mt-1 text-xs text-text-secondary">
              {controlsStatus === "healthy"
                ? "RPC fn_get_governance_controls responding normally."
                : controlsError ?? "Verifying RPC signature..."}
            </p>
          </div>

          <div className="border-t border-border-default pt-2.5 text-xs text-text-muted flex items-center justify-between">
            <span>Security Definer: Level 100</span>
            <span>{controls.filter((c) => c.enabled).length} Enabled</span>
          </div>
        </div>

        {/* Card 3: Operational Freeze Status */}
        <div className="rounded-xl border border-border-default bg-surface-base p-5 shadow-2xs space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Lock className="h-4 w-4 text-brand-primary" />
              <h3 className="text-xs font-bold text-text-secondary">
                Operational Freezes
              </h3>
            </div>
            <span
              className={`inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-xs font-bold ${
                freezeStatus === "inactive"
                  ? "bg-surface-subtle text-text-primary border border-border-default"
                  : freezeStatus === "active"
                  ? "bg-danger-subtle text-danger border border-danger-border"
                  : "bg-surface-subtle text-text-secondary border border-border-default"
              }`}
            >
              {freezeStatus === "inactive"
                ? "NO ACTIVE FREEZES"
                : freezeStatus === "active"
                ? "ACTIVE FREEZES"
                : "CHECKING"}
            </span>
          </div>

          <div className="pt-2">
            <div className="flex items-baseline gap-2">
              <span className="text-3xl font-extrabold text-text-primary">
                {freezeModes.filter((f) => f.enabled).length}
              </span>
              <span className="text-xs text-text-muted">active emergency locks</span>
            </div>
            <p className="mt-1 text-xs text-text-secondary">
              {freezeStatus === "inactive"
                ? "System is running with full write access."
                : freezeStatus === "active"
                ? "Emergency freeze is actively restricting operations!"
                : freezeError ?? "Checking freeze switches..."}
            </p>
          </div>

          <div className="border-t border-border-default pt-2.5 text-xs text-text-muted flex items-center justify-between">
            <span>RPC fn_get_freeze_modes</span>
            <span>{freezeModes.length} Monitored</span>
          </div>
        </div>
      </div>

      {/* Freeze Controls Detail Breakdown */}
      {freezeModes.length > 0 && (
        <div className="rounded-xl border border-border-default bg-surface-base p-6 shadow-2xs space-y-4">
          <div className="flex items-center gap-2 border-b border-border-default pb-3">
            <Flame className="h-4 w-4 text-brand-primary" />
            <h3 className="text-sm font-semibold text-text-primary">
              Emergency Freeze Status Breakdown
            </h3>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            {freezeModes.map((mode) => (
              <div
                key={mode.controlKey}
                className={`rounded-lg border p-3.5 space-y-2 ${
                  mode.enabled
                    ? "border-danger-border bg-danger-subtle"
                    : "border-border-default bg-surface-base"
                }`}
              >
                <div className="flex items-center justify-between">
                  <span className="font-mono text-xs font-bold text-text-primary">
                    {mode.controlKey}
                  </span>
                  <span
                    className={`inline-flex items-center rounded-md px-1.5 py-0.5 text-xs font-bold ${
                      mode.enabled
                        ? "bg-danger-button text-danger-button-text"
                        : "bg-surface-subtle text-text-secondary border border-border-default"
                    }`}
                  >
                    {mode.enabled ? "LOCKED" : "NORMAL"}
                  </span>
                </div>
                <p className="text-xs text-text-secondary line-clamp-2">
                  {mode.reason || (mode.enabled ? "Active restriction" : "Standard operational flow permitted")}
                </p>
                {mode.updatedByName && (
                  <p className="text-xs text-text-muted">
                    By: {mode.updatedByName}
                  </p>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* PostgREST Schema Cache Reload Utility */}
      <div className="rounded-xl border border-border-default bg-surface-base p-6 shadow-2xs space-y-4">
        <div className="flex items-center justify-between border-b border-border-default pb-3">
          <div className="flex items-center gap-2">
            <Database className="h-4 w-4 text-brand-primary" />
            <h3 className="text-sm font-semibold text-text-primary">
              PostgREST Schema Cache Synchronization
            </h3>
          </div>
          <span className="inline-flex items-center gap-1 text-xs text-brand-primary bg-brand-subtle px-2 py-0.5 rounded-md border border-brand-border font-medium">
            <ShieldCheck className="h-3.5 w-3.5" />
            PGRST202 Cache Tool
          </span>
        </div>

        <p className="text-xs leading-relaxed text-text-secondary">
          When new database migrations, table columns, or RPC functions are applied to Supabase, PostgREST might occasionally serve stale schema metadata until notified. Run the command below in the Supabase SQL Editor to invalidate and reload the schema cache instantly.
        </p>

        <div className="relative rounded-lg border border-border-default bg-surface-subtle p-4 font-mono text-xs text-text-primary flex items-center justify-between">
          <span>NOTIFY pgrst, &apos;reload schema&apos;;</span>

          <button
            type="button"
            onClick={copySchemaReloadCommand}
            className="inline-flex items-center gap-1.5 rounded-md bg-surface-base border border-border-default px-3 py-1.5 text-xs font-semibold text-text-primary hover:bg-surface-hover transition-colors shadow-2xs cursor-pointer"
          >
            {copiedSql ? (
              <>
                <Check className="h-3.5 w-3.5 text-brand-primary" />
                <span className="text-brand-primary">Copied!</span>
              </>
            ) : (
              <>
                <Copy className="h-3.5 w-3.5 text-text-secondary" />
                <span>Copy Command</span>
              </>
            )}
          </button>
        </div>

        <div className="rounded-lg bg-surface-subtle p-3 text-xs text-text-secondary flex items-start gap-2">
          <Activity className="h-4 w-4 text-brand-primary shrink-0 mt-0.5" />
          <span>
            Executing this SQL notification takes under 10 milliseconds and triggers zero service downtime.
          </span>
        </div>
      </div>
    </div>
  );
}
