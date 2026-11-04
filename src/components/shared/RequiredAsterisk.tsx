import React from "react";

export interface RequiredAsteriskProps {
  className?: string;
}

/**
 * Global standardized required field indicator (*) in Red (#EF4444 / text-red-500)
 * matching OHMployee system-wide design specifications.
 */
export function RequiredAsterisk({ className = "" }: RequiredAsteriskProps) {
  return (
    <span
      className={`text-red-500 font-semibold ml-0.5 select-none ${className}`.trim()}
      aria-hidden="true"
    >
      *
    </span>
  );
}

export default RequiredAsterisk;
