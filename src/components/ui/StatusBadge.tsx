import type { HTMLAttributes, ReactNode } from "react";
import { Badge } from "@/components/ui/badge";

export type BadgeVariant = "info" | "success" | "warning" | "danger" | "neutral";

export interface StatusBadgeProps extends HTMLAttributes<HTMLSpanElement> {
  variant: BadgeVariant;
  text?: string;
  children?: ReactNode;
}

const variantClasses: Record<BadgeVariant, string> = {
  success: "border-green-200 bg-green-50 text-green-700",
  warning: "border-amber-200 bg-amber-50 text-amber-700",
  danger: "border-red-200 bg-red-50 text-red-700",
  info: "border-blue-200 bg-blue-50 text-blue-700",
  neutral: "border-gray-200 bg-gray-50 text-gray-500",
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
