"use client";

import Link from "next/link";
import {
  AlertCircle,
  Bell,
  BellOff,
  Check,
  CheckCircle2,
  Clock,
  Mail,
} from "lucide-react";
import type { ComponentType } from "react";
import {
  parseNotificationDeepLink,
  type NotificationItem,
} from "@/lib/queries/notifications";
import { formatDisplayText } from "@/lib/utils/displayText";

// ============================================================================
// Relative Timestamp Formatter
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
// Visual Severity & Tone Categorization
// ============================================================================

interface ToneConfig {
  icon: ComponentType<{ className?: string }>;
  containerClass: string;
  badgeClass: string;
  badgeLabel: string;
}

function resolveNotificationTone(item: NotificationItem): ToneConfig {
  const type = (item.notification_type || "").toLowerCase();
  const event = (item.event_type || "").toLowerCase();
  const title = (item.title || "").toLowerCase();

  // 1. Danger / Rejections / Urgent
  if (
    type.includes("reject") ||
    event.includes("reject") ||
    title.includes("reject") ||
    type.includes("escalat") ||
    event.includes("escalat") ||
    event.includes("breach") ||
    title.includes("breach") ||
    title.includes("incident") ||
    event.includes("delet") ||
    title.includes("deletion")
  ) {
    return {
      icon: AlertCircle,
      containerClass: "bg-surface-subtle text-danger-text border border-border-default",
      badgeClass: "bg-surface-subtle text-danger-text border-border-default",
      badgeLabel: item.sla_level ? `SLA Breach (L${item.sla_level})` : "Attention Required",
    };
  }

  // 2. Success / Approved / Finalized
  if (
    (type.includes("approv") ||
      event.includes("approv") ||
      title.includes("approv") ||
      title.includes("created") ||
      event.includes("completed") ||
      title.includes("completed") ||
      type.includes("success")) &&
    !event.includes("required") &&
    !title.includes("needed") &&
    !title.includes("request")
  ) {
    return {
      icon: CheckCircle2,
      containerClass: "bg-surface-subtle text-text-primary border border-border-default ring-2 ring-border-default/20",
      badgeClass: "bg-surface-subtle text-text-primary border-border-default",
      badgeLabel: "Approved",
    };
  }

  // 3. Warning / SLA / Submissions / Pending Action
  if (
    (item.sla_level !== null && item.sla_level !== undefined && item.sla_level > 0) ||
    event.includes("sla") ||
    title.includes("sla") ||
    type.includes("submit") ||
    event.includes("submit") ||
    title.includes("request") ||
    title.includes("pending") ||
    title.includes("needed") ||
    event.includes("approval_required") ||
    title.includes("closure")
  ) {
    return {
      icon: Clock,
      containerClass: "bg-surface-subtle text-text-secondary border border-border-default ring-2 ring-border-default/20",
      badgeClass: "bg-surface-subtle text-text-secondary border-border-default",
      badgeLabel: item.sla_level ? `SLA Alert (L${item.sla_level})` : "Pending Action",
    };
  }

  // 4. Info / System Default
  return {
    icon: Bell,
    containerClass: "bg-surface-subtle text-text-secondary border border-border-default ring-2 ring-border-default/20",
    badgeClass: "bg-surface-subtle text-text-secondary border-border-default",
    badgeLabel: "Notice",
  };
}

// ============================================================================
// Notification Card Component
// ============================================================================

export interface NotificationCardProps {
  notification: NotificationItem;
  onToggleRead: (item: NotificationItem) => void;
  isToggling?: boolean;
}

export function NotificationCard({
  notification,
  onToggleRead,
  isToggling = false,
}: NotificationCardProps) {
  const tone = resolveNotificationTone(notification);
  const ToneIcon = tone.icon;
  const deepLink = parseNotificationDeepLink(notification);
  const formattedTime = formatRelativeTime(notification.created_at);
  const fullDateTime = notification.created_at
    ? new Date(notification.created_at).toLocaleString()
    : "";

  return (
    <article
      className={`group relative flex flex-col sm:flex-row sm:items-start gap-3.5 rounded-xl border p-4 transition duration-150 ${
        !notification.is_read
          ? "border-border-default bg-surface-base shadow-xs"
          : "border-border-subtle bg-surface-base/60 hover:bg-surface-base hover:border-border-default"
      }`}
    >
      {/* Unread Accent Pill Indicator */}
      {!notification.is_read && (
        <span
          className="absolute left-0 top-3 h-7 w-1 rounded-r-md bg-brand-500"
          aria-label="Unread notification indicator"
        />
      )}

      {/* Avatar Icon Container with Tone Tinting */}
      <div
        className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-full transition-transform group-hover:scale-105 ${tone.containerClass}`}
        aria-hidden="true"
      >
        <ToneIcon className="h-4.5 w-4.5" />
      </div>

      {/* Center Details Column */}
      <div className="flex-1 min-w-0">
        <div className="flex flex-wrap items-center justify-between gap-2">
          {/* Headline Title */}
          <div className="flex items-center gap-2 min-w-0">
            <h3
              className={`text-sm truncate ${
                !notification.is_read
                  ? "font-bold text-text-primary"
                  : "font-semibold text-text-secondary"
              }`}
            >
              {formatDisplayText(notification.title)}
            </h3>

            {/* Categorical Badge */}
            <span
              className={`inline-flex items-center rounded-md border px-1.5 py-0.5 text-[10px] font-semibold tracking-tight ${tone.badgeClass}`}
            >
              {tone.badgeLabel}
            </span>
          </div>

          {/* Timestamp */}
          <time
            dateTime={notification.created_at}
            title={fullDateTime}
            className="shrink-0 text-xs text-text-muted font-medium whitespace-nowrap"
          >
            {formattedTime}
          </time>
        </div>

        {/* Message Summary Text */}
        <p className="mt-1 text-xs text-text-secondary leading-relaxed sm:pr-8">
          {notification.message}
        </p>

        {/* Actionable Deep Link & Controls */}
        <div className="mt-3 flex flex-wrap items-center justify-between gap-3 pt-1 border-t border-border-subtle/60">
          {deepLink ? (
            <Link
              href={deepLink.route}
              className="inline-flex items-center gap-1 text-xs font-semibold text-brand-600 hover:text-brand-700 hover:underline transition"
            >
              <span>{deepLink.label}</span>
            </Link>
          ) : (
            <div />
          )}

          {/* Toggle Read/Unread Action Button */}
          <button
            type="button"
            onClick={() => onToggleRead(notification)}
            disabled={isToggling}
            title={notification.is_read ? "Mark as unread" : "Mark as read"}
            className="inline-flex h-7 items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-secondary hover:border-border-strong hover:bg-surface-hover hover:text-text-primary transition cursor-pointer disabled:opacity-50"
          >
            {notification.is_read ? (
              <>
                <Mail className="h-3 w-3 text-text-muted" aria-hidden="true" />
                <span>Mark unread</span>
              </>
            ) : (
              <>
                <Check className="h-3 w-3 text-pct-high" aria-hidden="true" />
                <span>Mark read</span>
              </>
            )}
          </button>
        </div>
      </div>
    </article>
  );
}

// ============================================================================
// Empty State Component
// ============================================================================

export interface NotificationEmptyStateProps {
  tab: string;
}

export function NotificationEmptyState({ tab }: NotificationEmptyStateProps) {
  const getMessage = () => {
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
    </div>
  );
}
