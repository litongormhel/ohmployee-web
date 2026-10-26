"use client";

import { useState, type FormEvent } from "react";
import {
  FileSearch,
  Filter,
  RotateCcw,
  Search,
  X,
} from "lucide-react";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";

export interface VacancyFilterToolbarProps {
  searchDraft: string;
  onSearchChange: (value: string) => void;
  onSearchSubmit: () => void;
  onClearSearch: () => void;
  accountId: string;
  onAccountChange: (accountId: string) => void;
  accounts: Array<{ id: string; name: string }>;
  groupId: string;
  onGroupChange: (groupId: string) => void;
  groups: Array<{ id: string; name: string }>;
  agingBucket: string;
  urgency: string;
  vacantFrom: string;
  vacantTo: string;
  onApplyAdvancedFilters: (filters: {
    agingBucket: string;
    urgency: string;
    vacantFrom: string;
    vacantTo: string;
  }) => void;
  onResetAdvancedFilters: () => void;
  onClearAll: () => void;
  onOpenSavedViews?: () => void;
  savedViewsCount?: number;
  disabled?: boolean;
}

export function VacancyFilterToolbar({
  searchDraft,
  onSearchChange,
  onSearchSubmit,
  onClearSearch,
  accountId,
  onAccountChange,
  accounts,
  groupId,
  onGroupChange,
  groups,
  agingBucket,
  urgency,
  vacantFrom,
  vacantTo,
  onApplyAdvancedFilters,
  onResetAdvancedFilters,
  onClearAll,
  onOpenSavedViews,
  savedViewsCount = 0,
  disabled = false,
}: VacancyFilterToolbarProps) {
  const [popoverOpen, setPopoverOpen] = useState(false);
  const [draftAging, setDraftAging] = useState(agingBucket);
  const [draftUrgency, setDraftUrgency] = useState(urgency);
  const [draftVacantFrom, setDraftVacantFrom] = useState(vacantFrom);
  const [draftVacantTo, setDraftVacantTo] = useState(vacantTo);

  const handleOpenChange = (open: boolean) => {
    if (open) {
      setDraftAging(agingBucket);
      setDraftUrgency(urgency);
      setDraftVacantFrom(vacantFrom);
      setDraftVacantTo(vacantTo);
    }
    setPopoverOpen(open);
  };

  const activeSecondaryCount = [
    Boolean(agingBucket),
    Boolean(urgency),
    Boolean(vacantFrom || vacantTo),
  ].filter(Boolean).length;

  const isAnyFilterActive = Boolean(
    searchDraft.trim() ||
      accountId ||
      groupId ||
      agingBucket ||
      urgency ||
      vacantFrom ||
      vacantTo,
  );

  const handleSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    onSearchSubmit();
  };

  const handleApplyDraftFilters = () => {
    onApplyAdvancedFilters({
      agingBucket: draftAging,
      urgency: draftUrgency,
      vacantFrom: draftVacantFrom,
      vacantTo: draftVacantTo,
    });
    setPopoverOpen(false);
  };

  const handleResetDraftFilters = () => {
    setDraftAging("");
    setDraftUrgency("");
    setDraftVacantFrom("");
    setDraftVacantTo("");
    onResetAdvancedFilters();
    setPopoverOpen(false);
  };

  return (
    <form
      onSubmit={handleSubmit}
      className="flex flex-wrap items-center justify-between gap-2.5 p-3 rounded-lg border border-border-subtle bg-surface mb-4"
    >
      {/* Left / Center Controls */}
      <div className="flex flex-1 flex-wrap items-center gap-2.5 min-w-0">
        {/* Search Input */}
        <div className="relative flex-1 min-w-[280px]">
          <Search
            className="pointer-events-none absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-text-muted"
            aria-hidden="true"
          />
          <input
            aria-label="Search vacancies"
            className="h-9 w-full rounded-md border border-border-default bg-surface-muted pl-9 pr-8 text-xs text-text-primary outline-none transition-colors focus:border-brand-500 focus:bg-surface-base disabled:cursor-not-allowed disabled:opacity-75"
            disabled={disabled}
            onChange={(e) => onSearchChange(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                onSearchSubmit();
              }
            }}
            placeholder="Search code, position, outlet, applicant, HRCO..."
            type="text"
            value={searchDraft}
          />
          {searchDraft && (
            <button
              aria-label="Clear search"
              className="absolute right-2.5 top-1/2 -translate-y-1/2 rounded p-0.5 text-text-muted hover:text-text-primary transition-colors cursor-pointer"
              disabled={disabled}
              onClick={onClearSearch}
              type="button"
            >
              <X className="h-3.5 w-3.5" aria-hidden="true" />
            </button>
          )}
        </div>

        {/* Inline Quick Selector: Account */}
        <select
          aria-label="Account filter"
          className="h-9 min-w-[140px] rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-primary outline-none focus:border-brand-500 hover:border-border-strong transition-colors cursor-pointer disabled:cursor-not-allowed disabled:opacity-50"
          disabled={disabled}
          onChange={(e) => onAccountChange(e.target.value)}
          value={accountId}
        >
          <option value="">All accounts</option>
          {accounts.map((account) => (
            <option key={account.id} value={account.id}>
              {account.name}
            </option>
          ))}
        </select>

        {/* Inline Quick Selector: Group */}
        <select
          aria-label="Group filter"
          className="h-9 min-w-[140px] rounded-md border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-primary outline-none focus:border-brand-500 hover:border-border-strong transition-colors cursor-pointer disabled:cursor-not-allowed disabled:opacity-50"
          disabled={disabled}
          onChange={(e) => onGroupChange(e.target.value)}
          value={groupId}
        >
          <option value="">All groups</option>
          {groups.map((group) => (
            <option key={group.id} value={group.id}>
              {group.name}
            </option>
          ))}
        </select>

        {/* Advanced Filters Popover */}
        <Popover open={popoverOpen} onOpenChange={handleOpenChange}>
          <PopoverTrigger asChild>
            <button
              aria-label="Advanced filters"
              className={`inline-flex h-9 shrink-0 items-center gap-1.5 rounded-md border px-3 text-xs font-semibold transition-colors cursor-pointer disabled:cursor-not-allowed disabled:opacity-50 ${
                activeSecondaryCount > 0
                  ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                  : "border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover hover:text-text-primary"
              }`}
              disabled={disabled}
              type="button"
            >
              <Filter className="h-3.5 w-3.5 text-current" aria-hidden="true" />
              <span>
                {activeSecondaryCount > 0
                  ? `Filters · ${activeSecondaryCount}`
                  : "Filters"}
              </span>
            </button>
          </PopoverTrigger>

          <PopoverContent align="start" className="w-80">
            <div className="flex flex-col gap-3.5">
              <div className="flex items-center justify-between border-b border-border-subtle pb-2.5">
                <span className="text-xs font-semibold text-text-primary">
                  Advanced Filters
                </span>
                {activeSecondaryCount > 0 && (
                  <span className="rounded-full bg-surface-muted border border-border-default px-2 py-0.5 text-xs font-semibold text-text-primary">
                    {activeSecondaryCount} active
                  </span>
                )}
              </div>

              {/* Aging Bucket */}
              <div className="space-y-1">
                <label
                  htmlFor="popover-filter-aging"
                  className="block text-[11px] font-medium text-text-secondary"
                >
                  Aging Bucket
                </label>
                <select
                  id="popover-filter-aging"
                  className="h-9 w-full rounded-md border border-border-default bg-surface-base px-2.5 text-xs text-text-primary outline-none focus:border-brand-500"
                  onChange={(e) => setDraftAging(e.target.value)}
                  value={draftAging}
                >
                  <option value="">All aging</option>
                  <option value="advance">Advance</option>
                  <option value="1_15">1-15 days</option>
                  <option value="16_30">16-30 days</option>
                  <option value="31_60">31-60 days</option>
                  <option value="61_120">61-120 days</option>
                  <option value="gt121">121+ days</option>
                </select>
              </div>

              {/* Urgency */}
              <div className="space-y-1">
                <label
                  htmlFor="popover-filter-urgency"
                  className="block text-[11px] font-medium text-text-secondary"
                >
                  Urgency
                </label>
                <select
                  id="popover-filter-urgency"
                  className="h-9 w-full rounded-md border border-border-default bg-surface-base px-2.5 text-xs text-text-primary outline-none focus:border-brand-500"
                  onChange={(e) => setDraftUrgency(e.target.value)}
                  value={draftUrgency}
                >
                  <option value="">All urgency</option>
                  <option value="High">High</option>
                  <option value="Medium">Medium</option>
                  <option value="Normal">Normal</option>
                </select>
              </div>

              {/* Date Range (From - To) */}
              <div className="space-y-1">
                <label className="block text-[11px] font-medium text-text-secondary">
                  Vacant Date Range
                </label>
                <div className="grid grid-cols-2 gap-2">
                  <div>
                    <span className="block text-[10px] text-text-muted mb-0.5">
                      From
                    </span>
                    <input
                      aria-label="Vacant date from"
                      className="h-9 w-full rounded-md border border-border-default bg-surface-base px-2 text-xs text-text-primary outline-none focus:border-brand-500"
                      max={draftVacantTo || undefined}
                      onChange={(e) => setDraftVacantFrom(e.target.value)}
                      type="date"
                      value={draftVacantFrom}
                    />
                  </div>
                  <div>
                    <span className="block text-[10px] text-text-muted mb-0.5">
                      To
                    </span>
                    <input
                      aria-label="Vacant date to"
                      className="h-9 w-full rounded-md border border-border-default bg-surface-base px-2 text-xs text-text-primary outline-none focus:border-brand-500"
                      min={draftVacantFrom || undefined}
                      onChange={(e) => setDraftVacantTo(e.target.value)}
                      type="date"
                      value={draftVacantTo}
                    />
                  </div>
                </div>
              </div>

              {/* Popover Footer: Reset & Apply actions */}
              <div className="flex items-center justify-between border-t border-border-subtle pt-3 mt-1">
                <button
                  className="h-8 px-3 rounded-md text-xs font-medium text-text-muted hover:text-text-primary hover:bg-surface-hover transition-colors cursor-pointer"
                  onClick={handleResetDraftFilters}
                  type="button"
                >
                  Reset
                </button>
                <button
                  className="h-8 px-3.5 rounded-md text-xs font-semibold bg-brand-600 text-white hover:bg-brand-700 transition-colors shadow-2xs cursor-pointer"
                  onClick={handleApplyDraftFilters}
                  type="button"
                >
                  Apply
                </button>
              </div>
            </div>
          </PopoverContent>
        </Popover>
      </div>

      {/* Action Endcap */}
      <div className="flex items-center gap-2 shrink-0">
        {isAnyFilterActive && (
          <button
            aria-label="Clear all filters"
            className="inline-flex h-9 items-center gap-1.5 rounded-md px-2.5 text-xs font-medium text-text-muted hover:text-text-primary hover:bg-surface-hover transition-colors cursor-pointer"
            disabled={disabled}
            onClick={onClearAll}
            type="button"
          >
            <RotateCcw className="h-3.5 w-3.5" aria-hidden="true" />
            <span>Clear All</span>
          </button>
        )}
        <button
          className="inline-flex h-9 items-center gap-1.5 rounded-md border border-border-subtle bg-surface-base px-3 text-xs font-medium text-text-secondary hover:bg-surface-hover hover:text-text-primary transition-colors shadow-2xs cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
          disabled={disabled}
          onClick={onOpenSavedViews}
          type="button"
          aria-label="Open saved views and presets"
        >
          <FileSearch className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
          <span>Saved View</span>
          {typeof savedViewsCount === "number" && savedViewsCount > 0 && (
            <span className="ml-0.5 rounded-full bg-surface-muted border border-border-default px-1.5 py-0.2 text-xs font-semibold text-text-primary">
              {savedViewsCount}
            </span>
          )}
        </button>
      </div>
    </form>
  );
}
