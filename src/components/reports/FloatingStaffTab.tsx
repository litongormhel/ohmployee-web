"use client";

import { useMemo, useState } from "react";
import {
  Download,
  FileSpreadsheet,
  Loader2,
  RefreshCw,
  Search,
} from "lucide-react";
import {
  useFloatingReport,
  useReportFilterOptions,
} from "@/lib/queries/reports";
import { exportToCsv, exportToXlsx } from "@/lib/utils/reports_export";

type BucketFilter = "all" | "under30" | "between30And60" | "over60";

function getBucket(days: number): "under30" | "between30And60" | "over60" {
  if (days < 30) return "under30";
  if (days <= 60) return "between30And60";
  return "over60";
}

export function FloatingStaffTab() {
  const [selectedGroupId, setSelectedGroupId] = useState<string>("");
  const [selectedAccountId, setSelectedAccountId] = useState<string>("");
  const [searchQuery, setSearchQuery] = useState("");
  const [activeBucket, setActiveBucket] = useState<BucketFilter>("all");

  const { data: filterOpts } = useReportFilterOptions();
  const groups = filterOpts?.groups ?? [];
  const accounts = filterOpts?.accounts ?? [];

  const filteredAccounts = selectedGroupId
    ? accounts.filter((a) => a.groupId === selectedGroupId)
    : accounts;

  const {
    data: rows = [],
    isLoading,
    isRefetching,
    error,
    refetch,
  } = useFloatingReport(selectedGroupId || null, selectedAccountId || null);

  // Compute KPIs
  const total = rows.length;
  const under30 = rows.filter((r) => getBucket(r.daysFloating) === "under30").length;
  const between30And60 = rows.filter((r) => getBucket(r.daysFloating) === "between30And60").length;
  const over60 = rows.filter((r) => getBucket(r.daysFloating) === "over60").length;

  // Filtered rows
  const filteredRows = useMemo(() => {
    return rows.filter((r) => {
      if (activeBucket !== "all" && getBucket(r.daysFloating) !== activeBucket) {
        return false;
      }
      if (!searchQuery) return true;
      const q = searchQuery.toLowerCase();
      return (
        r.employeeName.toLowerCase().includes(q) ||
        r.employeeNo.toLowerCase().includes(q) ||
        r.position.toLowerCase().includes(q) ||
        r.accountName.toLowerCase().includes(q) ||
        r.groupName.toLowerCase().includes(q) ||
        r.storeName.toLowerCase().includes(q)
      );
    });
  }, [rows, activeBucket, searchQuery]);

  // Account breakdown summary
  const accountBreakdown = useMemo(() => {
    const map = new Map<string, { count: number; group: string }>();
    for (const r of rows) {
      const prev = map.get(r.accountName) ?? { count: 0, group: r.groupName };
      map.set(r.accountName, { count: prev.count + 1, group: r.groupName });
    }
    return Array.from(map.entries())
      .map(([account, val]) => ({ account, group: val.group, count: val.count }))
      .sort((a, b) => b.count - a.count);
  }, [rows]);

  // Exports
  const handleExportXlsx = () => {
    exportToXlsx(
      filteredRows.map((r) => ({
        "Employee No": r.employeeNo || "—",
        "Employee Name": r.employeeName,
        Position: r.position,
        Account: r.accountName,
        Group: r.groupName,
        "Store Branch": r.storeName || "—",
        "Floating Since": r.floatingSince ? r.floatingSince.substring(0, 10) : "—",
        "Days Floating": r.daysFloating,
        "Aging Category":
          r.daysFloating < 30 ? "< 30 Days" : r.daysFloating <= 60 ? "30–60 Days" : "> 60 Days",
        "Employment Type": r.employmentType,
        Status: r.status,
      })),
      `Floating_Staff_${new Date().toISOString().split("T")[0]}`
    );
  };

  const handleExportCsv = () => {
    exportToCsv(
      filteredRows.map((r) => ({
        "Employee No": r.employeeNo || "—",
        "Employee Name": r.employeeName,
        Position: r.position,
        Account: r.accountName,
        Group: r.groupName,
        "Store Branch": r.storeName || "—",
        "Floating Since": r.floatingSince ? r.floatingSince.substring(0, 10) : "—",
        "Days Floating": r.daysFloating,
        "Aging Category":
          r.daysFloating < 30 ? "< 30 Days" : r.daysFloating <= 60 ? "30–60 Days" : "> 60 Days",
        "Employment Type": r.employmentType,
        Status: r.status,
      })),
      `Floating_Staff_${new Date().toISOString().split("T")[0]}`
    );
  };

  return (
    <div className="space-y-6 animate-in fade-in duration-150">
      {/* Header */}
      <div className="flex flex-wrap items-center justify-between gap-4 pb-4 border-b border-border-subtle">
        <div>
          <div className="flex items-center gap-2">
            <span className="text-[10px] font-bold uppercase tracking-wider text-amber-700 bg-amber-50 px-2 py-0.5 rounded border border-amber-200">
              Operational Staffing
            </span>
            <span className="text-xs text-text-muted">Port of FloatingReportScreen</span>
          </div>
          <h2 className="text-xl font-bold text-text-primary mt-0.5 tracking-tight">
            Floating Staff Monitoring & Aging
          </h2>
          <p className="text-xs text-text-secondary mt-0.5">
            Track unassigned and floating personnel duration, identify aged retention risks, and reassign workforce capacity.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => refetch()}
            disabled={isLoading || isRefetching}
            className="flex items-center gap-1.5 h-8 px-3 text-xs font-semibold text-text-secondary bg-surface-base hover:bg-surface-hover border border-border-default rounded-lg transition cursor-pointer disabled:opacity-50"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${isRefetching ? "animate-spin text-brand-600" : ""}`} />
            Refresh
          </button>
          <button
            onClick={handleExportXlsx}
            disabled={isLoading || !filteredRows.length}
            className="flex items-center gap-1.5 h-8 px-3 text-xs font-semibold text-emerald-700 bg-emerald-50 hover:bg-emerald-100 border border-emerald-200 rounded-lg transition cursor-pointer disabled:opacity-50"
          >
            <FileSpreadsheet className="w-3.5 h-3.5" />
            Export XLSX
          </button>
          <button
            onClick={handleExportCsv}
            disabled={isLoading || !filteredRows.length}
            className="flex items-center gap-1.5 h-8 px-3 text-xs font-semibold text-text-secondary bg-surface-base hover:bg-surface-hover border border-border-default rounded-lg transition cursor-pointer disabled:opacity-50"
          >
            <Download className="w-3.5 h-3.5" />
            CSV
          </button>
        </div>
      </div>

      {/* KPI Cards Strip (Clickable Bucket Filters) */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <button
          onClick={() => setActiveBucket("all")}
          className={`p-4 rounded-xl border text-left transition cursor-pointer shadow-2xs ${
            activeBucket === "all"
              ? "border-brand-500 bg-brand-50/50 ring-2 ring-brand-500/20"
              : "border-border-default bg-surface-base hover:border-slate-300"
          }`}
        >
          <div className="text-[11px] font-semibold uppercase tracking-wider text-text-muted">
            Total Floating Staff
          </div>
          <div className="text-2xl font-bold text-text-primary mt-1">{total}</div>
          <div className="text-[11px] text-text-muted mt-0.5">Across all accounts</div>
        </button>

        <button
          onClick={() => setActiveBucket("under30")}
          className={`p-4 rounded-xl border text-left transition cursor-pointer shadow-2xs ${
            activeBucket === "under30"
              ? "border-emerald-500 bg-emerald-50/50 ring-2 ring-emerald-500/20"
              : "border-border-default bg-surface-base hover:border-emerald-200"
          }`}
        >
          <div className="text-[11px] font-semibold uppercase tracking-wider text-emerald-700 flex items-center justify-between">
            <span>&lt; 30 Days</span>
            <span className="w-2 h-2 rounded-full bg-emerald-500" />
          </div>
          <div className="text-2xl font-bold text-emerald-700 mt-1">{under30}</div>
          <div className="text-[11px] text-emerald-600/80 mt-0.5">Fresh floating status</div>
        </button>

        <button
          onClick={() => setActiveBucket("between30And60")}
          className={`p-4 rounded-xl border text-left transition cursor-pointer shadow-2xs ${
            activeBucket === "between30And60"
              ? "border-amber-500 bg-amber-50/50 ring-2 ring-amber-500/20"
              : "border-border-default bg-surface-base hover:border-amber-200"
          }`}
        >
          <div className="text-[11px] font-semibold uppercase tracking-wider text-amber-700 flex items-center justify-between">
            <span>30–60 Days</span>
            <span className="w-2 h-2 rounded-full bg-amber-500" />
          </div>
          <div className="text-2xl font-bold text-amber-700 mt-1">{between30And60}</div>
          <div className="text-[11px] text-amber-600/80 mt-0.5">Moderate aging warning</div>
        </button>

        <button
          onClick={() => setActiveBucket("over60")}
          className={`p-4 rounded-xl border text-left transition cursor-pointer shadow-2xs ${
            activeBucket === "over60"
              ? "border-rose-500 bg-rose-50/50 ring-2 ring-rose-500/20"
              : "border-border-default bg-surface-base hover:border-rose-200"
          }`}
        >
          <div className="text-[11px] font-semibold uppercase tracking-wider text-rose-700 flex items-center justify-between">
            <span>&gt; 60 Days</span>
            <span className="w-2 h-2 rounded-full bg-rose-500" />
          </div>
          <div className="text-2xl font-bold text-rose-700 mt-1">{over60}</div>
          <div className="text-[11px] text-rose-600/80 mt-0.5">Critical stagnation risk</div>
        </button>
      </div>

      {/* Filter Toolbar */}
      <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs grid grid-cols-1 sm:grid-cols-3 gap-3">
        <div>
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
            placeholder="Search employee, no, store, position..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full h-8 pl-8 pr-3 text-xs bg-surface-base border border-border-default rounded-md focus:outline-hidden focus:border-brand-500"
          />
        </div>

        {/* Account distribution pills */}
        {accountBreakdown.length > 0 && (
          <div className="sm:col-span-3 flex items-center gap-1.5 overflow-x-auto no-scrollbar pt-1">
            <span className="text-[10px] font-semibold text-text-muted uppercase tracking-wider shrink-0 mr-1">
              By Account:
            </span>
            {accountBreakdown.map((item) => {
              const isSelected = selectedAccountId && accounts.find((a) => a.id === selectedAccountId)?.name === item.account;
              return (
                <button
                  key={item.account}
                  onClick={() => {
                    if (isSelected) {
                      setSelectedAccountId("");
                    } else {
                      const match = accounts.find((a) => a.name === item.account);
                      if (match) setSelectedAccountId(match.id);
                    }
                  }}
                  className={`inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-[11px] font-medium border transition cursor-pointer shrink-0 ${
                    isSelected
                      ? "bg-brand-50 border-brand-300 text-brand-800 font-semibold"
                      : "bg-surface-muted/60 border-border-subtle text-text-secondary hover:bg-surface-hover"
                  }`}
                >
                  <span>{item.account}</span>
                  <span className="text-[10px] px-1.5 py-0.2 rounded-full bg-surface-base border border-border-subtle font-bold">
                    {item.count}
                  </span>
                </button>
              );
            })}
          </div>
        )}
      </div>

      {/* Main Table */}
      <div className="rounded-xl border border-border-default bg-surface-base shadow-2xs overflow-hidden">
        {isLoading ? (
          <div className="flex flex-col items-center justify-center py-24 text-text-muted">
            <Loader2 className="w-8 h-8 animate-spin text-brand-600 mb-2" />
            <p className="text-xs font-medium">Loading floating employee roster...</p>
          </div>
        ) : error ? (
          <div className="p-8 text-center">
            <p className="text-sm font-semibold text-rose-700">Failed to load floating staff data</p>
            <p className="text-xs text-text-muted mt-1">{String(error)}</p>
            <button
              onClick={() => refetch()}
              className="mt-4 px-4 py-1.5 text-xs font-semibold text-brand-700 bg-brand-50 border border-brand-200 rounded-lg hover:bg-brand-100 transition cursor-pointer"
            >
              Retry Query
            </button>
          </div>
        ) : filteredRows.length === 0 ? (
          <div className="py-20 text-center text-text-muted text-xs">
            No floating staff records match the selected filters.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead className="bg-surface-muted border-b border-border-subtle text-text-secondary uppercase text-[10px] tracking-wider font-semibold">
                <tr>
                  <th className="py-3 px-4">Employee</th>
                  <th className="py-3 px-4">Position</th>
                  <th className="py-3 px-4">Account / Group</th>
                  <th className="py-3 px-4">Last Store Branch</th>
                  <th className="py-3 px-4">Floating Since</th>
                  <th className="py-3 px-4">Duration & Aging</th>
                  <th className="py-3 px-4 text-right">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border-subtle font-medium">
                {filteredRows.map((r) => {
                  const bucket = getBucket(r.daysFloating);
                  return (
                    <tr key={r.plantillaId} className="hover:bg-surface-hover/50 transition">
                      <td className="py-3 px-4">
                        <div className="font-semibold text-text-primary">{r.employeeName}</div>
                        <div className="text-[10px] font-mono text-text-muted">
                          {r.employeeNo ? `#${r.employeeNo}` : "No Emp #"}
                        </div>
                      </td>
                      <td className="py-3 px-4 text-text-secondary">{r.position || "Staff"}</td>
                      <td className="py-3 px-4">
                        <div className="font-medium text-text-primary">{r.accountName}</div>
                        <div className="text-[10px] text-text-muted">{r.groupName}</div>
                      </td>
                      <td className="py-3 px-4 text-text-secondary">
                        {r.storeName || "Unassigned"}
                      </td>
                      <td className="py-3 px-4 font-mono text-[11px] text-text-secondary">
                        {r.floatingSince ? r.floatingSince.substring(0, 10) : "—"}
                      </td>
                      <td className="py-3 px-4">
                        <span
                          className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-bold border ${
                            bucket === "under30"
                              ? "bg-emerald-50 text-emerald-700 border-emerald-200"
                              : bucket === "between30And60"
                              ? "bg-amber-50 text-amber-700 border-amber-200"
                              : "bg-rose-50 text-rose-700 border-rose-200"
                          }`}
                        >
                          {r.daysFloating} days
                        </span>
                      </td>
                      <td className="py-3 px-4 text-right">
                        <span className="inline-flex items-center px-2 py-0.5 rounded text-[10px] font-semibold bg-slate-100 text-slate-700 border border-slate-200">
                          {r.employmentType || "Stationary"}
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        {/* Footer */}
        <div className="flex items-center justify-between px-4 py-3 border-t border-border-subtle bg-surface-muted/30 text-xs text-text-muted">
          <span>
            Showing {filteredRows.length} of {rows.length} floating personnel • {under30} &lt;30d • {between30And60} 30–60d • {over60} &gt;60d
          </span>
        </div>
      </div>
    </div>
  );
}
