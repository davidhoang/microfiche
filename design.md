# Microfiche Design

## Native macOS Design References

Use Apple's [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines) as the primary reference for interaction, layout, navigation, materials, typography, color, and accessibility decisions. For the current system appearance, also review [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass) before adding custom visual effects.

### Liquid Glass Principles

- Prefer standard SwiftUI and AppKit components so navigation, controls, toolbars, sheets, and accessibility settings inherit native macOS behavior automatically.
- Treat Liquid Glass as a functional layer for navigation and controls, not as decoration for every container or row.
- Avoid stacking glass surfaces. Use spacing, alignment, typography, and subtle separators to establish hierarchy within a shared surface.
- Remove custom backgrounds that compete with system effects in `NavigationSplitView`, sidebars, title bars, and toolbars.
- Use system materials, semantic colors, standard spacing, and native button styles before introducing custom fills, borders, gradients, or shadows.
- Keep gradients quiet and contextual. They should support depth without becoming the dominant visual element.
- Preserve clear separation between navigation and content while allowing the sidebar to read as one fluid region.
- Test light and dark appearances, increased contrast, reduced transparency, and reduced motion. Custom treatments must remain legible when system effects adapt or disappear.
- Support arbitrary window sizes and rely on split-view behavior for fluid column resizing.

### Review Checklist

Before merging a visual change, verify that:

1. A native component or material cannot provide the same result more consistently.
2. Glass is limited to an important navigation or control layer.
3. No glass-on-glass or card-on-card layering has been introduced.
4. Text and icons remain legible over changing content and in accessibility modes.
5. The layout still feels native at minimum, ideal, and expanded window widths.

## Overview

Microfiche uses a durable, snappy macOS photo-library UI: solid system surfaces, crisp selection, and short interaction motion. Native Liquid Glass carries navigation chrome; content stays matte and scannable.

## Main UI Components

### 1. Sidebar
**Location:** Left side of window
**Purpose:** Navigation and library organization
**Background:** `NSColor.windowBackgroundColor` (darker grey)

**Sections:**
- **Folders Section**
  - "All" - Shows all images from linked folders
  - Individual folder items
  - Add Folder button (+)

- **Contact Sheets Section**
  - Contact Sheet items (user-created collections)
  - New Contact Sheet button (+)

**Styling:**
- No divider lines between sections
- `.listStyle(PlainListStyle())` for clean, fluid appearance
- `.listRowSeparator(.hidden)` to remove row separators
- 24pt spacer between Folders and Contact Sheets sections

---

### 2. Unified Toolbar
**Location:** Top of Content Area
**Purpose:** View mode and size controls
**Background:** `NSColor.textBackgroundColor` (very light grey, almost white)

**Controls:**
- **View Mode Picker:** Grid / List toggle (center)
- **Size Picker:** Small / Medium / Large (right side, Grid view only)

**Styling:**
- `.toolbarBackground(Color(NSColor.textBackgroundColor), for: .windowToolbar)`
- Subtle, light color to draw attention to the Content Area below
- Seamlessly integrated with Content Area (shares rounded corners and shadow)

**Design Philosophy:**
- Inspired by Arc browser's subtle toolbar design
- Light background recedes visually, emphasizing content
- Still part of the elevated Content Area card

---

### 3. Content Area
**Location:** Right side of window (main area)
**Purpose:** Display image grid/list and provide visual hierarchy
**Background:** Solid `NSColor.controlBackgroundColor` (no decorative gradients or blur)

**Components:**
- Hairline separator under the title/toolbar edge
- Image Grid or Image List (scrollable content)
- Floating view-mode control (bottom)

**Styling:**
- Matte canvas with a quiet leading separator against the sidebar
- Pre-Tahoe fallback may use a light card elevation via `microficheDetailChrome()`
- On macOS 26+, defer to system NavigationSplitView / window materials

**Design Rationale:**
- Solid surfaces read as durable and photographic
- Photos stay the focus; chrome stays quiet
- Snappy hover/selection avoids soft lift effects that feel slow

---

## Color Hierarchy

**From darkest to lightest:**

1. **Sidebar Background** - `NSColor.windowBackgroundColor`
   Dark grey base layer

2. **Content Area Background** - `NSColor.controlBackgroundColor`
   Medium grey elevated surface

3. **Unified Toolbar Background** - `NSColor.textBackgroundColor`
   Very light grey, almost white - most subtle

This three-tier color system creates natural visual hierarchy:
- Sidebar = foundation layer
- Content Area = elevated workspace
- Toolbar = subtle header receding to emphasize content

---

## Layout Structure

```
┌─────────────────────────────────────────────────────┐
│                    Window                           │
│  ┌──────────┬───────────────────────────────────┐  │
│  │          │  ┌─────────────────────────────┐  │  │
│  │          │  │   Unified Toolbar           │  │  │
│  │          │  │  (Light Grey)               │  │  │
│  │ Sidebar  │  ├─────────────────────────────┤  │  │
│  │ (Dark)   │  │                             │  │  │
│  │          │  │   Image Grid/List           │  │  │
│  │          │  │   (Content Area)            │  │  │
│  │          │  │   (Medium Grey)             │  │  │
│  │          │  │                             │  │  │
│  │          │  └─────────────────────────────┘  │  │
│  │          │        Content Area Elevation      │  │
│  │          │      (12pt radius, 8pt shadow)     │  │
│  └──────────┴───────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

---

## Code References

### Sidebar
- **File:** `ContentView.swift:1278-1378`
- **Struct:** `SidebarView`
- **Key Modifiers:**
  - `.listStyle(PlainListStyle())`
  - `.scrollContentBackground(.hidden)`
  - `.listRowSeparator(.hidden)`

### Unified Toolbar
- **File:** `ContentView.swift:1431-1460`
- **Location:** Inside `MainContentView.toolbar`
- **Key Modifiers:**
  - `.toolbarBackground(Color(NSColor.textBackgroundColor), for: .windowToolbar)`
  - `.toolbarBackground(.visible, for: .windowToolbar)`

### Content Area Elevation
- **File:** `ContentView.swift:1377-1467`
- **Struct:** `MainContentView`
- **Key Modifiers:**
  - `.background(Color(NSColor.controlBackgroundColor))`
  - `.cornerRadius(12)`
  - `.shadow(color: Color.black.opacity(0.15), radius: 8, x: -2, y: 0)`
  - `.padding(.leading, 2)` / `.padding(.trailing, 2)` / `.padding(.vertical, 2)`

---

## Design Principles

1. **Durable Surfaces**
   Prefer solid system colors and materials over decorative gradients, blur orbs, or soft glow. The canvas should feel planted, not atmospheric.

2. **Snappy Motion**
   Interaction feedback uses short ease-out timing (`MicroficheMotion.snap` ≈ 100ms). Avoid scale lifts and drop-shadow hover. Respect Reduce Motion.

3. **Crisp Selection**
   Selection is a high-contrast stroke and quiet fill — no accent glow or floating shadow. Hover is a flat tint only.

4. **Native Hierarchy**
   Let NavigationSplitView, toolbars, and system materials carry structure. Custom elevation is a fallback for pre-Tahoe macOS only.

5. **Dense, Readable Content**
   Tighter grid spacing and thumbnail corners keep the library scannable. Empty states stay direct — icon, headline, one supporting line.

6. **Subtle Chrome**
   Floating view-mode control and sidebar rows stay quiet so photos remain the focus.

---

## Motion Tokens

Defined in `LiquidGlassDesign.swift` as `MicroficheMotion`:

| Token | Duration | Use |
|-------|----------|-----|
| `snap` | 100ms easeOut | Hover, selection chrome, scroll-to, view-mode toggle |
| `transition` | 140ms easeOut | Detail open/close, sidebar collapse |

Disable animations while the grid size slider is dragging.

---

## Future Enhancements

Potential improvements to consider:

- **Reduced-motion audit:** Propagate `accessibilityReduceMotion` to remaining transitions
- **Keyboard focus ring:** Match selection chrome for full-keyboard browsing
- **Custom Accent Colors:** User-selectable theme colors
