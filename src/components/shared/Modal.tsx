"use client";

import { useEffect, useRef, type ReactNode } from "react";
import { X } from "lucide-react";
import { useMotionLevel } from "@/hooks/useMotionLevel";

export interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  title: string | ReactNode;
  subtitle?: string | ReactNode;
  icon?: React.ComponentType<{ className?: string }>;
  children: ReactNode;
  footer?: ReactNode;
  maxWidthClass?: string; // default "max-w-lg"
  className?: string;
  ariaDescribedBy?: string;
  isSubmitting?: boolean;
  disableBackdropClick?: boolean;
  isDirty?: boolean;
}

export function Modal({
  isOpen,
  onClose,
  title,
  subtitle,
  icon: Icon,
  children,
  footer,
  maxWidthClass = "max-w-lg",
  className = "",
  ariaDescribedBy,
  isSubmitting = false,
  disableBackdropClick = false,
  isDirty = false,
}: ModalProps) {
  const motionLevel = useMotionLevel();
  const dialogRef = useRef<HTMLDivElement>(null);

  // ESC key handler
  useEffect(() => {
    if (!isOpen) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        if (isSubmitting) return;
        if (isDirty) return; // Prevent accidental loss of unsaved input on Esc
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

  // Focus trap / initial focus
  useEffect(() => {
    if (isOpen && dialogRef.current) {
      const focusable = dialogRef.current.querySelectorAll<HTMLElement>(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
      );
      if (focusable.length > 0) {
        focusable[0].focus();
      }
    }
  }, [isOpen]);

  if (!isOpen) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={typeof title === "string" ? title : undefined}
      aria-describedby={ariaDescribedBy}
      className="fixed inset-0 z-[60] flex items-end sm:items-center justify-center p-0 sm:p-4"
    >
      {/* Flat translucent backdrop (No blur for performance and crisp legibility) */}
      <div
        className="fixed inset-0 bg-surface-overlay transition-opacity"
        onClick={() => {
          if (isSubmitting || disableBackdropClick) return;
          onClose();
        }}
        aria-hidden="true"
      />

      {/* Modal / Bottom sheet container */}
      <div
        ref={dialogRef}
        className={`relative z-10 flex flex-col w-full ${maxWidthClass} max-h-[90vh] sm:max-h-[85vh] rounded-t-2xl sm:rounded-2xl border border-border-default bg-surface-base shadow-xl overflow-hidden ${
          motionLevel === "full"
            ? "animate-[modalIn_180ms_cubic-bezier(0.16,1,0.3,1)_forwards]"
            : motionLevel === "lite"
            ? "animate-fade-in"
            : ""
        } ${className}`}
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border-subtle px-5 py-4 bg-surface-card shrink-0">
          <div className="flex items-center gap-3 min-w-0">
            {Icon && (
              <div className="flex h-9 w-9 items-center justify-center rounded-lg border border-border-subtle bg-surface-muted text-text-primary shrink-0">
                <Icon className="h-4 w-4" />
              </div>
            )}
            <div className="min-w-0">
              <h2 className="text-base font-semibold text-text-primary truncate">
                {title}
              </h2>
              {subtitle && (
                <p className="mt-0.5 text-xs text-text-secondary truncate">
                  {subtitle}
                </p>
              )}
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={isSubmitting}
            aria-label="Close dialog"
            className="ml-3 rounded-lg p-1.5 text-text-muted hover:bg-surface-hover hover:text-text-primary transition-colors cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Content Body */}
        <div className="flex-1 overflow-y-auto p-5 text-sm text-text-primary">
          {children}
        </div>

        {/* Footer Actions */}
        {footer && (
          <div className="border-t border-border-subtle px-5 py-3.5 bg-surface-card flex items-center justify-end gap-2.5 shrink-0">
            {footer}
          </div>
        )}
      </div>
    </div>
  );
}
