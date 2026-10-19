"use client";

import { useState, useMemo } from "react";
import {
  AlertCircle,
  CheckCircle2,
  ChevronRight,
  Clock,
  Download,
  Filter,
  History,
  Layers,
  MapPin,
  Plus,
  RefreshCw,
  Search,
  ShieldAlert,
  Sparkles,
  UserCheck,
  Users,
} from "lucide-react";
import { MetricCard } from "@/components/shared/MetricCard";
import { TablePagination } from "@/components/shared/TablePagination";
import { DataState } from "@/components/shared/DataState";
import { StatusBadge, type BadgeVariant } from "@/components/ui/StatusBadge";
import { exportToXlsx } from "@/lib/utils/reports_export";
import {
  useWorkforcePoolTypes,
  useWorkforcePoolSummaries,
  useWorkforcePoolEmployees,
  type WorkforcePoolEmployee,
} from "@/lib/queries/workforcePool";
import { PoolEmployeeDetailDrawer } from "@/components/plantilla/PoolEmployeeDetailDrawer";
import { PoolOpenSlotsDrawer } from "@/components/plantilla/PoolOpenSlotsDrawer";
import { PoolReviewQueueDrawer } from "@/components/plantilla/PoolReviewQueueDrawer";
import { PoolRequestHistoryDrawer } from "@/components/plantilla/PoolRequestHistoryDrawer";
import { RequestPoolHeadcountModal } from "@/components/plantilla/RequestPoolHeadcountModal";

function getAvailabilityVariant(status: string): BadgeVariant {
  switch (status.toLowerCase().trim()) {
    case "available":
      return "success";
    case "deployed":
      return "info";
    case "review":
      return "warning";
    case "inactive":
    case "resigned":
    case "terminated":
    case "suspended":
      return "danger";
    default:
      return "neutral";
  }
}

function getLoadLevelIndicator(level?: string | null) {
  if (!level) return null;
  const l = level.toLowerCase();
  if (l === "critical") {
    return <span className="h-2.5 w-2.5 rounded-full bg-red-600 ring-2 ring-red-200" title="Critical Load" />;
  }
  if (l === "high") {
    return <span className="h-2.5 w-2.5 rounded-full bg-orange-500 ring-2 ring-orange-200" title="High Load" />;
  }
  if (l === "medium") {
    return <span className="h-2.5 w-2.5 rounded-full bg-amber-500 ring-2 ring-amber-200" title="Medium Load" />;
  }
  return <span className="h-2.5 w-2.5 rounded-full bg-emerald-500 ring-2 ring-emerald-200" title="Low Load" />;
}

export function MosesHqPoolView() {
  // Navigation & Sub-views State
  const [selectedPoolType, setSelectedPoolType] = useState<string>("all");
  const [availabilityFilter, setAvailabilityFilter] = useState<string>("all");
  const [search, setSearch] = useState<string>("");
  const [page, setPage] = useState<number>(1);
  const [pageSize, setPageSize] = useState<number>(10);

  // Detail & Drawer states
  const [selectedEmployee, setSelectedEmployee] = useState<WorkforcePoolEmployee | null>(null);
  const [isOpenSlotsOpen, setIsOpenSlotsOpen] = useState<boolean>(false);
  const [isReviewQueueOpen, setIsReviewQueueOpen] = useState<boolean>(false);
  const [isRequestHistoryOpen, setIsRequestHistoryOpen] = useState<boolean>(false);
  const [isHeadcountModalOpen, setIsHeadcountModalOpen] = useState<boolean>(false);

  // Queries
  const poolTypesQuery = useWorkforcePoolTypes();
  const summariesQuery = useWorkforcePoolSummaries();
  const employeesQuery = useWorkforcePoolEmployees({
    poolTypeId: selectedPoolType === "all" ? null : selectedPoolType,
    availability: availabilityFilter === "all" ? null : availabilityFilter,
    search: search.trim() || null,
  });

  const poolTypes = poolTypesQuery.data ?? [];
  const summaries = useMemo(() => summariesQuery.data ?? [], [summariesQuery.data]);
  const employees = useMemo(() => employeesQuery.data ?? [], [employeesQuery.data]);

  // Summary Metrics derivation
  const overallSummary = useMemo(() => {
    let req = 0;
    let tot = 0;
    let avail = 0;
    let dep = 0;
    let rev = 0;
    let inact = 0;
    for (const s of summaries) {
      if (selectedPoolType === "all" || s.poolType.id === selectedPoolType) {
        req += s.requiredHc;
        tot += s.totalCount;
        avail += s.availableCount;
        dep += s.deployedCount;
        rev += s.reviewCount;
        inact += s.inactiveCount;
      }
    }
    return {
      required: req,
      total: tot,
      available: avail,
      deployed: dep,
      review: rev,
      inactive: inact,
      vacant: Math.max(0, req - tot),
    };
  }, [summaries, selectedPoolType]);

  // Paginated employees
  const paginatedEmployees = useMemo(() => {
    const start = (page - 1) * pageSize;
    return employees.slice(start, start + pageSize);
  }, [employees, page, pageSize]);

  // Export handler
  const handleExport = () => {
    const exportData = employees.map((e) => ({
      "Employee No": e.employeeNo,
      "Full Name": e.employeeName,
      "Pool Type": e.poolTypeName,
      "Availability Status": e.availabilityStatus,
      "Needs Review": e.needsReview ? "Yes" : "No",
      "Active Stores": e.activeStoreCount,
      "Current Store": e.primaryDeploymentStore || "—",
      "Load Level": e.deploymentLoadLevel || "Normal",
      Position: e.position || "—",
      "Date Hired": e.dateHired || "—",
      "Home Account": e.homeAccount || "—",
      VCode: e.vcode || "—",
    }));
    exportToXlsx(exportData, `Moses_HQ_Pool_${new Date().toISOString().substring(0, 10)}`);
  };

  return (
    <div className="space-y-6">
      {/* Top Banner / Actions Bar */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 p-5 rounded-xl border border-blue-100 bg-linear-to-r from-blue-900 via-indigo-900 to-slate-900 text-white shadow-md">
        <div className="space-y-1">
          <div className="flex items-center gap-2">
            <span className="text-lg font-black tracking-tight">Moses HQ Workforce Pool</span>
            <span className="text-[11px] font-bold uppercase tracking-wider bg-blue-500/30 text-blue-200 border border-blue-400/30 px-2 py-0.5 rounded-full">
              Mobile Parity
            </span>
          </div>
          <p className="text-xs text-blue-200/80 max-w-xl">
            Command center for managing non-plantilla mobile workforce (Relievers, Commandos, Seasonals),
            cross-store temporary coverage deployments, and slot replenishment.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => setIsHeadcountModalOpen(true)}
            className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-white bg-blue-600 rounded-lg hover:bg-blue-500 transition shadow-xs"
          >
            <Plus className="h-3.5 w-3.5" /> Request Pool Headcount
          </button>
          <button
            type="button"
            onClick={() => setIsOpenSlotsOpen(true)}
            className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-white/90 bg-white/10 hover:bg-white/20 border border-white/20 rounded-lg transition"
          >
            <Layers className="h-3.5 w-3.5" /> Approved Slots
          </button>
          <button
            type="button"
            onClick={() => setIsReviewQueueOpen(true)}
            className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-white/90 bg-white/10 hover:bg-white/20 border border-white/20 rounded-lg transition"
          >
            <ShieldAlert className="h-3.5 w-3.5" /> Review Queue
          </button>
          <button
            type="button"
            onClick={() => setIsRequestHistoryOpen(true)}
            className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-white/90 bg-white/10 hover:bg-white/20 border border-white/20 rounded-lg transition"
          >
            <History className="h-3.5 w-3.5" /> Request History
          </button>
          <button
            type="button"
            onClick={handleExport}
            disabled={employees.length === 0}
            className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-white/90 bg-white/10 hover:bg-white/20 border border-white/20 rounded-lg transition disabled:opacity-40"
          >
            <Download className="h-3.5 w-3.5" /> Export
          </button>
        </div>
      </div>

      {/* KPI Counters */}
      <div className="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-7 gap-3">
        <MetricCard
          label="Total Pool"
          value={overallSummary.total}
          variant="default"
          icon={Users}
        />
        <MetricCard
          label="Available"
          value={overallSummary.available}
          variant="positive"
          icon={CheckCircle2}
        />
        <MetricCard
          label="Deployed"
          value={overallSummary.deployed}
          variant="info"
          icon={UserCheck}
        />
        <MetricCard
          label="In Review"
          value={overallSummary.review}
          variant="warning"
          icon={AlertCircle}
        />
        <MetricCard
          label="Inactive"
          value={overallSummary.inactive}
          variant="neutral"
          icon={Clock}
        />
        <MetricCard
          label="Approved Quota"
          value={overallSummary.required}
          variant="default"
          icon={Layers}
        />
        <MetricCard
          label="Vacant Slots"
          value={overallSummary.vacant}
          variant={overallSummary.vacant > 0 ? "warning" : "positive"}
          icon={Sparkles}
        />
      </div>

      {/* Filter and Tab Section */}
      <div className="p-4 rounded-xl border border-gray-200 bg-white shadow-xs space-y-4">
        {/* Pool Type Tabs */}
        <div className="flex flex-wrap items-center gap-2 border-b border-gray-100 pb-3">
          <button
            type="button"
            onClick={() => {
              setSelectedPoolType("all");
              setPage(1);
            }}
            className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition ${
              selectedPoolType === "all"
                ? "bg-gray-900 text-white shadow-xs"
                : "bg-gray-100 text-gray-600 hover:bg-gray-200"
            }`}
          >
            All Pools ({summaries.reduce((acc, s) => acc + s.totalCount, 0)})
          </button>

          {poolTypes.map((pt) => {
            const sum = summaries.find((s) => s.poolType.id === pt.id);
            return (
              <button
                key={pt.id}
                type="button"
                onClick={() => {
                  setSelectedPoolType(pt.id);
                  setPage(1);
                }}
                className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition ${
                  selectedPoolType === pt.id
                    ? "bg-blue-600 text-white shadow-xs"
                    : "bg-gray-100 text-gray-600 hover:bg-gray-200"
                }`}
              >
                {pt.name} ({sum?.totalCount ?? 0})
              </button>
            );
          })}
        </div>

        {/* Search & Availability Filters */}
        <div className="flex flex-col sm:flex-row items-center gap-3">
          <div className="relative flex-1 w-full">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
            <input
              type="text"
              placeholder="Search pooled employee name, number, VCode, store, or position..."
              value={search}
              onChange={(e) => {
                setSearch(e.target.value);
                setPage(1);
              }}
              className="w-full pl-9 pr-3 py-2 text-xs rounded-lg border border-gray-200 focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>

          <div className="flex items-center gap-2 w-full sm:w-auto">
            <Filter className="h-4 w-4 text-gray-400 shrink-0" />
            <select
              value={availabilityFilter}
              onChange={(e) => {
                setAvailabilityFilter(e.target.value);
                setPage(1);
              }}
              className="w-full sm:w-auto text-xs rounded-lg border border-gray-200 py-2 px-3 bg-white focus:outline-none focus:ring-2 focus:ring-blue-500 font-medium"
            >
              <option value="all">All Statuses</option>
              <option value="available">Available</option>
              <option value="deployed">Deployed</option>
              <option value="review">Review Queue</option>
              <option value="inactive">Inactive / Resigned</option>
            </select>

            <button
              type="button"
              onClick={() => {
                employeesQuery.refetch();
                summariesQuery.refetch();
              }}
              className="p-2 text-gray-500 hover:text-gray-700 rounded-lg hover:bg-gray-100 transition"
              title="Refresh"
            >
              <RefreshCw className="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>

      {/* Main Employee Table */}
      <div className="rounded-xl border border-gray-200 bg-white shadow-xs overflow-hidden">
        {employeesQuery.isLoading ? (
          <div className="p-12">
            <DataState state="loading" message="Loading workforce pool personnel..." />
          </div>
        ) : employees.length === 0 ? (
          <div className="p-12">
            <DataState
              state="empty"
              title="No pool personnel found"
              message="No pooled personnel matched the selected pool type, status, or search query."
            />
          </div>
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="w-full text-left text-xs">
                <thead className="bg-gray-50 border-b border-gray-200 text-gray-600 font-bold uppercase tracking-wider text-[11px]">
                  <tr>
                    <th className="py-3 px-4">Employee</th>
                    <th className="py-3 px-4">Pool Type</th>
                    <th className="py-3 px-4">Availability</th>
                    <th className="py-3 px-4">Current Deployment</th>
                    <th className="py-3 px-4">Load</th>
                    <th className="py-3 px-4">Position</th>
                    <th className="py-3 px-4 text-right">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100 text-gray-700">
                  {paginatedEmployees.map((emp) => {
                    const initials = emp.employeeName
                      .split(" ")
                      .map((p) => p[0])
                      .slice(0, 2)
                      .join("")
                      .toUpperCase();

                    return (
                      <tr
                        key={emp.id}
                        onClick={() => setSelectedEmployee(emp)}
                        className="hover:bg-blue-50/50 cursor-pointer transition"
                      >
                        <td className="py-3 px-4">
                          <div className="flex items-center gap-3">
                            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-blue-100 text-blue-700 font-bold text-xs border border-blue-200">
                              {initials || "EM"}
                            </div>
                            <div>
                              <div className="font-semibold text-gray-900 hover:text-blue-600 transition">
                                {emp.employeeName}
                              </div>
                              <div className="text-[11px] text-gray-400 font-mono">
                                {emp.employeeNo} {emp.vcode ? `• ${emp.vcode}` : ""}
                              </div>
                            </div>
                          </div>
                        </td>

                        <td className="py-3 px-4">
                          <span className="font-medium text-gray-900 bg-gray-100 px-2 py-0.5 rounded text-[11px] border border-gray-200">
                            {emp.poolTypeName}
                          </span>
                        </td>

                        <td className="py-3 px-4">
                          <div className="flex items-center gap-1.5">
                            <StatusBadge variant={getAvailabilityVariant(emp.availabilityStatus)}>
                              {emp.availabilityStatus}
                            </StatusBadge>
                            {emp.hasPendingRequest && (
                              <span className="text-[9px] font-bold text-amber-700 bg-amber-100 px-1.5 py-0.5 rounded border border-amber-200 uppercase">
                                Req
                              </span>
                            )}
                          </div>
                        </td>

                        <td className="py-3 px-4">
                          {emp.primaryDeploymentStore ? (
                            <div className="flex items-center gap-1.5 text-gray-900 font-medium">
                              <MapPin className="h-3.5 w-3.5 text-blue-600 shrink-0" />
                              <span className="truncate max-w-[180px]">
                                {emp.primaryDeploymentStore}
                              </span>
                            </div>
                          ) : (
                            <span className="text-gray-400 italic">Not deployed</span>
                          )}
                        </td>

                        <td className="py-3 px-4">
                          <div className="flex items-center gap-1.5">
                            {getLoadLevelIndicator(emp.deploymentLoadLevel)}
                            <span className="capitalize text-gray-600">
                              {emp.deploymentLoadLevel || "Normal"}
                            </span>
                          </div>
                        </td>

                        <td className="py-3 px-4 text-gray-600">
                          {emp.position || "Pooled Staff"}
                        </td>

                        <td className="py-3 px-4 text-right">
                          <span className="inline-flex items-center text-blue-600 font-semibold gap-1 hover:underline text-xs">
                            Manage <ChevronRight className="h-3.5 w-3.5" />
                          </span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>

            <div className="border-t border-gray-200 px-4 py-3">
              <TablePagination
                totalCount={employees.length}
                page={page}
                pageSize={pageSize}
                onPageChange={setPage}
                onPageSizeChange={(newSize) => {
                  setPageSize(newSize);
                  setPage(1);
                }}
              />
            </div>
          </>
        )}
      </div>

      {/* Employee Detail Drawer */}
      <PoolEmployeeDetailDrawer
        employee={selectedEmployee}
        isOpen={Boolean(selectedEmployee)}
        onClose={() => setSelectedEmployee(null)}
        onUpdated={() => {
          employeesQuery.refetch();
          summariesQuery.refetch();
        }}
      />

      {/* Open Slots Drawer */}
      <PoolOpenSlotsDrawer
        isOpen={isOpenSlotsOpen}
        onClose={() => setIsOpenSlotsOpen(false)}
      />

      {/* Review Queue Drawer */}
      <PoolReviewQueueDrawer
        isOpen={isReviewQueueOpen}
        onClose={() => setIsReviewQueueOpen(false)}
      />

      {/* Request History Drawer */}
      <PoolRequestHistoryDrawer
        isOpen={isRequestHistoryOpen}
        onClose={() => setIsRequestHistoryOpen(false)}
      />

      {/* Headcount Modal */}
      <RequestPoolHeadcountModal
        isOpen={isHeadcountModalOpen}
        onClose={() => setIsHeadcountModalOpen(false)}
        onSuccess={() => {
          summariesQuery.refetch();
          employeesQuery.refetch();
        }}
      />
    </div>
  );
}
