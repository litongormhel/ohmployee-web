"use client";

import { useState } from "react";
import {
  AlertTriangle,
  ArrowRight,
  Clock,
  FileBarChart2,
  FileCheck2,
  Hourglass,
  Layers,
  MapPin,
  TrendingDown,
  UserCheck,
  UserMinus,
  UserX,
  Users,
} from "lucide-react";
import { ReportDetailView } from "./ReportDetailView";

interface ReportsCatalogTabProps {
  initialReportId?: string | null;
  onSwitchTab?: (tab: string) => void;
}

export function ReportsCatalogTab({
  initialReportId,
  onSwitchTab,
}: ReportsCatalogTabProps) {
  const [selectedReportId, setSelectedReportId] = useState<string | null>(
    initialReportId || null
  );

  if (selectedReportId) {
    return (
      <ReportDetailView
        reportId={selectedReportId}
        onBack={() => setSelectedReportId(null)}
      />
    );
  }

  return (
    <div className="space-y-8 animate-in fade-in duration-150">
      {/* Hero Banner */}
      <div className="p-6 rounded-2xl bg-gradient-to-r from-brand-900 via-brand-800 to-brand-950 text-white shadow-md relative overflow-hidden">
        <div className="relative z-10 max-w-2xl">
          <span className="text-[10px] font-bold uppercase tracking-widest text-brand-200 bg-[var(--surface-overlay)] px-2.5 py-1 rounded-full border border-[var(--border-subtle)]">
            Operational Intelligence & Analytics
          </span>
          <h2 className="text-2xl font-bold tracking-tight mt-2">
            Workforce Reports & Compliance Hub
          </h2>
          <p className="text-sm text-brand-100 mt-1 leading-relaxed">
            Consolidated operational reporting engine. Audit attrition trends, tracking floating staff aging, SLA discipline, data integrity anomalies, and custom workforce extractions.
          </p>
        </div>
        <div className="absolute right-0 bottom-0 opacity-10 pointer-events-none transform translate-x-10 translate-y-10">
          <FileBarChart2 className="w-80 h-80" />
        </div>
      </div>

      {/* Category 1: Separation & Attrition Reports */}
      <div className="space-y-3">
        <div className="flex items-center gap-2">
          <UserMinus className="w-4 h-4 text-text-primary" />
          <h3 className="text-sm font-bold uppercase tracking-wider text-text-primary">
            Separation & Attrition Reports
          </h3>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {/* Attrition */}
          <div
            onClick={() => setSelectedReportId("attrition_report")}
            className="group relative p-5 rounded-xl border border-border-default bg-surface-base hover:border-border-strong hover:shadow-md transition cursor-pointer flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2.5 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <TrendingDown className="w-5 h-5" />
                </div>
                <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded bg-surface-subtle text-text-secondary border border-border-default">
                  Universal Viewer
                </span>
              </div>
              <h4 className="text-base font-bold text-text-primary mt-3 group-hover:text-brand-primary transition">
                Attrition Report
              </h4>
              <p className="text-xs text-text-secondary mt-1 line-clamp-2">
                Analyze separation rates across accounts, drill down into affected stores, and inspect separated employee histories.
              </p>
            </div>
            <div className="mt-4 pt-3 border-t border-border-subtle flex items-center justify-between text-xs font-semibold text-brand-primary">
              <span>Launch Report & Drilldown</span>
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition" />
            </div>
          </div>

          {/* Resigned */}
          <div
            onClick={() => setSelectedReportId("resigned_report")}
            className="group relative p-5 rounded-xl border border-border-default bg-surface-base hover:border-border-strong hover:shadow-md transition cursor-pointer flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2.5 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <UserCheck className="w-5 h-5" />
                </div>
                <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded bg-surface-subtle text-text-secondary border border-border-default">
                  Universal Viewer
                </span>
              </div>
              <h4 className="text-base font-bold text-text-primary mt-3 group-hover:text-brand-primary transition">
                Resigned Staff Report
              </h4>
              <p className="text-xs text-text-secondary mt-1 line-clamp-2">
                Voluntary employee resignations and turnover breakdown by account with date range filtering.
              </p>
            </div>
            <div className="mt-4 pt-3 border-t border-border-subtle flex items-center justify-between text-xs font-semibold text-brand-primary">
              <span>View Resignations</span>
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition" />
            </div>
          </div>

          {/* AWOL */}
          <div
            onClick={() => setSelectedReportId("awol_report")}
            className="group relative p-5 rounded-xl border border-border-default bg-surface-base hover:border-border-strong hover:shadow-md transition cursor-pointer flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2.5 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <UserX className="w-5 h-5" />
                </div>
                <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded bg-surface-subtle text-text-secondary border border-border-default">
                  Universal Viewer
                </span>
              </div>
              <h4 className="text-base font-bold text-text-primary mt-3 group-hover:text-brand-primary transition">
                AWOL Separation Report
              </h4>
              <p className="text-xs text-text-secondary mt-1 line-clamp-2">
                Absence Without Official Leave separations, disciplinary movement, and store impact tracking.
              </p>
            </div>
            <div className="mt-4 pt-3 border-t border-border-subtle flex items-center justify-between text-xs font-semibold text-brand-primary">
              <span>Audit AWOL Events</span>
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition" />
            </div>
          </div>

          {/* Terminated */}
          <div
            onClick={() => setSelectedReportId("terminated_report")}
            className="group relative p-5 rounded-xl border border-border-default bg-surface-base hover:border-border-strong hover:shadow-md transition cursor-pointer flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2.5 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <UserMinus className="w-5 h-5" />
                </div>
                <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded bg-surface-subtle text-text-secondary border border-border-default">
                  Universal Viewer
                </span>
              </div>
              <h4 className="text-base font-bold text-text-primary mt-3 group-hover:text-brand-primary transition">
                Terminated Staff Report
              </h4>
              <p className="text-xs text-text-secondary mt-1 line-clamp-2">
                Involuntary separations, contract terminations, and end-of-service compliance tracking.
              </p>
            </div>
            <div className="mt-4 pt-3 border-t border-border-subtle flex items-center justify-between text-xs font-semibold text-brand-primary">
              <span>View Terminations</span>
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition" />
            </div>
          </div>

          {/* Back-Out */}
          <div
            onClick={() => setSelectedReportId("backout_report")}
            className="group relative p-5 rounded-xl border border-border-default bg-surface-base hover:border-border-strong hover:shadow-md transition cursor-pointer flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2.5 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <Clock className="w-5 h-5" />
                </div>
                <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded bg-surface-subtle text-text-secondary border border-border-default">
                  Universal Viewer
                </span>
              </div>
              <h4 className="text-base font-bold text-text-primary mt-3 group-hover:text-brand-primary transition">
                Back-Out Report
              </h4>
              <p className="text-xs text-text-secondary mt-1 line-clamp-2">
                Candidate onboarding back-outs and pre-deployment recruitment leakage audit.
              </p>
            </div>
            <div className="mt-4 pt-3 border-t border-border-subtle flex items-center justify-between text-xs font-semibold text-brand-primary">
              <span>View Back-Outs</span>
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition" />
            </div>
          </div>

          {/* Back-Out & Terminated Combined */}
          <div
            onClick={() => setSelectedReportId("backout_terminated_report")}
            className="group relative p-5 rounded-xl border border-border-default bg-surface-base hover:border-border-strong hover:shadow-md transition cursor-pointer flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2.5 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <Layers className="w-5 h-5" />
                </div>
                <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded bg-surface-subtle text-text-secondary border border-border-default">
                  Universal Viewer
                </span>
              </div>
              <h4 className="text-base font-bold text-text-primary mt-3 group-hover:text-brand-primary transition">
                Back-Out & Terminated Combined
              </h4>
              <p className="text-xs text-text-secondary mt-1 line-clamp-2">
                Combined leakage view tracking candidate back-outs alongside staff terminations in unified cards.
              </p>
            </div>
            <div className="mt-4 pt-3 border-t border-border-subtle flex items-center justify-between text-xs font-semibold text-brand-primary">
              <span>View Combined Audit</span>
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition" />
            </div>
          </div>
        </div>
      </div>

      {/* Category 2: Recruitment Velocity & Turnaround */}
      <div className="space-y-3">
        <div className="flex items-center gap-2">
          <Hourglass className="w-4 h-4 text-text-primary" />
          <h3 className="text-sm font-bold uppercase tracking-wider text-text-primary">
            Recruitment Velocity & Turnaround
          </h3>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {/* Time to Fill */}
          <div
            onClick={() => setSelectedReportId("time_to_fill")}
            className="group relative p-5 rounded-xl border border-border-default bg-surface-base hover:border-border-strong hover:shadow-md transition cursor-pointer flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2.5 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <Clock className="w-5 h-5" />
                </div>
                <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded bg-surface-subtle text-text-secondary border border-border-default">
                  Universal Viewer
                </span>
              </div>
              <h4 className="text-base font-bold text-text-primary mt-3 group-hover:text-brand-primary transition">
                Time to Fill Report
              </h4>
              <p className="text-xs text-text-secondary mt-1 line-clamp-2">
                Average requisition days to fill open vacancy slots, hiring speed, and store deployment velocity.
              </p>
            </div>
            <div className="mt-4 pt-3 border-t border-border-subtle flex items-center justify-between text-xs font-semibold text-brand-primary">
              <span>Analyze Fill Velocity</span>
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition" />
            </div>
          </div>

          {/* Vacancy Aging */}
          <div
            onClick={() => onSwitchTab?.("custom")}
            className="group relative p-5 rounded-xl border border-border-default bg-surface-base hover:border-border-strong hover:shadow-md transition cursor-pointer flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2.5 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <Hourglass className="w-5 h-5" />
                </div>
                <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded bg-surface-subtle text-text-secondary border border-border-default">
                  Custom Builder
                </span>
              </div>
              <h4 className="text-base font-bold text-text-primary mt-3 group-hover:text-brand-primary transition">
                Vacancy Aging & Allocation
              </h4>
              <p className="text-xs text-text-secondary mt-1 line-clamp-2">
                Inspect open vacancy duration, active headcount, and plantilla slot capacity across accounts.
              </p>
            </div>
            <div className="mt-4 pt-3 border-t border-border-subtle flex items-center justify-between text-xs font-semibold text-brand-primary">
              <span>Open in Custom Builder</span>
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition" />
            </div>
          </div>

          {/* Target Deployment */}
          <a
            href="/cencom"
            className="group relative p-5 rounded-xl border border-border-default bg-surface-base hover:border-border-strong hover:shadow-md transition cursor-pointer flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2.5 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <MapPin className="w-5 h-5" />
                </div>
                <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded bg-surface-subtle text-text-secondary border border-border-default">
                  CENCOM Module
                </span>
              </div>
              <h4 className="text-base font-bold text-text-primary mt-3 group-hover:text-brand-primary transition">
                Target Deployment Overview
              </h4>
              <p className="text-xs text-text-secondary mt-1 line-clamp-2">
                Store-by-store deployment fulfillment rates and geographic coverage breakdown in CENCOM.
              </p>
            </div>
            <div className="mt-4 pt-3 border-t border-border-subtle flex items-center justify-between text-xs font-semibold text-brand-primary">
              <span>Navigate to CENCOM</span>
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition" />
            </div>
          </a>
        </div>
      </div>

      {/* Category 3: Compliance & Dedicated Hub Surfaces */}
      <div className="space-y-3">
        <div className="flex items-center gap-2">
          <FileCheck2 className="w-4 h-4 text-text-primary" />
          <h3 className="text-sm font-bold uppercase tracking-wider text-text-primary">
            Workforce Health & Operational Audit
          </h3>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          {/* HR Emploc Late Update */}
          <div
            onClick={() => setSelectedReportId("emploc_late_update")}
            className="group relative p-5 rounded-xl border border-border-default bg-surface-base hover:border-border-strong hover:shadow-md transition cursor-pointer flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <Clock className="w-4 h-4" />
                </div>
                <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded bg-surface-subtle text-text-secondary border border-border-default">
                  Quick Report
                </span>
              </div>
              <h4 className="text-sm font-bold text-text-primary mt-3 group-hover:text-brand-primary transition">
                HR Emploc Late Updates
              </h4>
              <p className="text-xs text-text-secondary mt-1">
                SLA breaches and delayed location submissions.
              </p>
            </div>
            <div className="mt-4 pt-2.5 border-t border-border-subtle flex items-center justify-between text-xs font-semibold text-brand-primary">
              <span>Open Report</span>
              <ArrowRight className="w-3.5 h-3.5" />
            </div>
          </div>

          {/* Floating Staff */}
          <div
            onClick={() => onSwitchTab?.("floating")}
            className="group relative p-5 rounded-xl border border-border-default bg-surface-base hover:border-border-strong hover:shadow-md transition cursor-pointer flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <Users className="w-4 h-4" />
                </div>
                <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded bg-surface-subtle text-text-secondary border border-border-default">
                  Dedicated Hub Tab
                </span>
              </div>
              <h4 className="text-sm font-bold text-text-primary mt-3 group-hover:text-brand-primary transition">
                Floating Staff Report
              </h4>
              <p className="text-xs text-text-secondary mt-1">
                Floating employees aging (&lt;30d, 30–60d, &gt;60d).
              </p>
            </div>
            <div className="mt-4 pt-2.5 border-t border-border-subtle flex items-center justify-between text-xs font-semibold text-brand-primary">
              <span>Switch to Tab 2</span>
              <ArrowRight className="w-3.5 h-3.5" />
            </div>
          </div>

          {/* Team Performance */}
          <div
            onClick={() => onSwitchTab?.("team_performance")}
            className="group relative p-5 rounded-xl border border-border-default bg-surface-base hover:border-border-strong hover:shadow-md transition cursor-pointer flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <Layers className="w-4 h-4" />
                </div>
                <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded bg-surface-subtle text-text-secondary border border-border-default">
                  Dedicated Hub Tab
                </span>
              </div>
              <h4 className="text-sm font-bold text-text-primary mt-3 group-hover:text-brand-primary transition">
                Team Performance
              </h4>
              <p className="text-xs text-text-secondary mt-1">
                Discipline rankings, scorecards, and SLA issues.
              </p>
            </div>
            <div className="mt-4 pt-2.5 border-t border-border-subtle flex items-center justify-between text-xs font-semibold text-brand-primary">
              <span>Switch to Tab 3</span>
              <ArrowRight className="w-3.5 h-3.5" />
            </div>
          </div>

          {/* Data Integrity */}
          <div
            onClick={() => onSwitchTab?.("data_integrity")}
            className="group relative p-5 rounded-xl border border-border-default bg-surface-base hover:border-border-strong hover:shadow-md transition cursor-pointer flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <AlertTriangle className="w-4 h-4" />
                </div>
                <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded bg-surface-subtle text-text-secondary border border-border-default">
                  Dedicated Hub Tab
                </span>
              </div>
              <h4 className="text-sm font-bold text-text-primary mt-3 group-hover:text-brand-primary transition">
                Data Integrity Audit
              </h4>
              <p className="text-xs text-text-secondary mt-1">
                Ghost occupancy, delay audit, and pipeline anomalies.
              </p>
            </div>
            <div className="mt-4 pt-2.5 border-t border-border-subtle flex items-center justify-between text-xs font-semibold text-brand-primary">
              <span>Switch to Tab 4</span>
              <ArrowRight className="w-3.5 h-3.5" />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
