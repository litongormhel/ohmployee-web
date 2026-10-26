"use client";

import { useMemo, useState } from "react";
import {
  ArrowLeft,
  Calendar,
  Download,
  FileSpreadsheet,
  Loader2,
  RefreshCw,
  Search,
  Users,
} from "lucide-react";
import {
  useReportFilterOptions,
  useUniversalGroupReport,
  type ReportQueryFilters,
} from "@/lib/queries/reports";
import { exportToCsv, exportToXlsx } from "@/lib/utils/reports_export";
import { AttritionDrilldownModal } from "./AttritionDrilldownModal";

export interface ReportDefinition {
  id: string;
  title: string;
  description: string;
  category: "Separation & Attrition" | "Recruitment & Velocity" | "Compliance & Operations";
  badgeColor?: string;
  metricLabel: string;
}

export const REPORT_DEFINITIONS: Record<string, ReportDefinition> = {
  attrition_report: {
    id: "attrition_report",
    title: "Attrition Report",
    description: "Separation and attrition trends by account, store, and operational period.",
    category: "Separation & Attrition",
    badgeColor: "rose",
    metricLabel: "Attrition Rate",
  },
  resigned_report: {
    id: "resigned_report",
    title: "Resigned Staff Report",
    description: "Voluntary employee resignations and turnover breakdown by account.",
    category: "Separation & Attrition",
    badgeColor: "amber",
    metricLabel: "Resigned Count",
  },
  awol_report: {
    id: "awol_report",
    title: "AWOL Report",
    description: "Absence Without Official Leave (AWOL) separations and discipline tracking.",
    category: "Separation & Attrition",
    badgeColor: "red",
    metricLabel: "AWOL Count",
  },
  terminated_report: {
    id: "terminated_report",
    title: "Terminated Staff Report",
    description: "Involuntary separations, contract expirations, and company terminations.",
    category: "Separation & Attrition",
    badgeColor: "orange",
    metricLabel: "Terminated Count",
  },
  backout_report: {
    id: "backout_report",
    title: "Back-Out Report",
    description: "Candidate onboarding back-outs and pre-employment hiring leakage.",
    category: "Separation & Attrition",
    badgeColor: "amber",
    metricLabel: "Back-Out Count",
  },
  backout_terminated_report: {
    id: "backout_terminated_report",
    title: "Back-Out & Terminated Combined",
    description: "Combined leakage view tracking candidate back-outs alongside staff terminations.",
    category: "Separation & Attrition",
    badgeColor: "orange",
    metricLabel: "Total Events",
  },
  time_to_fill: {
    id: "time_to_fill",
    title: "Time to Fill Report",
    description: "Recruitment speed, requisition turnaround, and average days to fill vacancies.",
    category: "Recruitment & Velocity",
    badgeColor: "emerald",
    metricLabel: "Avg Days to Fill",
  },
  emploc_late_update: {
    id: "emploc_late_update",
    title: "HR Emploc Late Update Report",
    description: "Delayed HR location requests, SLA compliance breaches, and encoding audit.",
    category: "Compliance & Operations",
    badgeColor: "indigo",
    metricLabel: "Late Updates",
  },
};

interface ReportDetailViewProps {
  reportId: string;
  onBack?: () => void;
}

export function ReportDetailView({ reportId, onBack }: ReportDetailViewProps) {
  const meta = REPORT_DEFINITIONS[reportId] || {
    id: reportId,
    title: "Operational Report",
    description: "Operational workforce metrics and account breakdown.",
    category: "Separation & Attrition",
    metricLabel: "Metric",
  };

  // Filters State
  const [datePreset, setDatePreset] = useState<"last7" | "last30" | "last90" | "thisMonth" | "all">("last30");
  const [customStart, setCustomStart] = useState<string>("");
  const [customEnd, setCustomEnd] = useState<string>("");
  const [selectedGroupId, setSelectedGroupId] = useState<string>("");
  const [selectedAccountId, setSelectedAccountId] = useState<string>("");
  const [searchQuery, setSearchQuery] = useState("");
  const [sortType, setSortType] = useState<"metric" | "count" | "stores" | "name">("metric");

  // Drilldown Modal
  const [drilldownAccount, setDrilldownAccount] = useState<{ id: string; name: string } | null>(null);

  // Compute Active Date Range
  const activeDateRange = useMemo(() => {
    const now = new Date();
    const today = now.toISOString().split("T")[0];

    if (datePreset === "all") {
      return { startDate: null, endDate: null };
    }
    if (customStart && customEnd) {
      return { startDate: customStart, endDate: customEnd };
    }

    if (datePreset === "last7") {
      const d = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
      return { startDate: d.toISOString().split("T")[0], endDate: today };
    }
    if (datePreset === "last30") {
      const d = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
      return { startDate: d.toISOString().split("T")[0], endDate: today };
    }
    if (datePreset === "last90") {
      const d = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000);
      return { startDate: d.toISOString().split("T")[0], endDate: today };
    }
    if (datePreset === "thisMonth") {
      const start = new Date(now.getFullYear(), now.getMonth(), 1);
      return { startDate: start.toISOString().split("T")[0], endDate: today };
    }

    return { startDate: null, endDate: null };
  }, [datePreset, customStart, customEnd]);

  // Load Groups & Accounts metadata
  const { data: filterOpts } = useReportFilterOptions();
  const groups = filterOpts?.groups ?? [];
  const accounts = filterOpts?.accounts ?? [];

  const filteredAccounts = selectedGroupId
    ? accounts.filter((a) => a.groupId === selectedGroupId)
    : accounts;

  // Query Report Data
  const reportFilters: ReportQueryFilters = {
    startDate: activeDateRange.startDate,
    endDate: activeDateRange.endDate,
    groupId: selectedGroupId || null,
    accountId: selectedAccountId || null,
  };

  const {
    data: reportRows = [],
    isLoading,
    isRefetching,
    error,
    refetch,
  } = useUniversalGroupReport(reportId, reportFilters);

  // Filter & Sort client-side
  const filteredAndSortedRows = useMemo(() => {
    let result = reportRows.filter((r) => {
      if (!searchQuery) return true;
      const q = searchQuery.toLowerCase();
      return r.accountName.toLowerCase().includes(q) || r.groupName.toLowerCase().includes(q);
    });

    result = [...result].sort((a, b) => {
      switch (sortType) {
        case "metric":
          if (reportId === "attrition_report") {
            return (b.attritionRate ?? 0) - (a.attritionRate ?? 0);
          }
          if (reportId === "time_to_fill") {
            return (b.avgDaysToFill ?? 0) - (a.avgDaysToFill ?? 0);
          }
          if (reportId === "emploc_late_update") {
            return (b.lateCount ?? 0) - (a.lateCount ?? 0);
          }
          return b.totalCount - a.totalCount;
        case "count":
          return b.totalCount - a.totalCount;
        case "stores":
          return b.affectedStoreCount - a.affectedStoreCount;
        case "name":
          return a.accountName.localeCompare(b.accountName);
        default:
          return 0;
      }
    });

    return result;
  }, [reportRows, searchQuery, sortType, reportId]);

  // Computed KPIs
  const totalEvents = filteredAndSortedRows.reduce((sum, r) => sum + r.totalCount, 0);
  const totalStores = filteredAndSortedRows.reduce((sum, r) => sum + r.affectedStoreCount, 0);

  const overallAttritionRate = useMemo(() => {
    if (reportId !== "attrition_report" || !filteredAndSortedRows.length) return "0.00";
    let totalSep = 0;
    let totalHc = 0;
    for (const item of filteredAndSortedRows) {
      totalSep += item.totalCount;
      const rate = item.attritionRate ?? 0;
      if (rate > 0) {
        totalHc += (item.totalCount * 100) / rate;
      } else {
        totalHc += item.totalCount;
      }
    }
    if (totalHc === 0) return "0.00";
    return ((totalSep / totalHc) * 100).toFixed(2);
  }, [reportId, filteredAndSortedRows]);

  const avgTimeToFill = useMemo(() => {
    if (reportId !== "time_to_fill" || !filteredAndSortedRows.length) return "0.0";
    const weightedDays = filteredAndSortedRows.reduce(
      (sum, r) => sum + (r.avgDaysToFill ?? 0) * (r.totalCount || 1),
      0
    );
    const count = filteredAndSortedRows.reduce((sum, r) => sum + (r.totalCount || 1), 0);
    return count > 0 ? (weightedDays / count).toFixed(1) : "0.0";
  }, [reportId, filteredAndSortedRows]);

  const totalLateUpdates = useMemo(() => {
    if (reportId !== "emploc_late_update") return 0;
    return filteredAndSortedRows.reduce((sum, r) => sum + (r.lateCount ?? 0), 0);
  }, [reportId, filteredAndSortedRows]);

  // Exports
  const handleExportXlsx = () => {
    const exportData = filteredAndSortedRows.map((r) => {
      const row: Record<string, unknown> = {
        Group: r.groupName,
        Account: r.accountName,
      };
      if (reportId === "attrition_report") {
        row["Attrition Rate"] = `${(r.attritionRate ?? 0).toFixed(2)}%`;
      } else if (reportId === "time_to_fill") {
        row["Avg Days to Fill"] = (r.avgDaysToFill ?? 0).toFixed(1);
      } else if (reportId === "emploc_late_update") {
        row["Late Updates"] = r.lateCount ?? 0;
      }
      row["Total Count"] = r.totalCount;
      row["Affected Stores"] = r.affectedStoreCount;
      row["Period Start"] = r.periodStart;
      row["Period End"] = r.periodEnd;
      return row;
    });

    exportToXlsx(exportData, `${reportId}_${activeDateRange.startDate || "all"}_to_${activeDateRange.endDate || "now"}`);
  };

  const handleExportCsv = () => {
    const exportData = filteredAndSortedRows.map((r) => {
      const row: Record<string, unknown> = {
        Group: r.groupName,
        Account: r.accountName,
      };
      if (reportId === "attrition_report") {
        row["Attrition Rate"] = `${(r.attritionRate ?? 0).toFixed(2)}%`;
      } else if (reportId === "time_to_fill") {
        row["Avg Days to Fill"] = (r.avgDaysToFill ?? 0).toFixed(1);
      } else if (reportId === "emploc_late_update") {
        row["Late Updates"] = r.lateCount ?? 0;
      }
      row["Total Count"] = r.totalCount;
      row["Affected Stores"] = r.affectedStoreCount;
      row["Period Start"] = r.periodStart;
      row["Period End"] = r.periodEnd;
      return row;
    });

    exportToCsv(exportData, `${reportId}_${activeDateRange.startDate || "all"}_to_${activeDateRange.endDate || "now"}`);
  };

  return (
    <div className="space-y-6 animate-in fade-in duration-150">
      {/* Top Breadcrumb & Action Header */}
      <div className="flex flex-wrap items-center justify-between gap-4 pb-4 border-b border-border-subtle">
        <div className="flex items-center gap-3">
          {onBack && (
            <button
              onClick={onBack}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-text-secondary hover:text-text-primary bg-surface-base hover:bg-surface-hover border border-border-default rounded-lg transition cursor-pointer shadow-2xs"
            >
              <ArrowLeft className="w-3.5 h-3.5" />
              Catalog
            </button>
          )}
          <div>
            <div className="flex items-center gap-2">
              <span className="text-[10px] font-bold text-brand-600 bg-brand-50 px-2 py-0.5 rounded border border-brand-200">
                {meta.category}
              </span>
              <span className="text-xs text-text-muted">Universal Report Detail</span>
            </div>
            <h2 className="text-xl font-bold text-text-primary mt-0.5 tracking-tight">
              {meta.title}
            </h2>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => refetch()}
            disabled={isLoading || isRefetching}
            className="flex items-center gap-1.5 h-8 px-3 text-xs font-semibold text-text-secondary bg-surface-base hover:bg-surface-hover border border-border-default rounded-lg transition cursor-pointer disabled:opacity-50"
            title="Refresh Report Data"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${isRefetching ? "animate-spin text-brand-600" : ""}`} />
            Refresh
          </button>
          <button
            type="button"
            onClick={handleExportXlsx}
            disabled={isLoading || !filteredAndSortedRows.length}
            className="flex items-center gap-1.5 h-8 px-3 text-xs font-semibold text-text-primary bg-surface hover:bg-surface-hover border border-border-default rounded-lg transition cursor-pointer disabled:opacity-50"
          >
            <FileSpreadsheet className="w-3.5 h-3.5" />
            Export XLSX
          </button>
          <button
            type="button"
            onClick={handleExportCsv}
            disabled={isLoading || !filteredAndSortedRows.length}
            className="flex items-center gap-1.5 h-8 px-3 text-xs font-semibold text-text-secondary bg-surface-base hover:bg-surface-hover border border-border-default rounded-lg transition cursor-pointer disabled:opacity-50"
          >
            <Download className="w-3.5 h-3.5" />
            CSV
          </button>
        </div>
      </div>

      {/* KPI Cards Strip */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        {reportId === "attrition_report" ? (
          <>
            <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
              <div className="text-[11px] font-semibold text-text-muted">
                Overall Attrition
              </div>
              <div className="text-2xl font-bold text-pct-low mt-1">
                {overallAttritionRate}%
              </div>
              <div className="text-[11px] text-text-muted mt-0.5">Weighted separation rate</div>
            </div>
            <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
              <div className="text-[11px] font-semibold text-text-muted">
                Total Separations
              </div>
              <div className="text-2xl font-bold text-text-primary mt-1">
                {totalEvents}
              </div>
              <div className="text-[11px] text-text-muted mt-0.5">Employees departed</div>
            </div>
            <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
              <div className="text-[11px] font-semibold text-text-muted">
                Affected Stores
              </div>
              <div className="text-2xl font-bold text-text-primary mt-1">
                {totalStores}
              </div>
              <div className="text-[11px] text-text-muted mt-0.5">Store locations impacted</div>
            </div>
            <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
              <div className="text-[11px] font-semibold text-text-muted">
                Reporting Accounts
              </div>
              <div className="text-2xl font-bold text-text-primary mt-1">
                {filteredAndSortedRows.length}
              </div>
              <div className="text-[11px] text-text-muted mt-0.5">Active client accounts</div>
            </div>
          </>
        ) : reportId === "time_to_fill" ? (
          <>
            <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
              <div className="text-[11px] font-semibold text-text-muted">
                Avg Days to Fill
              </div>
              <div className="text-2xl font-bold text-text-primary mt-1">
                {avgTimeToFill}d
              </div>
              <div className="text-[11px] text-text-muted mt-0.5">Requisition turnaround</div>
            </div>
            <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
              <div className="text-[11px] font-semibold text-text-muted">
                Total Filled Vacancies
              </div>
              <div className="text-2xl font-bold text-text-primary mt-1">
                {totalEvents}
              </div>
              <div className="text-[11px] text-text-muted mt-0.5">Confirmed deployments</div>
            </div>
            <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
              <div className="text-[11px] font-semibold text-text-muted">
                Stores Staffed
              </div>
              <div className="text-2xl font-bold text-text-primary mt-1">
                {totalStores}
              </div>
              <div className="text-[11px] text-text-muted mt-0.5">Store branches with hires</div>
            </div>
            <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
              <div className="text-[11px] font-semibold text-text-muted">
                Active Accounts
              </div>
              <div className="text-2xl font-bold text-text-primary mt-1">
                {filteredAndSortedRows.length}
              </div>
              <div className="text-[11px] text-text-muted mt-0.5">Accounts with fill velocity</div>
            </div>
          </>
        ) : reportId === "emploc_late_update" ? (
          <>
            <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
              <div className="text-[11px] font-semibold text-text-muted">
                Late HR Updates
              </div>
              <div className="text-2xl font-bold text-text-primary mt-1">
                {totalLateUpdates}
              </div>
              <div className="text-[11px] text-text-muted mt-0.5">SLA delayed submissions</div>
            </div>
            <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
              <div className="text-[11px] font-semibold text-text-muted">
                Total HR Requests
              </div>
              <div className="text-2xl font-bold text-text-primary mt-1">
                {totalEvents}
              </div>
              <div className="text-[11px] text-text-muted mt-0.5">Total Emploc movements</div>
            </div>
            <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
              <div className="text-[11px] font-semibold text-text-muted">
                Stores Impacted
              </div>
              <div className="text-2xl font-bold text-text-primary mt-1">
                {totalStores}
              </div>
              <div className="text-[11px] text-text-muted mt-0.5">Stores with updates</div>
            </div>
            <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
              <div className="text-[11px] font-semibold text-text-muted">
                Accounts Monitored
              </div>
              <div className="text-2xl font-bold text-text-primary mt-1">
                {filteredAndSortedRows.length}
              </div>
              <div className="text-[11px] text-text-muted mt-0.5">Audited for compliance</div>
            </div>
          </>
        ) : (
          <>
            <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
              <div className="text-[11px] font-semibold text-text-muted">
                Total Events
              </div>
              <div className="text-2xl font-bold text-text-primary mt-1">
                {totalEvents}
              </div>
              <div className="text-[11px] text-text-muted mt-0.5">Cumulative incidents</div>
            </div>
            <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
              <div className="text-[11px] font-semibold text-text-muted">
                Affected Stores
              </div>
              <div className="text-2xl font-bold text-text-primary mt-1">
                {totalStores}
              </div>
              <div className="text-[11px] text-text-muted mt-0.5">Store locations involved</div>
            </div>
            <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
              <div className="text-[11px] font-semibold text-text-muted">
                Active Accounts
              </div>
              <div className="text-2xl font-bold text-text-primary mt-1">
                {filteredAndSortedRows.length}
              </div>
              <div className="text-[11px] text-text-muted mt-0.5">Reporting account rows</div>
            </div>
            <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
              <div className="text-[11px] font-semibold text-text-muted">
                Scope Filter
              </div>
              <div className="text-sm font-bold text-brand-700 mt-2 truncate">
                {selectedGroupId
                  ? groups.find((g) => g.id === selectedGroupId)?.name || "Filtered Group"
                  : "All Groups"}
              </div>
              <div className="text-[11px] text-text-muted mt-0.5">
                {selectedAccountId
                  ? accounts.find((a) => a.id === selectedAccountId)?.name || "Filtered Account"
                  : "All Accounts"}
              </div>
            </div>
          </>
        )}
      </div>

      {/* Comprehensive Filter Bar */}
      <div className="p-4 rounded-xl border border-border-default bg-surface-base space-y-3 shadow-2xs">
        <div className="flex flex-wrap items-center justify-between gap-3">
          {/* Date Range Presets */}
          <div className="flex items-center gap-1.5 flex-wrap">
            <span className="text-xs font-semibold text-text-muted mr-1 flex items-center gap-1">
              <Calendar className="w-3.5 h-3.5" /> Date:
            </span>
            {(
              [
                ["last7", "Last 7d"],
                ["last30", "Last 30d"],
                ["last90", "Last 90d"],
                ["thisMonth", "This Month"],
                ["all", "All Dates"],
              ] as const
            ).map(([key, label]) => (
              <button
                key={key}
                onClick={() => {
                  setDatePreset(key);
                  setCustomStart("");
                  setCustomEnd("");
                }}
                className={`px-2.5 py-1 text-xs font-medium rounded-md transition cursor-pointer ${
                  datePreset === key && !customStart
                    ? "bg-brand-50 text-brand-700 border border-brand-200 font-semibold"
                    : "text-text-secondary hover:bg-surface-hover border border-transparent"
                }`}
              >
                {label}
              </button>
            ))}
          </div>

          {/* Sort Presets */}
          <div className="flex items-center gap-1.5 ml-auto">
            <span className="text-xs font-semibold text-text-muted mr-1">Sort:</span>
            {(
              [
                ["metric", "Highest Metric"],
                ["count", "Most Events"],
                ["stores", "Most Stores"],
                ["name", "Account Name"],
              ] as const
            ).map(([key, label]) => (
              <button
                key={key}
                onClick={() => setSortType(key)}
                className={`px-2.5 py-1 text-xs font-medium rounded-md transition cursor-pointer ${
                  sortType === key
                    ? "bg-surface-subtle text-text-primary border border-border-default font-semibold"
                    : "text-text-secondary hover:bg-surface-hover border border-transparent"
                }`}
              >
                {label}
              </button>
            ))}
          </div>
        </div>

        {/* Second Row: Dropdowns & Search */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 pt-2 border-t border-border-subtle">
          <div className="relative">
            <select
              value={selectedGroupId}
              onChange={(e) => {
                setSelectedGroupId(e.target.value);
                setSelectedAccountId("");
              }}
              className="w-full h-8 px-2.5 text-xs bg-surface-base border border-border-default rounded-md focus:outline-hidden focus:border-brand-500 cursor-pointer"
            >
              <option value="">All Groups (Company-Wide)</option>
              {groups.map((g) => (
                <option key={g.id} value={g.id}>
                  {g.name}
                </option>
              ))}
            </select>
          </div>

          <div className="relative">
            <select
              value={selectedAccountId}
              onChange={(e) => setSelectedAccountId(e.target.value)}
              className="w-full h-8 px-2.5 text-xs bg-surface-base border border-border-default rounded-md focus:outline-hidden focus:border-brand-500 cursor-pointer"
            >
              <option value="">All Accounts</option>
              {filteredAccounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
          </div>

          <div className="relative">
            <Search className="w-3.5 h-3.5 absolute left-2.5 top-2.5 text-text-muted pointer-events-none" />
            <input
              type="text"
              placeholder="Search by account or group name..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full h-8 pl-8 pr-3 text-xs bg-surface-base border border-border-default rounded-md focus:outline-hidden focus:border-brand-500"
            />
          </div>
        </div>
      </div>

      {/* Main Data Table */}
      <div className="rounded-xl border border-border-default bg-surface-base shadow-2xs overflow-hidden">
        {isLoading ? (
          <div className="flex flex-col items-center justify-center py-24 text-text-muted">
            <Loader2 className="w-8 h-8 animate-spin text-brand-600 mb-2" />
            <p className="text-xs font-medium">Querying operational database report...</p>
          </div>
        ) : error ? (
          <div className="p-8 text-center">
            <p className="text-sm font-semibold text-danger-text">Failed to load report data</p>
            <p className="text-xs text-text-muted mt-1">{String(error)}</p>
            <button
              onClick={() => refetch()}
              className="mt-4 px-4 py-1.5 text-xs font-semibold text-brand-700 bg-brand-50 border border-brand-200 rounded-lg hover:bg-brand-100 transition cursor-pointer"
            >
              Retry Query
            </button>
          </div>
        ) : filteredAndSortedRows.length === 0 ? (
          <div className="py-20 text-center text-text-muted text-xs">
            No records found for the selected scope and date range.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="bg-surface-muted border-b border-border-subtle text-text-secondary text-sm font-semibold">
                <tr>
                  <th className="py-3 px-4">Group Scope</th>
                  <th className="py-3 px-4">Account Name</th>
                  <th className="py-3 px-4">{meta.metricLabel}</th>
                  <th className="py-3 px-4 text-center">Total Events</th>
                  <th className="py-3 px-4 text-center">Stores Affected</th>
                  <th className="py-3 px-4 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border-subtle font-medium">
                {filteredAndSortedRows.map((row) => (
                  <tr
                    key={`${row.groupId}-${row.accountId}`}
                    className="hover:bg-surface-hover/50 transition"
                  >
                    <td className="py-3 px-4 text-text-secondary">
                      {row.groupName}
                    </td>
                    <td className="py-3 px-4 font-semibold text-text-primary">
                      {row.accountName}
                    </td>
                    <td className="py-3 px-4">
                      {reportId === "attrition_report" ? (
                        <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-bold bg-surface-subtle text-text-primary border border-border-default">
                          {(row.attritionRate ?? 0).toFixed(2)}%
                        </span>
                      ) : reportId === "time_to_fill" ? (
                        <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-bold bg-surface-subtle text-text-primary border border-border-default">
                          {(row.avgDaysToFill ?? 0).toFixed(1)} days
                        </span>
                      ) : reportId === "emploc_late_update" ? (
                        <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-bold bg-surface-subtle text-text-primary border border-border-default">
                          {row.lateCount ?? 0}
                        </span>
                      ) : (
                        <span className="font-semibold text-text-primary">
                          {row.totalCount}
                        </span>
                      )}
                    </td>
                    <td className="py-3 px-4 text-center text-text-secondary font-mono">
                      {row.totalCount}
                    </td>
                    <td className="py-3 px-4 text-center text-text-secondary">
                      {row.affectedStoreCount}
                    </td>
                    <td className="py-3 px-4 text-right">
                      {reportId === "attrition_report" ? (
                        <button
                          onClick={() =>
                            setDrilldownAccount({ id: row.accountId, name: row.accountName })
                          }
                          className="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-semibold text-brand-700 bg-brand-50 hover:bg-brand-100 border border-brand-200 rounded-md transition cursor-pointer"
                        >
                          <Users className="w-3 h-3" />
                          View Separated Staff
                        </button>
                      ) : (
                        <span className="text-[11px] text-text-muted">
                          {row.periodStart && row.periodEnd
                            ? `${row.periodStart} to ${row.periodEnd}`
                            : "Active"}
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Table Footer */}
        <div className="flex items-center justify-between px-4 py-3 border-t border-border-subtle bg-surface-muted/30 text-xs text-text-muted">
          <span>
            Displaying {filteredAndSortedRows.length} account metrics • All operational queries synchronized
          </span>
        </div>
      </div>

      {/* Drilldown Modal for Attrition */}
      {drilldownAccount && (
        <AttritionDrilldownModal
          accountId={drilldownAccount.id}
          accountName={drilldownAccount.name}
          startDate={activeDateRange.startDate}
          endDate={activeDateRange.endDate}
          onClose={() => setDrilldownAccount(null)}
        />
      )}
    </div>
  );
}
