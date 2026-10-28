/**
 * src/lib/utils/displayText.ts
 *
 * Render-layer display casing formatter.
 * Formats names, positions, accounts, and stores into Title Case per word
 * while strictly preserving:
 * - Authoritative uppercase acronym allowlist (HQ, SM, HRCO, HC, MFR, SLA, OM, TL, ATL, NSR, G1-G5, etc.)
 * - Any token containing digits (e.g. VCAG5_0056, HRG3, phone numbers, employee numbers)
 * - Filipino orthography (Ñ / ñ)
 * - Hyphenated and apostrophed compound words (e.g. O'Brien, Dela-Cruz)
 * - Particles are title-cased per word ("Dela", "De", "La"), not lowercased
 *
 * NOTE: This is for DISPLAY/RENDER ONLY. Never mutate raw database records, search terms,
 * filters, sort parameters, API payloads, or CSV/Excel imports/exports.
 */

export const ACRONYM_ALLOWLIST = new Set([
  "HQ",
  "SM",
  "HRCO",
  "HC",
  "MFR",
  "SLA",
  "OM",
  "TL",
  "ATL",
  "NSR",
  "G1",
  "G2",
  "G3",
  "G4",
  "G5",
  "PSA",
  "SSS",
  "TIN",
  "NBI",
  "HR",
  "VCODE",
  "ID",
  "CENCOM",
  "ADR",
  "RPC",
  "RLS",
]);

/**
 * Format a single word or token according to Title Case rules:
 * - If token matches allowlist (case-insensitive check against uppercase list), keep uppercase allowlist form.
 * - If token contains any digits, preserve as-is.
 * - Handles internal apostrophes (O'Brien) and hyphens (Dela-Cruz).
 * - Handles 'Mc' prefix (MC DONALD -> Mc Donald).
 * - Full support for Ñ / ñ.
 */
function formatToken(token: string): string {
  if (!token) return token;

  // 1. If token contains any digit, preserve raw
  if (/\d/.test(token)) {
    return token;
  }

  // 2. Check acronym allowlist
  const upper = token.toUpperCase();
  if (ACRONYM_ALLOWLIST.has(upper)) {
    return upper;
  }

  // 3. Handle hyphenated sub-tokens (e.g. "DELA-CRUZ" -> "Dela-Cruz")
  if (token.includes("-")) {
    return token.split("-").map(formatToken).join("-");
  }

  // 4. Handle apostrophe sub-tokens (e.g. "O'BRIEN" -> "O'Brien")
  if (token.includes("'")) {
    return token.split("'").map(formatToken).join("'");
  }

  // 5. Handle "MC" prefix (e.g. "MCDONALD" -> "McDonald")
  if (upper.startsWith("MC") && upper.length > 2) {
    const rest = token.slice(2);
    return "Mc" + rest.charAt(0).toLocaleUpperCase("en-PH") + rest.slice(1).toLocaleLowerCase("en-PH");
  }

  // 6. Regular title case for word (supporting Ñ and unicode characters)
  const first = token.charAt(0).toLocaleUpperCase("en-PH");
  const rest = token.slice(1).toLocaleLowerCase("en-PH");
  return first + rest;
}

/**
 * Format a full display string (person name, position, store, account).
 * Splits along word boundaries while preserving punctuation and delimiters (commas, slashes, spaces, dots).
 */
export function formatDisplayText(text: string | null | undefined): string {
  if (!text) return "";
  if (typeof text !== "string") return String(text);

  // Split by regex capturing delimiters so we can reassemble exactly:
  // e.g. "SANTOS, JUAN DELA CRUZ" -> ["SANTOS", ", ", "JUAN", " ", "DELA", " ", "CRUZ"]
  // Delimiters include whitespace, slashes, commas, parentheses, etc.
  const parts = text.split(/([ \t\r\n,/()]+)/);

  return parts
    .map((part) => {
      // If the part is purely delimiter/whitespace/punctuation, keep it
      if (/^[ \t\r\n,/()]+$/.test(part)) {
        return part;
      }
      return formatToken(part);
    })
    .join("");
}

/**
 * Formats a person name into Title Case ("Santos, Juan Dela Cruz")
 * Supports either a single full name string or the (first, last, middle, full) signature.
 */
export function formatPersonName(
  firstNameOrFull?: string | null,
  lastName?: string | null,
  middleName?: string | null,
  fullName?: string | null,
): string {
  if (!firstNameOrFull && !lastName && !middleName && !fullName) return "";
  if (fullName?.trim()) {
    return formatDisplayText(fullName.trim());
  }
  if (lastName?.trim() && firstNameOrFull?.trim()) {
    const fn = firstNameOrFull.trim();
    const ln = lastName.trim();
    const mn = middleName?.trim() || "";
    const combined = mn ? `${ln}, ${fn} ${mn}` : `${ln}, ${fn}`;
    return formatDisplayText(combined);
  }
  return formatDisplayText(firstNameOrFull || lastName || "");
}

/**
 * Specialized alias for position titles
 */
export function formatPosition(pos: string | null | undefined): string {
  return formatDisplayText(pos);
}

/**
 * Specialized alias for store or outlet names
 */
export function formatStoreName(store: string | null | undefined): string {
  return formatDisplayText(store);
}

/**
 * Formats vacancy requisition aging bracket to humanized label
 * Based on authoritative definitions in vacancy.ts
 */
export function formatAgingBucket(bucket: string | null | undefined): string {
  if (!bucket) return "";
  switch (bucket) {
    case "0_7":
      return "0-7 days";
    case "8_14":
      return "8-14 days";
    case "15_30":
      return "15-30 days";
    case "31_plus":
      return "31+ days";
    default:
      return bucket;
  }
}

/**
 * Formats vacancy source enum to humanized display label
 */
export function formatVacancySource(source: string | null | undefined): string {
  if (!source) return "";
  const s = source.toLowerCase().trim();
  if (s === "pool") return "Pool";
  if (s === "plantilla") return "Plantilla";
  if (s === "coverage_group") return "Coverage Group";
  return formatDisplayText(source);
}

/**
 * Formats account name in CAPSLOCK (uppercase) per design specification
 * e.g. "MOSES HQ", "ACTISERVE", "FOREVER OFFICE"
 */
export function formatAccountName(acc: string | null | undefined): string {
  if (!acc) return "";
  return acc.trim().toUpperCase();
}
