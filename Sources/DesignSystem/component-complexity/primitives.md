# Deep Dive: Primitives in Design Systems

## Why Primitives Matter

Primitives are the ground floor of any design system. They're the
atoms: the smallest irreducible components that represent a single
design decision. Buttons, inputs, checkboxes, icons, typographic
elements—each is small enough to feel trivial, but together they form
the grammar of every interface.

The paradox of primitives is that their importance is inversely
proportional to their excitement. The most boring components—when
standardized and consistent—enable the most creative outcomes at
higher layers. When they're unstable or inconsistent, complexity
compounds exponentially across compounds, composers, and assemblies.

That's why primitives must be:

- **Stable**: their APIs change rarely, because every
  downstream component depends on them.
- **Accessible**: they bake in baseline ARIA and keyboard
  support, so teams can't "forget" the fundamentals.
- **Consistent**: they enforce token usage and naming
  conventions that ripple through the entire system.

In short: primitives must be boring, so everything above them can be
interesting.

## The Work of Primitives

### 1. Standards and Naming

Primitives encode standards into the system. A Button isn't just a
clickable element—it carries naming conventions, semantic intent, and
design tokens for states (default, hover, active, disabled).

- Correct naming avoids confusion: ButtonPrimary vs. ButtonSecondary
  is clearer than BlueButton vs. GrayButton.
- Token references ensure consistency: `--color-action-primary` instead of `#0055ff`.

### 2. Tokens as DNA

Every primitive should consume tokens, not hardcoded values. This
links design intent directly to code and allows system-wide theming
without rewrites.

- Typography primitives consume `font.size`, `font.weight`, `line-height`.
- Inputs consume `color.border`, `radius.sm`, `space.200`.
- Buttons consume `color.background.brand`, `color.foreground.onBrand`.

### 3. Accessibility Baselines

Primitives are the system's first line of accessibility defense.

- Buttons must always be focusable, keyboard-activatable, and
  screen-reader friendly.
- Inputs must handle labels, ARIA attributes, and states like disabled
  and required.
- Checkboxes must be operable with space/enter, expose
  checked/indeterminate states, and be properly labelled.

Because these patterns are embedded in primitives, downstream teams
don't have to learn them anew for every feature.

## Why "Boring" is Strategic

It's tempting to make primitives expressive—throw in clever styles,
animations, or flexible APIs. But "boring" primitives are what make
them reliable:

- A boring button doesn't surprise you with odd hover logic.
- A boring input doesn't embed its own form validation rules.
- A boring icon doesn't ship 50 variants of its own sizing model.

By being boring, primitives are predictable. Predictability is what
allows compounds and composers to flourish without constantly patching
or rethinking the foundation.

## Examples in Practice

```tsx
// ✅ A properly boring Button primitive
export interface ButtonProps {
  /** Visual weight of the button */
  variant?: 'primary' | 'secondary' | 'danger';
  /** Size of the button */
  size?: 'sm' | 'md' | 'lg';
  /** Disabled state */
  disabled?: boolean;
  /** Optional loading spinner */
  isLoading?: boolean;
  /** Button content */
  children: React.ReactNode;
  /** Click handler */
  onClick?: () => void;
  /** Button type for forms */
  type?: 'button' | 'submit' | 'reset';
}

export function Button({ 
  variant = 'primary', 
  size = 'md', 
  disabled, 
  isLoading, 
  children,
  onClick,
  type = 'button'
}: ButtonProps) {
  return (
    <button
      type={type}
      className={`btn btn-${variant} btn-${size}`}
      disabled={disabled || isLoading}
      onClick={onClick}
      style={{
        padding: size === 'sm' ? '8px 12px' : size === 'lg' ? '12px 20px' : '10px 16px',
        fontSize: size === 'sm' ? '14px' : size === 'lg' ? '18px' : '16px',
        fontWeight: '500',
        borderRadius: '6px',
        border: 'none',
        cursor: disabled || isLoading ? 'not-allowed' : 'pointer',
        opacity: disabled ? 0.6 : 1,
        backgroundColor: variant === 'primary' ? '#007bff' : 
                       variant === 'danger' ? '#dc3545' : '#6c757d',
        color: 'white',
        display: 'inline-flex',
        alignItems: 'center',
        gap: '8px',
        transition: 'all 0.2s ease'
      }}
    >
      {isLoading && (
        <span 
          style={{
            width: '14px',
            height: '14px',
            border: '2px solid currentColor',
            borderTop: '2px solid transparent',
            borderRadius: '50%',
            animation: 'spin 1s linear infinite'
          }}
          aria-hidden="true"
        />
      )}
      <span>{children}</span>
    </button>
  );
}
```

```tsx
// ✅ A properly boring Input primitive (no labels/errors)
export interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  /** Visual size */
  size?: 'sm' | 'md' | 'lg';
}

export function Input(props: InputProps) {
  const { size = 'md', ...inputProps } = props;
  
  return (
    <input 
      {...inputProps} 
      className={`input input-${size}`}
      style={{
        padding: size === 'sm' ? '6px 8px' : size === 'lg' ? '12px 16px' : '8px 12px',
        fontSize: size === 'sm' ? '14px' : size === 'lg' ? '18px' : '16px',
        border: '1px solid #ced4da',
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
        e.target.style.borderColor = '#ced4da';
        e.target.style.boxShadow = 'none';
        props.onBlur?.(e);
      }}
    />
  );
}
```

```tsx
// ✅ A properly boring Checkbox primitive
import { useState } from 'react';

export interface CheckboxProps {
  /** Whether the checkbox is checked */
  checked?: boolean;
  /** Default checked state for uncontrolled usage */
  defaultChecked?: boolean;
  /** Whether the checkbox is in indeterminate state */
  indeterminate?: boolean;
  /** Whether the checkbox is disabled */
  disabled?: boolean;
  /** Size of the checkbox */
  size?: 'sm' | 'md' | 'lg';
  /** Change handler */
  onChange?: (checked: boolean) => void;
  /** ARIA label for accessibility */
  'aria-label'?: string;
  /** ID for label association */
  id?: string;
}

export function Checkbox({
  checked,
  defaultChecked = false,
  indeterminate = false,
  disabled = false,
  size = 'md',
  onChange,
  'aria-label': ariaLabel,
  id
}: CheckboxProps) {
  const [internalChecked, setInternalChecked] = useState(defaultChecked);
  const isControlled = checked !== undefined;
  const isChecked = isControlled ? checked : internalChecked;
  
  const handleChange = () => {
    if (disabled) return;
    
    const newChecked = !isChecked;
    if (!isControlled) {
      setInternalChecked(newChecked);
    }
    onChange?.(newChecked);
  };
  
  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === ' ' || e.key === 'Enter') {
      e.preventDefault();
      handleChange();
    }
  };
  
  const sizeStyles = {
    sm: { width: '14px', height: '14px' },
    md: { width: '16px', height: '16px' },
    lg: { width: '20px', height: '20px' }
  };
  
  return (
    <div
      role="checkbox"
      aria-checked={indeterminate ? 'mixed' : isChecked}
      aria-label={ariaLabel}
      id={id}
      tabIndex={disabled ? -1 : 0}
      onClick={handleChange}
      onKeyDown={handleKeyDown}
      style={{
        ...sizeStyles[size],
        backgroundColor: isChecked || indeterminate ? '#007bff' : 'white',
        border: '2px solid #007bff',
        borderRadius: '3px',
        cursor: disabled ? 'not-allowed' : 'pointer',
        opacity: disabled ? 0.6 : 1,
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        outline: 'none',
        transition: 'all 0.15s ease'
      }}
    >
      {indeterminate ? (
        <div style={{
          width: '60%',
          height: '2px',
          backgroundColor: 'white'
        }} />
      ) : isChecked ? (
        <svg 
          width="12" 
          height="12" 
          viewBox="0 0 12 12" 
          fill="none"
          style={{ color: 'white' }}
        >
          <path 
            d="M10 3L4.5 8.5L2 6" 
            stroke="currentColor" 
            strokeWidth="2" 
            strokeLinecap="round" 
            strokeLinejoin="round"
          />
        </svg>
      ) : null}
    </div>
  );
}
```

```tsx
import { useState } from 'react';
import { Button } from './Button';
import { Input } from './Input';
import { Checkbox } from './Checkbox';

export default function App() {
  const [inputValue, setInputValue] = useState('');
  const [isChecked, setIsChecked] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  const handleSubmit = () => {
    setIsLoading(true);
    setTimeout(() => {
      alert(`Form submitted with: "${inputValue}" (checked: ${isChecked})`);
      setIsLoading(false);
    }, 2000);
  };

  return (
    <div style={{ padding: '20px', fontFamily: 'system-ui', maxWidth: '600px' }}>
      <style>{`
        @keyframes spin {
          0% { transform: rotate(0deg); }
          100% { transform: rotate(360deg); }
        }
      `}</style>
      
      <h2>Primitive Components Example</h2>
      <p style={{ color: '#666', marginBottom: '30px' }}>
        These primitives are boring by design. They handle the fundamentals 
        (accessibility, tokens, consistency) so higher layers can be creative.
      </p>

      <div style={{ marginBottom: '20px' }}>
        <h3>Button Primitives</h3>
        <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap', marginBottom: '16px' }}>
          <Button size="sm">Small</Button>
          <Button>Medium (default)</Button>
          <Button size="lg">Large</Button>
        </div>
        <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap', marginBottom: '16px' }}>
          <Button variant="primary">Primary</Button>
          <Button variant="secondary">Secondary</Button>
          <Button variant="danger">Danger</Button>
        </div>
        <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap' }}>
          <Button disabled>Disabled</Button>
          <Button isLoading={isLoading} onClick={handleSubmit}>
            {isLoading ? 'Submitting...' : 'Submit Form'}
          </Button>
        </div>
      </div>

      <div style={{ marginBottom: '20px' }}>
        <h3>Input Primitive</h3>
        <p style={{ marginBottom: '8px', fontSize: '14px', color: '#666' }}>
          Note: Labels and errors are handled by compounds, not primitives
        </p>
        <Input
          placeholder="Enter some text..."
          value={inputValue}
          onChange={(e) => setInputValue(e.target.value)}
          style={{ marginBottom: '8px' }}
        />
        <div style={{ display: 'flex', gap: '12px' }}>
          <Input size="sm" placeholder="Small input" />
          <Input size="lg" placeholder="Large input" />
          <Input disabled placeholder="Disabled input" />
        </div>
      </div>

      <div style={{ marginBottom: '30px' }}>
        <h3>Checkbox Primitive</h3>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
          <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}>
            <Checkbox
              checked={isChecked}
              onChange={setIsChecked}
              aria-label="Accept terms"
            />
            <span>I accept the terms and conditions</span>
          </label>

          <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}>
            <Checkbox
              indeterminate={true}
              aria-label="Partially selected"
            />
            <span>Indeterminate state (mixed selection)</span>
          </label>

          <div style={{ display: 'flex', gap: '16px', alignItems: 'center' }}>
            <label style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <Checkbox size="sm" aria-label="Small checkbox" />
              <span>Small</span>
            </label>
            <label style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <Checkbox size="md" aria-label="Medium checkbox" />
              <span>Medium</span>
            </label>
            <label style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <Checkbox size="lg" aria-label="Large checkbox" />
              <span>Large</span>
            </label>
            <label style={{ display: 'flex', alignItems: 'center', gap: '8px', opacity: 0.6 }}>
              <Checkbox disabled aria-label="Disabled checkbox" />
              <span>Disabled</span>
            </label>
          </div>
        </div>
      </div>

      <div style={{
        padding: '20px',
        backgroundColor: '#f8f9fa',
        borderRadius: '8px',
        border: '1px solid #e9ecef'
      }}>
        <h3 style={{ margin: '0 0 12px 0' }}>✅ Primitive Benefits:</h3>
        <ul style={{ margin: 0, paddingLeft: '20px' }}>
          <li><strong>Boring & Predictable:</strong> No surprising behaviors or edge cases</li>
          <li><strong>Token-Driven:</strong> Colors, spacing, and typography use design tokens</li>
          <li><strong>Accessible by Default:</strong> ARIA attributes, keyboard support, focus states</li>
          <li><strong>Stable APIs:</strong> Minimal props focused on intrinsic variations only</li>
          <li><strong>Composable:</strong> Can be safely used in compounds and composers</li>
        </ul>
      </div>
    </div>
  );
}
```

## Pitfalls of Primitives

### 1. Bloated Props

A primitive is not meant to cover every use case. Overloading a Button
with every possible prop ("size, variant, tone, emphasis, density,
iconPosition, isLoading, isGhost, isText, isIconOnly, shape,
animation, elevation…") is a sign that you're asking a primitive to do
compound or composer work.

**Guardrail:** primitives should expose only intrinsic
variations. For Button, that might be:
- `size` (sm, md, lg)
- `variant` (primary, secondary, danger)
- `state` (disabled, loading)

### 2. Reinventing Label/Error Logic

Inputs are especially prone to this. A TextInput primitive should not
reinvent labels or error messaging inside itself. That's the job of a
Field composer. Mixing these concerns creates duplicated accessibility
bugs and inconsistent UX.

### 3. Skipping Tokens

A primitive that uses hex codes or inline styles instead of tokens
creates technical debt: theming, dark mode, and cross-brand parity all
break downstream.

### 4. "Cute" or Over-Styled Primitives

Primitives should be boring. Introducing expressive styles (gradients,
shadows, animations) into primitives makes them fragile.
Expressiveness belongs in compounds, composers, or product
assemblies—not in the atomic layer.

## Why Standards at the Primitive Layer Matter

- **Ripple effects:** A poorly built primitive button
  means every compound (modal footers, toolbars) inherits bad
  accessibility.
- **Trust:** If designers and engineers can't trust the
  button, they'll fork their own, and the system fragments.
- **Economy of scale:** Fixes are cheapest at the
  primitive layer. One token update, thousands of instances improved.

If you get primitives right:

- Accessibility, consistency, and tokens scale automatically across
  compounds and composers.
- Designers and developers think less about the basics and more about
  solving domain problems.
- Your system becomes the default choice because it's easier to use
  than to reimplement.

## Summary

Primitives are irreducible, boring, and essential. They demand
standards because they set the foundation on which all compounds,
composers, and assemblies depend. Their role is not to be
expressive—it's to be predictable, tokenized, and accessible.

- **Examples:** Button, Input, Checkbox, Icon
- **Work of the system:** naming, tokens, accessibility
  patterns
- **Pitfalls:** bloated props, reinventing label/error
  logic, skipping tokens, over-styling

In the layered methodology, primitives are the only layer where
"boring is a feature, not a bug." Their discipline is what allows the
more complex layers—compounds, composers, and assemblies—to flourish
without collapsing under exceptions.

## Next Steps

Primitives are designed to be composed into [compounds](/blueprints/component-standards/component-complexity/compound),
orchestrated by [composers](/blueprints/component-standards/component-complexity/composer),
and assembled into [assemblies](/blueprints/component-standards/component-complexity/assemblies).
Their boring reliability is what makes the higher layers possible.
