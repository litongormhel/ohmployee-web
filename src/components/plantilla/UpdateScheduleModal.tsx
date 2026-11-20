"use client";

import React, { useState, useMemo } from "react";
import {
  Clock,
  Loader2,
  Calendar,
  Building2,
  AlertTriangle,
  Lock,
  RotateCcw,
  ChevronDown,
  ChevronUp,
  Copy,
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

// Palette derived directly from HTML mockup template (COL)
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

function parseShiftWindow(raw?: string | null): { timeIn: string; timeOut: string } {
  if (!raw || !raw.trim()) return { timeIn: "08:00 AM", timeOut: "05:00 PM" };
  const parts = raw.split("-").map((p) => p.trim());
  if (parts.length >= 2) {
    return { timeIn: parts[0] || "08:00 AM", timeOut: parts[1] || "05:00 PM" };
  }
  return { timeIn: raw.trim(), timeOut: "05:00 PM" };
}

function timeStringToMinutes(timeStr: string): number | null {
  if (!timeStr) return null;
  const match = timeStr.trim().match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
  if (!match) return null;
  let hours = parseInt(match[1], 10);
  const minutes = parseInt(match[2], 10);
  const period = match[3].toUpperCase();
  if (period === "PM" && hours < 12) hours += 12;
  if (period === "AM" && hours === 12) hours = 0;
  return hours * 60 + minutes;
}

function parseShiftInterval(shiftStr?: string | null): { start: number; end: number } | null {
  if (!shiftStr) return null;
  const parts = shiftStr.split("-").map((p) => p.trim());
  if (parts.length < 2) return null;
  const start = timeStringToMinutes(parts[0]);
  const end = timeStringToMinutes(parts[1]);
  if (start === null || end === null) return null;
  return { start, end };
}

function formatShortTime(timeStr?: string | null): string {
  if (!timeStr) return "";
  return timeStr
    .replace(/^0(\d):00\s*(AM|PM)/gi, "$1 $2")
    .replace(/ - 0?(\d):00\s*(AM|PM)/gi, " – $1 $2")
    .replace(/:00\s*(AM|PM)/gi, " $1");
}

function getShiftDurationMinutes(scheduleTime?: string | null): number | null {
  const parts = parseShiftWindow(scheduleTime);
  const start = timeStringToMinutes(parts.timeIn);
  const end = timeStringToMinutes(parts.timeOut);
  if (start === null || end === null) return null;
  if (end <= start) return null;
  return end - start;
}

function formatDurationText(minutes: number | null): string {
  if (minutes === null || minutes <= 0) return "--";
  const hrs = Math.floor(minutes / 60);
  const mins = minutes % 60;
  if (mins === 0) return `${hrs} hrs/day`;
  return `${hrs}h ${mins}m/day`;
}

function checkTimeError(scheduleTime?: string | null): string | null {
  const parts = parseShiftWindow(scheduleTime);
  const start = timeStringToMinutes(parts.timeIn);
  const end = timeStringToMinutes(parts.timeOut);
  if (start === null || end === null) return "Invalid time format";
  if (end <= start) return "Time-out must be later than time-in";
  return null;
}

function parse12HourTime(raw?: string): { hours: string; minutes: string; period: "AM" | "PM" } {
  if (!raw || !raw.trim()) {
    return { hours: "", minutes: "", period: "AM" };
  }
  const match = raw.match(/(\d{1,2}|--):(\d{2}|--)\s*(AM|PM)?/i);
  if (!match) {
    return { hours: "", minutes: "", period: "AM" };
  }
  return {
    hours: match[1] === "--" ? "" : match[1],
    minutes: match[2] === "--" ? "" : match[2],
    period: (match[3] || "AM").toUpperCase() === "PM" ? "PM" : "AM",
  };
}

interface TimeSegmentInputProps {
  label: "Time-in" | "Time-out";
  value?: string;
  onChange: (val: string) => void;
}

function TimeSegmentInput({ label, value, onChange }: TimeSegmentInputProps) {
  const { hours, minutes, period } = useMemo(() => parse12HourTime(value), [value]);

  const hoursRef = React.useRef<HTMLInputElement>(null);
  const minutesRef = React.useRef<HTMLInputElement>(null);

  const handleHoursChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const raw = e.target.value.replace(/\D/g, "").slice(0, 2);
    const num = parseInt(raw, 10);
    let finalH = raw;
    if (num > 12) finalH = "12";
    if (num === 0 && raw.length === 2) finalH = "12";
    onChange(`${finalH || "--"}:${minutes || "--"} ${period}`);
    if (raw.length === 2 || num > 1) {
      minutesRef.current?.focus();
      minutesRef.current?.select();
    }
  };

  const handleHoursBlur = () => {
    if (!hours) return;
    const num = parseInt(hours, 10);
    let finalH = hours;
    if (isNaN(num) || num === 0) finalH = "12";
    else if (num > 12) finalH = "12";
    onChange(`${finalH.padStart(2, "0")}:${minutes || "--"} ${period}`);
  };

  const handleMinutesChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const raw = e.target.value.replace(/\D/g, "").slice(0, 2);
    const num = parseInt(raw, 10);
    let finalM = raw;
    if (num > 59) finalM = "59";
    onChange(`${hours || "--"}:${finalM || "--"} ${period}`);
  };

  const handleMinutesBlur = () => {
    if (!minutes) return;
    const num = parseInt(minutes, 10);
    let finalM = minutes;
    if (isNaN(num)) finalM = "00";
    else if (num > 59) finalM = "59";
    onChange(`${hours || "--"}:${finalM.padStart(2, "0")} ${period}`);
  };

  const handleHoursKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === ":" || e.key === "Enter" || e.key === "ArrowRight") {
      e.preventDefault();
      minutesRef.current?.focus();
      minutesRef.current?.select();
    }
  };

  const handleMinutesKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Backspace" && !minutes) {
      e.preventDefault();
      hoursRef.current?.focus();
      hoursRef.current?.select();
    } else if (e.key === "a" || e.key === "A") {
      e.preventDefault();
      onChange(`${hours || "--"}:${minutes || "--"} AM`);
    } else if (e.key === "p" || e.key === "P") {
      e.preventDefault();
      onChange(`${hours || "--"}:${minutes || "--"} PM`);
    }
  };

  const togglePeriod = () => {
    const next = period === "AM" ? "PM" : "AM";
    onChange(`${hours || "--"}:${minutes || "--"} ${next}`);
  };

  const handleNativePicker = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (!e.target.value) return;
    const [h24, m] = e.target.value.split(":");
    let hNum = parseInt(h24, 10);
    const p: "AM" | "PM" = hNum >= 12 ? "PM" : "AM";
    hNum = hNum % 12;
    if (hNum === 0) hNum = 12;
    const h12 = String(hNum).padStart(2, "0");
    onChange(`${h12}:${m} ${p}`);
  };

  const nativeTime24 = useMemo(() => {
    if (!hours || !minutes || hours === "--" || minutes === "--") return "";
    let hNum = parseInt(hours, 10);
    if (isNaN(hNum)) return "";
    if (period === "PM" && hNum < 12) hNum += 12;
    if (period === "AM" && hNum === 12) hNum = 0;
    return `${String(hNum).padStart(2, "0")}:${minutes.padStart(2, "0")}`;
  }, [hours, minutes, period]);

  return (
    <fieldset className="rounded-xl border border-slate-300 dark:border-slate-700 px-3.5 pt-1 pb-2 focus-within:border-brand-primary focus-within:ring-1 focus-within:ring-brand-primary transition bg-white dark:bg-slate-900 shadow-2xs">
      <legend className="px-1 text-[11px] font-semibold text-slate-500 dark:text-slate-400 select-none">
        {label}
      </legend>
      <div className="flex items-center justify-between gap-1.5 mt-0.5">
        <div className="flex items-center gap-1 font-mono text-sm font-bold text-slate-900 dark:text-slate-100">
          <input
            ref={hoursRef}
            type="text"
            inputMode="numeric"
            pattern="[0-9]*"
            maxLength={2}
            value={hours}
            onChange={handleHoursChange}
            onBlur={handleHoursBlur}
            onKeyDown={handleHoursKeyDown}
            placeholder="--"
            className="w-7 text-center bg-transparent focus:outline-none focus:bg-brand-50 dark:focus:bg-brand-950/40 rounded py-0.5 selection:bg-brand-primary selection:text-white"
            aria-label={`${label} Hours`}
          />
          <span className="text-slate-400 select-none font-bold">:</span>
          <input
            ref={minutesRef}
            type="text"
            inputMode="numeric"
            pattern="[0-9]*"
            maxLength={2}
            value={minutes}
            onChange={handleMinutesChange}
            onBlur={handleMinutesBlur}
            onKeyDown={handleMinutesKeyDown}
            placeholder="--"
            className="w-7 text-center bg-transparent focus:outline-none focus:bg-brand-50 dark:focus:bg-brand-950/40 rounded py-0.5 selection:bg-brand-primary selection:text-white"
            aria-label={`${label} Minutes`}
          />
          <button
            type="button"
            onClick={togglePeriod}
            className="ml-2 px-2.5 py-0.5 text-xs font-bold rounded-md bg-brand-50 text-brand-primary dark:bg-brand-950/60 dark:text-brand-300 border border-brand-200 dark:border-brand-800 hover:bg-brand-100 transition cursor-pointer select-none"
            title="Click to toggle AM / PM"
          >
            {period}
          </button>
        </div>

        <label className="relative cursor-pointer text-slate-400 hover:text-slate-700 dark:hover:text-slate-200 transition shrink-0 p-1.5 rounded-lg hover:bg-slate-100 dark:hover:bg-slate-800">
          <Clock className="w-4 h-4" />
          <input
            type="time"
            value={nativeTime24}
            onChange={handleNativePicker}
            className="absolute inset-0 opacity-0 cursor-pointer w-full h-full"
            title={`Pick ${label}`}
          />
        </label>
      </div>
    </fieldset>
  );
}

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
  onSuccess,
}: UpdateScheduleModalProps) {
  // Multi-select designated rest days
  const [selectedDayoffs, setSelectedDayoffs] = useState<DayCode[]>(() =>
    parseDayoffString(initialDayoff)
  );

  // Store allocations matrix (strictly read-only for store identity and HC share)
  const defaultAllocations: StoreAllocationItem[] = useMemo(() => {
    if (initialStoreAllocations && initialStoreAllocations.length > 0) {
      return initialStoreAllocations.map((a) => ({
        storeId: a.storeId ?? "",
        storeName: a.storeName || "Primary Store",
        vcode: a.vcode ?? "",
        scheduleDays:
          (a.scheduleDays && a.scheduleDays.trim()) ||
          (initialStoreAllocations.length === 1
            ? (initialScheduleDays && initialScheduleDays.trim()) || "MON-SAT"
            : ""),
        scheduleTime:
          (a.scheduleTime && a.scheduleTime.trim()) ||
          (initialScheduleTime && initialScheduleTime.trim()) ||
          "08:00 AM - 05:00 PM",
        allocationPercent:
          a.allocationPercent ??
          (initialStoreAllocations.length > 1
            ? Math.round(100 / initialStoreAllocations.length)
            : 100),
      }));
    }
    return [
      {
        storeId: "",
        storeName: "Primary Store Assignment",
        vcode: "",
        scheduleDays: (initialScheduleDays && initialScheduleDays.trim()) || "MON-SAT",
        scheduleTime: (initialScheduleTime && initialScheduleTime.trim()) || "08:00 AM - 05:00 PM",
        allocationPercent: 100,
      },
    ];
  }, [initialStoreAllocations, initialScheduleDays, initialScheduleTime]);

  const [allocations, setAllocations] = useState<StoreAllocationItem[]>(defaultAllocations);
  const [expandedStoreIdx, setExpandedStoreIdx] = useState<number | null>(0);
  const [restDayNotice, setRestDayNotice] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isConfirmResetOpen, setIsConfirmResetOpen] = useState(false);

  // Dismiss rest day notice on any user action
  const dismissNotice = () => {
    if (restDayNotice) setRestDayNotice(null);
  };

  const handleResetSchedule = () => {
    setSelectedDayoffs([]);
    setAllocations((prev) =>
      prev.map((a) => ({
        ...a,
        scheduleDays: "",
        scheduleTime: "",
      }))
    );
    setIsConfirmResetOpen(false);
  };

  const isScheduleComplete = useMemo(() => {
    if (selectedDayoffs.length === 0) return false;
    return allocations.every((a) => {
      const days = (a.scheduleDays || "").trim();
      const time = (a.scheduleTime || "08:00 AM - 05:00 PM").trim();
      if (!days) return false;
      if (time.includes("--") || time === "-") return false;
      const parts = time.split("-").map((p) => p.trim());
      if (parts.length < 2 || !parts[0] || !parts[1]) return false;
      return true;
    });
  }, [selectedDayoffs, allocations]);

  // Total HC calculation & validation
  const totalPercent = useMemo(() => {
    return allocations.reduce(
      (sum, item) => sum + (Number(item.allocationPercent) || 0),
      0
    );
  }, [allocations]);

  const totalHcShare = (totalPercent / 100).toFixed(2);
  const isHcValid = Math.abs(totalPercent - 100) <= 1 || allocations.length === 1;

  // Toggle multi-select rest days with auto-carving from store duty days & notice banner
  const handleToggleDayoff = (day: DayCode) => {
    setSelectedDayoffs((prev) => {
      if (prev.includes(day)) {
        if (prev.length === 1) return prev; // Keep at least 1 rest day
        setRestDayNotice(null);
        return prev.filter((d) => d !== day);
      }

      // Day is being designated as rest day: remove from any store duty days
      const affectedStores: string[] = [];
      setAllocations((prevAlloc) =>
        prevAlloc.map((item, idx) => {
          const daySet = parseDaysToSet(item.scheduleDays);
          if (daySet.has(day)) {
            daySet.delete(day);
            affectedStores.push(item.storeName || `Store ${idx + 1}`);
            return { ...item, scheduleDays: formatDaysFromSet(daySet) };
          }
          return item;
        })
      );

      if (affectedStores.length > 0) {
        setRestDayNotice(
          `${day} marked as rest day. Removed from ${affectedStores.join(", ")}.`
        );
      } else {
        setRestDayNotice(null);
      }

      return [...prev, day];
    });
  };

  // Check if any allocation day conflicts with rest days (failsafe guard)
  const conflictingDays = useMemo(() => {
    const conflicts = new Set<string>();
    allocations.forEach((item) => {
      const daysStr = (item.scheduleDays || "").toUpperCase();
      selectedDayoffs.forEach((d) => {
        if (daysStr.includes(d)) conflicts.add(d);
      });
    });
    return Array.from(conflicts);
  }, [allocations, selectedDayoffs]);

  // Strict Roving Policy: Detect overlapping duty days and shift windows across stores
  const rovingOverlapConflicts = useMemo(() => {
    if (allocations.length <= 1) return [];
    const conflicts: Array<{
      storeA: string;
      storeB: string;
      days: string[];
      timeA: string;
      timeB: string;
    }> = [];

    for (let i = 0; i < allocations.length; i++) {
      for (let j = i + 1; j < allocations.length; j++) {
        const allocA = allocations[i];
        const allocB = allocations[j];
        const daysA = parseDaysToSet(allocA.scheduleDays);
        const daysB = parseDaysToSet(allocB.scheduleDays);
        const sharedDays = DAYS_OF_WEEK.filter((d) => daysA.has(d) && daysB.has(d));

        if (sharedDays.length > 0) {
          const timeA = (allocA.scheduleTime || "08:00 AM - 05:00 PM").trim();
          const timeB = (allocB.scheduleTime || "08:00 AM - 05:00 PM").trim();
          const intervalA = parseShiftInterval(timeA);
          const intervalB = parseShiftInterval(timeB);

          const overlaps =
            !intervalA ||
            !intervalB ||
            Math.max(intervalA.start, intervalB.start) < Math.min(intervalA.end, intervalB.end);

          if (overlaps) {
            conflicts.push({
              storeA: allocA.storeName || `Store ${i + 1}`,
              storeB: allocB.storeName || `Store ${j + 1}`,
              days: sharedDays,
              timeA,
              timeB,
            });
          }
        }
      }
    }
    return conflicts;
  }, [allocations]);

  const hasRovingConflict = rovingOverlapConflicts.length > 0;
  const hasRestDayConflict = conflictingDays.length > 0;

  // Time errors across stores
  const hasTimeError = useMemo(() => {
    return allocations.some((a) => checkTimeError(a.scheduleTime) !== null);
  }, [allocations]);

  // Unassigned days count
  const unassignedDays = useMemo(() => {
    return DAYS_OF_WEEK.filter(
      (d) =>
        !selectedDayoffs.includes(d) &&
        !allocations.some((a) => parseDaysToSet(a.scheduleDays).has(d))
    );
  }, [selectedDayoffs, allocations]);

  // Total weekly hours calculation across all assigned duty days
  const totalWeeklyHours = useMemo(() => {
    let totalMinutes = 0;
    DAYS_OF_WEEK.forEach((d) => {
      if (selectedDayoffs.includes(d)) return;
      const store = allocations.find((a) => parseDaysToSet(a.scheduleDays).has(d));
      if (store) {
        const duration = getShiftDurationMinutes(store.scheduleTime);
        if (duration !== null && duration > 0) {
          totalMinutes += duration;
        }
      }
    });
    const hours = (totalMinutes / 60).toFixed(1).replace(/\.0$/, "");
    return hours;
  }, [selectedDayoffs, allocations]);

  const isDirty = useMemo(() => {
    const initialDayoffs = parseDayoffString(initialDayoff);
    const dayoffsChanged =
      selectedDayoffs.length !== initialDayoffs.length ||
      selectedDayoffs.some((d) => !initialDayoffs.includes(d));
    if (dayoffsChanged) return true;

    for (let i = 0; i < allocations.length; i++) {
      if (
        allocations[i].scheduleDays !== defaultAllocations[i]?.scheduleDays ||
        allocations[i].scheduleTime !== defaultAllocations[i]?.scheduleTime
      ) {
        return true;
      }
    }
    return false;
  }, [selectedDayoffs, initialDayoff, allocations, defaultAllocations]);

  // Update allocation duty days / shift time
  const updateAllocation = (index: number, updates: Partial<StoreAllocationItem>) => {
    setAllocations((prev) => {
      const copy = [...prev];
      copy[index] = { ...copy[index], ...updates };
      return copy;
    });
  };

  // Cross-store aware duty day chip click:
  // - If day in current store: removes it
  // - If day in other store: takes over day from other store to current store
  // - If day unassigned: assigns to current store
  // - If rest day: disabled/no-op
  const handleDayChipClick = (storeIdx: number, day: DayCode) => {
    dismissNotice();
    if (selectedDayoffs.includes(day)) return;

    setAllocations((prev) => {
      const next = [...prev];
      const currentSet = parseDaysToSet(next[storeIdx].scheduleDays);

      if (currentSet.has(day)) {
        currentSet.delete(day);
        next[storeIdx] = {
          ...next[storeIdx],
          scheduleDays: formatDaysFromSet(currentSet),
        };
        return next;
      }

      // Check if another store currently owns this day; if so, release it
      next.forEach((item, otherIdx) => {
        if (otherIdx !== storeIdx) {
          const otherSet = parseDaysToSet(item.scheduleDays);
          if (otherSet.has(day)) {
            otherSet.delete(day);
            next[otherIdx] = {
              ...item,
              scheduleDays: formatDaysFromSet(otherSet),
            };
          }
        }
      });

      // Assign to current store
      currentSet.add(day);
      next[storeIdx] = {
        ...next[storeIdx],
        scheduleDays: formatDaysFromSet(currentSet),
      };
      return next;
    });
  };

  const handleTimeInChange = (idx: number, newTimeIn: string) => {
    dismissNotice();
    const current = parseShiftWindow(allocations[idx]?.scheduleTime);
    const timeOut = current.timeOut || "05:00 PM";
    const updated = newTimeIn ? `${newTimeIn} - ${timeOut}` : "";
    updateAllocation(idx, { scheduleTime: updated });
  };

  const handleTimeOutChange = (idx: number, newTimeOut: string) => {
    dismissNotice();
    const current = parseShiftWindow(allocations[idx]?.scheduleTime);
    const timeIn = current.timeIn || "08:00 AM";
    const updated = newTimeOut ? `${timeIn} - ${newTimeOut}` : "";
    updateAllocation(idx, { scheduleTime: updated });
  };

  // Apply shift time window to all stores
  const handleApplyTimeToAll = (sourceIdx: number) => {
    dismissNotice();
    const targetTime = allocations[sourceIdx]?.scheduleTime || "08:00 AM - 05:00 PM";
    setAllocations((prev) =>
      prev.map((a) => ({
        ...a,
        scheduleTime: targetTime,
      }))
    );
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (hasTimeError || !isScheduleComplete || !isHcValid || hasRovingConflict || hasRestDayConflict) {
      return;
    }
    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      const primaryScheduleDays = allocations[0]?.scheduleDays || "MON-SAT";
      const primaryScheduleTime = allocations[0]?.scheduleTime || "08:00 AM - 05:00 PM";
      const dayoffString = selectedDayoffs.join(", ");

      const storeAllocationsPayload: StoreAllocationInput[] = allocations.map((a) => ({
        storeId: a.storeId,
        storeName: a.storeName,
        vcode: a.vcode,
        scheduleDays: a.scheduleDays,
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
        err instanceof Error ? err.message : "Failed to update schedule and allocations."
      );
    } finally {
      setIsSubmitting(false);
    }
  };

  // Render modal footer (Sticky & Clean matching screenshot)
  const modalFooter = (
    <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 w-full">
      <div className="flex flex-wrap items-center gap-3">
        <button
          type="button"
          onClick={() => setIsConfirmResetOpen(true)}
          disabled={isSubmitting}
          className="h-10 px-4 rounded-xl border border-rose-200 bg-white dark:bg-slate-900 text-rose-700 dark:text-rose-400 hover:bg-rose-50 dark:hover:bg-rose-950/40 font-bold text-xs transition flex items-center gap-1.5 cursor-pointer shadow-2xs disabled:opacity-50"
          title="Reset all duty days, shift times, and rest days"
        >
          <RotateCcw className="w-3.5 h-3.5" />
          <span>Reset</span>
        </button>

        {/* Footer Status Indicators */}
        <div className="flex items-center gap-3">
          {hasTimeError ? (
            <span className="text-rose-600 dark:text-rose-400 font-bold text-xs flex items-center gap-1.5">
              <span className="w-2.5 h-2.5 rounded-full bg-rose-600 shrink-0" />
              <span>Time-out must be later than time-in</span>
            </span>
          ) : !isScheduleComplete ? (
            <span className="text-amber-600 dark:text-amber-400 font-semibold text-xs flex items-center gap-1.5">
              <span className="w-2.5 h-2.5 rounded-full bg-amber-500 shrink-0" />
              <span>Schedule incomplete (each store requires duty days)</span>
            </span>
          ) : hasRovingConflict ? (
            <span className="text-rose-600 dark:text-rose-400 font-bold text-xs flex items-center gap-1.5">
              <span className="w-2.5 h-2.5 rounded-full bg-rose-600 shrink-0" />
              <span>
                Overlap conflict: {rovingOverlapConflicts[0]?.storeA} &amp; {rovingOverlapConflicts[0]?.storeB}
              </span>
            </span>
          ) : hasRestDayConflict ? (
            <span className="text-rose-600 dark:text-rose-400 font-bold text-xs flex items-center gap-1.5">
              <span className="w-2.5 h-2.5 rounded-full bg-rose-600 shrink-0" />
              <span>Rest day conflict on {conflictingDays.join(", ")}</span>
            </span>
          ) : !isHcValid ? (
            <span className="text-rose-600 dark:text-rose-400 font-bold text-xs flex items-center gap-1.5">
              <span className="w-2.5 h-2.5 rounded-full bg-rose-600 shrink-0" />
              <span>Sum is {totalHcShare} HC. Must equal 1.00 HC.</span>
            </span>
          ) : (
            <div className="flex flex-wrap items-center gap-2.5 text-xs">
              <span className="font-bold text-slate-900 dark:text-slate-100 text-sm">
                {totalWeeklyHours} hrs/wk
              </span>
              {unassignedDays.length > 0 ? (
                <span className="text-amber-600 dark:text-amber-400 font-medium flex items-center gap-1.5">
                  <span className="w-2.5 h-2.5 rounded-full bg-amber-500 shrink-0" />
                  <span>
                    {unassignedDays.length} {unassignedDays.length === 1 ? "day" : "days"} without a store
                  </span>
                </span>
              ) : (
                <span className="text-emerald-700 dark:text-emerald-400 font-bold flex items-center gap-1.5">
                  <span className="w-2.5 h-2.5 rounded-full bg-emerald-500 shrink-0" />
                  <span>Ready to save</span>
                </span>
              )}
            </div>
          )}
        </div>
      </div>

      <div className="flex items-center gap-2.5 self-end sm:self-auto shrink-0">
        <button
          type="button"
          onClick={onClose}
          disabled={isSubmitting}
          className="h-10 px-5 rounded-xl border border-slate-300 dark:border-slate-700 bg-white dark:bg-slate-900 hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-300 font-semibold text-xs transition cursor-pointer"
        >
          Cancel
        </button>
        <button
          type="submit"
          form="update-schedule-form"
          disabled={
            isSubmitting ||
            hasTimeError ||
            !isScheduleComplete ||
            !isHcValid ||
            hasRovingConflict ||
            hasRestDayConflict
          }
          className="h-10 px-6 rounded-xl bg-brand-primary hover:bg-brand-secondary text-white font-bold text-xs transition shadow-sm cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
        >
          {isSubmitting ? (
            <>
              <Loader2 className="w-3.5 h-3.5 animate-spin" />
              <span>Saving…</span>
            </>
          ) : (
            <span>Save Schedule & Work Terms</span>
          )}
        </button>
      </div>
    </div>
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Edit Schedule & Work Terms"
      subtitle="Configuring rest days, per-store duty days, and shift time windows"
      icon={Clock}
      isSubmitting={isSubmitting}
      isDirty={isDirty}
      maxWidthClass="max-w-[760px]"
      footer={modalFooter}
    >
      {errorMessage && (
        <div className="mb-4 rounded-xl bg-rose-50 dark:bg-rose-950/40 border border-rose-200 dark:border-rose-800 p-3.5 text-xs text-rose-800 dark:text-rose-200 flex items-center justify-between">
          <span>{errorMessage}</span>
          <button
            type="button"
            onClick={() => setErrorMessage(null)}
            className="font-bold text-sm ml-2 cursor-pointer text-rose-600 hover:text-rose-800"
          >
            ✕
          </button>
        </div>
      )}

      <form id="update-schedule-form" onSubmit={handleSave} className="space-y-4">
        {/* TOP CARD: REST DAY + WEEKLY COVERAGE PREVIEW */}
        <div className="p-4 rounded-2xl bg-slate-50/80 dark:bg-slate-900/60 border border-slate-200/90 dark:border-slate-800 space-y-3.5">
          {/* Row 1: Rest Day Selector */}
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex flex-wrap items-center gap-2.5">
              <span className="text-xs font-bold text-slate-800 dark:text-slate-200 flex items-center gap-1.5 select-none">
                <Calendar className="w-4 h-4 text-brand-primary shrink-0" />
                <span>Rest Day:</span>
              </span>
              <div className="flex items-center gap-1.5">
                {DAYS_OF_WEEK.map((d) => {
                  const isSelected = selectedDayoffs.includes(d);
                  return (
                    <button
                      key={d}
                      type="button"
                      onClick={() => handleToggleDayoff(d)}
                      className={`px-3 py-1 text-xs font-bold rounded-lg border transition cursor-pointer select-none ${
                        isSelected
                          ? "bg-brand-primary text-white border-brand-primary shadow-xs"
                          : "bg-white dark:bg-slate-800 border-slate-300 dark:border-slate-700 text-slate-700 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-700"
                      }`}
                    >
                      {d}
                    </button>
                  );
                })}
              </div>
            </div>
            <span className="text-xs font-medium text-slate-500 dark:text-slate-400 select-none">
              {selectedDayoffs.length} {selectedDayoffs.length === 1 ? "Rest Day" : "Rest Days"}
            </span>
          </div>

          {/* Row 2: Weekly Coverage Preview */}
          <div className="pt-3 border-t border-slate-200/80 dark:border-slate-800 space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-[11px] font-bold text-slate-600 dark:text-slate-400 uppercase tracking-wider select-none">
                WEEKLY COVERAGE PREVIEW
              </span>
              <span className="text-[11px] font-medium text-slate-500 dark:text-slate-400 flex items-center gap-1 select-none">
                <span>Live sync</span>
              </span>
            </div>

            <div className="grid grid-cols-7 gap-2">
              {DAYS_OF_WEEK.map((day) => {
                const isRestDay = selectedDayoffs.includes(day);
                const assignedStoreIdx = allocations.findIndex((a) =>
                  parseDaysToSet(a.scheduleDays).has(day)
                );
                const assignedStore = assignedStoreIdx !== -1 ? allocations[assignedStoreIdx] : null;

                if (isRestDay) {
                  return (
                    <div
                      key={day}
                      className="rounded-xl border border-[#d5d9e0] dark:border-slate-700 bg-[#eceef2] dark:bg-slate-800 p-2.5 text-center flex flex-col items-center justify-between min-h-[96px] shadow-2xs"
                    >
                      <span className="text-[11px] font-bold tracking-wider text-[#3a4150] dark:text-slate-300 select-none">
                        {day}
                      </span>
                      <div className="w-[26px] h-[26px] rounded-full bg-[#5f6675] text-white text-xs font-bold flex items-center justify-center shadow-xs shrink-0 select-none">
                        R
                      </div>
                      <p className="font-mono text-[10.5px] font-bold text-slate-800 dark:text-slate-200 select-none">
                        Rest
                      </p>
                      <p className="text-[11px] text-[#4a5262] dark:text-slate-400 font-medium select-none">
                        Day off
                      </p>
                    </div>
                  );
                }

                if (assignedStore) {
                  const color = getStoreColor(assignedStoreIdx);
                  const timeFormatted = formatShortTime(assignedStore.scheduleTime);
                  return (
                    <div
                      key={day}
                      className="rounded-xl p-2.5 text-center flex flex-col items-center justify-between min-h-[96px] shadow-2xs transition"
                      style={{
                        backgroundColor: color.tint,
                        border: `1px solid ${color.solid}`,
                      }}
                      title={`${day}: ${assignedStore.storeName} (${assignedStore.vcode || "No VCode"}) · ${assignedStore.scheduleTime}`}
                    >
                      <span className="text-[11px] font-bold tracking-wider text-[#3a4150] select-none">
                        {day}
                      </span>
                      <div
                        className="w-[26px] h-[26px] rounded-full text-white text-xs font-bold flex items-center justify-center shadow-xs shrink-0 select-none"
                        style={{ backgroundColor: color.solid }}
                      >
                        {assignedStoreIdx + 1}
                      </div>
                      <p className="font-mono text-[10.5px] font-bold text-[#1a1f2b] tracking-tight whitespace-nowrap w-full px-0.5 select-none">
                        {assignedStore.vcode || assignedStore.storeName}
                      </p>
                      <p className="text-[11px] text-[#4a5262] font-semibold truncate w-full select-none">
                        {timeFormatted || "8 AM – 5 PM"}
                      </p>
                    </div>
                  );
                }

                // Unassigned day
                return (
                  <div
                    key={day}
                    className="rounded-xl border border-dashed border-[#a14d00] bg-[#fff7e6] p-2.5 text-center flex flex-col items-center justify-between min-h-[96px] shadow-2xs"
                    title={`${day}: No store assigned`}
                  >
                    <span className="text-[11px] font-bold tracking-wider text-[#a14d00] select-none">
                      {day}
                    </span>
                    <div className="w-[26px] h-[26px] rounded-full bg-white text-[#a14d00] border border-[#a14d00] text-xs font-bold flex items-center justify-center shadow-xs shrink-0 select-none">
                      !
                    </div>
                    <p className="font-mono text-[10.5px] font-bold text-[#a14d00] select-none">
                      No store
                    </p>
                    <p className="text-[11px] text-[#a14d00]/80 font-medium select-none">
                      Unassigned
                    </p>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        {/* REST DAY NOTICE BANNER */}
        {restDayNotice && (
          <div className="rounded-xl bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800 p-3 text-xs text-amber-800 dark:text-amber-200 flex items-center justify-between animate-fade-in">
            <div className="flex items-center gap-2 font-medium">
              <AlertTriangle className="w-4 h-4 shrink-0 text-amber-600 dark:text-amber-400" />
              <span>{restDayNotice}</span>
            </div>
            <button
              type="button"
              onClick={() => setRestDayNotice(null)}
              className="text-amber-600 hover:text-amber-900 dark:text-amber-400 dark:hover:text-amber-100 font-bold text-sm ml-2 cursor-pointer p-0.5"
              title="Dismiss notice"
            >
              ✕
            </button>
          </div>
        )}

        {/* ASSIGNED STORES & SHIFT WINDOWS (ACCORDION CARDS) */}
        <div className="space-y-3 pt-1">
          <div className="flex items-center justify-between px-0.5">
            <h4 className="text-xs font-bold text-slate-800 dark:text-slate-200 flex items-center gap-2">
              <Building2 className="w-4 h-4 text-brand-primary" />
              <span>Assigned Stores & Shift Windows</span>
            </h4>
            <span className="text-xs text-slate-500 dark:text-slate-400">
              Click header to expand or collapse
            </span>
          </div>

          <div className="space-y-2.5">
            {allocations.map((alloc, idx) => {
              const color = getStoreColor(idx);
              const isExpanded = expandedStoreIdx === idx;
              const currentDaySet = parseDaysToSet(alloc.scheduleDays);
              const formattedDays = formatDaysFromSet(currentDaySet) || "No duty days";
              const timeFormatted = formatShortTime(alloc.scheduleTime) || "08:00 AM - 05:00 PM";
              const hcFraction = (alloc.allocationPercent / 100).toFixed(2);
              const durationMin = getShiftDurationMinutes(alloc.scheduleTime);
              const timeError = checkTimeError(alloc.scheduleTime);
              const shiftTimes = parseShiftWindow(alloc.scheduleTime);

              return (
                <div
                  key={idx}
                  className="rounded-2xl border transition overflow-hidden bg-white dark:bg-slate-900 shadow-2xs"
                  style={{
                    borderColor: isExpanded ? color.solid : undefined,
                    boxShadow: isExpanded ? `0 0 0 1px ${color.solid}33` : undefined,
                  }}
                >
                  {/* Card Header (Accordion Toggle) */}
                  <button
                    type="button"
                    onClick={() => {
                      dismissNotice();
                      setExpandedStoreIdx((prev) => (prev === idx ? null : idx));
                    }}
                    className="w-full text-left p-3.5 flex items-center justify-between gap-3 cursor-pointer bg-white dark:bg-slate-900 hover:bg-slate-50/70 dark:hover:bg-slate-800/40 transition"
                  >
                    <div className="flex flex-wrap items-center gap-2 text-xs text-slate-600 dark:text-slate-300 min-w-0">
                      <span
                        className="w-[26px] h-[26px] rounded-full text-white text-xs font-bold flex items-center justify-center shrink-0 shadow-xs select-none"
                        style={{ backgroundColor: color.solid }}
                      >
                        {idx + 1}
                      </span>
                      <span className="font-bold text-slate-900 dark:text-slate-100 truncate max-w-[200px] uppercase">
                        {alloc.storeName}
                      </span>
                      {alloc.vcode && (
                        <span
                          className="font-mono text-xs font-semibold px-2 py-0.5 rounded-md border shrink-0"
                          style={{
                            color: color.solid,
                            borderColor: color.solid + "66",
                            backgroundColor: color.tint,
                          }}
                        >
                          {alloc.vcode}
                        </span>
                      )}
                      <span className="text-slate-300 dark:text-slate-700">·</span>
                      <span className="font-semibold text-slate-700 dark:text-slate-300 shrink-0">
                        {formattedDays}
                      </span>
                      <span className="text-slate-300 dark:text-slate-700">·</span>
                      <span className="font-medium text-slate-600 dark:text-slate-400 shrink-0">
                        {timeFormatted}
                      </span>
                      <span className="text-slate-300 dark:text-slate-700">·</span>
                      <span className="text-xs text-slate-500 dark:text-slate-400 font-medium shrink-0">
                        {hcFraction} HC
                      </span>
                    </div>

                    <div className="shrink-0 text-slate-400 hover:text-slate-700 dark:hover:text-slate-200">
                      {isExpanded ? (
                        <ChevronUp className="w-4 h-4" />
                      ) : (
                        <ChevronDown className="w-4 h-4" />
                      )}
                    </div>
                  </button>

                  {/* Expanded Card Content */}
                  {isExpanded && (
                    <div className="p-4.5 pt-3 border-t border-slate-100 dark:border-slate-800/70 bg-slate-50/40 dark:bg-slate-900/40 space-y-4">
                      {/* Subtitle row */}
                      <div className="flex items-center justify-between text-xs text-slate-500 dark:text-slate-400 pb-1.5 border-b border-slate-200/60 dark:border-slate-800">
                        <span>Duty days and shift hours for {alloc.storeName}</span>
                        <span className="font-semibold text-slate-700 dark:text-slate-300">
                          HC Share: {hcFraction} ({alloc.allocationPercent}%)
                        </span>
                      </div>

                      {/* DUTY DAYS selector */}
                      <div className="space-y-2">
                        <div className="flex items-center justify-between">
                          <label className="text-[11px] font-bold text-slate-600 dark:text-slate-400 uppercase tracking-wider select-none">
                            DUTY DAYS
                          </label>
                          <span className="text-xs font-medium text-slate-500 dark:text-slate-400 select-none">
                            {currentDaySet.size} {currentDaySet.size === 1 ? "day assigned" : "days assigned"}
                          </span>
                        </div>

                        <div className="grid grid-cols-7 gap-2">
                          {DAYS_OF_WEEK.map((d) => {
                            const isRestDay = selectedDayoffs.includes(d);
                            const isCurrentStore = currentDaySet.has(d);
                            const otherStoreIdx = allocations.findIndex(
                              (a, i) => i !== idx && parseDaysToSet(a.scheduleDays).has(d)
                            );

                            if (isRestDay) {
                              return (
                                <button
                                  key={d}
                                  type="button"
                                  disabled
                                  className="h-13 rounded-xl border border-[#e3e6eb] bg-[#f1f2f5] text-[#5f6675] cursor-not-allowed text-center flex flex-col items-center justify-center gap-0.5 select-none opacity-60"
                                  title={`${d} is marked as rest day`}
                                >
                                  <span className="text-xs font-bold">{d}</span>
                                  <span className="text-[10px] font-semibold text-[#5f6675]">Rest</span>
                                </button>
                              );
                            }

                            if (isCurrentStore) {
                              return (
                                <button
                                  key={d}
                                  type="button"
                                  onClick={() => handleDayChipClick(idx, d)}
                                  className="h-13 rounded-xl border shadow-xs transition cursor-pointer text-center flex flex-col items-center justify-center gap-0.5 select-none"
                                  style={{
                                    backgroundColor: color.tint,
                                    borderColor: color.solid,
                                    color: color.ink,
                                  }}
                                  title={`Assigned to ${alloc.storeName}. Click to remove.`}
                                >
                                  <span className="text-xs font-bold">{d}</span>
                                  <span className="text-[10px] font-bold">✓ Active</span>
                                </button>
                              );
                            }

                            if (otherStoreIdx !== -1) {
                              const otherColor = getStoreColor(otherStoreIdx);
                              return (
                                <button
                                  key={d}
                                  type="button"
                                  onClick={() => handleDayChipClick(idx, d)}
                                  className="h-13 rounded-xl border border-[#e3e6eb] bg-[#f1f2f5] text-[#5f6675] hover:border-slate-400 transition cursor-pointer text-center flex flex-col items-center justify-center gap-0.5 select-none"
                                  title={`Currently assigned to Store ${otherStoreIdx + 1} (${allocations[otherStoreIdx].storeName}). Tap to move here.`}
                                >
                                  <span className="text-xs font-bold text-slate-700">{d}</span>
                                  <span
                                    className="text-[10px] font-bold"
                                    style={{ color: otherColor.solid }}
                                  >
                                    In {otherStoreIdx + 1}
                                  </span>
                                </button>
                              );
                            }

                            // Unassigned
                            return (
                              <button
                                key={d}
                                type="button"
                                onClick={() => handleDayChipClick(idx, d)}
                                className="h-13 rounded-xl border border-[#cfd4dc] bg-white text-[#3a4150] hover:bg-slate-50 hover:border-slate-400 transition cursor-pointer text-center flex flex-col items-center justify-center gap-0.5 select-none"
                                title={`Unassigned. Tap to assign to ${alloc.storeName}.`}
                              >
                                <span className="text-xs font-semibold">{d}</span>
                                <span className="text-[10px] text-slate-300">—</span>
                              </button>
                            );
                          })}
                        </div>
                      </div>

                      {/* SHIFT TIME WINDOW */}
                      <div className="space-y-2">
                        <div className="flex items-center justify-between">
                          <label className="text-[11px] font-bold text-slate-600 dark:text-slate-400 uppercase tracking-wider select-none">
                            SHIFT TIME WINDOW
                          </label>
                          <div className="flex items-center gap-3">
                            {!timeError && durationMin !== null && (
                              <span className="text-xs font-bold text-slate-700 dark:text-slate-300 bg-slate-100 dark:bg-slate-800 px-2.5 py-0.5 rounded-lg border border-slate-200 dark:border-slate-700">
                                {formatDurationText(durationMin)}
                              </span>
                            )}
                            {allocations.length > 1 && (
                              <button
                                type="button"
                                onClick={() => handleApplyTimeToAll(idx)}
                                className="text-xs font-bold text-brand-primary hover:text-brand-secondary transition inline-flex items-center gap-1.5 cursor-pointer hover:underline"
                                title="Apply this shift time to all stores"
                              >
                                <Copy className="w-3.5 h-3.5" />
                                <span>Apply this time to all stores</span>
                              </button>
                            )}
                          </div>
                        </div>

                        <div className="grid grid-cols-2 gap-3.5">
                          <TimeSegmentInput
                            label="Time-in"
                            value={shiftTimes.timeIn}
                            onChange={(val) => handleTimeInChange(idx, val)}
                          />
                          <TimeSegmentInput
                            label="Time-out"
                            value={shiftTimes.timeOut}
                            onChange={(val) => handleTimeOutChange(idx, val)}
                          />
                        </div>

                        {timeError && (
                          <p className="mt-1 text-xs font-semibold text-rose-600 dark:text-rose-400 flex items-center gap-1.5">
                            <AlertTriangle className="w-3.5 h-3.5 shrink-0" />
                            <span>{timeError}</span>
                          </p>
                        )}
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>

          {/* Bottom Note: Read-Only HC Summary */}
          <div className="flex items-center justify-between text-xs text-slate-500 dark:text-slate-400 px-1 pt-1 select-none">
            <span>
              Total Headcount Share: <strong className="text-slate-900 dark:text-slate-100 font-bold">{totalHcShare} HC</strong>
            </span>
            <span>
              {allocations.length} {allocations.length === 1 ? "store allocation" : "store allocations"}
            </span>
          </div>
        </div>

        {/* Strict Roving Policy Overlap Banner (Failsafe) */}
        {hasRovingConflict && (
          <div className="rounded-2xl border border-rose-300 dark:border-rose-900 bg-rose-50/70 dark:bg-rose-950/40 p-3.5 text-xs text-rose-800 dark:text-rose-200 flex items-start gap-2.5">
            <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5 text-rose-600" />
            <div className="space-y-1">
              <p className="font-bold">Strict Roving Policy: Overlapping duty days and shift windows detected.</p>
              <ul className="list-disc list-inside space-y-0.5 text-xs font-medium">
                {rovingOverlapConflicts.map((c, idx) => (
                  <li key={idx}>
                    <span className="font-semibold">{c.storeA}</span> and{" "}
                    <span className="font-semibold">{c.storeB}</span> overlap on{" "}
                    <strong className="underline">{c.days.join(", ")}</strong> ({c.timeA} vs {c.timeB}).
                  </li>
                ))}
              </ul>
            </div>
          </div>
        )}

        {/* Allocation Governance Notice with Lock icon */}
        <div className="rounded-xl border border-slate-200/90 dark:border-slate-800 bg-slate-50/90 dark:bg-slate-900/60 p-3.5 flex items-start gap-2.5 text-xs text-slate-600 dark:text-slate-400">
          <Lock className="w-4 h-4 text-slate-500 shrink-0 mt-0.5" />
          <p className="text-[11.5px] leading-relaxed">
            Store assignments, VCodes, and Headcount (HC) Shares are governed strictly by official Plantilla and Movement approvals. Stores cannot be added or removed here.
          </p>
        </div>
      </form>

      {/* Reset Confirmation Dialog */}
      {isConfirmResetOpen && (
        <Modal
          isOpen={isConfirmResetOpen}
          onClose={() => setIsConfirmResetOpen(false)}
          title="Reset Schedule & Work Terms?"
          subtitle="All duty days, shift time windows, and rest days will be cleared."
          icon={AlertTriangle}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-4">
            <p className="text-xs text-slate-600 dark:text-slate-300 leading-relaxed">
              Are you sure you want to reset the schedule for{" "}
              <strong className="text-slate-900 dark:text-slate-100">{employeeName || "this employee"}</strong>? All
              duty days, shift times, and designated rest days will become blank so you can re-enter
              them easily.
            </p>
            <div className="rounded-xl bg-slate-100 dark:bg-slate-800 p-3 text-xs text-slate-600 dark:text-slate-400 border border-slate-200 dark:border-slate-700">
              ⚠️ <strong>Strict Guardrail:</strong> Store allocations and Headcount (HC) Shares will
              remain locked. The schedule cannot be saved while empty until you assign new duty days,
              shift times, and at least 1 rest day.
            </div>
            <div className="pt-3 border-t border-slate-200 dark:border-slate-800 flex items-center justify-end gap-2.5">
              <button
                type="button"
                onClick={() => setIsConfirmResetOpen(false)}
                className="px-4 py-2 text-xs font-semibold rounded-xl border border-slate-300 dark:border-slate-700 bg-white dark:bg-slate-900 hover:bg-slate-100 text-slate-700 dark:text-slate-300 cursor-pointer transition"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleResetSchedule}
                className="px-4 py-2 text-xs font-bold rounded-xl bg-rose-600 hover:bg-rose-700 text-white cursor-pointer transition flex items-center gap-1.5 shadow-sm"
              >
                <RotateCcw className="w-3.5 h-3.5" />
                <span>Yes, Reset All</span>
              </button>
            </div>
          </div>
        </Modal>
      )}
    </Modal>
  );
}
