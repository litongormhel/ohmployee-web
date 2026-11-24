"use client";

import React, { useState, useMemo } from "react";
import {
  Loader2,
  Calendar,
  Building2,
  AlertTriangle,
  Lock,
  RotateCcw,
  ChevronDown,
  X,
  Zap,
} from "lucide-react";
import { updatePlantillaSchedule, type StoreAllocationInput } from "@/lib/queries/plantilla";
import { Modal } from "@/components/shared/Modal";
import type { BaseModalProps } from "@/types/modal";

export interface StoreAllocationItem {
  storeId?: string | null;
  storeName: string;
  vcode?: string | null;
  scheduleDays?: string | null;
  scheduleTime?: string | null;
  allocationPercent: number; // 100 = 1.00 HC, 50 = 0.50 HC
}

export interface UpdateScheduleModalProps extends BaseModalProps {
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
type DayCode = (typeof DAYS_OF_WEEK)[number];
const DAY_SHORT_NAMES: Record<DayCode, string> = {
  MON: "Mon",
  TUE: "Tue",
  WED: "Wed",
  THU: "Thu",
  FRI: "Fri",
  SAT: "Sat",
  SUN: "Sun",
};

// Exact COL palette from interactive HTML mockup
export const STORE_COLORS = [
  { solid: "#1d4ed8", tint: "#e6edff", ink: "#12338f" }, // Store 1: Blue
  { solid: "#a14d00", tint: "#fff0d9", ink: "#6b3300" }, // Store 2: Amber
  { solid: "#0b6b5f", tint: "#dcf5f0", ink: "#08493f" }, // Store 3: Teal
  { solid: "#7a22b8", tint: "#f2e6fb", ink: "#521579" }, // Store 4: Purple
  { solid: "#c026d3", tint: "#fae8ff", ink: "#701a75" }, // Store 5: Fuchsia
  { solid: "#0284c7", tint: "#e0f2fe", ink: "#0369a1" }, // Store 6: Sky
  { solid: "#ea580c", tint: "#ffedd5", ink: "#9a3412" }, // Store 7: Orange
  { solid: "#4b5563", tint: "#f3f4f6", ink: "#1f2937" }, // Store 8: Slate
];

export function getStoreColor(index: number) {
  return STORE_COLORS[index % STORE_COLORS.length];
}

const pad = (n: number) => (n < 10 ? "0" : "") + n;

export function fmtLong(h: number): string {
  const norm = Math.max(0, Math.min(23.5, Math.round(h * 2) / 2));
  const hh = Math.floor(norm);
  const mm = norm % 1 ? "30" : "00";
  const displayH = hh % 12 || 12;
  return `${pad(displayH)}:${mm} ${hh >= 12 ? "PM" : "AM"}`;
}

export function fmtShort(h: number): string {
  const norm = Math.max(0, Math.min(23.5, Math.round(h * 2) / 2));
  const hh = Math.floor(norm);
  const mm = norm % 1 ? ":30" : "";
  const displayH = hh % 12 || 12;
  return `${displayH}${mm} ${hh >= 12 ? "PM" : "AM"}`;
}

export function fmtH(n: number): string {
  return (Number.isInteger(n) ? n : n.toFixed(1)) + "h";
}

export function parseTimeToDecimalHours(timeStr?: string | null): number | null {
  if (!timeStr) return null;
  const clean = timeStr.trim().toUpperCase();
  const m = clean.match(/^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?$/);
  if (!m) return null;
  let h = parseInt(m[1], 10);
  const min = m[2] ? parseInt(m[2], 10) : 0;
  const ampm = m[3] || (h >= 12 ? "PM" : "AM");
  if (ampm === "PM" && h < 12) h += 12;
  if (ampm === "AM" && h === 12) h = 0;
  return h + (min >= 15 && min < 45 ? 0.5 : min >= 45 ? 1 : 0);
}

export function parseShiftToHours(scheduleTime?: string | null): { start: number; end: number } {
  if (!scheduleTime) return { start: 8, end: 17 };
  const parts = scheduleTime.split("-").map((p) => p.trim());
  const start = parseTimeToDecimalHours(parts[0]) ?? 8;
  const end = parseTimeToDecimalHours(parts[1]) ?? 17;
  return { start, end };
}

export function calculateShiftDuration(start: number, end: number): {
  durationHours: number;
  isOvernight: boolean;
  error: string | null;
} {
  if (start === end) {
    return {
      durationHours: 0,
      isOvernight: false,
      error: "Time-in and time-out cannot be identical.",
    };
  }
  const isOvernight = end < start;
  const durationHours = isOvernight ? 24 - start + end : end - start;
  if (durationHours > 16) {
    return {
      durationHours,
      isOvernight,
      error: "Shift duration cannot exceed 16 hours.",
    };
  }
  return {
    durationHours,
    isOvernight,
    error: null,
  };
}

function parseDayoffString(raw?: string | null): DayCode[] {
  if (!raw || !raw.trim()) return ["SUN"];
  const dayMap: Record<string, DayCode> = {
    MONDAY: "MON",
    MON: "MON",
    TUESDAY: "TUE",
    TUE: "TUE",
    WEDNESDAY: "WED",
    WED: "WED",
    THURSDAY: "THU",
    THU: "THU",
    FRIDAY: "FRI",
    FRI: "FRI",
    SATURDAY: "SAT",
    SAT: "SAT",
    SUNDAY: "SUN",
    SUN: "SUN",
  };
  const parts = raw
    .toUpperCase()
    .split(/[,/&\s-]+/)
    .map((p) => p.trim())
    .filter(Boolean);
  const matched = parts.map((p) => dayMap[p]).filter((d): d is DayCode => Boolean(d));
  if (matched.length > 0) {
    return Array.from(new Set(matched));
  }
  return ["SUN"];
}

function parseDaysToSet(daysStr?: string | null): Set<DayCode> {
  const set = new Set<DayCode>();
  if (!daysStr) return set;
  const upper = daysStr.toUpperCase().trim();
  if (upper === "MON-SAT") return new Set<DayCode>(["MON", "TUE", "WED", "THU", "FRI", "SAT"]);
  if (upper === "MON-FRI") return new Set<DayCode>(["MON", "TUE", "WED", "THU", "FRI"]);
  if (upper === "MON-WED") return new Set<DayCode>(["MON", "TUE", "WED"]);
  if (upper === "THU-SAT") return new Set<DayCode>(["THU", "FRI", "SAT"]);

  const tokens = upper.split(/[,/&\s]+/).map((t) => t.trim()).filter(Boolean);
  for (const token of tokens) {
    if (token === "MON-SAT") {
      ["MON", "TUE", "WED", "THU", "FRI", "SAT"].forEach((d) => set.add(d as DayCode));
    } else if (token === "MON-FRI") {
      ["MON", "TUE", "WED", "THU", "FRI"].forEach((d) => set.add(d as DayCode));
    } else if (token === "MON-WED") {
      ["MON", "TUE", "WED"].forEach((d) => set.add(d as DayCode));
    } else if (token === "THU-SAT") {
      ["THU", "FRI", "SAT"].forEach((d) => set.add(d as DayCode));
    } else {
      DAYS_OF_WEEK.forEach((d) => {
        if (token === d) set.add(d);
      });
    }
  }
  return set;
}

function formatDaysFromSet(days: Set<string>): string {
  const ordered = DAYS_OF_WEEK.filter((d) => days.has(d));
  if (ordered.length === 6 && !days.has("SUN")) return "MON-SAT";
  if (ordered.length === 5 && !days.has("SAT") && !days.has("SUN")) return "MON-FRI";
  if (ordered.length === 3 && days.has("MON") && days.has("TUE") && days.has("WED")) return "MON-WED";
  if (ordered.length === 3 && days.has("THU") && days.has("FRI") && days.has("SAT")) return "THU-SAT";
  return ordered.join(", ");
}

export function UpdateScheduleModal({
  isOpen,
  onClose,
  plantillaId,
  employeeNo,
  initialScheduleDays,
  initialScheduleTime,
  initialDayoff,
  initialStoreAllocations,
  onSuccess,
}: UpdateScheduleModalProps) {
  const defaultAllocations: StoreAllocationItem[] = useMemo(() => {
    if (initialStoreAllocations && initialStoreAllocations.length > 0) {
      return initialStoreAllocations;
    }
    return [
      {
        storeId: null,
        storeName: "Primary Store Assignment",
        vcode: "",
        scheduleDays: initialScheduleDays ?? "",
        scheduleTime: initialScheduleTime || "08:00 AM - 05:00 PM",
        allocationPercent: 100,
      },
    ];
  }, [initialStoreAllocations, initialScheduleDays, initialScheduleTime]);

  const [selectedDayoffs, setSelectedDayoffs] = useState<DayCode[]>(() =>
    parseDayoffString(initialDayoff)
  );
  const [allocations, setAllocations] = useState<StoreAllocationItem[]>(defaultAllocations);
  const [expandedStoreIdx, setExpandedStoreIdx] = useState<number | null>(0);
  const [restDayNotice, setRestDayNotice] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const resetAll = () => {
    setSelectedDayoffs([]);
    setAllocations((curr) =>
      curr.map((alloc) => ({
        ...alloc,
        scheduleDays: "",
      }))
    );
    setExpandedStoreIdx(0);
    setRestDayNotice(null);
    setErrorMessage(null);
  };

  const dismissNotice = () => setRestDayNotice(null);

  // Track all stores assigned per day to detect conflicts/overlaps
  const dayStoreAssignments = useMemo(() => {
    const map: Record<DayCode, number[]> = {
      MON: [],
      TUE: [],
      WED: [],
      THU: [],
      FRI: [],
      SAT: [],
      SUN: [],
    };
    allocations.forEach((alloc, idx) => {
      const set = parseDaysToSet(alloc.scheduleDays);
      set.forEach((day) => {
        if (map[day]) map[day].push(idx);
      });
    });
    return map;
  }, [allocations]);

  const overlappingDays = useMemo(() => {
    return DAYS_OF_WEEK.filter((d) => (dayStoreAssignments[d]?.length ?? 0) > 1);
  }, [dayStoreAssignments]);

  // Auto-split non-rest working days evenly across all assigned stores
  const handleAutoSplitDays = () => {
    dismissNotice();
    const workingDays = DAYS_OF_WEEK.filter((d) => !selectedDayoffs.includes(d));
    if (workingDays.length === 0 || allocations.length <= 1) return;

    const numStores = allocations.length;
    const baseCount = Math.floor(workingDays.length / numStores);
    let remainder = workingDays.length % numStores;
    let dayPointer = 0;

    const updatedAllocations = allocations.map((alloc) => {
      const countForThisStore = baseCount + (remainder > 0 ? 1 : 0);
      if (remainder > 0) remainder--;

      const assignedDays = workingDays.slice(dayPointer, dayPointer + countForThisStore);
      dayPointer += countForThisStore;

      return {
        ...alloc,
        scheduleDays: assignedDays.join(", "),
      };
    });

    setAllocations(updatedAllocations);
    setExpandedStoreIdx(0);
  };

  // Toggle Rest Day (Support multi-day rest or single)
  const handleToggleRestDay = (day: DayCode) => {
    dismissNotice();
    setSelectedDayoffs((prev) => {
      let updated: DayCode[];
      if (prev.includes(day)) {
        if (prev.length === 1) {
          setRestDayNotice("Employee must have at least one designated Rest Day per week.");
          return prev;
        }
        updated = prev.filter((d) => d !== day);
      } else {
        updated = [...prev, day];
        // Remove day from all stores' duty days
        setAllocations((curr) =>
          curr.map((alloc) => {
            const set = parseDaysToSet(alloc.scheduleDays);
            if (set.has(day)) {
              set.delete(day);
              return {
                ...alloc,
                scheduleDays: formatDaysFromSet(set),
              };
            }
            return alloc;
          })
        );
      }
      return updated;
    });
  };

  // Toggle Duty Day on a store
  const handleToggleDutyDay = (storeIdx: number, day: DayCode) => {
    dismissNotice();
    if (selectedDayoffs.includes(day)) {
      setRestDayNotice(
        `${day} is a designated Rest Day. Please untoggle it from Rest Days first.`
      );
      return;
    }

    setAllocations((prev) => {
      return prev.map((item, i) => {
        if (i !== storeIdx) return item;
        const set = parseDaysToSet(item.scheduleDays);
        if (set.has(day)) {
          set.delete(day);
        } else {
          set.add(day);
        }
        return {
          ...item,
          scheduleDays: formatDaysFromSet(set),
        };
      });
    });
  };

  // Adjust shift time by delta (e.g. +0.5 or -0.5 hours) with 24h wrap-around
  const adjustShift = (storeIdx: number, key: "start" | "end", delta: number) => {
    dismissNotice();
    setAllocations((prev) =>
      prev.map((a, i) => {
        if (i !== storeIdx) return a;
        const { start, end } = parseShiftToHours(a.scheduleTime);
        let newStart = start;
        let newEnd = end;
        if (key === "start") {
          newStart = (start + delta + 24) % 24;
        } else {
          newEnd = (end + delta + 24) % 24;
        }
        return {
          ...a,
          scheduleTime: `${fmtLong(newStart)} - ${fmtLong(newEnd)}`,
        };
      })
    );
  };

  // Apply shift time to all stores
  const handleApplyTimeToAll = (sourceIdx: number) => {
    dismissNotice();
    const sourceTime = allocations[sourceIdx]?.scheduleTime || "08:00 AM - 05:00 PM";
    setAllocations((prev) =>
      prev.map((a) => ({
        ...a,
        scheduleTime: sourceTime,
      }))
    );
  };

  // Calculations for preview, status bar, and validation
  let totalWeeklyHours = 0;
  let timeErrorsCount = 0;
  const storeDayOwner: Record<DayCode, number> = {} as Record<DayCode, number>;

  allocations.forEach((a, idx) => {
    const { start, end } = parseShiftToHours(a.scheduleTime);
    const { durationHours, error } = calculateShiftDuration(start, end);
    if (error) {
      timeErrorsCount++;
    } else {
      const daysCount = parseDaysToSet(a.scheduleDays).size;
      totalWeeklyHours += durationHours * daysCount;
    }

    const set = parseDaysToSet(a.scheduleDays);
    set.forEach((day) => {
      storeDayOwner[day] = idx;
    });
  });

  // Calculate gaps (duty days that are neither rest day nor assigned to any store)
  const unassignedDutyDays = DAYS_OF_WEEK.filter(
    (d) => !selectedDayoffs.includes(d) && storeDayOwner[d] === undefined
  );
  const unassignedGapsCount = unassignedDutyDays.length;

  const totalHc = allocations.reduce((sum, a) => sum + (a.allocationPercent || 0), 0);
  const isHcValid = Math.abs(totalHc - 100) <= 2;

  const statusText =
    timeErrorsCount > 0
      ? `${timeErrorsCount} time error${timeErrorsCount > 1 ? "s" : ""} to fix`
      : overlappingDays.length > 0
      ? `${overlappingDays.length} overlapping day${overlappingDays.length > 1 ? "s" : ""} to resolve · ${fmtH(totalWeeklyHours)}/week`
      : unassignedGapsCount > 0
      ? `${unassignedGapsCount} day${unassignedGapsCount > 1 ? "s" : ""} without a store · ${fmtH(totalWeeklyHours)}/week`
      : `Ready to save · ${fmtH(totalWeeklyHours)}/week`;

  const statusColor =
    timeErrorsCount > 0
      ? "#a3141f"
      : overlappingDays.length > 0
      ? "#b45309"
      : unassignedGapsCount > 0
      ? "#8a4300"
      : "#0b6b3a";

  const canSave = timeErrorsCount === 0 && isHcValid && !isSubmitting;

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!canSave) return;
    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      const primaryScheduleDays = allocations[0]?.scheduleDays?.trim() || "";
      const primaryScheduleTime = allocations[0]?.scheduleTime || "08:00 AM - 05:00 PM";
      const dayoffString = selectedDayoffs.join(", ");

      const storeAllocationsPayload: StoreAllocationInput[] = allocations.map((a) => ({
        storeId: a.storeId,
        storeName: a.storeName,
        vcode: a.vcode,
        scheduleDays: a.scheduleDays?.trim() || "",
        scheduleTime: a.scheduleTime || "08:00 AM - 05:00 PM",
        allocationPercent: a.allocationPercent,
      }));

      await updatePlantillaSchedule({
        plantillaId,
        employeeNo,
        scheduleDays: primaryScheduleDays,
        scheduleTime: primaryScheduleTime,
        dayoff: dayoffString,
        storeAllocations: storeAllocationsPayload,
      });

      onSuccess();
      onClose();
    } catch (err) {
      setErrorMessage(
        err instanceof Error ? err.message : "Failed to update schedule. Please try again."
      );
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Edit Schedule & Work Terms"
      subtitle="Configuring rest days, per-store duty days, and shift time windows"
      maxWidthClass="max-w-4xl"
    >
      <form onSubmit={handleSave} className="space-y-4">
        {/* Banner Notice (if rest day conflict or notice) */}
        {restDayNotice && (
          <div className="p-3 bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800 rounded-xl text-amber-800 dark:text-amber-300 text-xs flex items-center justify-between gap-3 animate-in fade-in">
            <div className="flex items-center gap-2">
              <AlertTriangle className="w-4 h-4 text-amber-600 shrink-0" />
              <span>{restDayNotice}</span>
            </div>
            <button
              type="button"
              onClick={dismissNotice}
              className="text-amber-700 hover:text-amber-900 dark:text-amber-400 p-0.5 rounded cursor-pointer"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        )}

        {/* SCHEDULE CONFLICT / OVERLAP BANNER */}
        {overlappingDays.length > 0 && (
          <div className="p-3.5 bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800 rounded-xl text-amber-900 dark:text-amber-200 text-xs flex items-start justify-between gap-3 animate-in fade-in">
            <div className="flex items-start gap-2.5">
              <AlertTriangle className="w-4 h-4 text-amber-600 shrink-0 mt-0.5" />
              <div>
                <p className="font-bold">
                  Schedule Overlap Detected: {overlappingDays.map((d) => DAY_SHORT_NAMES[d]).join(", ")} {overlappingDays.length === 1 ? "is" : "are"} assigned to multiple stores.
                </p>
                <p className="mt-0.5 text-amber-800/80 dark:text-amber-300/80">
                  This employee cannot be deployed to multiple stores on the same day. Tap day chips below to reassign exclusively, or use Auto-Split to distribute working days evenly.
                </p>
                {allocations.length > 1 && (
                  <div className="mt-2.5 flex items-center gap-2 flex-wrap">
                    <button
                      type="button"
                      onClick={handleAutoSplitDays}
                      className="inline-flex items-center gap-1.5 px-3 py-1 text-xs font-bold rounded-lg bg-amber-600 hover:bg-amber-700 text-white transition cursor-pointer shadow-xs"
                    >
                      <Zap className="w-3.5 h-3.5" />
                      <span>
                        Auto-Split Days Evenly (
                        {Math.floor(DAYS_OF_WEEK.filter((d) => !selectedDayoffs.includes(d)).length / allocations.length)}–
                        {Math.ceil(DAYS_OF_WEEK.filter((d) => !selectedDayoffs.includes(d)).length / allocations.length)}d / store)
                      </span>
                    </button>
                    <button
                      type="button"
                      onClick={resetAll}
                      className="px-2.5 py-1 text-xs font-semibold rounded-lg bg-white dark:bg-slate-800 border border-amber-300 dark:border-amber-700 hover:bg-amber-100 dark:hover:bg-amber-900/60 text-amber-900 dark:text-amber-200 transition cursor-pointer"
                    >
                      Clear All (Reset)
                    </button>
                  </div>
                )}
              </div>
            </div>
          </div>
        )}

        {/* REST DAY SELECTOR */}
        <div className="bg-[#f8f9fb] dark:bg-slate-900/60 p-3.5 rounded-xl border border-[#dfe2e8] dark:border-slate-800 flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2 flex-wrap">
            <div className="flex items-center gap-1.5 text-xs font-bold text-[#1b1f28] dark:text-slate-200 mr-2">
              <Calendar className="w-4 h-4 text-[#1d4ed8]" />
              <span>Rest Day:</span>
            </div>
            <div className="flex items-center gap-1.5 flex-wrap">
              {DAYS_OF_WEEK.map((day) => {
                const isSelected = selectedDayoffs.includes(day);
                return (
                  <button
                    key={day}
                    type="button"
                    onClick={() => handleToggleRestDay(day)}
                    className={`px-3 py-1.5 text-xs font-bold rounded-lg transition cursor-pointer select-none ${
                      isSelected
                        ? "bg-[#1d4ed8] text-white shadow-xs"
                        : "bg-white dark:bg-slate-800 text-[#3a4150] dark:text-slate-300 border border-[#cfd4dc] dark:border-slate-700 hover:bg-[#f1f2f5]"
                    }`}
                  >
                    {day}
                  </button>
                );
              })}
            </div>
          </div>
          <div className="text-xs font-semibold text-[#5a6272] dark:text-slate-400 shrink-0">
            {selectedDayoffs.length} Rest {selectedDayoffs.length === 1 ? "Day" : "Days"}
          </div>
        </div>

        {/* WEEKLY COVERAGE PREVIEW */}
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <h4 className="text-xs font-bold text-[#1b1f28] dark:text-slate-200 uppercase tracking-wide">
              WEEKLY COVERAGE PREVIEW
            </h4>
            <span className="text-[11px] font-medium text-[#5a6272] dark:text-slate-400">
              Live sync
            </span>
          </div>

          <div className="grid grid-cols-7 gap-1.5 text-center">
            {DAYS_OF_WEEK.map((day) => {
              const isRest = selectedDayoffs.includes(day);
              const assignedStoreIndices = dayStoreAssignments[day] || [];
              const isConflict = assignedStoreIndices.length > 1;
              const ownerIdx = isConflict ? undefined : storeDayOwner[day];
              const isAssigned = ownerIdx !== undefined;
              const storeColor = isAssigned ? getStoreColor(ownerIdx) : null;
              const storeAlloc = isAssigned ? allocations[ownerIdx] : null;
              const { start, end } = storeAlloc ? parseShiftToHours(storeAlloc.scheduleTime) : { start: 8, end: 17 };
              const shiftTimeStr = `${fmtShort(start)} – ${fmtShort(end)}`;

              if (isRest) {
                return (
                  <div
                    key={day}
                    className="p-2 rounded-xl border border-[#dfe2e8] dark:border-slate-800 bg-[#f8f9fb] dark:bg-slate-900/60 flex flex-col items-center justify-center min-h-[78px] gap-1 select-none"
                  >
                    <span className="text-xs font-bold text-[#5a6272] dark:text-slate-400">
                      {day}
                    </span>
                    <span className="text-[10px] font-bold text-[#5a6272] dark:text-slate-400 bg-[#e6e8ed] dark:bg-slate-800 px-2 py-0.5 rounded-md">
                      Rest
                    </span>
                  </div>
                );
              }

              if (isConflict) {
                return (
                  <div
                    key={day}
                    className="p-2 rounded-xl border-2 border-amber-500 bg-amber-50 dark:bg-amber-950/40 text-amber-900 dark:text-amber-200 transition flex flex-col items-center justify-between min-h-[78px] gap-1 shadow-2xs select-none"
                    title={`Overlapping assignments: ${assignedStoreIndices.map((i) => allocations[i]?.storeName || `Store ${i + 1}`).join(", ")}`}
                  >
                    <div className="flex items-center gap-1">
                      <span className="text-xs font-bold text-amber-800 dark:text-amber-300">
                        {day}
                      </span>
                      <AlertTriangle className="w-3.5 h-3.5 text-amber-600 shrink-0" />
                    </div>
                    <span className="text-[10px] font-extrabold bg-amber-200 dark:bg-amber-800/60 px-1.5 py-0.5 rounded text-amber-900 dark:text-amber-100 whitespace-nowrap">
                      {assignedStoreIndices.length} Stores
                    </span>
                    <span className="text-[10px] font-bold text-amber-700 dark:text-amber-400">
                      Overlap
                    </span>
                  </div>
                );
              }

              if (isAssigned && storeColor && storeAlloc) {
                return (
                  <div
                    key={day}
                    className="p-2 rounded-xl border transition flex flex-col items-center justify-between min-h-[78px] gap-1 shadow-2xs select-none"
                    style={{
                      backgroundColor: storeColor.tint,
                      borderColor: storeColor.solid,
                    }}
                  >
                    <div className="flex items-center gap-1">
                      <span
                        className="text-xs font-bold"
                        style={{ color: storeColor.ink }}
                      >
                        {day}
                      </span>
                      <span
                        className="w-4 h-4 rounded-full text-white text-[10px] font-bold flex items-center justify-center shrink-0"
                        style={{ backgroundColor: storeColor.solid }}
                      >
                        {ownerIdx + 1}
                      </span>
                    </div>
                    <span
                      className="font-mono text-[11px] font-bold truncate max-w-full"
                      style={{ color: storeColor.ink }}
                      title={storeAlloc.vcode || storeAlloc.storeName}
                    >
                      {storeAlloc.vcode || `Store ${ownerIdx + 1}`}
                    </span>
                    <span
                      className="text-[10px] font-medium leading-none whitespace-nowrap"
                      style={{ color: storeColor.ink }}
                    >
                      {shiftTimeStr}
                    </span>
                  </div>
                );
              }

              // Unassigned Duty Day
              return (
                <div
                  key={day}
                  className="p-2 rounded-xl border border-dashed border-[#cfd4dc] dark:border-slate-700 bg-white dark:bg-slate-900 flex flex-col items-center justify-center min-h-[78px] gap-1 select-none"
                >
                  <span className="text-xs font-bold text-[#8a919e]">
                    {day}
                  </span>
                  <span className="text-[10px] font-medium text-[#8a919e]">
                    Unassigned
                  </span>
                </div>
              );
            })}
          </div>
        </div>

        {/* ASSIGNED STORES & SHIFT WINDOWS (ACCORDIONS) */}
        <div className="space-y-3 pt-1">
          <div className="flex items-center justify-between">
            <h4 className="text-xs font-bold text-[#1b1f28] dark:text-slate-200 flex items-center gap-2 uppercase tracking-wide">
              <Building2 className="w-4 h-4 text-[#1d4ed8]" />
              <span>Assigned Stores & Shift Windows</span>
            </h4>
            <span className="text-[11px] font-medium text-[#5a6272] dark:text-slate-400">
              Click header to expand or collapse
            </span>
          </div>

          <div className="space-y-2.5">
            {allocations.map((alloc, idx) => {
              const color = getStoreColor(idx);
              const isExpanded = expandedStoreIdx === idx;
              const currentDaySet = parseDaysToSet(alloc.scheduleDays);
              const { start, end } = parseShiftToHours(alloc.scheduleTime);
              const { durationHours, isOvernight, error: timeError } = calculateShiftDuration(start, end);
              const isBadTime = timeError !== null;
              const hcFraction = (alloc.allocationPercent / 100).toFixed(2);

              const dayNames = DAYS_OF_WEEK.filter((d) => currentDaySet.has(d))
                .map((d) => DAY_SHORT_NAMES[d])
                .join(", ") || "No duty days";
              const shiftSummary = isBadTime
                ? "Invalid shift"
                : `${fmtShort(start)} – ${fmtShort(end)}${isOvernight ? " (Overnight)" : ""}`;
              const summaryText = `${dayNames} · ${shiftSummary}`;

              const storeHasOverlap = DAYS_OF_WEEK.some(
                (d) => currentDaySet.has(d) && (dayStoreAssignments[d]?.length ?? 0) > 1
              );

              return (
                <div
                  key={idx}
                  className="rounded-[14px] border transition overflow-hidden bg-white dark:bg-slate-900 shadow-2xs"
                  style={{
                    borderColor: isExpanded ? color.solid : storeHasOverlap ? "#f59e0b" : "#dfe2e8",
                  }}
                >
                  {/* Card Header (Accordion Toggle) */}
                  <button
                    type="button"
                    onClick={() => {
                      dismissNotice();
                      setExpandedStoreIdx((prev) => (prev === idx ? null : idx));
                    }}
                    className="w-full text-left p-3 flex items-center gap-3 cursor-pointer bg-white dark:bg-slate-900 hover:bg-[#f6f7f9]/60 dark:hover:bg-slate-800/40 transition"
                  >
                    {/* Numbered Badge Circle */}
                    <span
                      className="w-[26px] h-[26px] rounded-full text-white text-[13px] font-bold flex items-center justify-center shrink-0 select-none shadow-xs"
                      style={{ backgroundColor: color.solid }}
                    >
                      {idx + 1}
                    </span>

                    {/* Store Info Column */}
                    <div className="flex flex-col gap-0.5 flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-bold text-[#1b1f28] dark:text-slate-100 text-sm truncate">
                          {alloc.storeName}
                        </span>
                        {alloc.vcode && (
                          <span
                            className="font-mono text-[11px] font-medium px-1.5 py-0.5 rounded-[5px] border shrink-0"
                            style={{
                              color: color.ink,
                              borderColor: color.solid + "66",
                              backgroundColor: color.tint,
                            }}
                          >
                            {alloc.vcode}
                          </span>
                        )}
                        {storeHasOverlap && (
                          <span className="inline-flex items-center gap-1 text-[10px] font-bold px-1.5 py-0.5 rounded bg-amber-100 dark:bg-amber-900/40 text-amber-800 dark:text-amber-300 border border-amber-300 dark:border-amber-700 shrink-0">
                            <AlertTriangle className="w-3 h-3 text-amber-600 shrink-0" />
                            <span>Overlapping</span>
                          </span>
                        )}
                      </div>
                      <span className="text-[12.5px] text-[#3f4757] dark:text-slate-400">
                        {summaryText}
                      </span>
                    </div>

                    {/* HC text */}
                    <span className="text-xs text-[#5a6272] dark:text-slate-400 whitespace-nowrap">
                      {hcFraction} HC · {alloc.allocationPercent}%
                    </span>

                    {/* Chevron */}
                    <ChevronDown
                      className="w-4 h-4 text-[#3a4150] dark:text-slate-400 shrink-0 transition-transform duration-150"
                      style={{ transform: isExpanded ? "rotate(180deg)" : "rotate(0deg)" }}
                    />
                  </button>

                  {/* Expanded Store Body */}
                  {isExpanded && (
                    <div className="border-t border-[#e6e8ed] dark:border-slate-800 p-3.5 space-y-3.5 bg-white dark:bg-slate-900">
                      {/* Sub-header info */}
                      <div className="flex items-center justify-between text-xs text-[#5a6272] dark:text-slate-400 pb-1">
                        <span>Duty days and shift hours for {alloc.storeName}</span>
                        <span className="font-semibold text-[#1b1f28] dark:text-slate-200">
                          HC Share: {hcFraction} ({alloc.allocationPercent}%)
                        </span>
                      </div>

                      {/* DUTY DAYS CHIPS */}
                      <div className="space-y-1.5">
                        <div className="flex items-center justify-between">
                          <label className="text-xs font-bold tracking-[0.05em] text-[#3a4150] dark:text-slate-300">
                            DUTY DAYS
                          </label>
                          <span className="text-[11px] font-medium text-[#5a6272] dark:text-slate-400">
                            {currentDaySet.size} {currentDaySet.size === 1 ? "day" : "days"} assigned
                          </span>
                        </div>

                        <div className="grid grid-cols-7 gap-1.5">
                          {DAYS_OF_WEEK.map((day) => {
                            const isMine = currentDaySet.has(day);
                            const otherOwnerIdx = allocations.findIndex(
                              (a, i) => i !== idx && parseDaysToSet(a.scheduleDays).has(day)
                            );
                            const isOther = otherOwnerIdx >= 0;
                            const isOverlapping = isMine && isOther;
                            const isRest = selectedDayoffs.includes(day);

                            let chipBg = "#fff";
                            let chipBorder = "#cfd4dc";
                            let chipColor = "#3a4150";
                            let subText = "";

                            if (isRest) {
                              chipBg = "#f1f2f5";
                              chipBorder = "#e3e6eb";
                              chipColor = "#5f6675";
                              subText = "Rest";
                            } else if (isOverlapping) {
                              chipBg = "#fffbeb";
                              chipBorder = "#f59e0b";
                              chipColor = "#b45309";
                              subText = "⚠️ Overlap";
                            } else if (isMine) {
                              chipBg = color.tint;
                              chipBorder = color.solid;
                              chipColor = color.ink;
                              subText = "✓";
                            } else if (isOther) {
                              chipBg = "#f1f2f5";
                              chipBorder = "#e3e6eb";
                              chipColor = "#5f6675";
                              subText = `In ${otherOwnerIdx + 1}`;
                            }

                            return (
                              <button
                                key={day}
                                type="button"
                                disabled={isRest}
                                onClick={() => handleToggleDutyDay(idx, day)}
                                className="h-[52px] rounded-[10px] border flex flex-col items-center justify-center gap-0.5 text-xs font-bold transition cursor-pointer select-none disabled:cursor-not-allowed"
                                style={{
                                  backgroundColor: chipBg,
                                  borderColor: chipBorder,
                                  color: chipColor,
                                }}
                              >
                                <span>{day}</span>
                                <span className="text-[10px] font-semibold min-h-[12px]">
                                  {subText}
                                </span>
                              </button>
                            );
                          })}
                        </div>
                      </div>

                      {/* SHIFT TIME WINDOW (STEPPERS WITH − AND +) */}
                      <div className="space-y-2">
                        <div className="text-xs font-bold tracking-[0.05em] text-[#3a4150] dark:text-slate-300">
                          SHIFT TIME WINDOW
                        </div>

                        <div className="flex items-center gap-2.5 flex-wrap">
                          {/* TIME-IN BOX */}
                          <div className="flex items-center border border-[#cfd4dc] dark:border-slate-700 rounded-xl overflow-hidden bg-white dark:bg-slate-800">
                            <button
                              type="button"
                              aria-label="Time-in 30 minutes earlier"
                              onClick={() => adjustShift(idx, "start", -0.5)}
                              className="w-11 h-11 border-0 bg-[#f6f7f9] hover:bg-[#eef0f4] dark:bg-slate-700 dark:hover:bg-slate-600 text-lg font-bold text-[#1b1f28] dark:text-white flex items-center justify-center cursor-pointer transition select-none"
                            >
                              −
                            </button>
                            <div className="px-3.5 text-center min-w-[96px]">
                              <div className="text-[10px] text-[#5a6272] dark:text-slate-400 font-semibold tracking-wider">
                                TIME-IN
                              </div>
                              <div className="font-mono text-sm font-bold text-[#1b1f28] dark:text-white">
                                {fmtLong(start)}
                              </div>
                            </div>
                            <button
                              type="button"
                              aria-label="Time-in 30 minutes later"
                              onClick={() => adjustShift(idx, "start", 0.5)}
                              className="w-11 h-11 border-0 bg-[#f6f7f9] hover:bg-[#eef0f4] dark:bg-slate-700 dark:hover:bg-slate-600 text-lg font-bold text-[#1b1f28] dark:text-white flex items-center justify-center cursor-pointer transition select-none"
                            >
                              +
                            </button>
                          </div>

                          {/* ARROW */}
                          <span className="text-[#5a6272] dark:text-slate-400 font-bold">→</span>

                          {/* TIME-OUT BOX */}
                          <div className="flex items-center border border-[#cfd4dc] dark:border-slate-700 rounded-xl overflow-hidden bg-white dark:bg-slate-800">
                            <button
                              type="button"
                              aria-label="Time-out 30 minutes earlier"
                              onClick={() => adjustShift(idx, "end", -0.5)}
                              className="w-11 h-11 border-0 bg-[#f6f7f9] hover:bg-[#eef0f4] dark:bg-slate-700 dark:hover:bg-slate-600 text-lg font-bold text-[#1b1f28] dark:text-white flex items-center justify-center cursor-pointer transition select-none"
                            >
                              −
                            </button>
                            <div className="px-3.5 text-center min-w-[96px]">
                              <div className="text-[10px] text-[#5a6272] dark:text-slate-400 font-semibold tracking-wider">
                                TIME-OUT
                              </div>
                              <div className="font-mono text-sm font-bold text-[#1b1f28] dark:text-white">
                                {fmtLong(end)}
                              </div>
                            </div>
                            <button
                              type="button"
                              aria-label="Time-out 30 minutes later"
                              onClick={() => adjustShift(idx, "end", 0.5)}
                              className="w-11 h-11 border-0 bg-[#f6f7f9] hover:bg-[#eef0f4] dark:bg-slate-700 dark:hover:bg-slate-600 text-lg font-bold text-[#1b1f28] dark:text-white flex items-center justify-center cursor-pointer transition select-none"
                            >
                              +
                            </button>
                          </div>

                          {/* DURATION BADGE */}
                          <span
                            className={`text-[12.5px] font-bold ${
                              isBadTime ? "text-[#a3141f]" : "text-[#3f4757] dark:text-slate-300"
                            }`}
                          >
                            {isBadTime ? "Invalid" : `${fmtH(durationHours)}/day${isOvernight ? " (Overnight)" : ""}`}
                          </span>
                        </div>

                        {/* ERROR NOTICE */}
                        {timeError && (
                          <div className="text-[12.5px] text-[#a3141f] font-semibold flex items-center gap-1.5">
                            <AlertTriangle className="w-3.5 h-3.5 shrink-0" />
                            <span>{timeError}</span>
                          </div>
                        )}

                        {/* APPLY TO ALL */}
                        {allocations.length > 1 && (
                          <div className="pt-0.5">
                            <button
                              type="button"
                              onClick={() => handleApplyTimeToAll(idx)}
                              className="border-0 bg-transparent text-[#1d4ed8] hover:text-[#12338f] text-[12.5px] font-semibold p-0 cursor-pointer underline transition"
                            >
                              Apply this time to all stores
                            </button>
                          </div>
                        )}
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>

        {/* Total HC Share & Invariant Notice */}
        <div className="pt-2 border-t border-[#e6e8ed] dark:border-slate-800 space-y-2">
          <div className="flex items-center justify-between text-xs">
            <span className="font-semibold text-[#1b1f28] dark:text-slate-200">
              Total Headcount Share:{" "}
              <span className={`font-mono font-bold ${isHcValid ? "text-[#0b6b3a]" : "text-[#a3141f]"}`}>
                {(totalHc / 100).toFixed(2)} HC
              </span>
            </span>
            <span className="text-[#5a6272] dark:text-slate-400">
              {allocations.length} {allocations.length === 1 ? "store allocation" : "store allocations"}
            </span>
          </div>

          <div className="p-2.5 rounded-lg bg-[#f8f9fb] dark:bg-slate-900 border border-[#dfe2e8] dark:border-slate-800 text-[11px] text-[#5a6272] dark:text-slate-400 flex items-center gap-2">
            <Lock className="w-3.5 h-3.5 text-[#5a6272] dark:text-slate-400 shrink-0" />
            <span>
              Store assignments, VCodes, and Headcount (HC) Shares are governed strictly by official Plantilla and Movement approvals.
            </span>
          </div>
        </div>

        {/* Error message */}
        {errorMessage && (
          <div className="p-3 bg-rose-50 dark:bg-rose-950/40 border border-rose-200 dark:border-rose-800 rounded-xl text-rose-800 dark:text-rose-300 text-xs flex items-center gap-2">
            <AlertTriangle className="w-4 h-4 text-rose-600 shrink-0" />
            <span>{errorMessage}</span>
          </div>
        )}

        {/* MODAL FOOTER */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pt-3 border-t border-[#e6e8ed] dark:border-slate-800">
          <button
            type="button"
            onClick={resetAll}
            title="Clear all schedule"
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg border border-[#cfd4dc] dark:border-slate-700 hover:bg-[#f6f7f9] dark:hover:bg-slate-800 text-[#5a6272] dark:text-slate-300 transition cursor-pointer self-start sm:self-auto"
          >
            <RotateCcw className="w-3.5 h-3.5" />
            <span>Reset</span>
          </button>

          {/* Status badge */}
          <div className="flex items-center gap-2 text-xs font-bold" style={{ color: statusColor }}>
            <span
              className="w-2 h-2 rounded-full shrink-0"
              style={{ backgroundColor: statusColor }}
            />
            <span>{statusText}</span>
          </div>

          <div className="flex items-center gap-2 self-end sm:self-auto">
            <button
              type="button"
              onClick={onClose}
              disabled={isSubmitting}
              className="px-4 py-2 text-xs font-semibold rounded-xl border border-[#cfd4dc] dark:border-slate-700 bg-white dark:bg-slate-800 hover:bg-[#f6f7f9] dark:hover:bg-slate-700 text-[#3a4150] dark:text-slate-300 transition cursor-pointer disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!canSave}
              className="inline-flex items-center gap-2 px-4 py-2 text-xs font-bold rounded-xl bg-[#1d4ed8] hover:bg-[#12338f] text-white shadow-xs transition cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
            >
              {isSubmitting && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
              <span>Save Schedule & Work Terms</span>
            </button>
          </div>
        </div>
      </form>
    </Modal>
  );
}
