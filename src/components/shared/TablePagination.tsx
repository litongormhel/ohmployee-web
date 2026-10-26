"use client";

import { useMemo } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";

export type TablePaginationProps = {
  page: number;
  pageSize: number;
  totalCount: number;
  pageSizeOptions?: number[];
  onPageChange: (newPage: number) => void;
  onPageSizeChange?: (newPageSize: number) => void;
  isLoading?: boolean;
  className?: string;
};

export function TablePagination({
  page,
  pageSize,
  totalCount,
  pageSizeOptions = [10, 25, 50],
  onPageChange,
  onPageSizeChange,
  isLoading = false,
  className = "",
}: TablePaginationProps) {
  const pageCount = Math.max(1, Math.ceil(totalCount / pageSize));
  const firstRecord = totalCount === 0 ? 0 : (page - 1) * pageSize + 1;
  const lastRecord = Math.min(totalCount, page * pageSize);

  // Generate page numbers with ellipses when needed
  const pageNumbers = useMemo(() => {
    if (pageCount <= 5) {
      return Array.from({ length: pageCount }, (_, i) => i + 1);
    }

    const pages: (number | "...")[] = [];
    if (page <= 3) {
      pages.push(1, 2, 3, 4, "...", pageCount);
    } else if (page >= pageCount - 2) {
      pages.push(1, "...", pageCount - 3, pageCount - 2, pageCount - 1, pageCount);
    } else {
      pages.push(1, "...", page - 1, page, page + 1, "...", pageCount);
    }
    return pages;
  }, [page, pageCount]);

  return (
    <div
      className={`flex flex-wrap items-center justify-between gap-3 border-t border-table-rule-section px-4 py-3 text-xs sm:text-sm text-table-text-muted ${className}`}
    >
      {/* Left side: Showing X–Y of Z records + rows per page */}
      <div className="flex flex-wrap items-center gap-3">
        <span>
          Showing {firstRecord}–{lastRecord} of {totalCount.toLocaleString()} records
        </span>

        {onPageSizeChange && (
          <div className="flex items-center gap-1.5 text-xs text-table-text-muted">
            <span>Rows per page:</span>
            <select
              value={pageSize}
              onChange={(e) => onPageSizeChange(Number(e.target.value))}
              disabled={isLoading}
              className="h-7 rounded border border-table-rule-section bg-table-row px-2 text-xs font-medium text-table-text focus:outline-none focus:ring-1 focus:ring-brand-500 cursor-pointer disabled:opacity-50"
              aria-label="Select rows per page"
            >
              {pageSizeOptions.map((opt) => (
                <option key={opt} value={opt}>
                  {opt}
                </option>
              ))}
            </select>
          </div>
        )}
      </div>

      {/* Right side: Prev / Page Numbers / Next */}
      <div className="flex items-center gap-1 sm:gap-1.5">
        <button
          type="button"
          disabled={page <= 1 || isLoading}
          onClick={() => onPageChange(page - 1)}
          className="inline-flex h-8 items-center gap-1 rounded-md border border-table-rule-section bg-table-row px-2.5 text-xs font-medium text-table-text-sub shadow-2xs hover:bg-table-row-hover transition-colors disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
          aria-label="Previous page"
        >
          <ChevronLeft className="h-3.5 w-3.5" />
          <span className="hidden sm:inline">Prev</span>
        </button>

        <div className="flex items-center gap-1">
          {pageNumbers.map((item, idx) => {
            if (item === "...") {
              return (
                <span
                  key={`ellipsis-${idx}`}
                  className="px-1.5 py-1 text-xs text-table-text-muted select-none"
                >
                  ...
                </span>
              );
            }

            const isActive = item === page;
            return (
              <button
                key={item}
                type="button"
                disabled={isLoading}
                onClick={() => onPageChange(item)}
                className={`inline-flex h-8 min-w-[2rem] items-center justify-center rounded-md px-2 text-xs font-medium transition-colors cursor-pointer ${
                  isActive
                    ? "bg-brand-button text-white font-semibold shadow-2xs"
                    : "border border-table-rule-section bg-table-row text-table-text-sub hover:bg-table-row-hover"
                }`}
                aria-current={isActive ? "page" : undefined}
                aria-label={`Page ${item}`}
              >
                {item}
              </button>
            );
          })}
        </div>

        <button
          type="button"
          disabled={page >= pageCount || isLoading}
          onClick={() => onPageChange(page + 1)}
          className="inline-flex h-8 items-center gap-1 rounded-md border border-table-rule-section bg-table-row px-2.5 text-xs font-medium text-table-text-sub shadow-2xs hover:bg-table-row-hover transition-colors disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
          aria-label="Next page"
        >
          <span className="hidden sm:inline">Next</span>
          <ChevronRight className="h-3.5 w-3.5" />
        </button>
      </div>
    </div>
  );
}
