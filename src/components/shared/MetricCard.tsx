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
    <div className="rounded-md border border-gray-200 bg-white px-3 py-2.5 shadow-sm transition-shadow hover:shadow-md duration-200">
      <div className="text-xs font-medium uppercase tracking-wider text-gray-500">
        {label}
      </div>
      <div className="mt-1 flex items-end justify-between gap-3">
        <div className="text-2xl font-semibold text-gray-900">
          {isCurrentlyLoading ? "--" : value ?? 0}
        </div>
        <Badge
          className={
            isCurrentlyBlocked
              ? "border-red-200 bg-red-50 text-red-700"
              : "border-gray-200 bg-gray-50 text-gray-500"
          }
        >
          {displayBadge}
        </Badge>
      </div>
      <div className="mt-1 text-xs">
        {isCurrentlyError && !isCurrentlyBlocked ? (
          <span className="text-red-500">{errorText ?? "Retryable summary error"}</span>
        ) : (
          <span className="text-gray-400">{isCurrentlyLoading && !isCurrentlyBlocked ? "Loading..." : displayHelper}</span>
        )}
      </div>
    </div>
  );
}
