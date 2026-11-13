export interface RoleBadgeConfig {
  label: string;
  badgeClass: string;
}

export function getRoleBadgeConfig(roleName?: string | null): RoleBadgeConfig {
  const norm = (roleName ?? "").toLowerCase().trim();

  if (norm.includes("head admin") || norm.includes("super admin")) {
    return {
      label: "Head Admin",
      badgeClass: "bg-purple-500/10 text-purple-700 dark:text-purple-300 border-purple-500/20",
    };
  }
  if (norm.includes("encoder")) {
    return {
      label: "Encoder",
      badgeClass: "bg-blue-500/10 text-blue-700 dark:text-blue-300 border-blue-500/20",
    };
  }
  if (norm.includes("recruitment") || norm.includes("recruiter")) {
    return {
      label: "Recruitment",
      badgeClass: "bg-teal-500/10 text-teal-700 dark:text-teal-300 border-teal-500/20",
    };
  }
  if (norm.includes("hrco") || norm.includes("operations")) {
    return {
      label: "HRCO",
      badgeClass: "bg-amber-500/10 text-amber-700 dark:text-amber-300 border-amber-500/20",
    };
  }
  if (norm.includes("hr personnel") || norm.includes("hr staff") || norm.includes("personnel")) {
    return {
      label: "HR Personnel",
      badgeClass: "bg-indigo-500/10 text-indigo-700 dark:text-indigo-300 border-indigo-500/20",
    };
  }
  if (norm.includes("back office") || norm.includes("bo staff")) {
    return {
      label: "Back Office",
      badgeClass: "bg-slate-500/10 text-slate-700 dark:text-slate-300 border-slate-500/20",
    };
  }

  return {
    label: roleName ?? "Unknown Role",
    badgeClass: "bg-surface-subtle text-text-secondary border-border-default",
  };
}
