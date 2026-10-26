"use client";

import { useState, useMemo } from "react";
import {
  Calendar,
  CheckCircle2,
  Clock,
  Download,
  MapPin,
  RefreshCw,
  Search,
  Store,
  TrendingUp,
} from "lucide-react";
import {
  useCencomDeploymentActivity,
  useCencomDeploymentSummary,
  type CencomDeploymentPeriod,
} from "@/lib/queries/cencom";
import { MetricCard } from "@/components/shared/MetricCard";

interface CencomDeploymentActivityTabProps {
  onRefresh?: () => void;
  isRefreshing?: boolean;
}

export function CencomDeploymentActivityTab({
  onRefresh,
  isRefreshing = false,
}: CencomDeploymentActivityTabProps) {
  const [period, setPeriod] = useState<CencomDeploymentPeriod>("month");
  const [searchQuery, setSearchQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");
  const [accountFilter, setAccountFilter] = useState("all");
  const [currentPage, setCurrentPage] = useState(1);
  const pageSize = 15;

  const {
    data: activityResult,
    isLoading: isLoadingActivity,
    refetch: refetchActivity,
    isRefetching: isRefetchingActivity,
  } = useCencomDeploymentActivity(period);

  const {
    data: deploymentSummary,
    isLoading: isLoadingSummary,
    refetch: refetchSummary,
  } = useCencomDeploymentSummary();

  const handleRefresh = async () => {
    if (onRefresh) onRefresh();
    await Promise.all([refetchActivity(), refetchSummary()]);
  };

  const records = useMemo(() => activityResult?.records ?? [], [activityResult?.records]);

  // Distinct accounts for filter
  const accountsList = useMemo(() => {
    const set = new Set<string>();
    for (const r of records) {
      if (r.account) set.add(r.account);
    }
    return Array.from(set).sort();
  }, [records]);

  // Filtered records
  const filteredRecords = useMemo(() => {
    let list = [...records];

    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase().trim();
      list = list.filter(
        (r) =>
          r.applicantName.toLowerCase().includes(q) ||
          r.storeName.toLowerCase().includes(q) ||
          r.account.toLowerCase().includes(q) ||
          r.position.toLowerCase().includes(q) ||
          (r.employeeNo && r.employeeNo.toLowerCase().includes(q)) ||
          (r.emplocNo && r.emplocNo.toLowerCase().includes(q)) ||
          (r.vcode && r.vcode.toLowerCase().includes(q))
      );
    }

    if (statusFilter !== "all") {
      list = list.filter((r) => r.status.toLowerCase().includes(statusFilter.toLowerCase()));
    }

    if (accountFilter !== "all") {
      list = list.filter((r) => r.account.toLowerCase() === accountFilter.toLowerCase());
    }

    return list;
  }, [records, searchQuery, statusFilter, accountFilter]);

  // Paginated records
  const paginatedRecords = useMemo(() => {
    const start = (currentPage - 1) * pageSize;
    return filteredRecords.slice(start, start + pageSize);
  }, [filteredRecords, currentPage]);

  const totalPages = Math.max(1, Math.ceil(filteredRecords.length / pageSize));

  // CSV export handler
  const handleExportCSV = () => {
    if (filteredRecords.length === 0) return;
    const headers = [
      "Candidate Name",
      "Employee No",
      "Emploc No",
      "Account",
      "Store Name",
      "Area",
      "Position",
      "VCode",
      "Hired Date",
      "Status",
    ];

    const rows = filteredRecords.map((r) => [
      `"${r.applicantName.replace(/"/g, '""')}"`,
      `"${(r.employeeNo || "").replace(/"/g, '""')}"`,
      `"${(r.emplocNo || "").replace(/"/g, '""')}"`,
      `"${r.account.replace(/"/g, '""')}"`,
      `"${r.storeName.replace(/"/g, '""')}"`,
      `"${r.area.replace(/"/g, '""')}"`,
      `"${r.position.replace(/"/g, '""')}"`,
      `"${(r.vcode || "").replace(/"/g, '""')}"`,
      `"${r.hiredDate || ""}"`,
      `"${r.status.replace(/"/g, '""')}"`,
    ]);

    const csvContent =
      "data:text/csv;charset=utf-8," +
      [headers.join(","), ...rows.map((row) => row.join(","))].join("\n");
    const encodedUri = encodeURI(csvContent);
    const link = document.createElement("a");
    link.setAttribute("href", encodedUri);
    link.setAttribute(
      "download",
      `cencom-deployment-activity-${period}-${new Date().toISOString().split("T")[0]}.csv`
    );
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  const stats = activityResult?.stats;

  return (
    <div className="space-y-6 animate-in fade-in duration-150">
      {/* 1. Header & Period Selector */}
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
        <div>
          <h2 className="text-lg font-bold text-text-primary flex items-center gap-2">
            <TrendingUp className="h-5 w-5 text-brand-500" />
            Deployment Activity & Personnel Movements
          </h2>
          <p className="text-xs text-text-secondary mt-0.5">
            Operational headcount deployments, onboarding velocities, newly deployed personnel, and store placements.
          </p>
        </div>

        {/* Period Filter Buttons */}
        <div className="flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base p-1 shadow-2xs self-start sm:self-auto">
          {(
            [
              { id: "month", label: "This Month" },
              { id: "last_month", label: "Last Month" },
              { id: "last_90_days", label: "Last 90 Days" },
              { id: "all", label: "All Time" },
            ] as const
          ).map((p) => (
            <button
              key={p.id}
              onClick={() => {
                setPeriod(p.id);
                setCurrentPage(1);
              }}
              className={`rounded-md px-3 py-1.5 text-xs font-semibold transition cursor-pointer ${
                period === p.id
                  ? "bg-brand-600 text-white shadow-xs"
                  : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
              }`}
            >
              {p.label}
            </button>
          ))}
        </div>
      </div>

      {/* 2. Deployment Velocity KPIs */}
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-6">
        <MetricCard
          label="Period Deployments"
          value={stats?.totalRecords ?? 0}
          badge={period === "month" ? "This Month" : "Selected Range"}
          helperText="Total personnel deployed"
          isLoading={isLoadingActivity}
        />
        <MetricCard
          label="Pending Emploc"
          value={stats?.pendingEmplocCount ?? 0}
          badge="In Queue"
          helperText="Awaiting employee assignment"
          isLoading={isLoadingActivity}
        />
        <MetricCard
          label="Moved to Plantilla"
          value={stats?.movedToPlantillaCount ?? 0}
          badge="Completed"
          helperText="Active on roster"
          isLoading={isLoadingActivity}
        />
        <MetricCard
          label="Top Account"
          value={stats?.topAccount || "--"}
          badge="High Velocity"
          helperText="Most placements"
          isLoading={isLoadingActivity}
        />
        <MetricCard
          label="Top Store"
          value={stats?.topStore || "--"}
          badge="High Intake"
          helperText="Store with most hires"
          isLoading={isLoadingActivity}
        />
        <MetricCard
          label="Monthly Quotas"
          value={deploymentSummary ? `${deploymentSummary.deployment}` : "--"}
          badge="RPC Synced"
          helperText="New hires from summary"
          isLoading={isLoadingSummary}
        />
      </div>

      {/* 3. Filter Bar & Actions */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="relative flex-1 max-w-md">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted" />
          <input
            type="text"
            placeholder="Search candidate, store, account, position, emploc #..."
            value={searchQuery}
            onChange={(e) => {
              setSearchQuery(e.target.value);
              setCurrentPage(1);
            }}
            className="w-full rounded-lg border border-border-default bg-surface-base pl-9 pr-3 py-2 text-xs text-text-primary placeholder:text-text-muted outline-none transition focus:border-brand-500"
          />
        </div>

        <div className="flex items-center gap-2 flex-wrap">
          {/* Status Filter */}
          <select
            value={statusFilter}
            onChange={(e) => {
              setStatusFilter(e.target.value);
              setCurrentPage(1);
            }}
            className="h-9 rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary outline-none transition focus:border-brand-500"
          >
            <option value="all">All Statuses</option>
            <option value="moved to plantilla">Moved to Plantilla</option>
            <option value="pending emploc">Pending Emploc</option>
            <option value="deployed">Deployed / Active</option>
          </select>

          {/* Account Filter */}
          {accountsList.length > 0 && (
            <select
              value={accountFilter}
              onChange={(e) => {
                setAccountFilter(e.target.value);
                setCurrentPage(1);
              }}
              className="h-9 rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary outline-none transition focus:border-brand-500"
            >
              <option value="all">All Accounts</option>
              {accountsList.map((acc) => (
                <option key={acc} value={acc}>
                  {acc}
                </option>
              ))}
            </select>
          )}

          {/* Export Button */}
          <button
            onClick={handleExportCSV}
            disabled={filteredRecords.length === 0}
            className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-2 text-xs font-semibold text-text-secondary hover:text-text-primary hover:bg-surface-hover disabled:opacity-40 transition cursor-pointer shadow-2xs"
          >
            <Download className="h-3.5 w-3.5" />
            Export CSV
          </button>

          {/* Refresh */}
          <button
            onClick={handleRefresh}
            disabled={isLoadingActivity || isRefetchingActivity || isRefreshing}
            className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base p-2 text-text-secondary hover:text-text-primary hover:bg-surface-hover disabled:opacity-40 transition cursor-pointer shadow-2xs"
            title="Refresh deployments"
          >
            <RefreshCw
              className={`h-3.5 w-3.5 ${
                isLoadingActivity || isRefetchingActivity || isRefreshing
                  ? "animate-spin"
                  : ""
              }`}
            />
          </button>
        </div>
      </div>

      {/* 4. High-Density Deployment Personnel Table */}
      <div className="rounded-xl border border-border-default bg-surface-base overflow-hidden shadow-xs">
        <div className="border-b border-border-default bg-surface-muted px-4 py-3 flex items-center justify-between">
          <h3 className="text-xs font-bold uppercase tracking-wider text-text-secondary">
            DEPLOYED PERSONNEL ACTIVITY ROSTER ({filteredRecords.length})
          </h3>
          <span className="text-xs text-text-muted">
            Page {currentPage} of {totalPages}
          </span>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs">
            <thead className="border-b border-border-default bg-surface-muted/50 text-[10px] font-bold uppercase tracking-wider text-text-secondary">
              <tr>
                <th className="py-2.5 px-4">Candidate / Personnel</th>
                <th className="py-2.5 px-3">Emploc / Emp #</th>
                <th className="py-2.5 px-3">Account</th>
                <th className="py-2.5 px-3">Store & Area</th>
                <th className="py-2.5 px-3">Position</th>
                <th className="py-2.5 px-3">VCode</th>
                <th className="py-2.5 px-3">Hired Date</th>
                <th className="py-2.5 px-4 text-right">Deployment Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle">
              {isLoadingActivity ? (
                <tr>
                  <td colSpan={8} className="py-12 text-center text-text-muted">
                    <div className="flex flex-col items-center justify-center gap-2">
                      <RefreshCw className="h-5 w-5 animate-spin text-brand-600" />
                      <span>Loading deployment personnel records...</span>
                    </div>
                  </td>
                </tr>
              ) : paginatedRecords.length === 0 ? (
                <tr>
                  <td colSpan={8} className="py-12 text-center text-text-muted">
                    No deployment records found for this period and filter selection.
                  </td>
                </tr>
              ) : (
                paginatedRecords.map((record) => {
                  const isPlantilla =
                    record.status.toLowerCase().includes("plantilla") ||
                    record.status.toLowerCase().includes("moved");

                  return (
                    <tr key={record.id} className="hover:bg-surface-hover/70 transition">
                      <td className="py-3 px-4 font-bold text-text-primary">
                        <div className="flex items-center gap-2">
                          <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-surface-muted text-text-primary font-bold text-[11px]">
                            {record.applicantName.charAt(0)}
                          </div>
                          <div>
                            <span className="block font-semibold">
                              {record.applicantName}
                            </span>
                            {record.createdAt && (
                              <span className="text-[10px] text-text-muted">
                                Added {record.createdAt.slice(0, 10)}
                              </span>
                            )}
                          </div>
                        </div>
                      </td>

                      <td className="py-3 px-3 font-mono text-sm text-text-secondary">
                        {record.emplocNo || record.employeeNo || (
                          <span className="text-text-muted italic">Pending</span>
                        )}
                      </td>

                      <td className="py-3 px-3">
                        <span className="inline-flex items-center rounded bg-brand-50 px-2 py-0.5 font-bold text-brand-700 text-[11px] border border-brand-100">
                          {record.account}
                        </span>
                      </td>

                      <td className="py-3 px-3">
                        <div className="font-semibold text-text-primary flex items-center gap-1">
                          <Store className="h-3 w-3 text-text-muted" />
                          <span>{record.storeName}</span>
                        </div>
                        <div className="text-[10px] text-text-muted flex items-center gap-1 mt-0.5">
                          <MapPin className="h-2.5 w-2.5" />
                          <span>{record.area}</span>
                        </div>
                      </td>

                      <td className="py-3 px-3 font-medium text-text-secondary">
                        {record.position}
                      </td>

                      <td className="py-3 px-3 font-mono text-sm text-text-secondary">
                        {record.vcode || "--"}
                      </td>

                      <td className="py-3 px-3 font-mono text-sm text-text-secondary">
                        {record.hiredDate ? (
                          <span className="flex items-center gap-1">
                            <Calendar className="h-3 w-3 text-text-muted" />
                            {record.hiredDate}
                          </span>
                        ) : (
                          "--"
                        )}
                      </td>

                      <td className="py-3 px-4 text-right">
                        <span className="inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-[11px] font-semibold border bg-surface-muted text-text-secondary border-border-default">
                          {isPlantilla ? (
                            <CheckCircle2 className="h-3 w-3 text-text-muted" />
                          ) : (
                            <Clock className="h-3 w-3 text-text-muted" />
                          )}
                          {record.status}
                        </span>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>

        {/* Pagination Bar */}
        {totalPages > 1 && (
          <div className="border-t border-border-default bg-surface-muted/30 px-4 py-3 flex items-center justify-between">
            <span className="text-xs text-text-secondary">
              Showing {(currentPage - 1) * pageSize + 1}–
              {Math.min(currentPage * pageSize, filteredRecords.length)} of{" "}
              {filteredRecords.length} records
            </span>
            <div className="flex items-center gap-1">
              <button
                onClick={() => setCurrentPage((p) => Math.max(1, p - 1))}
                disabled={currentPage === 1}
                className="rounded border border-border-default bg-surface-base px-2.5 py-1 text-xs font-semibold text-text-secondary hover:text-text-primary disabled:opacity-40 transition cursor-pointer"
              >
                Previous
              </button>
              <span className="px-2 text-xs font-mono font-semibold text-text-primary">
                {currentPage} / {totalPages}
              </span>
              <button
                onClick={() => setCurrentPage((p) => Math.min(totalPages, p + 1))}
                disabled={currentPage === totalPages}
                className="rounded border border-border-default bg-surface-base px-2.5 py-1 text-xs font-semibold text-text-secondary hover:text-text-primary disabled:opacity-40 transition cursor-pointer"
              >
                Next
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
