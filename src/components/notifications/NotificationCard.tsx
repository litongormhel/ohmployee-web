"use client";

import { BellOff, RotateCcw } from "lucide-react";
import type { NotificationItem } from "@/lib/queries/notifications";
import { NotificationRow, type NotificationRowProps } from "@/components/notifications/NotificationRow";

// ============================================================================
// Relative Timestamp Formatter (Re-exported for backwards compatibility)
// ============================================================================

export function formatRelativeTime(dateString: string | null | undefined): string {
  if (!dateString) return "";
  const date = new Date(dateString);
  if (isNaN(date.getTime())) return "";

  const now = new Date();
  const diffInSeconds = Math.floor((now.getTime() - date.getTime()) / 1000);

  if (diffInSeconds < 0 || diffInSeconds < 60) {
    return "Just now";
  }

  const diffInMinutes = Math.floor(diffInSeconds / 60);
  if (diffInMinutes < 60) {
    return `${diffInMinutes}m ago`;
  }

  const diffInHours = Math.floor(diffInMinutes / 60);
  if (diffInHours < 24) {
    return `${diffInHours}h ago`;
  }

  const diffInDays = Math.floor(diffInHours / 24);
  if (diffInDays < 7) {
    return `${diffInDays}d ago`;
  }

  return date.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

// ============================================================================
// NotificationCard: High-Fidelity Row Adapter
// ============================================================================

export interface NotificationCardProps extends NotificationRowProps {
  notification: NotificationItem;
}

export function NotificationCard(props: NotificationCardProps) {
  return <NotificationRow {...props} />;
}

// ============================================================================
// NotificationEmptyState: State Boundary with Reset Filters Action
// ============================================================================

export interface NotificationEmptyStateProps {
  tab: string;
  hasActiveFilters?: boolean;
  onResetFilters?: () => void;
}

export function NotificationEmptyState({
  tab,
  hasActiveFilters = false,
  onResetFilters,
}: NotificationEmptyStateProps) {
  const getMessage = () => {
    if (hasActiveFilters) {
      return {
        title: "No matching notifications",
        desc: "No notifications match your current filter, module, or search criteria.",
      };
    }

    switch (tab) {
      case "unread":
        return {
          title: "All caught up!",
          desc: "You have zero unread notifications in your activity center.",
        };
      case "requests":
        return {
          title: "No request notices",
          desc: "Headcount, store, and workforce request alerts will appear here.",
        };
      case "alerts":
        return {
          title: "No active SLA alerts",
          desc: "All operational milestones and aging thresholds are currently healthy.",
        };
      case "system":
        return {
          title: "No system notices",
          desc: "General activity, batch corrections, and audit announcements will show here.",
        };
      case "all":
      default:
        return {
          title: "No notifications",
          desc: "There are currently no operational alerts or activity notices logged.",
        };
    }
  };

  const info = getMessage();

  return (
    <div className="flex flex-col items-center justify-center rounded-xl border border-dashed border-border-default bg-surface-base/50 p-12 text-center">
      <div className="flex h-12 w-12 items-center justify-center rounded-full bg-surface-muted text-text-muted">
        <BellOff className="h-6 w-6" aria-hidden="true" />
      </div>
      <h3 className="mt-3 text-sm font-bold text-text-primary">{info.title}</h3>
      <p className="mt-1 text-xs text-text-muted max-w-sm leading-relaxed">
        {info.desc}
      </p>

      {hasActiveFilters && onResetFilters && (
        <button
          type="button"
          onClick={onResetFilters}
          className="mt-4 inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-primary hover:bg-surface-hover hover:border-border-strong transition cursor-pointer"
        >
          <RotateCcw className="h-3 w-3 text-text-muted" />
          <span>Reset all filters</span>
        </button>
      )}
    </div>
  );
}
