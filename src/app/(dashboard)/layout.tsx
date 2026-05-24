import { DashboardAuthShell } from "@/components/DashboardAuthShell";

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  return <DashboardAuthShell>{children}</DashboardAuthShell>;
}
