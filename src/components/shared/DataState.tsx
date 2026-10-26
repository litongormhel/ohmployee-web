import { AlertCircle, ClipboardList, LockKeyhole, RefreshCw } from "lucide-react";

export type DataStateKind = "loading" | "empty" | "access_denied" | "error";

export interface DataStateProps {
  kind?: DataStateKind;
  state?: DataStateKind;
  title?: string;
  description?: string;
  message?: string;
  onRetry?: () => void;
}

export function DataState({ kind, state, title, description, message, onRetry }: DataStateProps) {
  const activeKind = kind ?? state ?? "loading";
  const activeDesc = description ?? message;

  switch (activeKind) {
    case "loading": {
      return (
        <div className="flex flex-col items-center justify-center p-8 text-center">
          <RefreshCw
            className="h-6 w-6 animate-spin text-[var(--primary)]"
            aria-hidden="true"
          />
          <h3 className="mt-3 text-sm font-semibold text-[var(--foreground)]">
            {title ?? "Loading scoped vacancies"}
          </h3>
          <p className="mt-1 text-xs text-[var(--text-muted)] max-w-sm leading-relaxed">
            {activeDesc ?? "Fetching queue data through Supabase RPCs."}
          </p>
        </div>
      );
    }

    case "access_denied": {
      return (
        <div className="flex flex-col items-center justify-center p-8 text-center">
          <div className="rounded-full bg-[var(--danger-bg)] p-3 text-[var(--danger)] shadow-xs border border-[var(--danger-border)]">
            <LockKeyhole className="h-6 w-6" aria-hidden="true" />
          </div>
          <h3 className="mt-3 text-sm font-semibold text-[var(--foreground)]">
            {title ?? "Access Denied"}
          </h3>
          <p className="mt-1 text-xs text-[var(--text-muted)] max-w-md leading-relaxed">
            {activeDesc ?? "Supabase RLS policies blocked this read. You are not authorized to view rows outside your scoped boundary."}
          </p>
        </div>
      );
    }

    case "error": {
      return (
        <div className="flex flex-col items-center justify-center p-8 text-center">
          <div className="rounded-full bg-[var(--danger-bg)] p-3 text-[var(--danger)] shadow-xs border border-[var(--danger-border)]">
            <AlertCircle className="h-6 w-6" aria-hidden="true" />
          </div>
          <h3 className="mt-3 text-sm font-semibold text-[var(--foreground)]">
            {title ?? "Fetch Failed"}
          </h3>
          <p className="mt-1 text-xs text-[var(--text-muted)] max-w-md leading-relaxed">
            {activeDesc ?? "The query request failed. You can retry without changing filters."}
          </p>
          {onRetry && (
            <button
              className="mt-4 inline-flex h-8 items-center gap-2 rounded-md border border-[var(--border-subtle)] bg-[var(--card)] px-3 text-xs font-semibold text-[var(--foreground)] shadow-xs hover:bg-[var(--surface-muted)] transition-colors"
              onClick={onRetry}
              type="button"
            >
              <RefreshCw className="h-3.5 w-3.5" aria-hidden="true" />
              Retry Query
            </button>
          )}
        </div>
      );
    }

    case "empty": {
      return (
        <div className="flex flex-col items-center justify-center p-8 text-center">
          <div className="rounded-md border border-[var(--border-subtle)] bg-[var(--surface-muted)] p-2.5 shadow-xs">
            <ClipboardList className="h-6 w-6 text-[var(--text-muted)]" aria-hidden="true" />
          </div>
          <h3 className="mt-3 text-sm font-semibold text-[var(--foreground)]">
            {title ?? "No records found"}
          </h3>
          <p className="mt-1 text-xs text-[var(--text-muted)] max-w-sm leading-relaxed">
            {activeDesc ?? "The backend returned an empty scoped result for this selection."}
          </p>
        </div>
      );
    }

    default:
      return null;
  }
}
