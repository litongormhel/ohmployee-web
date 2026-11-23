"use client";

import {
  AlertCircle,
  Building2,
  Calendar,
  CheckCircle2,
  Clock,
  FileText,
  Layers,
  MapPin,
  TrendingUp,
  User,
  Users,
  XCircle,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import type { MyRequestItem, MyRequestStatus } from "@/lib/queries/my_requests";

interface MyRequestDetailModalProps {
  isOpen: boolean;
  onClose: () => void;
  request: MyRequestItem | null;
}

function formatFullDate(dateString?: string | null): string {
  if (!dateString) return "—";
  try {
    const d = new Date(dateString);
    if (isNaN(d.getTime())) return "—";
    return d.toLocaleString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
      hour12: true,
    });
  } catch {
    return dateString;
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
        <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-amber-500/10 text-amber-600 dark:text-amber-400 border border-amber-500/20">
          <Clock size={12} className="animate-spin text-amber-500" />
          Pending Review
        </span>
      );
    case "approved":
      return (
        <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20">
          <CheckCircle2 size={12} />
          Approved
        </span>
      );
    case "rejected":
      return (
        <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-rose-500/10 text-rose-600 dark:text-rose-400 border border-rose-500/20">
          <XCircle size={12} />
          Rejected
        </span>
      );
    case "cancelled":
      return (
        <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-slate-500/10 text-slate-600 dark:text-slate-400 border border-slate-500/20">
          <AlertCircle size={12} />
          Cancelled
        </span>
      );
  }
}

export function MyRequestDetailModal({
  isOpen,
  onClose,
  request,
}: MyRequestDetailModalProps) {
  if (!request) return null;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      maxWidthClass="max-w-2xl"
      title={
        <div className="flex flex-wrap items-center gap-2">
          <span
            className={`inline-flex items-center px-2 py-0.5 rounded-md text-[11px] font-semibold border ${getCategoryBadgeColor(
              request.category
            )}`}
          >
            {request.categoryLabel}
          </span>
          <span className="text-sm font-semibold text-[var(--text)]">
            Request Details
          </span>
        </div>
      }
      subtitle={
        <span className="text-xs text-[var(--muted)]">
          ID: <code className="font-mono text-2xs">{request.id}</code>
        </span>
      }
      footer={
        <div className="flex items-center justify-end w-full">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-medium rounded-lg border border-[var(--line)] bg-[var(--soft)] hover:bg-[var(--card)] text-[var(--text)] transition cursor-pointer"
          >
            Close
          </button>
        </div>
      }
    >
      <div className="p-5 space-y-5">
        {/* Top Status & Title Banner */}
        <div className="p-4 rounded-xl border border-[var(--line)] bg-[var(--card)] space-y-2.5">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h3 className="text-base font-semibold text-[var(--text)] leading-snug">
              {request.title}
            </h3>
            {getStatusBadge(request.status)}
          </div>
          {request.subtitle && (
            <p className="text-xs text-[var(--muted)] leading-relaxed">
              {request.subtitle}
            </p>
          )}
        </div>

        {/* Operational Scope Grid */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs">
          {request.details.accountName && (
            <div className="p-3 rounded-lg border border-[var(--line)] bg-[var(--soft)]/40 flex items-start gap-2.5">
              <Layers size={14} className="text-purple-500 mt-0.5 shrink-0" />
              <div>
                <span className="text-[10px] uppercase font-bold tracking-wider text-[var(--muted)] block">
                  Account
                </span>
                <span className="font-medium text-[var(--text)]">
                  {request.details.accountName}
                </span>
              </div>
            </div>
          )}

          {request.details.storeName && (
            <div className="p-3 rounded-lg border border-[var(--line)] bg-[var(--soft)]/40 flex items-start gap-2.5">
              <Building2 size={14} className="text-brand-500 mt-0.5 shrink-0" />
              <div>
                <span className="text-[10px] uppercase font-bold tracking-wider text-[var(--muted)] block">
                  Store / Branch
                </span>
                <span className="font-medium text-[var(--text)]">
                  {request.details.storeName}
                </span>
              </div>
            </div>
          )}

          {request.details.vcode && (
            <div className="p-3 rounded-lg border border-[var(--line)] bg-[var(--soft)]/40 flex items-start gap-2.5">
              <FileText size={14} className="text-amber-500 mt-0.5 shrink-0" />
              <div>
                <span className="text-[10px] uppercase font-bold tracking-wider text-[var(--muted)] block">
                  Vacancy Code (VCode)
                </span>
                <span className="font-mono font-medium text-[var(--text)]">
                  {request.details.vcode}
                </span>
              </div>
            </div>
          )}

          {request.details.positionName && (
            <div className="p-3 rounded-lg border border-[var(--line)] bg-[var(--soft)]/40 flex items-start gap-2.5">
              <User size={14} className="text-blue-500 mt-0.5 shrink-0" />
              <div>
                <span className="text-[10px] uppercase font-bold tracking-wider text-[var(--muted)] block">
                  Target Position
                </span>
                <span className="font-medium text-[var(--text)]">
                  {request.details.positionName}
                </span>
              </div>
            </div>
          )}

          {request.details.employeeName && (
            <div className="p-3 rounded-lg border border-[var(--line)] bg-[var(--soft)]/40 flex items-start gap-2.5">
              <User size={14} className="text-emerald-500 mt-0.5 shrink-0" />
              <div>
                <span className="text-[10px] uppercase font-bold tracking-wider text-[var(--muted)] block">
                  Personnel / Employee
                </span>
                <span className="font-medium text-[var(--text)]">
                  {request.details.employeeName}{" "}
                  {request.details.employeeNo ? `(${request.details.employeeNo})` : ""}
                </span>
              </div>
            </div>
          )}

          {request.details.headcountNeeded !== undefined &&
            request.details.headcountNeeded !== null && (
              <div className="p-3 rounded-lg border border-[var(--line)] bg-[var(--soft)]/40 flex items-start gap-2.5">
                <Users size={14} className="text-emerald-500 mt-0.5 shrink-0" />
                <div>
                  <span className="text-[10px] uppercase font-bold tracking-wider text-[var(--muted)] block">
                    Headcount Needed
                  </span>
                  <span className="font-medium text-[var(--text)]">
                    {request.details.headcountNeeded} pax
                  </span>
                </div>
              </div>
            )}

          {request.details.proposedTarget !== undefined &&
            request.details.proposedTarget !== null && (
              <div className="p-3 rounded-lg border border-[var(--line)] bg-[var(--soft)]/40 flex items-start gap-2.5">
                <TrendingUp size={14} className="text-cyan-500 mt-0.5 shrink-0" />
                <div>
                  <span className="text-[10px] uppercase font-bold tracking-wider text-[var(--muted)] block">
                    Target Quota Change
                  </span>
                  <span className="font-medium text-[var(--text)]">
                    {request.details.previousTarget ?? "—"} →{" "}
                    {request.details.proposedTarget}
                  </span>
                </div>
              </div>
            )}

          {request.details.location && (
            <div className="p-3 rounded-lg border border-[var(--line)] bg-[var(--soft)]/40 flex items-start gap-2.5">
              <MapPin size={14} className="text-rose-500 mt-0.5 shrink-0" />
              <div>
                <span className="text-[10px] uppercase font-bold tracking-wider text-[var(--muted)] block">
                  Location
                </span>
                <span className="font-medium text-[var(--text)]">
                  {request.details.location}
                </span>
              </div>
            </div>
          )}
        </div>

        {/* Stated Justification */}
        {request.details.reason && (
          <div className="p-4 rounded-xl border border-[var(--line)] bg-[var(--soft)]/30 space-y-1.5">
            <span className="text-[10px] font-bold uppercase tracking-wider text-[var(--muted)] block">
              Stated Justification
            </span>
            <p className="text-xs text-[var(--text)] italic leading-relaxed whitespace-pre-wrap">
              &ldquo;{request.details.reason}&rdquo;
            </p>
          </div>
        )}

        {/* Milestone Review & Audit Section */}
        <div className="space-y-2">
          <span className="text-[10px] font-bold uppercase tracking-wider text-[var(--muted)] block">
            Approval Milestone & Review
          </span>

          {request.status === "pending" && (
            <div className="p-3.5 rounded-xl border border-amber-200/70 bg-amber-50/50 dark:bg-amber-950/20 dark:border-amber-900/40 flex items-start gap-3 text-xs text-amber-800 dark:text-amber-300">
              <Clock size={16} className="text-amber-600 dark:text-amber-400 shrink-0 mt-0.5 animate-spin" />
              <div>
                <div className="font-semibold">Awaiting Administrative Review</div>
                <p className="text-[11px] text-amber-700/90 dark:text-amber-400/90 mt-0.5">
                  Your request has been submitted and is queued for evaluation by designated operations administrators.
                </p>
              </div>
            </div>
          )}

          {request.status === "approved" && (
            <div className="p-3.5 rounded-xl border border-emerald-200 bg-emerald-50/70 dark:bg-emerald-950/30 dark:border-emerald-900/50 space-y-2 text-xs text-emerald-900 dark:text-emerald-200">
              <div className="flex items-center justify-between">
                <div className="font-semibold flex items-center gap-2">
                  <CheckCircle2 size={16} className="text-emerald-600 dark:text-emerald-400" />
                  <span>Request Cleared & Approved</span>
                </div>
                {request.reviewedAt && (
                  <span className="text-[11px] text-emerald-700 dark:text-emerald-400 font-mono">
                    {formatFullDate(request.reviewedAt)}
                  </span>
                )}
              </div>
              {request.reviewedByName && (
                <p className="text-[11px] text-emerald-800 dark:text-emerald-300">
                  Approved by: <strong>{request.reviewedByName}</strong>
                </p>
              )}
              {request.reviewerRemarks && (
                <div className="p-2.5 rounded-lg bg-emerald-100/60 dark:bg-emerald-900/40 text-[11px] font-mono">
                  Remarks: {request.reviewerRemarks}
                </div>
              )}
            </div>
          )}

          {request.status === "rejected" && (
            <div className="p-3.5 rounded-xl border border-rose-200 bg-rose-50/70 dark:bg-rose-950/30 dark:border-rose-900/50 space-y-2 text-xs text-rose-900 dark:text-rose-200">
              <div className="flex items-center justify-between">
                <div className="font-semibold flex items-center gap-2">
                  <XCircle size={16} className="text-rose-600 dark:text-rose-400" />
                  <span>Request Declined by Approver</span>
                </div>
                {request.reviewedAt && (
                  <span className="text-[11px] text-rose-700 dark:text-rose-400 font-mono">
                    {formatFullDate(request.reviewedAt)}
                  </span>
                )}
              </div>
              {request.reviewedByName && (
                <p className="text-[11px] text-rose-800 dark:text-rose-300">
                  Reviewed by: <strong>{request.reviewedByName}</strong>
                </p>
              )}
              <div className="p-2.5 rounded-lg bg-rose-100/60 dark:bg-rose-900/40 text-[11px]">
                <strong className="block text-2xs uppercase tracking-wider text-rose-700 dark:text-rose-400 mb-0.5">
                  Rejection Feedback
                </strong>
                <p className="font-mono">
                  {request.reviewerRemarks || "No specific feedback notes provided."}
                </p>
              </div>
            </div>
          )}

          {request.status === "cancelled" && (
            <div className="p-3.5 rounded-xl border border-slate-200 bg-slate-50/70 dark:bg-slate-900/30 dark:border-slate-800 space-y-1 text-xs text-slate-800 dark:text-slate-200">
              <div className="font-semibold flex items-center gap-2">
                <AlertCircle size={16} className="text-slate-500" />
                <span>Request Cancelled</span>
              </div>
              <p className="text-[11px] text-slate-600 dark:text-slate-400">
                This request was cancelled or withdrawn.
              </p>
            </div>
          )}
        </div>

        {/* Timestamps Footer Info */}
        <div className="flex flex-wrap items-center justify-between gap-2 pt-2 border-t border-[var(--line)] text-2xs text-[var(--muted)] font-mono">
          <span className="flex items-center gap-1.5">
            <Calendar size={12} />
            <span>Submitted: {formatFullDate(request.createdAt)}</span>
          </span>
          {request.reviewedAt && (
            <span>Reviewed: {formatFullDate(request.reviewedAt)}</span>
          )}
        </div>
      </div>
    </Modal>
  );
}
