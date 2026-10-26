"use client";

import { useMemo, useState } from "react";
import {
  CheckSquare,
  Download,
  FileSpreadsheet,
  Filter,
  Layers,
  Loader2,
  Play,
  Search,
  Square,
  Table,
} from "lucide-react";
import {
  fetchCustomReportPreview,
  useReportFilterOptions,
} from "@/lib/queries/reports";
import { exportToCsv, exportToXlsx } from "@/lib/utils/reports_export";

type CustomReportSource =
  | "vacancy"
  | "hr_emploc"
  | "plantilla"
  | "deployment"
  | "data_integrity"
  | "team_performance";

interface SourceConfig {
  id: CustomReportSource;
  label: string;
  description: string;
  hasDateRange: boolean;
  hasGroupAccount: boolean;
  hasStatus: boolean;
  columns: { key: string; label: string }[];
}

const SOURCES: Record<CustomReportSource, SourceConfig> = {
  vacancy: {
    id: "vacancy",
    label: "Vacancy Capacity",
    description: "Account headcount capacity, vacant slots, and requisition pipeline",
    hasDateRange: false,
    hasGroupAccount: true,
    hasStatus: false,
    columns: [
      { key: "account_name", label: "Account" },
      { key: "actual_hc", label: "Active HC" },
      { key: "slot_vacant_hc", label: "Vacant HC" },
      { key: "required_hc", label: "Required HC" },
      { key: "pipeline_count", label: "Pipeline" },
      { key: "mfr", label: "MFR rate" },
    ],
  },
  hr_emploc: {
    id: "hr_emploc",
    label: "HR Emploc Pipeline",
    description: "Location assignments, applicant submissions, and approval status",
    hasDateRange: true,
    hasGroupAccount: true,
    hasStatus: true,
    columns: [
      { key: "applicant_name", label: "Applicant name" },
      { key: "position", label: "Position" },
      { key: "store_name", label: "Store branch" },
      { key: "hr_status", label: "HR status" },
      { key: "status", label: "Review status" },
      { key: "account", label: "Account" },
      { key: "date_requested", label: "Date requested" },
    ],
  },
  plantilla: {
    id: "plantilla",
    label: "Plantilla Headcount & MFR",
    description: "Authorized staffing limits, occupied positions, and fulfillment index",
    hasDateRange: false,
    hasGroupAccount: true,
    hasStatus: false,
    columns: [
      { key: "account_name", label: "Account" },
      { key: "actual_hc", label: "Active headcount" },
      { key: "required_hc", label: "Authorized required" },
      { key: "slot_vacant_hc", label: "Vacant capacity" },
      { key: "pipeline_count", label: "Pipeline progress" },
      { key: "mfr", label: "Fulfillment rate (MFR)" },
    ],
  },
  deployment: {
    id: "deployment",
    label: "Deployment Summary",
    description: "Current month net deployments, departures, and deletions",
    hasDateRange: false,
    hasGroupAccount: false,
    hasStatus: false,
    columns: [
      { key: "metric", label: "Deployment metric" },
      { key: "value", label: "Value / count" },
    ],
  },
  data_integrity: {
    id: "data_integrity",
    label: "Data Integrity Findings",
    description: "Delayed updates, vacancy delay, ghost occupancy, and pipeline anomalies",
    hasDateRange: false,
    hasGroupAccount: true,
    hasStatus: false,
    columns: [
      { key: "section", label: "Audit Section" },
      { key: "total_findings", label: "Total Findings" },
      { key: "affected_stores", label: "Affected Stores" },
      { key: "worst_delay", label: "Worst Delay" },
    ],
  },
  team_performance: {
    id: "team_performance",
    label: "Team Performance Ranking",
    description: "Account scorecards, operational rankings, and SLA metrics",
    hasDateRange: false,
    hasGroupAccount: true,
    hasStatus: false,
    columns: [
      { key: "account_name", label: "Account" },
      { key: "group_name", label: "Group" },
      { key: "score", label: "Score" },
      { key: "severity", label: "Severity" },
      { key: "mfr", label: "MFR Rate" },
      { key: "aged_vacancies", label: "Aged Vacancies" },
      { key: "late_hr_updates", label: "Late HR" },
      { key: "hrco_name", label: "HR Coordinator" },
    ],
  },
};

export function CustomReportTab() {
  const [selectedSource, setSelectedSource] = useState<CustomReportSource>("vacancy");
  const [datePreset, setDatePreset] = useState<"last7" | "last30" | "last90" | "thisMonth">("last30");
  const [customStart, setCustomStart] = useState("");
  const [customEnd, setCustomEnd] = useState("");

  const [selectedGroupId, setSelectedGroupId] = useState("");
  const [selectedAccountId, setSelectedAccountId] = useState("");
  const [selectedStatus, setSelectedStatus] = useState("");
  const [searchQuery, setSearchQuery] = useState("");

  const activeConfig = SOURCES[selectedSource];

  // Column Selection
  const [selectedColumns, setSelectedColumns] = useState<string[]>(
    activeConfig.columns.map((c) => c.key)
  );

  const handleSourceChange = (newSource: CustomReportSource) => {
    setSelectedSource(newSource);
    setSelectedColumns(SOURCES[newSource].columns.map((c) => c.key));
    setHasGenerated(false);
    setResults([]);
  };

  const toggleColumn = (key: string) => {
    if (selectedColumns.includes(key)) {
      if (selectedColumns.length > 1) {
        setSelectedColumns(selectedColumns.filter((c) => c !== key));
      }
    } else {
      setSelectedColumns([...selectedColumns, key]);
    }
  };

  // Groups and Accounts Filter Data
  const { data: filterOpts } = useReportFilterOptions();
  const groups = filterOpts?.groups ?? [];
  const accounts = filterOpts?.accounts ?? [];

  const filteredAccounts = selectedGroupId
    ? accounts.filter((a) => a.groupId === selectedGroupId)
    : accounts;

  // Query Execution State
  const [isGenerating, setIsGenerating] = useState(false);
  const [hasGenerated, setHasGenerated] = useState(false);
  const [results, setResults] = useState<Record<string, unknown>[]>([]);
  const [genError, setGenError] = useState<string | null>(null);

  // Compute Active Dates
  const computedDateRange = useMemo(() => {
    const now = new Date();
    const today = now.toISOString().split("T")[0];

    if (customStart && customEnd) {
      return { start: customStart, end: customEnd };
    }
    if (datePreset === "last7") {
      const d = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
      return { start: d.toISOString().split("T")[0], end: today };
    }
    if (datePreset === "last30") {
      const d = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
      return { start: d.toISOString().split("T")[0], end: today };
    }
    if (datePreset === "last90") {
      const d = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000);
      return { start: d.toISOString().split("T")[0], end: today };
    }
    if (datePreset === "thisMonth") {
      const start = new Date(now.getFullYear(), now.getMonth(), 1);
      return { start: start.toISOString().split("T")[0], end: today };
    }
    return { start: today, end: today };
  }, [datePreset, customStart, customEnd]);

  const handleGenerate = async () => {
    setIsGenerating(true);
    setGenError(null);
    try {
      const selectedAccountName = selectedAccountId
        ? accounts.find((a) => a.id === selectedAccountId)?.name
        : undefined;

      const rows = await fetchCustomReportPreview({
        reportType: selectedSource,
        startDate: computedDateRange.start,
        endDate: computedDateRange.end,
        groupId: selectedGroupId || null,
        accountId: selectedAccountId || null,
        accountName: selectedAccountName,
        status: selectedStatus || null,
      });

      setResults(rows);
      setHasGenerated(true);
    } catch (e) {
      console.error("[CustomReport] error generating:", e);
      setGenError(String(e));
    } finally {
      setIsGenerating(false);
    }
  };

  // Filter preview client-side by search
  const filteredResults = useMemo(() => {
    if (!searchQuery) return results;
    const q = searchQuery.toLowerCase();
    return results.filter((r) =>
      Object.values(r).some((val) => String(val ?? "").toLowerCase().includes(q))
    );
  }, [results, searchQuery]);

  // Export handlers
  const handleExportXlsx = () => {
    const exportRows = filteredResults.map((r) => {
      const row: Record<string, unknown> = {};
      for (const col of activeConfig.columns) {
        if (selectedColumns.includes(col.key)) {
          let val = r[col.key];
          if (col.key === "mfr" && typeof val === "number") {
            val = `${(val * 100).toFixed(1)}%`;
          }
          row[col.label] = val ?? "—";
        }
      }
      return row;
    });

    exportToXlsx(exportRows, `Custom_${selectedSource}_Report_${new Date().toISOString().split("T")[0]}`);
  };

  const handleExportCsv = () => {
    const exportRows = filteredResults.map((r) => {
      const row: Record<string, unknown> = {};
      for (const col of activeConfig.columns) {
        if (selectedColumns.includes(col.key)) {
          let val = r[col.key];
          if (col.key === "mfr" && typeof val === "number") {
            val = `${(val * 100).toFixed(1)}%`;
          }
          row[col.label] = val ?? "—";
        }
      }
      return row;
    });

    exportToCsv(exportRows, `Custom_${selectedSource}_Report_${new Date().toISOString().split("T")[0]}`);
  };

  return (
    <div className="space-y-6 animate-in fade-in duration-150">
      {/* Header */}
      <div className="flex flex-wrap items-center justify-between gap-4 pb-4 border-b border-border-subtle">
        <div>
          <div className="flex items-center gap-2">
            <span className="text-[10px] font-bold text-brand-700 bg-brand-50 px-2 py-0.5 rounded border border-brand-200">
              Query Builder
            </span>
            <span className="text-xs text-text-muted">Port of CustomReportScreen</span>
          </div>
          <h2 className="text-xl font-bold text-text-primary mt-0.5 tracking-tight">
            Custom Report Builder & Data Exporter
          </h2>
          <p className="text-xs text-text-secondary mt-0.5">
            Configure custom data sources, toggle columns, scope filters, and export high-density workforce datasets to XLSX/CSV.
          </p>
        </div>

        <div className="flex items-center gap-2">
          {hasGenerated && (
            <>
              <button
                type="button"
                onClick={handleExportXlsx}
                disabled={!filteredResults.length}
                className="flex items-center gap-1.5 h-8 px-3 text-xs font-semibold text-text-primary bg-surface hover:bg-surface-hover border border-border-default rounded-lg transition cursor-pointer disabled:opacity-50"
              >
                <FileSpreadsheet className="w-3.5 h-3.5" />
                Export XLSX
              </button>
              <button
                type="button"
                onClick={handleExportCsv}
                disabled={!filteredResults.length}
                className="flex items-center gap-1.5 h-8 px-3 text-xs font-semibold text-text-secondary bg-surface-base hover:bg-surface-hover border border-border-default rounded-lg transition cursor-pointer disabled:opacity-50"
              >
                <Download className="w-3.5 h-3.5" />
                CSV
              </button>
            </>
          )}
        </div>
      </div>

      {/* 1. Report Data Source Selector */}
      <div className="space-y-2">
        <label className="text-xs font-bold text-text-primary flex items-center gap-1.5">
          <Layers className="w-3.5 h-3.5 text-brand-600" />
          1. Select Primary Data Source
        </label>
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-2.5">
          {(Object.keys(SOURCES) as CustomReportSource[]).map((src) => {
            const config = SOURCES[src];
            const isSelected = selectedSource === src;
            return (
              <button
                type="button"
                key={src}
                onClick={() => handleSourceChange(src)}
                className={`p-3 rounded-xl border text-left transition cursor-pointer flex flex-col justify-between ${
                  isSelected
                    ? "border-brand-primary bg-surface-selected shadow-2xs ring-1 ring-brand-primary"
                    : "border-border-default bg-surface-base hover:border-border-strong"
                }`}
              >
                <div className="text-xs font-bold text-text-primary">{config.label}</div>
                <div className="text-xs text-text-secondary mt-1 line-clamp-2">
                  {config.description}
                </div>
              </button>
            );
          })}
        </div>
      </div>

      {/* 2. Scope & Condition Filters */}
      <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs space-y-4">
        <div className="flex items-center justify-between pb-2 border-b border-border-subtle">
          <label className="text-xs font-bold text-text-primary flex items-center gap-1.5">
            <Filter className="w-3.5 h-3.5 text-brand-600" />
            2. Scope & Condition Filters
          </label>
          <span className="text-[11px] text-text-muted">
            Configuring filters for: <strong className="text-text-primary">{activeConfig.label}</strong>
          </span>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          {activeConfig.hasGroupAccount && (
            <>
              <div>
                <label className="block text-[11px] font-semibold text-text-secondary mb-1">
                  Group Scope
                </label>
                <select
                  value={selectedGroupId}
                  onChange={(e) => {
                    setSelectedGroupId(e.target.value);
                    setSelectedAccountId("");
                  }}
                  className="w-full h-8 px-2.5 text-xs bg-surface-base border border-border-default rounded-md focus:outline-hidden focus:border-brand-500 cursor-pointer"
                >
                  <option value="">All Groups</option>
                  {groups.map((g) => (
                    <option key={g.id} value={g.id}>
                      {g.name}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-[11px] font-semibold text-text-secondary mb-1">
                  Account Scope
                </label>
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
            </>
          )}

          {activeConfig.hasDateRange && (
            <div>
              <label className="block text-[11px] font-semibold text-text-secondary mb-1">
                Date Range Preset
              </label>
              <select
                value={datePreset}
                onChange={(e) => {
                  setDatePreset(e.target.value as "last7" | "last30" | "last90" | "thisMonth");
                  setCustomStart("");
                  setCustomEnd("");
                }}
                className="w-full h-8 px-2.5 text-xs bg-surface-base border border-border-default rounded-md focus:outline-hidden focus:border-brand-500 cursor-pointer"
              >
                <option value="last7">Last 7 Days</option>
                <option value="last30">Last 30 Days</option>
                <option value="last90">Last 90 Days</option>
                <option value="thisMonth">This Month</option>
              </select>
            </div>
          )}

          {activeConfig.hasStatus && (
            <div>
              <label className="block text-[11px] font-semibold text-text-secondary mb-1">
                Emploc Status
              </label>
              <select
                value={selectedStatus}
                onChange={(e) => setSelectedStatus(e.target.value)}
                className="w-full h-8 px-2.5 text-xs bg-surface-base border border-border-default rounded-md focus:outline-hidden focus:border-brand-500 cursor-pointer"
              >
                <option value="">All Statuses</option>
                <option value="Pending">Pending</option>
                <option value="Approved">Approved</option>
                <option value="Deployed">Deployed</option>
                <option value="Correction Needed">Correction Needed</option>
                <option value="Rejected">Rejected</option>
              </select>
            </div>
          )}
        </div>
      </div>

      {/* 3. Column Selection Strip */}
      <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs space-y-3">
        <div className="flex items-center justify-between pb-2 border-b border-border-subtle">
          <label className="text-xs font-bold text-text-primary flex items-center gap-1.5">
            <CheckSquare className="w-3.5 h-3.5 text-brand-600" />
            3. Choose Columns to Include ({selectedColumns.length} of {activeConfig.columns.length})
          </label>
          <button
            onClick={() => setSelectedColumns(activeConfig.columns.map((c) => c.key))}
            className="text-[11px] font-semibold text-brand-600 hover:text-brand-700 cursor-pointer"
          >
            Select All
          </button>
        </div>

        <div className="flex flex-wrap gap-2">
          {activeConfig.columns.map((col) => {
            const isChecked = selectedColumns.includes(col.key);
            return (
              <button
                type="button"
                key={col.key}
                onClick={() => toggleColumn(col.key)}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium border transition cursor-pointer ${
                  isChecked
                    ? "bg-brand-50 border-brand-300 text-brand-800"
                    : "bg-surface-base border-border-default text-text-muted hover:border-border-strong"
                }`}
              >
                {isChecked ? (
                  <CheckSquare className="w-3.5 h-3.5 text-brand-600" />
                ) : (
                  <Square className="w-3.5 h-3.5 text-text-muted" />
                )}
                {col.label}
              </button>
            );
          })}
        </div>
      </div>

      {/* 4. Action Trigger */}
      <div className="flex items-center justify-between">
        <button
          type="button"
          onClick={handleGenerate}
          disabled={isGenerating}
          className="flex items-center gap-2 px-5 py-2 text-xs font-bold text-white bg-brand-600 hover:bg-brand-700 disabled:opacity-50 rounded-lg transition cursor-pointer shadow-sm"
        >
          {isGenerating ? (
            <>
              <Loader2 className="w-4 h-4 animate-spin" />
              Generating Custom Report...
            </>
          ) : (
            <>
              <Play className="w-4 h-4 fill-white" />
              Execute &amp; Generate Preview
            </>
          )}
        </button>

        {hasGenerated && (
          <div className="text-xs text-text-secondary">
            Generated <strong>{results.length}</strong> rows from <strong>{activeConfig.label}</strong>
          </div>
        )}
      </div>

      {/* Error Message */}
      {genError && (
        <div className="p-4 rounded-xl border border-danger-border bg-danger-subtle text-danger-text text-xs">
          Failed to generate custom report preview: {genError}
        </div>
      )}

      {/* 5. Results Preview Table */}
      {hasGenerated && (
        <div className="rounded-xl border border-border-default bg-surface-base shadow-2xs overflow-hidden space-y-0">
          <div className="flex flex-wrap items-center justify-between gap-3 px-4 py-3 border-b border-border-subtle bg-surface-muted/40">
            <div className="flex items-center gap-2">
              <Table className="w-4 h-4 text-brand-600" />
              <span className="text-xs font-bold text-text-primary">
                Report Preview ({filteredResults.length} Rows)
              </span>
            </div>

            <div className="relative">
              <Search className="w-3.5 h-3.5 absolute left-2.5 top-2.5 text-text-muted pointer-events-none" />
              <input
                type="text"
                placeholder="Search across all columns..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="h-8 pl-8 pr-3 text-xs bg-surface-base border border-border-default rounded-md focus:outline-hidden focus:border-brand-500 w-52 sm:w-64"
              />
            </div>
          </div>

          {filteredResults.length === 0 ? (
            <div className="py-20 text-center text-text-muted text-xs">
              No rows matched your search filter or data source criteria.
            </div>
          ) : (
            <div className="overflow-x-auto max-h-[500px]">
              <table className="w-full text-left text-sm">
                <thead className="bg-table-header border-b border-table-rule-section text-text-secondary text-sm font-semibold sticky top-0 z-10 shadow-2xs">
                  <tr>
                    {activeConfig.columns
                      .filter((c) => selectedColumns.includes(c.key))
                      .map((c) => (
                        <th key={c.key} className="py-2.5 px-3 whitespace-nowrap">
                          {c.label}
                        </th>
                      ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-subtle font-medium">
                  {filteredResults.map((r, idx) => (
                    <tr key={idx} className="hover:bg-surface-hover/50 transition">
                      {activeConfig.columns
                        .filter((c) => selectedColumns.includes(c.key))
                        .map((c) => {
                          let val = r[c.key];
                          if (c.key === "mfr" && typeof val === "number") {
                            val = `${(val * 100).toFixed(1)}%`;
                          }
                          return (
                            <td key={c.key} className="py-2.5 px-3 text-text-secondary whitespace-nowrap">
                              {String(val ?? "—")}
                            </td>
                          );
                        })}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          <div className="flex items-center justify-between px-4 py-3 border-t border-border-subtle bg-surface-muted/30 text-xs text-text-muted">
            <span>
              Showing {filteredResults.length} records • Ready for XLSX / CSV export
            </span>
          </div>
        </div>
      )}
    </div>
  );
}
