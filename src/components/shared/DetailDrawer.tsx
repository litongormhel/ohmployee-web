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
  widthClass = "w-[460px]",
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
        className="fixed inset-0 z-40 bg-black/40 backdrop-blur-xs transition-opacity duration-300"
        onClick={onClose}
        aria-hidden="true"
      />

      {/* Slide-in drawer */}
      <aside
        className={`fixed top-0 right-0 z-50 flex h-full ${widthClass} transform flex-col border-l border-gray-200 bg-white shadow-2xl transition-transform duration-300 translate-x-0`}
        role="dialog"
        aria-modal="true"
      >
        {/* Drawer Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-5 py-4">
          <div className="min-w-0 flex-1">
            {badge && <div className="mb-1">{badge}</div>}
            <div className="text-base font-bold text-gray-900 truncate">
              {title}
            </div>
            {subtitle && (
              <div className="mt-1.5 flex items-center gap-1 text-[11px] text-gray-500">
                {subtitle}
              </div>
            )}
          </div>
          <div className="ml-4 flex items-center gap-2">
            {actionSlot}
            <button
              aria-label="Close details"
              className="rounded-md p-1.5 text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition-colors"
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
