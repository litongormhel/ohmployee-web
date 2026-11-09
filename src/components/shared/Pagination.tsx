"use client";

import { useMemo, useCallback, useState } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";

export interface PaginationProps {
  page: number;
  limit?: number;
  pageSize?: number;
  totalCount: number;
  limitOptions?: number[];
  pageSizeOptions?: number[];
  onPageChange: (newPage: number) => void;
  onLimitChange?: (newLimit: number) => void;
  onPageSizeChange?: (newPageSize: number) => void;
  isLoading?: boolean;
  className?: string;
  showLimitSelector?: boolean;
  showRangeLabel?: boolean;
}

export function Pagination({
  page,
  limit,
  pageSize,
  totalCount,
  limitOptions,
  pageSizeOptions,
  onPageChange,
  onLimitChange,
  onPageSizeChange,
  isLoading = false,
  className = "",
  showLimitSelector = true,
  showRangeLabel = true,
}: PaginationProps) {
  const effectiveLimit = limit ?? pageSize ?? 10;
  const effectiveOptions = limitOptions ?? pageSizeOptions ?? [10, 25, 50];
  const effectiveOnLimitChange = onLimitChange ?? onPageSizeChange;

  const pageCount = Math.max(1, Math.ceil(totalCount / effectiveLimit));
  const firstRecord = totalCount === 0 ? 0 : (page - 1) * effectiveLimit + 1;
  const lastRecord = Math.min(totalCount, page * effectiveLimit);

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
    <nav
      aria-label="Pagination Navigation"
      className={`flex flex-wrap items-center justify-between gap-3 border-t border-table-rule-section px-4 py-3 text-xs sm:text-sm text-table-text-muted ${className}`}
    >
      {/* Left side: Range information and Rows per page */}
      <div className="flex flex-wrap items-center gap-3">
        {showRangeLabel && (
          <span>
            Showing <span className="font-semibold text-table-text">{firstRecord}</span>–
            <span className="font-semibold text-table-text">{lastRecord}</span> of{" "}
            <span className="font-semibold text-table-text">{totalCount.toLocaleString()}</span> records
          </span>
        )}

        {showLimitSelector && effectiveOnLimitChange && (
          <div className="flex items-center gap-1.5 text-xs text-table-text-muted">
            <span>Rows per page:</span>
            <select
              value={effectiveLimit}
              onChange={(e) => effectiveOnLimitChange(Number(e.target.value))}
              disabled={isLoading}
              className="h-7 rounded-md border border-table-rule-section bg-table-row px-2 text-xs font-medium text-table-text focus:outline-hidden focus:ring-1 focus:ring-brand-500 cursor-pointer disabled:opacity-50"
              aria-label="Select rows per page"
            >
              {effectiveOptions.map((opt) => (
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
    </nav>
  );
}

/**
 * Standard reusable hook for managing pagination state across client-side or API-driven queries.
 */
export interface UsePaginationOptions {
  initialPage?: number;
  initialLimit?: number;
  totalCount?: number;
}

export function usePagination({
  initialPage = 1,
  initialLimit = 10,
  totalCount = 0,
}: UsePaginationOptions = {}) {
  const [page, setPageState] = useState<number>(initialPage);
  const [limit, setLimitState] = useState<number>(initialLimit);

  const totalPages = Math.max(1, Math.ceil(totalCount / limit));
  const safePage = totalCount > 0 ? Math.min(Math.max(1, page), totalPages) : Math.max(1, page);

  const handlePageChange = useCallback((newPage: number) => {
    setPageState(Math.max(1, newPage));
  }, []);

  const handleLimitChange = useCallback((newLimit: number) => {
    setLimitState(newLimit);
    setPageState(1); // Reset to first page on page size change
  }, []);

  const resetPage = useCallback(() => {
    setPageState(1);
  }, []);

  const offset = (safePage - 1) * limit;

  const paginate = useCallback(
    <T,>(items: T[]): T[] => {
      const start = (safePage - 1) * limit;
      return items.slice(start, start + limit);
    },
    [safePage, limit],
  );

  return {
    page: safePage,
    limit,
    pageSize: limit,
    offset,
    totalPages,
    setPage: setPageState,
    setLimit: setLimitState,
    handlePageChange,
    handleLimitChange,
    resetPage,
    paginate,
    paginationParams: {
      page: safePage,
      limit,
      offset,
    },
  };
}
