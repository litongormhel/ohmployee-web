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
    return { timeIn: parts[0] || "", timeOut: parts[1] || "" };
  }
  return { timeIn: raw, timeOut: "" };
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
        scheduleDays: a.scheduleDays ?? initialScheduleDays ?? "MON-SAT",
        scheduleTime: a.scheduleTime ?? initialScheduleTime ?? "08:00 AM - 05:00 PM",
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
        scheduleDays: initialScheduleDays ?? "MON-SAT",
        scheduleTime: initialScheduleTime ?? "08:00 AM - 05:00 PM",
        allocationPercent: 100,
      },
    ];
  }, [initialStoreAllocations, initialScheduleDays, initialScheduleTime]);

  const [allocations, setAllocations] = useState<StoreAllocationItem[]>(defaultAllocations);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isConfirmResetOpen, setIsConfirmResetOpen] = useState(false);

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
      const time = (a.scheduleTime || "").trim();
      if (!days) return false;
      if (!time || time.includes("--") || time === "-") return false;
      const parts = time.split("-").map((p) => p.trim());
      if (parts.length < 2 || !parts[0] || !parts[1]) return false;
      return true;
    });
  }, [selectedDayoffs, allocations]);

  const isRoving = allocations.length > 1;

  // Total HC calculation & validation
  const totalPercent = useMemo(() => {
    return allocations.reduce(
      (sum, item) => sum + (Number(item.allocationPercent) || 0),
      0
    );
  }, [allocations]);

  const totalHcShare = (totalPercent / 100).toFixed(2);
  const isHcValid = Math.abs(totalPercent - 100) <= 1 || allocations.length === 1;

  // Toggle multi-select rest days
  const handleToggleDayoff = (day: DayCode) => {
    setSelectedDayoffs((prev) => {
      if (prev.includes(day)) {
        if (prev.length === 1) return prev; // Keep at least 1 rest day
        return prev.filter((d) => d !== day);
      }
      return [...prev, day];
    });
  };

  // Check if any allocation day conflicts with rest days
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

  // Toggle single duty day for a store
  const toggleStoreDay = (index: number, day: string) => {
    const alloc = allocations[index];
    const daySet = parseDaysToSet(alloc.scheduleDays);
    if (daySet.has(day)) {
      daySet.delete(day);
    } else {
      daySet.add(day);
    }
    updateAllocation(index, { scheduleDays: formatDaysFromSet(daySet) });
  };

  const handleTimeInChange = (idx: number, newTimeIn: string) => {
    const current = parseShiftWindow(allocations[idx]?.scheduleTime);
    const updated =
      newTimeIn && current.timeOut
        ? `${newTimeIn} - ${current.timeOut}`
        : newTimeIn || current.timeOut;
    updateAllocation(idx, { scheduleTime: updated });
  };

  const handleTimeOutChange = (idx: number, newTimeOut: string) => {
    const current = parseShiftWindow(allocations[idx]?.scheduleTime);
    const updated =
      current.timeIn && newTimeOut
        ? `${current.timeIn} - ${newTimeOut}`
        : current.timeIn || newTimeOut;
    updateAllocation(idx, { scheduleTime: updated });
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
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
        scheduleTime: a.scheduleTime,
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

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Edit Schedule & Work Terms"
      subtitle={
        employeeName ? (
          <span className="text-text-secondary text-xs">
            Configuring rest days, per-store duty days, and shift time windows for{" "}
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
        {/* SECTION 1: GLOBAL WORK TERMS & REST DAYS */}
        <div className="p-4 rounded-xl bg-surface-muted/50 border border-border-default space-y-4">
          <div className="flex items-center justify-between">
            <h4 className="text-xs font-bold text-text-primary flex items-center gap-1.5">
              <Calendar className="w-3.5 h-3.5 text-brand-primary" />
              <span>Designated Rest Days (Day Off)</span>
            </h4>
            <span className="text-2xs font-semibold px-2 py-0.5 rounded-full bg-surface border border-border-default text-text-secondary">
              {selectedDayoffs.length} {selectedDayoffs.length === 1 ? "Rest Day" : "Rest Days"} Selected
            </span>
          </div>

          {/* Multi-Select Rest Day Pills */}
          <div>
            <div className="grid grid-cols-7 gap-1.5">
              {DAYS_OF_WEEK.map((d) => {
                const isSelected = selectedDayoffs.includes(d);
                return (
                  <button
                    key={d}
                    type="button"
                    onClick={() => handleToggleDayoff(d)}
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
            {conflictingDays.length > 0 && (
              <p className="mt-2 text-[11px] text-amber-600 dark:text-amber-400 font-medium flex items-center gap-1">
                <AlertTriangle className="w-3.5 h-3.5 shrink-0" />
                <span>
                  Notice: Store duty schedules include {conflictingDays.join(", ")}, which is marked as a designated rest day.
                </span>
              </p>
            )}
          </div>
        </div>

        {/* SECTION 2: PER-STORE SCHEDULE & DUTY HOURS */}
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <div>
              <h4 className="text-xs font-bold text-text-primary flex items-center gap-1.5">
                <Building2 className="w-3.5 h-3.5 text-brand-primary" />
                <span>Store Deployments & Shift Time Windows</span>
              </h4>
              <p className="text-[11px] text-text-secondary mt-0.5">
                {isRoving
                  ? "Roving personnel: Configure duty days and shift hours for each assigned store."
                  : "Stationary personnel: Standard 8-hour shift and duty days schedule."}
              </p>
            </div>
          </div>

          {/* Store Deployment Cards */}
          <div className="space-y-3">
            {allocations.map((alloc, idx) => {
              const currentDaySet = parseDaysToSet(alloc.scheduleDays);
              const hcFraction = (alloc.allocationPercent / 100).toFixed(2);
              const shiftTimes = parseShiftWindow(alloc.scheduleTime);

              return (
                <div
                  key={idx}
                  className="p-4 rounded-xl border border-border-default bg-surface shadow-2xs space-y-3.5"
                >
                  {/* Card Header: Locked Store Identity & HC Share */}
                  <div className="flex flex-wrap items-center justify-between gap-2 pb-2.5 border-b border-border-subtle">
                    <div className="flex items-center gap-2 min-w-0">
                      <span className="w-5 h-5 rounded-full bg-brand-50 text-brand-700 font-bold text-[11px] flex items-center justify-center shrink-0 border border-brand-200 dark:bg-brand-950/40 dark:border-brand-800 dark:text-brand-300">
                        {idx + 1}
                      </span>
                      <h5 className="text-xs font-bold text-text-primary truncate">
                        {alloc.storeName}
                      </h5>
                      {alloc.vcode && (
                        <span className="font-mono text-[11px] font-bold text-brand-primary bg-brand-50 dark:bg-brand-950/40 border border-brand-200 dark:border-brand-800 px-2 py-0.2 rounded">
                          {alloc.vcode}
                        </span>
                      )}
                    </div>

                    <div className="flex items-center gap-2 shrink-0">
                      <span className="text-[11px] font-medium text-text-muted">HC Share:</span>
                      <span className="font-mono text-xs font-bold text-brand-primary bg-surface-muted border border-border-default px-2 py-0.5 rounded-md">
                        {hcFraction} HC ({alloc.allocationPercent}%)
                      </span>
                    </div>
                  </div>

                  {/* Duty Days Selector */}
                  <div>
                    <label className="block text-2xs font-bold text-text-secondary mb-1.5">
                      DUTY DAYS
                    </label>

                    {/* Day Pill Toggles */}
                    <div className="grid grid-cols-7 gap-1">
                      {DAYS_OF_WEEK.map((d) => {
                        const isDayActive = currentDaySet.has(d);
                        const isRestDay = selectedDayoffs.includes(d);
                        return (
                          <button
                            key={d}
                            type="button"
                            onClick={() => toggleStoreDay(idx, d)}
                            className={`py-1 text-[11px] font-bold rounded border transition cursor-pointer text-center ${
                              isDayActive
                                ? "bg-brand-50 border-brand-primary text-brand-700 dark:bg-brand-950/50 dark:text-brand-300 shadow-2xs font-extrabold"
                                : isRestDay
                                ? "bg-surface-muted/40 border-border-subtle text-text-muted/60"
                                : "bg-surface border-border-default text-text-secondary hover:text-text-primary hover:bg-surface-muted"
                            }`}
                            title={isRestDay ? `${d} is marked as rest day` : undefined}
                          >
                            {d}
                          </button>
                        );
                      })}
                    </div>
                  </div>

                  {/* Shift Time Window (Time-in & Time-out) */}
                  <div>
                    <label className="block text-2xs font-bold text-text-secondary mb-1.5">
                      SHIFT TIME WINDOW
                    </label>
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
                  </div>
                </div>
              );
            })}
          </div>

          {/* Allocation Governance Notice */}
          <div className="rounded-xl border border-border-subtle bg-surface-muted/40 p-3 flex items-start gap-2.5 text-xs text-text-secondary">
            <ShieldAlert className="w-4 h-4 text-brand-primary shrink-0 mt-0.5" />
            <p className="text-[11px] leading-relaxed">
              Store assignments, VCodes, and Headcount (HC) Shares are governed strictly by official Plantilla and Movement approvals. Store allocations cannot be added or deleted from this schedule window.
            </p>
          </div>
        </div>

        {/* Modal Actions Footer */}
        <div className="pt-4 border-t border-border-default flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div className="flex flex-wrap items-center gap-3">
            <button
              type="button"
              onClick={() => setIsConfirmResetOpen(true)}
              disabled={isSubmitting}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg border border-danger-border bg-danger-bg/40 text-danger-text hover:bg-danger-bg transition cursor-pointer disabled:opacity-50"
              title="Reset all duty days, shift times, and rest days"
            >
              <RotateCcw className="w-3.5 h-3.5" />
              <span>Reset Schedule</span>
            </button>

            <div className="text-xs">
              {!isScheduleComplete ? (
                <span className="text-amber-600 dark:text-amber-400 font-semibold flex items-center gap-1">
                  <AlertTriangle className="w-3.5 h-3.5" />
                  <span>Schedule incomplete (cannot be saved while blank)</span>
                </span>
              ) : !isHcValid ? (
                <span className="text-danger-text font-bold">
                  ⚠️ Sum is {totalHcShare} HC. Must equal 1.00 HC.
                </span>
              ) : (
                <span className="text-emerald-600 dark:text-emerald-400 font-semibold flex items-center gap-1">
                  <CheckCircle2 className="w-3.5 h-3.5" />
                  <span>Schedule terms ready to save</span>
                </span>
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
              disabled={isSubmitting || !isScheduleComplete || !isHcValid}
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
