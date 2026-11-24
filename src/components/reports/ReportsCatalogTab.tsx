"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  AlertTriangle,
  ArrowRight,
  Clock,
  FileCheck2,
  Hourglass,
  Layers,
  MapPin,
  Search,
  TrendingDown,
  UserCheck,
  UserMinus,
  Users,
  UserX,
  X,
  type LucideIcon,
} from "lucide-react";
import { ReportDetailView } from "./ReportDetailView";

interface ReportsCatalogTabProps {
  initialReportId?: string | null;
  onSwitchTab?: (tab: string) => void;
}

type ReportCategoryKey = "all" | "separation" | "velocity" | "operations";

interface CatalogItem {
  id: string;
  title: string;
  description: string;
  category: "separation" | "velocity" | "operations";
  categoryLabel: string;
  icon: LucideIcon;
  actionType: "select" | "tab" | "link";
  target: string;
  badge?: string;
}

const CATALOG_ITEMS: CatalogItem[] = [
  // Separation & Attrition Reports
  {
    id: "attrition_report",
    title: "Attrition Report",
    description: "Separation rates across accounts, drill down into affected stores, and employee histories.",
    category: "separation",
    categoryLabel: "Separation & Attrition",
    icon: TrendingDown,
    actionType: "select",
    target: "attrition_report",
  },
  {
    id: "resigned_report",
    title: "Resigned Staff Report",
    description: "Voluntary employee resignations and turnover breakdown by account with date range filtering.",
    category: "separation",
    categoryLabel: "Separation & Attrition",
    icon: UserCheck,
    actionType: "select",
    target: "resigned_report",
  },
  {
    id: "awol_report",
    title: "AWOL Separation Report",
    description: "Absence Without Official Leave separations, disciplinary movement, and store impact tracking.",
    category: "separation",
    categoryLabel: "Separation & Attrition",
    icon: UserX,
    actionType: "select",
    target: "awol_report",
  },
  {
    id: "terminated_report",
    title: "Terminated Staff Report",
    description: "Involuntary separations, contract expirations, and end-of-service compliance tracking.",
    category: "separation",
    categoryLabel: "Separation & Attrition",
    icon: UserMinus,
    actionType: "select",
    target: "terminated_report",
  },
  {
    id: "backout_report",
    title: "Back-Out Report",
    description: "Candidate onboarding back-outs and pre-deployment recruitment leakage audit.",
    category: "separation",
    categoryLabel: "Separation & Attrition",
    icon: Clock,
    actionType: "select",
    target: "backout_report",
  },
  {
    id: "backout_terminated_report",
    title: "Back-Out & Terminated",
    description: "Combined leakage view tracking candidate back-outs alongside staff terminations in unified cards.",
    category: "separation",
    categoryLabel: "Separation & Attrition",
    icon: Layers,
    actionType: "select",
    target: "backout_terminated_report",
  },

  // Recruitment Velocity & Turnaround
  {
    id: "time_to_fill",
    title: "Time to Fill Report",
    description: "Average requisition days to fill open vacancy slots, hiring speed, and store deployment velocity.",
    category: "velocity",
    categoryLabel: "Recruitment Velocity & Turnaround",
    icon: Clock,
    actionType: "select",
    target: "time_to_fill",
  },
  {
    id: "vacancy_aging",
    title: "Vacancy Aging & Allocation",
    description: "Inspect open vacancy duration, active headcount, and plantilla slot capacity across accounts.",
    category: "velocity",
    categoryLabel: "Recruitment Velocity & Turnaround",
    icon: Hourglass,
    actionType: "tab",
    target: "custom",
    badge: "Builder",
  },
  {
    id: "target_deployment",
    title: "Target Deployment Overview",
    description: "Store-by-store deployment fulfillment rates and geographic coverage breakdown in CENCOM.",
    category: "velocity",
    categoryLabel: "Recruitment Velocity & Turnaround",
    icon: MapPin,
    actionType: "link",
    target: "/cencom",
    badge: "CENCOM",
  },

  // Workforce Health & Operational Audit
  {
    id: "emploc_late_update",
    title: "HR Emploc Late Updates",
    description: "SLA breaches and delayed location submissions across employee onboarding queues.",
    category: "operations",
    categoryLabel: "Workforce Health & Operational Audit",
    icon: Clock,
    actionType: "select",
    target: "emploc_late_update",
  },
  {
    id: "floating",
    title: "Floating Staff Report",
    description: "Floating employees aging (<30d, 30–60d, >60d) and Article 301 compliance tracking.",
    category: "operations",
    categoryLabel: "Workforce Health & Operational Audit",
    icon: Users,
    actionType: "tab",
    target: "floating",
    badge: "Tab 2",
  },
  {
    id: "team_performance",
    title: "Team Performance",
    description: "Discipline rankings, scorecards, and operational SLA issue tracking.",
    category: "operations",
    categoryLabel: "Workforce Health & Operational Audit",
    icon: Layers,
    actionType: "tab",
    target: "team_performance",
    badge: "Tab 3",
  },
  {
    id: "data_integrity",
    title: "Data Integrity Audit",
    description: "Ghost occupancy, delay audit, and recruitment pipeline anomalies.",
    category: "operations",
    categoryLabel: "Workforce Health & Operational Audit",
    icon: AlertTriangle,
    actionType: "tab",
    target: "data_integrity",
    badge: "Tab 4",
  },
];

const CATEGORY_SECTIONS: {
  key: "separation" | "velocity" | "operations";
  title: string;
  icon: LucideIcon;
}[] = [
  {
    key: "separation",
    title: "Separation & Attrition Reports",
    icon: UserMinus,
  },
  {
    key: "velocity",
    title: "Recruitment Velocity & Turnaround",
    icon: Hourglass,
  },
  {
    key: "operations",
    title: "Workforce Health & Operational Audit",
    icon: FileCheck2,
  },
];

export function ReportsCatalogTab({
  initialReportId,
  onSwitchTab,
}: ReportsCatalogTabProps) {
  const router = useRouter();
  const [selectedReportId, setSelectedReportId] = useState<string | null>(
    initialReportId || null
  );
  const [activeCategory, setActiveCategory] = useState<ReportCategoryKey>("all");
  const [searchQuery, setSearchQuery] = useState("");

  const handleAction = (item: CatalogItem) => {
    if (item.actionType === "select") {
      setSelectedReportId(item.target);
    } else if (item.actionType === "tab") {
      onSwitchTab?.(item.target);
    } else if (item.actionType === "link") {
      router.push(item.target);
    }
  };

  const filteredItems = useMemo(() => {
    return CATALOG_ITEMS.filter((item) => {
      if (activeCategory !== "all" && item.category !== activeCategory) {
        return false;
      }
      if (!searchQuery.trim()) return true;
      const q = searchQuery.toLowerCase();
      return (
        item.title.toLowerCase().includes(q) ||
        item.description.toLowerCase().includes(q) ||
        item.categoryLabel.toLowerCase().includes(q)
      );
    });
  }, [activeCategory, searchQuery]);

  const countsByCategory = useMemo(() => {
    return {
      all: CATALOG_ITEMS.length,
      separation: CATALOG_ITEMS.filter((i) => i.category === "separation").length,
      velocity: CATALOG_ITEMS.filter((i) => i.category === "velocity").length,
      operations: CATALOG_ITEMS.filter((i) => i.category === "operations").length,
    };
  }, []);

  if (selectedReportId) {
    return (
      <ReportDetailView
        reportId={selectedReportId}
        onBack={() => setSelectedReportId(null)}
      />
    );
  }

  return (
    <div className="space-y-5 animate-in fade-in duration-150">
      {/* Compact Controls Toolbar */}
      <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3 p-1">
        {/* Category Filter Chips */}
        <div className="flex items-center gap-1.5 overflow-x-auto no-scrollbar">
          <button
            type="button"
            onClick={() => setActiveCategory("all")}
            className={`px-2.5 py-1 text-xs font-medium rounded-md transition cursor-pointer whitespace-nowrap ${
              activeCategory === "all"
                ? "bg-brand-primary text-white shadow-2xs"
                : "text-text-secondary hover:text-text-primary hover:bg-surface-hover bg-surface-subtle border border-border-subtle"
            }`}
          >
            All Reports ({countsByCategory.all})
          </button>
          <button
            type="button"
            onClick={() => setActiveCategory("separation")}
            className={`px-2.5 py-1 text-xs font-medium rounded-md transition cursor-pointer whitespace-nowrap ${
              activeCategory === "separation"
                ? "bg-brand-primary text-white shadow-2xs"
                : "text-text-secondary hover:text-text-primary hover:bg-surface-hover bg-surface-subtle border border-border-subtle"
            }`}
          >
            Separation ({countsByCategory.separation})
          </button>
          <button
            type="button"
            onClick={() => setActiveCategory("velocity")}
            className={`px-2.5 py-1 text-xs font-medium rounded-md transition cursor-pointer whitespace-nowrap ${
              activeCategory === "velocity"
                ? "bg-brand-primary text-white shadow-2xs"
                : "text-text-secondary hover:text-text-primary hover:bg-surface-hover bg-surface-subtle border border-border-subtle"
            }`}
          >
            Velocity ({countsByCategory.velocity})
          </button>
          <button
            type="button"
            onClick={() => setActiveCategory("operations")}
            className={`px-2.5 py-1 text-xs font-medium rounded-md transition cursor-pointer whitespace-nowrap ${
              activeCategory === "operations"
                ? "bg-brand-primary text-white shadow-2xs"
                : "text-text-secondary hover:text-text-primary hover:bg-surface-hover bg-surface-subtle border border-border-subtle"
            }`}
          >
            Operations ({countsByCategory.operations})
          </button>
        </div>

        {/* Search Input */}
        <div className="relative w-full sm:w-64 shrink-0">
          <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-text-muted pointer-events-none" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Filter reports..."
            className="w-full h-8 pl-8 pr-7 text-xs rounded-lg border border-border-default bg-surface-base text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-1 focus:ring-brand-primary transition"
          />
          {searchQuery && (
            <button
              type="button"
              onClick={() => setSearchQuery("")}
              className="absolute right-2 top-1/2 -translate-y-1/2 text-text-muted hover:text-text-primary p-0.5 rounded cursor-pointer"
            >
              <X className="w-3 h-3" />
            </button>
          )}
        </div>
      </div>

      {/* Report Cards by Section */}
      {searchQuery.trim() ? (
        /* Flat filtered view when searching */
        <div className="space-y-3">
          <div className="flex items-center justify-between text-xs text-text-muted pb-1 border-b border-border-subtle">
            <span>
              Search results for &ldquo;{searchQuery}&rdquo; ({filteredItems.length})
            </span>
            <button
              type="button"
              onClick={() => setSearchQuery("")}
              className="text-brand-primary hover:underline font-medium cursor-pointer"
            >
              Clear filter
            </button>
          </div>

          {filteredItems.length === 0 ? (
            <div className="p-8 text-center rounded-xl border border-dashed border-border-default bg-surface-subtle">
              <p className="text-xs text-text-muted">No reports match your search query.</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2.5">
              {filteredItems.map((item) => (
                <ReportCard key={item.id} item={item} onAction={handleAction} />
              ))}
            </div>
          )}
        </div>
      ) : (
        /* Categorized sections */
        <div className="space-y-5">
          {CATEGORY_SECTIONS.map((section) => {
            const items = filteredItems.filter((i) => i.category === section.key);
            if (items.length === 0) return null;
            const SectionIcon = section.icon;

            return (
              <div key={section.key} className="space-y-2">
                <div className="flex items-center gap-2 pb-1 border-b border-border-subtle">
                  <SectionIcon className="w-3.5 h-3.5 text-text-secondary" />
                  <h3 className="text-xs font-bold uppercase tracking-wider text-text-secondary">
                    {section.title}
                  </h3>
                  <span className="text-[10px] font-semibold text-text-muted bg-surface-subtle px-1.5 py-0.2 rounded border border-border-subtle">
                    {items.length}
                  </span>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2.5">
                  {items.map((item) => (
                    <ReportCard key={item.id} item={item} onAction={handleAction} />
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function ReportCard({
  item,
  onAction,
}: {
  item: CatalogItem;
  onAction: (item: CatalogItem) => void;
}) {
  const Icon = item.icon;

  return (
    <div
      onClick={() => onAction(item)}
      className="group relative p-3 rounded-xl border border-border-default bg-surface-base hover:border-brand-primary/50 hover:bg-surface-subtle/40 hover:shadow-2xs transition-all cursor-pointer flex items-start gap-2.5"
    >
      <div className="w-8 h-8 rounded-lg bg-surface-subtle border border-border-default flex items-center justify-center shrink-0 text-text-secondary group-hover:text-brand-primary group-hover:border-brand-primary/40 group-hover:bg-brand-primary/5 transition">
        <Icon className="w-4 h-4" />
      </div>

      <div className="flex-1 min-w-0">
        <div className="flex items-center justify-between gap-1.5">
          <h4 className="text-xs font-bold text-text-primary group-hover:text-brand-primary transition truncate">
            {item.title}
          </h4>
          <div className="flex items-center gap-1 shrink-0">
            {item.badge && (
              <span className="text-[9px] font-medium text-text-muted bg-surface-subtle px-1.5 py-0.5 rounded border border-border-subtle">
                {item.badge}
              </span>
            )}
            <ArrowRight className="w-3.5 h-3.5 text-text-tertiary group-hover:text-brand-primary group-hover:translate-x-0.5 transition" />
          </div>
        </div>
        <p className="text-[11px] text-text-secondary line-clamp-2 mt-0.5 leading-snug">
          {item.description}
        </p>
      </div>
    </div>
  );
}
