"use client";

import { useMemo, useState } from "react";
import {
  AlertTriangle,
  Award,
  ChevronRight,
  Download,
  FileSpreadsheet,
  Loader2,
  RefreshCw,
  Search,
  TrendingDown,
  TrendingUp,
} from "lucide-react";
import {
  useReportFilterOptions,
  useTeamPerformanceSummary,
} from "@/lib/queries/reports";
import { exportToCsv, exportToXlsx } from "@/lib/utils/reports_export";
import { TablePagination } from "@/components/shared/TablePagination";
import { TeamPerformanceIssuesModal } from "./TeamPerformanceIssuesModal";

export function TeamPerformanceTab() {
  const [selectedGroupId, setSelectedGroupId] = useState<string>("");
  const [selectedAccountId, setSelectedAccountId] = useState<string>("");
  const [searchQuery, setSearchQuery] = useState("");
  const [severityFilter, setSeverityFilter] = useState<string>("all");
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(15);

  const [drilldownAccount, setDrilldownAccount] = useState<{
    id: string;
    name: string;
    group: string;
  } | null>(null);

  const { data: filterOpts } = useReportFilterOptions();
  const groups = filterOpts?.groups ?? [];
  const accounts = filterOpts?.accounts ?? [];

  const filteredAccounts = selectedGroupId
    ? accounts.filter((a) => a.groupId === selectedGroupId)
    : accounts;

  const {
    data: summary,
    isLoading,
    isRefetching,
    error,
    refetch,
  } = useTeamPerformanceSummary(selectedGroupId || null, selectedAccountId || null);

  const kpis = summary?.kpis ?? {
    averageScore: 0,
    criticalCount: 0,
  };

  const filteredLeaderboard = useMemo(() => {
    const list = summary?.leaderboard ?? [];
    return list.filter((entry) => {
      if (severityFilter !== "all" && entry.severity !== severityFilter) return false;
      if (!searchQuery) return true;
      const q = searchQuery.toLowerCase();
      return (
        entry.accountName.toLowerCase().includes(q) ||
        entry.groupName.toLowerCase().includes(q) ||
        (entry.hrcoName && entry.hrcoName.toLowerCase().includes(q))
      );
    });
  }, [summary?.leaderboard, severityFilter, searchQuery]);

  const totalCount = filteredLeaderboard.length;
  const pageCount = Math.max(1, Math.ceil(totalCount / pageSize));
  const safePage = Math.min(page, pageCount);

  const paginatedLeaderboard = useMemo(() => {
    const start = (safePage - 1) * pageSize;
    return filteredLeaderboard.slice(start, start + pageSize);
  }, [filteredLeaderboard, safePage, pageSize]);

  const handleExportXlsx = () => {
    exportToXlsx(
      filteredLeaderboard.map((e, idx) => ({
        Rank: idx + 1,
        Account: e.accountName,
        Group: e.groupName,
        Score: e.score.toFixed(1),
        Severity: e.severity,
        "MFR Rate": `${(e.mfr * 100).toFixed(1)}%`,
        "Aged Vacancies": e.agedVacancies,
        "Late HR Updates": e.lateHrUpdates,
        HRCO: e.hrcoName || "—",
        "Active HC": e.actualHc,
        "Vacant HC": e.vacantHc,
        "Required HC": e.requiredHc,
      })),
      `Team_Performance_Ranking_${new Date().toISOString().split("T")[0]}`
    );
  };

  const handleExportCsv = () => {
    exportToCsv(
      filteredLeaderboard.map((e, idx) => ({
        Rank: idx + 1,
        Account: e.accountName,
        Group: e.groupName,
        Score: e.score.toFixed(1),
        Severity: e.severity,
        "MFR Rate": `${(e.mfr * 100).toFixed(1)}%`,
        "Aged Vacancies": e.agedVacancies,
        "Late HR Updates": e.lateHrUpdates,
        HRCO: e.hrcoName || "—",
        "Active HC": e.actualHc,
        "Vacant HC": e.vacantHc,
        "Required HC": e.requiredHc,
      })),
      `Team_Performance_Ranking_${new Date().toISOString().split("T")[0]}`
    );
  };

  return (
    <div className="space-y-4 animate-in fade-in duration-150">
      {/* Header */}
      <div className="flex flex-wrap items-center justify-between gap-3 pb-3 border-b border-border-subtle">
        <div>
          <div className="flex items-center gap-2">
            <span className="text-[10px] font-bold text-text-secondary bg-surface-subtle px-2 py-0.5 rounded border border-border-default">
              Operational Discipline
            </span>
          </div>
          <h2 className="text-lg font-bold text-text-primary mt-0.5 tracking-tight">
            Team Performance &amp; SLA Compliance Scorecards
          </h2>
          <p className="text-xs text-text-secondary mt-0.5">
            Operational discipline rankings by group and account, tracking SLA fulfillment, vacancy turnaround, and HR compliance.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => refetch()}
            disabled={isLoading || isRefetching}
            className="flex items-center gap-1.5 h-8 px-2.5 text-xs font-semibold text-text-secondary bg-surface-base hover:bg-surface-hover border border-border-default rounded-md transition cursor-pointer disabled:opacity-50"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${isRefetching ? "animate-spin text-brand-primary" : ""}`} />
            Refresh
          </button>
          <button
            onClick={handleExportXlsx}
            disabled={isLoading || !filteredLeaderboard.length}
            className="flex items-center gap-1.5 h-8 px-2.5 text-xs font-semibold text-text-secondary bg-surface-base hover:bg-surface-hover border border-border-default rounded-md transition cursor-pointer disabled:opacity-50"
          >
            <FileSpreadsheet className="w-3.5 h-3.5" />
            Export XLSX
          </button>
          <button
            onClick={handleExportCsv}
            disabled={isLoading || !filteredLeaderboard.length}
            className="flex items-center gap-1.5 h-8 px-2.5 text-xs font-semibold text-text-secondary bg-surface-base hover:bg-surface-hover border border-border-default rounded-md transition cursor-pointer disabled:opacity-50"
          >
            <Download className="w-3.5 h-3.5" />
            CSV
          </button>
        </div>
      </div>

      {/* KPI Cards Strip */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div className="p-3 rounded-lg border border-border-default bg-surface-base shadow-2xs">
          <div className="text-[11px] font-semibold text-text-muted flex items-center justify-between">
            <span>Average Team Score</span>
            <Award className="w-3.5 h-3.5 text-brand-primary" />
          </div>
          <div className="text-lg font-bold text-brand-primary mt-0.5">
            {kpis.averageScore.toFixed(1)}
          </div>
          <div className="text-[10px] text-text-muted mt-0.5">Scale: 0 to 100 points</div>
        </div>

        <div className="p-3 rounded-lg border border-border-default bg-surface-base shadow-2xs">
          <div className="text-[11px] font-semibold text-text-secondary flex items-center justify-between">
            <span>Top Performing</span>
            <TrendingUp className="w-3.5 h-3.5 text-text-primary" />
          </div>
          <div className="text-sm font-bold text-text-primary mt-0.5 truncate" title={kpis.bestGroupName || "—"}>
            {kpis.bestGroupName || "Top Group"}
          </div>
          <div className="text-[10px] text-text-muted mt-0.5">
            Score: {kpis.bestGroupScore != null ? kpis.bestGroupScore.toFixed(1) : "—"}
          </div>
        </div>

        <div className="p-3 rounded-lg border border-border-default bg-surface-base shadow-2xs">
          <div className="text-[11px] font-semibold text-text-secondary flex items-center justify-between">
            <span>Needs Attention</span>
            <TrendingDown className="w-3.5 h-3.5 text-text-secondary" />
          </div>
          <div className="text-sm font-bold text-text-primary mt-0.5 truncate" title={kpis.lowestGroupName || "—"}>
            {kpis.lowestGroupName || "Lowest Group"}
          </div>
          <div className="text-[10px] text-text-muted mt-0.5">
            Score: {kpis.lowestGroupScore != null ? kpis.lowestGroupScore.toFixed(1) : "—"}
          </div>
        </div>

        <div className="p-3 rounded-lg border border-border-default bg-surface-base shadow-2xs">
          <div className="text-[11px] font-semibold text-danger flex items-center justify-between">
            <span>Critical Accounts</span>
            <AlertTriangle className="w-3.5 h-3.5 text-danger" />
          </div>
          <div className="text-lg font-bold text-danger mt-0.5">
            {kpis.criticalCount}
          </div>
          <div className="text-[10px] text-danger/80 mt-0.5">Score under 70 points</div>
        </div>
      </div>

      {/* Filter Toolbar */}
      <div className="p-3 rounded-lg border border-border-default bg-surface-base shadow-2xs space-y-2.5">
        {/* Severity Filter Chips */}
        <div className="flex items-center gap-1.5 flex-wrap">
          <span className="text-[11px] font-semibold text-text-muted mr-1">Severity:</span>
          {(
            [
              ["all", "All Tiers"],
              ["Excellent", "Excellent (≥90)"],
              ["Good", "Good (80–89)"],
              ["Watch", "Watch (70–79)"],
              ["Critical", "Critical (<70)"],
            ] as const
          ).map(([key, label]) => (
            <button
              key={key}
              onClick={() => {
                setSeverityFilter(key);
                setPage(1);
              }}
              className={`px-2 py-0.5 text-xs font-medium rounded-md transition cursor-pointer ${
                severityFilter === key
                  ? "bg-brand-subtle text-brand-primary border border-brand-border font-semibold"
                  : "text-text-secondary hover:bg-surface-hover border border-transparent"
              }`}
            >
              {label}
            </button>
          ))}
        </div>

        {/* Dropdowns & Search */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5 pt-2 border-t border-border-subtle">
          <div>
            <select
              value={selectedGroupId}
              onChange={(e) => {
                setSelectedGroupId(e.target.value);
                setSelectedAccountId("");
                setPage(1);
              }}
              className="w-full h-8 px-2.5 text-xs bg-surface-base border border-border-default rounded-md focus:outline-hidden focus:border-brand-default focus:ring-1 focus:ring-brand-default cursor-pointer text-text-primary"
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
            <select
              value={selectedAccountId}
              onChange={(e) => {
                setSelectedAccountId(e.target.value);
                setPage(1);
              }}
              className="w-full h-8 px-2.5 text-xs bg-surface-base border border-border-default rounded-md focus:outline-hidden focus:border-brand-default focus:ring-1 focus:ring-brand-default cursor-pointer text-text-primary"
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
              placeholder="Search account, group, coordinator..."
              value={searchQuery}
              onChange={(e) => {
                setSearchQuery(e.target.value);
                setPage(1);
              }}
              className="w-full h-8 pl-8 pr-3 text-xs bg-surface-base border border-border-default rounded-md focus:outline-hidden focus:border-brand-default focus:ring-1 focus:ring-brand-default text-text-primary"
            />
          </div>
        </div>
      </div>

      {/* Leaderboard Table */}
      <div className="rounded-lg border border-border-default bg-surface-base shadow-2xs overflow-hidden">
        {isLoading ? (
          <div className="flex flex-col items-center justify-center py-20 text-text-muted">
            <Loader2 className="w-6 h-6 animate-spin text-brand-primary mb-2" />
            <p className="text-xs font-medium">Computing team performance rankings...</p>
          </div>
        ) : error ? (
          <div className="p-6 text-center">
            <p className="text-xs font-semibold text-danger">Failed to load performance scorecards</p>
            <p className="text-[11px] text-text-muted mt-1">{String(error)}</p>
            <button
              onClick={() => refetch()}
              className="mt-3 px-3 py-1 text-xs font-semibold text-brand-primary bg-brand-subtle border border-brand-border rounded-md hover:bg-brand-subtle/80 transition cursor-pointer"
            >
              Retry Query
            </button>
          </div>
        ) : filteredLeaderboard.length === 0 ? (
          <div className="py-16 text-center text-text-muted text-xs">
            No team performance rankings found for the active filter scope.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead className="bg-table-header border-b border-table-rule-section text-text-secondary text-[11px] font-semibold">
                <tr>
                  <th className="py-2 px-3 w-12 text-center whitespace-nowrap">Rank</th>
                  <th className="py-2 px-3 whitespace-nowrap">Account scope</th>
                  <th className="py-2 px-3 whitespace-nowrap">Performance score</th>
                  <th className="py-2 px-3 text-center whitespace-nowrap">MFR rate</th>
                  <th className="py-2 px-3 text-center whitespace-nowrap">Aged vacancies</th>
                  <th className="py-2 px-3 text-center whitespace-nowrap">Late HR</th>
                  <th className="py-2 px-3 whitespace-nowrap">Coordinator</th>
                  <th className="py-2 px-3 text-right whitespace-nowrap">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border-subtle font-medium text-text-primary">
                {paginatedLeaderboard.map((entry, idx) => {
                  const badgeColor =
                    entry.severity === "Critical"
                      ? "bg-danger-subtle text-danger border-danger-border"
                      : "bg-surface-subtle text-text-secondary border-border-default";

                  return (
                    <tr key={entry.accountId} className="hover:bg-surface-hover/50 transition">
                      <td className="py-2 px-3 text-center font-bold text-text-secondary text-xs">
                        #{(safePage - 1) * pageSize + idx + 1}
                      </td>
                      <td className="py-2 px-3">
                        <div className="font-semibold text-text-primary text-xs">{entry.accountName}</div>
                        <div className="text-[10px] text-text-muted">{entry.groupName}</div>
                      </td>
                      <td className="py-2 px-3">
                        <div className="flex items-center gap-1.5">
                          <span className="font-bold text-text-primary text-xs w-8">
                            {entry.score.toFixed(1)}
                          </span>
                          <span
                            className={`inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-bold border ${badgeColor}`}
                          >
                            {entry.severity}
                          </span>
                        </div>
                      </td>
                      <td className="py-2 px-3 text-center">
                        <span className="font-semibold text-text-primary text-xs">
                          {(entry.mfr * 100).toFixed(1)}%
                        </span>
                      </td>
                      <td className="py-2 px-3 text-center">
                        {entry.agedVacancies > 0 ? (
                          <span className="inline-flex items-center px-1.5 py-0.2 rounded text-[10px] font-bold bg-surface-subtle text-text-primary border border-border-default">
                            {entry.agedVacancies}
                          </span>
                        ) : (
                          <span className="text-text-muted text-xs">0</span>
                        )}
                      </td>
                      <td className="py-2 px-3 text-center">
                        {entry.lateHrUpdates > 0 ? (
                          <span className="inline-flex items-center px-1.5 py-0.2 rounded text-[10px] font-bold bg-danger-subtle text-danger border border-danger-border">
                            {entry.lateHrUpdates}
                          </span>
                        ) : (
                          <span className="text-text-muted text-xs">0</span>
                        )}
                      </td>
                      <td className="py-2 px-3 text-text-secondary text-xs">
                        {entry.hrcoName || "—"}
                      </td>
                      <td className="py-2 px-3 text-right">
                        <button
                          onClick={() =>
                            setDrilldownAccount({
                              id: entry.accountId,
                              name: entry.accountName,
                              group: entry.groupName,
                            })
                          }
                          className="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] font-semibold text-brand-primary bg-brand-subtle hover:bg-brand-subtle/80 border border-brand-border rounded-md transition cursor-pointer"
                        >
                          Audit Issues
                          <ChevronRight className="w-3 h-3" />
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        {/* Footer & Pagination */}
        <div className="flex flex-col border-t border-border-subtle bg-surface-muted/30">
          <div className="flex items-center justify-between px-4 py-2.5 text-xs text-text-muted border-b border-border-subtle/50">
            <span>
              Ranked {filteredLeaderboard.length} account scorecards • Weighted operational discipline index
            </span>
          </div>
          {filteredLeaderboard.length > 0 && (
            <TablePagination
              page={safePage}
              pageSize={pageSize}
              totalCount={totalCount}
              pageSizeOptions={[15, 25, 50, 100]}
              onPageChange={(newPage) => setPage(newPage)}
              onPageSizeChange={(newSize) => {
                setPageSize(newSize);
                setPage(1);
              }}
            />
          )}
        </div>
      </div>

      {/* Issues Drilldown Modal */}
      {drilldownAccount && (
        <TeamPerformanceIssuesModal
          accountId={drilldownAccount.id}
          accountName={drilldownAccount.name}
          groupName={drilldownAccount.group}
          onClose={() => setDrilldownAccount(null)}
        />
      )}
    </div>
  );
}
