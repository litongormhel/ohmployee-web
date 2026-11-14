"use client";

import { useState, useMemo } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import {
  ArrowLeft,
  ArrowUpDown,
  Briefcase,
  Building2,
  ExternalLink,
  RefreshCw,
  Search,
  ShieldCheck,
  Store,
  Users,
} from "lucide-react";
import { useCencomGroupDetail } from "@/lib/queries/cencom";
import { DataState } from "@/components/shared/DataState";
import { PercentageBar } from "@/components/shared/PercentageBar";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { KpiCard } from "@/components/shared/KpiCard";

export type AccountSortField =
  | "account_name"
  | "active_stores"
  | "required"
  | "actual"
  | "vacant"
  | "mfr";

export default function CencomGroupDetailPage() {
  const params = useParams();
  const groupId = typeof params?.id === "string" ? params.id : "";

  const {
    data: group,
    isLoading,
    isError,
    error,
    refetch,
    isFetching,
  } = useCencomGroupDetail(groupId);

  const [searchQuery, setSearchQuery] = useState("");
  const [healthFilter, setHealthFilter] = useState("all");
  const [sortField, setSortField] = useState<AccountSortField>("mfr");
  const [sortDirection, setSortDirection] = useState<"asc" | "desc">("desc");

  const handleSort = (field: AccountSortField) => {
    if (sortField === field) {
      setSortDirection((prev) => (prev === "asc" ? "desc" : "asc"));
    } else {
      setSortField(field);
      setSortDirection(field === "account_name" ? "asc" : "desc");
    }
  };

  const groupAccounts = group?.accounts;

  const filteredAndSortedAccounts = useMemo(() => {
    if (!groupAccounts) return [];
    let result = [...groupAccounts];

    // 1. Search Filter
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase().trim();
      result = result.filter(
        (a) =>
          a.accountName.toLowerCase().includes(q) ||
          (a.accountCode && a.accountCode.toLowerCase().includes(q))
      );
    }

    // 2. Health Filter
    if (healthFilter !== "all") {
      result = result.filter((a) => a.healthStatus === healthFilter);
    }

    // 3. Sorting
    result.sort((a, b) => {
      let comparison = 0;
      switch (sortField) {
        case "account_name":
          comparison = a.accountName.localeCompare(b.accountName);
          break;
        case "active_stores":
          comparison = a.activeStores - b.activeStores;
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
        case "mfr":
          comparison = a.mfr - b.mfr;
          break;
        default:
          comparison = 0;
      }
      return sortDirection === "asc" ? comparison : -comparison;
    });

    return result;
  }, [groupAccounts, searchQuery, healthFilter, sortField, sortDirection]);

  if (isLoading) {
    return (
      <div className="space-y-6">
        <div className="flex items-center gap-3 text-sm text-text-muted">
          <Link
            href="/cencom?tab=groups"
            className="inline-flex items-center gap-1.5 text-text-secondary hover:text-text-primary transition-colors"
          >
            <ArrowLeft className="h-4 w-4" />
            <span>Back to CENCOM</span>
          </Link>
        </div>
        <div className="rounded-xl border border-border-default bg-surface-card p-12">
          <DataState
            kind="loading"
            title="Loading Group Accounts"
            description="Retrieving operational account quotas, slot authority, and store metrics..."
          />
        </div>
      </div>
    );
  }

  if (isError || !group) {
    return (
      <div className="space-y-6">
        <div className="flex items-center gap-3 text-sm text-text-muted">
          <Link
            href="/cencom?tab=groups"
            className="inline-flex items-center gap-1.5 text-text-secondary hover:text-text-primary transition-colors"
          >
            <ArrowLeft className="h-4 w-4" />
            <span>Back to CENCOM</span>
          </Link>
        </div>
        <div className="rounded-xl border border-border-default bg-surface-card p-12">
          <DataState
            kind="error"
            title="Failed to Load Group"
            description={
              error?.message ?? "Operational group allocation records could not be resolved."
            }
            onRetry={() => refetch()}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6 animate-in fade-in duration-150">
      {/* Top Navigation & Breadcrumbs */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="space-y-1">
          <div className="flex items-center gap-2 text-xs font-medium text-text-muted">
            <Link
              href="/cencom"
              className="hover:text-text-primary transition-colors"
            >
              CENCOM
            </Link>
            <span>/</span>
            <Link
              href="/cencom?tab=groups"
              className="hover:text-text-primary transition-colors"
            >
              Groups
            </Link>
            <span>/</span>
            <span className="text-text-secondary">{group.groupName}</span>
          </div>
          <div className="flex items-center gap-3">
            <Link
              href="/cencom?tab=groups"
              className="inline-flex h-9 w-9 items-center justify-center rounded-lg border border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover hover:text-text-primary transition-colors focus:outline-none focus:ring-2 focus:ring-brand-500/20"
              aria-label="Back to CENCOM Groups"
            >
              <ArrowLeft className="h-4 w-4" />
            </Link>
            <div>
              <div className="flex items-center gap-2.5">
                <h1 className="text-2xl font-bold tracking-tight text-text-primary">
                  {group.groupName}
                </h1>
                {group.groupCode && (
                  <span className="inline-flex items-center rounded-md border border-border-default bg-surface-muted px-2 py-0.5 text-xs font-mono font-semibold text-text-secondary">
                    {group.groupCode}
                  </span>
                )}
                <span className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-muted px-2 py-0.5 text-xs font-medium text-text-secondary">
                  <Building2 className="h-3 w-3 text-text-muted" />
                  {group.totalAccounts} {group.totalAccounts === 1 ? "Account" : "Accounts"}
                </span>
                {group.isNormalized && (
                  <span
                    title="Slot authority enforced (Actual >= Required -> Vacant = 0)"
                    className="inline-flex items-center gap-1 rounded-full bg-status-info-bg px-2.5 py-0.5 text-[11px] font-medium text-status-info-text border border-status-info-border"
                  >
                    <ShieldCheck className="h-3.5 w-3.5" />
                    Slot Authority Enforced
                  </span>
                )}
              </div>
              <p className="text-xs text-text-muted mt-0.5">
                Granular account-level headcount quota allocation, open vacancies, and manpower fulfillment rate
              </p>
            </div>
          </div>
        </div>

        {/* Action Toolbar */}
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => refetch()}
            disabled={isFetching}
            className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-2 text-xs font-medium text-text-secondary hover:bg-surface-hover hover:text-text-primary transition-colors disabled:opacity-50"
          >
            <RefreshCw className={`h-3.5 w-3.5 ${isFetching ? "animate-spin" : ""}`} />
            <span>Refresh</span>
          </button>
        </div>
      </div>

      {/* KPI Cards Summary */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        <KpiCard
          title="Required HC"
          value={group.required}
          subtitle="Slot-authority capacity"
          icon={Users}
        />
        <KpiCard
          title="Actual HC"
          value={group.actual}
          subtitle="Active deployed personnel"
          icon={Users}
        />
        <KpiCard
          title="Open Vacancies"
          value={group.vacant}
          subtitle="Slot-backed openings"
          icon={Briefcase}
        />
        <KpiCard
          title="Active Stores"
          value={group.activeStores}
          suffix={group.totalStores > 0 ? ` / ${group.totalStores}` : ""}
          subtitle="Stores currently staffed"
          icon={Store}
        />
        <KpiCard
          title="Group MFR"
          value={group.mfrPercent}
          decimals={1}
          suffix="%"
          subtitle={`${group.actual} of ${group.required} fulfilled`}
          footer={
            <div className="pt-2">
              <PercentageBar
                percent={group.mfrPercent}
                scale="mfr"
                heightClass="h-1.5"
                showLabel={false}
              />
            </div>
          }
        />
      </div>

      {/* Search & Filter Bar */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="relative flex-1 max-w-md">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search accounts or codes (e.g. Banko, Three)..."
            className="w-full rounded-lg border border-border-default bg-surface-base py-2 pl-9 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
        </div>

        <div className="flex items-center gap-2">
          <div className="flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-2.5 py-1.5 text-xs text-text-secondary">
            <span className="text-text-muted font-medium">Status:</span>
            <select
              value={healthFilter}
              onChange={(e) => setHealthFilter(e.target.value)}
              className="bg-transparent text-xs font-medium text-text-primary focus:outline-none cursor-pointer"
            >
              <option value="all">All Health Statuses</option>
              <option value="healthy">Healthy</option>
              <option value="at_risk">At Risk</option>
              <option value="critical">Critical</option>
            </select>
          </div>

          {(searchQuery || healthFilter !== "all") && (
            <button
              type="button"
              onClick={() => {
                setSearchQuery("");
                setHealthFilter("all");
              }}
              className="rounded-lg border border-border-default bg-surface-muted px-2.5 py-1.5 text-xs font-medium text-text-secondary hover:text-text-primary transition-colors"
            >
              Reset
            </button>
          )}
        </div>
      </div>

      {/* Accounts Breakdown Table */}
      <div className="overflow-hidden rounded-xl border border-border-default bg-surface-base shadow-xs">
        <div className="border-b border-border-default bg-surface-header px-4 py-3 sm:px-6">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <h2 className="text-sm font-semibold text-text-primary">
                Accounts under {group.groupName}
              </h2>
              <span className="rounded-full bg-surface-muted px-2 py-0.5 text-xs font-medium text-text-secondary">
                {filteredAndSortedAccounts.length}
              </span>
            </div>
            <span className="text-xs text-text-muted">
              Click Plantilla or Vacancy shortcuts to inspect records
            </span>
          </div>
        </div>

        {filteredAndSortedAccounts.length === 0 ? (
          <div className="p-8">
            <DataState
              kind="empty"
              title="No Accounts Found"
              description={
                searchQuery.trim() || healthFilter !== "all"
                  ? "No accounts match your current search or status filter."
                  : "No active accounts are mapped to this operational group."
              }
            />
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-sm" role="table">
              <thead>
                <tr className="border-b border-border-default bg-surface-muted/40 text-xs font-semibold text-text-secondary">
                  <th className="py-3 pl-4 pr-3 sm:pl-6" scope="col">
                    <button
                      type="button"
                      onClick={() => handleSort("account_name")}
                      className="inline-flex items-center gap-1.5 transition-colors hover:text-text-primary"
                    >
                      <span>Account Name</span>
                      <ArrowUpDown className="h-3 w-3" />
                    </button>
                  </th>
                  <th className="px-3 py-3 text-center" scope="col">
                    <button
                      type="button"
                      onClick={() => handleSort("active_stores")}
                      className="inline-flex items-center gap-1.5 transition-colors hover:text-text-primary"
                    >
                      <span>Active Stores</span>
                      <ArrowUpDown className="h-3 w-3" />
                    </button>
                  </th>
                  <th className="px-3 py-3 text-center" scope="col">
                    <button
                      type="button"
                      onClick={() => handleSort("required")}
                      className="inline-flex items-center gap-1.5 transition-colors hover:text-text-primary"
                    >
                      <span>Required HC</span>
                      <ArrowUpDown className="h-3 w-3" />
                    </button>
                  </th>
                  <th className="px-3 py-3 text-center" scope="col">
                    <button
                      type="button"
                      onClick={() => handleSort("actual")}
                      className="inline-flex items-center gap-1.5 transition-colors hover:text-text-primary"
                    >
                      <span>Actual HC</span>
                      <ArrowUpDown className="h-3 w-3" />
                    </button>
                  </th>
                  <th className="px-3 py-3 text-center" scope="col">
                    <button
                      type="button"
                      onClick={() => handleSort("vacant")}
                      className="inline-flex items-center gap-1.5 transition-colors hover:text-text-primary"
                    >
                      <span>Vacancies</span>
                      <ArrowUpDown className="h-3 w-3" />
                    </button>
                  </th>
                  <th className="px-3 py-3 min-w-[160px]" scope="col">
                    <button
                      type="button"
                      onClick={() => handleSort("mfr")}
                      className="inline-flex items-center gap-1.5 transition-colors hover:text-text-primary"
                    >
                      <span>MFR Fulfillment</span>
                      <ArrowUpDown className="h-3 w-3" />
                    </button>
                  </th>
                  <th className="px-3 py-3 text-center" scope="col">
                    Status
                  </th>
                  <th className="py-3 pl-3 pr-4 text-right sm:pr-6" scope="col">
                    Quick Actions
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border-default bg-surface-base">
                {filteredAndSortedAccounts.map((account) => {
                  const mfrRate = account.mfrPercent;
                  const isHealthy =
                    account.required > 0 &&
                    (account.healthStatus === "healthy" || mfrRate >= 100);
                  const isAtRisk =
                    account.required > 0 && account.healthStatus === "at_risk";
                  const isStandby = account.required === 0;

                  const statusVariant = isStandby
                    ? "neutral"
                    : isHealthy
                    ? "success"
                    : isAtRisk
                    ? "warning"
                    : "danger";
                  const statusLabel = isStandby
                    ? "Standby"
                    : isHealthy
                    ? "Healthy"
                    : isAtRisk
                    ? "At Risk"
                    : "Critical";

                  return (
                    <tr
                      key={account.accountId}
                      className="transition-colors hover:bg-surface-hover"
                    >
                      {/* Account Name */}
                      <td className="py-3.5 pl-4 pr-3 sm:pl-6">
                        <div className="flex items-center gap-2">
                          <Building2 className="h-4 w-4 text-text-muted shrink-0" />
                          <div>
                            <span className="font-semibold text-text-primary">
                              {account.accountName}
                            </span>
                            {account.accountCode && (
                              <span className="ml-2 inline-flex items-center rounded-md border border-border-default bg-surface-muted px-1.5 py-0.5 text-[10px] font-mono font-medium text-text-secondary">
                                {account.accountCode}
                              </span>
                            )}
                            {account.isNormalized && (
                              <span
                                title="Slot authority enforced (Actual >= Required -> Vacant = 0)"
                                className="ml-2 inline-flex items-center gap-1 rounded-full bg-status-info-bg px-2 py-0.2 text-[9px] font-medium text-status-info-text border border-status-info-border"
                              >
                                <ShieldCheck className="h-2.5 w-2.5" />
                                Slot Authority
                              </span>
                            )}
                          </div>
                        </div>
                      </td>

                      {/* Active Stores */}
                      <td className="px-3 py-3.5 text-center">
                        <span className="inline-flex items-center gap-1 font-medium text-text-primary">
                          <Store className="h-3.5 w-3.5 text-text-muted" />
                          {account.activeStores}
                          {account.totalStores > 0 &&
                            account.totalStores !== account.activeStores && (
                              <span className="text-xs text-text-muted">
                                /{account.totalStores}
                              </span>
                            )}
                        </span>
                      </td>

                      {/* Required HC */}
                      <td className="px-3 py-3.5 text-center font-mono font-semibold text-text-primary">
                        {account.required}
                      </td>

                      {/* Actual HC */}
                      <td className="px-3 py-3.5 text-center">
                        <span className="inline-flex items-center gap-1 font-mono font-semibold text-text-primary">
                          <Users className="h-3.5 w-3.5 text-text-muted" />
                          {account.actual}
                        </span>
                      </td>

                      {/* Vacancies */}
                      <td className="px-3 py-3.5 text-center">
                        {account.vacant === 0 ? (
                          <span className="inline-flex items-center rounded-full bg-surface-muted px-2 py-0.5 text-xs font-medium text-text-muted border border-border-default">
                            0 vacant
                          </span>
                        ) : (
                          <span className="inline-flex items-center rounded-full bg-surface-muted px-2.5 py-0.5 text-xs font-mono font-bold text-text-primary border border-border-default">
                            {account.vacant}
                          </span>
                        )}
                      </td>

                      {/* MFR Progress */}
                      <td className="px-3 py-3.5">
                        <div className="space-y-1">
                          <div className="flex items-center justify-between text-xs">
                            <span className="text-[11px] text-text-muted">
                              {account.actual} / {account.required}
                            </span>
                            {account.required === 0 && (
                              <span className="font-semibold text-text-muted tabular-nums">
                                —
                              </span>
                            )}
                          </div>
                          {account.required > 0 ? (
                            <PercentageBar
                              percent={mfrRate}
                              scale="mfr"
                              heightClass="h-2"
                              showLabel={true}
                            />
                          ) : (
                            <div
                              className="w-full h-2 rounded-full bg-surface-muted border border-border-subtle/50 overflow-hidden"
                              role="progressbar"
                              aria-valuenow={0}
                              aria-valuemin={0}
                              aria-valuemax={100}
                            />
                          )}
                        </div>
                      </td>

                      {/* Status */}
                      <td className="px-3 py-3.5 text-center">
                        <StatusBadge variant={statusVariant} text={statusLabel} />
                      </td>

                      {/* Actions */}
                      <td className="py-3.5 pl-3 pr-4 text-right sm:pr-6">
                        <div className="inline-flex items-center gap-1.5 justify-end">
                          <Link
                            href={`/plantilla?account=${encodeURIComponent(
                              account.accountName
                            )}`}
                            className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-base px-2 py-1 text-xs font-medium text-text-secondary hover:bg-surface-hover hover:text-text-primary transition-colors focus:outline-none focus:ring-1 focus:ring-brand-500"
                            title={`View ${account.accountName} Plantilla roster`}
                          >
                            <span>Plantilla</span>
                            <ExternalLink className="h-3 w-3 text-text-muted" />
                          </Link>
                          <Link
                            href={`/vacancy?account=${encodeURIComponent(
                              account.accountName
                            )}`}
                            className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-base px-2 py-1 text-xs font-medium text-text-secondary hover:bg-surface-hover hover:text-text-primary transition-colors focus:outline-none focus:ring-1 focus:ring-brand-500"
                            title={`View ${account.accountName} Vacancy pipeline`}
                          >
                            <span>Vacancy</span>
                            <ExternalLink className="h-3 w-3 text-text-muted" />
                          </Link>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
