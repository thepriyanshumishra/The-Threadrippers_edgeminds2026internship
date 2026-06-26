---
name: Kivo Workspace
colors:
  surface: '#fef9ef'
  surface-dim: '#ded9d1'
  surface-bright: '#fef9ef'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f8f3ea'
  surface-container: '#f3ede4'
  surface-container-high: '#ede8df'
  surface-container-highest: '#e7e2d9'
  on-surface: '#1d1c16'
  on-surface-variant: '#414753'
  inverse-surface: '#32302a'
  inverse-on-surface: '#f5f0e7'
  outline: '#717784'
  outline-variant: '#c1c6d5'
  surface-tint: '#005eb4'
  primary: '#005db2'
  on-primary: '#ffffff'
  primary-container: '#0075de'
  on-primary-container: '#fffeff'
  inverse-primary: '#a8c8ff'
  secondary: '#5d5f5e'
  on-secondary: '#ffffff'
  secondary-container: '#dfe0df'
  on-secondary-container: '#616362'
  tertiary: '#9b4300'
  on-tertiary: '#ffffff'
  tertiary-container: '#c15600'
  on-tertiary-container: '#fffeff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d5e3ff'
  primary-fixed-dim: '#a8c8ff'
  on-primary-fixed: '#001b3c'
  on-primary-fixed-variant: '#00468a'
  secondary-fixed: '#e2e2e2'
  secondary-fixed-dim: '#c6c7c6'
  on-secondary-fixed: '#1a1c1c'
  on-secondary-fixed-variant: '#454747'
  tertiary-fixed: '#ffdbca'
  tertiary-fixed-dim: '#ffb68f'
  on-tertiary-fixed: '#331100'
  on-tertiary-fixed-variant: '#773200'
  background: '#fef9ef'
  on-background: '#1d1c16'
  surface-variant: '#e7e2d9'
typography:
  display-title:
    fontFamily: Inter
    fontSize: 40px
    fontWeight: '700'
    lineHeight: '1.2'
    letterSpacing: -0.02em
  display-title-mobile:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: '1.2'
  headline-md:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: '1.3'
  body-lg:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '400'
    lineHeight: '1.5'
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: '1.5'
  label-mono:
    fontFamily: IBM Plex Mono
    fontSize: 12px
    fontWeight: '400'
    lineHeight: '1.4'
    letterSpacing: 0.02em
  button-text:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '500'
    lineHeight: '1'
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  unit: 8px
  block_margin: 4px
  sidebar_width: 240px
  container_max_width: 900px
  gutter: 16px
---

## Brand & Style
The design system for this product is centered on the "Warm Paper" and "Stealth" philosophy—a premium, utility-driven aesthetic designed for deep focus and high-density knowledge work. It moves away from the clinical coldness of typical SaaS interfaces, favoring a tactile, analog-inspired warmth that mimics high-quality stationery.

The style is **Minimalist-Stealth**. It avoids heavy shadows and decorative flourishes in favor of precision, hairline borders, and subtle tonal shifts. The interface remains quiet and "invisible" until interaction is required, ensuring that the user's RAG-powered data and documentation remain the primary focus.

## Colors
The palette is divided into a high-contrast functional layer and a soft utility layer.

- **Primary Canvas:** Pure white in light mode provides a "paper" feel, while warm charcoal provides a "stealth" environment for dark mode.
- **Sidebars & Containers:** Subtle shifts (Warm Off-White/Charcoal) provide structural hierarchy without the need for elevation or shadows.
- **Accents:** "Notion Blue" is used sparingly for active states, primary actions, and focus rings to maintain a professional, utility-first vibe.
- **Semantic Tags:** A muted pastel palette is provided for categorization and metadata. These colors should have low saturation to prevent visual fatigue in information-dense views.

## Typography
The system uses a tri-font approach to differentiate content types:
- **Inter (Sans-Serif):** The primary workhorse for the UI, navigation, and input fields. It is clean and systematic.
- **Charter/Georgia (Serif):** Used for long-form reading and document content to improve legibility and provide an editorial feel (fallback to system serif).
- **IBM Plex Mono (Monospace):** Used for metadata, labels, IDs, and technical snippets to emphasize the "knowledge tool" and RAG data aspects.

Hierarchy is achieved primarily through weight and color rather than excessive scale. Body text is optimized at 14px and 15px with a generous 1.5 line height for maximum readability.

## Layout & Spacing
The layout follows a strict **8px grid** with **4px sub-intervals** for tight component grouping.

- **Modular Vertical Blocks:** Content is treated as "blocks" with consistent 4px margins between related elements, allowing for the flexible, stackable UI required for knowledge bases.
- **Dividers:** Use 1px hairline dividers (#EDEDEB in light, #2F2F2F in dark) for structural separation.
- **Fluidity:** Content areas should use a "fixed-fluid" model—a fixed maximum width (900px) for readability centered on the screen, with fluid margins and a fixed sidebar.
- **Breakpoints:**
  - Mobile (<640px): Sidebar collapses to a drawer; margins reduce to 16px.
  - Tablet (640px - 1024px): Sidebar remains fixed (condensed); margins at 24px.
  - Desktop (>1024px): Full sidebar (240px); wide gutters.

## Elevation & Depth
This design system avoids traditional box shadows to maintain the "Stealth" aesthetic. Depth is communicated through **Tonal Layers** and **Hairline Borders**.

- **Level 0 (Base):** The main canvas background.
- **Level 1 (Structural):** Sidebars and secondary panels using subtle tonal shifts (#FBFBFA / #202020).
- **Level 2 (Interactive):** Floating dropdowns and context menus. These are the *only* elements permitted to use a soft, low-opacity shadow (e.g., `0px 4px 12px rgba(0,0,0,0.1)`) to ensure they stand out against the flat content.
- **Dividers:** 1px hairlines replace shadows for defining sections and headers.

## Shapes
Shapes are intentionally precise and geometric to reflect a professional workspace.

- **Small Radius (4px):** Applied to buttons, input fields, and small UI controls. This keeps the look crisp.
- **Large Radius (8px):** Applied to cards, modals, and larger layout containers to provide a gentle "human" touch to the structured grid.
- **Zero Radius:** Used for vertical block indicators and hairline dividers.

## Components
Consistent styling across the system is achieved through "Stealth" interaction patterns.

- **Buttons:** Primary buttons use the accent blue. Secondary and "Stealth" buttons are transparent with no border, appearing only on hover with a background fill of `rgba(55, 53, 47, 0.06)` (Light) or `rgba(227, 226, 224, 0.06)` (Dark).
- **Input Fields:** 1px hairline borders with 4px radius. On focus, the border transitions to the accent blue with a subtle 2px outer glow of the same color.
- **Toggle Lists:** Use a small 12px chevron. The content block should be indented by 16px to signify hierarchy.
- **Cards:** No shadows. Use an 8px border-radius and a 1px hairline border. Backgrounds should match the sidebar color for a "sunken" feel or stay white for a "raised" feel.
- **Chips/Tags:** Rounded-lg (capsule) with the muted pastel palette. Text color should be a darker version of the background color for legibility.
- **Lists:** High-density, 8px padding between rows. Hover states use the stealth background fill.
- **Shimmer Skeletons:** Use a soft linear gradient that moves across the warm gray/charcoal base to indicate loading states for RAG queries.