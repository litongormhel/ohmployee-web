import React from "react";
import {
  Users,
  UserMinus,
  Briefcase,
  UserCheck,
  Share2,
  AlertCircle,
  UserX,
  List,
  LayoutGrid,
  Search,
  X,
  RotateCcw,
} from "lucide-react";
import type {
  MainViewToggle,
  StatusSubTab,
  DisplayView,
} from "./types";

export interface PlantillaFilterToolbarProps {
  mainView: MainViewToggle;
  statusTab: StatusSubTab;
  onSelectStatusTab: (tab: StatusSubTab) => void;
  activeCount: number;
  onLeaveCount: number;
  vacancyCount: number;
  pipelineCount?: number;
  floatingCount: number;
  deactivationCount: number;
  inactiveCount: number;
  displayView: DisplayView;
  onSetDisplayView: (view: DisplayView) => void;
  search: string;
  onSearchChange: (value: string) => void;
  areaCityFilter: string;
  onAreaCityFilterChange: (value: string) => void;
  hierarchicalAreaOptions: { area: string; cities: string[] }[];
  assignmentType: string;
  onAssignmentTypeChange: (value: string) => void;
  storeStatusFilter?: "active" | "archived" | "all";
  onStoreStatusFilterChange?: (value: "active" | "archived" | "all") => void;
  hasActiveFilters: boolean;
  onResetFilters: () => void;
}

export function PlantillaFilterToolbar({
  mainView,
  statusTab,
  onSelectStatusTab,
  activeCount,
  onLeaveCount,
  vacancyCount,
  pipelineCount = 0,
  floatingCount,
  deactivationCount,
  inactiveCount,
  displayView,
  onSetDisplayView,
  search,
  onSearchChange,
  areaCityFilter,
  onAreaCityFilterChange,
  hierarchicalAreaOptions,
  assignmentType,
  onAssignmentTypeChange,
  storeStatusFilter = "active",
  onStoreStatusFilterChange,
  hasActiveFilters,
  onResetFilters,
}: PlantillaFilterToolbarProps) {
  return (
    <>
      {/* Employee View Sub-Tabs (Hidden when mainView === "store") */}
      {mainView === "employee" && (
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-border-subtle pb-2 shrink-0">
          <div
            role="tablist"
            aria-label="Plantilla Directory Tabs"
            className="flex items-center gap-1.5 overflow-x-auto no-scrollbar scrollbar-none"
          >
            {/* Tab 1: Active */}
            <button
              type="button"
              role="tab"
              aria-selected={statusTab === "active"}
              onClick={() => onSelectStatusTab("active")}
              className={`group inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border px-3 py-1 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                statusTab === "active"
                  ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                  : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
              }`}
            >
              <Users className="w-3.5 h-3.5 shrink-0" />
              <span>Active</span>
              <span
                className={`ml-1 shrink-0 rounded-full px-1.5 py-0.2 font-sans tabular-nums text-[11px] font-semibold shadow-2xs transition-colors ${
                  statusTab === "active"
                    ? "bg-brand-button text-white"
                    : "bg-surface-muted text-text-secondary border border-border-default"
                }`}
              >
                {activeCount}
              </span>
            </button>

            {/* Tab 2: On-Leave */}
            <button
              type="button"
              role="tab"
              aria-selected={statusTab === "on_leave"}
              onClick={() => onSelectStatusTab("on_leave")}
              className={`group inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border px-3 py-1 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                statusTab === "on_leave"
                  ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                  : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
              }`}
            >
              <UserMinus className="w-3.5 h-3.5 shrink-0" />
              <span>On-Leave</span>
              <span
                className={`ml-1 shrink-0 rounded-full px-1.5 py-0.2 font-sans tabular-nums text-[11px] font-semibold shadow-2xs transition-colors ${
                  statusTab === "on_leave"
                    ? "bg-brand-button text-white"
                    : "bg-surface-muted text-text-secondary border border-border-default"
                }`}
              >
                {onLeaveCount}
              </span>
            </button>

            {/* Tab 3: Vacancy */}
            <button
              type="button"
              role="tab"
              aria-selected={statusTab === "vacancy"}
              onClick={() => onSelectStatusTab("vacancy")}
              className={`group inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border px-3 py-1 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                statusTab === "vacancy"
                  ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                  : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
              }`}
            >
              <Briefcase className="w-3.5 h-3.5 shrink-0" />
              <span>Vacancy</span>
              <span
                className={`ml-1 shrink-0 rounded-full px-1.5 py-0.2 font-sans tabular-nums text-[11px] font-semibold shadow-2xs transition-colors ${
                  statusTab === "vacancy"
                    ? "bg-brand-button text-white"
                    : "bg-surface-muted text-text-secondary border border-border-default"
                }`}
              >
                {vacancyCount}
              </span>
            </button>

            {/* Tab 4: Pipeline (Recruitment / Onboarding) */}
            <button
              type="button"
              role="tab"
              aria-selected={statusTab === "pipeline"}
              onClick={() => onSelectStatusTab("pipeline")}
              className={`group inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border px-3 py-1 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                statusTab === "pipeline"
                  ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                  : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
              }`}
            >
              <UserCheck className="w-3.5 h-3.5 shrink-0" />
              <span>Pipeline</span>
              <span
                className={`ml-1 shrink-0 rounded-full px-1.5 py-0.2 font-sans tabular-nums text-[11px] font-semibold shadow-2xs transition-colors ${
                  statusTab === "pipeline"
                    ? "bg-brand-button text-white"
                    : "bg-surface-muted text-text-secondary border border-border-default"
                }`}
              >
                {pipelineCount}
              </span>
            </button>

            {/* Tab 5: Floating */}
            <button
              type="button"
              role="tab"
              aria-selected={statusTab === "floating"}
              onClick={() => onSelectStatusTab("floating")}
              className={`group inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border px-3 py-1 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                statusTab === "floating"
                  ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                  : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
              }`}
            >
              <Share2 className="w-3.5 h-3.5 shrink-0" />
              <span>Floating</span>
              <span
                className={`ml-1 shrink-0 rounded-full px-1.5 py-0.2 font-sans tabular-nums text-[11px] font-semibold shadow-2xs transition-colors ${
                  statusTab === "floating"
                    ? "bg-brand-button text-white"
                    : "bg-surface-muted text-text-secondary border border-border-default"
                }`}
              >
                {floatingCount}
              </span>
            </button>

            {/* Tab 5: Deactivation */}
            <button
              type="button"
              role="tab"
              aria-selected={statusTab === "deactivation"}
              onClick={() => onSelectStatusTab("deactivation")}
              className={`group inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border px-3 py-1 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                statusTab === "deactivation"
                  ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                  : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
              }`}
            >
              <AlertCircle className="w-3.5 h-3.5 shrink-0" />
              <span>Deactivation</span>
              <span
                className={`ml-1 shrink-0 rounded-full px-1.5 py-0.2 font-sans tabular-nums text-[11px] font-semibold shadow-2xs transition-colors ${
                  statusTab === "deactivation"
                    ? "bg-brand-button text-white"
                    : "bg-surface-muted text-text-secondary border border-border-default"
                }`}
              >
                {deactivationCount}
              </span>
            </button>

            {/* Tab 6: Inactive */}
            <button
              type="button"
              role="tab"
              aria-selected={statusTab === "inactive"}
              onClick={() => onSelectStatusTab("inactive")}
              className={`group inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border px-3 py-1 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                statusTab === "inactive"
                  ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                  : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
              }`}
            >
              <UserX className="w-3.5 h-3.5 shrink-0" />
              <span>Inactive</span>
              <span
                className={`ml-1 shrink-0 rounded-full px-1.5 py-0.2 font-sans tabular-nums text-[11px] font-semibold shadow-2xs transition-colors ${
                  statusTab === "inactive"
                    ? "bg-brand-button text-white"
                    : "bg-surface-muted text-text-secondary border border-border-default"
                }`}
              >
                {inactiveCount}
              </span>
            </button>
          </div>

          {/* View switch: Table vs Cards (Employee view) */}
          <div className="flex h-8 items-center rounded-lg border border-border-default bg-surface-muted p-0.5">
            <button
              type="button"
              onClick={() => onSetDisplayView("table")}
              aria-label="Table View"
              title="Table View"
              className={`inline-flex h-full items-center gap-1.5 rounded-md px-2.5 text-xs font-semibold transition-colors cursor-pointer ${
                displayView === "table"
                  ? "bg-surface-base text-text-primary shadow-xs"
                  : "text-text-muted hover:text-text-primary"
              }`}
            >
              <List className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">Table</span>
            </button>
            <button
              type="button"
              onClick={() => onSetDisplayView("cards")}
              aria-label="Cards View"
              title="Cards View"
              className={`inline-flex h-full items-center gap-1.5 rounded-md px-2.5 text-xs font-semibold transition-colors cursor-pointer ${
                displayView === "cards"
                  ? "bg-surface-base text-text-primary shadow-xs"
                  : "text-text-muted hover:text-text-primary"
              }`}
            >
              <LayoutGrid className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">Cards</span>
            </button>
          </div>
        </div>
      )}

      {/* Unified Web Search & Filter Toolbar */}
      <div className="flex flex-col lg:flex-row items-stretch lg:items-center gap-2 rounded-xl border border-border-default bg-surface-base px-3 py-2 shadow-xs shrink-0">
        <div className="relative flex-1 min-w-[200px]">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-text-muted" />
          <input
            type="text"
            placeholder="Search employee, emploc no, name, store..."
            value={search}
            onChange={(e) => onSearchChange(e.target.value)}
            className="h-8.5 w-full rounded-lg border border-border-default bg-surface-muted pl-8 pr-8 text-xs text-text-primary outline-none transition-colors focus:border-brand-500 focus:bg-surface-base"
            aria-label="Search plantilla roster"
          />
          {search && (
            <button
              type="button"
              onClick={() => onSearchChange("")}
              className="absolute right-2.5 top-1/2 -translate-y-1/2 rounded-full p-1 text-text-muted hover:text-text-primary hover:bg-surface-hover transition-colors cursor-pointer"
              aria-label="Clear search"
            >
              <X className="h-3 w-3" />
            </button>
          )}
        </div>

        {/* Hierarchical Area -> City Dropdown */}
        <div className="flex flex-wrap items-center gap-2">
          <div className="min-w-[190px] flex-1 sm:flex-initial">
            <select
              value={areaCityFilter}
              onChange={(e) => onAreaCityFilterChange(e.target.value)}
              className="h-8.5 w-full rounded-lg border border-border-default bg-surface-base px-2.5 text-xs text-text-primary outline-none transition-colors focus:border-brand-500 cursor-pointer"
              aria-label="Filter by store area or city"
            >
              <option value="">All Stores (All Areas & Cities)</option>
              {hierarchicalAreaOptions.map(({ area, cities }) => (
                <optgroup key={area} label={area}>
                  <option value={`area:${area}`}>All {area} Stores</option>
                  {cities.map((city) => (
                    <option key={`${area}:${city}`} value={`city:${city}`}>
                      {city}, {area}
                    </option>
                  ))}
                </optgroup>
              ))}
            </select>
          </div>

          {/* Assignment Type Dropdown (Stationary / Roving) */}
          <div className="min-w-[115px] flex-1 sm:flex-initial">
            <select
              value={assignmentType}
              onChange={(e) => onAssignmentTypeChange(e.target.value)}
              className="h-8.5 w-full rounded-lg border border-border-default bg-surface-base px-2.5 text-xs text-text-primary outline-none transition-colors focus:border-brand-500 cursor-pointer"
              aria-label="Filter by assignment type"
            >
              <option value="">All Types</option>
              <option value="stationary">Stationary</option>
              <option value="roving">Roving</option>
            </select>
          </div>

          {/* Store Status Dropdown (Active / Archived / All) when in Store View */}
          {mainView === "store" && (
            <div className="min-w-[130px] flex-1 sm:flex-initial">
              <select
                value={storeStatusFilter}
                onChange={(e) => onStoreStatusFilterChange?.(e.target.value as "active" | "archived" | "all")}
                className="h-8.5 w-full rounded-lg border border-border-default bg-surface-base px-2.5 text-xs text-text-primary outline-none transition-colors focus:border-brand-500 cursor-pointer"
                aria-label="Filter stores by active or archived status"
              >
                <option value="active">Active Stores</option>
                <option value="archived">Archived Stores</option>
                <option value="all">All Stores</option>
              </select>
            </div>
          )}

          {hasActiveFilters && (
            <button
              type="button"
              onClick={onResetFilters}
              className="inline-flex h-8.5 items-center gap-1 rounded-lg border border-border-default bg-surface-muted px-2.5 text-xs font-semibold text-text-primary hover:bg-surface-hover transition-colors shadow-2xs cursor-pointer"
            >
              <RotateCcw className="h-3 w-3" />
              <span>Reset</span>
            </button>
          )}
        </div>
      </div>
    </>
  );
}
