"use client";

import { useState, useMemo } from "react";


import {
  Key,
  Clock,
  CheckCircle2,
  AlertTriangle,
  Plus,
  RefreshCw,
  Search,
  ShieldAlert,
  Calendar,
  Layers,
  Store,
  AppWindow,
  RotateCcw,
  User,
  Info,
} from "lucide-react";
import { useCurrentUser } from "@/lib/auth";
import {
  useTempPermissionsQuery,
  useGrantTempPermissionMutation,
  useRevokeTempPermissionMutation,
  type TempPermissionOverride,
  type TempPermissionScopeType,
} from "@/lib/queries/tempPermissions";
import {
  useUsersList,
  useGroupsQuery,
  type UserProfileItem,
} from "@/lib/queries/users";
import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { Modal } from "@/components/shared/Modal";

export interface TempPermissionModalProps {
  isOpen: boolean;
  onClose: () => void;
  presetUser?: UserProfileItem | null;
}

const AVAILABLE_MODULES = [
  { id: "cencom", name: "CENCOM Operations Hub", defaultGroup: "Global HQ" },
  { id: "approvals", name: "Approvals & Deactivations", defaultGroup: "Global HQ" },
  { id: "plantilla", name: "Plantilla & Pool Hub", defaultGroup: "Global HQ" },
  { id: "hremploc", name: "HR Emploc & Movements", defaultGroup: "Global HQ" },
  { id: "reports", name: "Operational Reports Center", defaultGroup: "Global HQ" },
  { id: "users", name: "User Management (View Only)", defaultGroup: "Global HQ" },
];

export function TempPermissionModal({
  isOpen,
  onClose,
  presetUser,
}: TempPermissionModalProps) {
  const currentUser = useCurrentUser();

  // Role Level Guards:
  // Super Admin (100) or Head Admin (90)
  const callerRoleLevel = useMemo(() => {
    const roleKey = (
      currentUser?.roleKey ||
      currentUser?.roleName ||
      ""
    ).toLowerCase();
    if (roleKey.includes("super_admin") || roleKey === "super admin") return 100;
    if (roleKey.includes("head_admin") || roleKey === "head admin") return 90;
    return 50;
  }, [currentUser]);

  const canManageOverrides = callerRoleLevel >= 90;

  // Active Tab: "active" | "history" | "grant"
  const [activeTab, setActiveTab] = useState<"active" | "history" | "grant">("active");

  // Filter & Search states
  const [filterUserOnly, setFilterUserOnly] = useState<boolean>(() => Boolean(presetUser));
  const [searchQuery, setSearchQuery] = useState("");

  // Track presetUser prop changes
  const [prevPresetUserId, setPrevPresetUserId] = useState<string | null>(presetUser?.id ?? null);
  if (presetUser && presetUser.id !== prevPresetUserId) {
    setPrevPresetUserId(presetUser.id);
    setFilterUserOnly(true);
  }

  // Queries
  const activeUserIdFilter = filterUserOnly && presetUser ? presetUser.id : undefined;
  const {
    data: permissionsData,
    isLoading: isPermissionsLoading,
    refetch,
    isFetching,
  } = useTempPermissionsQuery(activeUserIdFilter);

  const { data: allUsers = [] } = useUsersList();
  const { data: allGroups = [] } = useGroupsQuery();

  // Accounts Query
  const { data: allAccounts = [] } = useQuery({
    queryKey: ["temp-permission-accounts"],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("accounts")
        .select("id, account_name, group_id, groups(group_name)")
        .eq("is_active", true)
        .order("account_name");
      if (error) return [];
      return (data ?? []) as {
        id: string;
        account_name: string;
        group_id: string;
        groups?: { group_name?: string } | { group_name?: string }[] | null;
      }[];
    },
    staleTime: 5 * 60 * 1000,
    enabled: isOpen,
  });

  // Mutations
  const grantMutation = useGrantTempPermissionMutation();
  const revokeMutation = useRevokeTempPermissionMutation();

  // Form State for Granting Override
  const [selectedTargetUserId, setSelectedTargetUserId] = useState<string>(
    () => presetUser?.id ?? "",
  );
  const [prevFormPresetId, setPrevFormPresetId] = useState<string | null>(presetUser?.id ?? null);
  if (presetUser && presetUser.id !== prevFormPresetId) {
    setPrevFormPresetId(presetUser.id);
    setSelectedTargetUserId(presetUser.id);
  }

  const [scopeType, setScopeType] = useState<TempPermissionScopeType>("group");
  const [selectedGroupNames, setSelectedGroupNames] = useState<string[]>([]);
  const [selectedAccountIds, setSelectedAccountIds] = useState<string[]>([]);
  const [selectedModuleIds, setSelectedModuleIds] = useState<string[]>([]);
  const [presetDurationDays, setPresetDurationDays] = useState<number>(3);
  const [customExpiryDate, setCustomExpiryDate] = useState<string>(() => {
    const d = new Date();
    d.setDate(d.getDate() + 3);
    d.setHours(23, 59, 0, 0);
    const pad = (n: number) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(
      d.getDate(),
    )}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  });
  const [reason, setReason] = useState<string>("");
  const [notifyUser, setNotifyUser] = useState<boolean>(true);
  const [formError, setFormError] = useState<string | null>(null);
  const [formSuccess, setFormSuccess] = useState<string | null>(null);

  // Revoke Dialog State
  const [revokingItem, setRevokingItem] = useState<TempPermissionOverride | null>(null);
  const [revokeReason, setRevokeReason] = useState<string>("");
  const [isRevoking, setIsRevoking] = useState<boolean>(false);

  // Group search & account search inside form
  const [scopeSearch, setScopeSearch] = useState<string>("");


  if (!isOpen) return null;

  const activeOverrides = permissionsData?.active ?? [];
  const historyOverrides = permissionsData?.history ?? [];

  // Filtered lists
  const filteredActive = activeOverrides.filter((item) => {
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    return (
      item.userFullName.toLowerCase().includes(q) ||
      (item.userEmail && item.userEmail.toLowerCase().includes(q)) ||
      item.userRole.toLowerCase().includes(q) ||
      item.additionalGroups.some((g) => g.toLowerCase().includes(q)) ||
      (item.reason && item.reason.toLowerCase().includes(q)) ||
      item.grantedBy.toLowerCase().includes(q)
    );
  });

  const filteredHistory = historyOverrides.filter((item) => {
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    return (
      item.userFullName.toLowerCase().includes(q) ||
      (item.userEmail && item.userEmail.toLowerCase().includes(q)) ||
      item.userRole.toLowerCase().includes(q) ||
      item.additionalGroups.some((g) => g.toLowerCase().includes(q)) ||
      (item.reason && item.reason.toLowerCase().includes(q)) ||
      item.grantedBy.toLowerCase().includes(q)
    );
  });

  // Current selected user details in grant form
  const selectedUserObj = allUsers.find((u) => u.id === selectedTargetUserId);

  // Handle Preset Duration Click
  const handleSelectPresetDuration = (days: number) => {
    setPresetDurationDays(days);
    const d = new Date();
    d.setDate(d.getDate() + days);
    d.setHours(23, 59, 0, 0);
    const pad = (n: number) => String(n).padStart(2, "0");
    const formatted = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(
      d.getDate(),
    )}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
    setCustomExpiryDate(formatted);
  };

  // Toggle group selection
  const handleToggleGroup = (groupName: string) => {
    setSelectedGroupNames((prev) =>
      prev.includes(groupName)
        ? prev.filter((g) => g !== groupName)
        : [...prev, groupName],
    );
  };

  // Toggle account selection
  const handleToggleAccount = (accountId: string) => {
    setSelectedAccountIds((prev) =>
      prev.includes(accountId)
        ? prev.filter((id) => id !== accountId)
        : [...prev, accountId],
    );
  };

  // Toggle module selection
  const handleToggleModule = (moduleId: string) => {
    setSelectedModuleIds((prev) =>
      prev.includes(moduleId)
        ? prev.filter((id) => id !== moduleId)
        : [...prev, moduleId],
    );
  };

  // Submit Grant
  const handleGrantSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setFormError(null);
    setFormSuccess(null);

    if (!selectedTargetUserId) {
      setFormError("Please select a target user.");
      return;
    }

    if (!reason.trim() || reason.trim().length < 5) {
      setFormError("A comprehensive audit justification (minimum 5 characters) is required.");
      return;
    }

    // Resolve additional groups based on scope type
    let finalGroups: string[] = [];
    let scopeItemLabels: string[] = [];

    if (scopeType === "group") {
      finalGroups = selectedGroupNames;
      scopeItemLabels = selectedGroupNames;
      if (finalGroups.length === 0) {
        setFormError("Please select at least one organizational group.");
        return;
      }
    } else if (scopeType === "account") {
      if (selectedAccountIds.length === 0) {
        setFormError("Please select at least one store/account.");
        return;
      }
      // Map selected account IDs to their respective group names
      const matchedGroups = new Set<string>();
      const accountNames: string[] = [];
      for (const aid of selectedAccountIds) {
        const acc = allAccounts.find((a) => a.id === aid);
        if (acc) {
          accountNames.push(acc.account_name);
          const gObj = Array.isArray(acc.groups) ? acc.groups[0] : acc.groups;
          if (gObj?.group_name) {
            matchedGroups.add(gObj.group_name);
          } else {
            // Find in allGroups by ID
            const g = allGroups.find((grp) => grp.id === acc.group_id);
            if (g?.name) matchedGroups.add(g.name);
          }
        }
      }
      finalGroups = Array.from(matchedGroups);
      if (finalGroups.length === 0) {
        // Fallback to first available group
        if (allGroups.length > 0) finalGroups.push(allGroups[0].name);
      }
      scopeItemLabels = accountNames;
    } else if (scopeType === "module") {
      if (selectedModuleIds.length === 0) {
        setFormError("Please select at least one module delegation.");
        return;
      }
      const matchedGroups = new Set<string>();
      const moduleNames: string[] = [];
      for (const mid of selectedModuleIds) {
        const mod = AVAILABLE_MODULES.find((m) => m.id === mid);
        if (mod) {
          moduleNames.push(mod.name);
          matchedGroups.add(mod.defaultGroup);
        }
      }
      finalGroups = Array.from(matchedGroups);
      scopeItemLabels = moduleNames;
    }

    // Expiry validation (max 30 days enforced by Supabase trigger)
    const expiryTimestamp = new Date(customExpiryDate).getTime();
    if (isNaN(expiryTimestamp) || expiryTimestamp <= Date.now()) {
      setFormError("Expiration date and time must be set in the future.");
      return;
    }

    const maxExpiryTimestamp = Date.now() + 30 * 24 * 60 * 60 * 1000;
    if (expiryTimestamp > maxExpiryTimestamp) {
      setFormError("Temporary override expiration cannot exceed 30 days from now.");
      return;
    }

    try {
      const callerName = currentUser?.displayName || "Super Admin";
      await grantMutation.mutateAsync({
        userId: selectedTargetUserId,
        scopeType,
        additionalGroups: finalGroups,
        scopeItems: scopeItemLabels,
        expiresAt: new Date(customExpiryDate).toISOString(),
        reason: reason.trim(),
        notifyUser,
        grantedBy: callerName,
      });

      setFormSuccess(
        `Temporary ${scopeType} override granted successfully. Will expire on ${new Date(
          customExpiryDate,
        ).toLocaleString()}.`,
      );

      // Reset form
      setSelectedGroupNames([]);
      setSelectedAccountIds([]);
      setSelectedModuleIds([]);
      setReason("");
      setScopeSearch("");

      // Switch to active tab after brief delay
      setTimeout(() => {
        setActiveTab("active");
        setFormSuccess(null);
      }, 1500);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Failed to grant temporary permission override.";
      setFormError(msg);
    }
  };

  // Confirm Revoke
  const handleExecuteRevoke = async () => {
    if (!revokingItem) return;
    setIsRevoking(true);
    try {
      const callerName = currentUser?.displayName || "Super Admin";
      await revokeMutation.mutateAsync({
        overrideId: revokingItem.id,
        revokedBy: callerName,
        revokeReason: revokeReason.trim() || "Manual administrative revocation",
        userId: revokingItem.userId,
      });
      setRevokingItem(null);
      setRevokeReason("");
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Failed to revoke temporary permission.";
      alert(msg);
    } finally {
      setIsRevoking(false);
    }
  };

  const isDirty = Boolean(reason || selectedGroupNames.length || selectedAccountIds.length || selectedModuleIds.length);
  const isBusy = grantMutation.isPending || isRevoking;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={
        <div className="flex items-center gap-2">
          <span>Temporary Permission Overrides</span>
          {presetUser && (
            <span className="inline-flex items-center gap-1 rounded-full border border-border-default bg-surface-subtle px-2 py-0.5 text-[11px] font-semibold text-text-primary">
              <User className="w-3 h-3" />
              {presetUser.normalizedName || presetUser.fullName}
            </span>
          )}
        </div>
      }
      subtitle="Manage, audit, and revoke time-bound group, account, and module delegations"
      icon={Key}
      maxWidthClass="max-w-3xl"
      isDirty={isDirty}
      isSubmitting={isBusy}
      disableBackdropClick={isBusy}
    >
      <div className="-mx-6 -my-4 flex flex-col">

        {/* Preset User Scope Banner & Tab Header */}
        <div className="px-6 pt-3 border-b border-border-default bg-white">
          {presetUser && (
            <div className="mb-3 flex items-center justify-between rounded-lg border border-border-default bg-surface-subtle p-2.5 text-xs text-text-primary">
              <div className="flex items-center gap-2">
                <Info className="h-4 w-4 shrink-0 text-text-secondary" />
                <span>
                  Viewing context for <strong>{presetUser.fullName}</strong> ({presetUser.roleName})
                </span>
              </div>
              <button
                type="button"
                onClick={() => setFilterUserOnly(!filterUserOnly)}
                className="font-semibold text-text-primary underline hover:text-text-primary cursor-pointer"
              >
                {filterUserOnly ? "Show All Users" : "Filter to This User"}
              </button>
            </div>
          )}

          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => setActiveTab("active")}
                className={`relative px-3.5 py-2 text-xs font-bold transition-colors cursor-pointer ${
                  activeTab === "active"
                    ? "text-brand-600"
                    : "text-text-secondary hover:text-text-primary"
                }`}
              >
                <div className="flex items-center gap-1.5">
                  <Clock className="w-3.5 h-3.5" />
                  <span>Active Overrides</span>
                  <span
                    className={`ml-1 px-1.5 py-0.5 rounded-full text-[10px] font-mono ${
                      activeTab === "active"
                        ? "bg-brand-100 text-brand-700"
                        : "bg-surface-muted text-text-secondary"
                    }`}
                  >
                    {activeOverrides.length}
                  </span>
                </div>
                {activeTab === "active" && (
                  <span className="absolute bottom-0 left-0 right-0 h-0.5 bg-brand-600 rounded-full" />
                )}
              </button>

              <button
                type="button"
                onClick={() => setActiveTab("history")}
                className={`relative px-3.5 py-2 text-xs font-bold transition-colors cursor-pointer ${
                  activeTab === "history"
                    ? "text-brand-600"
                    : "text-text-secondary hover:text-text-primary"
                }`}
              >
                <div className="flex items-center gap-1.5">
                  <RotateCcw className="w-3.5 h-3.5" />
                  <span>History & Revocations</span>
                  <span
                    className={`ml-1 px-1.5 py-0.5 rounded-full text-[10px] font-mono ${
                      activeTab === "history"
                        ? "bg-brand-100 text-brand-700"
                        : "bg-surface-muted text-text-secondary"
                    }`}
                  >
                    {historyOverrides.length}
                  </span>
                </div>
                {activeTab === "history" && (
                  <span className="absolute bottom-0 left-0 right-0 h-0.5 bg-brand-600 rounded-full" />
                )}
              </button>
            </div>

            {canManageOverrides && (
              <button
                type="button"
                onClick={() => setActiveTab("grant")}
                className={`inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors cursor-pointer ${
                  activeTab === "grant"
                    ? "bg-brand-600 text-white shadow-2xs"
                    : "bg-brand-50 text-brand-700 hover:bg-brand-100 border border-brand-200"
                }`}
              >
                <Plus className="w-3.5 h-3.5" />
                <span>Grant Override</span>
              </button>
            )}
          </div>
        </div>

        {/* Modal Body */}
        <div className="flex-1 overflow-y-auto p-6 bg-surface-subtle/50">
          {/* TAB 1: ACTIVE OVERRIDES */}
          {activeTab === "active" && (
            <div className="space-y-4">
              {/* Search Bar */}
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-text-muted" />
                <input
                  type="text"
                  placeholder="Filter active overrides by user, role, group, or reason..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="w-full pl-9 pr-4 py-2 bg-white border border-border-default rounded-xl text-xs text-text-primary placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all shadow-2xs"
                />
              </div>

              {/* Overrides List */}
              {isPermissionsLoading ? (
                <div className="flex flex-col items-center justify-center py-12 text-center">
                  <RefreshCw className="w-6 h-6 text-brand-600 animate-spin mb-2" />
                  <p className="text-xs text-text-secondary">Loading active permission overrides...</p>
                </div>
              ) : filteredActive.length === 0 ? (
                <div className="flex flex-col items-center justify-center py-12 text-center rounded-xl border border-dashed border-border-default bg-white p-6">
                  <div className="w-12 h-12 rounded-full bg-surface-muted flex items-center justify-center text-text-muted mb-3">
                    <Key className="w-6 h-6" />
                  </div>
                  <h3 className="text-sm font-semibold text-text-primary">No active overrides</h3>
                  <p className="text-xs text-text-secondary mt-1 max-w-sm">
                    {searchQuery
                      ? "No active overrides match your filter criteria."
                      : "There are currently no active temporary scope delegations in effect."}
                  </p>
                  {canManageOverrides && !searchQuery && (
                    <button
                      type="button"
                      onClick={() => setActiveTab("grant")}
                      className="mt-4 inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-brand-600 text-white text-xs font-semibold hover:bg-brand-700 transition cursor-pointer"
                    >
                      <Plus className="w-3.5 h-3.5" />
                      <span>Grant First Override</span>
                    </button>
                  )}
                </div>
              ) : (
                <div className="space-y-3">
                  {filteredActive.map((item) => (
                    <div
                      key={item.id}
                      className="rounded-xl border border-border-default bg-white p-4 shadow-2xs hover:border-border-default transition-all space-y-3"
                    >
                      {/* Top Row: User Avatar, Name, Expiry Badge */}
                      <div className="flex items-start justify-between gap-3">
                        <div className="flex items-center gap-3">
                          <div className="w-10 h-10 rounded-full bg-brand-600 text-white flex items-center justify-center text-sm font-bold shadow-2xs">
                            {item.userFullName[0]?.toUpperCase() ?? "U"}
                          </div>
                          <div>
                            <div className="flex items-center gap-2">
                              <h4 className="text-sm font-bold text-text-primary">
                                {item.userFullName}
                              </h4>
                              <span className="inline-flex items-center rounded-md bg-surface-muted px-2 py-0.5 text-[10px] font-semibold text-text-secondary">
                                {item.userRole}
                              </span>
                              <span
                                className={`inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-[10px] font-semibold ${
                                  item.scopeType === "account"
                                    ? "bg-surface-subtle text-text-primary border border-border-default"
                                    : item.scopeType === "module"
                                    ? "bg-surface-subtle text-text-primary border border-border-default"
                                    : "bg-surface-subtle text-text-primary border border-border-default"
                                }`}
                              >
                                {item.scopeType === "account" ? (
                                  <Store className="w-3 h-3" />
                                ) : item.scopeType === "module" ? (
                                  <AppWindow className="w-3 h-3" />
                                ) : (
                                  <Layers className="w-3 h-3" />
                                )}
                                <span className="capitalize">{item.scopeType} Scope</span>
                              </span>
                            </div>
                            <div className="text-xs text-text-secondary mt-0.5">
                              {item.userEmail || "No email linked"}
                            </div>
                          </div>
                        </div>

                        {/* Status & Expiry Badge */}
                        <div className="text-right shrink-0">
                          <div className="inline-flex items-center gap-1.5 rounded-full bg-surface-subtle px-2.5 py-1 text-xs font-semibold text-text-primary border border-border-default">
                            <span className="relative flex h-2 w-2">
                              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-pct-high opacity-75"></span>
                              <span className="relative inline-flex rounded-full h-2 w-2 bg-pct-high"></span>
                            </span>
                            <span>{item.expiresLabel}</span>
                          </div>
                          <div className="text-[10px] text-text-muted mt-1">
                            Expires {new Date(item.expiresAt).toLocaleDateString()} at{" "}
                            {new Date(item.expiresAt).toLocaleTimeString([], {
                              hour: "2-digit",
                              minute: "2-digit",
                            })}
                          </div>
                        </div>
                      </div>

                      {/* Delegated Scopes Tags */}
                      <div className="flex items-start gap-2 pt-1 border-t border-border-subtle">
                        <span className="text-[11px] font-semibold text-text-secondary shrink-0 mt-0.5">
                          Delegated Access:
                        </span>
                        <div className="flex flex-wrap gap-1.5">
                          {item.additionalGroups.map((group) => (
                            <span
                              key={group}
                              className="inline-flex items-center gap-1 rounded-md bg-surface-subtle/80 px-2 py-0.5 text-xs font-semibold text-text-primary border border-border-default/80"
                            >
                              <Layers className="w-3 h-3 text-text-muted" />
                              {group}
                            </span>
                          ))}
                        </div>
                      </div>

                      {/* Audit Details & Actions */}
                      <div className="flex flex-wrap items-center justify-between gap-3 pt-2 text-xs border-t border-border-subtle">
                        <div className="space-y-1">
                          <div className="text-text-secondary">
                            <strong className="text-text-primary font-semibold">Granted by:</strong>{" "}
                            {item.grantedBy} •{" "}
                            <span className="text-text-muted">
                              {new Date(item.createdAt).toLocaleDateString()}
                            </span>
                          </div>
                          {item.displayReason && (
                            <div className="text-text-secondary italic text-[11px] bg-surface-subtle rounded-md px-2.5 py-1 border border-border-default/60 max-w-lg">
                              &ldquo;{item.displayReason}&rdquo;
                            </div>
                          )}
                        </div>

                        {canManageOverrides && (
                          <button
                            type="button"
                            onClick={() => setRevokingItem(item)}
                            className="inline-flex items-center gap-1.5 rounded-lg border border-danger-border bg-danger-subtle/70 px-3 py-1.5 text-xs font-semibold text-danger-text hover:bg-danger-subtle hover:border-danger-border transition cursor-pointer"
                          >
                            <AlertTriangle className="w-3.5 h-3.5" />
                            <span>Revoke Access</span>
                          </button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* TAB 2: HISTORY & REVOCATIONS */}
          {activeTab === "history" && (
            <div className="space-y-4">
              {/* Search Bar */}
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-text-muted" />
                <input
                  type="text"
                  placeholder="Search past overrides by user, role, group, or reason..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="w-full pl-9 pr-4 py-2 bg-white border border-border-default rounded-xl text-xs text-text-primary placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all shadow-2xs"
                />
              </div>

              {isPermissionsLoading ? (
                <div className="flex flex-col items-center justify-center py-12 text-center">
                  <RefreshCw className="w-6 h-6 text-brand-600 animate-spin mb-2" />
                  <p className="text-xs text-text-secondary">Loading override history...</p>
                </div>
              ) : filteredHistory.length === 0 ? (
                <div className="flex flex-col items-center justify-center py-12 text-center rounded-xl border border-dashed border-border-default bg-white p-6">
                  <RotateCcw className="w-8 h-8 text-text-muted mb-2" />
                  <h3 className="text-sm font-semibold text-text-primary">No historical overrides</h3>
                  <p className="text-xs text-text-secondary mt-1 max-w-sm">
                    {searchQuery
                      ? "No records match your filter criteria."
                      : "Expired and revoked permissions will be archived here for audit trail compliance."}
                  </p>
                </div>
              ) : (
                <div className="space-y-3">
                  {filteredHistory.map((item) => (
                    <div
                      key={item.id}
                      className="rounded-xl border border-border-default bg-white/80 p-4 shadow-2xs opacity-85 hover:opacity-100 transition-all space-y-2.5"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div className="flex items-center gap-3">
                          <div className="w-9 h-9 rounded-full bg-surface-muted text-text-primary flex items-center justify-center text-xs font-bold">
                            {item.userFullName[0]?.toUpperCase() ?? "U"}
                          </div>
                          <div>
                            <div className="flex items-center gap-2">
                              <h4 className="text-xs font-bold text-text-primary">
                                {item.userFullName}
                              </h4>
                              <span className="inline-flex items-center rounded-md bg-surface-muted px-2 py-0.2 text-[10px] font-semibold text-text-secondary">
                                {item.userRole}
                              </span>
                            </div>
                            <div className="text-[11px] text-text-muted">
                              Granted: {new Date(item.createdAt).toLocaleDateString()} by {item.grantedBy}
                            </div>
                          </div>
                        </div>

                        {/* Status Badge */}
                        <div className="text-right">
                          <span
                            className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ${
                              item.revokedAt
                                ? "bg-danger-subtle text-danger-text border border-danger-border"
                                : "bg-surface-muted text-text-secondary border border-border-default"
                            }`}
                          >
                            {item.revokedAt ? "Revoked" : "Expired"}
                          </span>
                          <div className="text-[10px] text-text-muted mt-0.5">
                            {item.revokedAt
                              ? `Revoked on ${new Date(item.revokedAt).toLocaleDateString()}`
                              : `Expired on ${new Date(item.expiresAt).toLocaleDateString()}`}
                          </div>
                        </div>
                      </div>

                      {/* Delegated Groups */}
                      <div className="flex items-center gap-2 text-xs">
                        <span className="text-[11px] font-medium text-text-secondary">Groups:</span>
                        <div className="flex flex-wrap gap-1">
                          {item.additionalGroups.map((group) => (
                            <span
                              key={group}
                              className="inline-flex items-center rounded bg-surface-muted px-1.5 py-0.5 text-[11px] text-text-primary"
                            >
                              {group}
                            </span>
                          ))}
                        </div>
                      </div>

                      {/* Reason & Revoked By Info */}
                      {(item.displayReason || item.revokedBy) && (
                        <div className="pt-1 border-t border-border-subtle flex flex-wrap items-center justify-between text-[11px] text-text-secondary">
                          {item.displayReason && (
                            <span className="italic">&ldquo;{item.displayReason}&rdquo;</span>
                          )}
                          {item.revokedBy && (
                            <span className="text-danger-icon font-medium ml-auto">
                              Revoked by: {item.revokedBy}
                            </span>
                          )}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* TAB 3: GRANT OVERRIDE FORM */}
          {activeTab === "grant" && (
            <form onSubmit={handleGrantSubmit} className="space-y-5">
              {/* Security Warning Notice */}
              <div className="rounded-xl border border-border-default bg-surface-subtle/80 p-3.5 text-xs text-text-primary flex items-start gap-3">
                <ShieldAlert className="w-5 h-5 text-text-secondary shrink-0 mt-0.5" />
                <div className="space-y-1">
                  <strong className="font-bold">Security & Auditing Warning</strong>
                  <p className="text-text-primary leading-relaxed">
                    Temporary permission overrides elevate an employee&apos;s access scope beyond
                    their permanent role profile. All temporary grants are logged to the security
                    audit trail and will automatically expire at the designated timestamp.
                  </p>
                </div>
              </div>

              {/* Feedback Alert */}
              {formError && (
                <div className="rounded-lg border border-danger-border bg-danger-subtle p-3 text-xs font-semibold text-danger-text flex items-center gap-2">
                  <AlertTriangle className="w-4 h-4 shrink-0 text-danger-icon" />
                  <span>{formError}</span>
                </div>
              )}

              {formSuccess && (
                <div className="rounded-lg border border-border-default bg-surface-subtle p-3 text-xs font-semibold text-text-primary flex items-center gap-2">
                  <CheckCircle2 className="w-4 h-4 shrink-0 text-pct-high" />
                  <span>{formSuccess}</span>
                </div>
              )}

              {/* Step 1: Target User Selection */}
              <div className="space-y-2 rounded-xl border border-border-default bg-white p-4">
                <label className="block text-xs font-bold uppercase tracking-wider text-text-secondary">
                  1. Select Target User
                </label>
                <select
                  value={selectedTargetUserId}
                  onChange={(e) => setSelectedTargetUserId(e.target.value)}
                  className="w-full h-10 rounded-lg border border-border-default bg-white px-3 text-xs font-semibold text-text-primary outline-none focus:border-brand-500"
                >
                  <option value="">-- Choose an active user --</option>
                  {allUsers
                    .filter((u) => u.status === "Active")
                    .map((user) => (
                      <option key={user.id} value={user.id}>
                        {user.fullName} ({user.roleName}) {user.email ? `• ${user.email}` : ""}
                      </option>
                    ))}
                </select>

                {selectedUserObj && (
                  <div className="mt-2 rounded-lg bg-surface-subtle p-2.5 text-xs text-text-secondary border border-border-default/80 flex items-center justify-between">
                    <div>
                      <span className="font-semibold text-text-primary">Current Role:</span>{" "}
                      {selectedUserObj.roleName}
                    </div>
                    <div>
                      <span className="font-semibold text-text-primary">Permanent Scopes:</span>{" "}
                      {selectedUserObj.scopeLabel || "None"}
                    </div>
                  </div>
                )}
              </div>

              {/* Step 2: Delegation Scope Type Selector */}
              <div className="space-y-3 rounded-xl border border-border-default bg-white p-4">
                <div className="flex items-center justify-between">
                  <label className="block text-xs font-bold uppercase tracking-wider text-text-secondary">
                    2. Scope Delegation Type
                  </label>
                  <span className="text-[11px] text-text-muted">
                    Choose what level of access to delegate
                  </span>
                </div>

                <div className="grid grid-cols-3 gap-2">
                  <button
                    type="button"
                    onClick={() => setScopeType("group")}
                    className={`flex items-center justify-center gap-2 rounded-xl border p-3 text-xs font-bold transition-all cursor-pointer ${
                      scopeType === "group"
                        ? "border-brand-500 bg-brand-50 text-brand-900 shadow-2xs"
                        : "border-border-default bg-white text-text-secondary hover:bg-surface-subtle"
                    }`}
                  >
                    <Layers className="w-4 h-4 text-brand-600" />
                    <span>Group Scope</span>
                  </button>

                  <button
                    type="button"
                    onClick={() => setScopeType("account")}
                    className={`flex items-center justify-center gap-2 rounded-xl border p-3 text-xs font-bold transition-all cursor-pointer ${
                      scopeType === "account"
                        ? "border-brand-500 bg-surface-subtle text-text-primary shadow-2xs"
                        : "border-border-default bg-white text-text-secondary hover:bg-surface-subtle"
                    }`}
                  >
                    <Store className="w-4 h-4 text-text-secondary" />
                    <span>Account Scope</span>
                  </button>

                  <button
                    type="button"
                    onClick={() => setScopeType("module")}
                    className={`flex items-center justify-center gap-2 rounded-xl border p-3 text-xs font-bold transition-all cursor-pointer ${
                      scopeType === "module"
                        ? "border-brand-500 bg-surface-subtle text-text-primary shadow-2xs"
                        : "border-border-default bg-white text-text-secondary hover:bg-surface-subtle"
                    }`}
                  >
                    <AppWindow className="w-4 h-4 text-text-secondary" />
                    <span>Module Scope</span>
                  </button>
                </div>

                {/* Sub-Selection based on Scope Type */}
                <div className="pt-2">
                  {/* GROUP SCOPE PICKER */}
                  {scopeType === "group" && (
                    <div className="space-y-2">
                      <div className="flex items-center justify-between text-xs text-text-secondary">
                        <span>Select Operational Groups to temporarily add:</span>
                        <div className="flex gap-2">
                          <button
                            type="button"
                            onClick={() => setSelectedGroupNames(allGroups.map((g) => g.name))}
                            className="font-semibold text-brand-600 hover:underline cursor-pointer"
                          >
                            Select All
                          </button>
                          <span>•</span>
                          <button
                            type="button"
                            onClick={() => setSelectedGroupNames([])}
                            className="font-semibold text-danger-icon hover:underline cursor-pointer"
                          >
                            Clear
                          </button>
                        </div>
                      </div>

                      <div className="flex flex-wrap gap-2 max-h-40 overflow-y-auto p-2 border border-border-default rounded-xl bg-surface-subtle/50">
                        {allGroups.map((group) => {
                          const isSelected = selectedGroupNames.includes(group.name);
                          return (
                            <button
                              key={group.id}
                              type="button"
                              onClick={() => handleToggleGroup(group.name)}
                              className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-semibold transition cursor-pointer ${
                                isSelected
                                  ? "bg-brand-600 text-white shadow-2xs"
                                  : "bg-white text-text-primary border border-border-default hover:bg-surface-muted"
                              }`}
                            >
                              <Layers className="w-3 h-3" />
                              <span>{group.name}</span>
                            </button>
                          );
                        })}
                      </div>
                    </div>
                  )}

                  {/* ACCOUNT SCOPE PICKER */}
                  {scopeType === "account" && (
                    <div className="space-y-2">
                      <div className="relative">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-text-muted" />
                        <input
                          type="text"
                          placeholder="Search accounts / stores..."
                          value={scopeSearch}
                          onChange={(e) => setScopeSearch(e.target.value)}
                          className="w-full pl-8 pr-3 py-1.5 bg-white border border-border-default rounded-lg text-xs"
                        />
                      </div>

                      <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 max-h-40 overflow-y-auto p-2 border border-border-default rounded-xl bg-surface-subtle/50">
                        {allAccounts
                          .filter((a) =>
                            scopeSearch
                              ? a.account_name.toLowerCase().includes(scopeSearch.toLowerCase())
                              : true,
                          )
                          .map((acc) => {
                            const isSelected = selectedAccountIds.includes(acc.id);
                            return (
                              <button
                                key={acc.id}
                                type="button"
                                onClick={() => handleToggleAccount(acc.id)}
                                className={`text-left p-2 rounded-lg text-xs font-semibold border transition truncate cursor-pointer ${
                                  isSelected
                                    ? "bg-brand-500 text-white border-brand-500 shadow-2xs"
                                    : "bg-white text-text-primary border-border-default hover:bg-surface-muted"
                                }`}
                              >
                                <div className="truncate">{acc.account_name}</div>
                              </button>
                            );
                          })}
                      </div>
                      <div className="text-[11px] text-text-muted">
                        {selectedAccountIds.length} account(s) selected. Associated group scopes will be automatically delegated.
                      </div>
                    </div>
                  )}

                  {/* MODULE SCOPE PICKER */}
                  {scopeType === "module" && (
                    <div className="grid grid-cols-2 gap-2">
                      {AVAILABLE_MODULES.map((mod) => {
                        const isSelected = selectedModuleIds.includes(mod.id);
                        return (
                          <button
                            key={mod.id}
                            type="button"
                            onClick={() => handleToggleModule(mod.id)}
                            className={`p-3 rounded-xl border text-left transition cursor-pointer ${
                              isSelected
                                ? "bg-brand-500 text-white border-brand-500 shadow-2xs"
                                : "bg-white text-text-primary border-border-default hover:bg-surface-subtle"
                            }`}
                          >
                            <div className="flex items-center gap-2">
                              <AppWindow className="w-4 h-4" />
                              <div className="text-xs font-bold">{mod.name}</div>
                            </div>
                          </button>
                        );
                      })}
                    </div>
                  )}
                </div>
              </div>

              {/* Step 3: Expiration Duration & Picker */}
              <div className="space-y-3 rounded-xl border border-border-default bg-white p-4">
                <div className="flex items-center justify-between">
                  <label className="block text-xs font-bold uppercase tracking-wider text-text-secondary">
                    3. Expiration Time Limit
                  </label>
                  <span className="text-[11px] text-text-muted">Max limit: 30 days</span>
                </div>

                <div className="flex flex-wrap gap-2">
                  {[
                    { label: "24 Hours (1 Day)", days: 1 },
                    { label: "3 Days", days: 3 },
                    { label: "7 Days (1 Week)", days: 7 },
                    { label: "14 Days (2 Weeks)", days: 14 },
                    { label: "30 Days (Maximum)", days: 30 },
                  ].map((preset) => (
                    <button
                      key={preset.days}
                      type="button"
                      onClick={() => handleSelectPresetDuration(preset.days)}
                      className={`px-3 py-1.5 rounded-lg text-xs font-semibold border transition cursor-pointer ${
                        presetDurationDays === preset.days
                          ? "bg-brand-500 text-white border-brand-500"
                          : "bg-white text-text-secondary border-border-default hover:bg-surface-subtle"
                      }`}
                    >
                      {preset.label}
                    </button>
                  ))}
                </div>

                <div className="pt-2">
                  <label className="block text-xs font-semibold text-text-secondary mb-1">
                    Exact Expiration Date & Time:
                  </label>
                  <div className="relative">
                    <Calendar className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-text-muted" />
                    <input
                      type="datetime-local"
                      value={customExpiryDate}
                      onChange={(e) => {
                        setCustomExpiryDate(e.target.value);
                        setPresetDurationDays(0);
                      }}
                      className="w-full pl-9 pr-3 py-2 border border-border-default rounded-lg text-xs font-semibold text-text-primary focus:outline-none focus:border-brand-500"
                    />
                  </div>
                </div>
              </div>

              {/* Step 4: Mandatory Audit Justification */}
              <div className="space-y-2 rounded-xl border border-border-default bg-white p-4">
                <div className="flex items-center justify-between">
                  <label className="block text-xs font-bold uppercase tracking-wider text-text-secondary">
                    4. Mandatory Audit Justification Reason <span className="text-danger-text">*</span>
                  </label>
                  <span className="text-[11px] text-text-muted">Recorded in compliance logs</span>
                </div>
                <textarea
                  rows={3}
                  placeholder="e.g. Temporary coverage for CENCOM Area 1 during regional system training and audit review..."
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  className="w-full p-3 border border-border-default rounded-xl text-xs text-text-primary placeholder-slate-400 focus:outline-none focus:border-brand-500"
                />

                <div className="flex items-center gap-2 pt-1">
                  <input
                    type="checkbox"
                    id="notify-user-check"
                    checked={notifyUser}
                    onChange={(e) => setNotifyUser(e.target.checked)}
                    className="rounded border-border-default text-brand-600 focus:ring-brand-500 cursor-pointer"
                  />
                  <label
                    htmlFor="notify-user-check"
                    className="text-xs text-text-secondary cursor-pointer select-none"
                  >
                    Send in-app notification to employee regarding granted access
                  </label>
                </div>
              </div>

              {/* Form Actions */}
              <div className="flex items-center justify-end gap-3 pt-2">
                <button
                  type="button"
                  onClick={() => setActiveTab("active")}
                  className="px-4 py-2 text-xs font-semibold text-text-secondary hover:text-text-primary cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={grantMutation.isPending}
                  className="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl bg-brand-600 text-white text-xs font-bold shadow-xs hover:bg-brand-700 disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer transition-all"
                >
                  {grantMutation.isPending ? (
                    <>
                      <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                      <span>Granting Override...</span>
                    </>
                  ) : (
                    <>
                      <Key className="w-3.5 h-3.5" />
                      <span>Grant Temporary Override</span>
                    </>
                  )}
                </button>
              </div>
            </form>
          )}
        </div>

      </div>

      {/* Revoke Confirmation Dialog */}
      <Modal
        isOpen={Boolean(revokingItem)}
        onClose={() => {
          setRevokingItem(null);
          setRevokeReason("");
        }}
        title="Revoke Temporary Access"
        subtitle="Immediately terminates delegated access for this employee"
        icon={AlertTriangle}
        maxWidthClass="max-w-md"
        isSubmitting={isRevoking}
        disableBackdropClick={isRevoking}
        footer={
          <div className="flex items-center justify-end gap-2">
            <button
              type="button"
              disabled={isRevoking}
              onClick={() => {
                setRevokingItem(null);
                setRevokeReason("");
              }}
              className="px-4 py-2 text-xs font-semibold text-text-secondary hover:text-text-primary cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="button"
              disabled={isRevoking}
              onClick={handleExecuteRevoke}
              className="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg bg-danger-button text-danger-button-text text-xs font-bold hover:bg-danger-button-hover transition cursor-pointer disabled:opacity-50"
            >
              {isRevoking ? (
                <>
                  <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                  <span>Revoking...</span>
                </>
              ) : (
                <span>Confirm Revocation</span>
              )}
            </button>
          </div>
        }
      >
        {revokingItem && (
          <div className="space-y-4">
            <div className="rounded-xl border border-danger-border bg-danger-subtle p-3 text-xs text-danger-text space-y-1">
              <div>
                <strong>User:</strong> {revokingItem.userFullName}
              </div>
              <div>
                <strong>Groups to remove:</strong> {revokingItem.additionalGroups.join(", ")}
              </div>
            </div>

            <div>
              <label className="block text-xs font-semibold text-text-primary mb-1">
                Revocation Reason (Optional):
              </label>
              <input
                type="text"
                placeholder="e.g. Coverage completed ahead of schedule"
                value={revokeReason}
                onChange={(e) => setRevokeReason(e.target.value)}
                className="w-full p-2.5 border border-border-default rounded-lg text-xs bg-surface text-text-primary"
              />
            </div>
          </div>
        )}
      </Modal>
    </Modal>
  );
}
