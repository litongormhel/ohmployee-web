import type { HTMLAttributes, ReactNode } from "react";
import { Badge } from "@/components/ui/badge";

export type BadgeVariant = "info" | "success" | "warning" | "danger" | "neutral";

export interface StatusBadgeProps extends HTMLAttributes<HTMLSpanElement> {
  variant: BadgeVariant;
  text?: string;
  children?: ReactNode;
}

const variantClasses: Record<BadgeVariant, string> = {
  success:
    "border-status-success-border bg-status-success-bg text-status-success-text",
  warning:
    "border-status-warning-border bg-status-warning-bg text-status-warning-text",
  danger:
    "border-status-danger-border bg-status-danger-bg text-status-danger-text",
  info: "border-status-info-border bg-status-info-bg text-status-info-text",
  neutral:
    "border-status-neutral-border bg-status-neutral-bg text-status-neutral-text",
};

export function StatusBadge({
  variant,
  text,
  children,
  className = "",
  ...props
}: StatusBadgeProps) {
  const variantStyles = variantClasses[variant] || variantClasses.neutral;

  return (
    <Badge className={`${variantStyles} ${className}`} {...props}>
      {text ?? children}
    </Badge>
  );
}
