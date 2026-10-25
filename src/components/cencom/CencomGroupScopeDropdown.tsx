"use client";

import { useEffect, useMemo } from "react";
import { formatGroupName } from "@/lib/queries/vacancy";
import type { CencomGroupKpiItem } from "@/lib/queries/cencom";
import { ScopeDropdown, type ScopeOption } from "@/components/shared/ScopeDropdown";

export interface GroupScopeOption {
  id: string; // "all" or groupId
  label: string;
  code: string | null;
}

export interface CencomGroupScopeDropdownProps {
  groups: CencomGroupKpiItem[];
  allowedGroupIds?: string[] | null; // null or undefined means broad access (all groups allowed)
  selectedGroupId: string; // "all" or specific groupId
  onSelectGroup: (groupId: string) => void;
  disabled?: boolean;
}

export function CencomGroupScopeDropdown({
  groups,
  allowedGroupIds,
  selectedGroupId,
  onSelectGroup,
}: CencomGroupScopeDropdownProps) {
  // 1. Build and sort permitted group options
  const options = useMemo<GroupScopeOption[]>(() => {
    // Filter groups by user's permitted scope if scoped
    const permitted =
      allowedGroupIds && allowedGroupIds.length > 0
        ? groups.filter((g) => allowedGroupIds.includes(g.groupId))
        : groups;

    // Sort by group_code ascending (ADR-001 Rule 5), fallback by name
    const sorted = [...permitted].sort((a, b) => {
      const codeA = a.groupCode ?? a.groupName;
      const codeB = b.groupCode ?? b.groupName;
      return codeA.localeCompare(codeB, undefined, { numeric: true });
    });

    return [
      { id: "all", label: "All groups", code: null },
      ...sorted.map((g) => ({
        id: g.groupId,
        label: formatGroupName(g.groupName) || g.groupName || "Group",
        code: g.groupCode,
      })),
    ];
  }, [groups, allowedGroupIds]);

  // 2. Ensure stale selection falls back to "all" if selected group is no longer available
  const isSelectionValid = options.some((opt) => opt.id === selectedGroupId);
  const effectiveValue = isSelectionValid ? selectedGroupId : "all";

  useEffect(() => {
    if (!isSelectionValid && selectedGroupId !== "all") {
      onSelectGroup("all");
    }
  }, [isSelectionValid, selectedGroupId, onSelectGroup]);

  const scopeOptions = useMemo<ScopeOption[]>(() => {
    return options.map((opt) => ({
      value: opt.id,
      label: opt.label,
      badge: opt.code ?? undefined,
    }));
  }, [options]);

  return (
    <ScopeDropdown
      value={effectiveValue}
      options={scopeOptions}
      onChange={onSelectGroup}
      ariaLabel="Group scope"
    />
  );
}
