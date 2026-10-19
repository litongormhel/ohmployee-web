"use client";

import { useState } from "react";
import { Clock, Filter, Layers, Search } from "lucide-react";
import { DetailDrawer } from "@/components/shared/DetailDrawer";
import { DataState } from "@/components/shared/DataState";
import { StatusBadge } from "@/components/ui/StatusBadge";
import {
  useOpenPoolSlots,
  useWorkforcePoolTypes,
} from "@/lib/queries/workforcePool";

export interface PoolOpenSlotsDrawerProps {
  isOpen: boolean;
  onClose: () => void;
}

export function PoolOpenSlotsDrawer({ isOpen, onClose }: PoolOpenSlotsDrawerProps) {
  const [selectedType, setSelectedType] = useState<string>("all");
  const [searchTerm, setSearchTerm] = useState<string>("");

  const poolTypesQuery = useWorkforcePoolTypes();
  const openSlotsQuery = useOpenPoolSlots(selectedType === "all" ? null : selectedType);

  const filteredSlots = (openSlotsQuery.data ?? []).filter((s) => {
    if (!searchTerm.trim()) return true;
    const term = searchTerm.toLowerCase();
    return (
      s.vcode.toLowerCase().includes(term) ||
      (s.position ?? "").toLowerCase().includes(term) ||
      (s.poolTypeName ?? "").toLowerCase().includes(term) ||
      (s.account ?? "").toLowerCase().includes(term)
    );
  });

  return (
    <DetailDrawer
      isOpen={isOpen}
      onClose={onClose}
      title="Approved Open Pool Slots"
      subtitle="Vacant slot inventory waiting for reliever/commando hiring & endorsement"
    >
      <div className="p-6 space-y-6">
        {/* Controls */}
        <div className="flex flex-col sm:flex-row gap-3">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
            <input
              type="text"
              placeholder="Filter by VCode, position, account..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full pl-9 pr-3 py-2 text-xs rounded-lg border border-gray-200 focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
          <div className="flex items-center gap-2">
            <Filter className="h-4 w-4 text-gray-400" />
            <select
              value={selectedType}
              onChange={(e) => setSelectedType(e.target.value)}
              className="text-xs rounded-lg border border-gray-200 py-2 px-3 bg-white focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              <option value="all">All Pool Types</option>
              {(poolTypesQuery.data ?? []).map((t) => (
                <option key={t.id} value={t.id}>
                  {t.name}
                </option>
              ))}
            </select>
          </div>
        </div>

        {/* Counter Header */}
        <div className="flex items-center justify-between text-xs text-gray-500 border-b border-gray-100 pb-2">
          <span>
            Showing <strong className="text-gray-900">{filteredSlots.length}</strong> open slots
          </span>
          <span className="flex items-center gap-1.5 text-blue-600 font-medium">
            <Layers className="h-3.5 w-3.5" /> Slot-first Authority
          </span>
        </div>

        {/* List */}
        {openSlotsQuery.isLoading ? (
          <DataState state="loading" message="Loading open pool slots..." />
        ) : filteredSlots.length === 0 ? (
          <DataState
            state="empty"
            title="No open slots found"
            message="All pool quotas are currently fully occupied, or no approved vacancies match your filter."
          />
        ) : (
          <div className="divide-y divide-gray-100 border border-gray-100 rounded-xl overflow-hidden bg-white shadow-xs">
            {filteredSlots.map((slot) => {
              const daysOld = slot.daysOpen;
              return (
                <div key={slot.id} className="p-4 hover:bg-gray-50/70 transition flex items-center justify-between gap-4">
                  <div className="space-y-1">
                    <div className="flex items-center gap-2">
                      <span className="font-mono text-xs font-bold text-blue-600 bg-blue-50 px-2 py-0.5 rounded border border-blue-200">
                        {slot.vcode}
                      </span>
                      <span className="text-sm font-semibold text-gray-900">
                        {slot.position || "Pooled Personnel"}
                      </span>
                    </div>
                    <div className="flex items-center gap-3 text-xs text-gray-500">
                      <span>{slot.poolTypeName || "Workforce Pool"}</span>
                      {slot.account && <span>&bull; {slot.account}</span>}
                    </div>
                  </div>

                  <div className="flex items-center gap-3 shrink-0">
                    {daysOld !== null && (
                      <span className="flex items-center gap-1 text-xs text-gray-400 font-mono">
                        <Clock className="h-3.5 w-3.5" />
                        {daysOld}d open
                      </span>
                    )}
                    <StatusBadge variant="info">
                      Open Slot
                    </StatusBadge>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </DetailDrawer>
  );
}
