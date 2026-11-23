"use client";

import { useMemo, useState } from "react";
import {
  BriefcaseBusiness,
  Building2,
  Check,
  CheckCheck,
  ChevronDown,
  ChevronRight,
  ClipboardList,
  FileBarChart,
  KeyRound,
  Layers,
  LayoutDashboard,
  Lock,
  RefreshCw,
  RotateCcw,
  Search,
  Shield,
  ShieldAlert,
  ShieldCheck,
  Sliders,
  Sparkles,
  Undo2,
  Users,
  UserX,
  X,
} from "lucide-react";
import { useCurrentUser } from "@/lib/auth";
import { isOwner, getRoleLevel } from "@/lib/rbac";
import { Modal } from "@/components/shared/Modal";
import {
  useAllRolesEffectiveMatrix,
  useGovernanceRoles,
  useApplyPermissionOverrides,
  useResetPermissionOverrides,
  type AllRolesMatrixRow,
  type GovernanceRole,
} from "@/lib/queries/governance";

// Module metadata mapping for friendly display & route badges
const MODULE_METADATA: Record<
  string,
  { label: string; route: string; order: number; icon: typeof LayoutDashboard }
> = {
  vacancy: { label: "Vacancy Management", route: "/vacancy", order: 1, icon: BriefcaseBusiness },
  plantilla: { label: "Plantilla Staffing", route: "/plantilla", order: 2, icon: ShieldCheck },
  hr_emploc: { label: "HR Emploc Records", route: "/hr-emploc", order: 3, icon: ClipboardList },
  cencom: { label: "CENCOM Coordination", route: "/cencom", order: 4, icon: Building2 },
  dashboard: { label: "Command Dashboard", route: "/dashboard", order: 5, icon: LayoutDashboard },
  reports: { label: "Executive Reports", route: "/reports", order: 6, icon: FileBarChart },
  approvals: { label: "Approvals Center", route: "/approvals", order: 7, icon: CheckCheck },
  deactivation: { label: "Deactivation Queue", route: "/approvals?tab=deactivations", order: 8, icon: UserX },
  user_management: { label: "User Administration", route: "/users", order: 9, icon: Users },
  access_management: { label: "Access & Security", route: "/settings?tab=security", order: 10, icon: Shield },
  data_control: { label: "Data Control & Imports", route: "/more?tab=data_control", order: 11, icon: Layers },
  admin_tools: { label: "Admin Tools (SA Recovery)", route: "/more?tab=admin_tools", order: 12, icon: Sliders },
  governance: { label: "System Governance", route: "/more?tab=governance", order: 13, icon: KeyRound },
};

type RoleGroupKey = "all" | "ops" | "data" | "hr" | "viewer";

const ROLE_GROUP_PRESETS: Record<RoleGroupKey, { label: string; levels: number[] }> = {
  all: { label: "All Roles (11)", levels: [100, 90, 70, 45, 42, 41, 30, 25, 20, 15, 10] },
  ops: { label: "Operations (OM, HRCO, ATL, TL)", levels: [70, 45, 42, 41] },
  data: { label: "Data Team (HA, Encoder)", levels: [90, 30] },
  hr: { label: "HR & Recruitment (Rec, HRP, BO)", levels: [25, 20, 15] },
  viewer: { label: "Viewer", levels: [10] },
};

export default function RbacPage() {
  const currentUser = useCurrentUser();
  const isSuperAdmin = isOwner(currentUser) || (getRoleLevel(currentUser) >= 100);

  // Queries
  const { data: roles = [], isLoading: isLoadingRoles } = useGovernanceRoles();
  const {
    data: allMatrixRows = [],
    isLoading: isLoadingMatrix,
    isFetching: isFetchingMatrix,
    refetch: refetchMatrix,
  } = useAllRolesEffectiveMatrix();

  const applyOverridesMutation = useApplyPermissionOverrides();
  const resetOverridesMutation = useResetPermissionOverrides();

  // Filters & UI State
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedRoleGroup, setSelectedRoleGroup] = useState<RoleGroupKey>("all");
  const [collapsedModules, setCollapsedModules] = useState<Record<string, boolean>>({});

  // Staged changes: key = `${roleName}::${moduleKey}::${resourceKey}::${actionKey}` -> targetAllowed
  const [stagedChanges, setStagedChanges] = useState<Record<string, boolean>>({});

  // Modals state
  const [isCommitModalOpen, setIsCommitModalOpen] = useState(false);
  const [commitReason, setCommitReason] = useState("");
  const [commitError, setCommitError] = useState<string | null>(null);

  const [resetTarget, setResetTarget] = useState<{
    roleName: string | null; // null = all roles
    overrideCount: number;
  } | null>(null);
  const [resetReason, setResetReason] = useState("");
  const [resetError, setResetError] = useState<string | null>(null);

  const [toastMessage, setToastMessage] = useState<string | null>(null);
  const showToast = (msg: string) => {
    setToastMessage(msg);
    setTimeout(() => setToastMessage(null), 4000);
  };

  // Sort and filter active roles by selected group
  const activeRoles = useMemo(() => {
    const sorted = [...roles].sort((a, b) => b.level - a.level);
    const targetLevels = new Set(ROLE_GROUP_PRESETS[selectedRoleGroup].levels);
    return sorted.filter((r) => targetLevels.has(r.level));
  }, [roles, selectedRoleGroup]);

  // Index matrix data: roleId/roleName -> permissionKey -> row
  const matrixIndex = useMemo(() => {
    const map = new Map<string, AllRolesMatrixRow>();
    allMatrixRows.forEach((row) => {
      const key = `${row.roleName}::${row.moduleKey}::${row.resourceKey}::${row.actionKey}`;
      map.set(key, row);
    });
    return map;
  }, [allMatrixRows]);

  // Distinct permission definitions across modules
  const distinctDefinitions = useMemo(() => {
    const defMap = new Map<
      string,
      {
        moduleKey: string;
        resourceKey: string;
        actionKey: string;
        description: string | null;
        isSystemLocked: boolean;
        isSensitive: boolean;
        sortOrder: number;
      }
    >();

    allMatrixRows.forEach((r) => {
      const defKey = `${r.moduleKey}::${r.resourceKey}::${r.actionKey}`;
      const existing = defMap.get(defKey);
      // Prefer non-locked row value if any role reports false, ensuring role-protection on SA does not bleed into definition catalog
      if (!existing || (existing.isSystemLocked && !r.isSystemLocked)) {
        defMap.set(defKey, {
          moduleKey: r.moduleKey,
          resourceKey: r.resourceKey,
          actionKey: r.actionKey,
          description: r.description,
          isSystemLocked: r.isSystemLocked,
          isSensitive: r.isSensitive,
          sortOrder: r.sortOrder,
        });
      }
    });

    return Array.from(defMap.values());
  }, [allMatrixRows]);

  // Group definitions by module with search filter applied
  const definitionsByModule = useMemo(() => {
    const q = searchQuery.toLowerCase().trim();
    const grouped: Record<string, typeof distinctDefinitions> = {};

    distinctDefinitions.forEach((def) => {
      if (q) {
        const modMeta = MODULE_METADATA[def.moduleKey];
        const match =
          def.moduleKey.toLowerCase().includes(q) ||
          def.resourceKey.toLowerCase().includes(q) ||
          def.actionKey.toLowerCase().includes(q) ||
          (def.description ?? "").toLowerCase().includes(q) ||
          (modMeta?.label ?? "").toLowerCase().includes(q) ||
          (modMeta?.route ?? "").toLowerCase().includes(q);
        if (!match) return;
      }

      if (!grouped[def.moduleKey]) {
        grouped[def.moduleKey] = [];
      }
      grouped[def.moduleKey].push(def);
    });

    // Sort definitions within each module
    Object.keys(grouped).forEach((k) => {
      grouped[k].sort((a, b) => a.sortOrder - b.sortOrder);
    });

    // Sort module keys by order
    const sortedKeys = Object.keys(grouped).sort((a, b) => {
      const orderA = MODULE_METADATA[a]?.order ?? 99;
      const orderB = MODULE_METADATA[b]?.order ?? 99;
      return orderA - orderB;
    });

    return { grouped, sortedKeys };
  }, [distinctDefinitions, searchQuery]);

  // Total active overrides count across all roles
  const totalActiveOverridesCount = useMemo(() => {
    return allMatrixRows.filter((r) => r.hasOverride).length;
  }, [allMatrixRows]);

  // Active overrides count per role
  const overridesCountByRole = useMemo(() => {
    const counts: Record<string, number> = {};
    allMatrixRows.forEach((r) => {
      if (r.hasOverride) {
        counts[r.roleName] = (counts[r.roleName] || 0) + 1;
      }
    });
    return counts;
  }, [allMatrixRows]);

  // Cell helper functions
  const getCellKey = (roleName: string, moduleKey: string, resourceKey: string, actionKey: string) =>
    `${roleName}::${moduleKey}::${resourceKey}::${actionKey}`;

  const getCellEffectiveValue = (
    role: GovernanceRole,
    moduleKey: string,
    resourceKey: string,
    actionKey: string
  ) => {
    const cellKey = getCellKey(role.name, moduleKey, resourceKey, actionKey);
    if (cellKey in stagedChanges) {
      return stagedChanges[cellKey];
    }
    const row = matrixIndex.get(cellKey);
    return row?.isAllowed ?? false;
  };

  const handleCellToggle = (
    role: GovernanceRole,
    moduleKey: string,
    resourceKey: string,
    actionKey: string,
    row?: AllRolesMatrixRow
  ) => {
    // Protected roles (Super Admin) or system-locked definitions cannot be toggled
    if (role.level >= 100) return;
    if (row?.isSystemLocked) return;

    const cellKey = getCellKey(role.name, moduleKey, resourceKey, actionKey);
    const currentValue = getCellEffectiveValue(role, moduleKey, resourceKey, actionKey);
    const targetValue = !currentValue;

    // If target value matches current database state, remove from staged
    const originalValue = row?.isAllowed ?? false;
    if (targetValue === originalValue) {
      const next = { ...stagedChanges };
      delete next[cellKey];
      setStagedChanges(next);
    } else {
      setStagedChanges((prev) => ({
        ...prev,
        [cellKey]: targetValue,
      }));
    }
  };

  const handleCellReset = async (
    role: GovernanceRole,
    moduleKey: string,
    resourceKey: string,
    actionKey: string
  ) => {
    if (role.level >= 100) return;
    try {
      await resetOverridesMutation.mutateAsync({
        role_name: role.name,
        module_key: moduleKey,
        resource_key: resourceKey,
        action_key: actionKey,
        reason: `Reverted ${moduleKey}.${resourceKey}.${actionKey} to default for ${role.name}`,
      });
      const cellKey = getCellKey(role.name, moduleKey, resourceKey, actionKey);
      if (cellKey in stagedChanges) {
        const next = { ...stagedChanges };
        delete next[cellKey];
        setStagedChanges(next);
      }
      refetchMatrix();
      showToast(`Reset ${resourceKey} (${actionKey}) to base default for ${role.name}.`);
    } catch (err: unknown) {
      showToast(`Error resetting: ${(err as Error).message}`);
    }
  };

  const handleDiscardStaged = () => {
    setStagedChanges({});
  };

  const stagedCount = Object.keys(stagedChanges).length;

  const handleConfirmCommit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!commitReason.trim()) {
      setCommitError("An audit justification reason is required for governance tracking.");
      return;
    }

    const changesToSubmit = Object.entries(stagedChanges).map(([cellKey, isAllowed]) => {
      const [roleName, moduleKey, resourceKey, actionKey] = cellKey.split("::");
      return {
        role_name: roleName,
        module_key: moduleKey,
        resource_key: resourceKey,
        action_key: actionKey,
        is_allowed: isAllowed,
      };
    });

    try {
      await applyOverridesMutation.mutateAsync({
        changes: changesToSubmit,
        reason: commitReason.trim(),
      });
      setStagedChanges({});
      setIsCommitModalOpen(false);
      refetchMatrix();
      showToast(`Successfully applied ${changesToSubmit.length} permission overrides.`);
    } catch (err: unknown) {
      setCommitError((err as Error).message);
    }
  };

  const handleConfirmReset = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!resetTarget) return;

    try {
      if (resetTarget.roleName) {
        await resetOverridesMutation.mutateAsync({
          role_name: resetTarget.roleName,
          reason: resetReason.trim() || `Reset all permission overrides for ${resetTarget.roleName}`,
        });
      } else {
        const rolesToReset = Array.from(
          new Set(
            allMatrixRows
              .filter((m) => m.hasOverride && m.roleName !== "Super Admin")
              .map((m) => m.roleName)
          )
        );
        for (const rName of rolesToReset) {
          await resetOverridesMutation.mutateAsync({
            role_name: rName,
            reason: resetReason.trim() || "Global reset of all permission overrides to system default matrix",
          });
        }
      }

      setStagedChanges({});
      setResetTarget(null);
      refetchMatrix();
      showToast(
        resetTarget.roleName
          ? `Reset all custom overrides for ${resetTarget.roleName} back to base defaults.`
          : "Successfully reset all custom overrides across all roles."
      );
    } catch (err: unknown) {
      setResetError((err as Error).message);
    }
  };

  // Expand / collapse all modules helper
  const handleToggleAllModules = (expand: boolean) => {
    const next: Record<string, boolean> = {};
    definitionsByModule.sortedKeys.forEach((k) => {
      next[k] = !expand;
    });
    setCollapsedModules(next);
  };

  if (!isSuperAdmin) {
    return (
      <div className="flex flex-col items-center justify-center p-12 text-center">
        <ShieldAlert className="h-12 w-12 text-danger mb-4" />
        <h2 className="text-lg font-bold text-text-primary">Super Admin Access Required</h2>
        <p className="text-sm text-text-secondary mt-1 max-w-md">
          The RBAC & Permission Matrix is restricted exclusively to Root Super Administrators.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col min-h-screen pb-24">
      {/* Toast Notification */}
      {toastMessage && (
        <div className="fixed top-5 right-5 z-50 flex items-center gap-2 rounded-xl border border-brand-border bg-brand-subtle px-4 py-3 text-xs font-semibold text-brand-primary shadow-lg animate-in fade-in slide-in-from-top-3">
          <Sparkles className="h-4 w-4 shrink-0 text-brand-primary" />
          <span>{toastMessage}</span>
        </div>
      )}

      {/* Page Header */}
      <div className="border-b border-border-default bg-surface-base px-6 py-5">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div className="flex items-center gap-2.5">
              <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-brand-subtle text-brand-primary border border-brand-border">
                <KeyRound className="h-5 w-5" />
              </span>
              <div>
                <h1 className="text-xl font-bold tracking-tight text-text-primary">
                  RBAC & Permission Matrix
                </h1>
                <p className="text-xs text-text-secondary mt-0.5">
                  Hierarchical role-based access control, route visibility, and action capabilities manager
                </p>
              </div>
            </div>
          </div>

          {/* Header Action Strip */}
          <div className="flex items-center gap-2.5">
            <button
              type="button"
              disabled={totalActiveOverridesCount === 0 || resetOverridesMutation.isPending}
              onClick={() => {
                setResetError(null);
                setResetReason("");
                setResetTarget({ roleName: null, overrideCount: totalActiveOverridesCount });
              }}
              className="inline-flex items-center gap-1.5 rounded-xl border border-border-default bg-surface-base px-3.5 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary shadow-xs transition cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
              title="Reset all custom overrides back to default system definitions"
            >
              <RotateCcw className="h-3.5 w-3.5 text-text-muted" />
              <span>Reset All Overrides</span>
              {totalActiveOverridesCount > 0 && (
                <span className="rounded-full bg-brand-primary text-text-inverse px-1.5 py-0.2 text-[10px] font-bold">
                  {totalActiveOverridesCount}
                </span>
              )}
            </button>

            <button
              type="button"
              onClick={() => refetchMatrix()}
              disabled={isFetchingMatrix}
              className="inline-flex items-center gap-1.5 rounded-xl border border-border-default bg-surface-base px-3.5 py-2 text-xs font-semibold text-text-primary shadow-xs hover:bg-surface-hover transition cursor-pointer"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isFetchingMatrix ? "animate-spin text-brand-primary" : "text-text-muted"
                }`}
              />
              <span>Refresh</span>
            </button>
          </div>
        </div>

        {/* Toolbar: Search, Role Group Filters & Expand All */}
        <div className="mt-5 flex flex-wrap items-center justify-between gap-3 border-t border-border-subtle pt-4">
          <div className="flex flex-wrap items-center gap-3">
            {/* Search Input */}
            <div className="relative w-72">
              <Search className="absolute left-3 top-2.5 h-3.5 w-3.5 text-text-muted" />
              <input
                type="text"
                placeholder="Search module, route, or action..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="h-9 w-full rounded-xl border border-border-default bg-surface-base pl-9 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default shadow-xs"
              />
              {searchQuery && (
                <button
                  type="button"
                  onClick={() => setSearchQuery("")}
                  className="absolute right-2.5 top-2.5 text-text-muted hover:text-text-primary"
                >
                  <X className="h-3.5 w-3.5" />
                </button>
              )}
            </div>

            {/* Role Group Filter Pills */}
            <div className="flex items-center rounded-xl bg-surface-subtle p-1 border border-border-default">
              {(Object.keys(ROLE_GROUP_PRESETS) as RoleGroupKey[]).map((key) => {
                const isSelected = selectedRoleGroup === key;
                return (
                  <button
                    key={key}
                    type="button"
                    onClick={() => setSelectedRoleGroup(key)}
                    className={`rounded-lg px-2.5 py-1 text-xs font-semibold transition cursor-pointer ${
                      isSelected
                        ? "bg-surface-base text-text-primary shadow-xs"
                        : "text-text-secondary hover:text-text-primary"
                    }`}
                  >
                    {ROLE_GROUP_PRESETS[key].label}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Expand / Collapse All Button */}
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => handleToggleAllModules(true)}
              className="text-xs font-semibold text-text-secondary hover:text-text-primary px-2 py-1 rounded-lg hover:bg-surface-subtle cursor-pointer"
            >
              Expand All
            </button>
            <span className="text-border-default">•</span>
            <button
              type="button"
              onClick={() => handleToggleAllModules(false)}
              className="text-xs font-semibold text-text-secondary hover:text-text-primary px-2 py-1 rounded-lg hover:bg-surface-subtle cursor-pointer"
            >
              Collapse All
            </button>
          </div>
        </div>
      </div>

      {/* Main Table Matrix Container */}
      <div className="flex-1 px-6 py-6 overflow-x-auto">
        {isLoadingMatrix || isLoadingRoles ? (
          <div className="flex h-80 flex-col items-center justify-center gap-3 text-text-muted">
            <RefreshCw className="h-8 w-8 animate-spin text-brand-primary" />
            <p className="text-xs font-medium">Resolving full RBAC effective matrix across all roles...</p>
          </div>
        ) : definitionsByModule.sortedKeys.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-border-default p-12 text-center text-xs text-text-muted">
            No modules or permissions found matching &quot;{searchQuery}&quot;.
          </div>
        ) : (
          <div className="rounded-2xl border border-border-default bg-surface-base shadow-sm overflow-hidden">
            <table className="w-full border-collapse text-left">
              {/* Table Header: Sticky Left + Role Columns */}
              <thead>
                <tr className="border-b border-border-default bg-surface-subtle text-xs font-bold text-text-secondary">
                  {/* Sticky Module/Route Column */}
                  <th className="sticky left-0 z-20 bg-surface-subtle px-5 py-3.5 min-w-[340px] max-w-[400px] border-r border-border-subtle shadow-[2px_0_5px_rgba(0,0,0,0.02)]">
                    <div className="flex items-center justify-between">
                      <span>Module / Sub-Action & Route</span>
                      <span className="text-[10px] font-mono text-text-muted uppercase">
                        {definitionsByModule.sortedKeys.length} Modules
                      </span>
                    </div>
                  </th>

                  {/* 11 Role Columns */}
                  {activeRoles.map((role) => {
                    const isProtected = role.level >= 100;
                    const overrideCount = overridesCountByRole[role.name] || 0;

                    return (
                      <th
                        key={role.id}
                        className="px-3.5 py-3.5 text-center min-w-[130px] border-r border-border-subtle last:border-r-0"
                      >
                        <div className="flex flex-col items-center justify-center gap-1">
                          <div className="flex items-center gap-1">
                            <span className="font-bold text-text-primary truncate max-w-[110px]" title={role.name}>
                              {role.name}
                            </span>
                            {isProtected && <Lock className="h-3 w-3 text-text-muted" />}
                          </div>

                          <div className="flex items-center gap-1.5">
                            <span
                              className={`rounded-md px-1.5 py-0.2 text-[10px] font-mono font-bold ${
                                role.level >= 90
                                  ? "bg-brand-subtle text-brand-primary border border-brand-border"
                                  : role.level >= 40
                                  ? "bg-surface-base text-text-secondary border border-border-default"
                                  : "bg-surface-subtle text-text-muted"
                              }`}
                            >
                              L{role.level}
                            </span>

                            {overrideCount > 0 && !isProtected && (
                              <button
                                type="button"
                                onClick={() => {
                                  setResetError(null);
                                  setResetReason("");
                                  setResetTarget({ roleName: role.name, overrideCount });
                                }}
                                className="inline-flex items-center gap-0.5 rounded px-1 text-[10px] font-bold text-brand-primary hover:bg-brand-subtle transition cursor-pointer"
                                title={`Reset all ${overrideCount} overrides for ${role.name}`}
                              >
                                <RotateCcw className="h-2.5 w-2.5" />
                                <span>{overrideCount}</span>
                              </button>
                            )}
                          </div>
                        </div>
                      </th>
                    );
                  })}
                </tr>
              </thead>

              {/* Table Body: Modules and Expandable Actions */}
              <tbody className="divide-y divide-border-subtle text-xs">
                {definitionsByModule.sortedKeys.map((moduleKey) => {
                  const meta = MODULE_METADATA[moduleKey];
                  const Icon = meta?.icon ?? Layers;
                  const definitions = definitionsByModule.grouped[moduleKey] || [];
                  const isCollapsed = collapsedModules[moduleKey] ?? false;

                  return (
                    <ModuleGroupRows
                      key={moduleKey}
                      moduleKey={moduleKey}
                      meta={meta}
                      Icon={Icon}
                      definitions={definitions}
                      isCollapsed={isCollapsed}
                      onToggleCollapse={() => {
                        setCollapsedModules((prev) => ({
                          ...prev,
                          [moduleKey]: !prev[moduleKey],
                        }));
                      }}
                      activeRoles={activeRoles}
                      matrixIndex={matrixIndex}
                      stagedChanges={stagedChanges}
                      onCellToggle={handleCellToggle}
                      onCellReset={handleCellReset}
                    />
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Sticky Bottom Bar for Staged Changes */}
      {stagedCount > 0 && (
        <div className="fixed bottom-0 left-0 right-0 z-40 flex flex-wrap items-center justify-between border-t border-brand-border bg-brand-subtle px-8 py-3.5 shadow-xl animate-in slide-in-from-bottom-2">
          <div className="flex items-center gap-3">
            <span className="flex h-7 w-7 items-center justify-center rounded-full bg-brand-primary text-text-inverse font-bold text-xs shadow-xs">
              {stagedCount}
            </span>
            <div>
              <h4 className="text-xs font-bold text-brand-primary">
                {stagedCount} staged permission {stagedCount === 1 ? "change" : "changes"} ready for review
              </h4>
              <p className="text-[11px] text-text-secondary">
                Changes will be saved atomically across targeted roles with audit logging.
              </p>
            </div>
          </div>

          <div className="flex items-center gap-3">
            <button
              type="button"
              onClick={handleDiscardStaged}
              className="inline-flex items-center gap-1.5 rounded-xl border border-border-default bg-surface-base px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition cursor-pointer shadow-xs"
            >
              <Undo2 className="h-3.5 w-3.5" />
              <span>Discard</span>
            </button>

            <button
              type="button"
              onClick={() => {
                setCommitReason("");
                setCommitError(null);
                setIsCommitModalOpen(true);
              }}
              className="inline-flex items-center gap-2 rounded-xl bg-brand-primary px-5 py-2 text-xs font-bold text-text-inverse shadow-xs hover:bg-brand-primary/90 transition cursor-pointer"
            >
              <Check className="h-3.5 w-3.5" />
              <span>Review & Save Changes</span>
            </button>
          </div>
        </div>
      )}

      {/* Commit Overrides Confirmation Modal */}
      <Modal
        isOpen={isCommitModalOpen}
        onClose={() => setIsCommitModalOpen(false)}
        title="Commit Permission Changes"
        subtitle={`Applying ${stagedCount} permission overrides across selected roles.`}
        icon={KeyRound}
        maxWidthClass="max-w-lg"
        isSubmitting={applyOverridesMutation.isPending}
        disableBackdropClick={applyOverridesMutation.isPending}
        isDirty={Boolean(commitReason)}
      >
        <div className="space-y-4">
          {commitError && (
            <div className="rounded-xl border border-danger-border bg-danger-subtle p-3 text-xs text-danger">
              {commitError}
            </div>
          )}

          <form onSubmit={handleConfirmCommit} className="space-y-4">
            <div>
              <label htmlFor="commit-audit-reason" className="block text-xs font-bold text-text-secondary mb-1">
                Audit Justification & Reason *
              </label>
              <textarea
                id="commit-audit-reason"
                rows={3}
                placeholder="Explain the operational rationale (e.g. Granted Vacancy Export capability to Encoder team)..."
                value={commitReason}
                onChange={(e) => setCommitReason(e.target.value)}
                className="w-full rounded-xl border border-border-default bg-surface-base p-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default"
              />
            </div>

            <div className="rounded-xl bg-surface-subtle p-3 border border-border-default max-h-44 overflow-y-auto space-y-1.5 text-xs font-mono">
              {Object.entries(stagedChanges).map(([key, val]) => {
                const [rName, , resKey, actKey] = key.split("::");
                return (
                  <div key={key} className="flex items-center justify-between py-0.5 border-b border-border-subtle last:border-b-0">
                    <span className="text-text-primary truncate max-w-[280px]">
                      <strong className="text-text-secondary">{rName}</strong>: {resKey}.{actKey}
                    </span>
                    <span className={val ? "text-brand-primary font-bold" : "text-danger font-bold"}>
                      → {val ? "ALLOW" : "DENY"}
                    </span>
                  </div>
                );
              })}
            </div>

            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                type="button"
                onClick={() => setIsCommitModalOpen(false)}
                disabled={applyOverridesMutation.isPending}
                className="rounded-xl border border-border-default px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover cursor-pointer disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={applyOverridesMutation.isPending}
                className="rounded-xl bg-brand-primary px-4 py-2 text-xs font-bold text-text-inverse shadow-xs hover:bg-brand-primary/90 disabled:opacity-50 cursor-pointer"
              >
                {applyOverridesMutation.isPending ? "Applying Overrides..." : "Confirm & Apply"}
              </button>
            </div>
          </form>
        </div>
      </Modal>

      {/* Reset Confirmation Modal */}
      <Modal
        isOpen={Boolean(resetTarget)}
        onClose={() => setResetTarget(null)}
        title="Reset Overrides to System Default"
        subtitle={
          resetTarget?.roleName
            ? `Reverting all custom permission overrides for ${resetTarget.roleName} back to base system definitions.`
            : "Reverting all custom overrides across all roles back to base system definitions."
        }
        icon={RotateCcw}
        maxWidthClass="max-w-lg"
        isSubmitting={resetOverridesMutation.isPending}
        disableBackdropClick={resetOverridesMutation.isPending}
      >
        <div className="space-y-4">
          {resetError && (
            <div className="rounded-xl border border-danger-border bg-danger-subtle p-3 text-xs text-danger">
              {resetError}
            </div>
          )}

          <div className="rounded-xl border border-border-default bg-surface-subtle p-3.5 space-y-2 text-xs text-text-secondary">
            <p className="font-semibold text-text-primary">
              {resetTarget?.roleName
                ? `Reset all ${resetTarget.overrideCount} active override(s) for ${resetTarget.roleName}?`
                : `Reset all ${resetTarget?.overrideCount} custom override(s) across the entire system?`}
            </p>
            <p>
              This action will clear all active records in <code className="font-mono text-xs">role_permission_overrides</code> and restore the default matrix defined in <code className="font-mono text-xs text-text-primary">role_permission_matrix</code>.
            </p>
          </div>

          <form onSubmit={handleConfirmReset} className="space-y-4">
            <div>
              <label htmlFor="reset-matrix-reason" className="block text-xs font-bold text-text-secondary mb-1">
                Audit Reason (Optional)
              </label>
              <textarea
                id="reset-matrix-reason"
                rows={2}
                placeholder="Explain why you are resetting these permissions (e.g. End of temporary cycle)..."
                value={resetReason}
                onChange={(e) => setResetReason(e.target.value)}
                className="w-full rounded-xl border border-border-default bg-surface-base p-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default"
              />
            </div>

            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                type="button"
                onClick={() => setResetTarget(null)}
                disabled={resetOverridesMutation.isPending}
                className="rounded-xl border border-border-default px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover cursor-pointer disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={resetOverridesMutation.isPending}
                className="rounded-xl bg-danger px-4 py-2 text-xs font-bold text-text-inverse shadow-xs hover:bg-danger/90 disabled:opacity-50 cursor-pointer"
              >
                {resetOverridesMutation.isPending ? "Resetting to Default..." : "Confirm & Reset"}
              </button>
            </div>
          </form>
        </div>
      </Modal>
    </div>
  );
}

// Subcomponent: Module Header Row + Expanded Action Child Rows
function ModuleGroupRows({
  moduleKey,
  meta,
  Icon,
  definitions,
  isCollapsed,
  onToggleCollapse,
  activeRoles,
  matrixIndex,
  stagedChanges,
  onCellToggle,
  onCellReset,
}: {
  moduleKey: string;
  meta?: { label: string; route: string; order: number };
  Icon: typeof LayoutDashboard;
  definitions: {
    moduleKey: string;
    resourceKey: string;
    actionKey: string;
    description: string | null;
    isSystemLocked: boolean;
    isSensitive: boolean;
    sortOrder: number;
  }[];
  isCollapsed: boolean;
  onToggleCollapse: () => void;
  activeRoles: GovernanceRole[];
  matrixIndex: Map<string, AllRolesMatrixRow>;
  stagedChanges: Record<string, boolean>;
  onCellToggle: (
    role: GovernanceRole,
    moduleKey: string,
    resourceKey: string,
    actionKey: string,
    row?: AllRolesMatrixRow
  ) => void;
  onCellReset: (
    role: GovernanceRole,
    moduleKey: string,
    resourceKey: string,
    actionKey: string
  ) => void;
}) {
  const label = meta?.label ?? moduleKey;
  const route = meta?.route ?? `/${moduleKey}`;

  // Find the primary "view" permission for the module header row (if any)
  const primaryViewDef = definitions.find((d) => d.actionKey === "view") ?? definitions[0];

  return (
    <>
      {/* Module Level Header Row */}
      <tr className="bg-surface-base hover:bg-surface-hover/60 transition group border-t-2 border-border-default">
        {/* Sticky Left Column: Module identity & Route badge */}
        <td className="sticky left-0 z-10 bg-surface-base group-hover:bg-surface-hover/60 px-5 py-3 border-r border-border-subtle shadow-[2px_0_5px_rgba(0,0,0,0.02)]">
          <div className="flex items-center justify-between">
            <button
              type="button"
              onClick={onToggleCollapse}
              className="flex items-center gap-2.5 text-left cursor-pointer focus:outline-hidden"
            >
              <span className="text-text-muted hover:text-text-primary transition-transform">
                {isCollapsed ? (
                  <ChevronRight className="h-4 w-4" />
                ) : (
                  <ChevronDown className="h-4 w-4" />
                )}
              </span>

              <div className="flex items-center gap-2">
                <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-surface-subtle text-text-primary border border-border-subtle">
                  <Icon className="h-3.5 w-3.5 text-brand-primary" />
                </span>
                <div>
                  <div className="font-bold text-text-primary text-xs flex items-center gap-1.5">
                    <span>{label}</span>
                  </div>
                  <div className="flex items-center gap-1.5 mt-0.5">
                    <span className="font-mono text-[11px] text-text-muted font-medium">
                      {route}
                    </span>
                    <span className="rounded bg-surface-subtle px-1.5 py-0.2 text-[10px] font-mono text-text-muted">
                      {definitions.length} {definitions.length === 1 ? "rule" : "rules"}
                    </span>
                  </div>
                </div>
              </div>
            </button>
          </div>
        </td>

        {/* Primary Route Access Toggle Across Roles */}
        {activeRoles.map((role) => {
          if (!primaryViewDef) {
            return (
              <td key={role.id} className="px-3.5 py-3 text-center border-r border-border-subtle last:border-r-0 text-text-muted text-[10px]">
                —
              </td>
            );
          }

          const cellKey = `${role.name}::${primaryViewDef.moduleKey}::${primaryViewDef.resourceKey}::${primaryViewDef.actionKey}`;
          const isStaged = cellKey in stagedChanges;
          const row = matrixIndex.get(cellKey);
          const isAllowed = isStaged ? stagedChanges[cellKey] : (row?.isAllowed ?? false);
          const hasOverride = row?.hasOverride ?? false;
          const isLocked = (role.level >= 100) || (row?.isSystemLocked ?? false);

          return (
            <td
              key={role.id}
              className={`px-3 py-2.5 text-center border-r border-border-subtle last:border-r-0 transition ${
                isStaged ? "bg-brand-subtle/50" : ""
              }`}
            >
              <div className="flex items-center justify-center gap-1">
                {hasOverride && !isLocked && (
                  <button
                    type="button"
                    onClick={() =>
                      onCellReset(
                        role,
                        primaryViewDef.moduleKey,
                        primaryViewDef.resourceKey,
                        primaryViewDef.actionKey
                      )
                    }
                    className="p-1 rounded text-text-muted hover:text-brand-primary transition cursor-pointer"
                    title={`Reset route view to base default (${row?.baseAllowed ? "Allowed" : "Denied"})`}
                  >
                    <RotateCcw className="h-3 w-3" />
                  </button>
                )}

                <SwitchToggle
                  checked={isAllowed}
                  disabled={isLocked}
                  isStaged={isStaged}
                  hasOverride={hasOverride}
                  onChange={() =>
                    onCellToggle(
                      role,
                      primaryViewDef.moduleKey,
                      primaryViewDef.resourceKey,
                      primaryViewDef.actionKey,
                      row
                    )
                  }
                />
              </div>
            </td>
          );
        })}
      </tr>

      {/* Expanded Child Action Rows */}
      {!isCollapsed &&
        definitions.map((def) => {
          // If this is the primary view def already shown on header, we still render with sub-action details
          return (
            <tr
              key={`${def.moduleKey}::${def.resourceKey}::${def.actionKey}`}
              className="bg-surface-subtle/40 hover:bg-surface-hover/40 transition"
            >
              {/* Sticky Indented Action Label Column */}
              <td className="sticky left-0 z-10 bg-surface-base hover:bg-surface-hover/40 pl-11 pr-5 py-2.5 border-r border-border-subtle shadow-[2px_0_5px_rgba(0,0,0,0.02)]">
                <div className="flex flex-col gap-0.5">
                  <div className="flex items-center gap-1.5 flex-wrap">
                    <span className="font-semibold text-text-primary text-xs">
                      {formatActionTitle(def.resourceKey, def.actionKey)}
                    </span>

                    <span className="rounded-md bg-surface-subtle px-1.5 py-0.2 font-mono text-[10px] text-text-muted border border-border-subtle">
                      {def.resourceKey}.{def.actionKey}
                    </span>

                    {def.isSystemLocked && (
                      <span className="inline-flex items-center gap-0.5 rounded px-1 py-0.2 text-[10px] font-medium text-text-secondary bg-surface-subtle border border-border-default">
                        <Lock className="h-2.5 w-2.5" /> Locked
                      </span>
                    )}

                    {def.isSensitive && (
                      <span className="rounded px-1 py-0.2 text-[10px] font-bold text-danger bg-danger-subtle border border-danger-border">
                        Sensitive
                      </span>
                    )}
                  </div>

                  {def.description && (
                    <p className="text-[11px] text-text-secondary line-clamp-1" title={def.description}>
                      {def.description}
                    </p>
                  )}
                </div>
              </td>

              {/* Sub-Action Toggle Cells Across Roles */}
              {activeRoles.map((role) => {
                const cellKey = `${role.name}::${def.moduleKey}::${def.resourceKey}::${def.actionKey}`;
                const isStaged = cellKey in stagedChanges;
                const row = matrixIndex.get(cellKey);
                const isAllowed = isStaged ? stagedChanges[cellKey] : (row?.isAllowed ?? false);
                const hasOverride = row?.hasOverride ?? false;
                const isLocked = (role.level >= 100) || (row?.isSystemLocked ?? def.isSystemLocked);

                return (
                  <td
                    key={role.id}
                    className={`px-3 py-2 text-center border-r border-border-subtle last:border-r-0 transition ${
                      isStaged ? "bg-brand-subtle/50" : ""
                    }`}
                  >
                    <div className="flex items-center justify-center gap-1">
                      {hasOverride && !isLocked && (
                        <button
                          type="button"
                          onClick={() =>
                            onCellReset(role, def.moduleKey, def.resourceKey, def.actionKey)
                          }
                          className="p-1 rounded text-text-muted hover:text-brand-primary transition cursor-pointer"
                          title={`Reset to base default (${row?.baseAllowed ? "Allowed" : "Denied"})`}
                        >
                          <RotateCcw className="h-3 w-3" />
                        </button>
                      )}

                      <SwitchToggle
                        checked={isAllowed}
                        disabled={isLocked}
                        isStaged={isStaged}
                        hasOverride={hasOverride}
                        onChange={() =>
                          onCellToggle(role, def.moduleKey, def.resourceKey, def.actionKey, row)
                        }
                      />
                    </div>
                  </td>
                );
              })}
            </tr>
          );
        })}
    </>
  );
}

// Reusable Clean Toggle Switch Component
function SwitchToggle({
  checked,
  disabled,
  isStaged,
  hasOverride,
  onChange,
}: {
  checked: boolean;
  disabled?: boolean;
  isStaged?: boolean;
  hasOverride?: boolean;
  onChange: () => void;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      onClick={onChange}
      className={`relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full transition-colors duration-200 ease-in-out focus:outline-hidden disabled:opacity-40 disabled:cursor-not-allowed ${
        checked ? "bg-brand-primary" : "bg-border-default"
      } ${
        isStaged ? "ring-2 ring-brand-default ring-offset-1" : ""
      } ${
        hasOverride && !isStaged ? "ring-1 ring-brand-border" : ""
      }`}
    >
      <span
        aria-hidden="true"
        className={`pointer-events-none inline-block h-4 w-4 transform rounded-full bg-surface-base shadow-sm ring-0 transition duration-200 ease-in-out mt-0.5 ${
          checked ? "translate-x-4.5" : "translate-x-0.5"
        }`}
      />
    </button>
  );
}

// Helper to convert technical snake_case keys into conversational labels
function formatActionTitle(resourceKey: string, actionKey: string): string {
  const combined = `${resourceKey} ${actionKey}`.replace(/_/g, " ");
  return combined
    .split(" ")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
    .join(" ");
}
