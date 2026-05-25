import { Badge } from "@/components/ui/badge";

export interface MetricCardProps {
  label: string;
  value: string | number | undefined;
  helperText?: string;
  helper?: string;
  isLoading?: boolean;
  loading?: boolean;
  isBlocked?: boolean;
  blocked?: boolean;
  badgeLabel?: string;
  badge?: string;
  isError?: boolean;
  error?: boolean;
  errorText?: string;
}

export function MetricCard({
  label,
  value,
  helperText,
  helper,
  isLoading,
  loading,
  isBlocked,
  blocked,
  badgeLabel,
  badge,
  isError,
  error,
  errorText,
}: MetricCardProps) {
  const displayHelper = helper ?? helperText;
  const isCurrentlyLoading = loading ?? isLoading;
  const isCurrentlyBlocked = blocked ?? isBlocked;
  const isCurrentlyError = error ?? isError;
  const displayBadge = badge ?? badgeLabel ?? (isCurrentlyBlocked ? "Blocked" : "RPC");

  return (
    <div className="rounded-md border border-border-default bg-surface-base px-4 py-3.5 shadow-sm transition-shadow duration-200 hover:shadow-md">
      <div className="text-xs font-semibold uppercase tracking-normal text-text-secondary">
        {label}
      </div>
      <div className="mt-1.5 flex items-end justify-between gap-3">
        <div className="text-3xl font-semibold leading-none text-text-primary">
          {isCurrentlyLoading ? "--" : value ?? 0}
        </div>
        <Badge
          className={
            isCurrentlyBlocked
              ? "border-status-danger-border bg-status-danger-bg text-status-danger-text"
              : "border-border-default bg-surface-muted text-text-muted"
          }
        >
          {displayBadge}
        </Badge>
      </div>
      <div className="mt-2 text-sm leading-5">
        {isCurrentlyError && !isCurrentlyBlocked ? (
          <span className="text-red-500">{errorText ?? "Retryable summary error"}</span>
        ) : (
          <span className="text-text-muted">{isCurrentlyLoading && !isCurrentlyBlocked ? "Loading..." : displayHelper}</span>
        )}
      </div>
    </div>
  );
}
