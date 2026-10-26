"use client";

import { useState, useMemo } from "react";
import {
  ArrowUpDown,
  Building2,
  ChevronDown,
  ChevronRight,
  ShieldCheck,
  Store,
  Users,
} from "lucide-react";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DataState } from "@/components/shared/DataState";
import { PercentageBar } from "@/components/shared/PercentageBar";
import type { CencomGroupKpiItem } from "@/lib/queries/cencom";

export type CencomSortField =
  | "group_name"
  | "mfr"
  | "required"
  | "actual"
  | "vacant"
  | "active_stores";

export interface CencomGroupTableProps {
  groups: CencomGroupKpiItem[];
  isLoading?: boolean;
  isError?: boolean;
  error?: Error | null;
  onRetry?: () => void;
  searchQuery?: string;
  healthFilter?: string;
}

export function CencomGroupTable({
  groups,
  isLoading = false,
  isError = false,
  error,
  onRetry,
  searchQuery = "",
  healthFilter = "all",
}: CencomGroupTableProps) {
  const [sortField, setSortField] = useState<CencomSortField>("mfr");
  const [sortDirection, setSortDirection] = useState<"asc" | "desc">("desc");
  const [expandedGroups, setExpandedGroups] = useState<Set<string>>(new Set());

  const toggleGroupExpand = (groupId: string) => {
    setExpandedGroups((prev) => {
      const next = new Set(prev);
      if (next.has(groupId)) {
        next.delete(groupId);
      } else {
        next.add(groupId);
      }
      return next;
    });
  };

  const handleSort = (field: CencomSortField) => {
    if (sortField === field) {
      setSortDirection((prev) => (prev === "asc" ? "desc" : "asc"));
    } else {
      setSortField(field);
      setSortDirection(field === "group_name" ? "asc" : "desc");
    }
  };

  const filteredAndSortedGroups = useMemo(() => {
    let result = [...groups];

    // 1. Search Filter
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase().trim();
      result = result.filter(
        (g) =>
          g.groupName.toLowerCase().includes(q) ||
          (g.groupCode && g.groupCode.toLowerCase().includes(q)) ||
          g.accountNames.some((acc) => acc.toLowerCase().includes(q))
      );
    }

    // 2. Health Filter
    if (healthFilter && healthFilter !== "all") {
      result = result.filter((g) => g.healthStatus === healthFilter);
    }

    // 3. Sorting
    result.sort((a, b) => {
      let comparison = 0;
      switch (sortField) {
        case "group_name":
          comparison = a.groupName.localeCompare(b.groupName);
          break;
        case "mfr":
          comparison = a.mfr - b.mfr;
          break;
        case "required":
          comparison = a.required - b.required;
          break;
        case "actual":
          comparison = a.actual - b.actual;
          break;
        case "vacant":
          comparison = a.vacant - b.vacant;
          break;
        case "active_stores":
          comparison = a.activeStores - b.activeStores;
          break;
        default:
          comparison = 0;
      }
      return sortDirection === "asc" ? comparison : -comparison;
    });

    return result;
  }, [groups, searchQuery, healthFilter, sortField, sortDirection]);

  if (isLoading) {
    return (
      <div className="rounded-lg border border-border-default bg-surface-base p-8 shadow-xs">
        <DataState
          kind="loading"
          title="Loading Group Allocation KPIs"
          description="Fetching slot-authority metrics from v_cencom_group_allocation_kpi..."
        />
      </div>
    );
  }

  if (isError) {
    return (
      <div className="rounded-lg border border-border-default bg-surface-base p-8 shadow-xs">
        <DataState
          kind="error"
          title="Failed to Load Group Metrics"
          description={error?.message ?? "An error occurred while retrieving group allocation records."}
          onRetry={onRetry}
        />
      </div>
    );
  }

  if (filteredAndSortedGroups.length === 0) {
    return (
      <div className="rounded-lg border border-border-default bg-surface-base p-8 shadow-xs">
        <DataState
          kind="empty"
          title="No Group Allocation Data"
          description={
            searchQuery.trim()
              ? "No groups match your current search or filter criteria."
              : "No CENCOM scoped groups found for this workspace."
          }
        />
      </div>
    );
  }

  return (
    <div className="overflow-hidden rounded-lg border border-border-default bg-surface-base shadow-xs">
      <div className="overflow-x-auto">
        <table className="w-full border-collapse text-left text-sm" role="table">
          <thead>
            <tr className="border-b border-border-default bg-surface-header text-sm font-semibold text-text-secondary">
              <th className="py-3 pl-4 pr-3 sm:pl-6" scope="col">
                <button
                  type="button"
                  onClick={() => handleSort("group_name")}
                  className="inline-flex items-center gap-1.5 transition-colors hover:text-text-primary"
                >
                  <span>Group / Accounts</span>
                  <ArrowUpDown className="h-3.5 w-3.5" />
                </button>
              </th>
              <th className="px-3 py-3 text-center" scope="col">
                <button
                  type="button"
                  onClick={() => handleSort("active_stores")}
                  className="inline-flex items-center gap-1.5 transition-colors hover:text-text-primary"
                >
                  <span>Active Stores</span>
                  <ArrowUpDown className="h-3.5 w-3.5" />
                </button>
              </th>
              <th className="px-3 py-3 text-center" scope="col">
                <button
                  type="button"
                  onClick={() => handleSort("required")}
                  className="inline-flex items-center gap-1.5 transition-colors hover:text-text-primary"
                >
                  <span>Required HC</span>
                  <ArrowUpDown className="h-3.5 w-3.5" />
                </button>
              </th>
              <th className="px-3 py-3 text-center" scope="col">
                <button
                  type="button"
                  onClick={() => handleSort("actual")}
                  className="inline-flex items-center gap-1.5 transition-colors hover:text-text-primary"
                >
                  <span>Actual HC</span>
                  <ArrowUpDown className="h-3.5 w-3.5" />
                </button>
              </th>
              <th className="px-3 py-3 text-center" scope="col">
                <button
                  type="button"
                  onClick={() => handleSort("vacant")}
                  className="inline-flex items-center gap-1.5 transition-colors hover:text-text-primary"
                >
                  <span>Vacancies</span>
                  <ArrowUpDown className="h-3.5 w-3.5" />
                </button>
              </th>
              <th className="px-3 py-3 min-w-[180px]" scope="col">
                <button
                  type="button"
                  onClick={() => handleSort("mfr")}
                  className="inline-flex items-center gap-1.5 transition-colors hover:text-text-primary"
                >
                  <span>MFR Fulfillment</span>
                  <ArrowUpDown className="h-3.5 w-3.5" />
                </button>
              </th>
              <th className="py-3 pl-3 pr-4 text-center sm:pr-6" scope="col">
                Status
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border-default bg-surface-base">
            {filteredAndSortedGroups.map((group) => {
              const isExpanded = expandedGroups.has(group.groupId);
              const mfrRate = group.mfrPercent;
              const isHealthy = group.required > 0 && (group.healthStatus === "healthy" || mfrRate >= 100);
              const isAtRisk = group.required > 0 && group.healthStatus === "at_risk";
              const isStandby = group.required === 0;

              const statusVariant = isStandby ? "neutral" : isHealthy ? "success" : isAtRisk ? "warning" : "danger";
              const statusLabel = isStandby ? "Standby" : isHealthy ? "Healthy" : isAtRisk ? "At Risk" : "Critical";

              return (
                <tr
                  key={group.groupId || group.groupName}
                  className="transition-colors hover:bg-surface-hover"
                >
                  {/* Group & Accounts */}
                  <td className="py-4 pl-4 pr-3 sm:pl-6">
                    <div className="flex items-start gap-2.5">
                      <button
                        type="button"
                        onClick={() => toggleGroupExpand(group.groupId)}
                        className="mt-0.5 inline-flex h-5 w-5 items-center justify-center rounded-sm text-text-muted hover:bg-surface-muted hover:text-text-primary"
                        aria-label={isExpanded ? "Collapse account list" : "Expand account list"}
                      >
                        {isExpanded ? (
                          <ChevronDown className="h-4 w-4" />
                        ) : (
                          <ChevronRight className="h-4 w-4" />
                        )}
                      </button>
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="font-semibold text-text-primary">
                            {group.groupName}
                          </span>
                          {group.groupCode && (
                            <span className="inline-flex items-center rounded-md border border-border-default bg-surface-muted px-1.5 py-0.5 text-xs font-mono font-medium text-text-secondary">
                              {group.groupCode}
                            </span>
                          )}
                          {group.isNormalized && (
                            <span
                              title="Slot authority enforced (Actual >= Required -> Vacant = 0)"
                              className="inline-flex items-center gap-1 rounded-full bg-status-info-bg px-2 py-0.5 text-[10px] font-medium text-status-info-text border border-status-info-border"
                            >
                              <ShieldCheck className="h-3 w-3" />
                              Slot Authority
                            </span>
                          )}
                        </div>

                        {/* Account Preview / List */}
                        {group.accountNames.length > 0 && (
                          <div className="mt-1 flex flex-wrap gap-1.5">
                            {isExpanded ? (
                              group.accountNames.map((acc) => (
                                <span
                                  key={acc}
                                  className="inline-flex items-center gap-1 rounded-md bg-surface-muted px-2 py-0.5 text-xs font-medium text-text-secondary border border-border-default"
                                >
                                  <Building2 className="h-3 w-3 text-text-muted" />
                                  {acc}
                                </span>
                              ))
                            ) : (
                              <span className="text-xs text-text-muted">
                                {group.accountNames.slice(0, 3).join(", ")}
                                {group.accountNames.length > 3 && (
                                  <span className="font-medium text-brand-600">
                                    {" "}
                                    +{group.accountNames.length - 3} more
                                  </span>
                                )}
                              </span>
                            )}
                          </div>
                        )}
                      </div>
                    </div>
                  </td>

                  {/* Active Stores */}
                  <td className="px-3 py-4 text-center">
                    <span className="inline-flex items-center gap-1 font-medium text-text-primary">
                      <Store className="h-3.5 w-3.5 text-text-muted" />
                      {group.activeStores}
                      {group.totalStores > 0 && group.totalStores !== group.activeStores && (
                        <span className="text-xs text-text-muted">/{group.totalStores}</span>
                      )}
                    </span>
                  </td>

                  {/* Required HC */}
                  <td className="px-3 py-4 text-center font-mono font-semibold text-text-primary">
                    {group.required}
                  </td>

                  {/* Actual HC */}
                  <td className="px-3 py-4 text-center">
                    <span className="inline-flex items-center gap-1 font-mono font-semibold text-text-primary">
                      <Users className="h-3.5 w-3.5 text-text-muted" />
                      {group.actual}
                    </span>
                  </td>

                  {/* Vacancies */}
                  <td className="px-3 py-4 text-center">
                    {group.vacant === 0 ? (
                      <span className="inline-flex items-center rounded-full bg-surface-muted px-2 py-0.5 text-xs font-medium text-text-muted border border-border-default">
                        0 vacant
                      </span>
                    ) : (
                      <span className="inline-flex items-center rounded-full bg-surface-muted px-2.5 py-0.5 text-xs font-mono font-bold text-text-primary border border-border-default">
                        {group.vacant}
                      </span>
                    )}
                  </td>

                  {/* MFR Progress Bar */}
                  <td className="px-3 py-4">
                    <div className="space-y-1">
                      <div className="flex items-center justify-between text-xs">
                        <span className="text-[11px] text-text-muted">
                          {group.actual} / {group.required}
                        </span>
                        {group.required === 0 && (
                          <span className="font-semibold text-text-muted tabular-nums">—</span>
                        )}
                      </div>
                      {group.required > 0 ? (
                        <PercentageBar
                          percent={mfrRate}
                          scale="mfr"
                          heightClass="h-2"
                          showLabel={true}
                        />
                      ) : (
                        <div
                          className="w-full h-2 rounded-full bg-surface-muted overflow-hidden"
                          role="progressbar"
                          aria-valuenow={0}
                          aria-valuemin={0}
                          aria-valuemax={100}
                        />
                      )}
                    </div>
                  </td>

                  {/* Operational Health Status */}
                  <td className="py-4 pl-3 pr-4 text-center sm:pr-6">
                    <StatusBadge variant={statusVariant} text={statusLabel} />
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
