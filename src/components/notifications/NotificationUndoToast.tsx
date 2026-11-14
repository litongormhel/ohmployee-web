"use client";

import { useEffect, useState } from "react";
import { RotateCcw, X } from "lucide-react";

export interface NotificationUndoToastProps {
  message: string;
  onUndo: () => void;
  onDismiss: () => void;
  durationMs?: number;
}

export function NotificationUndoToast({
  message,
  onUndo,
  onDismiss,
  durationMs = 5000,
}: NotificationUndoToastProps) {
  const [secondsLeft, setSecondsLeft] = useState(Math.ceil(durationMs / 1000));

  useEffect(() => {
    const timer = setInterval(() => {
      setSecondsLeft((prev) => {
        if (prev <= 1) {
          clearInterval(timer);
          onDismiss();
          return 0;
        }
        return prev - 1;
      });
    }, 1000);

    return () => clearInterval(timer);
  }, [durationMs, onDismiss]);

  return (
    <div
      role="status"
      aria-live="polite"
      className="fixed bottom-6 right-6 z-50 flex items-center gap-3 rounded-xl border border-border-default bg-surface-base px-4 py-3 shadow-xl animate-fade-in backdrop-blur-md"
    >
      <div className="flex items-center gap-2">
        <span className="h-2 w-2 rounded-full bg-emerald-500 animate-pulse" />
        <span className="text-xs font-medium text-text-primary">
          {message}
        </span>
        <span className="text-[11px] text-text-muted">
          ({secondsLeft}s)
        </span>
      </div>

      <div className="flex items-center gap-2 border-l border-border-subtle pl-2.5">
        <button
          type="button"
          onClick={onUndo}
          className="inline-flex h-7 items-center gap-1 rounded-md bg-brand-50 border border-brand-200 px-2.5 text-xs font-semibold text-brand-700 hover:bg-brand-100 dark:bg-brand-950/40 dark:border-brand-800 dark:text-brand-300 transition cursor-pointer"
        >
          <RotateCcw className="h-3 w-3" />
          <span>Undo</span>
        </button>

        <button
          type="button"
          onClick={onDismiss}
          title="Dismiss notice"
          className="inline-flex h-6 w-6 items-center justify-center rounded-md text-text-muted hover:text-text-primary transition cursor-pointer"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      </div>
    </div>
  );
}
