"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { LucideIcon } from "lucide-react";
import {
  AlertTriangle,
  ArrowRight,
  BarChart2,
  Clock,
  Compass,
  FileBarChart,
  FileSpreadsheet,
  HelpCircle,
  Hourglass,
  Layers,
  MapPin,
  TrendingDown,
  TrendingUp,
  UserCheck,
  UserMinus,
  Users,
  UserX,
  X,
} from "lucide-react";
import Link from "next/link";
import { ReportDetailView } from "@/components/reports/ReportDetailView";

interface CencomQuickReportsTabProps {
  onSwitchTab?: (tabKey: string) => void;
}

interface ReportOptionItem {
  id: string;
  title: string;
  desc: string;
  category: "Command Center" | "Separation & Leakage" | "Velocity & SLA" | "Workforce Audit";
  icon: LucideIcon;
  colorClass: string;
  bgClass: string;
  borderClass: string;
  badge: string;
  actionType: "internal_tab" | "reports_deep_link" | "inline_modal";
  targetTab?: string;
  reportId?: string;
  hubUrl?: string;
}

export function CencomQuickReportsTab({
  onSwitchTab,
}: CencomQuickReportsTabProps) {
  const router = useRouter();
  const [selectedReportId, setSelectedReportId] = useState<string | null>(null);
  const [activeCategory, setActiveCategory] = useState<string>("all");
  const [searchQuery, setSearchQuery] = useState("");

  const reportOptions: ReportOptionItem[] = [
    // 1-6 Command Center Views
    {
      id: "vacancy_summary",
      title: "Vacancy Summary",
      desc: "Overview of all vacancies by status, health, and operational area",
      category: "Command Center",
      icon: FileBarChart,
      colorClass: "text-blue-600",
      bgClass: "bg-blue-50",
      borderClass: "border-blue-200 hover:border-blue-300",
      badge: "CENCOM Overview",
      actionType: "internal_tab",
      targetTab: "overview",
    },
    {
      id: "vacancy_aging",
      title: "Vacancy Aging",
      desc: "Detailed aging distribution by area, province, and operating stores",
      category: "Command Center",
      icon: Clock,
      colorClass: "text-emerald-600",
      bgClass: "bg-emerald-50",
      borderClass: "border-emerald-200 hover:border-emerald-300",
      badge: "Target Deployment",
      actionType: "internal_tab",
      targetTab: "target_deployment",
    },
    {
      id: "deployment_summary",
      title: "Deployment Summary",
      desc: "Summary of monthly deployment movements, velocities, and newly deployed staff",
      category: "Command Center",
      icon: TrendingUp,
      colorClass: "text-purple-600",
      bgClass: "bg-purple-50",
      borderClass: "border-purple-200 hover:border-purple-300",
      badge: "Deployment Activity",
      actionType: "internal_tab",
      targetTab: "deployments",
    },
    {
      id: "target_deployment",
      title: "Target Deployment",
      desc: "Fulfillment quotas, open vacancy aging flags, and store-level drilldown",
      category: "Command Center",
      icon: MapPin,
      colorClass: "text-indigo-600",
      bgClass: "bg-indigo-50",
      borderClass: "border-indigo-200 hover:border-indigo-300",
      badge: "Area Breakdown",
      actionType: "internal_tab",
      targetTab: "target_deployment",
    },
    {
      id: "group_performance",
      title: "Group Performance",
      desc: "Performance of operational groups, accounts, and plantilla slot capacity",
      category: "Command Center",
      icon: BarChart2,
      colorClass: "text-amber-600",
      bgClass: "bg-amber-50",
      borderClass: "border-amber-200 hover:border-amber-300",
      badge: "Groups Tab",
      actionType: "internal_tab",
      targetTab: "groups",
    },
    {
      id: "hc_movement",
      title: "HC Movement",
      desc: "Executive headcount additions, departures, and net workforce delta",
      category: "Command Center",
      icon: Users,
      colorClass: "text-blue-600",
      bgClass: "bg-blue-50",
      borderClass: "border-blue-200 hover:border-blue-300",
      badge: "Executive Delta",
      actionType: "internal_tab",
      targetTab: "overview",
    },

    // 7-12 Separation & Leakage Reports
    {
      id: "attrition_report",
      title: "Attrition Report",
      desc: "Analyze employee separation rates across accounts, stores, and periods",
      category: "Separation & Leakage",
      icon: TrendingDown,
      colorClass: "text-rose-600",
      bgClass: "bg-rose-50",
      borderClass: "border-rose-200 hover:border-rose-300",
      badge: "Operational Report",
      actionType: "inline_modal",
      reportId: "attrition_report",
      hubUrl: "/reports?tab=catalog&report=attrition_report",
    },
    {
      id: "resigned_report",
      title: "Resigned Staff Report",
      desc: "Voluntary employee turnover and separation reasons across groups",
      category: "Separation & Leakage",
      icon: UserCheck,
      colorClass: "text-amber-600",
      bgClass: "bg-amber-50",
      borderClass: "border-amber-200 hover:border-amber-300",
      badge: "Operational Report",
      actionType: "inline_modal",
      reportId: "resigned_report",
      hubUrl: "/reports?tab=catalog&report=resigned_report",
    },
    {
      id: "awol_report",
      title: "AWOL Separation Report",
      desc: "Absence Without Official Leave tracking and disciplinary impact",
      category: "Separation & Leakage",
      icon: UserX,
      colorClass: "text-red-600",
      bgClass: "bg-red-50",
      borderClass: "border-red-200 hover:border-red-300",
      badge: "Operational Report",
      actionType: "inline_modal",
      reportId: "awol_report",
      hubUrl: "/reports?tab=catalog&report=awol_report",
    },
    {
      id: "terminated_report",
      title: "Terminated Staff Report",
      desc: "Involuntary staff contract terminations and compliance audits",
      category: "Separation & Leakage",
      icon: UserMinus,
      colorClass: "text-orange-600",
      bgClass: "bg-orange-50",
      borderClass: "border-orange-200 hover:border-orange-300",
      badge: "Operational Report",
      actionType: "inline_modal",
      reportId: "terminated_report",
      hubUrl: "/reports?tab=catalog&report=terminated_report",
    },
    {
      id: "backout_report",
      title: "Candidate Back-Out Report",
      desc: "Hiring leakage, candidate dropouts, and pre-deployment attrition",
      category: "Separation & Leakage",
      icon: Clock,
      colorClass: "text-amber-600",
      bgClass: "bg-amber-50",
      borderClass: "border-amber-200 hover:border-amber-300",
      badge: "Operational Report",
      actionType: "inline_modal",
      reportId: "backout_report",
      hubUrl: "/reports?tab=catalog&report=backout_report",
    },
    {
      id: "backout_terminated_report",
      title: "Back-Out & Terminated Combined",
      desc: "Combined view tracking pre-hire dropouts and post-hire terminations",
      category: "Separation & Leakage",
      icon: Layers,
      colorClass: "text-orange-600",
      bgClass: "bg-orange-50",
      borderClass: "border-orange-200 hover:border-orange-300",
      badge: "Combined Audit",
      actionType: "inline_modal",
      reportId: "backout_terminated_report",
      hubUrl: "/reports?tab=catalog&report=backout_terminated_report",
    },

    // 13-14 Velocity & SLA Reports
    {
      id: "time_to_fill",
      title: "Time to Fill Report",
      desc: "Average requisition days to fill vacancies, recruitment speed, and SLA turnaround",
      category: "Velocity & SLA",
      icon: Hourglass,
      colorClass: "text-emerald-600",
      bgClass: "bg-emerald-50",
      borderClass: "border-emerald-200 hover:border-emerald-300",
      badge: "Operational Report",
      actionType: "inline_modal",
      reportId: "time_to_fill",
      hubUrl: "/reports?tab=catalog&report=time_to_fill",
    },
    {
      id: "emploc_late_update",
      title: "HR Emploc Late Update Report",
      desc: "Late location updates, compliance tracking, and placement SLA breaches",
      category: "Velocity & SLA",
      icon: Clock,
      colorClass: "text-indigo-600",
      bgClass: "bg-indigo-50",
      borderClass: "border-indigo-200 hover:border-indigo-300",
      badge: "Compliance Report",
      actionType: "inline_modal",
      reportId: "emploc_late_update",
      hubUrl: "/reports?tab=catalog&report=emploc_late_update",
    },

    // 15-19 Workforce Audit & Dedicated Hubs
    {
      id: "ghost_employee_report",
      title: "Ghost Employee Audit",
      desc: "Detect MIKA vs Plantilla payroll discrepancies and ghost allocations",
      category: "Workforce Audit",
      icon: Compass,
      colorClass: "text-orange-600",
      bgClass: "bg-orange-50",
      borderClass: "border-orange-200 hover:border-orange-300",
      badge: "MIKA Integrity",
      actionType: "reports_deep_link",
      hubUrl: "/reports?tab=data_integrity",
    },
    {
      id: "floating_report",
      title: "Floating Staff Report",
      desc: "Currently floating unassigned employees by account and duration (<30d, 30–60d, >60d)",
      category: "Workforce Audit",
      icon: Users,
      colorClass: "text-amber-600",
      bgClass: "bg-amber-50",
      borderClass: "border-amber-200 hover:border-amber-300",
      badge: "Dedicated Hub Tab",
      actionType: "reports_deep_link",
      hubUrl: "/reports?tab=floating",
    },
    {
      id: "team_performance",
      title: "Team Performance Discipline",
      desc: "Operational discipline rankings, scorecard severity, and team leader rankings",
      category: "Workforce Audit",
      icon: Layers,
      colorClass: "text-teal-600",
      bgClass: "bg-teal-50",
      borderClass: "border-teal-200 hover:border-teal-300",
      badge: "Dedicated Hub Tab",
      actionType: "reports_deep_link",
      hubUrl: "/reports?tab=team_performance",
    },
    {
      id: "data_integrity",
      title: "Data Integrity Audit",
      desc: "Workforce data health, ghost occupancy, and late update anomalies",
      category: "Workforce Audit",
      icon: AlertTriangle,
      colorClass: "text-rose-600",
      bgClass: "bg-rose-50",
      borderClass: "border-rose-200 hover:border-rose-300",
      badge: "Dedicated Hub Tab",
      actionType: "reports_deep_link",
      hubUrl: "/reports?tab=data_integrity",
    },
    {
      id: "custom_report",
      title: "Custom Operational Report",
      desc: "Build, filter, preview, and export custom operational tabular reports",
      category: "Workforce Audit",
      icon: FileSpreadsheet,
      colorClass: "text-blue-600",
      bgClass: "bg-blue-50",
      borderClass: "border-blue-200 hover:border-blue-300",
      badge: "Query Builder",
      actionType: "reports_deep_link",
      hubUrl: "/reports?tab=custom",
    },
  ];

  const handleAction = (item: ReportOptionItem) => {
    if (item.actionType === "internal_tab" && item.targetTab) {
      if (onSwitchTab) {
        onSwitchTab(item.targetTab);
      } else {
        router.push(`/cencom?tab=${item.targetTab}`);
      }
    } else if (item.actionType === "inline_modal" && item.reportId) {
      setSelectedReportId(item.reportId);
    } else if (item.hubUrl) {
      router.push(item.hubUrl);
    }
  };

  const filteredReports = reportOptions.filter((r) => {
    if (activeCategory !== "all" && r.category !== activeCategory) return false;
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase().trim();
      return (
        r.title.toLowerCase().includes(q) ||
        r.desc.toLowerCase().includes(q) ||
        r.badge.toLowerCase().includes(q)
      );
    }
    return true;
  });

  return (
    <div className="space-y-6 animate-in fade-in duration-150">
      {/* 1. Header & Catalog Controls */}
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
        <div>
          <h2 className="text-lg font-bold text-text-primary flex items-center gap-2">
            <FileBarChart className="h-5 w-5 text-brand-600" />
            CENCOM Quick Reports Catalog (18 Operational Reports)
          </h2>
          <p className="text-xs text-text-secondary mt-0.5">
            Instant 1-click inline operational reports, executive command center shortcuts, and deep links into the Reports Hub.
          </p>
        </div>

        <Link
          href="/reports"
          className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-primary shadow-xs transition hover:bg-surface-hover cursor-pointer self-start sm:self-auto"
        >
          <span>Open Full Reports Hub</span>
          <ArrowRight className="h-3.5 w-3.5 text-text-muted" />
        </Link>
      </div>

      {/* 2. Filter Bar & Categories */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        {/* Category Pills */}
        <div className="flex items-center gap-1.5 overflow-x-auto no-scrollbar pb-1">
          {[
            { id: "all", label: "All Reports" },
            { id: "Command Center", label: "Command Center" },
            { id: "Separation & Leakage", label: "Separation & Leakage" },
            { id: "Velocity & SLA", label: "Velocity & SLA" },
            { id: "Workforce Audit", label: "Workforce Audit" },
          ].map((cat) => (
            <button
              key={cat.id}
              onClick={() => setActiveCategory(cat.id)}
              className={`rounded-lg px-3 py-1.5 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                activeCategory === cat.id
                  ? "bg-brand-600 text-white shadow-xs"
                  : "bg-surface-base text-text-secondary hover:text-text-primary border border-border-default hover:bg-surface-hover"
              }`}
            >
              {cat.label}
            </button>
          ))}
        </div>

        {/* Search */}
        <div className="relative min-w-[240px]">
          <input
            type="text"
            placeholder="Search report titles or descriptions..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs text-text-primary placeholder:text-text-muted outline-none transition focus:border-brand-500"
          />
        </div>
      </div>

      {/* 3. Report Cards Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {filteredReports.map((item) => {
          const Icon = item.icon;
          return (
            <div
              key={item.id}
              onClick={() => handleAction(item)}
              className={`group relative flex flex-col justify-between rounded-xl border bg-surface-base p-5 shadow-xs transition cursor-pointer hover:shadow-md ${item.borderClass}`}
            >
              <div>
                <div className="flex items-center justify-between">
                  <div
                    className={`flex h-10 w-10 items-center justify-center rounded-lg ${item.bgClass} ${item.colorClass}`}
                  >
                    <Icon className="h-5 w-5" />
                  </div>
                  <span className="rounded-full bg-slate-100 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-slate-700 border border-slate-200">
                    {item.badge}
                  </span>
                </div>

                <h3 className="mt-3.5 text-sm font-bold text-text-primary group-hover:text-brand-700 transition">
                  {item.title}
                </h3>
                <p className="mt-1 text-xs text-text-secondary line-clamp-2">
                  {item.desc}
                </p>
              </div>

              <div className="mt-4 flex items-center justify-between border-t border-border-subtle pt-3 text-xs font-semibold text-brand-600">
                <span>
                  {item.actionType === "internal_tab"
                    ? "Switch to Tab"
                    : item.actionType === "inline_modal"
                    ? "View Inline Report"
                    : "Open in Hub"}
                </span>
                <ArrowRight className="h-4 w-4 transition group-hover:translate-x-1" />
              </div>
            </div>
          );
        })}
      </div>

      {/* 4. Recently Generated Reports Section (Mobile Parity) */}
      <div className="space-y-3 pt-4 border-t border-border-default">
        <div className="flex items-center justify-between">
          <h3 className="text-xs font-bold uppercase tracking-wider text-text-secondary">
            RECENTLY GENERATED REPORTS
          </h3>
          <Link
            href="/reports"
            className="text-xs font-semibold text-brand-600 hover:text-brand-800"
          >
            View All in Hub &gt;
          </Link>
        </div>

        <div className="rounded-xl border border-border-default bg-surface-base p-6 text-center text-text-muted">
          <p className="text-xs">
            No recently downloaded reports. Use the cards above or the Reports Hub to export operational snapshots.
          </p>
        </div>
      </div>

      {/* 5. Report Schedules Section (Mobile Parity) */}
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <h3 className="text-xs font-bold uppercase tracking-wider text-text-secondary">
            REPORT SCHEDULES & DIGESTS
          </h3>
          <span className="text-xs text-text-muted">Automated Delivery</span>
        </div>

        <div className="rounded-xl border border-border-default bg-surface-base p-6 text-center text-text-muted">
          <p className="text-xs">
            No automated scheduled reports configured for your account. System administrators configure automated weekly MFR rollups.
          </p>
        </div>
      </div>

      {/* 6. Help Callout (Mobile Parity) */}
      <div className="flex items-center gap-3 rounded-xl border border-blue-200 bg-blue-50/70 p-4 text-blue-900 shadow-2xs">
        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-blue-100 text-blue-700">
          <HelpCircle className="h-5 w-5" />
        </div>
        <div className="text-xs">
          <p className="font-bold">Need custom metrics or bespoke workforce views?</p>
          <p className="text-blue-700 mt-0.5">
            Use the <strong>Custom Report Builder</strong> tab in the Reports Hub to query custom combinations of headcount, vacancy statuses, and date ranges.
          </p>
        </div>
      </div>

      {/* Inline Report Detail Modal */}
      {selectedReportId && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-xs p-4 animate-in fade-in">
          <div className="relative w-full max-w-5xl max-h-[90vh] overflow-y-auto rounded-2xl bg-surface-base p-6 shadow-2xl border border-border-default">
            <button
              onClick={() => setSelectedReportId(null)}
              className="absolute right-4 top-4 rounded-lg p-1.5 text-text-muted hover:bg-surface-hover hover:text-text-primary transition cursor-pointer"
              title="Close modal"
            >
              <X className="h-5 w-5" />
            </button>
            <ReportDetailView
              reportId={selectedReportId}
              onBack={() => setSelectedReportId(null)}
            />
          </div>
        </div>
      )}
    </div>
  );
}
