"use client";

import { useState } from "react";
import {
  Building2,
  Layers,
  MapPin,
  RefreshCw,
  Search,
  Users2,
} from "lucide-react";
import {
  useCoverageGroups,
  useCoverageGroupDetail,
} from "@/lib/queries/more";
import { Modal } from "@/components/shared/Modal";

export interface RovingCoverageGroupsModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function RovingCoverageGroupsModal({
  isOpen,
  onClose,
}: RovingCoverageGroupsModalProps) {
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedGroupId, setSelectedGroupId] = useState<string | null>(null);

  const {
    data: coverageGroups = [],
    isLoading,
    refetch,
    isFetching,
  } = useCoverageGroups();

  const {
    data: selectedDetail,
    isLoading: detailLoading,
  } = useCoverageGroupDetail(selectedGroupId);

  const filteredGroups = coverageGroups.filter((g) => {
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    return (
      g.coverageCode.toLowerCase().includes(q) ||
      g.accountName.toLowerCase().includes(q) ||
      g.positionName.toLowerCase().includes(q) ||
      (g.areaName && g.areaName.toLowerCase().includes(q)) ||
      (g.storePreview && g.storePreview.toLowerCase().includes(q))
    );
  });

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Roving Coverage Groups"
      subtitle="Inspect multi-store reliever assignment clusters, roving headcounts, and anchor stores."
      icon={Users2}
      maxWidthClass="max-w-5xl"
    >
      <div className="flex flex-col h-[75vh]">
        {/* Content Layout: 2 Columns on desktop */}
        <div className="flex-1 overflow-hidden flex flex-col md:flex-row divide-y md:divide-y-0 md:divide-x divide-border-subtle">
          {/* Left Column: Group List */}
          <div className="w-full md:w-1/2 flex flex-col h-full bg-surface-subtle/30">
            {/* Search toolbar */}
            <div className="p-4 border-b border-border-subtle bg-surface-base">
              <div className="relative">
                <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-text-muted" />
                <input
                  type="text"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  placeholder="Filter by coverage code, account, or area..."
                  className="w-full pl-9 pr-3 py-2 text-xs border border-border-default rounded-xl bg-surface-base text-text-primary placeholder:text-text-muted focus:outline-hidden focus:border-brand-default focus:ring-1 focus:ring-brand-default"
                />
              </div>
            </div>

            {/* List */}
            <div className="flex-1 overflow-y-auto p-4 space-y-2.5">
              {isLoading ? (
                <div className="py-12 text-center text-xs text-text-muted">Loading coverage groups...</div>
              ) : filteredGroups.length === 0 ? (
                <div className="py-12 text-center text-xs text-text-muted">
                  {searchQuery ? "No matching coverage groups found." : "No roving coverage groups configured."}
                </div>
              ) : (
                filteredGroups.map((group) => {
                  const isSelected = selectedGroupId === group.coverageGroupId;
                  return (
                    <div
                      key={group.coverageGroupId}
                      onClick={() => setSelectedGroupId(group.coverageGroupId)}
                      className={`p-3.5 rounded-xl border transition-all cursor-pointer shadow-2xs ${
                        isSelected
                          ? "bg-brand-subtle border-brand-default ring-1 ring-brand-default"
                          : "bg-surface-base border-border-default hover:border-border-strong"
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <span className="font-mono text-xs font-bold text-text-primary">
                          {group.coverageCode}
                        </span>
                        <span className="px-2 py-0.5 rounded text-xs font-bold bg-surface-subtle text-text-primary border border-border-default">
                          {group.groupStatus.toUpperCase()}
                        </span>
                      </div>

                      <div className="mt-1 flex items-center gap-2 text-sm text-text-primary">
                        <Building2 className="w-3.5 h-3.5 text-text-muted shrink-0" />
                        <span className="font-semibold truncate">{group.accountName}</span>
                        {group.groupName && (
                          <span className="text-xs text-text-muted">({group.groupName})</span>
                        )}
                      </div>

                      <div className="mt-2 flex items-center justify-between text-xs text-text-muted border-t border-border-subtle pt-2">
                        <span>Position: {group.positionName}</span>
                        <span>{group.activeStoreCount} stores</span>
                      </div>

                      <div className="mt-1 flex items-center gap-3 text-xs">
                        <span className="text-brand-primary font-semibold">
                          Req: {group.requiredHc}
                        </span>
                        <span className="text-text-muted">
                          Open: {group.openCount}
                        </span>
                        <span className="text-text-primary font-semibold">
                          Active: {group.activeCount}
                        </span>
                      </div>
                    </div>
                  );
                })
              )}
            </div>
          </div>

          {/* Right Column: Group Inspection Details */}
          <div className="w-full md:w-1/2 flex flex-col h-full bg-surface-base overflow-y-auto p-6">
            {!selectedGroupId ? (
              <div className="h-full flex flex-col items-center justify-center text-center p-6 text-text-muted">
                <Users2 className="w-10 h-10 mb-2 stroke-1" />
                <p className="text-xs font-semibold text-text-secondary">Select a Coverage Group</p>
                <p className="text-xs text-text-muted mt-1 max-w-xs">
                  Choose any coverage pool from the list to review designated cluster stores, slots, and anchor location.
                </p>
              </div>
            ) : detailLoading ? (
              <div className="py-20 text-center text-xs text-text-muted">Loading group details...</div>
            ) : !selectedDetail ? (
              <div className="py-20 text-center text-xs text-text-muted">Unable to load group detail.</div>
            ) : (
              <div className="space-y-6">
                <div>
                  <div className="flex items-center justify-between">
                    <h3 className="text-base font-bold text-text-primary font-mono">
                      {selectedDetail.coverageCode}
                    </h3>
                    <span className="px-2 py-0.5 rounded text-xs font-bold bg-surface-subtle text-text-secondary border border-border-default">
                      {selectedDetail.employmentType}
                    </span>
                  </div>
                  <p className="text-xs text-text-muted mt-0.5">
                    {selectedDetail.accountName} • {selectedDetail.positionName}
                  </p>
                </div>

                {/* KPI block */}
                <div className="grid grid-cols-2 gap-3">
                  <div className="p-3 rounded-xl bg-surface-subtle border border-border-default">
                    <span className="text-xs font-bold text-text-muted">
                      Cluster Stores
                    </span>
                    <p className="text-lg font-bold text-text-primary mt-0.5">
                      {selectedDetail.stores.length}
                    </p>
                  </div>
                  <div className="p-3 rounded-xl bg-surface-subtle border border-border-default">
                    <span className="text-xs font-bold text-text-muted">
                      Headcount Slots
                    </span>
                    <p className="text-lg font-bold text-text-primary mt-0.5">
                      {selectedDetail.slots.length}
                    </p>
                  </div>
                </div>

                {/* Stores in Group */}
                <div>
                  <h4 className="text-xs font-bold text-text-secondary mb-2 flex items-center gap-1.5">
                    <MapPin className="w-3.5 h-3.5 text-brand-primary" />
                    <span>Designated Stores ({selectedDetail.stores.length})</span>
                  </h4>
                  <div className="space-y-1.5 max-h-48 overflow-y-auto">
                    {selectedDetail.stores.map((s) => (
                      <div
                        key={s.id}
                        className="p-2.5 rounded-lg border border-border-default bg-surface-subtle/50 flex items-center justify-between text-xs"
                      >
                        <div>
                          <div className="font-semibold text-text-primary">{s.storeName}</div>
                          {(s.areaCity || s.areaProvince) && (
                            <div className="text-xs text-text-muted">
                              {[s.areaCity, s.areaProvince].filter(Boolean).join(", ")}
                            </div>
                          )}
                        </div>
                        {s.isAnchor && (
                          <span className="px-2 py-0.5 rounded-full text-xs font-semibold bg-surface-subtle text-text-primary border border-border-default">
                            Anchor
                          </span>
                        )}
                      </div>
                    ))}
                  </div>
                </div>

                {/* Slots in Group */}
                <div>
                  <h4 className="text-xs font-bold text-text-secondary mb-2 flex items-center gap-1.5">
                    <Layers className="w-3.5 h-3.5 text-brand-primary" />
                    <span>Coverage Slots ({selectedDetail.slots.length})</span>
                  </h4>
                  <div className="space-y-1.5 max-h-48 overflow-y-auto">
                    {selectedDetail.slots.map((sl) => (
                      <div
                        key={sl.id}
                        className="p-2.5 rounded-lg border border-border-default bg-surface-subtle/50 flex items-center justify-between text-xs"
                      >
                        <span className="font-mono font-bold text-text-primary">{sl.vcode}</span>
                        <div className="flex items-center gap-2">
                          <span className="text-text-secondary text-xs">
                            {sl.assignedEmployeeName || "Unassigned Slot"}
                          </span>
                          <span className="px-1.5 py-0.2 rounded text-xs font-bold bg-surface-subtle text-text-primary border border-border-default">
                            {sl.slotStatus}
                          </span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-2 py-3 border-t border-border-subtle bg-surface-base">
          <button
            type="button"
            onClick={() => refetch()}
            disabled={isFetching}
            className="flex items-center gap-1.5 text-xs text-text-secondary hover:text-text-primary cursor-pointer"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${isFetching ? "animate-spin text-brand-primary" : ""}`} />
            <span>Refresh Groups</span>
          </button>
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-semibold text-text-secondary bg-surface-base border border-border-default rounded-xl hover:bg-surface-hover transition-colors cursor-pointer"
          >
            Close
          </button>
        </div>
      </div>
    </Modal>
  );
}
