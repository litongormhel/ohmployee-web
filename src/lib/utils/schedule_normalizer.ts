/**
 * Schedule Days & Dayoff Normalization Utility (ADR-002 Addendum R4)
 *
 * Expands shorthand day ranges (linear ranges, wrap-around ranges, hybrid lists)
 * into canonical 3-letter day codes strictly ordered MON to SUN, serializes to
 * comma-separated PostgreSQL text format, and resolves duty/rest-day overlap.
 */

export const DAYS_OF_WEEK = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"] as const;
export type DayCode = (typeof DAYS_OF_WEEK)[number];

export const DAY_ALIAS_MAP: Record<string, DayCode> = {
  MON: "MON",
  MONDAY: "MON",
  TUE: "TUE",
  TUES: "TUE",
  TUESDAY: "TUE",
  WED: "WED",
  WEDNESDAY: "WED",
  THU: "THU",
  THUR: "THU",
  THURS: "THU",
  THURSDAY: "THU",
  FRI: "FRI",
  FRIDAY: "FRI",
  SAT: "SAT",
  SATURDAY: "SAT",
  SUN: "SUN",
  SUNDAY: "SUN",
};

/**
 * Expands a schedule days or dayoff string into discrete DayCodes, strictly ordered MON to SUN.
 * Supports:
 * - Linear ranges: "MON-SAT", "MON-FRI", "THU-SAT", "TUE-SAT"
 * - Wrap-around ranges: "SAT-TUE" -> MON, TUE, SAT, SUN
 * - Hybrid lists: "MON-WED,FRI", "MON-WED; FRI"
 * - Discrete lists: "MON, WED, FRI", "SAT, SUN"
 *
 * @throws Error if any token or range boundary is unrecognized.
 */
export function expandScheduleDays(raw?: string | null): { days: DayCode[]; formatted: string } {
  if (!raw || !raw.trim()) {
    return { days: [], formatted: "" };
  }

  const cleaned = raw
    .toUpperCase()
    .trim()
    .replace(/\./g, "")
    .replace(/\s*-\s*/g, "-");
  // Split on commas, semicolons, slashes, ampersands, or whitespace, but keep hyphens for ranges
  const tokens = cleaned
    .split(/[,;/&\s]+/)
    .map((t) => t.trim())
    .filter(Boolean);

  const daySet = new Set<DayCode>();

  for (const token of tokens) {
    const rangeMatch = token.match(/^([A-Z]+)\s*-\s*([A-Z]+)$/);
    if (rangeMatch) {
      const startAlias = rangeMatch[1];
      const endAlias = rangeMatch[2];
      const start = DAY_ALIAS_MAP[startAlias];
      const end = DAY_ALIAS_MAP[endAlias];

      if (!start || !end) {
        throw new Error(
          `Invalid schedule day range: "${token}". Unrecognized day token (${!start ? startAlias : endAlias}).`
        );
      }

      const sIdx = DAYS_OF_WEEK.indexOf(start);
      const eIdx = DAYS_OF_WEEK.indexOf(end);

      if (sIdx <= eIdx) {
        // Standard linear range (e.g. MON-SAT)
        for (let i = sIdx; i <= eIdx; i++) {
          daySet.add(DAYS_OF_WEEK[i]);
        }
      } else {
        // Wrap-around range (e.g. SAT-TUE)
        for (let i = sIdx; i < DAYS_OF_WEEK.length; i++) {
          daySet.add(DAYS_OF_WEEK[i]);
        }
        for (let i = 0; i <= eIdx; i++) {
          daySet.add(DAYS_OF_WEEK[i]);
        }
      }
    } else {
      const day = DAY_ALIAS_MAP[token];
      if (!day) {
        throw new Error(
          `Invalid schedule day token: "${token}". Expected 3-letter day code (MON-SUN).`
        );
      }
      daySet.add(day);
    }
  }

  // Strictly order MON to SUN
  const ordered = DAYS_OF_WEEK.filter((d) => daySet.has(d));
  return {
    days: ordered,
    formatted: ordered.join(", "),
  };
}

export interface ResolveDutyAndRestDaysResult {
  scheduleDays: string;
  dayoff: string;
  dutyDays: DayCode[];
  restDays: DayCode[];
  conflictRemoved: DayCode[];
  error?: string;
}

/**
 * Resolves SCHEDULE_DAYS and DAYOFF by expanding ranges, ordering canonically MON-SUN,
 * and carving out designated rest days from duty days to eliminate mutually exclusive
 * pill conflict states in the Web UI modal.
 */
export function resolveDutyAndRestDays(
  scheduleDaysRaw?: string | null,
  dayoffRaw?: string | null
): ResolveDutyAndRestDaysResult {
  let expandedDuty: { days: DayCode[]; formatted: string } = { days: [], formatted: "" };
  let expandedRest: { days: DayCode[]; formatted: string } = { days: [], formatted: "" };
  let error: string | undefined;

  try {
    expandedDuty = expandScheduleDays(scheduleDaysRaw);
  } catch (err) {
    error = err instanceof Error ? err.message : String(err);
  }

  try {
    expandedRest = expandScheduleDays(dayoffRaw);
  } catch (err) {
    if (!error) {
      error = err instanceof Error ? err.message : String(err);
    }
  }

  if (error) {
    return {
      scheduleDays: (scheduleDaysRaw ?? "").trim(),
      dayoff: (dayoffRaw ?? "").trim(),
      dutyDays: expandedDuty.days,
      restDays: expandedRest.days,
      conflictRemoved: [],
      error,
    };
  }

  const restDaySet = new Set(expandedRest.days);
  const conflictRemoved: DayCode[] = [];
  const remainingDutyDays: DayCode[] = [];

  for (const d of expandedDuty.days) {
    if (restDaySet.has(d)) {
      conflictRemoved.push(d);
    } else {
      remainingDutyDays.push(d);
    }
  }

  if (expandedDuty.days.length > 0 && remainingDutyDays.length === 0) {
    return {
      scheduleDays: "",
      dayoff: expandedRest.formatted,
      dutyDays: [],
      restDays: expandedRest.days,
      conflictRemoved,
      error: "Schedule days cannot be entirely comprised of rest days.",
    };
  }

  return {
    scheduleDays: remainingDutyDays.join(", "),
    dayoff: expandedRest.formatted,
    dutyDays: remainingDutyDays,
    restDays: expandedRest.days,
    conflictRemoved,
  };
}
