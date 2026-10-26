"use client";

import { useState, useMemo } from "react";
import {
  CheckCircle2,
  ChevronRight,
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
import { useCurrentUser } from "@/lib/auth";
import {
  isOpsTeam,
  isDataTeam,
  hasFullAccess,
  normalizeRole,
  AppRole,
} from "@/lib/rbac";

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
    return <span className="h-2.5 w-2.5 rounded-full bg-pct-bad-text ring-2 ring-pct-bad-border" title="Critical Load" />;
  }
  if (l === "high") {
    return <span className="h-2.5 w-2.5 rounded-full bg-pct-warn-text ring-2 ring-pct-warn-border" title="High Load" />;
  }
  if (l === "medium") {
    return <span className="h-2.5 w-2.5 rounded-full bg-pct-warn-text ring-2 ring-pct-warn-border" title="Medium Load" />;
  }
  return <span className="h-2.5 w-2.5 rounded-full bg-pct-good-text ring-2 ring-pct-good-border" title="Low Load" />;
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

  const currentUser = useCurrentUser();
  const canMutatePool = Boolean(
    currentUser &&
      (isOpsTeam(currentUser) || isDataTeam(currentUser) || hasFullAccess(currentUser)) &&
      normalizeRole(currentUser.roleKey || currentUser.roleName) !== AppRole.VIEWER
  );

  const canExportPool = Boolean(
    currentUser &&
      (isOpsTeam(currentUser) || isDataTeam(currentUser) || hasFullAccess(currentUser))
  );

  // Queries
  const poolTypesQuery = useWorkforcePoolTypes();
  const summariesQuery = useWorkforcePoolSummaries();
  const employeesQuery = useWorkforcePoolEmployees({
    poolTypeId: selectedPoolType === "all" ? undefined : selectedPoolType,
    availability: availabilityFilter === "all" ? undefined : availabilityFilter,
    search: search.trim() || undefined,
  });

  const poolTypes = poolTypesQuery.data ?? [];
  const summaries = useMemo(() => summariesQuery.data ?? [], [summariesQuery.data]);
  const employees = useMemo(() => employeesQuery.data ?? [], [employeesQuery.data]);

  // Summary aggregation
  const overallSummary = useMemo(() => {
    return summaries.reduce(
      (acc, s) => ({
        budgeted: acc.budgeted + s.requiredHc,
        active: acc.active + s.totalCount,
        deployed: acc.deployed + s.deployedCount,
        available: acc.available + s.availableCount,
        review: acc.review + s.reviewCount,
        vacant: acc.vacant + s.vacantHc,
      }),
      { budgeted: 0, active: 0, deployed: 0, available: 0, review: 0, vacant: 0 }
    );
  }, [summaries]);

  // Pagination slice
  const paginatedEmployees = useMemo(() => {
    const start = (page - 1) * pageSize;
    return employees.slice(start, start + pageSize);
  }, [employees, page, pageSize]);

  const handleExport = () => {
    const exportData = employees.map((e) => ({
      "Employee No": e.employeeNo,
      "Employee Name": e.employeeName,
      "Pool Type": e.poolTypeName,
      "Availability Status": e.availabilityStatus,
      "Has Pending Req": e.hasPendingRequest ? "Yes" : "No",
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
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 p-5 rounded-xl border border-border-default bg-surface text-text-primary shadow-xs">
        <div className="space-y-1">
          <div className="flex items-center gap-2">
            <span className="text-lg font-bold tracking-tight">Moses HQ Workforce Pool</span>
            <span className="text-[11px] font-bold uppercase tracking-wider bg-surface-muted text-brand-primary border border-border-default px-2 py-0.5 rounded-full">
              Mobile Parity
            </span>
          </div>
          <p className="text-xs text-text-secondary max-w-xl">
            Command center for managing non-plantilla mobile workforce (Relievers, Commandos, Seasonals),
            cross-store temporary coverage deployments, and slot replenishment.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          {canMutatePool && (
            <button
              type="button"
              onClick={() => setIsHeadcountModalOpen(true)}
              className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-white bg-brand-primary rounded-lg hover:bg-brand-secondary transition-colors cursor-pointer shadow-xs"
            >
              <Plus className="h-3.5 w-3.5" /> Request Pool Headcount
            </button>
          )}
          <button
            type="button"
            onClick={() => setIsOpenSlotsOpen(true)}
            className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-text-primary bg-surface-muted hover:bg-surface-hover border border-border-default rounded-lg transition-colors cursor-pointer"
          >
            <Layers className="h-3.5 w-3.5" /> Approved Slots
          </button>
          <button
            type="button"
            onClick={() => setIsReviewQueueOpen(true)}
            className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-text-primary bg-surface-muted hover:bg-surface-hover border border-border-default rounded-lg transition-colors cursor-pointer"
          >
            <ShieldAlert className="h-3.5 w-3.5" /> Review Queue
          </button>
          <button
            type="button"
            onClick={() => setIsRequestHistoryOpen(true)}
            className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-text-primary bg-surface-muted hover:bg-surface-hover border border-border-default rounded-lg transition-colors cursor-pointer"
          >
            <History className="h-3.5 w-3.5" /> Request History
          </button>
          {canExportPool && (
            <button
              type="button"
              onClick={handleExport}
              className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-text-primary bg-surface-muted hover:bg-surface-hover border border-border-default rounded-lg transition-colors cursor-pointer"
              title="Export pool personnel to Excel"
            >
              <Download className="h-3.5 w-3.5" /> Export
            </button>
          )}
        </div>
      </div>

      {/* KPI Metrics Strip */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
        <MetricCard
          label="Budgeted Slots"
          value={overallSummary.budgeted}
          variant="neutral"
          icon={Layers}
        />
        <MetricCard
          label="Active Personnel"
          value={overallSummary.active}
          variant="neutral"
          icon={Users}
        />
        <MetricCard
          label="Deployed"
          value={overallSummary.deployed}
          variant="positive"
          icon={UserCheck}
        />
        <MetricCard
          label="Available"
          value={overallSummary.available}
          variant="positive"
          icon={CheckCircle2}
        />
        <MetricCard
          label="Under Review"
          value={overallSummary.review}
          variant={overallSummary.review > 0 ? "warning" : "neutral"}
          icon={ShieldAlert}
        />
        <MetricCard
          label="Vacant Slots"
          value={overallSummary.vacant}
          variant={overallSummary.vacant > 0 ? "warning" : "positive"}
          icon={Sparkles}
        />
      </div>

      {/* Filter and Tab Section */}
      <div className="p-4 rounded-xl border border-border-default bg-surface shadow-xs space-y-4">
        {/* Pool Type Tabs */}
        <div className="flex flex-wrap items-center gap-2 border-b border-border-subtle pb-3">
          <button
            type="button"
            onClick={() => {
              setSelectedPoolType("all");
              setPage(1);
            }}
            className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors cursor-pointer ${
              selectedPoolType === "all"
                ? "bg-brand-primary text-white shadow-xs"
                : "bg-surface-muted text-text-secondary hover:bg-surface-hover hover:text-text-primary"
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
                className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors cursor-pointer ${
                  selectedPoolType === pt.id
                    ? "bg-brand-primary text-white shadow-xs"
                    : "bg-surface-muted text-text-secondary hover:bg-surface-hover hover:text-text-primary"
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
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-text-muted" />
            <input
              type="text"
              placeholder="Search pooled employee name, number, VCode, store, or position..."
              value={search}
              onChange={(e) => {
                setSearch(e.target.value);
                setPage(1);
              }}
              className="w-full pl-9 pr-3 py-2 text-xs rounded-lg border border-border-default bg-surface text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:outline-hidden"
            />
          </div>

          <div className="flex items-center gap-2 w-full sm:w-auto">
            <Filter className="h-4 w-4 text-text-muted shrink-0" />
            <select
              value={availabilityFilter}
              onChange={(e) => {
                setAvailabilityFilter(e.target.value);
                setPage(1);
              }}
              className="w-full sm:w-auto text-xs rounded-lg border border-border-default py-2 px-3 bg-surface text-text-primary focus:border-brand-primary focus:outline-hidden font-medium"
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
              className="p-2 text-text-secondary hover:text-text-primary rounded-lg hover:bg-surface-hover transition-colors cursor-pointer"
              title="Refresh"
            >
              <RefreshCw className="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>

      {/* Main Employee Table */}
      <div className="rounded-xl border border-border-default bg-surface shadow-xs overflow-hidden">
        {employeesQuery.isLoading ? (
          <div className="p-12">
            <DataState kind="loading" title="Loading workforce pool personnel..." />
          </div>
        ) : employees.length === 0 ? (
          <div className="p-12">
            <DataState
              kind="empty"
              title="No pool personnel found"
              description="No pooled personnel matched the selected pool type, status, or search query."
            />
          </div>
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm">
                <thead className="bg-table-header border-b border-table-rule text-table-text-muted font-bold uppercase tracking-wider text-xs">
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
                <tbody className="divide-y divide-table-rule text-table-text">
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
                        className="hover:bg-table-row-hover cursor-pointer transition-colors"
                      >
                        <td className="py-3 px-4">
                          <div className="flex items-center gap-3">
                            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-surface-muted text-brand-primary font-bold text-xs border border-border-default">
                              {initials || "EM"}
                            </div>
                            <div>
                              <div className="font-semibold text-table-text hover:text-brand-primary transition-colors text-sm">
                                {emp.employeeName}
                              </div>
                              <div className="text-xs text-table-text-muted font-mono mt-0.5">
                                {emp.employeeNo} {emp.vcode ? `• ${emp.vcode}` : ""}
                              </div>
                            </div>
                          </div>
                        </td>

                        <td className="py-3 px-4">
                          <span className="font-medium text-text-primary bg-surface-muted px-2 py-0.5 rounded text-xs border border-border-default">
                            {emp.poolTypeName}
                          </span>
                        </td>

                        <td className="py-3 px-4">
                          <div className="flex items-center gap-1.5">
                            <StatusBadge variant={getAvailabilityVariant(emp.availabilityStatus)}>
                              {emp.availabilityStatus}
                            </StatusBadge>
                            {emp.hasPendingRequest && (
                              <span className="text-[10px] font-bold text-pct-warn-text bg-pct-warn-bg px-1.5 py-0.5 rounded border border-pct-warn-border uppercase">
                                Req
                              </span>
                            )}
                          </div>
                        </td>

                        <td className="py-3 px-4">
                          {emp.primaryDeploymentStore ? (
                            <div className="flex items-center gap-1.5 text-text-primary font-medium text-sm">
                              <MapPin className="h-3.5 w-3.5 text-brand-primary shrink-0" />
                              <span className="truncate max-w-[180px]">
                                {emp.primaryDeploymentStore}
                              </span>
                            </div>
                          ) : (
                            <span className="text-text-muted italic text-xs">Not deployed</span>
                          )}
                        </td>

                        <td className="py-3 px-4">
                          <div className="flex items-center gap-1.5">
                            {getLoadLevelIndicator(emp.deploymentLoadLevel)}
                            <span className="capitalize text-text-secondary text-xs">
                              {emp.deploymentLoadLevel || "Normal"}
                            </span>
                          </div>
                        </td>

                        <td className="py-3 px-4 text-text-secondary text-sm">
                          {emp.position || "Pooled Staff"}
                        </td>

                        <td className="py-3 px-4 text-right">
                          <span className="inline-flex items-center text-brand-primary font-semibold gap-1 hover:underline text-xs">
                            Manage <ChevronRight className="h-3.5 w-3.5" />
                          </span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>

            <div className="border-t border-border-default px-4 py-3">
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

      {/* Drawers & Modals */}
      {selectedEmployee && (
        <PoolEmployeeDetailDrawer
          employee={selectedEmployee}
          isOpen={Boolean(selectedEmployee)}
          onClose={() => setSelectedEmployee(null)}
          onUpdated={() => {
            employeesQuery.refetch();
            summariesQuery.refetch();
          }}
        />
      )}

      {isOpenSlotsOpen && (
        <PoolOpenSlotsDrawer
          isOpen={isOpenSlotsOpen}
          onClose={() => setIsOpenSlotsOpen(false)}
        />
      )}

      {isReviewQueueOpen && (
        <PoolReviewQueueDrawer
          isOpen={isReviewQueueOpen}
          onClose={() => setIsReviewQueueOpen(false)}
          onUpdated={() => {
            employeesQuery.refetch();
            summariesQuery.refetch();
          }}
        />
      )}

      {isRequestHistoryOpen && (
        <PoolRequestHistoryDrawer
          isOpen={isRequestHistoryOpen}
          onClose={() => setIsRequestHistoryOpen(false)}
        />
      )}

      {isHeadcountModalOpen && (
        <RequestPoolHeadcountModal
          isOpen={isHeadcountModalOpen}
          onClose={() => setIsHeadcountModalOpen(false)}
          onSuccess={() => {
            summariesQuery.refetch();
            employeesQuery.refetch();
          }}
        />
      )}
    </div>
  );
}
