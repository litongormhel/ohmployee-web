"use client";

import { useState } from "react";
import {
  ArrowRightLeft,
  Loader2,
  MapPin,
  UserCheck,
} from "lucide-react";
import { DetailDrawer } from "@/components/shared/DetailDrawer";
import { StatusBadge } from "@/components/ui/StatusBadge";
import type { BadgeVariant } from "@/components/ui/StatusBadge";
import {
  useWorkforcePoolEmployeeDetail,
  useCloseWorkforceAssignment,
  useWithdrawRelieverCoverage,
  type WorkforcePoolEmployee,
  type WorkforcePendingRequest,
} from "@/lib/queries/workforcePool";
import { RequestRelieverCoverageModal } from "@/components/plantilla/RequestRelieverCoverageModal";
import { RequestPoolConversionModal } from "@/components/plantilla/RequestPoolConversionModal";

export interface PoolEmployeeDetailDrawerProps {
  employee: WorkforcePoolEmployee | null;
  isOpen: boolean;
  onClose: () => void;
  onUpdated?: () => void;
}

function getAvailabilityVariant(status: string): BadgeVariant {
  switch (status.toLowerCase().trim()) {
    case "available":
      return "success";
    case "deployed":
      return "info";
    case "review":
      return "warning";
    case "inactive":
    case "resigned":
    case "terminated":
    case "suspended":
      return "danger";
    default:
      return "neutral";
  }
}

function getLoadLevelBadge(level?: string | null) {
  if (!level) return null;
  const l = level.toLowerCase();
  if (l === "critical") {
    return <span className="inline-flex items-center gap-1 text-[11px] font-bold text-red-700 bg-red-100 px-2 py-0.5 rounded-full">● Critical Load</span>;
  }
  if (l === "high") {
    return <span className="inline-flex items-center gap-1 text-[11px] font-bold text-orange-700 bg-orange-100 px-2 py-0.5 rounded-full">● High Load</span>;
  }
  if (l === "medium") {
    return <span className="inline-flex items-center gap-1 text-[11px] font-bold text-amber-700 bg-amber-100 px-2 py-0.5 rounded-full">● Med Load</span>;
  }
  return <span className="inline-flex items-center gap-1 text-[11px] font-medium text-emerald-700 bg-emerald-100 px-2 py-0.5 rounded-full">● Low Load</span>;
}

export function PoolEmployeeDetailDrawer({
  employee,
  isOpen,
  onClose,
  onUpdated,
}: PoolEmployeeDetailDrawerProps) {
  const [isCoverageModalOpen, setIsCoverageModalOpen] = useState(false);
  const [isConversionModalOpen, setIsConversionModalOpen] = useState(false);
  const [closingAssignmentId, setClosingAssignmentId] = useState<string | null>(null);
  const [closingNotes, setClosingNotes] = useState<string>("");

  const detailQuery = useWorkforcePoolEmployeeDetail(employee?.id ?? null);
  const closeAssignmentMutation = useCloseWorkforceAssignment();
  const withdrawMutation = useWithdrawRelieverCoverage();

  if (!employee) return null;

  const detail = detailQuery.data;
  const emp = detail?.employee ?? employee;

  const handleCloseAssignment = (assignmentId: string) => {
    closeAssignmentMutation.mutate(
      { assignmentId, notes: closingNotes.trim() || undefined },
      {
        onSuccess: () => {
          setClosingAssignmentId(null);
          setClosingNotes("");
          detailQuery.refetch();
          onUpdated?.();
        },
      }
    );
  };

  const handleWithdrawRequest = (request: WorkforcePendingRequest) => {
    if (confirm(`Withdraw pending coverage request for ${request.storeName || "this store"}?`)) {
      withdrawMutation.mutate(
        { requestId: request.id },
        {
          onSuccess: () => {
            detailQuery.refetch();
            onUpdated?.();
          },
        }
      );
    }
  };

  return (
    <>
      <DetailDrawer
        isOpen={isOpen}
        onClose={onClose}
        title={emp.employeeName}
        subtitle={`${emp.employeeNo} • ${emp.poolTypeName}`}
      >
        <div className="p-6 space-y-6">
          {/* Top Profile Summary Card */}
          <div className="p-5 rounded-xl border border-gray-200 bg-linear-to-br from-gray-50 to-white shadow-xs space-y-4">
            <div className="flex items-start justify-between">
              <div className="space-y-1">
                <div className="flex items-center gap-2">
                  <span className="text-base font-bold text-gray-900">{emp.employeeName}</span>
                  {getLoadLevelBadge(emp.deploymentLoadLevel)}
                </div>
                <p className="text-xs text-gray-500 font-mono">
                  No: {emp.employeeNo} {emp.vcode ? `• VCode: ${emp.vcode}` : ""}
                </p>
              </div>
              <div className="flex items-center gap-2">
                <StatusBadge variant={getAvailabilityVariant(emp.availabilityStatus)}>
                  {emp.availabilityStatus}
                </StatusBadge>
                {emp.hasPendingRequest && (
                  <span className="text-[10px] font-bold uppercase tracking-wider text-amber-700 bg-amber-100 px-2 py-0.5 rounded border border-amber-200">
                    Reserved
                  </span>
                )}
              </div>
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 pt-3 border-t border-gray-100 text-xs">
              <div>
                <span className="text-gray-400 block mb-0.5">Pool Type</span>
                <span className="font-semibold text-gray-800">{emp.poolTypeName}</span>
              </div>
              <div>
                <span className="text-gray-400 block mb-0.5">Position</span>
                <span className="font-semibold text-gray-800">{emp.position || "Pooled Personnel"}</span>
              </div>
              <div>
                <span className="text-gray-400 block mb-0.5">Active Stores</span>
                <span className="font-semibold text-gray-800">
                  {emp.activeStoreCount} store{emp.activeStoreCount === 1 ? "" : "s"}
                </span>
              </div>
              <div>
                <span className="text-gray-400 block mb-0.5">Home Account</span>
                <span className="font-semibold text-gray-800">{emp.homeAccount || "Moses HQ"}</span>
              </div>
            </div>

            {/* Action Bar */}
            <div className="flex flex-wrap gap-2 pt-2 border-t border-gray-100">
              <button
                type="button"
                onClick={() => setIsCoverageModalOpen(true)}
                className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-white bg-blue-600 rounded-lg hover:bg-blue-700 transition shadow-xs"
              >
                <UserCheck className="h-3.5 w-3.5" /> Request Coverage Deployment
              </button>
              <button
                type="button"
                onClick={() => setIsConversionModalOpen(true)}
                className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-purple-700 bg-purple-50 border border-purple-200 rounded-lg hover:bg-purple-100 transition"
              >
                <ArrowRightLeft className="h-3.5 w-3.5" /> Convert to Regular Plantilla
              </button>
            </div>
          </div>

          {/* Active Deployments Section */}
          <div className="space-y-3">
            <h3 className="text-xs font-bold uppercase tracking-wider text-gray-500 flex items-center justify-between">
              <span>Active Store Deployments ({detail?.activeDeployments.length ?? 0})</span>
              <span className="text-[11px] font-normal text-gray-400">Real-time Coverage</span>
            </h3>

            {detailQuery.isLoading ? (
              <div className="py-4 text-center text-xs text-gray-400">Loading deployments...</div>
            ) : (detail?.activeDeployments ?? []).length === 0 ? (
              <div className="p-4 rounded-xl border border-dashed border-gray-200 text-center text-xs text-gray-500 bg-gray-50/50">
                Not currently deployed to any store. Ready for coverage deployment.
              </div>
            ) : (
              <div className="divide-y divide-gray-100 border border-gray-200 rounded-xl overflow-hidden bg-white shadow-xs">
                {detail?.activeDeployments.map((dep) => (
                  <div key={dep.id} className="p-4 space-y-3">
                    <div className="flex items-start justify-between">
                      <div>
                        <div className="flex items-center gap-2">
                          <MapPin className="h-4 w-4 text-blue-600 shrink-0" />
                          <span className="text-sm font-semibold text-gray-900">
                            {dep.storeName || "Store"} {dep.storeBranch ? `(${dep.storeBranch})` : ""}
                          </span>
                          {dep.isPrimary && (
                            <span className="text-[10px] font-bold text-blue-700 bg-blue-50 px-1.5 py-0.5 rounded border border-blue-200">
                              Primary
                            </span>
                          )}
                        </div>
                        <p className="text-xs text-gray-500 mt-1">
                          Account: {dep.accountName || "—"} {dep.positionCovered ? `• Covering: ${dep.positionCovered}` : ""}
                        </p>
                      </div>
                      <StatusBadge variant="success">{dep.status}</StatusBadge>
                    </div>

                    <div className="flex items-center justify-between text-xs text-gray-500">
                      <span>
                        Dates: {dep.startDate || "—"} &rarr; {dep.endDate || "Ongoing"}
                      </span>
                      {closingAssignmentId !== dep.id && (
                        <button
                          type="button"
                          onClick={() => setClosingAssignmentId(dep.id)}
                          className="text-xs font-medium text-red-600 hover:text-red-700 underline underline-offset-2"
                        >
                          Close Assignment
                        </button>
                      )}
                    </div>

                    {/* Inline Close Assignment form */}
                    {closingAssignmentId === dep.id && (
                      <div className="p-3 bg-red-50/60 border border-red-200 rounded-lg space-y-2 mt-2">
                        <label className="block text-xs font-semibold text-red-900">
                          Reason for closing deployment:
                        </label>
                        <input
                          type="text"
                          value={closingNotes}
                          onChange={(e) => setClosingNotes(e.target.value)}
                          placeholder="e.g. Regular employee returned, contract concluded..."
                          className="w-full text-xs rounded border border-red-300 p-2 bg-white focus:outline-none focus:ring-2 focus:ring-red-500"
                        />
                        <div className="flex justify-end gap-2">
                          <button
                            type="button"
                            onClick={() => {
                              setClosingAssignmentId(null);
                              setClosingNotes("");
                            }}
                            className="px-2.5 py-1 text-xs text-gray-600 hover:text-gray-800"
                          >
                            Cancel
                          </button>
                          <button
                            type="button"
                            onClick={() => handleCloseAssignment(dep.id)}
                            disabled={closeAssignmentMutation.isPending}
                            className="inline-flex items-center gap-1 px-3 py-1 text-xs font-semibold text-white bg-red-600 rounded hover:bg-red-700 transition"
                          >
                            {closeAssignmentMutation.isPending && <Loader2 className="h-3 w-3 animate-spin" />}
                            Confirm Close
                          </button>
                        </div>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Pending Requests Section */}
          {(detail?.pendingRequests ?? []).length > 0 && (
            <div className="space-y-3">
              <h3 className="text-xs font-bold uppercase tracking-wider text-amber-700 flex items-center justify-between">
                <span>Pending Coverage Requests ({detail?.pendingRequests.length})</span>
                <span className="text-[11px] font-normal text-amber-600">Awaiting Data Team SLA</span>
              </h3>
              <div className="divide-y divide-amber-100 border border-amber-200 rounded-xl overflow-hidden bg-amber-50/30">
                {detail?.pendingRequests.map((req) => (
                  <div key={req.id} className="p-3.5 flex items-center justify-between gap-3 text-xs">
                    <div className="space-y-0.5">
                      <div className="font-semibold text-gray-900">
                        {req.accountName ? `${req.accountName} / ` : ""}
                        {req.storeName || "Store"}
                      </div>
                      <div className="text-gray-500">
                        Requested by: {req.requestedBy || "Requester"} • Priority: {req.priority}
                        {req.ageDays != null ? ` • ${req.ageDays}d ago` : ""}
                      </div>
                    </div>
                    <div className="flex items-center gap-2 shrink-0">
                      <StatusBadge variant="warning">{req.status}</StatusBadge>
                      <button
                        type="button"
                        onClick={() => handleWithdrawRequest(req)}
                        disabled={withdrawMutation.isPending}
                        className="text-xs font-medium text-red-600 hover:text-red-800 hover:underline"
                      >
                        Withdraw
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Pending Conversions Section */}
          {(detail?.conversionRequests ?? []).length > 0 && (
            <div className="space-y-3">
              <h3 className="text-xs font-bold uppercase tracking-wider text-purple-700 flex items-center justify-between">
                <span>Conversion Requests ({detail?.conversionRequests.length})</span>
              </h3>
              <div className="divide-y divide-purple-100 border border-purple-200 rounded-xl overflow-hidden bg-purple-50/30">
                {detail?.conversionRequests.map((c) => (
                  <div key={c.id} className="p-3.5 space-y-1 text-xs">
                    <div className="flex items-center justify-between">
                      <span className="font-semibold text-gray-900">
                        Target: {c.targetAccount} / {c.targetStore} &rarr; {c.targetPosition}
                      </span>
                      <StatusBadge
                        variant={
                          c.status.toLowerCase() === "approved"
                            ? "success"
                            : c.status.toLowerCase() === "rejected"
                            ? "danger"
                            : "warning"
                        }
                      >
                        {c.status}
                      </StatusBadge>
                    </div>
                    <p className="text-gray-600">Effective: {c.effectiveDate} • Reason: {c.reason}</p>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Assignment History Section */}
          <div className="space-y-3">
            <h3 className="text-xs font-bold uppercase tracking-wider text-gray-500">
              Assignment History ({detail?.assignmentHistory.length ?? 0})
            </h3>
            {detailQuery.isLoading ? (
              <div className="py-4 text-center text-xs text-gray-400">Loading history...</div>
            ) : (detail?.assignmentHistory ?? []).length === 0 ? (
              <div className="p-4 rounded-xl border border-dashed border-gray-200 text-center text-xs text-gray-500">
                No prior deployment assignments found.
              </div>
            ) : (
              <div className="divide-y divide-gray-100 border border-gray-200 rounded-xl overflow-hidden bg-white text-xs">
                {detail?.assignmentHistory.map((h) => (
                  <div key={h.id} className="p-3 hover:bg-gray-50 flex items-center justify-between gap-4">
                    <div>
                      <div className="font-semibold text-gray-900">
                        {h.accountName ? `${h.accountName} / ` : ""}
                        {h.storeName || "Store"}
                        {h.positionCovered ? ` (${h.positionCovered})` : ""}
                      </div>
                      <div className="text-gray-400 mt-0.5">
                        {h.startDate || "—"} to {h.endDate || "Present"} {h.endReason ? `• Reason: ${h.endReason}` : ""}
                      </div>
                    </div>
                    <StatusBadge variant="neutral">{h.status}</StatusBadge>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </DetailDrawer>

      {/* Coverage Request Modal */}
      {isCoverageModalOpen && (
        <RequestRelieverCoverageModal
          isOpen={isCoverageModalOpen}
          onClose={() => setIsCoverageModalOpen(false)}
          employee={emp}
          onSuccess={() => {
            detailQuery.refetch();
            onUpdated?.();
          }}
        />
      )}

      {/* Conversion Request Modal */}
      {isConversionModalOpen && (
        <RequestPoolConversionModal
          isOpen={isConversionModalOpen}
          onClose={() => setIsConversionModalOpen(false)}
          employee={emp}
          onSuccess={() => {
            detailQuery.refetch();
            onUpdated?.();
          }}
        />
      )}
    </>
  );
}
