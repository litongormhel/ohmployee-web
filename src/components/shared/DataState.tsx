import { AlertCircle, ClipboardList, LockKeyhole, RefreshCw } from "lucide-react";

export type DataStateKind = "loading" | "empty" | "access_denied" | "error";

export interface DataStateProps {
  kind: DataStateKind;
  title?: string;
  description?: string;
  onRetry?: () => void;
}

export function DataState({ kind, title, description, onRetry }: DataStateProps) {
  switch (kind) {
    case "loading": {
      return (
        <div className="flex flex-col items-center justify-center p-8 text-center">
          <RefreshCw
            className="h-6 w-6 animate-spin text-brand-500"
            aria-hidden="true"
          />
          <h3 className="mt-3 text-sm font-semibold text-text-primary">
            {title ?? "Loading scoped vacancies"}
          </h3>
          <p className="mt-1 text-xs text-text-muted max-w-sm leading-relaxed">
            {description ?? "Fetching queue data through Supabase RPCs."}
          </p>
        </div>
      );
    }

    case "access_denied": {
      return (
        <div className="flex flex-col items-center justify-center p-8 text-center">
          <div className="rounded-full bg-red-50 p-3 text-red-600 shadow-xs border border-red-100">
            <LockKeyhole className="h-6 w-6" aria-hidden="true" />
          </div>
          <h3 className="mt-3 text-sm font-semibold text-text-primary">
            {title ?? "Access Denied"}
          </h3>
          <p className="mt-1 text-xs text-text-secondary max-w-md leading-relaxed">
            {description ?? "Supabase RLS policies blocked this read. You are not authorized to view rows outside your scoped boundary."}
          </p>
        </div>
      );
    }

    case "error": {
      return (
        <div className="flex flex-col items-center justify-center p-8 text-center">
          <div className="rounded-full bg-amber-50 p-3 text-amber-600 shadow-xs border border-amber-100">
            <AlertCircle className="h-6 w-6" aria-hidden="true" />
          </div>
          <h3 className="mt-3 text-sm font-semibold text-text-primary">
            {title ?? "Fetch Failed"}
          </h3>
          <p className="mt-1 text-xs text-text-secondary max-w-md leading-relaxed">
            {description ?? "The query request failed. You can retry without changing filters."}
          </p>
          {onRetry && (
            <button
              className="mt-4 inline-flex h-8 items-center gap-2 rounded-md border border-border-default bg-surface-base px-3 text-xs font-semibold text-text-secondary shadow-xs hover:bg-surface-hover transition-colors"
              onClick={onRetry}
              type="button"
            >
              <RefreshCw className="h-3.5 w-3.5 animate-duration-150" aria-hidden="true" />
              Retry Query
            </button>
          )}
        </div>
      );
    }

    case "empty": {
      return (
        <div className="flex flex-col items-center justify-center p-8 text-center">
          <div className="rounded-md border border-border-default bg-surface-muted p-2.5 shadow-xs">
            <ClipboardList className="h-6 w-6 text-text-muted" aria-hidden="true" />
          </div>
          <h3 className="mt-3 text-sm font-semibold text-text-primary">
            {title ?? "No records found"}
          </h3>
          <p className="mt-1 text-xs text-text-muted max-w-sm leading-relaxed">
            {description ?? "The backend returned an empty scoped result for this selection."}
          </p>
        </div>
      );
    }

    default:
      return null;
  }
}
