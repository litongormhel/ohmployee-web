import {
  Bell,
  BriefcaseBusiness,
  Building2,
  CheckCheck,
  ClipboardList,
  FileBarChart,
  LayoutDashboard,
  MoreHorizontal,
  Settings,
  ShieldCheck,
  Users,
  UsersRound,
} from "lucide-react";

export type WebModule = {
  key: string;
  title: string;
  href: string;
  purpose: string;
  icon: typeof LayoutDashboard;
};

export const webModules: WebModule[] = [
  {
    key: "dashboard",
    title: "Dashboard",
    href: "/dashboard",
    purpose: "Command-center landing space for operational summaries and next actions.",
    icon: LayoutDashboard,
  },
  {
    key: "cencom",
    title: "CENCOM",
    href: "/cencom",
    purpose: "Centralized coordination workspace for workforce operations.",
    icon: Building2,
  },
  {
    key: "vacancy",
    title: "Vacancy",
    href: "/vacancy",
    purpose: "Vacancy tracking foundation for requisition and hiring movement.",
    icon: BriefcaseBusiness,
  },
  {
    key: "hr_emploc",
    title: "HR Emploc",
    href: "/hr-emploc",
    purpose: "Employee location and HR assignment workspace.",
    icon: ClipboardList,
  },
  {
    key: "plantilla",
    title: "Plantilla",
    href: "/plantilla",
    purpose: "Position structure and staffing plantilla foundation.",
    icon: ShieldCheck,
  },
  {
    key: "approvals",
    title: "Approvals",
    href: "/approvals",
    purpose: "Review queue shell for future routed approval workflows.",
    icon: CheckCheck,
  },
  {
    key: "users",
    title: "User Management",
    href: "/users",
    purpose: "Access and account administration workspace.",
    icon: Users,
  },
  {
    key: "team_directory",
    title: "Team Directory",
    href: "/team-directory",
    purpose: "Organization directory shell for teams, people, and reporting lines.",
    icon: UsersRound,
  },
  {
    key: "notifications",
    title: "Notifications",
    href: "/notifications",
    purpose: "Operational notification center for future alerts and messages.",
    icon: Bell,
  },
  {
    key: "reports",
    title: "Reports",
    href: "/reports",
    purpose: "Reporting surface for future exports, metrics, and operational review.",
    icon: FileBarChart,
  },
  {
    key: "settings",
    title: "Settings",
    href: "/settings",
    purpose: "Administrative configuration space for web app settings.",
    icon: Settings,
  },
  {
    key: "more",
    title: "More",
    href: "/more",
    purpose: "Overflow area for modules that do not yet need primary navigation.",
    icon: MoreHorizontal,
  },
];

export function getModuleByHref(href: string) {
  return webModules.find((module) => module.href === href);
}

export function getActiveModule(pathname: string, modules: WebModule[] = webModules) {
  return (
    modules.find((module) =>
      module.href === "/dashboard"
        ? pathname === module.href
        : pathname.startsWith(module.href),
    ) ?? modules[0] ?? webModules[0]
  );
}
