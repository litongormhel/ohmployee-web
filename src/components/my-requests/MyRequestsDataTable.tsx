"use client";

import {
  AlertCircle,
  Building2,
  Calendar,
  CheckCircle2,
  Clock,
  XCircle,
} from "lucide-react";
import type { MyRequestItem, MyRequestStatus } from "@/lib/queries/my_requests";

interface MyRequestsDataTableProps {
  requests: MyRequestItem[];
  onViewDetails: (item: MyRequestItem) => void;
}

function formatRelativeTime(dateString: string): string {
  try {
    const date = new Date(dateString);
    if (isNaN(date.getTime())) return "—";
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffSec = Math.floor(diffMs / 1000);
    const diffMin = Math.floor(diffSec / 60);
    const diffHours = Math.floor(diffMin / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffDays > 30) {
      return date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
    }
    if (diffDays > 0) return `${diffDays}d ago`;
    if (diffHours > 0) return `${diffHours}h ago`;
    if (diffMin > 0) return `${diffMin}m ago`;
    return "just now";
  } catch {
    return "—";
  }
}

function formatSubmittedDate(dateString: string): { date: string; time: string } {
  try {
    const d = new Date(dateString);
    if (isNaN(d.getTime())) return { date: "—", time: "" };
    const date = d.toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
    });
    const time = d.toLocaleTimeString("en-US", {
      hour: "numeric",
      minute: "2-digit",
      hour12: true,
    });
    return { date, time };
  } catch {
    return { date: dateString, time: "" };
  }
}

function getCategoryBadgeColor(category: MyRequestItem["category"]): string {
  switch (category) {
    case "headcount":
      return "bg-purple-50 text-purple-700 border-purple-200 dark:bg-purple-950/40 dark:text-purple-300 dark:border-purple-800";
    case "new_stores":
      return "bg-blue-50 text-blue-700 border-blue-200 dark:bg-blue-950/40 dark:text-blue-300 dark:border-blue-800";
    case "vacancy_closures":
      return "bg-amber-50 text-amber-700 border-amber-200 dark:bg-amber-950/40 dark:text-amber-300 dark:border-amber-800";
    case "deactivations":
      return "bg-rose-50 text-rose-700 border-rose-200 dark:bg-rose-950/40 dark:text-rose-300 dark:border-rose-800";
    case "applicant_movements":
      return "bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-950/40 dark:text-emerald-300 dark:border-emerald-800";
    case "coverage":
      return "bg-cyan-50 text-cyan-700 border-cyan-200 dark:bg-cyan-950/40 dark:text-cyan-300 dark:border-cyan-800";
    default:
      return "bg-slate-50 text-slate-700 border-slate-200 dark:bg-slate-800 dark:text-slate-300 dark:border-slate-700";
  }
}

function getStatusBadge(status: MyRequestStatus) {
  switch (status) {
    case "pending":
      return (
        <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-semibold bg-amber-500/10 text-amber-600 dark:text-amber-400 border border-amber-500/20 whitespace-nowrap">
          <Clock size={11} className="animate-spin text-amber-500 shrink-0" />
          Pending Review
        </span>
      );
    case "approved":
      return (
        <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-semibold bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20 whitespace-nowrap">
          <CheckCircle2 size={11} className="shrink-0" />
          Approved
        </span>
      );
    case "rejected":
      return (
        <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-semibold bg-rose-500/10 text-rose-600 dark:text-rose-400 border border-rose-500/20 whitespace-nowrap">
          <XCircle size={11} className="shrink-0" />
          Rejected
        </span>
      );
    case "cancelled":
      return (
        <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-semibold bg-slate-500/10 text-slate-600 dark:text-slate-400 border border-slate-500/20 whitespace-nowrap">
          <AlertCircle size={11} className="shrink-0" />
          Cancelled
        </span>
      );
  }
}

export function MyRequestsDataTable({
  requests,
  onViewDetails,
}: MyRequestsDataTableProps) {
  return (
    <div className="w-full overflow-hidden rounded-xl border border-[var(--line)] bg-[var(--card)] shadow-xs">
      <div className="overflow-x-auto">
        <table className="w-full min-w-[880px] border-collapse text-left text-xs">
          <thead>
            <tr className="border-b border-[var(--line)] bg-[var(--soft)]/75 text-[11px] font-semibold uppercase tracking-wider text-[var(--muted)]">
              <th scope="col" className="px-4 py-3 whitespace-nowrap w-[130px]">
                Type
              </th>
              <th scope="col" className="px-4 py-3 whitespace-nowrap min-w-[240px]">
                Request Subject
              </th>
              <th scope="col" className="px-4 py-3 whitespace-nowrap min-w-[200px]">
                Account & Store
              </th>
              <th scope="col" className="px-4 py-3 whitespace-nowrap min-w-[220px]">
                Stated Justification
              </th>
              <th scope="col" className="px-4 py-3 whitespace-nowrap w-[130px]">
                Submitted
              </th>
              <th scope="col" className="px-4 py-3 whitespace-nowrap min-w-[180px]">
                Status & Milestone
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--line)]">
            {requests.map((item) => {
              const { date, time } = formatSubmittedDate(item.createdAt);
              const relativeTime = formatRelativeTime(item.createdAt);

              return (
                <tr
                  key={item.id}
                  onClick={() => onViewDetails(item)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault();
                      onViewDetails(item);
                    }
                  }}
                  tabIndex={0}
                  className="group transition-colors hover:bg-[var(--soft)]/60 cursor-pointer focus:bg-[var(--soft)]/80 focus:outline-hidden"
                >
                  {/* Column 1: Type / Category */}
                  <td className="px-4 py-3 align-top whitespace-nowrap">
                    <div className="space-y-1">
                      <span
                        className={`inline-flex items-center px-2 py-0.5 rounded-md text-[11px] font-semibold border ${getCategoryBadgeColor(
                          item.category
                        )}`}
                      >
                        {item.categoryLabel}
                      </span>
                      <div className="text-[10px] text-[var(--muted)] font-mono">
                        {relativeTime}
                      </div>
                    </div>
                  </td>

                  {/* Column 2: Subject / Title / Context (Clean & Non-Redundant) */}
                  <td className="px-4 py-3 align-top">
                    <div className="space-y-1">
                      <div className="font-semibold text-[13px] text-[var(--text)] group-hover:text-brand-500 transition-colors leading-snug">
                        {item.title}
                      </div>
                      {item.subtitle && (
                        <div className="text-xs text-[var(--muted)] font-mono">
                          {item.subtitle}
                        </div>
                      )}
                    </div>
                  </td>

                  {/* Column 3: Account & Store */}
                  <td className="px-4 py-3 align-top">
                    <div className="space-y-1">
                      <div className="text-xs font-semibold text-[var(--text)] line-clamp-1">
                        {item.details.accountName || "—"}
                      </div>
                      <div className="flex items-center gap-1.5 text-xs text-[var(--muted)]">
                        <Building2 size={12} className="text-brand-500 shrink-0" />
                        <span className="line-clamp-1">
                          {item.details.storeName || "—"}
                        </span>
                      </div>
                    </div>
                  </td>

                  {/* Column 4: Stated Justification */}
                  <td className="px-4 py-3 align-top max-w-[260px]">
                    {item.details.reason ? (
                      <p
                        className="text-xs text-[var(--text)] italic leading-relaxed line-clamp-2"
                        title={item.details.reason}
                      >
                        &ldquo;{item.details.reason}&rdquo;
                      </p>
                    ) : (
                      <span className="text-[var(--muted)] italic text-2xs">
                        No stated reason
                      </span>
                    )}
                  </td>

                  {/* Column 5: Submitted Date */}
                  <td className="px-4 py-3 align-top whitespace-nowrap">
                    <div className="space-y-0.5">
                      <div className="flex items-center gap-1 text-xs font-medium text-[var(--text)]">
                        <Calendar size={11} className="text-[var(--muted)] shrink-0" />
                        <span>{date}</span>
                      </div>
                      <div className="text-[11px] font-mono text-[var(--muted)] pl-3.5">
                        {time}
                      </div>
                    </div>
                  </td>

                  {/* Column 6: Status & Milestone */}
                  <td className="px-4 py-3 align-top">
                    <div className="space-y-1">
                      <div>{getStatusBadge(item.status)}</div>

                      {item.status === "pending" && (
                        <div className="text-[11px] text-amber-600/90 dark:text-amber-400/90 font-medium line-clamp-1">
                          Awaiting approver review
                        </div>
                      )}

                      {item.status === "approved" && (
                        <div className="text-[11px] text-emerald-700 dark:text-emerald-400 line-clamp-1">
                          Cleared {item.reviewedByName ? `by ${item.reviewedByName}` : ""}
                        </div>
                      )}

                      {item.status === "rejected" && (
                        <div className="text-[11px] text-rose-600 dark:text-rose-400 line-clamp-1">
                          {item.reviewerRemarks
                            ? `Note: ${item.reviewerRemarks}`
                            : item.reviewedByName
                            ? `Declined by ${item.reviewedByName}`
                            : "Declined by approver"}
                        </div>
                      )}
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
