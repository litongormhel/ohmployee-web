import type { ReactNode } from "react";

/**
 * Shared Modal & Dialog Contracts (Interface Segregation Principle & Liskov Substitution Principle)
 *
 * Defines lean, segregated interfaces for modals and dialogs across OHMployee Web.
 */

/**
 * Minimal contract for any component acting as a modal dialog.
 * Enforces Interface Segregation by standardizing open/close state controls.
 */
export interface BaseModalProps {
  isOpen: boolean;
  onClose: () => void;
}

/**
 * Standard contract for action-oriented dialogs that dispatch an onSuccess notification or payload.
 */
export interface ActionModalProps<TResult = void> extends BaseModalProps {
  onSuccess?: (result: TResult) => void;
}

/**
 * Standard contract for entity-focused dialogs that target a specific domain object.
 */
export interface EntityModalProps<TEntity, TResult = void> extends ActionModalProps<TResult> {
  entity: TEntity;
}

/**
 * Standard contract for sliding drawer components controlled via isOpen boolean.
 */
export interface BaseDrawerProps extends BaseModalProps {
  title?: string | ReactNode;
}
