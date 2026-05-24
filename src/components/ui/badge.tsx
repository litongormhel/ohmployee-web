import type { HTMLAttributes } from "react";

type BadgeProps = HTMLAttributes<HTMLSpanElement>;

export function Badge({ className = "", ...props }: BadgeProps) {
  return (
    <span
      className={`inline-flex items-center rounded-md border border-border-default bg-surface-muted px-2 py-0.5 text-xs font-medium text-text-secondary ${className}`}
      {...props}
    />
  );
}
