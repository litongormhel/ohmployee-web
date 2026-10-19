"use client";

import { useState } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  Mail,
  Phone,
  RefreshCw,
} from "lucide-react";
import {
  useApproveAccountRequest,
  useRejectAccountRequest,
  type AccountRequestItem,
  type AccountRequestStatus,
} from "@/lib/queries/accountRequests";
import { useRolesQuery, useGroupsQuery, useAccountsByGroupsQuery } from "@/lib/queries/users";

interface AccountRequestDataTableProps {
  requests: AccountRequestItem[];
  tab: AccountRequestStatus;
}

function formatDate(dateStr: string | null): string {
  if (!dateStr) return "—";
  try {
    return new Date(dateStr).toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
    });
  } catch {
    return dateStr;
  }
}

export function AccountRequestDataTable({
  requests,
  tab,
}: AccountRequestDataTableProps) {
  // Modal states for single action
  const [selectedApproveRequest, setSelectedApproveRequest] =
    useState<AccountRequestItem | null>(null);
  const [selectedRejectRequest, setSelectedRejectRequest] =
    useState<AccountRequestItem | null>(null);

  // Approval Form Inputs
  const [selectedRoleId, setSelectedRoleId] = useState<string>("");
  const [scopeType, setScopeType] = useState<"global" | "scoped">("scoped");
  const [selectedGroupIds, setSelectedGroupIds] = useState<string[]>([]);
  const [selectedAccountIds, setSelectedAccountIds] = useState<string[]>([]);

  // Rejection Form Inputs
  const [rejectionReason, setRejectionReason] = useState<string>("");
  const [rejectionRemarks, setRejectionRemarks] = useState<string>("");
  const [rejectReasonError, setRejectReasonError] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  // Queries for role / group / account selection
  const { data: roles = [] } = useRolesQuery();
  const { data: groups = [] } = useGroupsQuery();
  const { data: accounts = [] } = useAccountsByGroupsQuery(selectedGroupIds);

  const approveMutation = useApproveAccountRequest();
  const rejectMutation = useRejectAccountRequest();

  // Filter roles to exclude Super Admin and Head Admin (as per Mobile security standards)
  const assignableRoles = roles.filter(
    (r) => r.name !== "Super Admin" && r.name !== "Head Admin"
  );

  const handleOpenApprove = (req: AccountRequestItem) => {
    setActionError(null);
    setSelectedApproveRequest(req);
    setSelectedRoleId(req.requestedRoleId || assignableRoles[0]?.id || "");
    setScopeType(req.requestedScopeType || "scoped");
    setSelectedGroupIds(req.requestedGroupIds || []);
    setSelectedAccountIds(req.requestedAccountIds || []);
  };

  const handleOpenReject = (req: AccountRequestItem) => {
    setActionError(null);
    setSelectedRejectRequest(req);
    setRejectionReason("");
    setRejectionRemarks("");
    setRejectReasonError(false);
  };

  const handleToggleGroup = (groupId: string) => {
    setSelectedGroupIds((prev) =>
      prev.includes(groupId) ? prev.filter((id) => id !== groupId) : [...prev, groupId]
    );
  };

  const handleToggleAccount = (accountId: string) => {
    setSelectedAccountIds((prev) =>
      prev.includes(accountId) ? prev.filter((id) => id !== accountId) : [...prev, accountId]
    );
  };

  const handleConfirmApprove = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedApproveRequest) return;
    if (!selectedRoleId) {
      setActionError("Please select a role to assign.");
      return;
    }
    if (scopeType === "scoped" && selectedGroupIds.length === 0) {
      setActionError("Please select at least one group for scoped access.");
      return;
    }

    setActionError(null);
    try {
      await approveMutation.mutateAsync({
        requestId: selectedApproveRequest.id,
        roleId: selectedRoleId,
        scopeType,
        groupIds: scopeType === "global" ? [] : selectedGroupIds,
        accountIds: scopeType === "global" ? [] : selectedAccountIds,
      });
      setSelectedApproveRequest(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error ? err.message : "Failed to approve account request."
      );
    }
  };

  const handleConfirmReject = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedRejectRequest) return;
    if (!rejectionReason.trim()) {
      setRejectReasonError(true);
      return;
    }

    setActionError(null);
    try {
      await rejectMutation.mutateAsync({
        requestId: selectedRejectRequest.id,
        reason: rejectionReason.trim(),
        remarks: rejectionRemarks.trim() || undefined,
      });
      setSelectedRejectRequest(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error ? err.message : "Failed to reject account request."
      );
    }
  };

  const isBusy = approveMutation.isPending || rejectMutation.isPending;

  return (
    <div className="flex-1 min-h-0 flex flex-col">
      {/* Table Container */}
      <div className="flex-1 min-h-0 flex flex-col rounded-xl border border-[var(--line)] bg-[var(--bg)] overflow-hidden">
        <div className="flex-1 overflow-x-auto">
          <table className="w-full min-w-[960px] border-collapse text-left text-xs">
            <thead className="sticky top-0 z-10 bg-[var(--bg)] text-[12.5px] font-medium text-[var(--muted)] border-b border-[var(--line)]">
              <tr>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Applicant Name
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Email & Contact
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Requested Role
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Requested Scope
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Notes
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Submitted
                </th>
                <th
                  scope="col"
                  className={`px-4 py-2.5 font-medium ${
                    tab === "rejected" ? "text-left" : "text-right"
                  }`}
                >
                  {tab === "rejected" ? "Rejection Reason" : "Action"}
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--line)]">
              {requests.map((request) => {
                const isPending = tab === "pending" || request.status === "pending";
                const isApproved = tab === "approved" || request.status === "approved";

                return (
                  <tr
                    key={request.id}
                    className="transition-colors hover:bg-[var(--soft)]"
                  >
                    <td className="px-4 py-3">
                      <div className="font-semibold text-[var(--text)]">
                        {request.fullName}
                      </div>
                      <div className="text-[11px] text-[var(--muted)]">
                        ID: {request.id.slice(0, 8)}…
                      </div>
                    </td>
                    <td className="px-4 py-3 text-[var(--text)]">
                      <div className="flex items-center gap-1.5 font-medium">
                        <Mail className="h-3 w-3 text-[var(--muted)]" />
                        <span>{request.email}</span>
                      </div>
                      {request.mobileNumber && (
                        <div className="flex items-center gap-1.5 text-[11px] text-[var(--muted)] mt-0.5">
                          <Phone className="h-3 w-3 text-[var(--muted)]" />
                          <span>{request.mobileNumber}</span>
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-3 text-[var(--text)]">
                      <span className="inline-flex items-center rounded-md bg-[var(--soft)] px-2 py-0.5 text-xs font-medium text-[var(--text)]">
                        {request.requestedRoleName || "Standard User"}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-[var(--text)]">
                      <div className="text-xs">
                        <strong className="text-[var(--accent)] font-medium">
                          {request.requestedScopeType === "global"
                            ? "Global"
                            : request.requestedGroupNames.length > 0
                            ? request.requestedGroupNames.join(", ")
                            : "Scoped"}
                        </strong>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-[var(--muted)] max-w-xs truncate text-[11px]">
                      {request.notes ? `"${request.notes}"` : "—"}
                    </td>
                    <td className="px-4 py-3 text-[var(--muted)] whitespace-nowrap">
                      {formatDate(request.createdAt)}
                    </td>
                    <td
                      className={`px-4 py-3 ${
                        tab === "rejected" ? "text-left" : "text-right"
                      }`}
                    >
                      {isPending ? (
                        <div className="flex items-center justify-end gap-1.5">
                          <button
                            type="button"
                            onClick={() => handleOpenReject(request)}
                            disabled={isBusy}
                            className="inline-flex h-7 items-center rounded-md border border-[var(--bad)]/40 bg-transparent px-2 text-xs font-medium text-[var(--bad)] hover:bg-[var(--bad)]/10 disabled:opacity-50 transition cursor-pointer"
                          >
                            <span>Reject</span>
                          </button>
                          <button
                            type="button"
                            onClick={() => handleOpenApprove(request)}
                            disabled={isBusy}
                            className="inline-flex h-7 items-center rounded-md border border-[var(--ok)] bg-[var(--ok)] px-2.5 text-xs font-medium text-white hover:brightness-105 disabled:opacity-50 transition cursor-pointer"
                          >
                            <span>Approve</span>
                          </button>
                        </div>
                      ) : isApproved ? (
                        <div className="inline-flex items-center gap-1 text-xs font-medium text-[var(--ok)]">
                          <CheckCircle2 className="h-3.5 w-3.5" />
                          <span>Assigned: {request.assignedRoleName || "User"}</span>
                          {request.reviewerDisplayName && (
                            <span className="text-[11px] text-[var(--muted)] ml-1">
                              by {request.reviewerDisplayName}
                            </span>
                          )}
                        </div>
                      ) : (
                        <div className="text-xs text-[var(--bad)] max-w-xs truncate">
                          {request.rejectionReason || "Rejected"}
                          {request.reviewerDisplayName && (
                            <div className="text-[10px] text-[var(--muted)]">
                              by {request.reviewerDisplayName}
                            </div>
                          )}
                        </div>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {/* Approve Modal Dialog */}
      {selectedApproveRequest && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-xs">
          <div className="bg-[var(--bg)] rounded-2xl shadow-xl border border-[var(--line)] w-full max-w-lg p-5 space-y-4 max-h-[85vh] flex flex-col animate-in fade-in-0 zoom-in-95">
            <div>
              <h3 className="text-sm font-bold text-[var(--text)]">Approve Account Registration</h3>
              <p className="text-xs text-[var(--muted)] mt-0.5">
                Assign role and operational scope for <strong>{selectedApproveRequest.fullName}</strong> (
                {selectedApproveRequest.email})
              </p>
            </div>

            {actionError && (
              <div className="flex items-center gap-2 rounded-md border border-rose-200 bg-rose-50 p-2 text-xs text-rose-800">
                <AlertTriangle className="h-4 w-4 shrink-0" />
                <span>{actionError}</span>
              </div>
            )}

            <form onSubmit={handleConfirmApprove} className="space-y-4 flex-1 overflow-y-auto pr-1">
              <div>
                <label className="block text-xs font-bold text-[var(--text)] mb-1">
                  Assigned Role *
                </label>
                <select
                  required
                  value={selectedRoleId}
                  onChange={(e) => setSelectedRoleId(e.target.value)}
                  className="w-full p-2.5 text-xs rounded-xl border border-[var(--line)] bg-[var(--bg)] text-[var(--text)] focus:outline-hidden focus:border-[var(--accent)]"
                >
                  <option value="">Select Role...</option>
                  {assignableRoles.map((r) => (
                    <option key={r.id} value={r.id}>
                      {r.name}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-xs font-bold text-[var(--text)] mb-1">Scope Mode *</label>
                <div className="grid grid-cols-2 gap-2">
                  <button
                    type="button"
                    onClick={() => setScopeType("scoped")}
                    className={`py-2 text-xs font-semibold rounded-xl border transition cursor-pointer ${
                      scopeType === "scoped"
                        ? "border-[var(--accent)] bg-[var(--soft)] text-[var(--accent)]"
                        : "border-[var(--line)] bg-[var(--bg)] text-[var(--text)] hover:bg-[var(--soft)]"
                    }`}
                  >
                    Scoped Groups
                  </button>
                  <button
                    type="button"
                    onClick={() => setScopeType("global")}
                    className={`py-2 text-xs font-semibold rounded-xl border transition cursor-pointer ${
                      scopeType === "global"
                        ? "border-[var(--accent)] bg-[var(--soft)] text-[var(--accent)]"
                        : "border-[var(--line)] bg-[var(--bg)] text-[var(--text)] hover:bg-[var(--soft)]"
                    }`}
                  >
                    Global (All Groups)
                  </button>
                </div>
              </div>

              {scopeType === "scoped" && (
                <>
                  <div className="space-y-2">
                    <label className="block text-xs font-bold text-[var(--text)]">
                      Assign Operational Groups *
                    </label>
                    <div className="border border-[var(--line)] rounded-xl p-3 max-h-36 overflow-y-auto space-y-1.5 bg-[var(--soft)]/50">
                      {groups.map((g) => (
                        <label
                          key={g.id}
                          className="flex items-center gap-2 text-xs text-[var(--text)] cursor-pointer hover:opacity-80"
                        >
                          <input
                            type="checkbox"
                            checked={selectedGroupIds.includes(g.id)}
                            onChange={() => handleToggleGroup(g.id)}
                            className="rounded text-[var(--accent)] focus:ring-[var(--accent)] cursor-pointer"
                          />
                          <span>{g.name}</span>
                        </label>
                      ))}
                    </div>
                  </div>

                  {accounts.length > 0 && (
                    <div className="space-y-2">
                      <label className="block text-xs font-bold text-[var(--text)]">
                        Assign Specific Accounts (Optional)
                      </label>
                      <div className="border border-[var(--line)] rounded-xl p-3 max-h-36 overflow-y-auto space-y-1.5 bg-[var(--soft)]/50">
                        {accounts.map((a) => (
                          <label
                            key={a.id}
                            className="flex items-center gap-2 text-xs text-[var(--text)] cursor-pointer hover:opacity-80"
                          >
                            <input
                              type="checkbox"
                              checked={selectedAccountIds.includes(a.id)}
                              onChange={() => handleToggleAccount(a.id)}
                              className="rounded text-[var(--accent)] focus:ring-[var(--accent)] cursor-pointer"
                            />
                            <span>{a.account_name}</span>
                          </label>
                        ))}
                      </div>
                    </div>
                  )}
                </>
              )}

              <div className="flex items-center justify-end gap-2 pt-2 border-t border-[var(--line)]">
                <button
                  type="button"
                  onClick={() => setSelectedApproveRequest(null)}
                  className="px-3.5 py-2 text-xs font-semibold text-[var(--muted)] hover:bg-[var(--soft)] rounded-xl transition cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={approveMutation.isPending}
                  className="px-4 py-2 text-xs font-bold text-white bg-[var(--ok)] hover:brightness-105 rounded-xl transition cursor-pointer disabled:opacity-50 inline-flex items-center gap-1.5"
                >
                  {approveMutation.isPending && (
                    <RefreshCw className="h-3 w-3 animate-spin" />
                  )}
                  <span>{approveMutation.isPending ? "Approving..." : "Confirm & Provision User"}</span>
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Reject Modal Dialog */}
      {selectedRejectRequest && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-xs">
          <div className="bg-[var(--bg)] rounded-2xl shadow-xl border border-[var(--line)] w-full max-w-md p-5 space-y-4 animate-in fade-in-0 zoom-in-95">
            <div>
              <h3 className="text-sm font-bold text-[var(--text)]">Reject Account Request</h3>
              <p className="text-xs text-[var(--muted)] mt-0.5">
                Decline registration for <strong>{selectedRejectRequest.fullName}</strong>.
              </p>
            </div>

            {actionError && (
              <div className="flex items-center gap-2 rounded-md border border-rose-200 bg-rose-50 p-2 text-xs text-rose-800">
                <AlertTriangle className="h-4 w-4 shrink-0" />
                <span>{actionError}</span>
              </div>
            )}

            <form onSubmit={handleConfirmReject} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-[var(--text)] mb-1">
                  Rejection Reason *
                </label>
                <select
                  required
                  value={rejectionReason}
                  onChange={(e) => {
                    setRejectionReason(e.target.value);
                    if (rejectReasonError && e.target.value.trim()) {
                      setRejectReasonError(false);
                    }
                  }}
                  className={`w-full p-2.5 text-xs rounded-xl border bg-[var(--bg)] text-[var(--text)] focus:outline-hidden ${
                    rejectReasonError
                      ? "border-[var(--bad)] focus:border-[var(--bad)]"
                      : "border-[var(--line)] focus:border-[var(--accent)]"
                  }`}
                >
                  <option value="">Select Reason...</option>
                  <option value="Duplicate registration attempt">
                    Duplicate registration attempt
                  </option>
                  <option value="Unverified employee identity">
                    Unverified employee identity
                  </option>
                  <option value="Invalid phone number format">Invalid phone number format</option>
                  <option value="Unauthorized external registration">
                    Unauthorized external registration
                  </option>
                  <option value="Other / Role mismatch">Other / Role mismatch</option>
                </select>
                {rejectReasonError && (
                  <p className="mt-1 text-2xs text-[var(--bad)]">
                    Please select a rejection reason.
                  </p>
                )}
              </div>

              <div>
                <label className="block text-xs font-bold text-[var(--text)] mb-1">
                  Additional Notes (Optional)
                </label>
                <textarea
                  rows={2}
                  value={rejectionRemarks}
                  onChange={(e) => setRejectionRemarks(e.target.value)}
                  placeholder="Details for user audit record"
                  className="w-full p-2 text-xs rounded-xl border border-[var(--line)] bg-[var(--bg)] text-[var(--text)] placeholder:text-[var(--muted)] focus:outline-hidden focus:border-[var(--accent)]"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-2 border-t border-[var(--line)]">
                <button
                  type="button"
                  onClick={() => setSelectedRejectRequest(null)}
                  className="px-3.5 py-2 text-xs font-semibold text-[var(--muted)] hover:bg-[var(--soft)] rounded-xl transition cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={rejectMutation.isPending}
                  className="px-4 py-2 text-xs font-bold text-white bg-[var(--bad)] hover:brightness-105 rounded-xl transition cursor-pointer disabled:opacity-50 inline-flex items-center gap-1.5"
                >
                  {rejectMutation.isPending && (
                    <RefreshCw className="h-3 w-3 animate-spin" />
                  )}
                  <span>{rejectMutation.isPending ? "Rejecting..." : "Confirm Rejection"}</span>
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
