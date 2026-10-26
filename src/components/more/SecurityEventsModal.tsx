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
} from "lucide-react";
import { useSecurityEvents } from "@/lib/queries/governance";
import { createClient } from "@/lib/supabase/client";
import { Modal } from "@/components/shared/Modal";

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
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Security Events & Threat Stream"
      subtitle="Real-time security telemetry, suspicious authentication alerts, and administrative session terminations."
      icon={ShieldAlert}
      maxWidthClass="max-w-6xl"
    >
      <div className="flex flex-col h-[75vh]">
        {/* Top Metric Cards */}
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 border-b border-border-subtle bg-surface-base px-2 py-4">
          <div className="rounded-xl border border-border-default bg-surface-base p-3.5 shadow-2xs">
            <div className="flex items-center justify-between text-xs text-text-secondary font-semibold">
              <span>Total Events</span>
              <Shield className="h-4 w-4 text-brand-primary" />
            </div>
            <div className="mt-1 flex items-baseline gap-2">
              <span className="text-2xl font-extrabold text-text-primary">{events.length}</span>
              <span className="text-xs font-semibold text-text-muted">Captured</span>
            </div>
          </div>

          <div className="rounded-xl border border-border-default bg-surface-base p-3.5 shadow-2xs">
            <div className="flex items-center justify-between text-xs text-danger font-semibold">
              <span>Critical Incidents</span>
              <AlertTriangle className="h-4 w-4 text-danger" />
            </div>
            <div className="mt-1 flex items-baseline gap-2">
              <span className="text-2xl font-extrabold text-danger">{criticalCount}</span>
              {criticalCount > 0 ? (
                <span className="text-xs font-bold text-danger">Immediate Action</span>
              ) : (
                <span className="text-xs font-semibold text-text-muted">Zero Critical</span>
              )}
            </div>
          </div>

          <div className="rounded-xl border border-border-default bg-surface-base p-3.5 shadow-2xs">
            <div className="flex items-center justify-between text-xs text-text-secondary font-semibold">
              <span>High Severity</span>
              <Flame className="h-4 w-4 text-text-secondary" />
            </div>
            <div className="mt-1 flex items-baseline gap-2">
              <span className="text-2xl font-extrabold text-text-primary">{highCount}</span>
              <span className="text-xs font-semibold text-text-muted">Flagged</span>
            </div>
          </div>

          <div className="rounded-xl border border-border-default bg-surface-base p-3.5 shadow-2xs">
            <div className="flex items-center justify-between text-xs text-text-secondary font-semibold">
              <span>Terminated Sessions</span>
              <LogOut className="h-4 w-4 text-text-secondary" />
            </div>
            <div className="mt-1 flex items-baseline gap-2">
              <span className="text-2xl font-extrabold text-text-primary">{terminatedCount}</span>
              <span className="text-xs font-semibold text-text-muted">Revoked</span>
            </div>
          </div>
        </div>

        {/* Filter and Search Bar */}
        <div className="flex flex-wrap items-center justify-between border-b border-border-subtle bg-surface-base px-2 py-3 gap-3">
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative w-64">
              <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
              <input
                type="text"
                placeholder="Search event, actor, details..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="h-8.5 w-full rounded-lg border border-border-default bg-surface-base pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default"
              />
            </div>

            <div className="flex items-center gap-1">
              {["all", "critical", "high", "medium", "low"].map((sev) => (
                <button
                  key={sev}
                  type="button"
                  onClick={() => setSeverityFilter(sev)}
                  className={`rounded-lg px-2.5 py-1 text-xs font-bold uppercase transition cursor-pointer ${
                    severityFilter === sev
                      ? "bg-brand-primary text-text-inverse"
                      : "bg-surface-base text-text-secondary hover:bg-surface-hover border border-border-subtle"
                  }`}
                >
                  {sev}
                </button>
              ))}
            </div>

            <select
              value={dateRangeDays}
              onChange={(e) => setDateRangeDays(Number(e.target.value))}
              className="h-8.5 rounded-lg border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-primary focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default cursor-pointer"
            >
              <option value={1}>Last 24 Hours</option>
              <option value={7}>Last 7 Days</option>
              <option value={30}>Last 30 Days</option>
              <option value={0}>All Time</option>
            </select>
          </div>

          <div className="flex items-center gap-3">
            <span className="text-xs text-text-muted font-mono">
              Showing {filteredEvents.length} events
            </span>
            <button
              type="button"
              onClick={() => refetch()}
              disabled={isFetching}
              className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition cursor-pointer"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isFetching ? "animate-spin text-brand-primary" : "text-text-muted"
                }`}
              />
              Refresh
            </button>
          </div>
        </div>

        {/* Events Feed Body */}
        <div className="flex-1 overflow-y-auto p-4 space-y-3">
          {isLoading ? (
            <div className="flex h-64 flex-col items-center justify-center gap-3 text-text-muted">
              <RefreshCw className="h-8 w-8 animate-spin text-brand-primary" />
              <p className="text-xs">Fetching security events stream...</p>
            </div>
          ) : filteredEvents.length === 0 ? (
            <div className="rounded-xl border border-dashed border-border-default p-12 text-center text-xs text-text-muted">
              <ShieldCheck className="mx-auto h-8 w-8 text-brand-primary mb-2" />
              <p className="font-semibold text-text-primary">No security events found</p>
              <p className="mt-0.5 text-text-muted">
                No threat indicators or authentication alerts recorded for the selected period.
              </p>
            </div>
          ) : (
            filteredEvents.map((ev) => {
              const isCrit = ev.severity.toLowerCase() === "critical";
              const isExpanded = expandedEvents[ev.id];

              return (
                <div
                  key={ev.id}
                  className={`rounded-xl border p-4 transition shadow-2xs ${
                    isCrit
                      ? "border-danger-border bg-danger-subtle/50"
                      : "border-border-default bg-surface-base"
                  }`}
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="flex items-center gap-2.5">
                      <span
                        className={`rounded-md px-2 py-0.5 text-xs font-bold uppercase tracking-wider ${
                          isCrit
                            ? "bg-danger-subtle text-danger border border-danger-border"
                            : "bg-surface-subtle text-text-primary border border-border-default"
                        }`}
                      >
                        {ev.severity}
                      </span>
                      <h4 className="text-sm font-bold text-text-primary">{ev.action}</h4>
                      <span className="font-mono text-xs bg-surface-subtle px-2 py-0.5 rounded-md border border-border-subtle text-text-muted">
                        {ev.eventType}
                      </span>
                    </div>

                    <span className="text-xs font-mono text-text-muted flex items-center gap-1">
                      <Clock className="h-3 w-3" />
                      {new Date(ev.happenedAt).toLocaleString()}
                    </span>
                  </div>

                  <div className="mt-2 flex flex-wrap items-center gap-4 text-xs text-text-secondary">
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
                        className="text-brand-primary font-semibold hover:underline cursor-pointer"
                      >
                        {isExpanded ? "Hide Payload" : "Inspect Payload"}
                      </button>
                    )}
                  </div>

                  {isExpanded && ev.details && (
                    <pre className="mt-3 rounded-lg bg-surface-subtle p-3 font-mono text-xs text-text-secondary border border-border-subtle overflow-x-auto">
                      {JSON.stringify(ev.details, null, 2)}
                    </pre>
                  )}
                </div>
              );
            })
          )}
        </div>

        {/* Modal Footer */}
        <div className="flex items-center justify-between border-t border-border-subtle bg-surface-base px-2 py-3 pt-4">
          <div className="flex items-center gap-2 text-xs text-text-muted font-mono">
            <span>Table: public.security_events • Realtime channel: gov_sec_events</span>
            {isLiveActive && (
              <span className="inline-flex items-center gap-1 rounded-full bg-surface-subtle px-2 py-0.5 text-xs font-semibold text-text-primary">
                <span className="h-1.5 w-1.5 rounded-full bg-brand-primary animate-pulse" />
                Live
              </span>
            )}
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg border border-border-default bg-surface-base px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition cursor-pointer"
          >
            Close
          </button>
        </div>
      </div>
    </Modal>
  );
}
