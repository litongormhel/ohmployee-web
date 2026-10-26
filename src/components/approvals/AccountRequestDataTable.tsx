"use client";

import { useMemo, useState } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  Mail,
  Phone,
  RefreshCw,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { TablePagination } from "@/components/shared/TablePagination";
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
  page?: number;
  pageSize?: number;
  totalCount?: number;
  onPageChange?: (newPage: number) => void;
  onPageSizeChange?: (newPageSize: number) => void;
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
  page,
  pageSize,
  totalCount,
  onPageChange,
  onPageSizeChange,
}: AccountRequestDataTableProps) {
  const currentPage = page ?? 1;
  const currentPageSize = pageSize ?? 10;
  const count = totalCount ?? requests.length;

  const paginatedRequests = useMemo(() => {
    const start = (currentPage - 1) * currentPageSize;
    return requests.slice(start, start + currentPageSize);
  }, [requests, currentPage, currentPageSize]);

  // Modal states for single action
  const [selectedApproveRequest, setSelectedApproveRequest] =
    useState<AccountRequestItem | null>(null);
  const [selectedRejectRequest, setSelectedRejectRequest] =
    useState<AccountRequestItem | null>(null);

  // Approval Form Inputs
  const [selectedRoleId, setSelectedRoleId] = useState<string>("" );
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
      <div className="flex-1 min-h-0 flex flex-col rounded-xl border border-border-default bg-surface overflow-hidden">
        <div className="flex-1 overflow-x-auto">
          <table className="w-full min-w-[960px] border-collapse text-left text-sm">
            <thead className="sticky top-0 z-10 bg-surface-subtle text-xs font-semibold text-text-secondary border-b border-border-default">
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
            <tbody className="divide-y divide-border-default">
              {paginatedRequests.map((request) => {
                const isPending = tab === "pending" || request.status === "pending";
                const isApproved = tab === "approved" || request.status === "approved";

                return (
                  <tr
                    key={request.id}
                    className="transition-colors hover:bg-surface-hover"
                  >
                    <td className="px-4 py-2.5">
                      <div className="font-semibold text-text-primary text-sm">
                        {request.fullName}
                      </div>
                      <div className="text-xs text-text-muted font-mono">
                        ID: {request.id.slice(0, 8)}…
                      </div>
                    </td>
                    <td className="px-4 py-2.5 text-text-primary text-sm">
                      <div className="flex items-center gap-1.5 font-medium">
                        <Mail className="h-3.5 w-3.5 text-text-muted" />
                        <span>{request.email}</span>
                      </div>
                      {request.mobileNumber && (
                        <div className="flex items-center gap-1.5 text-xs text-text-muted mt-0.5">
                          <Phone className="h-3.5 w-3.5 text-text-muted" />
                          <span>{request.mobileNumber}</span>
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-2.5 text-text-primary text-sm">
                      <span className="inline-flex items-center rounded-md bg-surface-subtle px-2 py-0.5 text-xs font-medium text-text-primary border border-border-default">
                        {request.requestedRoleName || "Standard User"}
                      </span>
                    </td>
                    <td className="px-4 py-2.5 text-text-primary text-sm">
                      <div className="text-xs font-semibold text-text-brand-bold">
                        {request.requestedScopeType === "global"
                          ? "Global"
                          : request.requestedGroupNames.length > 0
                          ? request.requestedGroupNames.join(", ")
                          : "Scoped"}
                      </div>
                    </td>
                    <td className="px-4 py-2.5 text-text-secondary max-w-xs truncate text-xs">
                      {request.notes ? `"${request.notes}"` : "—"}
                    </td>
                    <td className="px-4 py-2.5 text-text-secondary whitespace-nowrap text-xs font-mono">
                      {formatDate(request.createdAt)}
                    </td>
                    <td
                      className={`px-4 py-2.5 ${
                        tab === "rejected" ? "text-left" : "text-right"
                      }`}
                    >
                      {isPending ? (
                        <div className="flex items-center justify-end gap-1.5">
                          <button
                            type="button"
                            onClick={() => handleOpenReject(request)}
                            disabled={isBusy}
                            className="inline-flex h-7 items-center rounded-md border border-border-danger bg-transparent px-2.5 text-xs font-medium text-text-danger hover:bg-danger-subtle disabled:opacity-50 transition cursor-pointer"
                          >
                            <span>Reject</span>
                          </button>
                          <button
                            type="button"
                            onClick={() => handleOpenApprove(request)}
                            disabled={isBusy}
                            className="inline-flex h-7 items-center rounded-md border border-border-brand bg-brand-500 hover:bg-brand-600 px-2.5 text-xs font-medium text-white shadow-2xs disabled:opacity-50 transition cursor-pointer"
                          >
                            <span>Approve</span>
                          </button>
                        </div>
                      ) : isApproved ? (
                        <div className="inline-flex items-center gap-1 text-xs font-medium text-text-primary">
                          <CheckCircle2 className="h-3.5 w-3.5 text-text-muted" />
                          <span>Assigned: {request.assignedRoleName || "User"}</span>
                          {request.reviewerDisplayName && (
                            <span className="text-xs text-text-muted ml-1">
                              by {request.reviewerDisplayName}
                            </span>
                          )}
                        </div>
                      ) : (
                        <div className="text-xs text-text-danger max-w-xs truncate">
                          {request.rejectionReason || "Rejected"}
                          {request.reviewerDisplayName && (
                            <div className="text-xs text-text-muted">
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

        {onPageChange && (
          <TablePagination
            page={currentPage}
            pageSize={currentPageSize}
            totalCount={count}
            pageSizeOptions={[10, 25, 50]}
            onPageChange={onPageChange}
            onPageSizeChange={onPageSizeChange}
          />
        )}
      </div>

      {/* Approve Modal Dialog */}
      {selectedApproveRequest && (
        <Modal
          isOpen={Boolean(selectedApproveRequest)}
          onClose={() => setSelectedApproveRequest(null)}
          title="Approve Account Registration"
          subtitle={`Assign role and operational scope for ${selectedApproveRequest.fullName} (${selectedApproveRequest.email})`}
          isSubmitting={approveMutation.isPending}
          disableBackdropClick={approveMutation.isPending}
          maxWidthClass="max-w-lg"
        >
          <div className="space-y-4">
            {actionError && (
              <div className="flex items-center gap-2 rounded-md border border-border-danger bg-danger-subtle p-2 text-xs text-text-danger">
                <AlertTriangle className="h-4 w-4 shrink-0" />
                <span>{actionError}</span>
              </div>
            )}

            <form onSubmit={handleConfirmApprove} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-text-primary mb-1">
                  Assigned Role *
                </label>
                <select
                  required
                  value={selectedRoleId}
                  onChange={(e) => setSelectedRoleId(e.target.value)}
                  className="w-full p-2.5 text-xs rounded-xl border border-border-default bg-surface text-text-primary focus:outline-hidden focus:border-border-brand"
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
                <label className="block text-xs font-bold text-text-primary mb-1">Scope Mode *</label>
                <div className="grid grid-cols-2 gap-2">
                  <button
                    type="button"
                    onClick={() => setScopeType("scoped")}
                    className={`py-2 text-xs font-semibold rounded-xl border transition cursor-pointer ${
                      scopeType === "scoped"
                        ? "border-border-brand bg-brand-subtle text-text-brand-bold"
                        : "border-border-default bg-surface text-text-primary hover:bg-surface-hover"
                    }`}
                  >
                    Scoped Groups
                  </button>
                  <button
                    type="button"
                    onClick={() => setScopeType("global")}
                    className={`py-2 text-xs font-semibold rounded-xl border transition cursor-pointer ${
                      scopeType === "global"
                        ? "border-border-brand bg-brand-subtle text-text-brand-bold"
                        : "border-border-default bg-surface text-text-primary hover:bg-surface-hover"
                    }`}
                  >
                    Global (All Groups)
                  </button>
                </div>
              </div>

              {scopeType === "scoped" && (
                <>
                  <div className="space-y-2">
                    <label className="block text-xs font-bold text-text-primary">
                      Assign Operational Groups *
                    </label>
                    <div className="border border-border-default rounded-xl p-3 max-h-36 overflow-y-auto space-y-1.5 bg-surface-subtle">
                      {groups.map((g) => (
                        <label
                          key={g.id}
                          className="flex items-center gap-2 text-xs text-text-primary cursor-pointer hover:opacity-80"
                        >
                          <input
                            type="checkbox"
                            checked={selectedGroupIds.includes(g.id)}
                            onChange={() => handleToggleGroup(g.id)}
                            className="rounded text-brand-500 focus:ring-brand-500 cursor-pointer"
                          />
                          <span>{g.name}</span>
                        </label>
                      ))}
                    </div>
                  </div>

                  {accounts.length > 0 && (
                    <div className="space-y-2">
                      <label className="block text-xs font-bold text-text-primary">
                        Assign Specific Accounts (Optional)
                      </label>
                      <div className="border border-border-default rounded-xl p-3 max-h-36 overflow-y-auto space-y-1.5 bg-surface-subtle">
                        {accounts.map((a) => (
                          <label
                            key={a.id}
                            className="flex items-center gap-2 text-xs text-text-primary cursor-pointer hover:opacity-80"
                          >
                            <input
                              type="checkbox"
                              checked={selectedAccountIds.includes(a.id)}
                              onChange={() => handleToggleAccount(a.id)}
                              className="rounded text-brand-500 focus:ring-brand-500 cursor-pointer"
                            />
                            <span>{a.account_name}</span>
                          </label>
                        ))}
                      </div>
                    </div>
                  )}
                </>
              )}

              <div className="flex items-center justify-end gap-2 pt-2 border-t border-border-default">
                <button
                  type="button"
                  onClick={() => setSelectedApproveRequest(null)}
                  className="px-3.5 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover rounded-xl transition cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={approveMutation.isPending}
                  className="px-4 py-2 text-xs font-bold text-white bg-brand-500 hover:bg-brand-600 rounded-xl transition cursor-pointer disabled:opacity-50 inline-flex items-center gap-1.5 shadow-2xs"
                >
                  {approveMutation.isPending && (
                    <RefreshCw className="h-3 w-3 animate-spin" />
                  )}
                  <span>{approveMutation.isPending ? "Approving..." : "Confirm & Provision User"}</span>
                </button>
              </div>
            </form>
          </div>
        </Modal>
      )}

      {/* Reject Modal Dialog */}
      {selectedRejectRequest && (
        <Modal
          isOpen={Boolean(selectedRejectRequest)}
          onClose={() => setSelectedRejectRequest(null)}
          title="Reject Account Request"
          subtitle={`Decline registration for ${selectedRejectRequest.fullName}.`}
          isSubmitting={rejectMutation.isPending}
          disableBackdropClick={rejectMutation.isPending}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-4">
            {actionError && (
              <div className="flex items-center gap-2 rounded-md border border-border-danger bg-danger-subtle p-2 text-xs text-text-danger">
                <AlertTriangle className="h-4 w-4 shrink-0" />
                <span>{actionError}</span>
              </div>
            )}

            <form onSubmit={handleConfirmReject} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-text-primary mb-1">
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
                  className={`w-full p-2.5 text-xs rounded-xl border bg-surface text-text-primary focus:outline-hidden ${
                    rejectReasonError
                      ? "border-border-danger focus:border-border-danger"
                      : "border-border-default focus:border-border-brand"
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
                  <p className="mt-1 text-2xs text-text-danger">
                    Please select a rejection reason.
                  </p>
                )}
              </div>

              <div>
                <label className="block text-xs font-bold text-text-primary mb-1">
                  Additional Notes (Optional)
                </label>
                <textarea
                  rows={2}
                  value={rejectionRemarks}
                  onChange={(e) => setRejectionRemarks(e.target.value)}
                  placeholder="Details for user audit record"
                  className="w-full p-2 text-xs rounded-xl border border-border-default bg-surface text-text-primary placeholder:text-text-muted focus:outline-hidden focus:border-border-brand"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-2 border-t border-border-default">
                <button
                  type="button"
                  onClick={() => setSelectedRejectRequest(null)}
                  className="px-3.5 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover rounded-xl transition cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={rejectMutation.isPending}
                  className="px-4 py-2 text-xs font-bold text-white bg-danger-button hover:bg-danger-button-hover rounded-xl transition cursor-pointer disabled:opacity-50 inline-flex items-center gap-1.5 shadow-2xs"
                >
                  {rejectMutation.isPending && (
                    <RefreshCw className="h-3 w-3 animate-spin" />
                  )}
                  <span>{rejectMutation.isPending ? "Rejecting..." : "Confirm Rejection"}</span>
                </button>
              </div>
            </form>
          </div>
        </Modal>
      )}
    </div>
  );
}
