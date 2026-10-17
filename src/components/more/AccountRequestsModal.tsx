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
  X,
} from "lucide-react";
import {
  useAccountApprovalQueue,
  useApproveAccountRequest,
  useRejectAccountRequest,
  type AccountRequestItem,
  type AccountRequestStatus,
} from "@/lib/queries/accountRequests";
import { useRolesQuery, useGroupsQuery, useAccountsByGroupsQuery } from "@/lib/queries/users";

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

  if (!isOpen) return null;

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

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-xs animate-in fade-in duration-200">
      <div className="bg-white rounded-2xl shadow-2xl border border-slate-200 w-full max-w-4xl max-h-[90vh] flex flex-col overflow-hidden">
        {/* Header */}
        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between bg-slate-50/50">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-blue-100 text-blue-700 flex items-center justify-center font-bold">
              <UserCheck className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-base font-bold text-slate-900">Account Requests</h2>
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-blue-100 text-blue-800 uppercase tracking-wider">
                  Registration Queue
                </span>
              </div>
              <p className="text-xs text-slate-500">
                Review, approve, and provision newly registered accounts with role and operational scopes
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => refetch()}
              disabled={isFetching}
              className="p-2 hover:bg-slate-100 rounded-lg text-slate-500 hover:text-slate-700 transition cursor-pointer"
              title="Refresh requests"
            >
              <RefreshCw className={`w-4 h-4 ${isFetching ? "animate-spin text-blue-600" : ""}`} />
            </button>
            <button
              type="button"
              onClick={onClose}
              className="p-2 hover:bg-slate-100 rounded-lg text-slate-400 hover:text-slate-600 transition cursor-pointer"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
        </div>

        {/* Tab Strip */}
        <div className="px-6 border-b border-slate-200 flex items-center justify-between bg-white">
          <div className="flex items-center gap-4">
            {(["pending", "approved", "rejected"] as const).map((tab) => (
              <button
                key={tab}
                type="button"
                onClick={() => {
                  setActiveTab(tab);
                  setSelectedRequest(null);
                  setActionType(null);
                }}
                className={`py-3 text-xs font-bold capitalize border-b-2 transition cursor-pointer ${
                  activeTab === tab
                    ? "border-blue-600 text-blue-700"
                    : "border-transparent text-slate-500 hover:text-slate-800"
                }`}
              >
                <span>{tab}</span>
              </button>
            ))}
          </div>

          <div className="w-64 my-1 relative">
            <Search className="w-3.5 h-3.5 text-slate-400 absolute left-2.5 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              placeholder="Search request..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-8 pr-3 py-1.5 text-xs rounded-lg border border-slate-200 bg-white focus:outline-hidden focus:border-blue-500"
            />
          </div>
        </div>

        {/* Error Alert */}
        {errorMessage && (
          <div className="mx-6 mt-4 p-3 rounded-xl bg-rose-50 border border-rose-200 text-rose-800 text-xs flex items-center gap-2">
            <AlertCircle className="w-4 h-4 shrink-0" />
            <span>{errorMessage}</span>
          </div>
        )}

        {/* Content List */}
        <div className="p-6 flex-1 overflow-y-auto space-y-3">
          {isLoading ? (
            <div className="py-16 text-center text-xs text-slate-400 flex flex-col items-center gap-2">
              <RefreshCw className="w-5 h-5 animate-spin text-blue-600" />
              <span>Loading account requests...</span>
            </div>
          ) : filteredRequests.length === 0 ? (
            <div className="py-16 text-center text-xs text-slate-400">
              No {activeTab} account registration requests found.
            </div>
          ) : (
            <div className="divide-y divide-slate-100 border border-slate-200 rounded-2xl overflow-hidden bg-white">
              {filteredRequests.map((req) => (
                <div
                  key={req.id}
                  className="p-4 flex flex-col md:flex-row md:items-center justify-between gap-4 hover:bg-slate-50/50 transition-colors"
                >
                  <div className="space-y-1">
                    <div className="flex items-center gap-2">
                      <span className="text-xs font-bold text-slate-900">{req.fullName}</span>
                      <span className="px-2 py-0.2 rounded-full text-[9px] font-bold uppercase tracking-wider bg-blue-50 text-blue-700 border border-blue-200">
                        {req.requestedRoleName || "Requested Role"}
                      </span>
                      {req.daysPending !== null && req.status === "pending" && (
                        <span className="px-2 py-0.2 rounded-full text-[9px] font-bold bg-amber-50 text-amber-700 border border-amber-200 flex items-center gap-1">
                          <Clock className="w-3 h-3" />
                          <span>{req.daysPending}d pending</span>
                        </span>
                      )}
                    </div>

                    <div className="flex flex-wrap items-center gap-3 text-[11px] text-slate-500">
                      <span className="flex items-center gap-1">
                        <Mail className="w-3 h-3 text-slate-400" />
                        <span>{req.email}</span>
                      </span>
                      {req.mobileNumber && (
                        <>
                          <span>•</span>
                          <span className="flex items-center gap-1">
                            <Phone className="w-3 h-3 text-slate-400" />
                            <span>{req.mobileNumber}</span>
                          </span>
                        </>
                      )}
                      <span>•</span>
                      <span>
                        Scope:{" "}
                        <strong className="text-slate-700">
                          {req.requestedScopeType === "global"
                            ? "Global"
                            : req.requestedGroupNames.length > 0
                            ? req.requestedGroupNames.join(", ")
                            : "Scoped"}
                        </strong>
                      </span>
                    </div>

                    {req.notes && (
                      <p className="text-[11px] text-slate-400 italic mt-1">
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
                        className="px-3 py-1.5 text-xs font-bold text-white bg-emerald-600 hover:bg-emerald-700 rounded-xl transition cursor-pointer disabled:opacity-50 flex items-center gap-1"
                      >
                        <UserCheck className="w-3.5 h-3.5" />
                        <span>Approve</span>
                      </button>
                      <button
                        type="button"
                        onClick={() => handleOpenReject(req)}
                        disabled={!isSuperAdmin}
                        className="px-3 py-1.5 text-xs font-bold text-rose-700 bg-rose-50 hover:bg-rose-100 border border-rose-200 rounded-xl transition cursor-pointer disabled:opacity-50 flex items-center gap-1"
                      >
                        <UserX className="w-3.5 h-3.5" />
                        <span>Reject</span>
                      </button>
                    </div>
                  )}

                  {/* Details for Approved / Rejected */}
                  {req.status === "approved" && (
                    <div className="text-right text-[11px] text-slate-500">
                      <div className="font-semibold text-emerald-700">
                        Assigned: {req.assignedRoleName} ({req.assignedScopeType})
                      </div>
                      <div className="text-[10px] text-slate-400">
                        Approved by {req.reviewerDisplayName || "Super Admin"} on{" "}
                        {new Date(req.reviewedAt || req.updatedAt || "").toLocaleDateString()}
                      </div>
                    </div>
                  )}

                  {req.status === "rejected" && (
                    <div className="text-right text-[11px] text-slate-500">
                      <div className="font-semibold text-rose-700">
                        Reason: {req.rejectionReason || "Declined"}
                      </div>
                      <div className="text-[10px] text-slate-400">
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

        {/* Footer */}
        <div className="px-6 py-3 border-t border-slate-200 bg-slate-50/70 flex items-center justify-between text-xs text-slate-500">
          <span>Backend RPC: approve_account_request_v2</span>
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-semibold text-slate-700 bg-white hover:bg-slate-100 border border-slate-200 rounded-xl transition cursor-pointer"
          >
            Close
          </button>
        </div>
      </div>

      {/* Approve Modal Dialog */}
      {actionType === "approve" && selectedRequest && (
        <div className="fixed inset-0 z-60 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-xs animate-in fade-in duration-150">
          <div className="bg-white rounded-2xl shadow-xl border border-slate-200 w-full max-w-lg p-5 space-y-4 max-h-[85vh] flex flex-col">
            <div>
              <h3 className="text-sm font-bold text-slate-900">Approve Account Registration</h3>
              <p className="text-xs text-slate-500 mt-0.5">
                Assign role and operational scope for <strong>{selectedRequest.fullName}</strong> (
                {selectedRequest.email})
              </p>
            </div>

            <form onSubmit={handleApproveSubmit} className="space-y-4 flex-1 overflow-y-auto pr-1">
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">
                  Assigned Role *
                </label>
                <select
                  required
                  value={selectedRoleId}
                  onChange={(e) => setSelectedRoleId(e.target.value)}
                  className="w-full p-2.5 text-xs rounded-xl border border-slate-200 bg-white focus:outline-hidden focus:border-blue-500"
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
                <label className="block text-xs font-bold text-slate-700 mb-1">Scope Mode *</label>
                <div className="grid grid-cols-2 gap-2">
                  <button
                    type="button"
                    onClick={() => setScopeType("scoped")}
                    className={`py-2 text-xs font-semibold rounded-xl border transition cursor-pointer ${
                      scopeType === "scoped"
                        ? "border-blue-600 bg-blue-50 text-blue-700"
                        : "border-slate-200 bg-white text-slate-700 hover:bg-slate-50"
                    }`}
                  >
                    Scoped Groups
                  </button>
                  <button
                    type="button"
                    onClick={() => setScopeType("global")}
                    className={`py-2 text-xs font-semibold rounded-xl border transition cursor-pointer ${
                      scopeType === "global"
                        ? "border-blue-600 bg-blue-50 text-blue-700"
                        : "border-slate-200 bg-white text-slate-700 hover:bg-slate-50"
                    }`}
                  >
                    Global (All Groups)
                  </button>
                </div>
              </div>

              {scopeType === "scoped" && (
                <>
                  <div className="space-y-2">
                    <label className="block text-xs font-bold text-slate-700">
                      Assign Operational Groups *
                    </label>
                    <div className="border border-slate-200 rounded-xl p-3 max-h-36 overflow-y-auto space-y-1.5 bg-slate-50/50">
                      {groups.map((g) => (
                        <label
                          key={g.id}
                          className="flex items-center gap-2 text-xs text-slate-700 cursor-pointer hover:text-slate-900"
                        >
                          <input
                            type="checkbox"
                            checked={selectedGroupIds.includes(g.id)}
                            onChange={() => handleToggleGroup(g.id)}
                            className="rounded text-blue-600 focus:ring-blue-500"
                          />
                          <span>{g.name}</span>
                        </label>
                      ))}
                    </div>
                  </div>

                  {accounts.length > 0 && (
                    <div className="space-y-2">
                      <label className="block text-xs font-bold text-slate-700">
                        Assign Specific Accounts (Optional)
                      </label>
                      <div className="border border-slate-200 rounded-xl p-3 max-h-36 overflow-y-auto space-y-1.5 bg-slate-50/50">
                        {accounts.map((a) => (
                          <label
                            key={a.id}
                            className="flex items-center gap-2 text-xs text-slate-700 cursor-pointer hover:text-slate-900"
                          >
                            <input
                              type="checkbox"
                              checked={selectedAccountIds.includes(a.id)}
                              onChange={() => handleToggleAccount(a.id)}
                              className="rounded text-blue-600 focus:ring-blue-500"
                            />
                            <span>{a.account_name}</span>
                          </label>
                        ))}
                      </div>
                    </div>
                  )}
                </>
              )}

              <div className="flex items-center justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setActionType(null)}
                  className="px-3.5 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-xl transition cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={approveMutation.isPending}
                  className="px-4 py-2 text-xs font-bold text-white bg-emerald-600 hover:bg-emerald-700 rounded-xl transition cursor-pointer disabled:opacity-50"
                >
                  {approveMutation.isPending ? "Approving..." : "Confirm & Provision User"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Reject Modal Dialog */}
      {actionType === "reject" && selectedRequest && (
        <div className="fixed inset-0 z-60 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-xs animate-in fade-in duration-150">
          <div className="bg-white rounded-2xl shadow-xl border border-slate-200 w-full max-w-md p-5 space-y-4">
            <div>
              <h3 className="text-sm font-bold text-slate-900">Reject Account Request</h3>
              <p className="text-xs text-slate-500 mt-0.5">
                Decline registration for <strong>{selectedRequest.fullName}</strong>.
              </p>
            </div>

            <form onSubmit={handleRejectSubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">
                  Rejection Reason *
                </label>
                <select
                  required
                  value={rejectionReason}
                  onChange={(e) => setRejectionReason(e.target.value)}
                  className="w-full p-2.5 text-xs rounded-xl border border-slate-200 bg-white focus:outline-hidden focus:border-rose-500"
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
                <label className="block text-xs font-bold text-slate-700 mb-1">
                  Additional Notes (Optional)
                </label>
                <textarea
                  rows={2}
                  value={rejectionRemarks}
                  onChange={(e) => setRejectionRemarks(e.target.value)}
                  placeholder="Details for user audit record"
                  className="w-full p-2 text-xs rounded-xl border border-slate-200 bg-white focus:outline-hidden focus:border-rose-500"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setActionType(null)}
                  className="px-3.5 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-xl transition cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={rejectMutation.isPending}
                  className="px-4 py-2 text-xs font-bold text-white bg-rose-600 hover:bg-rose-700 rounded-xl transition cursor-pointer disabled:opacity-50"
                >
                  {rejectMutation.isPending ? "Rejecting..." : "Confirm Rejection"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
