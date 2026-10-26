"use client";

import { useMemo, type ReactNode } from "react";
import { useCurrentUser } from "@/lib/auth";
import {
  getRoleLevel,
  normalizeRole,
  canPerformDrawerAction,
  isOwner,
  hasFullAccess,
  isDataTeam,
  isOpsTeam,
  isEncoder,
  type DrawerActionItem,
} from "@/lib/rbac";

export function useRolePermissions() {
  const currentUser = useCurrentUser();

  const roleLevel = useMemo(() => getRoleLevel(currentUser), [currentUser]);
  const role = useMemo(
    () => normalizeRole(currentUser?.roleKey || currentUser?.roleName),
    [currentUser]
  );

  const permissions = useMemo(() => {
    return {
      currentUser,
      roleLevel,
      role,
      isOwner: isOwner(currentUser),
      hasFullAccess: hasFullAccess(currentUser),
      isDataTeam: isDataTeam(currentUser),
      isOpsTeam: isOpsTeam(currentUser),
      isEncoder: isEncoder(currentUser),

      canPerformAction: (actionItem: DrawerActionItem): boolean => {
        return canPerformDrawerAction(actionItem, currentUser);
      },
    };
  }, [currentUser, roleLevel, role]);

  return permissions;
}

export interface RoleGuardProps {
  action?: DrawerActionItem;
  minLevel?: number;
  fallback?: ReactNode;
  children: ReactNode;
}

/**
 * RoleGuard component to conditionally render UI controls based on the RBAC matrix.
 */
export function RoleGuard({
  action,
  minLevel,
  fallback = null,
  children,
}: RoleGuardProps) {
  const { canPerformAction, roleLevel } = useRolePermissions();

  if (action && !canPerformAction(action)) {
    return <>{fallback}</>;
  }

  if (typeof minLevel === "number" && roleLevel < minLevel) {
    return <>{fallback}</>;
  }

  return <>{children}</>;
}
