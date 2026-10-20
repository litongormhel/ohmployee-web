const SUFFIXES = new Set(["JR", "JR.", "SR", "SR.", "II", "III", "IV", "V"]);
const COMPOUND_PREFIXES = new Set([
  "DELA",
  "DE",
  "DEL",
  "DELOS",
  "SAN",
  "STA",
  "STA.",
  "SANTO",
]);

/**
 * Standardizes person names strictly to UPPERCASE:
 * "LASTNAME, FIRSTNAME MIDDLENAME" (or "LASTNAME, FIRSTNAME" if middle name absent).
 *
 * Examples:
 *   formatPersonName("LINDSAY", "LOHAN", "TAN") => "LOHAN, LINDSAY TAN"
 *   formatPersonName("Lindsay", "Lohan") => "LOHAN, LINDSAY"
 *   formatPersonName(null, null, null, "LINDSAY TAN LOHAN") => "LOHAN, LINDSAY TAN"
 *   formatPersonName(null, null, null, "LOHAN, LINDSAY TAN") => "LOHAN, LINDSAY TAN"
 *   formatPersonName(null, null, null, "ALFREDO CUIZON CAMPAÑA JR") => "CAMPAÑA JR, ALFREDO CUIZON"
 */
export function formatPersonName(
  firstName?: string | null,
  lastName?: string | null,
  middleName?: string | null,
  fullName?: string | null,
): string {
  const f = firstName?.trim() || "";
  const l = lastName?.trim() || "";
  const m = middleName?.trim() || "";

  if (l && f) {
    if (!m && fullName?.trim()) {
      const parsedFromFull = parseFullNameString(fullName.trim());
      if (parsedFromFull.includes(",")) {
        const parts = parsedFromFull.split(",");
        const parsedFirstAndMiddle = parts.slice(1).join(" ").trim();
        if (
          parsedFirstAndMiddle.toUpperCase().startsWith(f.toUpperCase()) &&
          parsedFirstAndMiddle.length > f.length
        ) {
          return `${l}, ${parsedFirstAndMiddle}`.toUpperCase();
        }
      }
    }
    const fnPart = m ? `${f} ${m}` : f;
    return `${l}, ${fnPart}`.toUpperCase();
  }

  if (l && !f) {
    return l.toUpperCase();
  }

  if (f && !l) {
    return parseFullNameString(f);
  }

  const raw = fullName?.trim() || "";
  if (!raw) return "";

  return parseFullNameString(raw);
}

/**
 * Formats HRCO name strictly as "LASTNAME, FIRSTNAME" (e.g. "GOMEZ, SELENA").
 */
export function formatHrcoName(name?: string | null): string {
  if (!name) return "";
  const trimmed = name.trim();
  if (!trimmed || trimmed === "—" || trimmed === "-") return trimmed;
  if (trimmed.toLowerCase() === "unassigned") return "Unassigned";

  const formatted = parseFullNameString(trimmed);
  if (!formatted.includes(",")) {
    return formatted.toUpperCase();
  }

  const [lastName, ...restParts] = formatted.split(",");
  const rest = restParts.join(" ").trim();
  const tokens = rest.split(/\s+/).filter(Boolean);

  if (tokens.length <= 1) {
    return `${lastName.trim()}, ${rest}`.toUpperCase();
  }

  const lastToken = tokens[tokens.length - 1];
  if (lastToken.length <= 2 || lastToken.endsWith(".")) {
    tokens.pop();
  }

  return `${lastName.trim()}, ${tokens.join(" ")}`.toUpperCase();
}

/**
 * Parses an arbitrary full name string into uppercase "LASTNAME, FIRSTNAME MIDDLENAME".
 */
export function parseFullNameString(name: string): string {
  const trimmed = name.trim();
  if (!trimmed) return "";

  const lower = trimmed.toLowerCase();
  if (
    lower.includes("vacant") ||
    lower === "unassigned" ||
    lower === "anonymous" ||
    lower === "candidate" ||
    lower === "hired worker" ||
    lower === "—" ||
    lower === "-"
  ) {
    return trimmed;
  }

  // If already contains comma: "LASTNAME, FIRSTNAME [MIDDLENAME]"
  if (trimmed.includes(",")) {
    const parts = trimmed.split(",");
    const lastPart = parts[0].trim();
    const rest = parts.slice(1).join(" ").trim();
    if (lastPart && rest) {
      return `${lastPart}, ${rest}`.toUpperCase();
    }
    return trimmed.toUpperCase();
  }

  // Space-separated: "FIRSTNAME [MIDDLENAME] LASTNAME [SUFFIX]"
  const tokens = trimmed.split(/\s+/).filter(Boolean);
  if (tokens.length <= 1) {
    return tokens[0] ? tokens[0].toUpperCase() : "";
  }

  // Check if last token is a recognized suffix (JR, SR, III, etc.)
  let lastIdx = tokens.length - 1;
  let suffix = "";
  if (tokens.length >= 3 && SUFFIXES.has(tokens[lastIdx].toUpperCase())) {
    suffix = ` ${tokens[lastIdx]}`;
    lastIdx--;
  }

  const lastPart = tokens[lastIdx] + suffix;
  const firstParts = tokens.slice(0, lastIdx).join(" ");

  return `${lastPart}, ${firstParts}`.toUpperCase();
}

/**
 * Parses candidate name components from either structured inputs or a full-name string.
 * Prioritizes discrete structured properties if provided.
 *
 * For formatted strings ("LASTNAME, FIRSTNAME MIDDLENAME"):
 * - Splits on the first comma to preserve multi-word surnames (e.g. "DELA CRUZ").
 * - Handles trailing suffix tokens (JR, SR, etc.) without misinterpreting them as middle names.
 * - Keeps compound surname prefixes (DELA, DE, SAN, etc.) attached to the middle name.
 */
export function parseCandidateFullName(
  fullName?: string | null,
  structured?: {
    firstName?: string | null;
    lastName?: string | null;
    middleName?: string | null;
  },
): {
  firstName: string;
  lastName: string;
  middleName: string;
} {
  const structuredFirst = structured?.firstName?.trim() || "";
  const structuredLast = structured?.lastName?.trim() || "";
  const structuredMiddle = structured?.middleName?.trim() || "";

  // If all structured fields are present, return them immediately
  if (structuredFirst && structuredLast && structuredMiddle) {
    return {
      firstName: structuredFirst,
      lastName: structuredLast,
      middleName: structuredMiddle,
    };
  }

  const raw = fullName?.trim() || "";
  if (!raw) {
    return {
      firstName: structuredFirst,
      lastName: structuredLast,
      middleName: structuredMiddle,
    };
  }

  // Handle placeholders
  const lower = raw.toLowerCase();
  if (
    lower === "candidate" ||
    lower === "anonymous" ||
    lower === "hired worker" ||
    lower === "unassigned" ||
    lower === "—" ||
    lower === "-"
  ) {
    return {
      firstName: structuredFirst,
      lastName: structuredLast || raw,
      middleName: structuredMiddle,
    };
  }

  let parsedLast = "";
  let parsedFirst = "";
  let parsedMiddle = "";

  if (raw.includes(",")) {
    const commaIndex = raw.indexOf(",");
    let lastSegment = raw.slice(0, commaIndex).trim();
    const restSegment = raw.slice(commaIndex + 1).trim();

    const tokens = restSegment.split(/\s+/).filter(Boolean);

    // Check if trailing token in restSegment is a suffix (e.g. "DELA CRUZ, JUANCO SANTOS JR.")
    if (tokens.length > 0 && SUFFIXES.has(tokens[tokens.length - 1].toUpperCase())) {
      const suffix = tokens.pop()!;
      if (!lastSegment.toUpperCase().includes(suffix.toUpperCase())) {
        lastSegment = `${lastSegment} ${suffix}`;
      }
    }

    parsedLast = lastSegment;

    if (tokens.length === 1) {
      parsedFirst = tokens[0];
      parsedMiddle = "";
    } else if (tokens.length >= 2) {
      // Check if second-to-last token is a compound prefix (e.g. "DELA", "SAN", etc.)
      const secondToLast = tokens[tokens.length - 2].toUpperCase();
      if (tokens.length >= 3 && COMPOUND_PREFIXES.has(secondToLast)) {
        parsedMiddle = `${tokens[tokens.length - 2]} ${tokens[tokens.length - 1]}`;
        parsedFirst = tokens.slice(0, tokens.length - 2).join(" ");
      } else {
        parsedMiddle = tokens[tokens.length - 1];
        parsedFirst = tokens.slice(0, -1).join(" ");
      }
    }
  } else {
    // No comma: e.g. "JUANCO SANTOS DELA CRUZ"
    const tokens = raw.split(/\s+/).filter(Boolean);
    let suffix = "";
    if (tokens.length >= 3 && SUFFIXES.has(tokens[tokens.length - 1].toUpperCase())) {
      suffix = ` ${tokens.pop()}`;
    }

    if (tokens.length === 1) {
      parsedLast = tokens[0] + suffix;
    } else if (tokens.length === 2) {
      parsedFirst = tokens[0];
      parsedLast = tokens[1] + suffix;
    } else {
      const secondToLast = tokens[tokens.length - 2].toUpperCase();
      let surnameTokensCount = 1;
      if (COMPOUND_PREFIXES.has(secondToLast)) {
        surnameTokensCount = 2;
      }
      const lastTokens = tokens.slice(tokens.length - surnameTokensCount);
      parsedLast = lastTokens.join(" ") + suffix;

      const remainingTokens = tokens.slice(0, tokens.length - surnameTokensCount);
      if (remainingTokens.length === 1) {
        parsedFirst = remainingTokens[0];
      } else if (remainingTokens.length >= 2) {
        const midPrefix = remainingTokens[remainingTokens.length - 2].toUpperCase();
        if (remainingTokens.length >= 3 && COMPOUND_PREFIXES.has(midPrefix)) {
          parsedMiddle = `${remainingTokens[remainingTokens.length - 2]} ${remainingTokens[remainingTokens.length - 1]}`;
          parsedFirst = remainingTokens.slice(0, remainingTokens.length - 2).join(" ");
        } else {
          parsedMiddle = remainingTokens[remainingTokens.length - 1];
          parsedFirst = remainingTokens.slice(0, -1).join(" ");
        }
      }
    }
  }

  return {
    firstName: structuredFirst || parsedFirst,
    lastName: structuredLast || parsedLast,
    middleName: structuredMiddle || parsedMiddle,
  };
}

/**
 * Formats multi-store displays compactly as "First Store Name +X more"
 * and provides a full comma-separated list of stores for hover tooltips.
 */
export function formatStoreDisplay(
  primaryStore: string | null | undefined,
  allStores?: string[] | null | undefined,
): {
  display: string;
  displayText: string;
  tooltip: string;
  hasMore: boolean;
  isMulti: boolean;
  firstStore: string;
  moreCount: number;
  extraCount: number;
} {
  const storeList: string[] = [];

  if (Array.isArray(allStores) && allStores.length > 0) {
    for (const s of allStores) {
      const clean = s?.trim();
      if (clean && !storeList.includes(clean)) {
        storeList.push(clean);
      }
    }
  }

  const rawPrimary = (primaryStore || "").trim();
  if (rawPrimary && rawPrimary !== "—" && rawPrimary !== "-") {
    // If primaryStore contains comma-separated stores
    if (rawPrimary.includes(",")) {
      const parts = rawPrimary.split(",").map((s) => s.trim()).filter(Boolean);
      for (const p of parts) {
        if (!storeList.includes(p)) {
          storeList.push(p);
        }
      }
    } else if (!storeList.includes(rawPrimary)) {
      storeList.unshift(rawPrimary);
    }
  }

  if (storeList.length > 1) {
    const firstStore = storeList[0];
    const moreCount = storeList.length - 1;
    const display = `${firstStore} +${moreCount} more`;
    return {
      display,
      displayText: display,
      tooltip: storeList.join(", "),
      hasMore: true,
      isMulti: true,
      firstStore,
      moreCount,
      extraCount: moreCount,
    };
  }

  if (storeList.length === 1) {
    return {
      display: storeList[0],
      displayText: storeList[0],
      tooltip: storeList[0],
      hasMore: false,
      isMulti: false,
      firstStore: storeList[0],
      moreCount: 0,
      extraCount: 0,
    };
  }

  const fallback = rawPrimary || "—";
  return {
    display: fallback,
    displayText: fallback,
    tooltip: rawPrimary || "Unassigned Outlet",
    hasMore: false,
    isMulti: false,
    firstStore: fallback,
    moreCount: 0,
    extraCount: 0,
  };
}
