"use client";

import { memo } from "react";
import { AlertCircle, RotateCcw } from "lucide-react";

export interface InlineErrorProps {
  message: string;
  title?: string;
  onRetry?: () => void;
  className?: string;
}

export const InlineError = memo(function InlineError({
  message,
  title = "Unable to load data",
  onRetry,
  className = "",
}: InlineErrorProps) {
  return (
    <div
      role="alert"
      className={`flex items-start gap-3 rounded-xl border border-pct-bad-border bg-pct-bad-bg p-4 text-xs ${className}`}
    >
      <AlertCircle className="h-5 w-5 shrink-0 text-pct-bad-text mt-0.5" />
      <div className="flex-1 min-w-0">
        <h4 className="font-semibold text-pct-bad-text">{title}</h4>
        <p className="mt-0.5 text-text-secondary leading-relaxed">{message}</p>
        {onRetry && (
          <button
            type="button"
            onClick={onRetry}
            className="mt-2 inline-flex items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2.5 py-1 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover cursor-pointer"
          >
            <RotateCcw className="h-3.5 w-3.5" />
            <span>Try Again</span>
          </button>
        )}
      </div>
    </div>
  );
});
