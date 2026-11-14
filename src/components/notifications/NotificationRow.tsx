"use client";

import Link from "next/link";
import { useState } from "react";
import { Check, Mail, ExternalLink, Copy } from "lucide-react";
import type { NotificationItem } from "@/lib/queries/notifications";
import { formatRelativeTime } from "@/components/notifications/NotificationCard";
import {
  resolveNotificationPresentation,
  type NotificationPresentation,
} from "@/lib/notifications/severity";
import { formatDisplayText } from "@/lib/utils/displayText";

export interface NotificationRowProps {
  notification: NotificationItem;
  isSelected?: boolean;
  onToggleSelect?: (id: string) => void;
  onToggleRead: (item: NotificationItem) => void;
  onNavigate?: (item: NotificationItem) => void;
  isToggling?: boolean;
}

export function NotificationRow({
  notification,
  isSelected = false,
  onToggleSelect,
  onToggleRead,
  onNavigate,
  isToggling = false,
}: NotificationRowProps) {
  const [copied, setCopied] = useState(false);
  const p: NotificationPresentation = resolveNotificationPresentation(notification);
  const Icon = p.icon;
  const relativeTime = formatRelativeTime(notification.created_at);
  const fullDateTime = notification.created_at
    ? new Date(notification.created_at).toLocaleString("en-US", {
        dateStyle: "medium",
        timeStyle: "short",
      })
    : "";

  const handleCopyCode = (e: React.MouseEvent, code: string) => {
    e.stopPropagation();
    e.preventDefault();
    navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  const handleCtaClick = () => {
    if (!notification.is_read) {
      onToggleRead(notification);
    }
    if (onNavigate) {
      onNavigate(notification);
    }
  };

  return (
    <div
      role="row"
      className={`group relative flex items-center justify-between gap-3 px-3 py-2.5 rounded-lg border transition-all text-xs ${
        !notification.is_read
          ? "border-border-default bg-brand-50/25 dark:bg-brand-950/15 shadow-2xs"
          : "border-border-subtle/80 bg-surface-base hover:border-border-default hover:bg-surface-hover/70"
      } ${isSelected ? "ring-2 ring-brand-500/30 border-brand-500 bg-brand-50/40" : ""}`}
    >
      {/* Left: Checkbox + Unread Indicator + Icon + Main Content */}
      <div className="flex items-center gap-2.5 min-w-0 flex-1">
        {/* Selection Checkbox */}
        {onToggleSelect && (
          <label className="flex items-center cursor-pointer shrink-0" onClick={(e) => e.stopPropagation()}>
            <input
              type="checkbox"
              checked={isSelected}
              onChange={() => onToggleSelect(notification.id)}
              className="h-3.5 w-3.5 rounded border-border-default text-brand-600 focus:ring-brand-500/30 cursor-pointer"
              aria-label={`Select notification: ${notification.title}`}
            />
          </label>
        )}

        {/* Unread Accent Dot */}
        <div className="w-2 flex justify-center shrink-0">
          {!notification.is_read ? (
            <span
              className={`h-2 w-2 rounded-full ${p.dotClass}`}
              title="Unread notification"
            />
          ) : (
            <span className="h-2 w-2" />
          )}
        </div>

        {/* Severity Icon Pill */}
        <div
          className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-md border ${p.containerClass}`}
          title={`${p.moduleLabel} • ${p.statusLabel}`}
        >
          <Icon className="h-3.5 w-3.5" />
        </div>

        {/* Content Stream (Title, Status Chip, Message, Entity Code, Actor) */}
        <div className="flex flex-col sm:flex-row sm:items-center gap-1 sm:gap-2.5 min-w-0 flex-1">
          {/* Title & Status Badge */}
          <div className="flex items-center gap-1.5 shrink-0">
            <span
              className={`truncate max-w-[220px] sm:max-w-[280px] ${
                !notification.is_read
                  ? "font-bold text-text-primary"
                  : "font-medium text-text-secondary"
              }`}
              title={notification.title}
            >
              {formatDisplayText(notification.title)}
            </span>

            {/* Status Chip */}
            <span
              className={`inline-flex items-center rounded px-1.5 py-0.5 text-[10px] font-semibold border ${p.badgeClass}`}
            >
              {p.statusLabel}
            </span>
          </div>

          {/* Single-line Message */}
          <p
            className="truncate text-text-muted text-[11px] min-w-0 flex-1"
            title={notification.message}
          >
            {notification.message}
          </p>

          {/* Metadata Badges: Entity Code & Actor */}
          <div className="flex items-center gap-1.5 shrink-0">
            {p.entityCode && (
              <button
                type="button"
                onClick={(e) => handleCopyCode(e, p.entityCode!)}
                title={copied ? "Copied!" : `Copy code: ${p.entityCode}`}
                className="inline-flex items-center gap-1 font-mono text-[10px] font-semibold bg-mono-pill-surface text-mono-pill-ink border border-mono-pill-ring rounded px-1.5 py-0.5 hover:bg-surface-hover transition cursor-pointer"
              >
                <span>{p.entityCode}</span>
                <Copy className="h-2.5 w-2.5 text-text-muted" />
              </button>
            )}

            {p.actor && (
              <span
                className="text-[10px] text-text-muted truncate max-w-[90px] hidden md:inline"
                title={`By ${p.actor}`}
              >
                by {p.actor}
              </span>
            )}
          </div>
        </div>
      </div>

      {/* Right Controls: Timestamp + Inline CTA + Mark Read Button */}
      <div className="flex items-center gap-2.5 shrink-0">
        {/* Timestamp with Absolute Datetime on Hover */}
        <time
          dateTime={notification.created_at}
          title={fullDateTime}
          className="text-[11px] text-text-muted font-mono whitespace-nowrap cursor-help hidden sm:inline"
        >
          {relativeTime}
        </time>

        {/* Primary Inline CTA */}
        {p.deepLink ? (
          <Link
            href={p.deepLink.route}
            onClick={handleCtaClick}
            className="inline-flex items-center gap-1 text-[11px] font-semibold text-brand-600 hover:text-brand-700 hover:underline px-2 py-1 rounded bg-brand-50/50 dark:bg-brand-950/20 hover:bg-brand-100/50 transition whitespace-nowrap"
          >
            <span>{p.deepLink.label}</span>
            <ExternalLink className="h-3 w-3" />
          </Link>
        ) : null}

        {/* Quick Read/Unread Action Button */}
        <button
          type="button"
          onClick={() => onToggleRead(notification)}
          disabled={isToggling}
          title={notification.is_read ? "Mark as unread" : "Mark as read"}
          className="inline-flex h-7 w-7 items-center justify-center rounded-md border border-border-default bg-surface-base text-text-secondary hover:border-border-strong hover:bg-surface-hover hover:text-text-primary transition cursor-pointer disabled:opacity-50"
        >
          {notification.is_read ? (
            <Mail className="h-3.5 w-3.5 text-text-muted" />
          ) : (
            <Check className="h-3.5 w-3.5 text-emerald-600" />
          )}
        </button>
      </div>
    </div>
  );
}
