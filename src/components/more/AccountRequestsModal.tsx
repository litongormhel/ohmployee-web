"use client";

import { useState } from "react";
import {
  AlertCircle,
  Clock,
  Mail,
  Phone,
  RefreshCw,
  Search,
  UserCheck,
  UserX,
} from "lucide-react";
import {
  useAccountApprovalQueue,
  useApproveAccountRequest,
  useRejectAccountRequest,
  type AccountRequestItem,
  type AccountRequestStatus,
} from "@/lib/queries/accountRequests";
import { useRolesQuery, useGroupsQuery, useAccountsByGroupsQuery } from "@/lib/queries/users";
import { Modal } from "@/components/shared/Modal";

export interface AccountRequestsModalProps {
  isOpen: boolean;
  onClose: () => void;
  isSuperAdmin: boolean;
}

export function AccountRequestsModal({
  isOpen,
  onClose,
  isSuperAdmin,
}: AccountRequestsModalProps) {
  const [activeTab, setActiveTab] = useState<AccountRequestStatus>("pending");
  const [searchQuery, setSearchQuery] = useState("");

  // Approval / Rejection Action States
  const [selectedRequest, setSelectedRequest] = useState<AccountRequestItem | null>(null);
  const [actionType, setActionType] = useState<"approve" | "reject" | null>(null);

  // Approval Form Inputs
  const [selectedRoleId, setSelectedRoleId] = useState<string>("");
  const [scopeType, setScopeType] = useState<"global" | "scoped">("scoped");
  const [selectedGroupIds, setSelectedGroupIds] = useState<string[]>([]);
  const [selectedAccountIds, setSelectedAccountIds] = useState<string[]>([]);

  // Rejection Form Inputs
  const [rejectionReason, setRejectionReason] = useState<string>("");
  const [rejectionRemarks, setRejectionRemarks] = useState<string>("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Queries
  const {
    data: requests = [],
    isLoading,
    refetch,
    isFetching,
  } = useAccountApprovalQueue(activeTab);

  const { data: roles = [] } = useRolesQuery();
  const { data: groups = [] } = useGroupsQuery();
  const { data: accounts = [] } = useAccountsByGroupsQuery(selectedGroupIds);

  const approveMutation = useApproveAccountRequest();
  const rejectMutation = useRejectAccountRequest();

  // Filter roles to exclude Super Admin and Head Admin (as per Mobile security standards)
  const assignableRoles = roles.filter(
    (r) => r.name !== "Super Admin" && r.name !== "Head Admin"
  );

  const filteredRequests = requests.filter((r) => {
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    return (
      r.fullName.toLowerCase().includes(q) ||
      r.email.toLowerCase().includes(q) ||
      (r.mobileNumber && r.mobileNumber.toLowerCase().includes(q)) ||
      (r.requestedRoleName && r.requestedRoleName.toLowerCase().includes(q))
    );
  });

  const handleOpenApprove = (req: AccountRequestItem) => {
    setSelectedRequest(req);
    setActionType("approve");
    setErrorMessage(null);
    setSelectedRoleId(req.requestedRoleId || assignableRoles[0]?.id || "");
    setScopeType(req.requestedScopeType || "scoped");
    setSelectedGroupIds(req.requestedGroupIds || []);
    setSelectedAccountIds(req.requestedAccountIds || []);
  };

  const handleOpenReject = (req: AccountRequestItem) => {
    setSelectedRequest(req);
    setActionType("reject");
    setErrorMessage(null);
    setRejectionReason("");
    setRejectionRemarks("");
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

  const handleApproveSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedRequest) return;
    if (!selectedRoleId) {
      setErrorMessage("Please select a role to assign.");
      return;
    }
    if (scopeType === "scoped" && selectedGroupIds.length === 0) {
      setErrorMessage("Please assign at least one group for scoped access.");
      return;
    }

    try {
      await approveMutation.mutateAsync({
        requestId: selectedRequest.id,
        roleId: selectedRoleId,
        scopeType,
        groupIds: scopeType === "scoped" ? selectedGroupIds : [],
        accountIds: scopeType === "scoped" ? selectedAccountIds : [],
      });
      setSelectedRequest(null);
      setActionType(null);
    } catch (err: unknown) {
      setErrorMessage((err as Error)?.message || "Failed to approve account request.");
    }
  };

  const handleRejectSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedRequest) return;
    if (!rejectionReason.trim()) {
      setErrorMessage("Please select or enter a rejection reason.");
      return;
    }

    try {
      await rejectMutation.mutateAsync({
        requestId: selectedRequest.id,
        reason: rejectionReason.trim(),
        remarks: rejectionRemarks.trim() || undefined,
      });
      setSelectedRequest(null);
      setActionType(null);
    } catch (err: unknown) {
      setErrorMessage((err as Error)?.message || "Failed to reject account request.");
    }
  };

  const isApproveDirty =
    Boolean(selectedRequest) &&
    (selectedRoleId !== (selectedRequest?.requestedRoleId || assignableRoles[0]?.id || "") ||
      selectedGroupIds.length !== (selectedRequest?.requestedGroupIds || []).length);

  const isRejectDirty = rejectionReason.trim().length > 0 || rejectionRemarks.trim().length > 0;

  return (
    <>
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title="Account Requests"
        subtitle="Review, approve, and provision newly registered accounts with role and operational scopes"
        icon={UserCheck}
        maxWidthClass="max-w-4xl"
        footer={
          <div className="flex w-full items-center justify-between text-xs text-text-muted">
            <span>Backend RPC: approve_account_request_v2</span>
            <button
              type="button"
              onClick={onClose}
              className="rounded-xl border border-border-default bg-surface-primary px-4 py-2 text-xs font-semibold text-text-primary transition hover:bg-surface-hover cursor-pointer"
            >
              Close
            </button>
          </div>
        }
      >
        <div className="space-y-4">
          {/* Controls Bar: Tab Strip + Search + Refresh */}
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-border-default pb-3">
            <div className="flex items-center gap-2">
              {(["pending", "approved", "rejected"] as const).map((tab) => (
                <button
                  key={tab}
                  type="button"
                  onClick={() => {
                    setActiveTab(tab);
                    setSelectedRequest(null);
                    setActionType(null);
                  }}
                  className={`px-3 py-1.5 text-xs font-semibold rounded-lg capitalize transition cursor-pointer ${
                    activeTab === tab
                      ? "bg-brand-50 text-brand-900 border border-brand-200"
                      : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
                  }`}
                >
                  {tab}
                </button>
              ))}
            </div>

            <div className="flex items-center gap-2">
              <div className="relative w-full sm:w-60">
                <Search className="w-3.5 h-3.5 text-text-muted absolute left-2.5 top-1/2 -translate-y-1/2" />
                <input
                  type="text"
                  placeholder="Search request..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="w-full pl-8 pr-3 py-1.5 text-xs rounded-xl border border-border-default bg-surface-primary text-text-primary placeholder:text-text-muted focus:outline-hidden focus:border-brand-primary"
                />
              </div>

              <button
                type="button"
                onClick={() => refetch()}
                disabled={isFetching}
                className="p-2 rounded-xl border border-border-default bg-surface-primary hover:bg-surface-hover text-text-secondary transition cursor-pointer disabled:opacity-50"
                title="Refresh requests"
              >
                <RefreshCw className={`w-4 h-4 ${isFetching ? "animate-spin text-brand-primary" : ""}`} />
              </button>
            </div>
          </div>

          {/* Error Alert */}
          {errorMessage && (
            <div className="p-3 rounded-xl bg-danger-surface border border-danger-border text-danger-text text-xs flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0" />
              <span>{errorMessage}</span>
            </div>
          )}

          {/* Requests Stream */}
          <div className="max-h-[58vh] overflow-y-auto space-y-2 pr-1">
            {isLoading ? (
              <div className="py-16 text-center text-xs text-text-muted flex flex-col items-center gap-2">
                <RefreshCw className="w-5 h-5 animate-spin text-brand-primary" />
                <span>Loading account requests...</span>
              </div>
            ) : filteredRequests.length === 0 ? (
              <div className="py-16 text-center text-xs text-text-muted border border-dashed border-border-default rounded-2xl">
                No {activeTab} account registration requests found.
              </div>
            ) : (
              <div className="divide-y divide-border-subtle border border-border-default rounded-2xl overflow-hidden bg-surface-primary">
                {filteredRequests.map((req) => (
                  <div
                    key={req.id}
                    className="p-4 flex flex-col md:flex-row md:items-center justify-between gap-4 hover:bg-surface-hover transition-colors"
                  >
                    <div className="space-y-1">
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-semibold text-text-primary">{req.fullName}</span>
                        <span className="px-2 py-0.5 rounded-full text-xs font-medium uppercase tracking-wider bg-surface-subtle text-text-secondary border border-border-default">
                          {req.requestedRoleName || "Requested Role"}
                        </span>
                        {req.daysPending !== null && req.status === "pending" && (
                          <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-surface-subtle text-text-secondary border border-border-default flex items-center gap-1">
                            <Clock className="w-3 h-3 text-text-muted" />
                            <span>{req.daysPending}d pending</span>
                          </span>
                        )}
                      </div>

                      <div className="flex flex-wrap items-center gap-3 text-xs text-text-secondary">
                        <span className="flex items-center gap-1">
                          <Mail className="w-3 h-3 text-text-muted" />
                          <span>{req.email}</span>
                        </span>
                        {req.mobileNumber && (
                          <>
                            <span>•</span>
                            <span className="flex items-center gap-1">
                              <Phone className="w-3 h-3 text-text-muted" />
                              <span>{req.mobileNumber}</span>
                            </span>
                          </>
                        )}
                        <span>•</span>
                        <span>
                          Scope:{" "}
                          <strong className="text-text-primary">
                            {req.requestedScopeType === "global"
                              ? "Global"
                              : req.requestedGroupNames.length > 0
                              ? req.requestedGroupNames.join(", ")
                              : "Scoped"}
                          </strong>
                        </span>
                      </div>

                      {req.notes && (
                        <p className="text-xs text-text-muted italic mt-1">
                          &quot;{req.notes}&quot;
                        </p>
                      )}
                    </div>

                    {/* Actions for Pending */}
                    {req.status === "pending" && (
                      <div className="flex items-center gap-2 self-start md:self-auto shrink-0">
                        <button
                          type="button"
                          onClick={() => handleOpenApprove(req)}
                          disabled={!isSuperAdmin}
                          className="px-3.5 py-1.5 text-xs font-semibold text-surface-primary bg-brand-primary hover:bg-brand-primary-hover rounded-xl transition cursor-pointer disabled:opacity-50 flex items-center gap-1.5"
                        >
                          <UserCheck className="w-3.5 h-3.5" />
                          <span>Approve</span>
                        </button>
                        <button
                          type="button"
                          onClick={() => handleOpenReject(req)}
                          disabled={!isSuperAdmin}
                          className="px-3.5 py-1.5 text-xs font-semibold text-danger-text bg-danger-surface hover:bg-danger-border/40 border border-danger-border rounded-xl transition cursor-pointer disabled:opacity-50 flex items-center gap-1.5"
                        >
                          <UserX className="w-3.5 h-3.5" />
                          <span>Reject</span>
                        </button>
                      </div>
                    )}

                    {/* Details for Approved / Rejected */}
                    {req.status === "approved" && (
                      <div className="text-right text-xs text-text-secondary">
                        <div className="font-semibold text-text-primary">
                          Assigned: {req.assignedRoleName} ({req.assignedScopeType})
                        </div>
                        <div className="text-xs text-text-muted">
                          Approved by {req.reviewerDisplayName || "Super Admin"} on{" "}
                          {new Date(req.reviewedAt || req.updatedAt || "").toLocaleDateString()}
                        </div>
                      </div>
                    )}

                    {req.status === "rejected" && (
                      <div className="text-right text-xs text-text-secondary">
                        <div className="font-semibold text-danger-text">
                          Reason: {req.rejectionReason || "Declined"}
                        </div>
                        <div className="text-xs text-text-muted">
                          Rejected by {req.reviewerDisplayName || "Super Admin"} on{" "}
                          {new Date(req.rejectedAt || req.updatedAt || "").toLocaleDateString()}
                        </div>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </Modal>

      {/* Approve Modal Dialog */}
      <Modal
        isOpen={actionType === "approve" && !!selectedRequest}
        onClose={() => setActionType(null)}
        title="Approve Account Registration"
        subtitle={
          selectedRequest
            ? `Assign role and operational scope for ${selectedRequest.fullName} (${selectedRequest.email})`
            : undefined
        }
        icon={UserCheck}
        maxWidthClass="max-w-lg"
        isSubmitting={approveMutation.isPending}
        disableBackdropClick={approveMutation.isPending}
        isDirty={isApproveDirty}
      >
        {selectedRequest && (
          <form onSubmit={handleApproveSubmit} className="space-y-4">
            <div>
              <label className="block text-xs font-bold text-text-primary mb-1">
                Assigned Role *
              </label>
              <select
                required
                value={selectedRoleId}
                onChange={(e) => setSelectedRoleId(e.target.value)}
                className="w-full p-2.5 text-xs rounded-xl border border-border-default bg-surface-primary text-text-primary focus:outline-hidden focus:border-brand-primary"
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
                      ? "border-brand-primary bg-brand-50 text-brand-900"
                      : "border-border-default bg-surface-primary text-text-secondary hover:bg-surface-hover"
                  }`}
                >
                  Scoped Groups
                </button>
                <button
                  type="button"
                  onClick={() => setScopeType("global")}
                  className={`py-2 text-xs font-semibold rounded-xl border transition cursor-pointer ${
                    scopeType === "global"
                      ? "border-brand-primary bg-brand-50 text-brand-900"
                      : "border-border-default bg-surface-primary text-text-secondary hover:bg-surface-hover"
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
                        className="flex items-center gap-2 text-xs text-text-secondary cursor-pointer hover:text-text-primary"
                      >
                        <input
                          type="checkbox"
                          checked={selectedGroupIds.includes(g.id)}
                          onChange={() => handleToggleGroup(g.id)}
                          className="rounded border-border-default text-brand-primary focus:ring-brand-primary"
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
                          className="flex items-center gap-2 text-xs text-text-secondary cursor-pointer hover:text-text-primary"
                        >
                          <input
                            type="checkbox"
                            checked={selectedAccountIds.includes(a.id)}
                            onChange={() => handleToggleAccount(a.id)}
                            className="rounded border-border-default text-brand-primary focus:ring-brand-primary"
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
                onClick={() => setActionType(null)}
                className="px-3.5 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover rounded-xl transition cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={approveMutation.isPending}
                className="px-4 py-2 text-xs font-semibold text-surface-primary bg-brand-primary hover:bg-brand-primary-hover rounded-xl transition cursor-pointer disabled:opacity-50"
              >
                {approveMutation.isPending ? "Approving..." : "Confirm & Provision User"}
              </button>
            </div>
          </form>
        )}
      </Modal>

      {/* Reject Modal Dialog */}
      <Modal
        isOpen={actionType === "reject" && !!selectedRequest}
        onClose={() => setActionType(null)}
        title="Reject Account Request"
        subtitle={
          selectedRequest
            ? `Decline registration for ${selectedRequest.fullName}.`
            : undefined
        }
        icon={UserX}
        maxWidthClass="max-w-md"
        isSubmitting={rejectMutation.isPending}
        disableBackdropClick={rejectMutation.isPending}
        isDirty={isRejectDirty}
      >
        {selectedRequest && (
          <form onSubmit={handleRejectSubmit} className="space-y-4">
            <div>
              <label className="block text-xs font-bold text-text-primary mb-1">
                Rejection Reason *
              </label>
              <select
                required
                value={rejectionReason}
                onChange={(e) => setRejectionReason(e.target.value)}
                className="w-full p-2.5 text-xs rounded-xl border border-border-default bg-surface-primary text-text-primary focus:outline-hidden focus:border-danger-border"
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
                className="w-full p-2 text-xs rounded-xl border border-border-default bg-surface-primary text-text-primary focus:outline-hidden focus:border-danger-border"
              />
            </div>

            <div className="flex items-center justify-end gap-2 pt-2 border-t border-border-default">
              <button
                type="button"
                onClick={() => setActionType(null)}
                className="px-3.5 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover rounded-xl transition cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={rejectMutation.isPending}
                className="px-4 py-2 text-xs font-semibold text-surface-primary bg-danger hover:bg-danger-hover rounded-xl transition cursor-pointer disabled:opacity-50"
              >
                {rejectMutation.isPending ? "Rejecting..." : "Confirm Rejection"}
              </button>
            </div>
          </form>
        )}
      </Modal>
    </>
  );
}
