# Deep Dive: Compounds

## Why Compounds Exist

If primitives are the raw parts, compounds are the predictable
bundles. They emerge when teams repeatedly combine the same
primitives in the same ways. Instead of asking designers and
developers to reinvent the bundle every time, the system codifies
the convention.

Compounds give structure to combinations that look obvious in
hindsight but are fragile in practice. A text input always needs a
label. A table row always assumes a parent table. A card usually
pairs heading, body, and actions in a fixed layout.

The compound layer is where convention becomes codified.

## Characteristics of Compounds

- Predictable combinations: the system says, "these primitives
  always travel together."
- Narrow scope: compounds aren't meant to anticipate every
  combination—only the blessed ones.
- Stable defaults: compounds take care of padding, grouping, or
  spacing rules once, so teams don't keep tweaking.
- Consistent behavior: accessibility rules (like label
  associations) are guaranteed, not optional.

## Examples of Compounds

- TextField: bundles Input, Label, ErrorMessage.
- TableRow: bundles TableCell primitives with semantics tied to
  Table.
- Card: bundles Heading, Body, Footer with standardized spacing.
- Tag / Chip: bundles Label and DismissButton.

## The Work of the System at the Compound Layer

### 1. Conventions

- Define what belongs together: label + input, icon + text, header
  + footer.
- Define approved variations (e.g., TextField can have optional
  helper text, but never hides the label).

### 2. Blessed Combinations

- Encode spacing, order, and accessibility rules into the
  compound.
- Example: a TextField enforces label placement and
  aria-describedby linking to the error state.

### 3. Flexibility Without Drift

- Compounds should allow a controlled amount of flexibility
  (slots, optional props).
- The key is to prevent unbounded prop creep—flexibility should
  follow the system's conventions.

## Pitfalls of Compounds

1. **Prop Explosion**
   - When compounds try to solve every variation, they mutate
     into composers.
   - Guardrail: compounds support only the blessed variations. If
     you find yourself adding a boolean every sprint, you've
     crossed layers.

2. **Breaking Accessibility by Accident**
   - A text field without a proper <label> or
     aria-describedby is a broken compound.
   - Guardrail: accessibility associations must be baked in, not
     optional.

3. **Over-abstracting Visuals**
   - Avoid infinite layout variations. For instance, a Card that
     allows every combination of header/body/footer permutations
     becomes ungovernable.
   - Guardrail: fix the expected structure, allow slots for
     content.

4. **Duplication of Logic**
   - Don't reimplement primitive behaviors inside compounds
     (e.g., don't reinvent Checkbox logic inside a "FilterRow"
     compound).
   - Guardrail: compounds compose primitives; they don't replace
     them.

## Example: TextField

```tsx
// Primitive Input component (from previous layer)
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
        ...props.disabled && {
          backgroundColor: '#f5f5f5',
          cursor: 'not-allowed'
        }
      }}
      onFocus={(e) => {
        e.target.style.borderColor = '#007bff';
        e.target.style.boxShadow = '0 0 0 2px rgba(0, 123, 255, 0.25)';
      }}
      onBlur={(e) => {
        e.target.style.borderColor = '#ccc';
        e.target.style.boxShadow = 'none';
      }}
    />
  );
}
```

```tsx
import { Input } from './Input';

export interface TextFieldProps {
  id: string;
  label: string;
  error?: string;
  helperText?: string;
  required?: boolean;
  placeholder?: string;
  disabled?: boolean;
}

export function TextField({
  id,
  label,
  error,
  helperText,
  required,
  placeholder,
  disabled
}: TextFieldProps) {
  const describedBy = [
    error ? `${id}-error` : null,
    helperText ? `${id}-helper` : null
  ].filter(Boolean).join(' ') || undefined;

  return (
    <div style={{ marginBottom: '16px' }}>
      <label
        htmlFor={id}
        style={{
          display: 'block',
          marginBottom: '4px',
          fontWeight: '500',
          color: error ? '#dc3545' : '#333'
        }}
      >
        {label}
        {required && <span style={{ color: '#dc3545' }}>*</span>}
      </label>

      <Input
        id={id}
        placeholder={placeholder}
        disabled={disabled}
        aria-describedby={describedBy}
        aria-invalid={!!error}
        style={{
          borderColor: error ? '#dc3545' : undefined
        }}
      />

      {helperText && (
        <p
          id={`${id}-helper`}
          style={{
            margin: '4px 0 0 0',
            fontSize: '14px',
            color: '#666'
          }}
        >
          {helperText}
        </p>
      )}

      {error && (
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
      )}
    </div>
  );
}
```

```tsx
import { TextField } from './TextField';
import { useState } from 'react';

export default function App() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [errors, setErrors] = useState<{email?: string; password?: string}>({});

  const validateEmail = (value: string) => {
    if (!value) return 'Email is required';
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) return 'Invalid email format';
    return '';
  };

  const validatePassword = (value: string) => {
    if (!value) return 'Password is required';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return '';
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const emailError = validateEmail(email);
    const passwordError = validatePassword(password);

    setErrors({
      email: emailError,
      password: passwordError
    });

    if (!emailError && !passwordError) {
      alert('Form submitted successfully!');
    }
  };

  return (
    <div style={{ padding: '20px', fontFamily: 'system-ui', maxWidth: '400px' }}>
      <h2>TextField Compound Examples</h2>

      <form onSubmit={handleSubmit}>
        <TextField
          id="email"
          label="Email Address"
          placeholder="Enter your email"
          required
          error={errors.email}
          helperText="We'll never share your email"
        />

        <TextField
          id="password"
          label="Password"
          placeholder="Enter your password"
          required
          error={errors.password}
          helperText="Must be at least 6 characters"
        />

        <TextField
          id="optional"
          label="Optional Field"
          placeholder="This field is optional"
          helperText="You can skip this if you want"
        />

        <TextField
          id="disabled"
          label="Disabled Field"
          placeholder="This field is disabled"
          disabled
          helperText="This field cannot be edited"
        />

        <button
          type="submit"
          style={{
            padding: '10px 20px',
            backgroundColor: '#007bff',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
            cursor: 'pointer',
            marginTop: '16px'
          }}
        >
          Submit
        </button>
      </form>

      <div style={{ marginTop: '20px', padding: '16px', backgroundColor: '#f8f9fa', borderRadius: '4px' }}>
        <h3>Compound Benefits:</h3>
        <ul style={{ margin: 0, paddingLeft: '20px' }}>
          <li>✅ Bundles Input + Label + Error + Helper</li>
          <li>✅ Consistent accessibility (aria-describedby)</li>
          <li>✅ Standardized spacing and styling</li>
          <li>✅ Reduces repetitive markup</li>
        </ul>
      </div>
    </div>
  );
}
```

- The Input primitive is still used, but labeling, error
  messaging, and helper text are orchestrated once.
- Teams now can't "forget" accessibility—they inherit it
  automatically.

## Why Compounds are Critical

- They reduce cognitive load: designers and engineers don't have
  to reassemble primitives every time.
- They prevent inconsistent conventions: spacing, order,
  accessibility are centralized.
- They free the system team from triaging endless one-offs: by
  pre-blessing common bundles, the system reduces churn.
- They create legibility in design files and codebases:
  "TextField" communicates intent better than "Input + Label +
  Error stacked manually."

## Summary

Compounds are the codified bundles of your design system.

- Examples: TextField, TableRow, Card, Chip
- Work of the system: conventions, blessed combinations, baked-in
  accessibility
- Pitfalls: prop explosion, accessibility drift, ungoverned
  permutations, logic duplication

If [primitives](/blueprints/component-standards/component-complexity/primitives)
are the boring DNA, compounds are the grammar rules—they make sure
the words can be combined into predictable, legible sentences.

## Next Steps

Compounds work well on their own, but they really shine when
orchestrated by [composers](/blueprints/component-standards/component-complexity/composer)
or combined into [assemblies](/blueprints/component-standards/component-complexity/assemblies).
