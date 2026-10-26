# UI Standard Rollout Queue

Track progress of the continuous UI Standard & Motion System rollout across OHMployee Web.
Each item is ticked ONLY after completing its own complete verification:
1. `npm run lint` clean (0 errors)
2. `npm run build` clean (all routes generated, 0 type errors)
3. Color literals = 0 for the module
4. Behavior diff audit
5. Danger audit (--danger strictly for errors/destructive/failed states)
6. Color-use audit (percentages only for semantic colors)
7. Documentation updated (`.ai/briefing.md`, `.ai/handoff.md`, state files)
8. Local commit on `main` (never push/merge)

---

## Rollout Queue Checklist

- [x] 7A Approvals navigation + data tables
- [x] 7B Approvals cards + action modals
- [x] Users and Team Directory
- [x] Notifications
- [x] Reports
- [x] Settings
- [x] More A (governance/security)
- [x] More B (import centers/QA)
- [ ] Final: app-wide route transition and page-enter sequence in the shared (dashboard) layout, consistency sweep across modules, full light/dark/responsive pass, remove dead styles, consolidate docs, final ui-standard.md update
