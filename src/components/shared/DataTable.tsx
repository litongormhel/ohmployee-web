"use client";

import type { ReactNode } from "react";
import { useMotionLevel } from "@/hooks/useMotionLevel";

export type TableDensity = "compact" | "comfortable";

export interface Column<T> {
  key: string;
  header: string;
  render?: (row: T, index: number) => ReactNode;
  align?: "left" | "center" | "right";
  isNumeric?: boolean;
  className?: string;
  width?: string;
}

export interface DataTableProps<T> {
  columns: Column<T>[];
  data: T[];
  density?: TableDensity;
  rowKey: (row: T, index: number) => string;
  onRowClick?: (row: T) => void;
  selectedRowKey?: string;
  emptyState?: ReactNode;
  stickyHeader?: boolean;
  className?: string;
}

export function DataTable<T>({
  columns,
  data,
  density = "compact",
  rowKey,
  onRowClick,
  selectedRowKey,
  emptyState,
  stickyHeader = true,
  className = "",
}: DataTableProps<T>) {
  const motionLevel = useMotionLevel();

  // Density padding floors: font size is STRICTLY minimum 14px (text-sm)
  // Compact density reduces padding only!
  const cellPadding =
    density === "compact"
      ? "px-2.5 py-1.5" // compact padding
      : "px-4 py-2.5";   // comfortable padding

  if (data.length === 0 && emptyState) {
    return <div className="w-full">{emptyState}</div>;
  }

  return (
    <div
      className={`relative w-full overflow-x-auto rounded-xl border border-table-rule bg-surface-card ${
        motionLevel === "full" ? "animate-fade-in" : ""
      } ${className}`}
    >
      <table className="w-full min-w-full border-collapse text-left text-sm text-table-text">
        <thead
          className={`border-b border-table-rule-section bg-table-header text-xs font-semibold text-text-secondary ${
            stickyHeader ? "sticky top-0 z-10" : ""
          }`}
        >
          <tr>
            {columns.map((col) => {
              const alignClass =
                col.align === "right" || col.isNumeric
                  ? "text-right"
                  : col.align === "center"
                  ? "text-center"
                  : "text-left";

              return (
                <th
                  key={col.key}
                  scope="col"
                  style={{ width: col.width }}
                  className={`${cellPadding} ${alignClass} font-semibold uppercase tracking-wider text-[11px] text-text-muted ${col.className ?? ""}`}
                >
                  {col.header}
                </th>
              );
            })}
          </tr>
        </thead>
        <tbody className="divide-y divide-table-rule bg-table-row">
          {data.map((row, index) => {
            const id = rowKey(row, index);
            const isSelected = selectedRowKey === id;
            const isClickable = Boolean(onRowClick);

            return (
              <tr
                key={id}
                onClick={() => onRowClick?.(row)}
                className={`transition-colors duration-100 ${
                  isSelected
                    ? "bg-table-row-selected font-medium"
                    : isClickable
                    ? "hover:bg-table-row-hover cursor-pointer"
                    : ""
                }`}
              >
                {columns.map((col) => {
                  const alignClass =
                    col.align === "right" || col.isNumeric
                      ? "text-right tabular-nums"
                      : col.align === "center"
                      ? "text-center"
                      : "text-left";

                  const renderedContent = col.render
                    ? col.render(row, index)
                    : (row as Record<string, unknown>)[col.key] as ReactNode;

                  return (
                    <td
                      key={col.key}
                      className={`${cellPadding} ${alignClass} text-sm ${col.className ?? ""}`}
                    >
                      {renderedContent}
                    </td>
                  );
                })}
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
