"use client";

import { useState, useCallback } from "react";
import type { VacancyStatus } from "./VacancyTable";

export interface VacancyFilterState {
  status: VacancyStatus;
  search: string;
  accountId: string;
  groupId: string;
  agingBucket: string;
  urgency: string;
  vacantFrom: string;
  vacantTo: string;
}

export interface VacancySavedView {
  id: string;
  name: string;
  filters: VacancyFilterState;
  createdAt: string;
  updatedAt: string;
}

const STORAGE_KEY = "ohm_vacancy_saved_views_v1";

function loadSavedViewsFromStorage(): VacancySavedView[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        return parsed;
      }
    }
  } catch (e) {
    console.error("Failed to load saved views from localStorage:", e);
  }
  return [];
}

export function useVacancySavedViews() {
  const [savedViews, setSavedViews] = useState<VacancySavedView[]>(loadSavedViewsFromStorage);

  const persistViews = useCallback((views: VacancySavedView[]) => {
    setSavedViews(views);
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(views));
    } catch (e) {
      console.error("Failed to persist saved views to localStorage:", e);
    }
  }, []);

  const saveView = useCallback(
    (name: string, filters: VacancyFilterState): VacancySavedView => {
      const now = new Date().toISOString();
      const newView: VacancySavedView = {
        id:
          typeof crypto !== "undefined" && crypto.randomUUID
            ? crypto.randomUUID()
            : `view_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`,
        name: name.trim(),
        filters: { ...filters },
        createdAt: now,
        updatedAt: now,
      };

      const updated = [newView, ...savedViews];
      persistViews(updated);
      return newView;
    },
    [savedViews, persistViews]
  );

  const updateView = useCallback(
    (id: string, name: string, filters: VacancyFilterState): VacancySavedView | null => {
      const now = new Date().toISOString();
      let updatedItem: VacancySavedView | null = null;
      const updated = savedViews.map((item) => {
        if (item.id === id) {
          updatedItem = {
            ...item,
            name: name.trim() || item.name,
            filters: { ...filters },
            updatedAt: now,
          };
          return updatedItem;
        }
        return item;
      });

      if (updatedItem) {
        persistViews(updated);
      }
      return updatedItem;
    },
    [savedViews, persistViews]
  );

  const deleteView = useCallback(
    (id: string) => {
      const updated = savedViews.filter((item) => item.id !== id);
      persistViews(updated);
    },
    [savedViews, persistViews]
  );

  return {
    savedViews,
    saveView,
    updateView,
    deleteView,
  };
}
