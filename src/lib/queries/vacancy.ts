/**
 * @file vacancy.ts
 * Master Re-Export Facade for the Vacancy query domain.
 * Enforces Single Responsibility Principle (SRP) by modularizing into:
 *   - ./vacancy/types
 *   - ./vacancy/vacancyHelpers
 *   - ./vacancy/vacancyListing
 *   - ./vacancy/vacancyMutations
 *   - ./vacancy/vacancyClosures
 *   - ./vacancy/vacancyExport
 *
 * Preserves 100% backward compatibility for all existing imports.
 */

export * from "./vacancy/types";
export * from "./vacancy/vacancyHelpers";
export * from "./vacancy/vacancyListing";
export * from "./vacancy/vacancyMutations";
export * from "./vacancy/vacancyClosures";
export * from "./vacancy/vacancyExport";
