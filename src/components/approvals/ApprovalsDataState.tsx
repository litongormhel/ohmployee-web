export type ApprovalsDataStateKind = "loading" | "empty" | "access_denied" | "error";

export interface ApprovalsDataStateProps {
  kind: ApprovalsDataStateKind;
  title?: string;
  description?: string;
  onRetry?: () => void;
}

export function ApprovalsDataState({
  kind,
  title,
  description,
  onRetry,
}: ApprovalsDataStateProps) {
  switch (kind) {
    case "loading": {
      return (
        <div className="flex flex-col items-center justify-center py-14 px-4 text-center">
          <b className="text-sm font-medium text-[var(--text)]">
            {title ?? "Loading queue data..."}
          </b>
          <p className="mt-1 text-xs text-[var(--muted)] max-w-sm leading-relaxed">
            {description ?? "Please wait while records are fetched."}
          </p>
        </div>
      );
    }

    case "access_denied": {
      return (
        <div className="flex flex-col items-center justify-center py-14 px-4 text-center">
          <b className="text-sm font-medium text-[var(--bad)]">
            {title ?? "Access Denied"}
          </b>
          <p className="mt-1 text-xs text-[var(--muted)] max-w-md leading-relaxed">
            {description ??
              "Supabase RLS policies blocked this read. You are not authorized to view rows outside your scoped boundary."}
          </p>
        </div>
      );
    }

    case "error": {
      return (
        <div className="flex flex-col items-center justify-center py-14 px-4 text-center">
          <b className="text-sm font-medium text-[var(--bad)]">
            {title ?? "Fetch Failed"}
          </b>
          <p className="mt-1 text-xs text-[var(--muted)] max-w-md leading-relaxed">
            {description ??
              "The query request failed. You can retry without changing filters."}
          </p>
          {onRetry && (
            <button
              className="mt-3 inline-flex h-8 items-center gap-2 rounded-[9px] border border-[var(--line)] bg-transparent px-3 text-xs font-medium text-[var(--text)] hover:border-[var(--text)] transition cursor-pointer"
              onClick={onRetry}
              type="button"
            >
              Retry
            </button>
          )}
        </div>
      );
    }

    case "empty": {
      return (
        <div className="flex flex-col items-center justify-center py-14 px-4 text-center">
          <b className="text-sm font-medium text-[var(--text)]">
            {title ?? "Nothing waiting on you"}
          </b>
          <p className="mt-1 text-xs text-[var(--muted)] max-w-sm leading-relaxed">
            {description ?? "New requests will appear here."}
          </p>
        </div>
      );
    }

    default:
      return null;
  }
}
