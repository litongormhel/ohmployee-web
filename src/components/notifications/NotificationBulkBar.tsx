"use client";

import { Check, Mail, X } from "lucide-react";

export interface NotificationBulkBarProps {
  selectedCount: number;
  onMarkRead: () => void;
  onMarkUnread: () => void;
  onClear: () => void;
  isPending?: boolean;
}

export function NotificationBulkBar({
  selectedCount,
  onMarkRead,
  onMarkUnread,
  onClear,
  isPending = false,
}: NotificationBulkBarProps) {
  if (selectedCount === 0) return null;

  return (
    <div
      role="region"
      aria-label="Bulk actions toolbar"
      className="fixed bottom-6 left-1/2 -translate-x-1/2 z-50 flex items-center gap-3 rounded-xl border border-border-default bg-surface-base px-4 py-2.5 shadow-lg animate-fade-in backdrop-blur-md"
    >
      <div className="flex items-center gap-2 border-r border-border-subtle pr-3">
        <span className="inline-flex h-5 min-w-5 items-center justify-center rounded-full bg-brand-600 px-1.5 text-xs font-bold text-white tabular-nums">
          {selectedCount}
        </span>
        <span className="text-xs font-semibold text-text-primary">
          selected
        </span>
      </div>

      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={onMarkRead}
          disabled={isPending}
          className="inline-flex h-8 items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 text-xs font-medium text-text-primary hover:bg-surface-hover hover:border-border-strong transition cursor-pointer disabled:opacity-50"
        >
          <Check className="h-3.5 w-3.5 text-emerald-600" />
          <span>Mark as read</span>
        </button>

        <button
          type="button"
          onClick={onMarkUnread}
          disabled={isPending}
          className="inline-flex h-8 items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 text-xs font-medium text-text-primary hover:bg-surface-hover hover:border-border-strong transition cursor-pointer disabled:opacity-50"
        >
          <Mail className="h-3.5 w-3.5 text-text-muted" />
          <span>Mark as unread</span>
        </button>

        <button
          type="button"
          onClick={onClear}
          title="Clear selection"
          className="inline-flex h-8 w-8 items-center justify-center rounded-lg border border-transparent text-text-muted hover:bg-surface-hover hover:text-text-primary transition cursor-pointer"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
}
