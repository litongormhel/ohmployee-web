"use client";

import { useState } from "react";
import {
  AlertCircle,
  Building2,
  CheckCircle2,
  ChevronRight,
  Layers,
  MapPin,
  Plus,
  RefreshCw,
  Search,
  Users2,
  X,
} from "lucide-react";
import {
  useCoverageGroups,
  useCoverageGroupDetail,
  type CoverageGroupSummaryItem,
} from "@/lib/queries/more";
import { useCurrentUser } from "@/lib/auth";

export interface RovingCoverageGroupsModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function RovingCoverageGroupsModal({
  isOpen,
  onClose,
}: RovingCoverageGroupsModalProps) {
  const currentUser = useCurrentUser();
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

  if (!isOpen) return null;

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
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="roving-groups-title"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/70 backdrop-blur-xs animate-in fade-in duration-200"
    >
      <div className="relative w-full max-w-5xl bg-white rounded-2xl shadow-2xl border border-slate-200 overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4.5 border-b border-slate-200 bg-slate-50/80">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-blue-100 text-blue-700 flex items-center justify-center shadow-xs">
              <Users2 className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 id="roving-groups-title" className="text-base font-bold text-slate-900 leading-tight">
                  Roving Coverage Groups
                </h2>
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-blue-100 text-blue-800">
                  STORE COVERAGE POOLS
                </span>
              </div>
              <p className="text-xs text-slate-500">
                Inspect multi-store reliever assignment clusters, roving headcounts, and anchor stores
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1.5 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-200/60 transition-colors"
            aria-label="Close modal"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content Layout: 2 Columns on desktop */}
        <div className="flex-1 overflow-hidden flex flex-col md:flex-row divide-y md:divide-y-0 md:divide-x divide-slate-200">
          {/* Left Column: Group List */}
          <div className="w-full md:w-1/2 flex flex-col h-full bg-slate-50/30">
            {/* Search toolbar */}
            <div className="p-4 border-b border-slate-200 bg-white">
              <div className="relative">
                <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
                <input
                  type="text"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  placeholder="Filter by coverage code, account, or area..."
                  className="w-full pl-9 pr-3 py-2 text-xs border border-slate-200 rounded-xl bg-white focus:outline-hidden focus:ring-2 focus:ring-blue-500"
                />
              </div>
            </div>

            {/* List */}
            <div className="flex-1 overflow-y-auto p-4 space-y-2.5">
              {isLoading ? (
                <div className="py-12 text-center text-xs text-slate-400">Loading coverage groups...</div>
              ) : filteredGroups.length === 0 ? (
                <div className="py-12 text-center text-xs text-slate-400">
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
                          ? "bg-blue-50/70 border-blue-400 ring-1 ring-blue-400"
                          : "bg-white border-slate-200 hover:border-slate-300"
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <span className="font-mono text-xs font-bold text-slate-900">
                          {group.coverageCode}
                        </span>
                        <span
                          className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                            group.groupStatus === "Active"
                              ? "bg-emerald-100 text-emerald-800"
                              : "bg-slate-100 text-slate-600"
                          }`}
                        >
                          {group.groupStatus.toUpperCase()}
                        </span>
                      </div>

                      <div className="mt-1 flex items-center gap-2 text-xs text-slate-700">
                        <Building2 className="w-3.5 h-3.5 text-slate-400 shrink-0" />
                        <span className="font-semibold truncate">{group.accountName}</span>
                        {group.groupName && (
                          <span className="text-[11px] text-slate-400">({group.groupName})</span>
                        )}
                      </div>

                      <div className="mt-2 flex items-center justify-between text-[11px] text-slate-500 border-t border-slate-100 pt-2">
                        <span>Position: {group.positionName}</span>
                        <span>{group.activeStoreCount} stores</span>
                      </div>

                      <div className="mt-1 flex items-center gap-3 text-[11px]">
                        <span className="text-blue-700 font-semibold">
                          Req: {group.requiredHc}
                        </span>
                        <span className="text-slate-500">
                          Open: {group.openCount}
                        </span>
                        <span className="text-emerald-700 font-semibold">
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
          <div className="w-full md:w-1/2 flex flex-col h-full bg-white overflow-y-auto p-6">
            {!selectedGroupId ? (
              <div className="h-full flex flex-col items-center justify-center text-center p-6 text-slate-400">
                <Users2 className="w-10 h-10 mb-2 stroke-1" />
                <p className="text-xs font-semibold text-slate-600">Select a Coverage Group</p>
                <p className="text-[11px] text-slate-400 mt-1 max-w-xs">
                  Choose any coverage pool from the list to review designated cluster stores, slots, and anchor location.
                </p>
              </div>
            ) : detailLoading ? (
              <div className="py-20 text-center text-xs text-slate-400">Loading group details...</div>
            ) : !selectedDetail ? (
              <div className="py-20 text-center text-xs text-slate-400">Unable to load group detail.</div>
            ) : (
              <div className="space-y-6">
                <div>
                  <div className="flex items-center justify-between">
                    <h3 className="text-base font-bold text-slate-900 font-mono">
                      {selectedDetail.coverageCode}
                    </h3>
                    <span className="px-2 py-0.5 rounded text-[10px] font-bold bg-blue-100 text-blue-800">
                      {selectedDetail.employmentType}
                    </span>
                  </div>
                  <p className="text-xs text-slate-500 mt-0.5">
                    {selectedDetail.accountName} • {selectedDetail.positionName}
                  </p>
                </div>

                {/* KPI block */}
                <div className="grid grid-cols-2 gap-3">
                  <div className="p-3 rounded-xl bg-slate-50 border border-slate-200">
                    <span className="text-[10px] uppercase font-bold text-slate-400">
                      Cluster Stores
                    </span>
                    <p className="text-lg font-bold text-slate-900 mt-0.5">
                      {selectedDetail.stores.length}
                    </p>
                  </div>
                  <div className="p-3 rounded-xl bg-slate-50 border border-slate-200">
                    <span className="text-[10px] uppercase font-bold text-slate-400">
                      Headcount Slots
                    </span>
                    <p className="text-lg font-bold text-slate-900 mt-0.5">
                      {selectedDetail.slots.length}
                    </p>
                  </div>
                </div>

                {/* Stores in Group */}
                <div>
                  <h4 className="text-xs font-bold uppercase tracking-wider text-slate-700 mb-2 flex items-center gap-1.5">
                    <MapPin className="w-3.5 h-3.5 text-blue-600" />
                    <span>Designated Stores ({selectedDetail.stores.length})</span>
                  </h4>
                  <div className="space-y-1.5 max-h-48 overflow-y-auto">
                    {selectedDetail.stores.map((s) => (
                      <div
                        key={s.id}
                        className="p-2.5 rounded-lg border border-slate-200 bg-slate-50/50 flex items-center justify-between text-xs"
                      >
                        <div>
                          <div className="font-semibold text-slate-800">{s.storeName}</div>
                          {(s.areaCity || s.areaProvince) && (
                            <div className="text-[10px] text-slate-400">
                              {[s.areaCity, s.areaProvince].filter(Boolean).join(", ")}
                            </div>
                          )}
                        </div>
                        {s.isAnchor && (
                          <span className="px-2 py-0.5 rounded-full text-[9px] font-bold bg-amber-100 text-amber-900 border border-amber-300">
                            ANCHOR
                          </span>
                        )}
                      </div>
                    ))}
                  </div>
                </div>

                {/* Slots in Group */}
                <div>
                  <h4 className="text-xs font-bold uppercase tracking-wider text-slate-700 mb-2 flex items-center gap-1.5">
                    <Layers className="w-3.5 h-3.5 text-blue-600" />
                    <span>Coverage Slots ({selectedDetail.slots.length})</span>
                  </h4>
                  <div className="space-y-1.5 max-h-48 overflow-y-auto">
                    {selectedDetail.slots.map((sl) => (
                      <div
                        key={sl.id}
                        className="p-2.5 rounded-lg border border-slate-200 bg-slate-50/50 flex items-center justify-between text-xs"
                      >
                        <span className="font-mono font-bold text-slate-700">{sl.vcode}</span>
                        <div className="flex items-center gap-2">
                          <span className="text-slate-600 text-[11px]">
                            {sl.assignedEmployeeName || "Unassigned Slot"}
                          </span>
                          <span
                            className={`px-1.5 py-0.2 rounded text-[10px] font-bold ${
                              sl.slotStatus.toLowerCase() === "occupied"
                                ? "bg-emerald-100 text-emerald-800"
                                : "bg-blue-100 text-blue-800"
                            }`}
                          >
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
        <div className="flex items-center justify-between px-6 py-4 border-t border-slate-200 bg-slate-50/50">
          <button
            type="button"
            onClick={() => refetch()}
            disabled={isFetching}
            className="flex items-center gap-1.5 text-xs text-slate-500 hover:text-slate-800"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${isFetching ? "animate-spin" : ""}`} />
            <span>Refresh Groups</span>
          </button>
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-medium text-slate-700 bg-white border border-slate-300 rounded-xl hover:bg-slate-50 transition-colors"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
