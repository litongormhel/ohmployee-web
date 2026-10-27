"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Building2, Search, Sliders, X } from "lucide-react";
import { DetailDrawer } from "@/components/shared/DetailDrawer";
import { Badge } from "@/components/ui/badge";
import { StatusBadge, type BadgeVariant } from "@/components/ui/StatusBadge";
import { DataState } from "@/components/shared/DataState";
import {
  listWebPlantillaStoreStaffing,
  deriveStaffingRisk,
  type PlantillaStoreStaffingRow,
} from "@/lib/queries/plantilla";

export interface StoreStaffingOverviewDrawerProps {
  isOpen: boolean;
  onClose: () => void;
  accountId: string;
  accountName?: string | null;
  onSelectStore: (store: PlantillaStoreStaffingRow) => void;
  canReviseQuota: boolean;
  canRequestAdjustment: boolean;
  summaryRequiredQuota?: number;
}

function formatFillRate(fillRate: number | null): string {
  if (fillRate === null) return "—";
  return `${(fillRate * 100).toFixed(1)}%`;
}

function staffingStatusVariant(status: string | null | undefined): BadgeVariant {
  switch ((status ?? "").toLowerCase()) {
    case "fully-staffed":
    case "optimal":
    case "low":
      return "success";
    case "under-staffed":
    case "critical":
    case "high":
      return "danger";
    case "over-staffed":
    case "medium":
      return "warning";
    default:
      return "neutral";
  }
}

export function StoreStaffingOverviewDrawer({
  isOpen,
  onClose,
  accountId,
  accountName,
  onSelectStore,
  summaryRequiredQuota,
}: StoreStaffingOverviewDrawerProps) {
  const [search, setSearch] = useState("");

  const storesQuery = useQuery({
    queryKey: ["plantilla", "store-staffing-overview", accountId],
    queryFn: () =>
      listWebPlantillaStoreStaffing({
        accountId,
        page: 1,
        pageSize: 100,
      }),
    enabled: isOpen && !!accountId,
    staleTime: 15000,
  });

  const storeRows = storesQuery.data?.data ?? [];

  const filteredStores = storeRows.filter((s) => {
    if (!search.trim()) return true;
    const q = search.toLowerCase();
    return (
      (s.storeName?.toLowerCase() ?? "").includes(q) ||
      (s.storeCode?.toLowerCase() ?? "").includes(q) ||
      (s.region?.toLowerCase() ?? "").includes(q)
    );
  });

  return (
    <DetailDrawer
      isOpen={isOpen}
      onClose={onClose}
      widthClass="w-[var(--drawer-width-xl)] max-w-full"
      badge={
        <Badge className="font-mono text-xs font-semibold bg-brand-600 text-white border-none py-1 px-2.5">
          {summaryRequiredQuota !== undefined ? `${summaryRequiredQuota} Quota` : "Store Staffing"}
        </Badge>
      }
      title={accountName ? `${accountName} — Store Staffing` : "Store Staffing Overview"}
      subtitle={
        <div className="flex items-center gap-1.5 text-xs text-text-muted">
          <Building2 className="h-3.5 w-3.5 shrink-0" />
          <span>Manage store-level quotas, discrete workforce slots, and staffing gaps.</span>
        </div>
      }
    >
      <div className="space-y-5">
        {/* Search Bar inside Drawer */}
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search stores by name, code, or region..."
            className="h-10 w-full rounded-lg border border-border-default bg-surface-muted pl-9 pr-9 text-sm text-text-primary outline-none transition-colors focus:border-brand-500 focus:bg-surface-base"
          />
          {search && (
            <button
              type="button"
              onClick={() => setSearch("")}
              className="absolute right-2.5 top-1/2 -translate-y-1/2 rounded p-1 text-text-muted hover:text-text-primary transition-colors"
              aria-label="Clear store search"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          )}
        </div>

        {/* Content */}
        {storesQuery.isLoading ? (
          <DataState
            kind="loading"
            title="Loading Store Staffing"
            description="Fetching store allocation quotas and actual counts..."
          />
        ) : storesQuery.isError ? (
          <DataState
            kind="error"
            title="Failed to Load Store Staffing"
            description={storesQuery.error instanceof Error ? storesQuery.error.message : "Error fetching stores"}
            onRetry={() => storesQuery.refetch()}
          />
        ) : filteredStores.length === 0 ? (
          <DataState
            kind="empty"
            title="No Stores Found"
            description={
              search ? "No store staffing records match your search." : "No stores registered under this account."
            }
          />
        ) : (
          <div className="space-y-3">
            {filteredStores.map((row) => {
              const risk = deriveStaffingRisk(row);
              return (
                <div
                  key={row.storeId}
                  className="rounded-xl border border-border-default bg-surface-base p-4 shadow-xs transition-all hover:border-border-subtle hover:shadow-sm"
                >
                  <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        {row.storeCode && (
                          <span className="font-mono text-xs font-semibold text-text-primary bg-mono-pill-surface border border-mono-pill-ring rounded px-1.5 py-0.5">
                            {row.storeCode}
                          </span>
                        )}
                        <h4 className="text-sm font-bold text-text-primary truncate">
                          {row.storeName ?? "Unnamed Store"}
                        </h4>
                      </div>
                      {row.region && (
                        <p className="mt-0.5 text-xs text-text-muted">{row.region}</p>
                      )}
                    </div>

                    <div className="flex items-center gap-2 shrink-0">
                      {risk.staffingRisk && (
                        <StatusBadge
                          variant={staffingStatusVariant(risk.staffingRisk)}
                          text={risk.staffingRisk}
                        />
                      )}
                      <button
                        type="button"
                        onClick={() => {
                          onSelectStore(row);
                        }}
                        className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-brand-600 hover:border-brand-300 transition-colors shadow-xs"
                      >
                        <Sliders className="h-3.5 w-3.5" />
                        <span>Manage Quota</span>
                      </button>
                    </div>
                  </div>

                  {/* Staffing Breakdown Numbers */}
                  <div className="mt-3.5 grid grid-cols-2 sm:grid-cols-4 gap-2 text-center border-t border-border-subtle pt-3">
                    <div className="rounded border border-border-subtle bg-surface-muted/50 p-2">
                      <div className="text-[10px] font-semibold text-text-muted">Actual</div>
                      <div className="text-sm font-bold font-mono text-text-primary">{row.onboardCount}</div>
                    </div>
                    <div className="rounded border border-border-subtle bg-surface-muted/50 p-2">
                      <div className="text-[10px] font-semibold text-text-muted">Pipeline</div>
                      <div className="text-sm font-bold font-mono text-text-primary">{row.hrPipelineCount}</div>
                    </div>
                    <div className="rounded border border-border-subtle bg-surface-muted/50 p-2">
                      <div className="text-[10px] font-semibold text-text-muted">Open Vacant</div>
                      <div className="text-sm font-bold font-mono text-text-primary">{row.openHeadcount}</div>
                    </div>
                    <div className="rounded border border-border-subtle bg-surface-muted/50 p-2">
                      <div className="text-[10px] font-semibold text-text-muted">Required</div>
                      <div className="text-sm font-bold font-mono text-text-primary">{row.requiredHeadcount}</div>
                    </div>
                  </div>

                  {/* Fill Rate Progress Bar */}
                  <div className="mt-3 flex items-center gap-2.5">
                    <span className="text-[10px] font-semibold text-text-muted shrink-0">
                      MFR
                    </span>
                    <div className="relative flex-1 h-1.5 rounded-full bg-surface-muted border border-border-subtle/50 overflow-hidden">
                      <div
                        className={`absolute left-0 top-0 h-full rounded-full transition-all ${
                          (row.fillRate ?? 0) >= 1
                            ? "bg-pct-good-bar"
                            : (row.fillRate ?? 0) >= 0.95
                            ? "bg-pct-warn-bar"
                            : "bg-pct-bad-bar"
                        }`}
                        style={{ width: `${Math.min(100, Math.round((row.fillRate ?? 0) * 100))}%` }}
                      />
                    </div>
                    <span className="text-xs font-mono font-semibold text-text-secondary shrink-0">
                      {formatFillRate(row.fillRate)}
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </DetailDrawer>
  );
}
