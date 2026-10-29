/**
 * src/components/dashboard/RecentActivityFeed.tsx
 *
 * Recent Activity Feed widget for Executive Dashboard (Phase 2B-1).
 * Displays up to 8 latest operational events in the selected scope,
 * one compact line per entry, with relative timestamps right-aligned,
 * batched sample expansion, and SA-only "View all" link.
 */

"use client";

import React, { memo, useState } from "react";
import Link from "next/link";
import { History, ArrowRight, ChevronDown } from "lucide-react";
import { useRecentActivity, type RecentActivityItem } from "@/lib/queries/activity";
import {
  getActivityEventIcon,
  formatRecentActivitySentence,
} from "@/lib/utils/activity_formatter";

export interface RecentActivityFeedProps {
  groupId?: string | null;
  accountId?: string | null;
  isSuperAdmin?: boolean;
}

export function formatRelativeTime(dateString: string): string {
  const date = new Date(dateString);
  const now = new Date();
  const diffSec = Math.floor((now.getTime() - date.getTime()) / 1000);
  if (diffSec < 60) return "just now";
  const diffMin = Math.floor(diffSec / 60);
  if (diffMin < 60) return `${diffMin}m ago`;
  const diffHours = Math.floor(diffMin / 60);
  if (diffHours < 24) return `${diffHours}h ago`;
  const diffDays = Math.floor(diffHours / 24);
  if (diffDays === 1) return "yesterday";
  if (diffDays < 7) return `${diffDays}d ago`;
  return date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

export const RecentActivityFeed = memo(function RecentActivityFeed({
  groupId,
  accountId,
  isSuperAdmin = false,
}: RecentActivityFeedProps) {
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());

  const { data: activities = [], isLoading, isError } = useRecentActivity({
    groupId,
    accountId,
    limit: 8,
  });

  const toggleExpand = (id: string) => {
    setExpandedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  };

  return (
    <section
      aria-label="Recent activity feed"
      className="w-full rounded-2xl border border-border-default bg-surface-card p-4 sm:p-5 shadow-2xs"
    >
      {/* Header */}
      <div className="flex items-center justify-between pb-3 border-b border-border-subtle">
        <div className="flex items-center gap-2">
          <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-surface-muted text-text-primary">
            <History className="h-4 w-4" />
          </div>
          <div>
            <h3 className="text-sm font-semibold tracking-tight text-text-primary">
              Recent Activity
            </h3>
          </div>
        </div>

        {activities.length > 0 && (
          <span className="inline-flex items-center rounded-full bg-surface-muted px-2 py-0.5 text-[11px] font-semibold text-text-muted">
            {activities.length} latest
          </span>
        )}
      </div>

      {/* Content */}
      <div className="mt-2">
        {isLoading ? (
          <div className="py-6 text-center text-xs text-text-muted animate-pulse">
            Loading activity feed...
          </div>
        ) : isError ? (
          <div className="py-6 text-center text-xs text-rose-600">
            Failed to load recent activity.
          </div>
        ) : activities.length === 0 ? (
          <div className="py-6 text-center">
            <p className="text-xs font-medium text-text-muted">
              No recent activity in this scope.
            </p>
          </div>
        ) : (
          <ul className="divide-y divide-border-subtle">
            {activities.slice(0, 8).map((item: RecentActivityItem) => {
              const isExpanded = expandedIds.has(item.id);
              const hasSamples = item.batchCount > 1 && item.samples && item.samples.length > 0;

              return (
                <li key={item.id} className="py-2.5 first:pt-2 last:pb-1">
                  <div className="flex items-center justify-between gap-3 text-xs">
                    {/* Left: Icon + Compact formatted sentence + Optional expand button */}
                    <div className="flex items-center gap-2.5 min-w-0">
                      <div className="flex h-5 w-5 shrink-0 items-center justify-center rounded-md bg-surface-muted">
                        {getActivityEventIcon(item.eventType)}
                      </div>
                      <div className="truncate text-text-secondary">
                        {formatRecentActivitySentence(item)}
                      </div>
                      {hasSamples && (
                        <button
                          type="button"
                          onClick={() => toggleExpand(item.id)}
                          className="shrink-0 inline-flex items-center gap-0.5 rounded px-1.5 py-0.5 text-[10px] font-medium bg-surface-muted text-text-secondary hover:bg-surface-hover hover:text-text-primary transition-colors cursor-pointer"
                          title="Toggle sample subjects"
                        >
                          <span>
                            {isExpanded
                              ? "Hide"
                              : `${item.samples.length} sample${item.samples.length > 1 ? "s" : ""}`}
                          </span>
                          <ChevronDown
                            className={`h-3 w-3 transition-transform ${
                              isExpanded ? "rotate-180" : ""
                            }`}
                          />
                        </button>
                      )}
                    </div>

                    {/* Right: Relative time right-aligned */}
                    <div className="shrink-0 text-[11px] font-mono text-text-muted text-right">
                      {formatRelativeTime(item.timestamp)}
                    </div>
                  </div>

                  {/* Expandable Sample List */}
                  {hasSamples && isExpanded && (
                    <div className="mt-2 ml-7 pl-3 border-l-2 border-border-subtle py-1 space-y-1">
                      <div className="text-[10px] uppercase font-semibold text-text-muted tracking-wider">
                        Sample Subjects ({item.samples.length} of {item.batchCount}):
                      </div>
                      <div className="grid grid-cols-1 sm:grid-cols-3 gap-1 pt-0.5">
                        {item.samples.map((s, idx) => (
                          <div
                            key={idx}
                            className="text-xs text-text-secondary flex items-center gap-1 truncate"
                          >
                            <span className="font-medium text-text-primary truncate">
                              {s.name}
                            </span>
                            {s.employee_no && (
                              <span className="text-text-muted font-mono text-[10px] shrink-0">
                                [{s.employee_no}]
                              </span>
                            )}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </div>

      {/* Footer Link: Gated to Super Admin only per specification */}
      {isSuperAdmin && (
        <div className="mt-3 pt-3 border-t border-border-subtle flex justify-end">
          <Link
            href="/more?tab=audit_logs"
            className="inline-flex items-center gap-1 text-xs font-semibold text-brand-600 hover:text-brand-700 transition-colors"
          >
            <span>View all</span>
            <ArrowRight className="h-3 w-3" />
          </Link>
        </div>
      )}
    </section>
  );
});
