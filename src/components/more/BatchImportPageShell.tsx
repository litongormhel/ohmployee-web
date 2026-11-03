"use client";

import React, { type ComponentType, type ReactNode } from "react";
import { ArrowLeft } from "lucide-react";

export interface BatchImportPageShellProps {
  title: ReactNode;
  subtitle?: ReactNode;
  icon?: ComponentType<{ className?: string }>;
  onBack: () => void;
  children: ReactNode;
  footer?: ReactNode;
}

export function BatchImportPageShell({
  title,
  subtitle,
  icon: Icon,
  onBack,
  children,
  footer,
}: BatchImportPageShellProps) {
  return (
    <div className="flex flex-col min-h-[calc(100vh-6.5rem)] space-y-4">
      {/* Top Navigation & Header */}
      <div className="flex flex-col gap-3 pb-3 border-b border-border-subtle shrink-0">
        <div className="flex items-center">
          <button
            type="button"
            onClick={onBack}
            className="inline-flex items-center gap-1.5 text-xs font-semibold text-text-secondary hover:text-text-primary transition-colors cursor-pointer group py-1"
            aria-label="Back to Batch Imports"
          >
            <ArrowLeft className="w-3.5 h-3.5 transition-transform group-hover:-translate-x-0.5 text-text-muted group-hover:text-text-primary" />
            <span>← Back to Batch Imports</span>
          </button>
        </div>

        <div className="flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-3 min-w-0">
            {Icon && (
              <div className="w-9 h-9 rounded-xl bg-surface-subtle border border-border-default flex items-center justify-center shrink-0">
                <Icon className="w-4 h-4 text-brand-primary" />
              </div>
            )}
            <div className="min-w-0">
              <h1 className="text-lg font-bold text-text-primary tracking-tight leading-tight flex items-center gap-2 flex-wrap">
                {title}
              </h1>
              {subtitle && (
                <p className="text-xs text-text-secondary mt-0.5 leading-normal">
                  {subtitle}
                </p>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Main Content Area */}
      <div className="flex-1 flex flex-col space-y-4">
        {children}
      </div>

      {/* Sticky Bottom Actions Footer */}
      {footer && (
        <div className="sticky bottom-0 z-30 bg-surface-base/95 backdrop-blur-xs border-t border-border-default -mx-4 -mb-5 px-4 sm:-mx-5 sm:px-5 lg:-mx-6 lg:px-6 2xl:-mx-8 2xl:px-8 py-3.5 mt-auto shadow-xs">
          {footer}
        </div>
      )}
    </div>
  );
}
