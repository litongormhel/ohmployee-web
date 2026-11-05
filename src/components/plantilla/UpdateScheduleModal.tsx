"use client";

import React, { useState, useMemo } from "react";
import {
  Clock,
  Loader2,
  Calendar,
  Building2,
  Plus,
  Trash2,
  AlertTriangle,
  CheckCircle2,
} from "lucide-react";
import { updatePlantillaSchedule, type StoreAllocationInput } from "@/lib/queries/plantilla";
import { Modal } from "@/components/shared/Modal";

export interface StoreAllocationItem {
  storeId?: string | null;
  storeName: string;
  vcode?: string | null;
  scheduleDays?: string | null;
  scheduleTime?: string | null;
  allocationPercent: number; // 100 = 1.00 HC, 50 = 0.50 HC
}

export interface UpdateScheduleModalProps {
  isOpen: boolean;
  onClose: () => void;
  plantillaId: string;
  employeeNo?: string | null;
  employeeName?: string | null;
  initialScheduleDays?: string | null;
  initialScheduleTime?: string | null;
  initialDayoff?: string | null;
  initialStoreAllocations?: StoreAllocationItem[];
  availableStores?: Array<{ id: string; name: string; vcode?: string | null }>;
  onSuccess: () => void;
}

const DAYS_OF_WEEK = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"] as const;

const TIME_PRESETS = [
  "08:00 AM - 05:00 PM",
  "09:00 AM - 06:00 PM",
  "07:00 AM - 04:00 PM",
  "10:00 AM - 07:00 PM",
  "FLEXI (8 HRS)",
];

export function UpdateScheduleModal({
  isOpen,
  onClose,
  plantillaId,
  employeeNo,
  employeeName,
  initialScheduleDays,
  initialScheduleTime,
  initialDayoff,
  initialStoreAllocations,
  availableStores = [],
  onSuccess,
}: UpdateScheduleModalProps) {
  // Global terms
  const [dayoff, setDayoff] = useState<string>(
    initialDayoff ? initialDayoff.trim().toUpperCase() : "SUN"
  );
  const [globalShiftTime, setGlobalShiftTime] = useState<string>(
    initialScheduleTime ?? "08:00 AM - 05:00 PM"
  );

  // Store allocations matrix
  const defaultAllocations: StoreAllocationItem[] = useMemo(() => {
    if (initialStoreAllocations && initialStoreAllocations.length > 0) {
      return initialStoreAllocations.map((a) => ({
        storeId: a.storeId ?? "",
        storeName: a.storeName || "Primary Store",
        vcode: a.vcode ?? "",
        scheduleDays: a.scheduleDays ?? initialScheduleDays ?? "MON-SAT",
        scheduleTime: a.scheduleTime ?? initialScheduleTime ?? "08:00 AM - 05:00 PM",
        allocationPercent: a.allocationPercent ?? (initialStoreAllocations.length > 1 ? Math.round(100 / initialStoreAllocations.length) : 100),
      }));
    }
    return [
      {
        storeId: "",
        storeName: "Primary Store Assignment",
        vcode: "",
        scheduleDays: initialScheduleDays ?? "MON-SAT",
        scheduleTime: initialScheduleTime ?? "08:00 AM - 05:00 PM",
        allocationPercent: 100,
      },
    ];
  }, [initialStoreAllocations, initialScheduleDays, initialScheduleTime]);

  const [allocations, setAllocations] = useState<StoreAllocationItem[]>(defaultAllocations);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Total HC calculation & validation
  const totalPercent = useMemo(() => {
    return allocations.reduce((sum, item) => sum + (Number(item.allocationPercent) || 0), 0);
  }, [allocations]);

  const totalHcShare = (totalPercent / 100).toFixed(2);
  const isHcValid = Math.abs(totalPercent - 100) < 0.01;

  // Check if any allocation day conflicts with rest day
  const hasRestDayConflict = useMemo(() => {
    return allocations.some((item) => {
      const days = (item.scheduleDays || "").toUpperCase();
      return days.includes(dayoff);
    });
  }, [allocations, dayoff]);

  const isDirty = useMemo(() => {
    if (dayoff !== (initialDayoff ?? "SUN")) return true;
    if (allocations.length !== defaultAllocations.length) return true;
    for (let i = 0; i < allocations.length; i++) {
      if (
        allocations[i].storeName !== defaultAllocations[i]?.storeName ||
        allocations[i].allocationPercent !== defaultAllocations[i]?.allocationPercent ||
        allocations[i].scheduleDays !== defaultAllocations[i]?.scheduleDays ||
        allocations[i].scheduleTime !== defaultAllocations[i]?.scheduleTime
      ) {
        return true;
      }
    }
    return false;
  }, [dayoff, initialDayoff, allocations, defaultAllocations]);

  // Handle adding roving store
  const handleAddStore = () => {
    const nextCount = allocations.length + 1;
    const splitPercent = Math.floor(100 / nextCount);
    const remainder = 100 - splitPercent * nextCount;

    const newAllocations = allocations.map((item, idx) => ({
      ...item,
      allocationPercent: idx === 0 ? splitPercent + remainder : splitPercent,
    }));

    newAllocations.push({
      storeId: "",
      storeName: `Coverage Branch ${nextCount}`,
      vcode: "",
      scheduleDays: "THU-SAT",
      scheduleTime: globalShiftTime,
      allocationPercent: splitPercent,
    });

    setAllocations(newAllocations);
  };

  // Handle removing store
  const handleRemoveStore = (indexToRemove: number) => {
    if (allocations.length <= 1) return;
    const remaining = allocations.filter((_, idx) => idx !== indexToRemove);
    const splitPercent = Math.floor(100 / remaining.length);
    const remainder = 100 - splitPercent * remaining.length;

    setAllocations(
      remaining.map((item, idx) => ({
        ...item,
        allocationPercent: idx === 0 ? splitPercent + remainder : splitPercent,
      }))
    );
  };

  // Update allocation field
  const updateAllocation = (index: number, patch: Partial<StoreAllocationItem>) => {
    setAllocations((prev) =>
      prev.map((item, idx) => (idx === index ? { ...item, ...patch } : item))
    );
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!isHcValid) {
      setErrorMessage("Total Headcount (HC) Share across all assigned stores must equal exactly 1.00 (100%).");
      return;
    }

    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      const storeAllocationsPayload: StoreAllocationInput[] = allocations.map((a) => ({
        storeId: a.storeId || null,
        storeName: a.storeName,
        vcode: a.vcode || null,
        scheduleDays: a.scheduleDays || null,
        scheduleTime: a.scheduleTime || globalShiftTime,
        allocationPercent: a.allocationPercent,
      }));

      // Derive primary store schedule for the top-level plantilla row
      const primaryScheduleDays = allocations[0]?.scheduleDays || "MON-SAT";
      const primaryScheduleTime = allocations[0]?.scheduleTime || globalShiftTime;

      await updatePlantillaSchedule({
        plantillaId,
        employeeNo,
        scheduleDays: primaryScheduleDays,
        scheduleTime: primaryScheduleTime,
        dayoff,
        storeAllocations: storeAllocationsPayload,
      });

      onSuccess();
      onClose();
    } catch (err) {
      setErrorMessage(err instanceof Error ? err.message : "Failed to update schedule and allocations.");
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Edit Schedule & Store Allocation"
      subtitle={
        employeeName ? (
          <span className="text-text-secondary text-xs">
            Configuring per-store shift schedules and headcount share for{" "}
            <strong className="text-text-primary font-semibold">{employeeName}</strong>
            {employeeNo && <span className="font-mono ml-1">({employeeNo})</span>}
          </span>
        ) : undefined
      }
      icon={Clock}
      isSubmitting={isSubmitting}
      isDirty={isDirty}
      maxWidthClass="max-w-2xl"
    >
      {errorMessage && (
        <div className="mb-4 rounded-xl bg-danger-bg border border-danger-border p-3.5 text-xs text-danger-text flex items-center justify-between">
          <span>{errorMessage}</span>
          <button
            type="button"
            onClick={() => setErrorMessage(null)}
            className="font-bold text-sm ml-2 cursor-pointer"
          >
            ✕
          </button>
        </div>
      )}

      <form onSubmit={handleSave} className="space-y-6">
        {/* SECTION 1: GLOBAL TERMS */}
        <div className="p-4 rounded-xl bg-surface-muted/50 border border-border-default space-y-4">
          <h4 className="text-xs font-bold text-text-primary flex items-center gap-1.5">
            <Calendar className="w-3.5 h-3.5 text-brand-primary" />
            <span>Global Work Terms & Rest Day</span>
          </h4>

          {/* Designated Day Off (1 Rest Day per week) */}
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <label className="text-2xs font-bold text-text-secondary">
                DESIGNATED DAY OFF (1 REST DAY / WEEK)
              </label>
              <span className="text-2xs text-text-muted">Mandated weekly rest day</span>
            </div>
            <div className="grid grid-cols-7 gap-1.5">
              {DAYS_OF_WEEK.map((d) => {
                const isSelected = dayoff === d;
                return (
                  <button
                    key={d}
                    type="button"
                    onClick={() => setDayoff(d)}
                    className={`py-2 text-xs font-bold rounded-lg border transition cursor-pointer text-center ${
                      isSelected
                        ? "bg-brand-primary text-white border-brand-primary shadow-xs"
                        : "bg-surface border-border-default text-text-secondary hover:text-text-primary hover:bg-surface-muted"
                    }`}
                  >
                    {d}
                  </button>
                );
              })}
            </div>
            {hasRestDayConflict && (
              <p className="mt-2 text-[11px] text-amber-600 dark:text-amber-400 font-medium flex items-center gap-1">
                <AlertTriangle className="w-3.5 h-3.5 shrink-0" />
                <span>Notice: One or more store schedules include {dayoff}, which is the designated day off.</span>
              </p>
            )}
          </div>

          {/* Default Shift Time Preset */}
          <div>
            <label className="block text-2xs font-bold text-text-secondary mb-1">
              STANDARD DUTY HOURS
            </label>
            <div className="flex flex-wrap gap-1.5">
              {TIME_PRESETS.map((t) => (
                <button
                  key={t}
                  type="button"
                  onClick={() => setGlobalShiftTime(t)}
                  className={`px-2.5 py-1 text-xs rounded-md border transition cursor-pointer font-mono ${
                    globalShiftTime === t
                      ? "bg-brand-50 border-brand-primary text-brand-700 dark:bg-brand-950/40 dark:text-brand-300 font-bold"
                      : "bg-surface border-border-default text-text-secondary hover:text-text-primary hover:bg-surface-muted"
                  }`}
                >
                  {t}
                </button>
              ))}
            </div>
          </div>
        </div>

        {/* SECTION 2: PER-STORE SCHEDULE & HC SHARE MATRIX */}
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <div>
              <h4 className="text-xs font-bold text-text-primary flex items-center gap-1.5">
                <Building2 className="w-3.5 h-3.5 text-brand-primary" />
                <span>Store Deployments & Headcount (HC) Share Allocation</span>
              </h4>
              <p className="text-[11px] text-text-secondary mt-0.5">
                Configure visit days, time windows, and fractional headcount allocation for each store.
              </p>
            </div>

            {/* Total HC Meter Badge */}
            <div
              className={`px-3 py-1 rounded-full text-xs font-bold flex items-center gap-1.5 border ${
                isHcValid
                  ? "bg-emerald-50 text-emerald-700 border-emerald-300 dark:bg-emerald-950/40 dark:text-emerald-300 dark:border-emerald-800"
                  : "bg-danger-bg text-danger-text border-danger-border animate-pulse"
              }`}
            >
              {isHcValid ? <CheckCircle2 className="w-3.5 h-3.5" /> : <AlertTriangle className="w-3.5 h-3.5" />}
              <span>Total HC: {totalHcShare} / 1.00</span>
            </div>
          </div>

          {/* Store Allocations List */}
          <div className="space-y-3">
            {allocations.map((alloc, idx) => (
              <div
                key={idx}
                className="p-4 rounded-xl border border-border-default bg-surface shadow-2xs space-y-3 relative"
              >
                <div className="flex items-center justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <span className="w-5 h-5 rounded-full bg-brand-50 text-brand-700 font-bold text-[11px] flex items-center justify-center shrink-0 border border-brand-200 dark:bg-brand-950/40 dark:border-brand-800 dark:text-brand-300">
                      {idx + 1}
                    </span>
                    <span className="text-xs font-bold text-text-primary">
                      {idx === 0 ? "Primary Store Deployment" : `Roving Deployment #${idx + 1}`}
                    </span>
                  </div>

                  {allocations.length > 1 && (
                    <button
                      type="button"
                      onClick={() => handleRemoveStore(idx)}
                      className="text-text-muted hover:text-danger-text p-1 transition cursor-pointer"
                      title="Remove store allocation"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  )}
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 text-xs">
                  {/* Store Name / Branch */}
                  <div className="col-span-1 sm:col-span-2">
                    <label className="block text-2xs font-bold text-text-secondary mb-1">
                      STORE BRANCH NAME
                    </label>
                    {availableStores.length > 0 ? (
                      <select
                        value={alloc.storeId || ""}
                        onChange={(e) => {
                          const matched = availableStores.find((s) => s.id === e.target.value);
                          updateAllocation(idx, {
                            storeId: e.target.value,
                            storeName: matched?.name || alloc.storeName,
                            vcode: matched?.vcode || alloc.vcode,
                          });
                        }}
                        className="w-full px-3 py-1.5 rounded-lg border border-border-default bg-surface-base text-text-primary text-xs focus:ring-1 focus:ring-brand-primary"
                      >
                        <option value="">{alloc.storeName || "Select Store Location"}</option>
                        {availableStores.map((st) => (
                          <option key={st.id} value={st.id}>
                            {st.name} {st.vcode ? `(${st.vcode})` : ""}
                          </option>
                        ))}
                      </select>
                    ) : (
                      <input
                        type="text"
                        value={alloc.storeName}
                        onChange={(e) => updateAllocation(idx, { storeName: e.target.value })}
                        placeholder="e.g. Puregold Shaw"
                        className="w-full px-3 py-1.5 rounded-lg border border-border-default bg-surface-base text-text-primary text-xs font-medium focus:ring-1 focus:ring-brand-primary"
                      />
                    )}
                  </div>

                  {/* VCode */}
                  <div>
                    <label className="block text-2xs font-bold text-text-secondary mb-1">
                      VCODE
                    </label>
                    <input
                      type="text"
                      value={alloc.vcode || ""}
                      onChange={(e) => updateAllocation(idx, { vcode: e.target.value.toUpperCase() })}
                      placeholder="e.g. PG001"
                      className="w-full px-3 py-1.5 rounded-lg border border-border-default bg-surface-base text-text-primary text-xs font-mono focus:ring-1 focus:ring-brand-primary uppercase"
                    />
                  </div>

                  {/* HC Share */}
                  <div>
                    <div className="flex items-center justify-between mb-1">
                      <label className="text-2xs font-bold text-text-secondary">
                        HC SHARE
                      </label>
                      <span className="font-mono text-2xs font-bold text-brand-primary">
                        {(alloc.allocationPercent / 100).toFixed(2)} HC
                      </span>
                    </div>
                    <div className="flex items-center gap-1.5">
                      <input
                        type="number"
                        min="1"
                        max="100"
                        step="5"
                        value={alloc.allocationPercent}
                        onChange={(e) => {
                          const val = Math.max(1, Math.min(100, Number(e.target.value) || 0));
                          updateAllocation(idx, { allocationPercent: val });
                        }}
                        className="w-full px-3 py-1.5 rounded-lg border border-border-default bg-surface-base text-text-primary text-xs font-mono font-bold focus:ring-1 focus:ring-brand-primary"
                      />
                      <span className="text-xs text-text-muted">%</span>
                    </div>
                  </div>

                  {/* Schedule Days */}
                  <div className="col-span-1 sm:col-span-2">
                    <label className="block text-2xs font-bold text-text-secondary mb-1">
                      SCHEDULE DAYS
                    </label>
                    <div className="flex items-center gap-1.5">
                      <input
                        type="text"
                        value={alloc.scheduleDays || ""}
                        onChange={(e) => updateAllocation(idx, { scheduleDays: e.target.value.toUpperCase() })}
                        placeholder="e.g. MON-WED or MON,WED,FRI"
                        className="w-full px-3 py-1.5 rounded-lg border border-border-default bg-surface-base text-text-primary text-xs font-medium focus:ring-1 focus:ring-brand-primary uppercase"
                      />
                      <div className="flex gap-1 shrink-0">
                        {["MON-WED", "THU-SAT", "MON-SAT"].map((preset) => (
                          <button
                            key={preset}
                            type="button"
                            onClick={() => updateAllocation(idx, { scheduleDays: preset })}
                            className="px-1.5 py-1 text-[10px] font-semibold rounded bg-surface-muted hover:bg-surface-base border border-border-default text-text-secondary hover:text-text-primary cursor-pointer"
                          >
                            {preset}
                          </button>
                        ))}
                      </div>
                    </div>
                  </div>

                  {/* Shift Time */}
                  <div className="col-span-1 sm:col-span-2">
                    <label className="block text-2xs font-bold text-text-secondary mb-1">
                      SHIFT TIME WINDOW
                    </label>
                    <input
                      type="text"
                      value={alloc.scheduleTime || ""}
                      onChange={(e) => updateAllocation(idx, { scheduleTime: e.target.value })}
                      placeholder="e.g. 08:00 AM - 05:00 PM"
                      className="w-full px-3 py-1.5 rounded-lg border border-border-default bg-surface-base text-text-primary text-xs font-mono focus:ring-1 focus:ring-brand-primary"
                    />
                  </div>
                </div>
              </div>
            ))}
          </div>

          {/* Add Roving Store Trigger */}
          <button
            type="button"
            onClick={handleAddStore}
            className="w-full py-2.5 rounded-xl border-2 border-dashed border-border-default hover:border-brand-primary text-text-secondary hover:text-brand-primary transition text-xs font-bold flex items-center justify-center gap-2 cursor-pointer bg-surface/50 hover:bg-surface-muted/50"
          >
            <Plus className="w-4 h-4" />
            <span>Add Roving Store Allocation</span>
          </button>
        </div>

        {/* Modal Actions Footer */}
        <div className="pt-4 border-t border-border-default flex items-center justify-between">
          <div className="text-xs">
            {!isHcValid ? (
              <span className="text-danger-text font-bold">
                ⚠️ Sum is {totalHcShare} HC. Must equal 1.00 HC.
              </span>
            ) : (
              <span className="text-emerald-600 dark:text-emerald-400 font-semibold flex items-center gap-1">
                <CheckCircle2 className="w-3.5 h-3.5" />
                <span>Valid headcount allocation (1.00 HC)</span>
              </span>
            )}
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={onClose}
              disabled={isSubmitting}
              className="px-4 py-2 text-xs font-semibold rounded-lg border border-border-default bg-surface hover:bg-surface-muted text-text-secondary hover:text-text-primary transition cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting || !isHcValid}
              className="px-4 py-2 text-xs font-bold rounded-lg bg-brand-primary hover:bg-brand-secondary text-white transition shadow-xs cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-1.5"
            >
              {isSubmitting ? (
                <>
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                  <span>Saving…</span>
                </>
              ) : (
                <span>Save Schedule & Allocations</span>
              )}
            </button>
          </div>
        </div>
      </form>
    </Modal>
  );
}
