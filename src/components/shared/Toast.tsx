"use client";

import { memo } from "react";
import { Check, AlertCircle, Info, X } from "lucide-react";

export type ToastVariant = "success" | "warning" | "danger" | "info";

export interface ToastProps {
  isOpen?: boolean;
  message: string;
  variant?: ToastVariant;
  onClose?: () => void;
  className?: string;
}

export const Toast = memo(function Toast({
  isOpen = true,
  message,
  variant = "success",
  onClose,
  className = "",
}: ToastProps) {
  if (!isOpen) return null;

  const config = {
    success: {
      icon: Check,
      border: "border-pct-good-border",
      bg: "bg-pct-good-bg",
      text: "text-pct-good-text",
    },
    warning: {
      icon: AlertCircle,
      border: "border-pct-warn-border",
      bg: "bg-pct-warn-bg",
      text: "text-pct-warn-text",
    },
    danger: {
      icon: AlertCircle,
      border: "border-danger-border",
      bg: "bg-danger-bg",
      text: "text-danger-text",
    },
    info: {
      icon: Info,
      border: "border-brand-200 dark:border-brand-500/30",
      bg: "bg-brand-50 dark:bg-brand-500/15",
      text: "text-brand-700 dark:text-brand-300",
    },
  }[variant];

  const Icon = config.icon;

  return (
    <div
      role="status"
      aria-live="polite"
      className={`fixed bottom-6 right-6 z-[100] flex items-center gap-2.5 rounded-xl border ${config.border} ${config.bg} px-4 py-3 text-xs font-semibold ${config.text} shadow-lg animate-fade-in ${className}`}
    >
      <Icon className="h-4 w-4 shrink-0" />
      <span>{message}</span>
      {onClose && (
        <button
          type="button"
          onClick={onClose}
          aria-label="Dismiss toast"
          className="ml-2 rounded p-0.5 hover:opacity-75 cursor-pointer"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      )}
    </div>
  );
});
