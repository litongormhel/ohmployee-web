import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

export interface RefLocationItem {
  province: string;
  city: string;
  island_group?: string | null;
}

/**
 * Fetch unique active provinces sorted alphabetically.
 */
export async function fetchRefProvinces(): Promise<string[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("ref_locations")
    .select("province")
    .eq("is_active", true)
    .order("province");

  if (error) {
    console.error("[PostgREST Schema Error] fetchRefProvinces failed:", error);
    throw error;
  }

  if (!data) return [];

  const unique = Array.from(
    new Set(
      data
        .map((r: { province: string | null }) => r.province?.trim() || "")
        .filter(Boolean)
    )
  ).sort();

  return unique;
}

export function useRefProvinces(options?: { enabled?: boolean }) {
  return useQuery({
    queryKey: ["ref_locations", "provinces"],
    queryFn: fetchRefProvinces,
    staleTime: 1000 * 60 * 30, // 30 minutes cache for static reference data
    enabled: options?.enabled ?? true,
  });
}

/**
 * Fetch unique active cities for a specific province.
 */
export async function fetchRefCities(province: string): Promise<string[]> {
  if (!province?.trim()) return [];

  const supabase = createClient();
  const { data, error } = await supabase
    .from("ref_locations")
    .select("city")
    .eq("province", province.trim())
    .eq("is_active", true)
    .order("city", { ascending: true });

  if (error) {
    console.error(`[PostgREST Schema Error] fetchRefCities for ${province} failed:`, error);
    throw error;
  }

  if (!data) return [];

  const rawCities = data.map((c: { city: string | null }) => c.city?.trim() || "");
  const uniqueCitiesMap = new Map<string, string>();
  rawCities.filter(Boolean).forEach((c: string) => {
    const key = c.toLowerCase();
    if (!uniqueCitiesMap.has(key)) {
      uniqueCitiesMap.set(key, c);
    }
  });

  return Array.from(uniqueCitiesMap.values()).sort();
}

export function useRefCities(province?: string | null, options?: { enabled?: boolean }) {
  const cleanProvince = province?.trim() || null;
  return useQuery({
    queryKey: ["ref_locations", "cities", cleanProvince],
    queryFn: () => (cleanProvince ? fetchRefCities(cleanProvince) : Promise.resolve([])),
    staleTime: 1000 * 60 * 30,
    enabled: (options?.enabled ?? true) && Boolean(cleanProvince),
  });
}

/**
 * Fetch all active locations with province, city, and island_group.
 */
export async function fetchRefLocations(): Promise<RefLocationItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("ref_locations")
    .select("province, city, island_group")
    .eq("is_active", true)
    .order("province", { ascending: true });

  if (error) {
    console.error("[PostgREST Schema Error] fetchRefLocations failed:", error);
    throw error;
  }

  return (data ?? []).map((row) => ({
    province: row.province?.trim() || "",
    city: row.city?.trim() || "",
    island_group: row.island_group || null,
  }));
}

export function useRefLocations(options?: { enabled?: boolean }) {
  return useQuery({
    queryKey: ["ref_locations", "all"],
    queryFn: fetchRefLocations,
    staleTime: 1000 * 60 * 30,
    enabled: options?.enabled ?? true,
  });
}
