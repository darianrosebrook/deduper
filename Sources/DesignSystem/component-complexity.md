# Designing with Layers: A Systems Approach to Components

When design systems first take root, they begin with components:
buttons, inputs, icons, toggles. The goal is consistency, but
consistency alone doesn't explain why complexity creeps in. Over time,
you notice the neat catalog breaks down: forms behave differently
across contexts, toolbars overflow with actions, editors sprout
feature walk-throughs, and pagination mutates with ellipses and
compact modes.

The problem isn't that your system is "messy." The problem
is that you're seeing composition at work. Complexity in digital
interfaces rarely comes from primitives themselves—it emerges when
small parts are combined, orchestrated, and pushed against application
workflows.

To build systems that endure, you need a lens that helps you
anticipate this layering before it manifests in code. That's what the
layered component methodology provides: a way to classify, compose,
and govern components across four levels of scale.

## The Four Layers of Components

### 1. [Primitives](/blueprints/component-standards/component-complexity/primitives)

Primitives are the ground floor: irreducible building blocks like
buttons, text inputs, checkboxes, icons, and typographic elements.
Their goals are stability, accessibility, and consistency. They should
be as "boring" as possible.

**Examples:**
- Button, Input, Checkbox, Icon

**Work of the system:**
- naming, tokens, accessibility patterns

**Pitfalls:**
- bloated props, reinventing label or error logic inside each input

→ Deep dive into Primitives

### 2. [Compounds](/blueprints/component-standards/component-complexity/compound)

Compounds bundle [primitives](/blueprints/component-standards/component-complexity/primitives)
into predictable, reusable groupings. They codify conventions and
reduce repeated decision-making.

**Examples:**
- TextField (input + label + error), TableRow, Card

**Work of the system:**
- defining which sub-parts exist, providing safe variations

**Pitfalls:**
- "mega-props" that attempt to account for every variation

→ Deep dive into Compounds

### 3. [Composers](/blueprints/component-standards/component-complexity/composer)

Composers orchestrate state, interaction, and context across multiple
children. This is where systems meet complexity: modals, toolbars,
message composers, pagination. They often contain [compounds](/blueprints/component-standards/component-complexity/compound)
and [primitives](/blueprints/component-standards/component-complexity/primitives).

**Examples:**
- Modal, Form Field (with label/error orchestration), Toolbar,
  Pagination, Rich Text Editor

**Work of the system:**
- governing orchestration, exposing slots, avoiding prop explosion

**Pitfalls:**
- burying orchestration in ad-hoc props instead of a clear context
  model

→ Deep dive into Composers

### 4. [Assemblies](/blueprints/component-standards/component-complexity/assemblies)

Assemblies are application-specific flows encoded as components. They
aren't universal system primitives; they're product
constructs that use the system's [primitives](/blueprints/component-standards/component-complexity/primitives),
[compounds](/blueprints/component-standards/component-complexity/compound),
and [composers](/blueprints/component-standards/component-complexity/composer).

**Examples:**
- Checkout Flow, Project Board, Analytics Dashboard

**Work of the system:**
- provide the building blocks; assemblies live at the app layer

**Pitfalls:**
- accidentally "baking in" assemblies as universal
  components, which ossifies the system which ossifies the system

→ Deep dive into Assemblies

## Meta-Patterns Across All Layers

Regardless of layer, three meta-patterns ensure scalability:
- **Slotting & Substitution**: anticipate replaceable regions (children,
  slots, render props).
- **Headless Abstractions**: separate logic (hooks, providers) from
  presentation (styled components).
- **Contextual Orchestration**: treat composers as state providers, not
  just visual containers.

These aren't just coding tricks—they're governance
strategies. They help a design system resist collapse under
exceptions.

## Designing with Layers: A Systems Approach to Components

(excerpt with added section)

## Why Composition Matters

Design systems cannot anticipate every product problem, every variant,
or every edge case. If they try, they either collapse under prop bloat
("yet another boolean for yet another exception") or grind
to a halt as every new request funnels through the system team. Both
outcomes slow teams and erode trust.

Composition is the release valve. By leaning into patterns like
compound components in React, or slotting and substitution at the
system layer, you give product teams a way to:
- Use the system a la carte: pull in primitives and compounds without
  committing to a rigid, monolithic API.
- Insert what they need: slot in custom behavior, add a
  product-specific sub-control, or override presentation while still
  sitting inside the system's orchestrator.
- Omit what they don't: drop optional slots or props that
  aren't relevant, without violating conventions.
- Stay unblocked: product timelines aren't gated by triage
  queues; teams compose from known parts and keep shipping.
- Adhere where possible: because orchestration is handled by the
  composer (Field, Toolbar, Pagination), the accessibility, ARIA, and
  state management rules are inherited "for free."

This is why composition is a governance strategy, not just a coding
trick. It creates a continuum: the system team defines boundaries and
patterns, and product teams compose solutions inside those boundaries
without waiting for new one-off components.

## Case Studies in Complexity

**One-Time Passcode Input (Compound → Composer)**

What seems like "just six inputs" quickly becomes a
coordination problem: auto-advancing focus, backspacing, accessibility
for screen readers. By elevating the "field state" to a
composer with shared context, you allow each input cell to remain
simple while the container manages orchestration.

**Coachmarks & Product Walkthroughs (Composer)**

Onboarding experiences often break system rules because they're
built in isolation. A coachmark composer integrates with your Popover
primitive, tracks step state, and ensures consistent keyboard
navigation and focus management. This prevents ad-hoc, inaccessible
walkthroughs.

**Skeletons & Spinners (Primitives with Nuance)**

Loading indicators are "simple," but their nuances matter:
skeletons must respect the shape of the eventual content (text vs
media vs datavis), and spinners must scale with container context. By
treating them as tokenized primitives with animation policies, you
avoid teams inventing divergent loaders.

**Form Fields (Composer)**

Every control needs a label and error messaging. Instead of
duplicating logic in each input, a Field composer provides a context:
labels associate automatically, error messages announce via ARIA, and
useFieldControl() ensures consistency across text, select, and
checkbox controls. This is orchestration as governance.

**Toolbars & Filter Action Bars (Composer)**

Toolbars fail when they're just a row of buttons. The system
approach: actions are registered with priorities, measured with
ResizeObserver, and overflowed into a "More" menu. The composer
orchestrates roving tabindex and ARIA roles, keeping unknown sets of
actions consistent with app conventions.

**Pagination (Composer)**

Pagination looks trivial until totals grow. The composer governs page
windows, ellipses insertion, compact breakpoints, and cursor mode (for
unknown totals). By making layout policy explicit, you prevent every
product from reinventing "pagination rules."

**Rich Text Editor (Composer with Plugins)**

The richest example of orchestration: schema, commands, plugins, and
UI slots (toolbar, bubble, slash, mentions). By isolating the engine
(ProseMirror, Slate, Lexical) behind a stable API, you give your
system resilience to vendor shifts. Complexity here is not
eliminated—it's governed.

## Why This Matters

For junior designers, the natural unit of thinking is the screen: what
needs to be drawn to make this flow work? For system designers, the
unit shifts to grammar: what are the rules of combination, and how do
we prepare for emergent complexity?

- Primitives demand standards.
- Compounds demand conventions.
- Composers demand orchestration.
- Assemblies demand boundaries.

Compounds demand conventions.

Composers demand orchestration.

Assemblies demand boundaries.

When you apply this layered lens, your system stops being a library of
parts and becomes a language for products.

## Composition Makes Complexity Manageable

Complexity is inevitable. The goal isn't to eliminate it, but to
channel it into structures that remain legible, maintainable, and
extensible. Composition makes that channel possible. A button is
stable. A field is orchestrated. A toolbar overflows gracefully. A
rich text editor governs the chaos of paste and plugins. And
crucially: when product teams need something new, they don't need
to break the system—they compose with it.

By recognizing components not as flat things, but as layered patterns,
you prepare your system for growth. You teach teams not only what to
build, but how to think about building—and that's the difference
between a component library and a true design system.

That's how a design system grows from a catalog of parts into a
library for products.
