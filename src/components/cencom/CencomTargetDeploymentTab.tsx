"use client";

import { useState, useMemo } from "react";
import {
  Calendar,
  ChevronDown,
  ChevronRight,
  Clock,
  Info,
  MapPin,
  RefreshCw,
  Search,
  ShieldAlert,
  Store,
  UserCheck,
} from "lucide-react";
import { useCencomTargetDeployment } from "@/lib/queries/cencom";
import { MetricCard } from "@/components/shared/MetricCard";

interface CencomTargetDeploymentTabProps {
  onRefresh?: () => void;
  isRefreshing?: boolean;
}

export function CencomTargetDeploymentTab({
  onRefresh,
  isRefreshing = false,
}: CencomTargetDeploymentTabProps) {
  const {
    data,
    isLoading,
    isError,
    error,
    refetch,
    isRefetching,
  } = useCencomTargetDeployment();

  const [searchQuery, setSearchQuery] = useState("");
  const [agingFilter, setAgingFilter] = useState<string>("all");
  const [selectedProvince, setSelectedProvince] = useState<string | null>(null);
  const [expandedOutlets, setExpandedOutlets] = useState<Set<string>>(new Set());

  const handleRefresh = async () => {
    if (onRefresh) onRefresh();
    await refetch();
  };

  const toggleOutletExpand = (outletKey: string) => {
    setExpandedOutlets((prev) => {
      const next = new Set(prev);
      if (next.has(outletKey)) next.delete(outletKey);
      else next.add(outletKey);
      return next;
    });
  };

  const provinces = useMemo(() => data?.provinces ?? [], [data?.provinces]);
  const groupedOutlets = useMemo(() => data?.groupedOutlets ?? [], [data?.groupedOutlets]);

  // Filtered provinces
  const filteredProvinces = useMemo(() => {
    let list = [...provinces];

    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase().trim();
      list = list.filter(
        (p) =>
          p.province.toLowerCase().includes(q) ||
          p.vacancies.some(
            (v) =>
              v.storeName.toLowerCase().includes(q) ||
              v.areaName.toLowerCase().includes(q) ||
              v.position.toLowerCase().includes(q) ||
              v.account.toLowerCase().includes(q) ||
              v.vcode.toLowerCase().includes(q)
          )
      );
    }

    if (agingFilter !== "all") {
      list = list.filter((p) => {
        if (agingFilter === "1_15") return p.bucket1_15 > 0;
        if (agingFilter === "16_30") return p.bucket16_30 > 0;
        if (agingFilter === "31_60") return p.bucket31_60 > 0;
        if (agingFilter === "61_120") return p.bucket61_120 > 0;
        if (agingFilter === "gt121") return p.bucketGt121 > 0;
        if (agingFilter === "advance") return p.advanceCount > 0;
        if (agingFilter === "critical") return p.bucket31_60 + p.bucket61_120 + p.bucketGt121 > 0;
        return true;
      });
    }

    return list;
  }, [provinces, searchQuery, agingFilter]);

  // Outlets for active selected province or all
  const filteredOutlets = useMemo(() => {
    let outlets = groupedOutlets;

    if (selectedProvince) {
      outlets = outlets.filter(
        (o) => o.province.toLowerCase() === selectedProvince.toLowerCase()
      );
    }

    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase().trim();
      outlets = outlets.filter(
        (o) =>
          o.store.toLowerCase().includes(q) ||
          o.area.toLowerCase().includes(q) ||
          o.hrco.toLowerCase().includes(q) ||
          o.vacancies.some(
            (v) =>
              v.position.toLowerCase().includes(q) ||
              v.account.toLowerCase().includes(q) ||
              v.vcode.toLowerCase().includes(q)
          )
      );
    }

    if (agingFilter !== "all") {
      outlets = outlets.filter((o) => {
        if (agingFilter === "advance") return o.vacancies.every((v) => v.bucket === "advance");
        if (agingFilter === "1_15") return o.vacancies.some((v) => v.bucket === "1_15");
        if (agingFilter === "16_30") return o.vacancies.some((v) => v.bucket === "16_30");
        if (agingFilter === "31_60") return o.vacancies.some((v) => v.bucket === "31_60");
        if (agingFilter === "61_120") return o.vacancies.some((v) => v.bucket === "61_120");
        if (agingFilter === "gt121") return o.vacancies.some((v) => v.bucket === "gt121");
        if (agingFilter === "critical") return o.oldestAging >= 31;
        return true;
      });
    }

    return outlets;
  }, [groupedOutlets, selectedProvince, searchQuery, agingFilter]);

  if (isError) {
    return (
      <div className="rounded-xl border border-border-default bg-surface-card p-6 text-text-primary shadow-xs">
        <div className="flex items-center gap-3">
          <ShieldAlert className="h-6 w-6 text-text-secondary" />
          <div>
            <h3 className="font-semibold text-text-primary">
              Unable to load Target Deployment data
            </h3>
            <p className="text-xs text-text-muted mt-0.5">
              {error?.message || "An error occurred while fetching vacancy aging records."}
            </p>
          </div>
        </div>
        <button
          onClick={handleRefresh}
          className="mt-4 inline-flex items-center gap-1.5 rounded-md border border-border-default bg-surface-card px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs transition hover:bg-surface-hover cursor-pointer"
        >
          <RefreshCw className="h-3.5 w-3.5" />
          Retry
        </button>
      </div>
    );
  }

  const denom = (data?.operationalTotal ?? 0) > 0 ? data!.operationalTotal : 1;

  return (
    <div className="space-y-6 animate-in fade-in duration-150">
      {/* 1. Header & Quick Controls */}
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
        <div>
          <h2 className="text-lg font-bold text-text-primary flex items-center gap-2">
            <MapPin className="h-5 w-5 text-brand-600" />
            Target Deployment & Vacancy Aging by Area & Province
          </h2>
          <p className="text-xs text-text-secondary mt-0.5">
            Geographic vacancy distribution, aging brackets, store drilldowns, and reliever coverage status.
          </p>
        </div>
        <button
          onClick={handleRefresh}
          disabled={isLoading || isRefetching || isRefreshing}
          className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-primary shadow-xs transition hover:bg-surface-hover disabled:opacity-50 cursor-pointer self-start sm:self-auto"
        >
          <RefreshCw
            className={`h-3.5 w-3.5 ${
              isLoading || isRefetching || isRefreshing ? "animate-spin" : ""
            }`}
          />
          {isLoading || isRefetching || isRefreshing ? "Refreshing..." : "Refresh Aging"}
        </button>
      </div>

      {/* 2. Top-Level Aging KPIs */}
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-2 lg:grid-cols-5">
        <MetricCard
          label="Operational Vacancies"
          value={data?.operationalTotal ?? 0}
          badge="Active Aging"
          helperText="Excludes advance requisitions"
          isLoading={isLoading}
        />
        <MetricCard
          label="Advance Vacancies"
          value={data?.advanceCount ?? 0}
          badge="Future Need"
          helperText="Not yet in aging calculation"
          isLoading={isLoading}
        />
        <MetricCard
          label="Average Aging Days"
          value={data ? `${data.avgAgingDays}d` : "--"}
          badge="Network Avg"
          helperText="Requisition duration open"
          isLoading={isLoading}
        />
        <MetricCard
          label="Critical Aging (>30d)"
          value={data ? `${data.pctCriticalAging}%` : "--"}
          badge={
            (data?.pctCriticalAging ?? 0) > 40
              ? "Critical"
              : (data?.pctCriticalAging ?? 0) > 20
              ? "Watch"
              : "Healthy"
          }
          helperText="Vacancies open over 30 days"
          isLoading={isLoading}
        />
        <MetricCard
          label="Max Days Open"
          value={data ? `${data.maxAgingDays}d` : "--"}
          badge="Oldest Unfilled"
          helperText="Across all active stores"
          isLoading={isLoading}
        />
      </div>

      {/* 3. Aging Bucket Breakdown Panel (Mobile 1:1 Parity) */}
      <div className="rounded-xl border border-border-default bg-surface-base p-5 shadow-xs">
        <div className="flex items-center justify-between border-b border-border-subtle pb-3">
          <div className="flex items-center gap-2">
            <Clock className="h-4 w-4 text-brand-600" />
            <h3 className="text-xs font-bold uppercase tracking-wider text-text-secondary">
              VACANCY AGING SUMMARY BRACKETS
            </h3>
          </div>
          <span className="text-xs font-semibold text-text-secondary">
            Operational Total:{" "}
            <span className="font-bold font-mono text-text-primary">
              {data?.operationalTotal ?? 0}
            </span>
          </span>
        </div>

        {/* Bucket Rows */}
        <div className="mt-4 grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
          {/* 1-15 Days */}
          <div
            onClick={() => setAgingFilter(agingFilter === "1_15" ? "all" : "1_15")}
            className={`cursor-pointer rounded-xl border p-3 transition shadow-2xs ${
              agingFilter === "1_15"
                ? "border-brand-500 bg-surface-card ring-2 ring-brand-500"
                : "border-border-default bg-surface-card hover:border-border-strong hover:bg-surface-hover"
            }`}
          >
            <div className="flex items-center justify-between">
              <span className="text-[11px] font-bold text-text-secondary">1–15 DAYS</span>
              <span className="h-2 w-2 rounded-full bg-border-strong" />
            </div>
            <div className="mt-2 text-2xl font-bold font-mono text-text-primary">
              {data?.bucket1_15 ?? 0}
            </div>
            <div className="text-[10px] text-text-muted">
              {Math.round(((data?.bucket1_15 ?? 0) / denom) * 100)}% of operational
            </div>
          </div>

          {/* 16-30 Days */}
          <div
            onClick={() => setAgingFilter(agingFilter === "16_30" ? "all" : "16_30")}
            className={`cursor-pointer rounded-xl border p-3 transition shadow-2xs ${
              agingFilter === "16_30"
                ? "border-brand-500 bg-surface-card ring-2 ring-brand-500"
                : "border-border-default bg-surface-card hover:border-border-strong hover:bg-surface-hover"
            }`}
          >
            <div className="flex items-center justify-between">
              <span className="text-[11px] font-bold text-text-secondary">16–30 DAYS</span>
              <span className="h-2 w-2 rounded-full bg-border-strong" />
            </div>
            <div className="mt-2 text-2xl font-bold font-mono text-text-primary">
              {data?.bucket16_30 ?? 0}
            </div>
            <div className="text-[10px] text-text-muted">
              {Math.round(((data?.bucket16_30 ?? 0) / denom) * 100)}% of operational
            </div>
          </div>

          {/* 31-60 Days */}
          <div
            onClick={() => setAgingFilter(agingFilter === "31_60" ? "all" : "31_60")}
            className={`cursor-pointer rounded-xl border p-3 transition shadow-2xs ${
              agingFilter === "31_60"
                ? "border-brand-500 bg-surface-card ring-2 ring-brand-500"
                : "border-border-default bg-surface-card hover:border-border-strong hover:bg-surface-hover"
            }`}
          >
            <div className="flex items-center justify-between">
              <span className="text-[11px] font-bold text-text-secondary">31–60 DAYS</span>
              <span className="h-2 w-2 rounded-full bg-border-strong" />
            </div>
            <div className="mt-2 text-2xl font-bold font-mono text-text-primary">
              {data?.bucket31_60 ?? 0}
            </div>
            <div className="text-[10px] text-text-muted">
              {Math.round(((data?.bucket31_60 ?? 0) / denom) * 100)}% of operational
            </div>
          </div>

          {/* 61-120 Days */}
          <div
            onClick={() => setAgingFilter(agingFilter === "61_120" ? "all" : "61_120")}
            className={`cursor-pointer rounded-xl border p-3 transition shadow-2xs ${
              agingFilter === "61_120"
                ? "border-brand-500 bg-surface-card ring-2 ring-brand-500"
                : "border-border-default bg-surface-card hover:border-border-strong hover:bg-surface-hover"
            }`}
          >
            <div className="flex items-center justify-between">
              <span className="text-[11px] font-bold text-text-secondary">61–120 DAYS</span>
              <span className="h-2 w-2 rounded-full bg-border-strong" />
            </div>
            <div className="mt-2 text-2xl font-bold font-mono text-text-primary">
              {data?.bucket61_120 ?? 0}
            </div>
            <div className="text-[10px] text-text-muted">
              {Math.round(((data?.bucket61_120 ?? 0) / denom) * 100)}% of operational
            </div>
          </div>

          {/* >121 Days */}
          <div
            onClick={() => setAgingFilter(agingFilter === "gt121" ? "all" : "gt121")}
            className={`cursor-pointer rounded-xl border p-3 transition shadow-2xs ${
              agingFilter === "gt121"
                ? "border-brand-500 bg-surface-card ring-2 ring-brand-500"
                : "border-border-default bg-surface-card hover:border-border-strong hover:bg-surface-hover"
            }`}
          >
            <div className="flex items-center justify-between">
              <span className="text-[11px] font-bold text-text-secondary">&gt;121 DAYS</span>
              <span className="h-2 w-2 rounded-full bg-border-strong" />
            </div>
            <div className="mt-2 text-2xl font-bold font-mono text-text-primary">
              {data?.bucketGt121 ?? 0}
            </div>
            <div className="text-[10px] text-text-muted">
              {Math.round(((data?.bucketGt121 ?? 0) / denom) * 100)}% of operational
            </div>
          </div>

          {/* Advance Vacancy */}
          <div
            onClick={() => setAgingFilter(agingFilter === "advance" ? "all" : "advance")}
            className={`cursor-pointer rounded-xl border p-3 transition shadow-2xs ${
              agingFilter === "advance"
                ? "border-brand-500 bg-surface-card ring-2 ring-brand-500"
                : "border-border-default bg-surface-card hover:border-border-strong hover:bg-surface-hover"
            }`}
          >
            <div className="flex items-center justify-between">
              <span className="text-[11px] font-bold text-text-secondary">ADVANCE VACANCY</span>
              <span className="h-2 w-2 rounded-full bg-brand-500" />
            </div>
            <div className="mt-2 text-2xl font-bold font-mono text-text-primary">
              {data?.advanceCount ?? 0}
            </div>
            <div className="text-[10px] text-text-muted">Future start date</div>
          </div>
        </div>

        {/* Advance Notice Helper */}
        <div className="mt-4 flex items-center gap-2 rounded-lg bg-surface-muted p-3 text-xs text-text-secondary border border-border-default">
          <Info className="h-4 w-4 shrink-0 text-brand-500" />
          <span>
            <strong>Advance Vacancy note:</strong> Positions requested for future need are tracked separately and not factored into the operational aging computation until their effective vacant date.
          </span>
        </div>
      </div>

      {/* 4. Filter & Search Toolbar */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="relative flex-1 max-w-md">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted" />
          <input
            type="text"
            placeholder="Search province, area, store, or position..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full rounded-lg border border-border-default bg-surface-base pl-9 pr-3 py-2 text-xs text-text-primary placeholder:text-text-muted outline-none transition focus:border-brand-500"
          />
        </div>

        <div className="flex items-center gap-2 flex-wrap">
          <select
            value={agingFilter}
            onChange={(e) => setAgingFilter(e.target.value)}
            className="h-9 rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary outline-none transition focus:border-brand-500"
          >
            <option value="all">All Aging Brackets</option>
            <option value="1_15">1–15 Days</option>
            <option value="16_30">16–30 Days</option>
            <option value="31_60">31–60 Days</option>
            <option value="61_120">61–120 Days</option>
            <option value="gt121">&gt;121 Days</option>
            <option value="critical">Critical (&gt;30d)</option>
            <option value="advance">Advance Vacancy Only</option>
          </select>

          {selectedProvince && (
            <button
              onClick={() => setSelectedProvince(null)}
              className="inline-flex items-center gap-1.5 rounded-lg bg-brand-50 px-3 py-1.5 text-xs font-semibold text-brand-700 border border-brand-200 transition hover:bg-brand-100 cursor-pointer"
            >
              <span>Province: {selectedProvince}</span>
              <span className="text-brand-400 hover:text-brand-900">&times;</span>
            </button>
          )}

          {(searchQuery || agingFilter !== "all" || selectedProvince) && (
            <button
              onClick={() => {
                setSearchQuery("");
                setAgingFilter("all");
                setSelectedProvince(null);
              }}
              className="text-xs font-semibold text-text-secondary hover:text-text-primary cursor-pointer px-2"
            >
              Reset Filters
            </button>
          )}
        </div>
      </div>

      {/* 5. Province Vacancy Aging Summary Table */}
      <div className="rounded-xl border border-border-default bg-surface-base overflow-hidden shadow-xs">
        <div className="border-b border-border-default bg-surface-muted px-4 py-3">
          <h3 className="text-xs font-bold uppercase tracking-wider text-text-secondary">
            VACANCY AGING BY PROVINCE & AREA
          </h3>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs">
            <thead className="border-b border-border-default bg-surface-muted/50 text-[10px] font-bold uppercase tracking-wider text-text-secondary">
              <tr>
                <th className="py-2.5 px-4">Province / Area</th>
                <th className="py-2.5 px-3 text-right">Total Open</th>
                <th className="py-2.5 px-2 text-center text-text-secondary">1–15d</th>
                <th className="py-2.5 px-2 text-center text-text-secondary">16–30d</th>
                <th className="py-2.5 px-2 text-center text-text-secondary">31–60d</th>
                <th className="py-2.5 px-2 text-center text-text-secondary">61–120d</th>
                <th className="py-2.5 px-2 text-center text-text-secondary">&gt;121d</th>
                <th className="py-2.5 px-3 text-center text-text-secondary">Advance</th>
                <th className="py-2.5 px-3 text-center">Stores</th>
                <th className="py-2.5 px-4 text-right">Drilldown</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle">
              {filteredProvinces.length === 0 ? (
                <tr>
                  <td colSpan={10} className="py-8 text-center text-text-muted">
                    No province records matching the current filters.
                  </td>
                </tr>
              ) : (
                filteredProvinces.map((prov) => {
                  const isSelected = selectedProvince === prov.province;
                  return (
                    <tr
                      key={prov.provinceKey}
                      onClick={() =>
                        setSelectedProvince(isSelected ? null : prov.province)
                      }
                      className={`cursor-pointer transition hover:bg-surface-hover ${
                        isSelected ? "bg-brand-50/60 font-semibold" : ""
                      }`}
                    >
                      <td className="py-3 px-4 font-bold text-text-primary flex items-center gap-2">
                        <MapPin className="h-3.5 w-3.5 text-text-muted" />
                        <span>{prov.province.toUpperCase()}</span>
                      </td>
                      <td className="py-3 px-3 text-right font-mono font-bold text-text-primary">
                        {prov.total}
                      </td>
                      <td className="py-3 px-2 text-center font-mono text-text-primary">
                        {prov.bucket1_15 || "-"}
                      </td>
                      <td className="py-3 px-2 text-center font-mono text-text-primary">
                        {prov.bucket16_30 || "-"}
                      </td>
                      <td className="py-3 px-2 text-center font-mono text-text-primary">
                        {prov.bucket31_60 || "-"}
                      </td>
                      <td className="py-3 px-2 text-center font-mono text-text-primary">
                        {prov.bucket61_120 || "-"}
                      </td>
                      <td className="py-3 px-2 text-center font-mono text-text-primary font-bold">
                        {prov.bucketGt121 || "-"}
                      </td>
                      <td className="py-3 px-3 text-center font-mono text-text-primary">
                        {prov.advanceCount || "-"}
                      </td>
                      <td className="py-3 px-3 text-center font-mono text-text-secondary">
                        {prov.storeCount}
                      </td>
                      <td className="py-3 px-4 text-right">
                        <span
                          className={`inline-flex items-center gap-1 rounded px-2 py-0.5 text-[10px] font-bold ${
                            isSelected
                              ? "bg-brand-600 text-white"
                              : "bg-surface-muted text-text-secondary hover:bg-brand-100 hover:text-brand-800"
                          }`}
                        >
                          {isSelected ? "Active Filter" : "View Outlets"}
                          <ChevronRight className="h-3 w-3" />
                        </span>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* 6. Store-Level Vacancy Drilldown Section */}
      <section className="space-y-3" aria-label="Store-Level Vacancy Drilldown">
        <div className="flex items-center justify-between">
          <div>
            <h3 className="text-sm font-bold text-text-primary flex items-center gap-2">
              <Store className="h-4 w-4 text-brand-600" />
              Store-Level Outlet Drilldown
              {selectedProvince && (
                <span className="text-xs font-normal text-text-secondary">
                  — Filtered to <strong>{selectedProvince}</strong>
                </span>
              )}
            </h3>
            <p className="text-xs text-text-muted mt-0.5">
              Showing {filteredOutlets.length} store outlets with open vacancies and coverage status
            </p>
          </div>
          {selectedProvince && (
            <button
              onClick={() => setSelectedProvince(null)}
              className="text-xs font-semibold text-brand-600 hover:text-brand-800 cursor-pointer"
            >
              Clear Province Filter
            </button>
          )}
        </div>

        <div className="space-y-3">
          {filteredOutlets.length === 0 ? (
            <div className="rounded-xl border border-border-default bg-surface-base p-8 text-center text-text-muted">
              No store outlets found matching the selected province and search criteria.
            </div>
          ) : (
            filteredOutlets.map((outlet) => {
              const isExpanded = expandedOutlets.has(outlet.key);
              return (
                <div
                  key={outlet.key}
                  className="rounded-xl border border-border-default bg-surface-base shadow-xs overflow-hidden transition"
                >
                  {/* Outlet Summary Header */}
                  <div
                    onClick={() => toggleOutletExpand(outlet.key)}
                    className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 p-4 cursor-pointer hover:bg-surface-hover/70 transition"
                  >
                    <div className="flex items-start gap-3">
                      <div className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-brand-50 text-brand-700 border border-brand-100">
                        <Store className="h-4 w-4" />
                      </div>
                      <div>
                        <div className="flex items-center gap-2 flex-wrap">
                          <h4 className="text-sm font-bold text-text-primary">
                            {outlet.store}
                          </h4>
                          <span className="inline-flex items-center gap-1 rounded bg-surface-muted px-2 py-0.5 text-[10px] font-semibold text-text-secondary">
                            <MapPin className="h-3 w-3 text-text-muted" />
                            {outlet.area}, {outlet.province}
                          </span>
                        </div>
                        <div className="mt-1 flex items-center gap-3 text-xs text-text-secondary flex-wrap">
                          <span>
                            HRCO: <strong>{outlet.hrco}</strong>
                          </span>
                          <span>•</span>
                          <span>
                            Open Positions:{" "}
                            <strong className="text-text-primary font-mono">
                              {outlet.vacancies.length}
                            </strong>
                          </span>
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center gap-3 self-end sm:self-auto">
                      {/* Oldest aging badge */}
                      <div className="text-right">
                        <div className="text-[10px] uppercase font-bold text-text-muted">
                          Oldest Aging
                        </div>
                        <span className="inline-flex items-center gap-1 text-xs font-bold font-mono px-2 py-0.5 rounded border bg-surface-muted text-text-secondary border-border-default">
                          {outlet.oldestAging > 0 ? `${outlet.oldestAging} Days` : "Advance"}
                        </span>
                      </div>

                      {/* Reliever status */}
                      <span className="inline-flex items-center gap-1 rounded px-2.5 py-1 text-[11px] font-semibold border bg-surface-muted text-text-secondary border-border-default">
                        <UserCheck className="h-3.5 w-3.5" />
                        {outlet.relieverStatus}
                      </span>

                      <button
                        type="button"
                        className="p-1 text-text-muted hover:text-text-primary"
                        aria-label="Toggle store detail"
                      >
                        {isExpanded ? (
                          <ChevronDown className="h-5 w-5" />
                        ) : (
                          <ChevronRight className="h-5 w-5" />
                        )}
                      </button>
                    </div>
                  </div>

                  {/* Expanded Vacancies at this Store */}
                  {isExpanded && (
                    <div className="border-t border-border-subtle bg-surface-muted/40 p-4">
                      <div className="text-[11px] font-bold uppercase tracking-wider text-text-secondary mb-2">
                        Active Vacancies at {outlet.store} ({outlet.vacancies.length})
                      </div>
                      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
                        {outlet.vacancies.map((v) => (
                          <div
                            key={v.id}
                            className="rounded-lg border border-border-default bg-surface-base p-3 shadow-2xs space-y-2"
                          >
                            <div className="flex items-center justify-between">
                              <span className="font-mono text-xs font-bold text-brand-700">
                                {v.vcode}
                              </span>
                              <span className="rounded px-1.5 py-0.5 text-[9px] font-bold uppercase border bg-surface-muted text-text-secondary border-border-default">
                                {v.urgencyLevel || "Normal"}
                              </span>
                            </div>

                            <div>
                              <div className="text-xs font-semibold text-text-primary">
                                {v.position}
                              </div>
                              <div className="text-[11px] text-text-muted">
                                Account: {v.account}
                              </div>
                            </div>

                            <div className="flex items-center justify-between text-[11px] pt-2 border-t border-border-subtle text-text-secondary">
                              <span>
                                Vacant Date: <strong>{v.vacantDate || "--"}</strong>
                              </span>
                              <span className="font-mono font-bold text-text-primary">
                                {v.agingDays ? `${v.agingDays}d open` : "Advance"}
                              </span>
                            </div>

                            {v.targetFillDate && (
                              <div className="text-[10px] text-text-muted flex items-center gap-1">
                                <Calendar className="h-3 w-3" />
                                Target Fill: {v.targetFillDate}
                              </div>
                            )}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              );
            })
          )}
        </div>
      </section>
    </div>
  );
}
