"use client";

import React, { useState, useMemo } from "react";
import {
  Clock,
  Loader2,
  Calendar,
  Building2,
  AlertTriangle,
  CheckCircle2,
  ShieldAlert,
  RotateCcw,
  ChevronDown,
  ChevronUp,
  Copy,
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
type DayCode = (typeof DAYS_OF_WEEK)[number];

const CIRCLED_NUMBERS = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"];

function parseDayoffString(raw?: string | null): DayCode[] {
  if (!raw || !raw.trim()) return ["SUN"];
  const dayMap: Record<string, DayCode> = {
    MONDAY: "MON", MON: "MON",
    TUESDAY: "TUE", TUE: "TUE",
    WEDNESDAY: "WED", WED: "WED",
    THURSDAY: "THU", THU: "THU",
    FRIDAY: "FRI", FRI: "FRI",
    SATURDAY: "SAT", SAT: "SAT",
    SUNDAY: "SUN", SUN: "SUN",
  };
  const parts = raw.toUpperCase().split(/[,/&\s-]+/).map((p) => p.trim()).filter(Boolean);
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
    <fieldset className="rounded-xl border border-border-default px-3 pt-0.5 pb-2 focus-within:border-brand-primary focus-within:ring-1 focus-within:ring-brand-primary transition bg-surface">
      <legend className="px-1 text-[11px] font-medium text-text-secondary select-none">
        {label}
      </legend>
      <div className="flex items-center justify-between gap-1.5 mt-0.5">
        <div className="flex items-center gap-1 font-mono text-sm font-semibold text-text-primary">
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
            className="w-6 text-center bg-transparent focus:outline-none focus:bg-brand-50/50 dark:focus:bg-brand-950/40 rounded py-0.5 selection:bg-brand-primary selection:text-white"
            aria-label={`${label} Hours`}
          />
          <span className="text-text-muted select-none font-bold">:</span>
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
            className="w-6 text-center bg-transparent focus:outline-none focus:bg-brand-50/50 dark:focus:bg-brand-950/40 rounded py-0.5 selection:bg-brand-primary selection:text-white"
            aria-label={`${label} Minutes`}
          />
          <button
            type="button"
            onClick={togglePeriod}
            className="ml-1.5 px-2 py-0.5 text-xs font-bold rounded bg-surface-muted hover:bg-surface-base border border-border-default text-brand-primary transition cursor-pointer select-none"
            title="Click to toggle AM / PM"
          >
            {period}
          </button>
        </div>

        <label className="relative cursor-pointer text-text-muted hover:text-text-primary transition shrink-0 p-1 rounded-md hover:bg-surface-muted">
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
        scheduleDays: (a.scheduleDays && a.scheduleDays.trim()) || (initialScheduleDays && initialScheduleDays.trim()) || "MON-SAT",
        scheduleTime: (a.scheduleTime && a.scheduleTime.trim()) || (initialScheduleTime && initialScheduleTime.trim()) || "08:00 AM - 05:00 PM",
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

  // Render modal footer (Sticky)
  const modalFooter = (
    <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 w-full">
      <div className="flex flex-wrap items-center gap-3">
        <button
          type="button"
          onClick={() => setIsConfirmResetOpen(true)}
          disabled={isSubmitting}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg border border-danger-border bg-danger-bg/40 text-danger-text hover:bg-danger-bg transition cursor-pointer disabled:opacity-50"
          title="Reset all duty days, shift times, and rest days"
        >
          <RotateCcw className="w-3.5 h-3.5" />
          <span>Reset</span>
        </button>

        {/* Footer Status Indicators */}
        <div className="text-xs">
          {hasTimeError ? (
            <span className="text-danger-text font-bold flex items-center gap-1">
              <AlertTriangle className="w-3.5 h-3.5 shrink-0" />
              <span>Time-out must be later than time-in</span>
            </span>
          ) : !isScheduleComplete ? (
            <span className="text-amber-600 dark:text-amber-400 font-semibold flex items-center gap-1">
              <AlertTriangle className="w-3.5 h-3.5 shrink-0" />
              <span>Schedule incomplete (each store requires at least 1 duty day)</span>
            </span>
          ) : hasRovingConflict ? (
            <span className="text-danger-text font-bold flex items-center gap-1">
              <AlertTriangle className="w-3.5 h-3.5 shrink-0" />
              <span>
                Overlap conflict: {rovingOverlapConflicts[0]?.storeA} &amp; {rovingOverlapConflicts[0]?.storeB}
              </span>
            </span>
          ) : hasRestDayConflict ? (
            <span className="text-danger-text font-bold flex items-center gap-1">
              <AlertTriangle className="w-3.5 h-3.5 shrink-0" />
              <span>Rest day conflict on {conflictingDays.join(", ")}</span>
            </span>
          ) : !isHcValid ? (
            <span className="text-danger-text font-bold">
              ⚠️ Sum is {totalHcShare} HC. Must equal 1.00 HC.
            </span>
          ) : (
            <div className="flex flex-wrap items-center gap-2 text-xs">
              <span className="font-bold text-text-primary">
                {totalWeeklyHours} hrs/wk
              </span>
              {unassignedDays.length > 0 ? (
                <span className="text-amber-600 dark:text-amber-400 font-medium flex items-center gap-1">
                  <AlertTriangle className="w-3 h-3 shrink-0" />
                  <span>
                    {unassignedDays.length} {unassignedDays.length === 1 ? "day" : "days"} without a store
                  </span>
                </span>
              ) : (
                <span className="text-emerald-600 dark:text-emerald-400 font-semibold flex items-center gap-1">
                  <CheckCircle2 className="w-3.5 h-3.5 shrink-0" />
                  <span>Ready to save</span>
                </span>
              )}
            </div>
          )}
        </div>
      </div>

      <div className="flex items-center gap-2 self-end sm:self-auto shrink-0">
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
          form="update-schedule-form"
          disabled={
            isSubmitting ||
            hasTimeError ||
            !isScheduleComplete ||
            !isHcValid ||
            hasRovingConflict ||
            hasRestDayConflict
          }
          className="px-4 py-2 text-xs font-bold rounded-lg bg-brand-primary hover:bg-brand-secondary text-white transition shadow-xs cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-1.5"
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
      maxWidthClass="max-w-3xl"
      footer={modalFooter}
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

      <form id="update-schedule-form" onSubmit={handleSave} className="space-y-4">
        {/* COMPACT REST DAY SELECTOR */}
        <div className="flex flex-wrap items-center justify-between gap-2 p-2.5 rounded-xl bg-surface-muted/50 border border-border-default">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs font-bold text-text-primary flex items-center gap-1.5">
              <Calendar className="w-3.5 h-3.5 text-brand-primary shrink-0" />
              <span>Rest Day:</span>
            </span>
            <div className="flex items-center gap-1">
              {DAYS_OF_WEEK.map((d) => {
                const isSelected = selectedDayoffs.includes(d);
                return (
                  <button
                    key={d}
                    type="button"
                    onClick={() => handleToggleDayoff(d)}
                    className={`px-2 py-0.5 text-xs font-bold rounded-md border transition cursor-pointer ${
                      isSelected
                        ? "bg-brand-primary text-white border-brand-primary shadow-2xs"
                        : "bg-surface border-border-default text-text-secondary hover:text-text-primary hover:bg-surface-muted"
                    }`}
                  >
                    {d}
                  </button>
                );
              })}
            </div>
          </div>
          <span className="text-2xs font-medium text-text-muted">
            {selectedDayoffs.length} {selectedDayoffs.length === 1 ? "Rest Day" : "Rest Days"}
          </span>
        </div>

        {/* REST DAY CHANGE NOTICE BANNER */}
        {restDayNotice && (
          <div className="rounded-xl bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800 p-2.5 text-xs text-amber-800 dark:text-amber-200 flex items-center justify-between animate-fade-in">
            <div className="flex items-center gap-1.5 font-medium">
              <AlertTriangle className="w-3.5 h-3.5 shrink-0 text-amber-600 dark:text-amber-400" />
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

        {/* WEEKLY COVERAGE STRIP (MON–SUN) */}
        <div className="space-y-1.5">
          <div className="flex items-center justify-between px-0.5">
            <span className="text-2xs font-bold text-text-secondary uppercase tracking-wider">
              WEEKLY COVERAGE PREVIEW
            </span>
            <span className="text-2xs text-text-muted">Live sync</span>
          </div>

          <div className="grid grid-cols-7 gap-1.5">
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
                    className="rounded-lg border border-border-default bg-surface-muted/60 p-2 text-center flex flex-col items-center justify-center min-h-[64px]"
                  >
                    <span className="text-2xs font-bold text-text-secondary mb-1">{day}</span>
                    <span className="px-1.5 py-0.5 rounded text-[10px] font-bold bg-surface border border-border-subtle text-text-muted">
                      Rest
                    </span>
                  </div>
                );
              }

              if (assignedStore) {
                const circled = CIRCLED_NUMBERS[assignedStoreIdx] || String(assignedStoreIdx + 1);
                const timeFormatted = formatShortTime(assignedStore.scheduleTime);
                return (
                  <div
                    key={day}
                    className="rounded-lg border border-brand-200 dark:border-brand-800 bg-brand-50/50 dark:bg-brand-950/30 p-2 text-center flex flex-col items-center justify-between min-h-[64px]"
                    title={`${day}: ${assignedStore.storeName} (${assignedStore.scheduleTime})`}
                  >
                    <div className="flex items-center gap-1 justify-center w-full">
                      <span className="text-2xs font-extrabold text-brand-700 dark:text-brand-300">{day}</span>
                      <span className="text-xs font-bold text-brand-primary">{circled}</span>
                    </div>
                    <p className="text-[10px] font-bold text-text-primary truncate w-full px-0.5">
                      {assignedStore.storeName}
                    </p>
                    <p className="text-[9px] font-medium text-text-muted truncate w-full">
                      {timeFormatted || "8 AM–5 PM"}
                    </p>
                  </div>
                );
              }

              // Unassigned day
              return (
                <div
                  key={day}
                  className="rounded-lg border border-dashed border-amber-300 dark:border-amber-700/60 bg-amber-50/40 dark:bg-amber-950/20 p-2 text-center flex flex-col items-center justify-center min-h-[64px]"
                  title={`${day}: No store assigned`}
                >
                  <span className="text-2xs font-bold text-amber-700 dark:text-amber-400 mb-1">{day}</span>
                  <span className="text-[10px] font-semibold text-amber-700 dark:text-amber-300 flex items-center gap-0.5">
                    <AlertTriangle className="w-2.5 h-2.5 shrink-0" />
                    <span>No store</span>
                  </span>
                </div>
              );
            })}
          </div>
        </div>

        {/* COLLAPSIBLE STORE CARDS (ACCORDION) */}
        <div className="space-y-2.5 pt-1">
          <div className="flex items-center justify-between">
            <h4 className="text-xs font-bold text-text-primary flex items-center gap-1.5">
              <Building2 className="w-3.5 h-3.5 text-brand-primary" />
              <span>Assigned Stores & Shift Windows</span>
            </h4>
            <span className="text-2xs text-text-muted">
              Click header to expand or collapse
            </span>
          </div>

          <div className="space-y-2">
            {allocations.map((alloc, idx) => {
              const isExpanded = expandedStoreIdx === idx;
              const circled = CIRCLED_NUMBERS[idx] || String(idx + 1);
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
                  className={`rounded-xl border transition overflow-hidden bg-surface ${
                    isExpanded
                      ? "border-brand-primary/50 shadow-xs ring-1 ring-brand-primary/20"
                      : "border-border-default hover:border-border-strong shadow-2xs"
                  }`}
                >
                  {/* Card Header (Accordion Toggle) */}
                  <button
                    type="button"
                    onClick={() => {
                      dismissNotice();
                      setExpandedStoreIdx((prev) => (prev === idx ? null : idx));
                    }}
                    className="w-full text-left p-3 flex items-center justify-between gap-3 cursor-pointer bg-surface hover:bg-surface-muted/40 transition"
                  >
                    <div className="flex flex-wrap items-center gap-1.5 text-xs text-text-secondary min-w-0">
                      <span className="font-bold text-sm text-brand-primary shrink-0">
                        {circled}
                      </span>
                      <span className="font-bold text-text-primary truncate max-w-[180px]">
                        {alloc.storeName}
                      </span>
                      {alloc.vcode && (
                        <>
                          <span className="text-text-muted">·</span>
                          <span className="font-mono text-2xs font-semibold px-1.5 py-0.5 rounded bg-surface-muted border border-border-subtle text-text-secondary shrink-0">
                            {alloc.vcode}
                          </span>
                        </>
                      )}
                      <span className="text-text-muted">·</span>
                      <span className="font-medium text-text-secondary shrink-0">
                        {formattedDays}
                      </span>
                      <span className="text-text-muted">·</span>
                      <span className="font-medium text-text-secondary shrink-0">
                        {timeFormatted}
                      </span>
                      <span className="text-text-muted">·</span>
                      <span className="text-2xs text-text-muted font-normal shrink-0">
                        {hcFraction} HC
                      </span>
                    </div>

                    <div className="shrink-0 text-text-muted hover:text-text-primary">
                      {isExpanded ? (
                        <ChevronUp className="w-4 h-4" />
                      ) : (
                        <ChevronDown className="w-4 h-4" />
                      )}
                    </div>
                  </button>

                  {/* Expanded Card Content */}
                  {isExpanded && (
                    <div className="p-4 pt-2 border-t border-border-subtle bg-surface-card/30 space-y-4">
                      {/* Read-Only HC Share Subtitle */}
                      <div className="flex items-center justify-between text-2xs text-text-muted pb-1 border-b border-border-subtle/50">
                        <span>Duty days and shift hours for {alloc.storeName}</span>
                        <span className="font-normal text-text-muted">
                          HC Share: {hcFraction} ({alloc.allocationPercent}%)
                        </span>
                      </div>

                      {/* Cross-Store Aware Duty Days Selector */}
                      <div>
                        <div className="flex items-center justify-between mb-1.5">
                          <label className="text-2xs font-bold text-text-secondary uppercase tracking-wider">
                            DUTY DAYS
                          </label>
                          <span className="text-2xs text-text-muted">
                            {currentDaySet.size} {currentDaySet.size === 1 ? "day assigned" : "days assigned"}
                          </span>
                        </div>

                        <div className="grid grid-cols-7 gap-1.5">
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
                                  className="py-1.5 px-1 text-xs font-medium rounded-lg border border-dashed border-border-subtle bg-surface-muted/40 text-text-muted/50 cursor-not-allowed text-center flex flex-col items-center justify-center"
                                  title={`${d} is marked as rest day`}
                                >
                                  <span>{d}</span>
                                  <span className="text-[9px] text-text-muted/60 leading-none mt-0.5">Rest</span>
                                </button>
                              );
                            }

                            if (isCurrentStore) {
                              return (
                                <button
                                  key={d}
                                  type="button"
                                  onClick={() => handleDayChipClick(idx, d)}
                                  className="py-1.5 px-1 text-xs font-bold rounded-lg border border-brand-primary bg-brand-primary text-white shadow-2xs hover:bg-brand-secondary transition cursor-pointer text-center flex flex-col items-center justify-center"
                                  title={`Assigned to ${alloc.storeName}. Click to remove.`}
                                >
                                  <span>{d}</span>
                                  <span className="text-[9px] text-white/80 leading-none mt-0.5">Active</span>
                                </button>
                              );
                            }

                            if (otherStoreIdx !== -1) {
                              return (
                                <button
                                  key={d}
                                  type="button"
                                  onClick={() => handleDayChipClick(idx, d)}
                                  className="py-1.5 px-1 text-xs font-semibold rounded-lg border border-border-default bg-surface-muted/70 text-text-muted hover:text-brand-primary hover:border-brand-primary/50 hover:bg-brand-50/40 transition cursor-pointer text-center flex flex-col items-center justify-center"
                                  title={`Currently assigned to Store ${otherStoreIdx + 1} (${allocations[otherStoreIdx].storeName}). Tap to move here.`}
                                >
                                  <span>{d}</span>
                                  <span className="text-[9px] text-brand-600 dark:text-brand-400 font-bold leading-none mt-0.5">
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
                                className="py-1.5 px-1 text-xs font-semibold rounded-lg border border-border-default bg-surface text-text-secondary hover:text-text-primary hover:bg-surface-muted hover:border-border-strong transition cursor-pointer text-center flex flex-col items-center justify-center"
                                title={`Unassigned. Tap to assign to ${alloc.storeName}.`}
                              >
                                <span>{d}</span>
                                <span className="text-[9px] text-text-muted/50 leading-none mt-0.5">—</span>
                              </button>
                            );
                          })}
                        </div>
                      </div>

                      {/* Shift Time Window */}
                      <div>
                        <div className="flex items-center justify-between mb-1.5">
                          <label className="text-2xs font-bold text-text-secondary uppercase tracking-wider">
                            SHIFT TIME WINDOW
                          </label>
                          <div className="flex items-center gap-3">
                            {!timeError && durationMin !== null && (
                              <span className="text-2xs font-semibold text-text-secondary">
                                {formatDurationText(durationMin)}
                              </span>
                            )}
                            {allocations.length > 1 && (
                              <button
                                type="button"
                                onClick={() => handleApplyTimeToAll(idx)}
                                className="text-2xs font-bold text-brand-primary hover:text-brand-secondary transition inline-flex items-center gap-1 cursor-pointer"
                                title="Apply this shift time to all stores"
                              >
                                <Copy className="w-3 h-3" />
                                <span>Apply this time to all stores</span>
                              </button>
                            )}
                          </div>
                        </div>

                        <div className="grid grid-cols-2 gap-3">
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
                          <p className="mt-1.5 text-2xs font-semibold text-danger-text flex items-center gap-1">
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
          <div className="flex items-center justify-between text-2xs text-text-muted px-1 pt-0.5">
            <span>
              Total Headcount Share: <strong className="text-text-primary">{totalHcShare} HC</strong>
            </span>
            <span>
              {allocations.length} {allocations.length === 1 ? "store allocation" : "store allocations"}
            </span>
          </div>
        </div>

        {/* Strict Roving Policy Overlap Banner (Failsafe) */}
        {hasRovingConflict && (
          <div className="rounded-xl border border-danger-border bg-danger-bg/40 p-3 text-xs text-danger-text flex items-start gap-2.5">
            <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" />
            <div className="space-y-1">
              <p className="font-bold">Strict Roving Policy: Overlapping duty days and shift windows detected.</p>
              <ul className="list-disc list-inside space-y-0.5 text-2xs font-medium">
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

        {/* Allocation Governance Notice */}
        <div className="rounded-xl border border-border-subtle bg-surface-muted/40 p-3 flex items-start gap-2.5 text-xs text-text-secondary">
          <ShieldAlert className="w-4 h-4 text-brand-primary shrink-0 mt-0.5" />
          <p className="text-[11px] leading-relaxed">
            Store assignments, VCodes, and Headcount (HC) Shares are governed strictly by official Plantilla and Movement approvals. Store allocations cannot be added or deleted from this schedule window.
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
            <p className="text-xs text-text-secondary leading-relaxed">
              Are you sure you want to reset the schedule for{" "}
              <strong className="text-text-primary">{employeeName || "this employee"}</strong>? All
              duty days, shift times, and designated rest days will become blank so you can re-enter
              them easily.
            </p>
            <div className="rounded-lg bg-surface-muted p-2.5 text-2xs text-text-muted border border-border-subtle">
              ⚠️ <strong>Strict Guardrail:</strong> Store allocations and Headcount (HC) Shares will
              remain locked. The schedule cannot be saved while empty until you assign new duty days,
              shift times, and at least 1 rest day.
            </div>
            <div className="pt-3 border-t border-border-default flex items-center justify-end gap-2">
              <button
                type="button"
                onClick={() => setIsConfirmResetOpen(false)}
                className="px-3.5 py-1.5 text-xs font-semibold rounded-lg border border-border-default bg-surface hover:bg-surface-muted text-text-secondary hover:text-text-primary cursor-pointer transition"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleResetSchedule}
                className="px-3.5 py-1.5 text-xs font-bold rounded-lg bg-danger-bg text-danger-text border border-danger-border hover:bg-danger-bg/80 cursor-pointer transition flex items-center gap-1.5"
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
