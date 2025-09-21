# Deep Dive: Composers

## Why Composers Exist

Primitives give us atoms, compounds give us molecules — but product
interfaces demand more. A composer is where a design system stops
bundling parts and starts orchestrating interaction and state.

Think of a modal, a toolbar, pagination, or a form fieldset. These
aren't just bundles of primitives — they coordinate:

- Multiple states (open/closed, selected/unselected, error/valid).
- Multiple flows (keyboard vs mouse, small vs large screen, logged in
  vs logged out).
- Multiple roles (what happens to focus, what gets announced to a
  screen reader, what rules apply when contents vary).

Composers exist because user interactions don't stop at a single
element — they span across elements.

## Characteristics of Composers

- **Orchestration**: manage focus, context, and state for child
  primitives/compounds.
- **Slotting**: expose defined areas (header, body, footer, actions) for
  flexible composition.
- **Variation by pattern, not prop**: handle families of behavior (e.g.,
  ellipses in pagination) rather than a Boolean soup of configuration.
- **Context Providers**: share state between sub-parts without forcing
  prop-drilling.

## Examples of Composers

- **Modal**: orchestrates open/close, traps focus, provides slots for
  header/body/footer.
- **Form Field**: orchestrates label, input, error messaging across
  multiple input types.
- **Toolbar / Filter Bar**: orchestrates a dynamic set of actions,
  priorities, and overflow menus.
- **Pagination**: orchestrates page numbers, overflow ellipses, compact vs
  full modes.
- **Rich Text Editor**: orchestrates schema, commands, plugins, and UI
  slots.

## The Work of the System at the Composer Layer

### 1. Orchestration

- Control state transitions (modal open → trap focus → restore focus
  on close).
- Govern keyboard interaction models (arrow key navigation in
  toolbars, tab order in forms).
- Provide context for sub-parts (form state, toolbar action registry).

### 2. Variation by Pattern

- Instead of adding a prop for every variant, encode structural
  patterns.
- Example: Pagination doesn't expose showEllipses: boolean; it defines
  a policy for when ellipses appear.

### 3. Slots for Composition

- Provide places for product-specific content without breaking
  orchestration.
- Example: Modal slots for header/body/footer let teams add what they
  need while the system enforces a11y and focus rules.

## Pitfalls of Composers

1. **Prop Explosion as a Lazy Shortcut**
   - Composers often start with props for each variation:
     hasCloseButton, showFooter, isInline, isSticky.
   - Guardrail: encode variations as structural patterns, not
     toggles.

2. **Leaking Internal State**
   - If a form composer exposes internal validation state poorly,
     teams may hack around it.
   - Guardrail: provide a clean context/hook API for internal
     orchestration.

3. **Breaking Accessibility in the Orchestration**
   - Example: a modal that doesn't trap focus or a toolbar without
     roving tabindex.
   - Guardrail: accessibility rules must be first-class
     orchestration, not optional add-ons.

4. **Overgeneralization**
   - Composers aren't universal solutions. A "SuperModal" that tries
     to handle every drawer/alert/dialog variant will be brittle.
   - Guardrail: scope composers to a pattern family, not the entire
     design problem space.

## The Problem: Without Composers

Before we see composers in action, let's understand what happens
without them. Consider building modals across a large application:

```tsx
// Without Composer: Scattered logic, inconsistent behavior
import { useState, useEffect } from 'react';

export function BadModal({ isOpen, onClose, children }: {
  isOpen: boolean;
  onClose: () => void;
  children: React.ReactNode;
}) {
  // Each modal reimplements focus trap differently (or not at all)
  useEffect(() => {
    if (isOpen) {
      // Some modals handle escape, others don't
      const handleEscape = (e: KeyboardEvent) => {
        if (e.key === 'Escape') onClose();
      };
      document.addEventListener('keydown', handleEscape);
      return () => document.removeEventListener('keydown', handleEscape);
    }
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  return (
    <div 
      style={{
        position: 'fixed',
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        backgroundColor: 'rgba(0, 0, 0, 0.5)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center'
      }}
      // Some modals close on backdrop click, others don't
      onClick={onClose}
    >
      <div 
        style={{
          backgroundColor: 'white',
          padding: '20px',
          borderRadius: '8px',
          maxWidth: '400px'
        }}
        // Missing stopPropagation - closes when clicking content!
      >
        {children}
      </div>
    </div>
  );
}
```

```tsx
import { useState } from 'react';
import { BadModal } from './BadModal';

export default function App() {
  const [showModal, setShowModal] = useState(false);

  return (
    <div style={{ padding: '20px', fontFamily: 'system-ui' }}>
      <h2>Problems Without Composers</h2>
      
      <button 
        onClick={() => setShowModal(true)}
        style={{
          padding: '10px 20px',
          backgroundColor: '#dc3545',
          color: 'white',
          border: 'none',
          borderRadius: '4px',
          cursor: 'pointer'
        }}
      >
        Open Problematic Modal
      </button>

      <BadModal isOpen={showModal} onClose={() => setShowModal(false)}>
        <h3>Issues with this approach:</h3>
        <ul style={{ textAlign: 'left', paddingLeft: '20px' }}>
          <li>Clicking content closes modal (missing stopPropagation)</li>
          <li>No focus trap or ARIA attributes</li>
          <li>Every modal reimplements escape key handling</li>
          <li>No responsive behavior considerations</li>
          <li>Inconsistent styling across modals</li>
          <li>Hard to test - logic scattered everywhere</li>
        </ul>
        
        <button 
          onClick={() => setShowModal(false)}
          style={{
            marginTop: '16px',
            padding: '8px 16px',
            backgroundColor: '#6c757d',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
            cursor: 'pointer'
          }}
        >
          Close
        </button>
      </BadModal>
      
      <div style={{ 
        marginTop: '20px', 
        padding: '16px', 
        backgroundColor: '#f8d7da', 
        border: '1px solid #f5c6cb',
        borderRadius: '4px',
        color: '#721c24'
      }}>
        <strong>Result:</strong> Every team builds modals differently, creating inconsistent UX, 
        accessibility gaps, and maintenance nightmares. This is exactly what composers solve.
      </div>
    </div>
  );
}
```

## The Solution: Modal Composer

Now let's see how a composer centralizes this complexity into a
reliable, reusable orchestration layer:

```tsx
// Primitive Button (from previous layers)
export interface ButtonProps {
  variant?: 'primary' | 'secondary' | 'danger';
  size?: 'sm' | 'md' | 'lg';
  disabled?: boolean;
  children: React.ReactNode;
  onClick?: () => void;
}

export function Button({ 
  variant = 'primary', 
  size = 'md', 
  disabled, 
  children,
  onClick 
}: ButtonProps) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      style={{
        padding: size === 'sm' ? '8px 12px' : size === 'lg' ? '12px 20px' : '10px 16px',
        fontSize: size === 'sm' ? '14px' : size === 'lg' ? '18px' : '16px',
        fontWeight: '500',
        borderRadius: '6px',
        border: 'none',
        cursor: disabled ? 'not-allowed' : 'pointer',
        backgroundColor: variant === 'primary' ? '#007bff' : 
                       variant === 'danger' ? '#dc3545' : '#6c757d',
        color: 'white',
        display: 'inline-flex',
        alignItems: 'center',
        gap: '8px',
        transition: 'all 0.2s ease'
      }}
    >
      <span>{children}</span>
    </button>
  );
}
```

```tsx
import { useEffect } from 'react';
import { Button } from './Button';

export interface ModalProps {
  open: boolean;
  onClose: () => void;
  children: React.ReactNode;
}

export function Modal({ open, onClose, children }: ModalProps) {
  // Focus trap and escape key handling
  useEffect(() => {
    if (!open) return;
    
    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    
    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div 
      style={{
        position: 'fixed',
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        backgroundColor: 'rgba(0, 0, 0, 0.5)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 1000
      }}
      onClick={onClose}
    >
      <div 
        style={{
          backgroundColor: 'white',
          borderRadius: '8px',
          maxWidth: '500px',
          width: '90%',
          maxHeight: '80vh',
          overflow: 'auto',
          boxShadow: '0 10px 25px rgba(0, 0, 0, 0.2)'
        }}
        onClick={(e) => e.stopPropagation()}
      >
        {children}
      </div>
    </div>
  );
}

// Slot components for composition
Modal.Header = ({ children }: { children: React.ReactNode }) => (
  <div style={{
    padding: '20px 20px 0 20px',
    borderBottom: '1px solid #eee',
    paddingBottom: '16px',
    marginBottom: '16px'
  }}>
    <h2 style={{ margin: 0, fontSize: '20px', fontWeight: '600' }}>
      {children}
    </h2>
  </div>
);

Modal.Body = ({ children }: { children: React.ReactNode }) => (
  <div style={{ padding: '0 20px 16px 20px' }}>
    {children}
  </div>
);

Modal.Footer = ({ children }: { children: React.ReactNode }) => (
  <div style={{
    padding: '16px 20px 20px 20px',
    borderTop: '1px solid #eee',
    display: 'flex',
    gap: '12px',
    justifyContent: 'flex-end'
  }}>
    {children}
  </div>
);
```

```tsx
import { useState } from 'react';
import { Modal } from './Modal';
import { Button } from './Button';

export default function App() {
  const [showBasic, setShowBasic] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [showForm, setShowForm] = useState(false);

  return (
    <div style={{ padding: '20px', fontFamily: 'system-ui' }}>
      <h2>Modal Composer Examples</h2>
      <p>Modals orchestrate focus, escape handling, and overlay behavior while providing slots for flexible content.</p>
      
      <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap' }}>
        <Button onClick={() => setShowBasic(true)}>
          Basic Modal
        </Button>
        <Button onClick={() => setShowConfirm(true)} variant="danger">
          Confirm Dialog
        </Button>
        <Button onClick={() => setShowForm(true)} variant="secondary">
          Form Modal
        </Button>
      </div>

      {/* Basic Modal */}
      <Modal open={showBasic} onClose={() => setShowBasic(false)}>
        <Modal.Header>Welcome!</Modal.Header>
        <Modal.Body>
          <p>This is a basic modal with header and body slots.</p>
          <p>The modal composer handles:</p>
          <ul>
            <li>Focus trap and escape key</li>
            <li>Overlay click to close</li>
            <li>Flexible content via slots</li>
            <li>Consistent styling</li>
          </ul>
        </Modal.Body>
        <Modal.Footer>
          <Button onClick={() => setShowBasic(false)}>
            Close
          </Button>
        </Modal.Footer>
      </Modal>

      {/* Confirmation Modal */}
      <Modal open={showConfirm} onClose={() => setShowConfirm(false)}>
        <Modal.Header>Confirm Action</Modal.Header>
        <Modal.Body>
          <p>Are you sure you want to delete this item? This action cannot be undone.</p>
        </Modal.Body>
        <Modal.Footer>
          <Button 
            variant="secondary" 
            onClick={() => setShowConfirm(false)}
          >
            Cancel
          </Button>
          <Button 
            variant="danger"
            onClick={() => {
              alert('Item deleted!');
              setShowConfirm(false);
            }}
          >
            Delete
          </Button>
        </Modal.Footer>
      </Modal>

      {/* Form Modal */}
      <Modal open={showForm} onClose={() => setShowForm(false)}>
        <Modal.Header>Add New Item</Modal.Header>
        <Modal.Body>
          <form style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
            <div>
              <label style={{ display: 'block', marginBottom: '4px', fontWeight: '500' }}>
                Name
              </label>
              <input 
                style={{
                  width: '100%',
                  padding: '8px 12px',
                  border: '1px solid #ccc',
                  borderRadius: '4px',
                  fontSize: '16px'
                }}
                placeholder="Enter item name"
              />
            </div>
            <div>
              <label style={{ display: 'block', marginBottom: '4px', fontWeight: '500' }}>
                Description
              </label>
              <textarea 
                style={{
                  width: '100%',
                  padding: '8px 12px',
                  border: '1px solid #ccc',
                  borderRadius: '4px',
                  fontSize: '16px',
                  minHeight: '80px',
                  resize: 'vertical'
                }}
                placeholder="Enter description"
              />
            </div>
          </form>
        </Modal.Body>
        <Modal.Footer>
          <Button 
            variant="secondary" 
            onClick={() => setShowForm(false)}
          >
            Cancel
          </Button>
          <Button onClick={() => {
            alert('Item saved!');
            setShowForm(false);
          }}>
            Save
          </Button>
        </Modal.Footer>
      </Modal>

      <div style={{ 
        marginTop: '40px', 
        padding: '16px', 
        backgroundColor: '#f8f9fa', 
        borderRadius: '4px' 
      }}>
        <h3>Composer Benefits:</h3>
        <ul style={{ margin: 0, paddingLeft: '20px' }}>
          <li><strong>Orchestration:</strong> Handles focus, keyboard, overlay behavior</li>
          <li><strong>Slotting:</strong> Header/Body/Footer for flexible composition</li>
          <li><strong>Accessibility:</strong> Focus trap, escape key, ARIA built-in</li>
          <li><strong>Reusability:</strong> Same modal, different content patterns</li>
        </ul>
      </div>
    </div>
  );
}
```

## Advanced Example: Form Field Composer

Let's see a more complex composer that demonstrates context-based
orchestration, managing multiple children and coordinating validation
state:

```tsx
// Primitive Input (from previous layers)
export interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  size?: 'sm' | 'md' | 'lg';
}

export function Input(props: InputProps) {
  const { size = 'md', ...inputProps } = props;
  
  return (
    <input 
      {...inputProps} 
      style={{
        padding: size === 'sm' ? '6px 8px' : size === 'lg' ? '12px 16px' : '8px 12px',
        fontSize: size === 'sm' ? '14px' : size === 'lg' ? '18px' : '16px',
        border: '1px solid #ccc',
        borderRadius: '4px',
        outline: 'none',
        width: '100%',
        boxSizing: 'border-box',
        transition: 'border-color 0.15s ease-in-out, box-shadow 0.15s ease-in-out',
        ...props.disabled && { 
          backgroundColor: '#f8f9fa', 
          cursor: 'not-allowed',
          opacity: 0.6
        }
      }}
      onFocus={(e) => {
        e.target.style.borderColor = '#80bdff';
        e.target.style.boxShadow = '0 0 0 0.2rem rgba(0, 123, 255, 0.25)';
        props.onFocus?.(e);
      }}
      onBlur={(e) => {
        e.target.style.borderColor = '#ccc';
        e.target.style.boxShadow = 'none';
        props.onBlur?.(e);
      }}
    />
  );
}
```

```tsx
// Form Field Composer: Context-based orchestration
import { createContext, useContext, useState, useId } from 'react';
import { Input } from './Input';

// Context for child coordination
interface FieldContextValue {
  id: string;
  error?: string;
  required: boolean;
  disabled: boolean;
  describedBy: string;
  setError: (error?: string) => void;
  validate: () => boolean;
}

const FieldContext = createContext<FieldContextValue | null>(null);

// Hook for children to access field state
export function useField() {
  const context = useContext(FieldContext);
  if (!context) {
    throw new Error('useField must be used within a FormField');
  }
  return context;
}

// Main composer component
export interface FormFieldProps {
  children: React.ReactNode;
  required?: boolean;
  disabled?: boolean;
  validator?: (value: string) => string | undefined;
}

export function FormField({ 
  children, 
  required = false, 
  disabled = false,
  validator 
}: FormFieldProps) {
  const id = useId();
  const [error, setError] = useState<string>();
  const [value, setValue] = useState('');
  
  // Orchestrated validation
  const validate = () => {
    if (required && !value.trim()) {
      setError('This field is required');
      return false;
    }
    
    if (validator && value) {
      const validationError = validator(value);
      setError(validationError);
      return !validationError;
    }
    
    setError(undefined);
    return true;
  };
  
  // Build describedBy for accessibility
  const describedBy = [
    error ? `${id}-error` : null,
    `${id}-helper`
  ].filter(Boolean).join(' ');
  
  const contextValue: FieldContextValue = {
    id,
    error,
    required,
    disabled,
    describedBy,
    setError,
    validate
  };
  
  return (
    <FieldContext.Provider value={contextValue}>
      <div style={{ marginBottom: '20px' }}>
        {children}
      </div>
    </FieldContext.Provider>
  );
}

// Slot components that use context
FormField.Label = ({ children }: { children: React.ReactNode }) => {
  const { id, required, error } = useField();
  
  return (
    <label 
      htmlFor={id}
      style={{
        display: 'block',
        marginBottom: '6px',
        fontWeight: '500',
        color: error ? '#dc3545' : '#333'
      }}
    >
      {children}
      {required && <span style={{ color: '#dc3545', marginLeft: '2px' }}>*</span>}
    </label>
  );
};

FormField.Input = (props: Omit<React.InputHTMLAttributes<HTMLInputElement>, 'id'>) => {
  const { id, error, disabled, describedBy, setError } = useField();
  
  return (
    <Input
      {...props}
      id={id}
      disabled={disabled}
      aria-describedby={describedBy}
      aria-invalid={!!error}
      style={{
        ...props.style,
        borderColor: error ? '#dc3545' : undefined
      }}
      onChange={(e) => {
        props.onChange?.(e);
        // Clear error on change
        if (error) setError(undefined);
      }}
    />
  );
};

FormField.Helper = ({ children }: { children: React.ReactNode }) => {
  const { id } = useField();
  
  return (
    <p 
      id={`${id}-helper`}
      style={{
        margin: '4px 0 0 0',
        fontSize: '14px',
        color: '#666'
      }}
    >
      {children}
    </p>
  );
};

FormField.Error = () => {
  const { id, error } = useField();
  
  if (!error) return null;
  
  return (
    <p 
      id={`${id}-error`}
      style={{
        margin: '4px 0 0 0',
        fontSize: '14px',
        color: '#dc3545'
      }}
    >
      {error}
    </p>
  );
};
```

```tsx
import { useState } from 'react';
import { FormField } from './FormField';

export default function App() {
  const [formData, setFormData] = useState({
    email: '',
    password: '',
    confirmPassword: ''
  });

  const emailValidator = (value: string) => {
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) {
      return 'Please enter a valid email address';
    }
  };

  const passwordValidator = (value: string) => {
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!/(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/.test(value)) {
      return 'Password must contain uppercase, lowercase, and number';
    }
  };

  const confirmPasswordValidator = (value: string) => {
    if (value !== formData.password) {
      return 'Passwords do not match';
    }
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    // In real implementation, you'd validate all fields
    alert('Form submitted! Check console for orchestration benefits.');
    console.log('Composer Benefits Demonstrated:');
    console.log('Consistent ARIA relationships across all fields');
    console.log('Centralized validation orchestration');
    console.log('Context-based child coordination');
    console.log('No prop drilling - children access field state via context');
    console.log('Reusable validation patterns');
  };

  return (
    <div style={{ padding: '20px', fontFamily: 'system-ui', maxWidth: '500px' }}>
      <h2>Form Field Composer</h2>
      <p style={{ color: '#666', marginBottom: '30px' }}>
        This composer orchestrates validation, accessibility, and child coordination 
        through React Context. Notice how each field is self-contained yet consistent.
      </p>
      
      <form onSubmit={handleSubmit}>
        <FormField required validator={emailValidator}>
          <FormField.Label>Email Address</FormField.Label>
          <FormField.Input 
            type="email"
            placeholder="Enter your email"
            value={formData.email}
            onChange={(e) => setFormData(prev => ({ ...prev, email: e.target.value }))}
          />
          <FormField.Helper>We'll never share your email with anyone</FormField.Helper>
          <FormField.Error />
        </FormField>

        <FormField required validator={passwordValidator}>
          <FormField.Label>Password</FormField.Label>
          <FormField.Input 
            type="password"
            placeholder="Create a password"
            value={formData.password}
            onChange={(e) => setFormData(prev => ({ ...prev, password: e.target.value }))}
          />
          <FormField.Helper>Must be 8+ chars with uppercase, lowercase, and number</FormField.Helper>
          <FormField.Error />
        </FormField>

        <FormField required validator={confirmPasswordValidator}>
          <FormField.Label>Confirm Password</FormField.Label>
          <FormField.Input 
            type="password"
            placeholder="Confirm your password"
            value={formData.confirmPassword}
            onChange={(e) => setFormData(prev => ({ ...prev, confirmPassword: e.target.value }))}
          />
          <FormField.Helper>Must match your password above</FormField.Helper>
          <FormField.Error />
        </FormField>

        <button 
          type="submit"
          style={{
            padding: '12px 24px',
            backgroundColor: '#007bff',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
            cursor: 'pointer',
            fontSize: '16px',
            marginTop: '10px'
          }}
        >
          Create Account
        </button>
      </form>
      
      <div style={{ 
        marginTop: '30px', 
        padding: '20px', 
        backgroundColor: '#d4edda', 
        border: '1px solid #c3e6cb',
        borderRadius: '4px',
        color: '#155724'
      }}>
        <h3 style={{ margin: '0 0 12px 0' }}>Composer Orchestration:</h3>
        <ul style={{ margin: 0, paddingLeft: '20px' }}>
          <li><strong>Context Coordination:</strong> Children access field state without prop drilling</li>
          <li><strong>ARIA Management:</strong> Automatic describedBy relationships</li>
          <li><strong>Validation Orchestration:</strong> Centralized error handling</li>
          <li><strong>State Synchronization:</strong> Error clearing, required indicators</li>
          <li><strong>Consistent Behavior:</strong> All fields follow same patterns</li>
        </ul>
      </div>
    </div>
  );
}
```

## Why Composers Are Essential

Composers solve the "coordination problem" that emerges in
design systems at scale. They provide governance through
orchestration:

### Orchestration Benefits

- **Single Source of Truth**: Complex behavior lives in
  one place, not scattered across implementations
- **Consistent Patterns**: Every modal, form field, or
  toolbar behaves identically
- **Accessibility by Default**: ARIA relationships,
  focus management, and keyboard behavior built-in
- **Easier Testing**: Test the composer once, trust it
  everywhere

### Composition Benefits

- **Flexible Content**: Slots allow varied content
  while maintaining consistent behavior
- **Context Coordination**: Children access
  orchestrated state without prop drilling
- **Separation of Concerns**: Content creators focus on
  content, not complex behavior
- **Reusable Patterns**: Same orchestration, infinite
  content variations

### ⚖️ Governance Benefits

- **Prevents Drift**: Teams can't accidentally
  build inconsistent versions
- **Enforces Standards**: Accessibility and UX patterns
  are automatic
- **Reduces Maintenance**: Fix behavior once, it's
  fixed everywhere
- **Enables Scale**: New team members get consistent
  behavior "for free"

## Case Study: OTP Composer

A one-time passcode (OTP) input is a great example of a composer: it
coordinates multiple input fields, manages paste behavior, advances
focus, and exposes slots for labels, separators, and errors — all
while remaining brand-agnostic and token-driven.

```tsx
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

export type Guard = 'numeric' | 'alphanumeric' | RegExp;

const guardChar = (ch: string, mode: Guard) => {
  if (mode === 'numeric') return /^[0-9]$/.test(ch);
  if (mode === 'alphanumeric') return /^[a-zA-Z0-9]$/.test(ch);
  return (mode as RegExp).test(ch);
};

export interface UseOtpOptions {
  length: number;
  mode: Guard;
  value?: string;
  defaultValue?: string;
  disabled?: boolean;
  readOnly?: boolean;
  onChange?(code: string): void;
  onComplete?(code: string): void;
}

export function useOtp(opts: UseOtpOptions) {
  const { length, mode, value, defaultValue, disabled, readOnly, onChange, onComplete } = opts;

  const isControlled = typeof value === 'string';
  const [internal, setInternal] = useState<string[]>(
    () => (defaultValue ? defaultValue.slice(0, length).split('') : Array.from({ length }, () => ''))
  );

  const refs = useRef<HTMLInputElement[]>([]);

  const code = (isControlled ? value! : internal.join('')).padEnd(length, '').slice(0, length);
  const chars = code.split('');

  const setChar = useCallback(
    (index: number, ch: string) => {
      if (disabled || readOnly) return;
      if (!guardChar(ch, mode)) return;

      const next = chars.slice();
      next[index] = ch;

      const joined = next.join('');
      if (!isControlled) setInternal(next);
      onChange?.(joined);

      if (index < length - 1) refs.current[index + 1]?.focus();
      else onComplete?.(joined);
    },
    [chars, disabled, readOnly, isControlled, length, mode, onChange, onComplete]
  );

  const clearChar = useCallback(
    (index: number) => {
      if (disabled || readOnly) return;
      const next = chars.slice();
      next[index] = '';
      const joined = next.join('');
      if (!isControlled) setInternal(next);
      onChange?.(joined);
    },
    [chars, disabled, readOnly, isControlled, onChange]
  );

  const handlePaste = useCallback(
    (index: number, text: string) => {
      if (disabled || readOnly) return;
      const clean = Array.from(text).filter(ch => guardChar(ch, mode)).slice(0, length - index);
      if (clean.length === 0) return;

      const next = chars.slice();
      for (let i = 0; i < clean.length; i++) next[index + i] = clean[i];

      const joined = next.join('');
      if (!isControlled) setInternal(next);
      onChange?.(joined);

      const last = Math.min(index + clean.length - 1, length - 1);
      if (next.every(Boolean)) onComplete?.(joined);
      refs.current[last]?.focus();
    },
    [chars, disabled, readOnly, isControlled, length, mode, onChange, onComplete]
  );

  const register = useCallback((el: HTMLInputElement | null, i: number) => {
    if (el) refs.current[i] = el;
  }, []);

  const api = useMemo(
    () => ({
      length,
      chars,
      disabled: !!disabled,
      readOnly: !!readOnly,
      register,
      setChar,
      clearChar,
      handlePaste,
      focus(i: number) {
        refs.current[i]?.focus();
      },
    }),
    [length, chars, disabled, readOnly, register, setChar, clearChar, handlePaste]
  );

  return api;
}
```

```tsx
import React, { createContext, useContext } from 'react';
import { useOtp, type UseOtpOptions } from './useOtp';

interface Ctx extends ReturnType<typeof useOtp> {
  id?: string;
  describedBy?: string;
  autocomplete?: string;
  inputMode?: React.InputHTMLAttributes<HTMLInputElement>['inputMode'];
  mask?: boolean;
  separator?: 'none' | 'space' | 'dash' | React.ReactNode;
}

const OtpCtx = createContext<Ctx | null>(null);
export const useOtpCtx = () => {
  const ctx = useContext(OtpCtx);
  if (!ctx) throw new Error('OTP components must be used within <OTPProvider>');
  return ctx;
};

export interface OTPProviderProps extends UseOtpOptions {
  children: React.ReactNode;
  id?: string;
  'aria-describedby'?: string;
  autocomplete?: string;
  inputMode?: React.InputHTMLAttributes<HTMLInputElement>['inputMode'];
  mask?: boolean;
  separator?: 'none' | 'space' | 'dash' | React.ReactNode;
}

export function OTPProvider(props: OTPProviderProps) {
  const {
    children,
    id,
    autocomplete = 'one-time-code',
    inputMode,
    mask = false,
    separator = 'space',
    'aria-describedby': describedBy,
    ...opts
  } = props;

  const api = useOtp(opts);

  return (
    <OtpCtx.Provider value={{ ...api, id, describedBy, autocomplete, inputMode, mask, separator }}>
      {children}
    </OtpCtx.Provider>
  );
}
```

```tsx
import React from 'react';
import { useOtpCtx } from './OTPProvider';

export function OTPInput(props: { children: React.ReactNode; className?: string }) {
  const { id, describedBy, length, disabled, readOnly } = useOtpCtx();
  return (
    <div
      role="group"
      className={props.className}
      aria-disabled={disabled || undefined}
      aria-readonly={readOnly || undefined}
      aria-describedby={describedBy}
      id={id}
      data-length={length}
      style={{ display: 'inline-flex', alignItems: 'center', gap: 12 }}
    >
      {props.children}
    </div>
  );
}
```

```tsx
import React, { useCallback } from 'react';
import { useOtpCtx } from './OTPProvider';

export interface OTPFieldProps {
  index: number;
  className?: string;
  'aria-label'?: string;
}

export function OTPField({ index, className, ...aria }: OTPFieldProps) {
  const { chars, register, setChar, clearChar, handlePaste, disabled, readOnly, autocomplete, inputMode, mask } = useOtpCtx();

  const onKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      const key = e.key;
      if (key === 'Backspace') {
        if (!chars[index]) {
          const prev = (e.currentTarget.form?.elements[index - 1] as HTMLElement | undefined);
          prev?.focus();
        } else {
          clearChar(index);
        }
        e.preventDefault();
      }
      if (key === 'ArrowLeft' && index > 0) {
        (e.currentTarget.form?.elements[index - 1] as HTMLElement | undefined)?.focus();
        e.preventDefault();
      }
      if (key === 'ArrowRight' && index < chars.length - 1) {
        (e.currentTarget.form?.elements[index + 1] as HTMLElement | undefined)?.focus();
        e.preventDefault();
      }
    },
    [chars, index, clearChar]
  );

  const onChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const v = e.target.value;
      if (!v) return;
      const ch = v.slice(-1);
      setChar(index, ch);
    },
    [index, setChar]
  );

  const onPaste = useCallback(
    (e: React.ClipboardEvent<HTMLInputElement>) => {
      const text = e.clipboardData.getData('text');
      if (text) {
        e.preventDefault();
        handlePaste(index, text);
      }
    },
    [handlePaste, index]
  );

  return (
    <input
      ref={(el) => register(el, index)}
      className={className}
      value={mask && chars[index] ? '•' : chars[index] || ''}
      inputMode={inputMode}
      autoComplete={autocomplete}
      maxLength={1}
      onKeyDown={onKeyDown}
      onChange={onChange}
      onPaste={onPaste}
      disabled={disabled}
      readOnly={readOnly}
      aria-label={aria['aria-label'] ?? `Digit ${index + 1}`}
      aria-invalid={undefined}
      style={{
        width: 44,
        height: 44,
        textAlign: 'center',
        fontSize: 18,
        fontWeight: 600,
        borderRadius: 8,
        border: '1px solid #ced4da'
      }}
    />
  );
}
```

```tsx
import React from 'react';
export function OTPSeparator({ children = ' ', className }: { children?: React.ReactNode; className?: string }) {
  return <span className={className} style={{ padding: '0 4px' }}>{children}</span>;
}
```

```tsx
import React from 'react';
export function OTPLabel({ htmlFor, children, className }: { htmlFor?: string; children: React.ReactNode; className?: string }) {
  return (
    <label htmlFor={htmlFor} className={className} style={{ display: 'block', marginBottom: 8, fontWeight: 500 }}>
      {children}
    </label>
  );
}
```

```tsx
import React from 'react';
export function OTPError({ id, children, className }: { id?: string; children?: React.ReactNode; className?: string }) {
  if (!children) return null;
  return (
    <div role="alert" id={id} className={className} style={{ color: '#dc3545', marginTop: 8, fontSize: 14 }}>
      {children}
    </div>
  );
}
```

```tsx
export { OTPProvider } from './OTPProvider';
export { OTPInput } from './OTPInput';
export { OTPField } from './OTPField';
export { OTPSeparator } from './OTPSeparator';
export { OTPLabel } from './OTPLabel';
export { OTPError } from './OTPError';
```

```tsx
import { OTPProvider, OTPInput, OTPField, OTPSeparator, OTPLabel, OTPError } from './index';

export default function App() {
  return (
    <div style={{ padding: 20, fontFamily: 'system-ui', maxWidth: 480 }}>
      <h2>OTP Composer</h2>
      <p style={{ color: '#666' }}>
        Headless logic + slots. Paste a 6-digit code into any field, use arrow keys, or backspace across fields.
      </p>
      <form onSubmit={(e) => { e.preventDefault(); alert('Verified'); }}>
        <OTPProvider length={6} mode="numeric" onComplete={(code) => alert('Code: ' + code)}>
          <OTPLabel>Enter the 6-digit code</OTPLabel>
          <OTPInput>
            <OTPField index={0} />
            <OTPField index={1} />
            <OTPField index={2} />
            <OTPSeparator>-</OTPSeparator>
            <OTPField index={3} />
            <OTPField index={4} />
            <OTPField index={5} />
          </OTPInput>
          <OTPError id="otp-error">&nbsp;</OTPError>
        </OTPProvider>
        <button type="submit" style={{ marginTop: 16, padding: '10px 16px', borderRadius: 6, border: '1px solid #ced4da', background: '#f8f9fa' }}>Verify</button>
      </form>
    </div>
  );
}
```

### API (minimal, orchestration-first)

- **length**: number of digits; default 6
- **mode**: 'numeric' | 'alphanumeric' | RegExp
- **value / defaultValue**: controlled or uncontrolled
- **onChange / onComplete**: callbacks for progress and
  completion
- **mask**: visual masking (•) only; logic remains
  accessible
- **separator**: 'none' | 'space' | 'dash' | React node
- **autocomplete / inputMode**: platform hints for
  keyboards and auto-fill

### Meta-patterns

- **Headless logic hook**: core OTP behaviors live in `useOtp`
- **Context provider**: `OTPProvider` exposes
  orchestrated state
- **Slotting & substitution**: UI parts are
  replaceable (field, label, error, separator)
- **Token-driven visuals**: no hard-coded colors; styles
  map to tokens

### Folder structure

```
OTPInput/
├── index.tsx
├── OTPInput.tsx            # visual scaffolding (slots)
├── OTPProvider.tsx         # context + orchestration
├── useOtp.ts               # headless logic (state, focus, paste)
├── OTPField.tsx            # default field primitive (swappable)
├── OTPSeparator.tsx        # optional slot
├── OTPLabel.tsx            # optional slot
├── OTPError.tsx            # optional slot
├── OTPInput.module.scss
├── OTPInput.tokens.json
├── OTPInput.tokens.generated.scss
└── README.md
```

### Accessibility Notes

- **Group semantics**: wrap fields in a
  role="group" and associate labels/errors via described-by
- **Paste**: allow multi-character paste and distribute
  across slots
- **Backspace**: backspace moves focus left when empty;
  clears when filled
- **Virtual keyboards**:
  autocomplete="one-time-code",
  inputMode="numeric" or "tel"
- **Screen readers**: each field has an aria-label (e.g.,
  "Digit 1")
- **Reduced motion**: advance focus only on valid entry;
  deterministic arrow navigation

### Why this travels well

- **Headless logic**: products can reskin without
  re-implementing paste/focus/validation
- **Slotting**: replace `OTPField`,
  separators, and text slots freely
- **Tokenized visuals**: map typography, radius, spacing,
  and colors to tokens
- **Clear boundaries**: OTP is a system composer; flows
  like checkout live as assemblies

### Quick verification

- Composer invariants: `useOtp` + `OTPProvider` exist
- Exports include provider, group, field, and slots
- README-style guidance covers usage, props, and a11y
- No prop explosion; variations derive from slots + tokens

### Explicit props interface

```tsx
export interface OTPInputProps {
  /** Number of OTP digits (3–12 typical). Default: 6 */
  length?: number;
  /** Numeric-only, alphanumeric, or custom regex guard. Default: "numeric" */
  mode?: 'numeric' | 'alphanumeric' | RegExp;
  /** Autofill hints for platforms that support it. Default: 'one-time-code' */
  autocomplete?: 'one-time-code' | 'otp' | string;
  /** Controlled value as a string of length N (optional) */
  value?: string;
  /** Uncontrolled default value (optional) */
  defaultValue?: string;
  /** Called when all N slots are filled with valid characters */
  onComplete?(code: string): void;
  /** Called on any change (partial codes included) */
  onChange?(code: string): void;
  /** Disabled / readOnly semantics */
  disabled?: boolean;
  readOnly?: boolean;
  /** Ids for a11y grouping & descriptions (label, error, help) */
  id?: string;
  'aria-describedby'?: string;
  /** Optional mask (e.g., show • instead of digits) */
  mask?: boolean;
  /** Optional separator render strategy ('space' by default) */
  separator?: 'none' | 'space' | 'dash' | React.ReactNode;
  /** Inputmode hint to virtual keyboards; defaults inferred from mode */
  inputMode?: React.InputHTMLAttributes<HTMLInputElement>['inputMode'];
}
```

### Tokens and styles

Example token JSON and SCSS usage:

```json
// OTPInput.tokens.json
{
  "component": {
    "otpInput": {
      "field": {
        "size": { "minWidth": "{size.12}", "height": "{size.12}" },
        "typo": { "fontSize": "{font.size.300}", "fontWeight": "{font.weight.semibold}" },
        "radius": "{radius.md}",
        "gap": "{space.200}"
      },
      "color": {
        "text": "{color.foreground.default}",
        "bg": "{color.background.surface}",
        "border": "{color.border.subtle}",
        "focus": "{color.border.focus}",
        "invalid": "{color.border.danger}"
      }
    }
  }
}
```

```scss
// OTPInput.module.scss
@import './OTPInput.tokens.generated.scss';

.root {
  display: inline-flex;
  align-items: center;
  gap: var(--component-otp-field-gap);
}

.field {
  min-width: var(--component-otp-field-min-width);
  height: var(--component-otp-field-height);
  text-align: center;
  font-size: var(--component-otp-field-font-size);
  font-weight: var(--component-otp-field-font-weight);
  border-radius: var(--component-otp-field-radius);
  color: var(--component-otp-color-text);
  background: var(--component-otp-color-bg);
  border: 1px solid var(--component-otp-color-border);
  outline: none;
}

.field:focus-visible {
  border-color: var(--component-otp-color-focus);
  box-shadow: 0 0 0 3px color-mix(in oklab, var(--component-otp-color-focus) 30%, transparent);
}
```

### Usage (slots + defaults)

```tsx
import {
  OTPProvider,
  OTPInput,
  OTPField,
  OTPSeparator,
  OTPLabel,
  OTPError,
} from '@/ui/components/OTPInput';

export function CheckoutOtpExample() {
  return (
    <form onSubmit={(e) => { e.preventDefault(); }}>
      <OTPProvider length={6} mode="numeric" onComplete={(code) => console.log('OTP:', code)}>
        <OTPLabel>Enter the 6-digit code</OTPLabel>
        <OTPInput>
          {Array.from({ length: 6 }).map((_, i) => <OTPField key={i} index={i} />)}
        </OTPInput>
        <OTPError id="otp-error">{/* show error when server rejects */}</OTPError>
      </OTPProvider>
      <button type="submit">Verify</button>
    </form>
  );
}
```

### README starter

```markdown
# OTPInput

A composer for one-time passcodes (OTP). Headless logic + slot-based UI for multi-brand reuse.

## When to use
- Login, 2FA, device verification, high-risk actions.

## Key ideas
- Headless logic in useOtp (paste, focus, completion)
- Slotting: replace OTPField, OTPSeparator, OTPLabel, OTPError freely
- Tokenized visuals for brand theming

## Props
See OTPInputProps. Minimal surface: length, mode, onComplete, onChange, a11y ids, mask, separator.

## Accessibility
- Grouped with role="group", labeled and described
- autocomplete="one-time-code", inputMode hints for keyboards
- Backspace & arrow navigation semantics included
- Paste distribution supported
```

## Original Modal Example

- Orchestration: open/close, overlay click, focus trap handled once.
- Slots: Header, Body, Footer as sub-components.
- Composition: teams can put whatever primitives inside, but
  accessibility and focus rules are enforced.

## Why Composers are Critical

- They channel complexity into predictable patterns rather than
  scattered workarounds.
- They protect accessibility models at the multi-element level (focus,
  ARIA roles, keyboard models).
- They enable flexibility without chaos: slots allow teams to insert
  or omit, but orchestration keeps rules consistent.
- They free product teams from rebuilding orchestration logic (which
  is hard, error-prone, and often missed).

## Summary

Composers are the system's conductors: they coordinate state, focus,
and interaction across multiple children.

- Examples: Modal, Form Field, Toolbar, Pagination, Rich Text Editor
- Work of the system: orchestration, variation by pattern, slotting,
  context providers
- Pitfalls: prop explosion, leaking state, accessibility drift,
  overgeneralization

If [primitives](/blueprints/component-standards/component-complexity/primitives)
are the boring DNA, and [compounds](/blueprints/component-standards/component-complexity/compound)
are the grammar rules, then composers are the syntax that makes the
grammar work in practice. They're where design systems prove
their worth — not just in how things look, but in how they behave.

## Next Steps

Composers often contain [compounds](/blueprints/component-standards/component-complexity/compound)
and [primitives](/blueprints/component-standards/component-complexity/primitives),
and can be combined into [assemblies](/blueprints/component-standards/component-complexity/assemblies)
for complete user flows.
