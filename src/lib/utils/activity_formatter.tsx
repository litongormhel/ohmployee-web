/**
 * src/lib/utils/activity_formatter.tsx
 *
 * Presentation-layer formatter for Recent Activity Feed (Phase 2B-1).
 * Formats allow-listed operational events into human-readable sentences
 * rendered as pure React elements (zero dangerouslySetInnerHTML).
 */

import React from "react";
import {
  UserCheck,
  UserX,
  Briefcase,
  UserMinus,
  AlertCircle,
  FileCheck,
  ArrowRightCircle,
  RotateCcw,
  PlusCircle,
  Clock,
  Sparkles,
} from "lucide-react";
import type { RecentActivityItem, ActivityEventType } from "@/lib/queries/activity";

export function getActivityEventIcon(eventType: ActivityEventType): React.ReactElement {
  switch (eventType) {
    case "user_approved":
    case "user_role_updated":
      return <UserCheck className="h-3.5 w-3.5 text-emerald-600 dark:text-emerald-400" />;
    case "user_archived":
      return <UserX className="h-3.5 w-3.5 text-rose-600 dark:text-rose-400" />;
    case "plantilla_deployed":
    case "emploc_deployed":
      return <Briefcase className="h-3.5 w-3.5 text-brand-600 dark:text-brand-400" />;
    case "plantilla_separation":
    case "plantilla_deactivated":
      return <UserMinus className="h-3.5 w-3.5 text-rose-600 dark:text-rose-400" />;
    case "plantilla_on_leave":
    case "plantilla_deactivation_requested":
      return <Clock className="h-3.5 w-3.5 text-amber-600 dark:text-amber-400" />;
    case "vacancy_opened":
    case "emploc_created":
      return <PlusCircle className="h-3.5 w-3.5 text-blue-600 dark:text-blue-400" />;
    case "vacancy_filled":
    case "emploc_approved":
      return <FileCheck className="h-3.5 w-3.5 text-emerald-600 dark:text-emerald-400" />;
    case "vacancy_closed":
      return <UserMinus className="h-3.5 w-3.5 text-slate-500" />;
    case "vacancy_reopened":
    case "emploc_reverted":
      return <RotateCcw className="h-3.5 w-3.5 text-amber-600 dark:text-amber-400" />;
    case "emploc_for_correction":
      return <AlertCircle className="h-3.5 w-3.5 text-amber-600 dark:text-amber-400" />;
    case "emploc_for_review":
      return <ArrowRightCircle className="h-3.5 w-3.5 text-indigo-600 dark:text-indigo-400" />;
    default:
      return <Sparkles className="h-3.5 w-3.5 text-slate-500" />;
  }
}

export function formatRecentActivitySentence(item: RecentActivityItem): React.ReactNode {
  const { actorName, eventType, details } = item;
  const isSystem = !actorName || actorName.toLowerCase() === "system";

  const actorNode = (
    <span className="font-semibold text-text-primary">
      {isSystem ? "System:" : actorName}
    </span>
  );

  const subjectNode = details.subject ? (
    <span className="font-semibold text-text-primary">{details.subject}</span>
  ) : (
    <span className="font-semibold text-text-primary">Record</span>
  );

  const employeeBadge = details.employee_no ? (
    <span className="text-text-muted font-mono text-[11px] ml-1">
      [{details.employee_no}]
    </span>
  ) : null;

  const accountTag = details.account_name ? (
    <span className="font-medium text-text-secondary ml-1">
      [{details.account_name}]
    </span>
  ) : null;

  const positionNode = details.position ? (
    <span className="font-semibold text-text-primary">{details.position}</span>
  ) : (
    <span className="font-semibold text-text-primary">Vacancy</span>
  );

  const storeText = details.store_name ? ` at ${details.store_name}` : "";

  switch (eventType) {
    case "user_approved":
      return (
        <span>
          {actorNode} approved new user {subjectNode} as{" "}
          <span className="font-medium text-text-primary">
            {details.target_role || "User"}
          </span>
        </span>
      );

    case "user_role_updated":
      return (
        <span>
          {actorNode} updated role for {subjectNode} to{" "}
          <span className="font-medium text-text-primary">
            {details.target_role || "User"}
          </span>
        </span>
      );

    case "user_archived":
      return (
        <span>
          {actorNode} archived user {subjectNode}
        </span>
      );

    case "plantilla_deployed":
      return (
        <span>
          {actorNode} {subjectNode}
          {employeeBadge} transferred to Plantilla{accountTag}
        </span>
      );

    case "plantilla_separation":
      return (
        <span>
          {actorNode} marked separation for {subjectNode}
          {accountTag}
        </span>
      );

    case "plantilla_deactivated":
      return (
        <span>
          {actorNode} deactivated plantilla slot for {subjectNode}
          {accountTag}
        </span>
      );

    case "plantilla_on_leave":
      return (
        <span>
          {actorNode} updated status for {subjectNode} to On Leave{accountTag}
        </span>
      );

    case "plantilla_deactivation_requested":
      return (
        <span>
          {actorNode} requested deactivation for {subjectNode}
          {accountTag}
        </span>
      );

    case "vacancy_opened":
      return (
        <span>
          {actorNode} opened vacancy for {positionNode}
          {storeText}
          {accountTag}
        </span>
      );

    case "vacancy_filled":
      return (
        <span>
          {actorNode} filled vacancy for {positionNode}
          {storeText}
          {accountTag}
        </span>
      );

    case "vacancy_closed":
      return (
        <span>
          {actorNode} closed vacancy for {positionNode}
          {storeText}
          {accountTag}
        </span>
      );

    case "vacancy_reopened":
      return (
        <span>
          {actorNode} reopened vacancy for {positionNode}
          {storeText}
          {accountTag}
        </span>
      );

    case "emploc_created":
      return (
        <span>
          {actorNode} created HR Emploc for {subjectNode}
          {accountTag}
        </span>
      );

    case "emploc_for_correction":
      return (
        <span>
          {actorNode} flagged {subjectNode} for correction{accountTag}
        </span>
      );

    case "emploc_for_review":
      return (
        <span>
          {actorNode} submitted correction for {subjectNode}
          {accountTag}
        </span>
      );

    case "emploc_approved":
      return (
        <span>
          {actorNode} approved HR Emploc for {subjectNode}
          {accountTag}
        </span>
      );

    case "emploc_deployed":
      return (
        <span>
          {actorNode} deployed {subjectNode} to Plantilla{accountTag}
        </span>
      );

    case "emploc_reverted":
      return (
        <span>
          {actorNode} reverted {subjectNode} back to Pending{accountTag}
        </span>
      );

    default:
      return (
        <span>
          {actorNode} recorded update on {subjectNode}
        </span>
      );
  }
}
