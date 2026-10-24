"use client";

import { useEffect, useId, useMemo } from "react";
import { ChevronDown, Filter } from "lucide-react";
import { formatGroupName } from "@/lib/queries/vacancy";
import type { CencomGroupKpiItem } from "@/lib/queries/cencom";

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
  disabled = false,
}: CencomGroupScopeDropdownProps) {
  const selectId = useId();

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

  return (
    <div className="relative inline-flex items-center">
      <label htmlFor={selectId} className="sr-only">
        Group scope
      </label>
      <div className="pointer-events-none absolute left-3 flex items-center text-text-muted">
        <Filter className="h-3.5 w-3.5" aria-hidden="true" />
      </div>
      <select
        id={selectId}
        aria-label="Group scope"
        value={effectiveValue}
        onChange={(e) => onSelectGroup(e.target.value)}
        disabled={disabled}
        className="h-9 min-w-[140px] max-w-[200px] cursor-pointer appearance-none rounded-lg border border-border-default bg-surface-base pl-8 pr-8 text-xs font-semibold text-text-primary shadow-2xs transition-colors hover:bg-surface-hover focus:border-border-strong focus:outline-none focus:ring-1 focus:ring-border-strong disabled:cursor-not-allowed disabled:opacity-50"
      >
        {options.map((opt) => (
          <option key={opt.id} value={opt.id} className="bg-surface-base text-text-primary">
            {opt.label}
            {opt.code ? ` (${opt.code})` : ""}
          </option>
        ))}
      </select>
      <div className="pointer-events-none absolute right-2.5 flex items-center text-text-muted">
        <ChevronDown className="h-3.5 w-3.5" aria-hidden="true" />
      </div>
    </div>
  );
}
