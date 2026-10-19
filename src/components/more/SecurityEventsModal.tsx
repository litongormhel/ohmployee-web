"use client";

import { useEffect, useState } from "react";
import {
  AlertTriangle,
  Clock,
  Flame,
  LogOut,
  RefreshCw,
  Search,
  Shield,
  ShieldAlert,
  ShieldCheck,
  X,
} from "lucide-react";
import { useSecurityEvents } from "@/lib/queries/governance";
import { createClient } from "@/lib/supabase/client";

export interface SecurityEventsModalProps {
  isOpen: boolean;
  onClose: () => void;
  isSuperAdmin?: boolean;
}

export function SecurityEventsModal({
  isOpen,
  onClose,
}: SecurityEventsModalProps) {

  const [severityFilter, setSeverityFilter] = useState<string>("all");
  const [dateRangeDays, setDateRangeDays] = useState<number>(7);
  const [searchQuery, setSearchQuery] = useState("");
  const [expandedEvents, setExpandedEvents] = useState<Record<string, boolean>>({});
  const [isLiveActive, setIsLiveActive] = useState(false);

  const {
    data: events = [],
    isLoading,
    isFetching,
    refetch,
  } = useSecurityEvents({
    severity: severityFilter,
    dateRangeDays,
    limit: 100,
  });

  // Realtime subscription to security_events table
  useEffect(() => {
    if (!isOpen) return;
    const supabase = createClient();
    const channel = supabase
      .channel("gov_sec_events")
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "security_events" },
        () => {
          refetch();
        }
      )
      .subscribe((status) => {
        setIsLiveActive(status === "SUBSCRIBED");
      });

    return () => {
      supabase.removeChannel(channel);
    };
  }, [isOpen, refetch]);

  if (!isOpen) return null;

  const toggleExpand = (id: string) => {
    setExpandedEvents((prev) => ({ ...prev, [id]: !prev[id] }));
  };

  const filteredEvents = events.filter((ev) => {
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    const detailsStr = ev.details ? JSON.stringify(ev.details).toLowerCase() : "";
    return (
      ev.action.toLowerCase().includes(q) ||
      ev.eventType.toLowerCase().includes(q) ||
      (ev.actorName ?? "").toLowerCase().includes(q) ||
      (ev.actorId ?? "").toLowerCase().includes(q) ||
      (ev.targetId ?? "").toLowerCase().includes(q) ||
      detailsStr.includes(q)
    );
  });

  const criticalCount = events.filter((e) => e.severity === "critical").length;
  const highCount = events.filter((e) => e.severity === "high").length;
  const terminatedCount = events.filter(
    (e) => e.eventType.includes("terminate") || e.action.toLowerCase().includes("terminate")
  ).length;

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4 sm:p-6"
    >
      <div className="relative flex h-[90vh] max-h-[850px] w-full max-w-6xl flex-col rounded-2xl border border-border-default bg-surface-card shadow-2xl overflow-hidden">
        {/* Modal Header */}
        <div className="flex flex-wrap items-center justify-between border-b border-border-subtle bg-surface-base/80 px-6 py-4 gap-4">
          <div className="flex items-center gap-3.5">
            <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-purple-500/10 text-purple-600 border border-purple-500/20">
              <ShieldAlert className="h-6 w-6" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-bold text-text-primary">Security Events & Threat Stream</h2>
                <span className="rounded-md bg-purple-50 px-2 py-0.5 text-2xs font-extrabold text-purple-700 border border-purple-200 uppercase">
                  Super Admin
                </span>
                <span className="inline-flex items-center gap-1 rounded-md bg-emerald-50 px-2 py-0.5 text-2xs font-bold text-emerald-700 border border-emerald-200">
                  <span className={`h-1.5 w-1.5 rounded-full ${isLiveActive ? "bg-emerald-500 animate-pulse" : "bg-slate-400"}`} />
                  {isLiveActive ? "Live Realtime" : "Polling"}
                </span>
              </div>
              <p className="text-xs text-text-secondary mt-0.5">
                Real-time security telemetry, suspicious authentication alerts, and administrative session terminations.
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => refetch()}
              disabled={isFetching}
              className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-card px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition cursor-pointer"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isFetching ? "animate-spin text-purple-600" : "text-text-muted"
                }`}
              />
              Refresh
            </button>
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg p-1.5 text-text-muted hover:bg-surface-hover hover:text-text-primary transition cursor-pointer"
            >
              <X className="h-5 w-5" />
            </button>
          </div>
        </div>

        {/* Top Metric Cards */}
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 border-b border-border-subtle bg-surface-card px-6 py-4">
          <div className="rounded-xl border border-border-subtle bg-surface-base p-3.5">
            <div className="flex items-center justify-between text-xs text-text-secondary font-semibold">
              <span>Total Events</span>
              <Shield className="h-4 w-4 text-purple-600" />
            </div>
            <div className="mt-1 flex items-baseline gap-2">
              <span className="text-2xl font-extrabold text-text-primary">{events.length}</span>
              <span className="text-2xs font-semibold text-purple-600">Captured</span>
            </div>
          </div>

          <div className="rounded-xl border border-border-subtle bg-surface-base p-3.5">
            <div className="flex items-center justify-between text-xs text-text-secondary font-semibold">
              <span>Critical Incidents</span>
              <AlertTriangle className="h-4 w-4 text-red-600" />
            </div>
            <div className="mt-1 flex items-baseline gap-2">
              <span className="text-2xl font-extrabold text-red-600">{criticalCount}</span>
              {criticalCount > 0 ? (
                <span className="text-2xs font-bold text-red-700">Immediate Investigation</span>
              ) : (
                <span className="text-2xs font-semibold text-emerald-600">Zero Critical</span>
              )}
            </div>
          </div>

          <div className="rounded-xl border border-border-subtle bg-surface-base p-3.5">
            <div className="flex items-center justify-between text-xs text-text-secondary font-semibold">
              <span>High Severity</span>
              <Flame className="h-4 w-4 text-orange-600" />
            </div>
            <div className="mt-1 flex items-baseline gap-2">
              <span className="text-2xl font-extrabold text-orange-600">{highCount}</span>
              <span className="text-2xs font-semibold text-orange-600">Flagged</span>
            </div>
          </div>

          <div className="rounded-xl border border-border-subtle bg-surface-base p-3.5">
            <div className="flex items-center justify-between text-xs text-text-secondary font-semibold">
              <span>Terminated Sessions</span>
              <LogOut className="h-4 w-4 text-brand-600" />
            </div>
            <div className="mt-1 flex items-baseline gap-2">
              <span className="text-2xl font-extrabold text-text-primary">{terminatedCount}</span>
              <span className="text-2xs font-semibold text-text-muted">Revoked</span>
            </div>
          </div>
        </div>

        {/* Filter and Search Bar */}
        <div className="flex flex-wrap items-center justify-between border-b border-border-subtle bg-surface-base px-6 py-3 gap-3">
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative w-64">
              <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
              <input
                type="text"
                placeholder="Search event, actor, details..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="h-8.5 w-full rounded-lg border border-border-default bg-surface-card pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
              />
            </div>

            <div className="flex items-center gap-1">
              {["all", "critical", "high", "medium", "low"].map((sev) => (
                <button
                  key={sev}
                  type="button"
                  onClick={() => setSeverityFilter(sev)}
                  className={`rounded-lg px-2.5 py-1 text-2xs font-bold uppercase transition cursor-pointer ${
                    severityFilter === sev
                      ? "bg-purple-600 text-white"
                      : "bg-surface-card text-text-secondary hover:bg-surface-hover border border-border-subtle"
                  }`}
                >
                  {sev}
                </button>
              ))}
            </div>

            <select
              value={dateRangeDays}
              onChange={(e) => setDateRangeDays(Number(e.target.value))}
              className="h-8.5 rounded-lg border border-border-default bg-surface-card px-2.5 text-xs font-medium text-text-primary focus:border-brand-500 focus:outline-hidden"
            >
              <option value={1}>Last 24 Hours</option>
              <option value={7}>Last 7 Days</option>
              <option value={30}>Last 30 Days</option>
              <option value={0}>All Time</option>
            </select>
          </div>

          <span className="text-2xs text-text-muted font-mono">
            Showing {filteredEvents.length} events
          </span>
        </div>

        {/* Events Feed Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-3">
          {isLoading ? (
            <div className="flex h-64 flex-col items-center justify-center gap-3 text-text-muted">
              <RefreshCw className="h-8 w-8 animate-spin text-purple-600" />
              <p className="text-xs">Fetching security events stream...</p>
            </div>
          ) : filteredEvents.length === 0 ? (
            <div className="rounded-xl border border-dashed border-border-default p-12 text-center text-xs text-text-muted">
              <ShieldCheck className="mx-auto h-8 w-8 text-emerald-500 mb-2" />
              <p className="font-semibold text-text-primary">No security events found</p>
              <p className="mt-0.5 text-text-muted">
                No threat indicators or authentication alerts recorded for the selected period.
              </p>
            </div>
          ) : (
            filteredEvents.map((ev) => {
              const isCrit = ev.severity.toLowerCase() === "critical";
              const isHigh = ev.severity.toLowerCase() === "high";
              const isExpanded = expandedEvents[ev.id];

              return (
                <div
                  key={ev.id}
                  className={`rounded-xl border p-4 transition shadow-2xs ${
                    isCrit
                      ? "border-red-200 bg-red-50/15"
                      : isHigh
                      ? "border-orange-200 bg-orange-50/15"
                      : "border-border-default bg-surface-card"
                  }`}
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="flex items-center gap-2.5">
                      <span
                        className={`rounded-md px-2 py-0.5 text-2xs font-extrabold uppercase tracking-wider ${
                          isCrit
                            ? "bg-red-100 text-red-800 border border-red-200"
                            : isHigh
                            ? "bg-orange-100 text-orange-800 border border-orange-200"
                            : "bg-blue-100 text-blue-800 border border-blue-200"
                        }`}
                      >
                        {ev.severity}
                      </span>
                      <h4 className="text-xs font-bold text-text-primary">{ev.action}</h4>
                      <span className="font-mono text-2xs bg-surface-base px-2 py-0.5 rounded-md border border-border-subtle text-text-muted">
                        {ev.eventType}
                      </span>
                    </div>

                    <span className="text-2xs font-mono text-text-muted flex items-center gap-1">
                      <Clock className="h-3 w-3" />
                      {new Date(ev.happenedAt).toLocaleString()}
                    </span>
                  </div>

                  <div className="mt-2 flex flex-wrap items-center gap-4 text-2xs text-text-secondary">
                    {ev.actorName && (
                      <span>
                        Actor: <strong className="text-text-primary">{ev.actorName}</strong> ({ev.actorRole ?? "User"})
                      </span>
                    )}
                    {ev.targetId && (
                      <span>
                        Target: <code className="font-mono text-text-muted">{ev.targetId.slice(0, 8)}...</code>
                      </span>
                    )}
                    {ev.details && Object.keys(ev.details).length > 0 && (
                      <button
                        type="button"
                        onClick={() => toggleExpand(ev.id)}
                        className="text-brand-600 font-semibold hover:underline cursor-pointer"
                      >
                        {isExpanded ? "Hide Payload" : "Inspect Payload"}
                      </button>
                    )}
                  </div>

                  {isExpanded && ev.details && (
                    <pre className="mt-3 rounded-lg bg-surface-base p-3 font-mono text-2xs text-text-secondary border border-border-subtle overflow-x-auto">
                      {JSON.stringify(ev.details, null, 2)}
                    </pre>
                  )}
                </div>
              );
            })
          )}
        </div>

        {/* Modal Footer */}
        <div className="flex items-center justify-between border-t border-border-subtle bg-surface-base px-6 py-3">
          <span className="text-2xs text-text-muted font-mono">
            Table: public.security_events • Realtime channel: gov_sec_events
          </span>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg border border-border-default bg-surface-card px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition cursor-pointer"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
