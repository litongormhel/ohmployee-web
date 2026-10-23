"use client";

import React, { useState } from "react";
import { Clock, X, Loader2, Check } from "lucide-react";
import { updatePlantillaSchedule } from "@/lib/queries/plantilla";

export interface UpdateScheduleModalProps {
  isOpen: boolean;
  onClose: () => void;
  plantillaId: string;
  employeeNo?: string | null;
  employeeName?: string | null;
  initialScheduleDays?: string | null;
  initialScheduleTime?: string | null;
  initialDayoff?: string | null;
  onSuccess: () => void;
}

const DAYS_OF_WEEK = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"] as const;

const TIME_PRESETS = [
  "08:00 AM - 05:00 PM",
  "09:00 AM - 06:00 PM",
  "07:00 AM - 04:00 PM",
  "FLEXI (4 HRS)",
  "FLEXI (6 HRS)",
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
  onSuccess,
}: UpdateScheduleModalProps) {
  const [scheduleDays, setScheduleDays] = useState<string>(initialScheduleDays ?? "MON-SAT");
  const [scheduleTime, setScheduleTime] = useState<string>(initialScheduleTime ?? "08:00 AM - 05:00 PM");
  const [dayoff, setDayoff] = useState<string>(initialDayoff ?? "SUN");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  if (!isOpen) return null;

  // Day toggle helper
  const toggleDay = (currentStr: string, day: string): string => {
    const parts = currentStr
      .split(/[,-]/)
      .map((d) => d.trim().toUpperCase())
      .filter(Boolean);
    const set = new Set(parts);
    if (set.has(day)) {
      set.delete(day);
    } else {
      set.add(day);
    }
    // Sort by order of week
    const ordered = DAYS_OF_WEEK.filter((d) => set.has(d));
    return ordered.join(",");
  };

  const isDaySelected = (currentStr: string, day: string): boolean => {
    if (currentStr === "MON-SAT") return day !== "SUN";
    if (currentStr === "MON-FRI") return day !== "SAT" && day !== "SUN";
    if (currentStr === "SAT-SUN") return day === "SAT" || day === "SUN";
    const parts = currentStr.split(/[,-]/).map((d) => d.trim().toUpperCase());
    return parts.includes(day);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      await updatePlantillaSchedule({
        plantillaId,
        employeeNo,
        scheduleDays: scheduleDays.trim() || null,
        scheduleTime: scheduleTime.trim() || null,
        dayoff: dayoff.trim() || null,
      });
      onSuccess();
      onClose();
    } catch (err) {
      setErrorMessage(err instanceof Error ? err.message : "Failed to update schedule.");
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="relative w-full max-w-md rounded-2xl border border-border-subtle bg-surface p-6 shadow-xl animate-in fade-in zoom-in-95 duration-150">
        <button
          onClick={onClose}
          className="absolute right-4 top-4 text-text-muted hover:text-text-primary"
        >
          <X className="h-4 w-4" />
        </button>

        <div className="flex items-center gap-2 mb-4">
          <Clock className="h-5 w-5 text-purple-600" />
          <h3 className="text-sm font-bold text-text-primary">
            Edit Ops Schedule & Dayoff
          </h3>
        </div>

        {employeeName && (
          <p className="text-2xs text-text-secondary mb-4 pb-3 border-b border-border-subtle">
            Configuring store visit and duty hours for{" "}
            <span className="font-semibold text-text-primary">{employeeName}</span>
            {employeeNo && <span className="font-mono text-purple-700 ml-1">({employeeNo})</span>}
          </p>
        )}

        {errorMessage && (
          <div className="mb-4 rounded-lg bg-rose-50 border border-rose-200 p-3 text-xs text-rose-700">
            {errorMessage}
          </div>
        )}

        <form onSubmit={handleSave} className="space-y-4">
          {/* SCHEDULE_DAYS */}
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <label className="text-2xs font-bold uppercase tracking-wider text-text-secondary">
                Schedule Days
              </label>
              <div className="flex items-center gap-1">
                <button
                  type="button"
                  onClick={() => setScheduleDays("MON-FRI")}
                  className="px-1.5 py-0.5 rounded text-3xs font-semibold bg-surface-subtle border border-border-subtle text-text-secondary hover:text-text-primary"
                >
                  MON-FRI
                </button>
                <button
                  type="button"
                  onClick={() => setScheduleDays("MON-SAT")}
                  className="px-1.5 py-0.5 rounded text-3xs font-semibold bg-surface-subtle border border-border-subtle text-text-secondary hover:text-text-primary"
                >
                  MON-SAT
                </button>
              </div>
            </div>

            <div className="grid grid-cols-7 gap-1 mb-2">
              {DAYS_OF_WEEK.map((d) => {
                const selected = isDaySelected(scheduleDays, d);
                return (
                  <button
                    key={d}
                    type="button"
                    onClick={() => setScheduleDays(toggleDay(scheduleDays, d))}
                    className={`py-1.5 text-3xs font-bold rounded-lg border transition ${
                      selected
                        ? "bg-purple-600 text-white border-purple-600 shadow-xs"
                        : "bg-surface border-border-subtle text-text-muted hover:border-border-default"
                    }`}
                  >
                    {d}
                  </button>
                );
              })}
            </div>
            <input
              type="text"
              value={scheduleDays}
              onChange={(e) => setScheduleDays(e.target.value)}
              placeholder="e.g. MON-SAT, MON-FRI, MON,WED,FRI"
              className="w-full h-8 rounded-lg border border-border-subtle bg-surface px-2.5 text-xs text-text-primary focus:outline-hidden"
            />
          </div>

          {/* SCHEDULE_TIME */}
          <div>
            <label className="block text-2xs font-bold uppercase tracking-wider text-text-secondary mb-1.5">
              Schedule Time / Flexi Visit Window
            </label>
            <div className="flex flex-wrap gap-1 mb-2">
              {TIME_PRESETS.map((preset) => (
                <button
                  key={preset}
                  type="button"
                  onClick={() => setScheduleTime(preset)}
                  className={`px-2 py-0.5 rounded-md text-3xs font-medium border transition ${
                    scheduleTime === preset
                      ? "bg-purple-100 text-purple-800 border-purple-300 font-semibold"
                      : "bg-surface-subtle border-border-subtle text-text-secondary hover:text-text-primary"
                  }`}
                >
                  {preset}
                </button>
              ))}
            </div>
            <input
              type="text"
              value={scheduleTime}
              onChange={(e) => setScheduleTime(e.target.value)}
              placeholder="e.g. 08:00 AM - 05:00 PM or FLEXI (4 HRS)"
              className="w-full h-8 rounded-lg border border-border-subtle bg-surface px-2.5 text-xs text-text-primary focus:outline-hidden"
            />
          </div>

          {/* DAYOFF */}
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <label className="text-2xs font-bold uppercase tracking-wider text-text-secondary">
                Dayoff
              </label>
              <div className="flex items-center gap-1">
                <button
                  type="button"
                  onClick={() => setDayoff("SUN")}
                  className="px-1.5 py-0.5 rounded text-3xs font-semibold bg-surface-subtle border border-border-subtle text-text-secondary hover:text-text-primary"
                >
                  SUN
                </button>
                <button
                  type="button"
                  onClick={() => setDayoff("SAT-SUN")}
                  className="px-1.5 py-0.5 rounded text-3xs font-semibold bg-surface-subtle border border-border-subtle text-text-secondary hover:text-text-primary"
                >
                  SAT-SUN
                </button>
              </div>
            </div>

            <div className="grid grid-cols-7 gap-1 mb-2">
              {DAYS_OF_WEEK.map((d) => {
                const selected = isDaySelected(dayoff, d);
                return (
                  <button
                    key={d}
                    type="button"
                    onClick={() => setDayoff(toggleDay(dayoff, d))}
                    className={`py-1.5 text-3xs font-bold rounded-lg border transition ${
                      selected
                        ? "bg-amber-600 text-white border-amber-600 shadow-xs"
                        : "bg-surface border-border-subtle text-text-muted hover:border-border-default"
                    }`}
                  >
                    {d}
                  </button>
                );
              })}
            </div>
            <input
              type="text"
              value={dayoff}
              onChange={(e) => setDayoff(e.target.value)}
              placeholder="e.g. SUN, SAT-SUN, MON"
              className="w-full h-8 rounded-lg border border-border-subtle bg-surface px-2.5 text-xs text-text-primary focus:outline-hidden"
            />
          </div>

          <div className="flex items-center justify-end gap-2 pt-3 border-t border-border-subtle">
            <button
              type="button"
              onClick={onClose}
              disabled={isSubmitting}
              className="px-3.5 py-1.5 rounded-lg border border-border-subtle bg-surface text-xs font-semibold text-text-secondary hover:bg-surface-hover transition disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting}
              className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-lg bg-purple-600 text-xs font-semibold text-white hover:bg-purple-700 shadow-xs transition disabled:opacity-50"
            >
              {isSubmitting ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" /> Saving...
                </>
              ) : (
                <>
                  <Check className="h-3.5 w-3.5" /> Save Schedule
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
