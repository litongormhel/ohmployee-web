import React from "react";
import {
  Building,
  Share2,
  MoreVertical,
  ArrowRightLeft,
  Archive,
  GitFork,
} from "lucide-react";
import { DataState } from "@/components/shared/DataState";
import {
  formatAccountName,
  formatDisplayText,
} from "@/lib/utils/displayText";
import type { PlantillaScopedAccountItem } from "@/lib/queries/plantilla";
import type { AccountSummaryMetric, ArchiveModalAccount } from "./types";

export interface PlantillaAccountSelectionProps {
  allowedAccounts: PlantillaScopedAccountItem[];
  isLoading: boolean;
  isError: boolean;
  onRetry: () => void;
  accountSearch: string;
  onAccountSearchChange: (value: string) => void;
  uniqueGroups: { id: string; name: string }[];
  effectiveSelectorGroupId: string;
  onSelectorGroupIdChange: (value: string) => void;
  hasAllScope: boolean;
  getAccountSummary: (accId: string) => AccountSummaryMetric;
  onSelectAccount: (accId: string) => void;
  activeMenuAccountId: string | null;
  setActiveMenuAccountId: (id: string | null | ((prev: string | null) => string | null)) => void;
  onAbsorbClick: (account: { id: string; name: string }) => void;
  onArchiveClick: (account: ArchiveModalAccount) => void;
  canTransferGroup?: boolean;
  onTransferGroupClick?: (account: PlantillaScopedAccountItem) => void;
}

export function PlantillaAccountSelection({
  allowedAccounts,
  isLoading,
  isError,
  onRetry,
  accountSearch,
  onAccountSearchChange,
  uniqueGroups,
  effectiveSelectorGroupId,
  onSelectorGroupIdChange,
  hasAllScope,
  getAccountSummary,
  onSelectAccount,
  activeMenuAccountId,
  setActiveMenuAccountId,
  onAbsorbClick,
  onArchiveClick,
  canTransferGroup,
  onTransferGroupClick,
}: PlantillaAccountSelectionProps) {
  if (isLoading) {
    return (
      <DataState
        kind="loading"
        title="Loading Accounts"
        description="Fetching your authorized accounts..."
      />
    );
  }

  if (isError) {
    return (
      <DataState
        kind="error"
        title="Failed to Load Accounts"
        description="An error occurred while fetching your authorized billing accounts."
        onRetry={onRetry}
      />
    );
  }

  if (allowedAccounts.length === 0) {
    return (
      <DataState
        kind="access_denied"
        title="No Authorized Accounts"
        description="Your user profile does not have any active billing account scopes assigned. Access remains restricted."
      />
    );
  }

  const filteredAccounts = allowedAccounts.filter((a) => {
    const matchesSearch = a.name.toLowerCase().includes(accountSearch.toLowerCase());
    const matchesGroup = !effectiveSelectorGroupId || a.groupId === effectiveSelectorGroupId;
    return matchesSearch && matchesGroup;
  });

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center gap-3">
        <div className="relative w-full max-w-xs">
          <input
            type="text"
            placeholder="Search accounts..."
            value={accountSearch}
            onChange={(e) => onAccountSearchChange(e.target.value)}
            className="h-10 w-full rounded-lg border border-border-default bg-surface-base px-3 text-sm text-text-primary outline-none focus:border-brand-500 transition-colors"
          />
        </div>
        {uniqueGroups.length > 0 && (
          <select
            value={effectiveSelectorGroupId}
            onChange={(e) => onSelectorGroupIdChange(e.target.value)}
            className="h-10 rounded-lg border border-border-default bg-surface-base px-3 text-sm text-text-primary outline-none focus:border-brand-500 transition-colors"
            aria-label="Filter accounts by group"
          >
            <option value="">{hasAllScope ? "All Groups" : "All Assigned Groups"}</option>
            {uniqueGroups.map((g) => (
              <option key={g.id} value={g.id}>
                {g.name}
              </option>
            ))}
          </select>
        )}
        {(accountSearch || effectiveSelectorGroupId) && (
          <button
            type="button"
            onClick={() => {
              onAccountSearchChange("");
              onSelectorGroupIdChange("");
            }}
            className="text-sm font-semibold text-brand-600 hover:text-brand-700 px-2 cursor-pointer"
          >
            Clear Filters
          </button>
        )}
      </div>

      {filteredAccounts.length === 0 ? (
        <DataState
          kind="empty"
          title="No accounts match search"
          description="Try searching with a different term."
        />
      ) : (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {(() => {
            const sortedAccounts = filteredAccounts
              .map((account) => {
                const summary = getAccountSummary(account.id);
                const actual = summary.actual;
                const vacant = summary.vacant;
                const hrProcess = summary.hrProcess;
                const leave = summary.leave;
                const required = summary.required;
                const fillRate = required > 0 ? (actual / required) * 100 : 0;

                return {
                  ...account,
                  actual,
                  vacant,
                  hrProcess,
                  leave,
                  required,
                  fillRate,
                };
              })
              .sort((a, b) => {
                const aIsPool = !!a.isPoolAccount || a.name.trim().toLowerCase() === "moses hq";
                const bIsPool = !!b.isPoolAccount || b.name.trim().toLowerCase() === "moses hq";

                // 0. MOSES HQ / Pool Account is ALWAYS pinned to the very front
                if (aIsPool && !bIsPool) return -1;
                if (!aIsPool && bIsPool) return 1;

                const aHasRequirements = a.required > 0;
                const bHasRequirements = b.required > 0;

                // 1. Accounts with active headcount requirements precede accounts with blank MFR
                if (aHasRequirements && !bHasRequirements) return -1;
                if (!aHasRequirements && bHasRequirements) return 1;

                // 2. Both have active requirements: lowest fillRate first
                if (aHasRequirements && bHasRequirements) {
                  if (a.fillRate !== b.fillRate) {
                    return a.fillRate - b.fillRate;
                  }
                  // Tie-breaker: higher vacant slots first
                  if (b.vacant !== a.vacant) {
                    return b.vacant - a.vacant;
                  }
                }

                // 3. Alphabetical tie-breaker
                return a.name.localeCompare(b.name);
              });

            return sortedAccounts.map((account) => {
              const getProgressColors = (rate: number) => {
                if (rate >= 100) {
                  return {
                    bar: "bg-pct-good-bar",
                    text: "text-pct-good-text",
                    track: "bg-surface-muted border border-border-subtle/50",
                  };
                }
                if (rate >= 95) {
                  return {
                    bar: "bg-pct-warn-bar",
                    text: "text-pct-warn-text",
                    track: "bg-surface-muted border border-border-subtle/50",
                  };
                }
                return {
                  bar: "bg-pct-bad-bar",
                  text: "text-pct-bad-text",
                  track: "bg-surface-muted border border-border-subtle/50",
                };
              };

              const colors = getProgressColors(account.fillRate);

              return (
                <div
                  key={account.id}
                  role="button"
                  tabIndex={0}
                  onClick={() => onSelectAccount(account.id)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      onSelectAccount(account.id);
                    }
                  }}
                  className="group relative flex w-full items-start gap-4 rounded-xl border border-border-default bg-surface-base p-5 text-left transition-all duration-300 hover:-translate-y-0.5 hover:border-brand-primary hover:shadow-md focus:outline-none focus:ring-2 focus:ring-brand-primary focus:ring-offset-2 cursor-pointer"
                >
                  <div
                    className={`shrink-0 rounded-lg p-2.5 ${
                      account.isPoolAccount
                        ? "bg-surface-muted text-brand-primary border border-border-default"
                        : "bg-brand-50/60 text-brand-primary"
                    }`}
                  >
                    {account.isPoolAccount ? (
                      <Share2 className="h-5 w-5" />
                    ) : (
                      <Building className="h-5 w-5" />
                    )}
                  </div>

                  <div className="flex-1 min-w-0">
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <h3 className="text-base font-bold text-text-primary truncate">
                          {!account.isPoolAccount && account.groupName && (
                            <span className="text-text-secondary font-normal text-sm mr-1">
                              {account.groupName.trim().toLowerCase().startsWith("group")
                                ? formatDisplayText(account.groupName)
                                : `Group ${formatDisplayText(account.groupName)}`}{" "}
                              •
                            </span>
                          )}
                          {formatAccountName(account.name)}
                        </h3>
                        {account.isPoolAccount && (
                          <p className="text-[10px] font-bold text-text-secondary tracking-wider mt-0.5">
                            Workforce Pool Inside Plantilla
                          </p>
                        )}
                      </div>

                      <div className="shrink-0 flex items-center gap-1.5">
                        {account.isPoolAccount ? (
                          <span className="inline-flex items-center rounded-full bg-surface-muted border border-border-default px-2 py-0.5 text-xs font-semibold text-text-primary">
                            Pool
                          </span>
                        ) : (
                          account.required > 0 && account.fillRate < 80 && (
                            <span className="inline-flex items-center rounded-full bg-surface-muted border border-border-default px-2 py-0.5 text-xs font-semibold text-text-secondary">
                              Warning
                            </span>
                          )
                        )}

                        {/* Three-dot context menu */}
                        <div className="relative">
                          <button
                            type="button"
                            onClick={(e) => {
                              e.stopPropagation();
                              setActiveMenuAccountId((prev) =>
                                prev === account.id ? null : account.id,
                              );
                            }}
                            className="p-1 rounded-md text-text-muted hover:text-text-primary hover:bg-surface-hover transition cursor-pointer"
                            title="Account Actions"
                            aria-label="Account actions menu"
                          >
                            <MoreVertical className="h-4 w-4" />
                          </button>

                          {activeMenuAccountId === account.id && (
                            <div
                              onClick={(e) => e.stopPropagation()}
                              className="absolute right-0 top-full mt-1 w-44 rounded-xl border border-border-default bg-surface-base p-1.5 shadow-lg z-30 animate-fade-in"
                            >
                              <button
                                type="button"
                                onClick={() => {
                                  setActiveMenuAccountId(null);
                                  onAbsorbClick({ id: account.id, name: account.name });
                                }}
                                className="flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-xs font-medium text-text-primary hover:bg-surface-hover transition cursor-pointer"
                              >
                                <ArrowRightLeft className="h-3.5 w-3.5 text-brand-600 shrink-0" />
                                <span>Absorb Employees</span>
                              </button>
                              {canTransferGroup && (
                                <button
                                  type="button"
                                  onClick={() => {
                                    setActiveMenuAccountId(null);
                                    onTransferGroupClick?.(account);
                                  }}
                                  className="flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-xs font-medium text-text-primary hover:bg-surface-hover transition cursor-pointer"
                                >
                                  <GitFork className="h-3.5 w-3.5 text-brand-600 shrink-0" />
                                  <span>Transfer Group</span>
                                </button>
                              )}
                              <button
                                type="button"
                                onClick={() => {
                                  setActiveMenuAccountId(null);
                                  onArchiveClick({
                                    id: account.id,
                                    name: account.name,
                                    actual: account.actual,
                                    vacant: account.vacant,
                                    required: account.required,
                                    groupName: account.groupName,
                                  });
                                }}
                                className="flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-xs font-medium text-danger-text hover:bg-danger-bg/40 transition cursor-pointer"
                              >
                                <Archive className="h-3.5 w-3.5 text-danger-text shrink-0" />
                                <span>Archive Account</span>
                              </button>
                            </div>
                          )}
                        </div>
                      </div>
                    </div>

                    <div className="mt-2.5 text-xs text-text-secondary flex flex-wrap items-center gap-x-2 gap-y-1">
                      <span>
                        HC <strong className="text-text-primary font-bold">{account.actual}</strong>/
                        <strong className="text-text-primary font-bold">{account.required}</strong>
                      </span>
                      <span className="text-text-secondary/40">•</span>
                      <span>
                        Vacant <strong className="text-text-primary font-bold">{account.vacant}</strong>
                      </span>
                      {!account.isPoolAccount && (
                        <>
                          <span className="text-text-secondary/40">•</span>
                          <span>
                            Pipeline <strong className="text-text-primary font-bold">{account.hrProcess}</strong>
                          </span>
                        </>
                      )}
                      {account.leave > 0 && (
                        <>
                          <span className="text-text-secondary/40">•</span>
                          <span>
                            Leave <strong className="text-text-primary font-bold">{account.leave}</strong>
                          </span>
                        </>
                      )}
                    </div>

                    {!account.isPoolAccount && (
                      <div className="mt-3.5 flex items-center gap-3">
                        <span className="text-[10px] font-bold text-text-secondary shrink-0 w-8">
                          MFR
                        </span>
                        <div
                          className={`relative flex-1 h-2 rounded-full overflow-hidden ${
                            account.required > 0 ? colors.track : "bg-surface-muted border border-border-subtle/50"
                          }`}
                        >
                          {account.required > 0 && (
                            <div
                              className={`absolute left-0 top-0 h-full rounded-full transition-all duration-500 ${colors.bar}`}
                              style={{ width: `${Math.min(100, account.fillRate)}%` }}
                            />
                          )}
                        </div>
                        <span
                          className={`text-xs font-semibold shrink-0 text-right font-mono ${
                            account.required > 0 ? colors.text : "text-text-muted"
                          }`}
                        >
                          {account.required > 0
                            ? account.fillRate >= 100
                              ? "100%"
                              : account.actual < account.required && account.fillRate >= 99.95
                              ? "99.9%"
                              : `${(account.fillRate % 1 === 0 ? account.fillRate : account.fillRate.toFixed(2))}%`
                            : "—"}
                        </span>
                      </div>
                    )}
                  </div>
                </div>
              );
            });
          })()}
        </div>
      )}
    </div>
  );
}
