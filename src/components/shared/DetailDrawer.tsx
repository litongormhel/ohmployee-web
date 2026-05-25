"use client";

import type { ReactNode } from "react";
import { useEffect } from "react";
import { X } from "lucide-react";

export interface DetailDrawerProps {
  isOpen: boolean;
  onClose: () => void;
  title: string | ReactNode;
  subtitle?: string | ReactNode;
  badge?: ReactNode;
  actionSlot?: ReactNode;
  children: ReactNode;
  widthClass?: string; // e.g. "w-[460px]" or custom responsive overrides
}

export function DetailDrawer({
  isOpen,
  onClose,
  title,
  subtitle,
  badge,
  actionSlot,
  children,
  widthClass = "w-[var(--drawer-width-md)] max-w-full",
}: DetailDrawerProps) {
  // ESC key handler
  useEffect(() => {
    if (!isOpen) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        onClose();
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, onClose]);

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
      {/* Backdrop overlay */}
      <div
        className="fixed inset-0 z-40 bg-[var(--surface-overlay)] backdrop-blur-xs animate-fade-in"
        onClick={onClose}
        aria-hidden="true"
      />

      {/* Slide-in drawer (animate-drawer-in plays on mount, fixing the
          mounting glitch where the panel previously appeared without sliding) */}
      <aside
        className={`fixed top-0 right-0 z-50 flex h-full ${widthClass} flex-col border-l border-border-default bg-surface-base shadow-2xl animate-drawer-in`}
        role="dialog"
        aria-modal="true"
        aria-label={typeof title === "string" ? title : "Details panel"}
      >
        {/* Drawer Header */}
        <div className="flex items-center justify-between border-b border-border-subtle px-5 py-4">
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
              className="rounded-md p-1.5 text-text-muted hover:bg-surface-muted hover:text-text-secondary transition-colors"
              onClick={onClose}
              type="button"
            >
              <X className="h-5 w-5" aria-hidden="true" />
            </button>
          </div>
        </div>

        {/* Scrollable Content */}
        <div className="flex-1 overflow-y-auto p-5 space-y-5">
          {children}
        </div>
      </aside>
    </>
  );
}
