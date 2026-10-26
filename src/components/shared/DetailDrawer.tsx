"use client";

import type { ReactNode } from "react";
import { useEffect } from "react";
import { X } from "lucide-react";
import { useMotionLevel } from "@/hooks/useMotionLevel";

export interface DetailDrawerProps {
  isOpen: boolean;
  onClose: () => void;
  title: string | ReactNode;
  subtitle?: string | ReactNode;
  badge?: ReactNode;
  actionSlot?: ReactNode;
  children: ReactNode;
  widthClass?: string; // e.g. "w-full sm:w-[460px]" or custom responsive overrides
  footer?: ReactNode;
  contentClassName?: string;
  footerClassName?: string;
  disableBackdropClick?: boolean;
  isSubmitting?: boolean;
  isDirty?: boolean;
}

export function DetailDrawer({
  isOpen,
  onClose,
  title,
  subtitle,
  badge,
  actionSlot,
  children,
  widthClass = "w-full sm:w-[var(--drawer-width-md)] max-w-full",
  footer,
  contentClassName = "p-5 space-y-5",
  footerClassName = "px-5 py-3",
  disableBackdropClick = false,
  isSubmitting = false,
  isDirty = false,
}: DetailDrawerProps) {
  const motionLevel = useMotionLevel();

  const handleDismiss = () => {
    if (isSubmitting) return;
    if (isDirty && !window.confirm("You have unsaved changes. Discard?")) return;
    onClose();
  };

  // ESC key handler
  useEffect(() => {
    if (!isOpen) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        if (isSubmitting) return;
        if (isDirty && !window.confirm("You have unsaved changes. Discard?")) return;
        onClose();
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, onClose, isSubmitting, isDirty]);

  // Body Scroll Lock
  useEffect(() => {
    if (!isOpen) return;
    const originalOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = originalOverflow;
    };
  }, [isOpen]);

  if (!isOpen) return null;

  return (
    <>
      {/* Backdrop overlay (flat translucent color, no blur) */}
      <div
        className="fixed inset-0 z-40 bg-surface-overlay animate-fade-in"
        onClick={disableBackdropClick ? undefined : handleDismiss}
        aria-hidden="true"
      />

      {/* Slide-in drawer */}
      <aside
        className={`fixed top-0 right-0 z-50 flex h-full ${widthClass} flex-col border-l border-border-default bg-surface-base shadow-2xl ${
          motionLevel === "full"
            ? "animate-drawer-in"
            : motionLevel === "lite"
            ? "animate-fade-in"
            : ""
        }`}
        role="dialog"
        aria-modal="true"
        aria-label={typeof title === "string" ? title : "Details panel"}
      >
        {/* Drawer Header */}
        <div className="flex items-center justify-between border-b border-border-subtle px-5 py-4 shrink-0">
          <div className="min-w-0 flex-1">
            {badge && <div className="mb-1">{badge}</div>}
            <div className="text-base font-bold text-text-primary truncate">
              {title}
            </div>
            {subtitle && (
              <div className="mt-1.5 flex items-center gap-1 text-[11px] text-text-secondary">
                {subtitle}
              </div>
            )}
          </div>
          <div className="ml-4 flex items-center gap-2">
            {actionSlot}
            <button
              aria-label="Close details"
              className="rounded-md p-1.5 text-text-muted hover:bg-surface-muted hover:text-text-secondary transition-colors disabled:opacity-40"
              onClick={handleDismiss}
              disabled={isSubmitting}
              type="button"
            >
              <X className="h-5 w-5" aria-hidden="true" />
            </button>
          </div>
        </div>

        {/* Scrollable Content */}
        <div className={`flex-1 overflow-y-auto ${contentClassName}`}>
          {children}
        </div>

        {/* Drawer Footer */}
        {footer && (
          <div className={`border-t border-border-subtle bg-surface-base shrink-0 ${footerClassName}`}>
            {footer}
          </div>
        )}
      </aside>
    </>
  );
}
