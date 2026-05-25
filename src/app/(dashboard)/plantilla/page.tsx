"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { LockKeyhole, Users } from "lucide-react";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { MetricCard } from "@/components/shared/MetricCard";
import { AdminFilterBar } from "@/components/shared/AdminFilterBar";
import { DataState } from "@/components/shared/DataState";
import { StatusBadge } from "@/components/ui/StatusBadge";
import type { BadgeVariant } from "@/components/ui/StatusBadge";
import {
  getPlantillaSummary,
  listWebPlantillaEmployees,
  listWebPlantillaStoreStaffing,
  deriveDeactivationOverlay,
  deriveStaffingRisk,
  PlantillaDataError,
  type PlantillaEmployeeListItem,
  type PlantillaStoreStaffingRow,
} from "@/lib/queries/plantilla";
import { PlantillaDetailDrawer } from "@/components/plantilla/PlantillaDetailDrawer";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type ViewMode = "employee" | "store";

// ---------------------------------------------------------------------------
// Status helpers
// ---------------------------------------------------------------------------

function plantillaStatusVariant(status: string | null | undefined): BadgeVariant {
  switch ((status ?? "").toLowerCase()) {
    case "active":
      return "success";
    case "pending transfer":
    case "pending_transfer":
      return "info";
    case "pending separation":
    case "pending_separation":
      return "danger";
    case "suspended":
      return "warning";
    case "inactive":
    case "terminated":
      return "neutral";
    default:
      return "neutral";
  }
}

function staffingSlaVariant(status: string | null | undefined): BadgeVariant {
  switch ((status ?? "").toLowerCase()) {
    case "fully-staffed":
      return "success";
    case "under-staffed":
      return "danger";
    case "over-staffed":
      return "warning";
    default:
      return "neutral";
  }
}

// ---------------------------------------------------------------------------
// Filter option constants
// ---------------------------------------------------------------------------

const STATUS_OPTIONS = [
  { value: "", label: "All Statuses" },
  { value: "active", label: "Active" },
  { value: "pending_transfer", label: "Pending Transfer" },
  { value: "pending_separation", label: "Pending Separation" },
  { value: "suspended", label: "Suspended" },
  { value: "inactive", label: "Inactive" },
];

const DEPLOYMENT_TYPE_OPTIONS = [
  { value: "", label: "All Types" },
  { value: "budgeted", label: "Budgeted" },
  { value: "additional", label: "Additional (AH)" },
];

const STAFFING_RISK_OPTIONS = [
  { value: "", label: "All SLA Status" },
  { value: "under-staffed", label: "Under-Staffed" },
  { value: "fully-staffed", label: "Fully-Staffed" },
  { value: "over-staffed", label: "Over-Staffed" },
];

const PAGE_SIZE = 25;

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function PlantillaPage() {
  const [view, setView] = useState<ViewMode>("employee");
  const [page, setPage] = useState(1);
  const [selectedPlantillaId, setSelectedPlantillaId] = useState<string | null>(null);

  // Committed filter values (drive queries)
  const [search, setSearch] = useState("");
  const [accountId, setAccountId] = useState("");

  // Pending (unsubmitted) filter values
  const [pendingSearch, setPendingSearch] = useState("");
  const [pendingAccountId, setPendingAccountId] = useState("");
  // groupId is captured in the filter bar but not yet in the RPC contract
  const [pendingGroupId, setPendingGroupId] = useState("");

  // Employee-specific pending filters
  const [pendingStoreId, setPendingStoreId] = useState("");
  const [pendingStatus, setPendingStatus] = useState("");
  const [pendingPlantillaType, setPendingPlantillaType] = useState("");

  // Committed employee filters
  const [storeId, setStoreId] = useState("");
  const [status, setStatus] = useState("");
  const [plantillaType, setPlantillaType] = useState("");

  // Store-specific pending filters
  const [pendingSlaStatus, setPendingSlaStatus] = useState("");

  // Committed store filters
  const [slaStatus, setSlaStatus] = useState("");

  // -------------------------------------------------------------------------
  // Queries
  // -------------------------------------------------------------------------

  const summaryQuery = useQuery({
    queryKey: ["plantilla", "summary", accountId],
    queryFn: () =>
      getPlantillaSummary({ accountId: accountId || undefined }),
  });

  const employeeQuery = useQuery({
    queryKey: [
      "plantilla",
      "employees",
      { search, accountId, storeId, status, plantillaType, page },
    ],
    queryFn: () =>
      listWebPlantillaEmployees({
        search: search || undefined,
        accountId: accountId || undefined,
        storeId: storeId || undefined,
        status: status || undefined,
        plantillaType: plantillaType || undefined,
        page,
        pageSize: PAGE_SIZE,
      }),
    enabled: view === "employee",
  });

  const storeQuery = useQuery({
    queryKey: ["plantilla", "stores", { search, accountId, slaStatus, page }],
    queryFn: () =>
      listWebPlantillaStoreStaffing({
        search: search || undefined,
        accountId: accountId || undefined,
        slaStatus: slaStatus || undefined,
        page,
        pageSize: PAGE_SIZE,
      }),
    enabled: view === "store",
  });

  // -------------------------------------------------------------------------
  // Derived state
  // -------------------------------------------------------------------------

  const summaryData = summaryQuery.data;
  const summaryError =
    summaryQuery.error instanceof PlantillaDataError ? summaryQuery.error : null;
  const summaryBlocked = summaryError?.kind === "access_denied";

  const activeListQuery = view === "employee" ? employeeQuery : storeQuery;
  const listError =
    activeListQuery.error instanceof PlantillaDataError ? activeListQuery.error : null;

  const isListLoading = activeListQuery.isLoading;
  const isListError = activeListQuery.isError && !isListLoading;
  const isAccessDenied = listError?.kind === "access_denied";
  const isRetryable = isListError && !isAccessDenied;

  const employeeRows = employeeQuery.data?.data ?? [];
  const storeRows = storeQuery.data?.data ?? [];
  const totalCount = activeListQuery.data?.totalCount ?? 0;
  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));

  // -------------------------------------------------------------------------
  // Handlers
  // -------------------------------------------------------------------------

  function handleApply() {
    setSearch(pendingSearch);
    setAccountId(pendingAccountId);
    setStoreId(pendingStoreId);
    setStatus(pendingStatus);
    setPlantillaType(pendingPlantillaType);
    setSlaStatus(pendingSlaStatus);
    setPage(1);
  }

  function handleReset() {
    setPendingSearch("");
    setPendingAccountId("");
    setPendingGroupId("");
    setPendingStoreId("");
    setPendingStatus("");
    setPendingPlantillaType("");
    setPendingSlaStatus("");
    setSearch("");
    setAccountId("");
    setStoreId("");
    setStatus("");
    setPlantillaType("");
    setSlaStatus("");
    setPage(1);
  }

  function switchView(next: ViewMode) {
    if (next !== view) {
      setView(next);
      setPage(1);
    }
  }

  // -------------------------------------------------------------------------
  // List content
  // -------------------------------------------------------------------------

  function renderListContent() {
    if (isListLoading) {
      return (
        <DataState
          kind="loading"
          title="Loading plantilla records"
          description="Fetching personnel and store data through Supabase RPCs."
        />
      );
    }

    if (isAccessDenied) {
      return (
        <DataState
          kind="access_denied"
          title="Access Restricted"
          description="Supabase RLS policies blocked this read. You are not authorized to view plantilla records outside your scoped boundary."
        />
      );
    }

    if (isRetryable) {
      return (
        <DataState
          kind="error"
          title="Fetch Failed"
          description={
            listError?.message ??
            "The plantilla query failed. You can retry without changing filters."
          }
          onRetry={() => activeListQuery.refetch()}
        />
      );
    }

    if (view === "employee") {
      if (employeeRows.length === 0) {
        return (
          <DataState
            kind="empty"
            title="No employee records found"
            description="No active plantilla employees match the current filters."
          />
        );
      }
      return <EmployeeTable rows={employeeRows} onRowClick={setSelectedPlantillaId} />;
    }

    if (storeRows.length === 0) {
      return (
        <DataState
          kind="empty"
          title="No store records found"
          description="No store staffing records match the current filters."
        />
      );
    }
    return <StoreTable rows={storeRows} />;
  }

  // -------------------------------------------------------------------------
  // View toggle element (injected into filter bar)
  // -------------------------------------------------------------------------

  const viewToggle = (
    <div
      aria-label="Plantilla view mode"
      className="flex items-center overflow-hidden rounded-md border border-border-default"
      role="tablist"
    >
      <button
        aria-selected={view === "employee"}
        role="tab"
        type="button"
        className={`h-9 px-3 text-sm font-medium transition-colors ${
          view === "employee"
            ? "bg-brand-600 text-white"
            : "bg-surface-base text-text-secondary hover:bg-surface-hover"
        }`}
        onClick={() => switchView("employee")}
      >
        Employee View
      </button>
      <button
        aria-selected={view === "store"}
        role="tab"
        type="button"
        className={`h-9 border-l border-border-default px-3 text-sm font-medium transition-colors ${
          view === "store"
            ? "bg-brand-600 text-white"
            : "bg-surface-base text-text-secondary hover:bg-surface-hover"
        }`}
        onClick={() => switchView("store")}
      >
        Store Staffing
      </button>
    </div>
  );

  const selectClass =
    "h-9 rounded-md border border-border-default bg-surface-muted px-2 text-sm text-text-primary outline-none focus:border-brand-500 transition-colors";

  const inputClass =
    "h-9 rounded-md border border-border-default bg-surface-muted px-3 text-sm text-text-primary outline-none focus:border-brand-500 transition-colors w-32";

  // -------------------------------------------------------------------------
  // Render
  // -------------------------------------------------------------------------

  return (
    <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-4 p-4 text-gray-900 sm:p-5">
      <AdminPageHeader
        title="Plantilla Directory"
        subtitle="Manage active personnel, audit store capacities, and govern movements."
        icon={Users}
        readOnly
      />

      {/* KPI summary row */}
      <section
        aria-label="Plantilla summary metrics"
        className="grid gap-2 sm:grid-cols-2 xl:grid-cols-4"
      >
        <MetricCard
          label="Active Roster"
          value={summaryData?.totalActiveRoster}
          helperText="Total active deployed employees"
          isLoading={summaryQuery.isLoading}
          isBlocked={summaryBlocked}
          isError={!summaryBlocked && summaryQuery.isError}
          errorText="Summary data failed to load"
          badgeLabel="RPC"
        />
        <MetricCard
          label="Budgeted Slots"
          value={summaryData?.totalBudgetedSlots}
          helperText="Standard contracted allocations"
          isLoading={summaryQuery.isLoading}
          isBlocked={summaryBlocked}
          isError={!summaryBlocked && summaryQuery.isError}
          errorText="Summary data failed to load"
          badgeLabel="RPC"
        />
        <MetricCard
          label="AH (Temp) Slots"
          value={summaryData?.totalAdditionalSlots}
          helperText="Active additional headcount slots"
          isLoading={summaryQuery.isLoading}
          isBlocked={summaryBlocked}
          isError={!summaryBlocked && summaryQuery.isError}
          errorText="Summary data failed to load"
          badgeLabel="RPC"
        />
        <MetricCard
          label="Under-Staffed"
          value={summaryData?.understaffedStores}
          helperText="Stores below budgeted target"
          isLoading={summaryQuery.isLoading}
          isBlocked={summaryBlocked}
          isError={!summaryBlocked && summaryQuery.isError}
          errorText="Summary data failed to load"
          badgeLabel="RPC"
        />
      </section>

      {/* Filter bar */}
      <AdminFilterBar
        searchPlaceholder="Search by employee, store, or VCode..."
        searchVal={pendingSearch}
        onSearchChange={setPendingSearch}
        onApply={handleApply}
        onReset={handleReset}
        showResetButton
        resetLabel="Reset"
        filterSlot={
          <div className="flex flex-wrap items-center gap-2">
            {viewToggle}

            <input
              type="text"
              placeholder="Account ID"
              value={pendingAccountId}
              onChange={(e) => setPendingAccountId(e.target.value)}
              className={inputClass}
              aria-label="Filter by account ID"
            />

            <input
              type="text"
              placeholder="Group ID"
              value={pendingGroupId}
              onChange={(e) => setPendingGroupId(e.target.value)}
              className={inputClass}
              aria-label="Filter by group ID"
            />

            {view === "employee" && (
              <>
                <input
                  type="text"
                  placeholder="Store ID"
                  value={pendingStoreId}
                  onChange={(e) => setPendingStoreId(e.target.value)}
                  className={inputClass}
                  aria-label="Filter by store ID"
                />

                <select
                  value={pendingStatus}
                  onChange={(e) => setPendingStatus(e.target.value)}
                  className={selectClass}
                  aria-label="Filter by employment status"
                >
                  {STATUS_OPTIONS.map((o) => (
                    <option key={o.value} value={o.value}>
                      {o.label}
                    </option>
                  ))}
                </select>

                <select
                  value={pendingPlantillaType}
                  onChange={(e) => setPendingPlantillaType(e.target.value)}
                  className={selectClass}
                  aria-label="Filter by deployment type"
                >
                  {DEPLOYMENT_TYPE_OPTIONS.map((o) => (
                    <option key={o.value} value={o.value}>
                      {o.label}
                    </option>
                  ))}
                </select>
              </>
            )}

            {view === "store" && (
              <select
                value={pendingSlaStatus}
                onChange={(e) => setPendingSlaStatus(e.target.value)}
                className={selectClass}
                aria-label="Filter by staffing risk"
              >
                {STAFFING_RISK_OPTIONS.map((o) => (
                  <option key={o.value} value={o.value}>
                    {o.label}
                  </option>
                ))}
              </select>
            )}
          </div>
        }
      />

      {/* Detail drawer */}
      <PlantillaDetailDrawer
        plantillaId={selectedPlantillaId}
        onClose={() => setSelectedPlantillaId(null)}
      />

      {/* Table area */}
      <div className="overflow-hidden rounded-md border border-border-default bg-surface-base">
        {renderListContent()}

        {!isListLoading && !isListError && totalCount > 0 && (
          <div className="flex items-center justify-between border-t border-border-default px-4 py-2 text-xs text-text-muted">
            <span>
              {totalCount.toLocaleString()} record
              {totalCount !== 1 ? "s" : ""}
            </span>
            {totalPages > 1 && (
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  disabled={page <= 1}
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                  className="h-7 rounded border border-border-default px-2 text-xs font-medium text-text-secondary transition-colors hover:bg-surface-hover disabled:cursor-not-allowed disabled:opacity-40"
                >
                  Previous
                </button>
                <span>
                  {page} / {totalPages}
                </span>
                <button
                  type="button"
                  disabled={page >= totalPages}
                  onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                  className="h-7 rounded border border-border-default px-2 text-xs font-medium text-text-secondary transition-colors hover:bg-surface-hover disabled:cursor-not-allowed disabled:opacity-40"
                >
                  Next
                </button>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Footer system boundaries notice */}
      <section className="rounded-md border border-dashed border-gray-300 bg-gray-50 p-3">
        <div className="flex items-start gap-2 text-xs text-gray-600">
          <LockKeyhole className="mt-0.5 h-4 w-4 text-gray-400 shrink-0" aria-hidden="true" />
          <div>
            <span className="font-semibold text-gray-700">Read-Only Boundary:</span> Plantilla reads use{" "}
            <code className="font-mono bg-gray-100 px-1 rounded text-[11px]">get_web_plantilla_summary</code>,{" "}
            <code className="font-mono bg-gray-100 px-1 rounded text-[11px]">list_web_plantilla_employees</code>, and{" "}
            <code className="font-mono bg-gray-100 px-1 rounded text-[11px]">list_web_plantilla_store_staffing</code>.
            Employee transfers, AH slot management, separations, and other mutations remain disabled until backend action RPCs are approved.
          </div>
        </div>
      </section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Employee table
// ---------------------------------------------------------------------------

function EmployeeTable({
  rows,
  onRowClick,
}: {
  rows: PlantillaEmployeeListItem[];
  onRowClick: (id: string) => void;
}) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[1120px] text-sm">
        <thead>
          <tr className="border-b border-table-rule bg-table-header">
            <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-table-text-muted">
              Emp ID
            </th>
            <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-table-text-muted">
              Name
            </th>
            <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-table-text-muted">
              Account / Store
            </th>
            <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-table-text-muted">
              Position
            </th>
            <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-table-text-muted">
              Assignment
            </th>
            <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-table-text-muted">
              Type
            </th>
            <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-table-text-muted">
              Status
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-table-rule">
          {rows.map((row) => {
            const overlay = deriveDeactivationOverlay(row.plantillaStatus);

            const isClickable = !overlay.isDimmed;

            const rowClass = [
              "transition-colors",
              overlay.isPendingSeparation
                ? "border border-dashed border-status-danger-border bg-red-50/30 opacity-80 cursor-pointer"
                : overlay.isDimmed
                  ? "pointer-events-none opacity-65"
                  : "hover:bg-table-row-hover cursor-pointer",
            ].join(" ");

            const dimText = overlay.isDimmed
              ? "line-through decoration-gray-300 text-gray-400"
              : "";

            const displayName =
              row.lastName && row.firstName
                ? `${row.lastName}, ${row.firstName}`
                : (row.lastName ?? row.firstName ?? "—");

            return (
              <tr
                key={row.id}
                className={rowClass}
                onClick={isClickable ? () => onRowClick(row.id) : undefined}
                onKeyDown={
                  isClickable
                    ? (e) => {
                        if (e.key === "Enter" || e.key === " ") {
                          e.preventDefault();
                          onRowClick(row.id);
                        }
                      }
                    : undefined
                }
                tabIndex={isClickable ? 0 : undefined}
                role={isClickable ? "button" : undefined}
                aria-label={isClickable ? `View details for ${displayName}` : undefined}
              >
                <td className="px-3 py-2.5">
                  <span
                    className={`font-mono text-xs bg-mono-pill-surface border border-mono-pill-ring rounded px-1.5 py-0.5 ${
                      overlay.isDimmed ? "text-gray-400 line-through decoration-gray-300" : "text-table-text"
                    }`}
                  >
                    {row.employeeNo}
                  </span>
                </td>

                <td className="px-3 py-2.5 font-medium text-table-text">
                  <span className={dimText}>{displayName}</span>
                  {!overlay.isDimmed && row.plantillaType === "AH" && (
                    <span className="ml-1.5 inline-flex items-center rounded border border-status-warning-border bg-amber-50 px-1.5 py-0.5 text-xs font-semibold text-status-warning-text">
                      AH
                    </span>
                  )}
                </td>

                <td className="px-3 py-2.5 text-table-text-sub">
                  <div className="leading-tight">
                    <div className={dimText}>{row.accountName ?? "—"}</div>
                    {row.primaryStoreName && (
                      <div className={`text-xs text-table-text-muted ${dimText}`}>
                        {row.primaryStoreName}
                      </div>
                    )}
                  </div>
                </td>

                <td className={`px-3 py-2.5 text-table-text-sub ${dimText}`}>
                  {row.positionTitle ?? "—"}
                </td>

                <td className={`px-3 py-2.5 text-table-text-sub ${dimText}`}>
                  {row.assignmentType === "Roving" && row.coveredStoresCount > 0 ? (
                    <span title={`Covers ${row.coveredStoresCount} store(s)`}>
                      Roving ({row.coveredStoresCount})
                    </span>
                  ) : (
                    (row.assignmentType ?? "—")
                  )}
                </td>

                <td className={`px-3 py-2.5 text-xs text-table-text-sub ${dimText}`}>
                  {row.plantillaType ?? "—"}
                </td>

                <td className="px-3 py-2.5">
                  {row.plantillaStatus ? (
                    <span className="inline-flex items-center gap-1">
                      <StatusBadge
                        variant={plantillaStatusVariant(row.plantillaStatus)}
                        text={row.plantillaStatus}
                      />
                      {row.slaBreached && (
                        <span
                          className="text-xs font-semibold text-status-danger-text"
                          title="SLA breached"
                        >
                          ⚠
                        </span>
                      )}
                    </span>
                  ) : (
                    <span className="text-xs text-table-text-muted">—</span>
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Store staffing table
// ---------------------------------------------------------------------------

function StoreTable({ rows }: { rows: PlantillaStoreStaffingRow[] }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[1120px] text-sm">
        <thead>
          <tr className="border-b border-table-rule bg-table-header">
            <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-table-text-muted">
              Store Code
            </th>
            <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-table-text-muted">
              Store Name
            </th>
            <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-table-text-muted">
              Account / Region
            </th>
            <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-table-text-muted">
              Budgeted
            </th>
            <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-table-text-muted">
              Active (B)
            </th>
            <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-table-text-muted">
              Active (AH)
            </th>
            <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-table-text-muted">
              Vacancies
            </th>
            <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-table-text-muted">
              SLA Status
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-table-rule">
          {rows.map((row) => {
            const risk = deriveStaffingRisk(row);
            return (
              <tr key={row.storeId} className="transition-colors hover:bg-table-row-hover">
                <td className="px-3 py-2.5">
                  <span className="font-mono text-xs text-table-text bg-mono-pill-surface border border-mono-pill-ring rounded px-1.5 py-0.5">
                    {row.storeCode ?? "—"}
                  </span>
                </td>

                <td className="px-3 py-2.5 font-medium text-table-text">
                  {row.storeName ?? "—"}
                </td>

                <td className="px-3 py-2.5 text-table-text-sub">
                  <div className="leading-tight">
                    <div>{row.accountName ?? "—"}</div>
                    {row.region && (
                      <div className="text-xs text-table-text-muted">{row.region}</div>
                    )}
                  </div>
                </td>

                <td className="px-3 py-2.5 text-table-text-sub">{row.budgetedTarget}</td>

                <td className="px-3 py-2.5 text-table-text-sub">{row.activeBudgetedCount}</td>

                <td className="px-3 py-2.5 text-table-text-sub">{row.activeAdditionalCount}</td>

                <td className="px-3 py-2.5 text-table-text-sub">
                  {risk.vacanciesCount > 0 ? (
                    <span
                      className={
                        risk.vacancySlaBreached ? "font-semibold text-status-danger-text" : ""
                      }
                    >
                      {risk.vacanciesCount}
                      {risk.vacancySlaBreached && (
                        <span className="ml-1 text-xs" title="Vacancy SLA breached (7 days+)">
                          ⚠
                        </span>
                      )}
                    </span>
                  ) : (
                    <span className="text-table-text-muted">0</span>
                  )}
                </td>

                <td className="px-3 py-2.5">
                  {row.staffingSlaStatus ? (
                    <StatusBadge
                      variant={staffingSlaVariant(row.staffingSlaStatus)}
                      text={row.staffingSlaStatus}
                    />
                  ) : (
                    <span className="text-xs text-table-text-muted">—</span>
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
