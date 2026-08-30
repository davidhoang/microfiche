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
6. Navigation, selection, and keyboard behavior still match the rules below.

---

## Overview

Microfiche is a durable, snappy macOS photo-library UI: solid system surfaces, crisp selection, and short interaction motion. Native Liquid Glass carries navigation chrome; the photo canvas stays matte and scannable.

---

## Design Principles

1. **Durable Surfaces** — Prefer solid system colors and materials over decorative gradients, blur orbs, or soft glow.
2. **Snappy Motion** — Short ease-out feedback (`MicroficheMotion`). No scale lifts or drop-shadow hover. Respect Reduce Motion.
3. **Crisp Selection** — High-contrast stroke and quiet fill. Hover is a flat tint only.
4. **Native Hierarchy** — Let `NavigationSplitView`, toolbars, inspector, and system materials carry structure.
5. **Dense, Readable Content** — Photos first; chrome stays quiet. Empty states stay direct.
6. **Library Continuity** — Changing location resets transient browsing state so the canvas never shows stale selection.

---

## Navigation

Rules derived from `ContentView`, `SidebarView`, and `ImageDetailView`.

1. **Two-column shell + inspector** — Use `NavigationSplitView` (sidebar + detail). Metadata lives in a detail-attached `.inspector`, not a third permanent split column.
2. **Sidebar owns library location** — Selection is a single enum: All Images, Folder, or Contact Sheet. External drive rows are status only — not navigation targets.
3. **Location change clears browsing state** — On library selection change, clear image selection, focus, quick preview, and detail view.
4. **Detail pushes on the detail stack** — Double-click opens `ImageDetailView` via `NavigationStack` + `navigationDestination`, not an opacity overlay or new split column.
5. **Inspector stays with detail** — Entering detail keeps the metadata inspector available so Finder labels, tags, and comments can be edited while viewing.
6. **Sidebar is collapsible** — Width 240–360 (ideal 280). Use the system split-view divider and sidebar toggle; do not programmatically override `columnVisibility` during resize.
7. **Unified chrome** — Window uses unified toolbar with no title. Keep `.navigationTitle("")` unless a mode truly needs a title.
8. **Window scale** — Minimum about 1100×700; default launch size stays large enough for sidebar + grid + inspector.

```
┌──────────────────────────────────────────────────────────┐
│  Unified toolbar (no title)                              │
├────────────┬─────────────────────────────┬───────────────┤
│  Sidebar   │  Detail canvas              │  Inspector    │
│  Library / │  Grid | List | Detail overlay│  Metadata     │
│  Locations │  Floating Grid/List control │  (optional)   │
│  Collections│                             │               │
└────────────┴─────────────────────────────┴───────────────┘
```

---

## Sidebar Structure

1. **Section taxonomy** — Eyebrow → title → one detail line; optional trailing `+` action.
   - Library → Folders
   - Locations → External Drives (when remembered volumes exist)
   - Collections → Contact Sheets
2. **Primary entry label** — Use “All Images”, not “All”.
3. **Custom scroll stack** — Prefer `ScrollView` + section components over `List` separators for a fluid sidebar.
4. **Offline in place** — Surface availability in section detail counts, row subtitles, and the main empty state — don’t invent a separate offline screen.
5. **Destructive menus** — Use `role: .destructive` with explicit labels (“Remove Folder”, “Forget Drive”, “Delete”).

### Sidebar type scale

| Role | Size / weight | Color |
|------|---------------|-------|
| Eyebrow | 9pt medium, uppercase, tracking 0.7 | secondary |
| Section title | 13pt semibold | primary |
| Section detail | 11pt regular | tertiary |
| Row title | 14pt (semibold when selected) | primary |
| Row subtitle | 11pt regular | secondary |
| Row icon | 13pt semibold in 24×24 | accent when selected; secondary otherwise |

Spacing: 12pt horizontal / 16pt vertical container padding; ~22pt between sections; row padding 8×6; corner radius 8.

---

## Selection & Focus

1. **Two coordinated IDs** — `selectedImageFileIDs` (multi-select) and `focusedImageFileID` (keyboard / inspector anchor). Keep them updated together.
2. **macOS click modifiers** — Click replaces; ⌘ toggles; ⇧ ranges from the focused item.
3. **Inspector follows focus** — Metadata binds to `focusedImageFile`, not only the open detail file.
4. **Scroll after structural moves** — After delete, view-mode change, or leaving detail, scroll the focused item into view.
5. **Grid vs list chrome** — Grid uses `contentSelectionChrome`; list uses accent fill + stroke. Prefer crisp planted framing in both — no glow or lift.
6. **Inline rename** — Clicking an already-selected name begins rename (contact sheets, list filenames).

---

## Keyboard

Handled by `KeyboardEventHandlingView` when a text field is not first responder.

| Key | Behavior |
|-----|----------|
| ←↑↓→ | Move focus/selection; in grid, vertical step uses column count |
| ⇧+←↑↓→ | Extend selection (library mode) |
| Space | Toggle quick preview (library mode, focused selection only) |
| Esc | Detail → quick preview → clear selection (in that order) |
| Delete | Move selection to Trash (confirm unless bypassed) |
| ⌘/⇧+Delete | Bypass delete confirmation |
| ⌘⇧A | Move selection to Archive (prompts for folder if unset) |

Don’t steal keys while the user is editing text.

---

## Toolbar & Controls

1. **Library toolbar owns browsing tools** — Thumbnail size slider (grid only) and inspector toggle live on `ContentView`’s toolbar, not inside the canvas view.
2. **Continuous size, not presets** — Grid size is an 80–180pt slider in the principal slot. In list mode, keep a clear spacer so toolbar layout doesn’t jump.
3. **View mode floats on the canvas** — Grid/List is a bottom floating control, not a toolbar segmented control. Hide it when detail is open.
4. **Inspector toggle is shared language** — `sidebar.right` with help “Show Info” / “Hide Info” in library and detail toolbars.
5. **macOS 26 toolbar items** — Hide shared background on custom toolbar clusters via `hideSharedBackgroundIfAvailable()`.

---

## Empty & Offline States

1. **Canvas empty** — Centered icon + headline + one supporting sentence (~360pt max width). No decorative glow circle.
2. **Two library empties** — “No images yet” vs “Reconnect the drive” (different icon + copy).
3. **Sidebar empties** — Inline secondary copy under the section, not `ContentUnavailableView`.
4. **Inspector empty** — System `ContentUnavailableView` when nothing is focused.

---

## Materials & Surfaces

1. **Matte photo canvas** — `controlBackgroundColor` with quiet separators. No decorative gradients or blur orbs.
2. **Detail canvas** — Lighter `textBackgroundColor` so the focused image reads as a print on paper.
3. **Inspector / sidebar material** — Use `microficheSidebarChrome()` (sidebar visual effect) for navigation-adjacent panels.
4. **Glass budget** — Floating view-mode control and quick-preview panel may use Liquid Glass / materials. Thumbnails, rows, and the grid itself stay matte.
5. **Legacy card elevation** — `microficheDetailChrome()` is a pre-Tahoe fallback only; do not reintroduce floating content cards on modern macOS.

---

## Motion Tokens

Defined in `LiquidGlassDesign.swift` as `MicroficheMotion`:

| Token | Duration | Use |
|-------|----------|-----|
| `snap` | 100ms easeOut | Hover, selection, scroll-to, view-mode toggle |
| `transition` | 140ms easeOut | Detail open/close, sidebar collapse |

Disable animations while the grid size slider is dragging. Prefer `MicroficheMotion` over ad-hoc durations.

---

## Copy Tone

1. **Direct and instructional** — Sentence case for descriptions; Title Case for actions and section names.
2. **Name the target** — “Remove Folder”, “Forget Drive”, “Move to Trash” — not vague “Delete” when the object matters.
3. **Short toolbar help** — Verb phrases: “Thumbnail Size”, “Back to Library”, “Show Info”.
4. **Status is factual** — “Offline”, “Connected”, “3 linked folders • 1 offline”.
5. **Onboarding stays concrete** — One benefit per step; say what the user does and what they get. Prefer product terms already in the UI (Contact Sheets, Finder labels/tags/comments, Link a Folder) over marketing verbs.

---

## Drag, Drop & Context Menus

1. **Images drag as file URLs** from grid and list.
2. **Contact sheets are drop targets** — Accent border while targeted; accept image file URLs.
3. **Grid and list context menus** — “Add to Contact Sheet” when sheets exist, plus “Move to Archive”.
4. **Archive** — Moves selected originals into a user-chosen folder (Settings → Archive, or prompted on first use). Menu: **File → Move to Archive** (⌘⇧A). Local Microfiche metadata follows the move.
5. **Destructive actions stay in context menus** — Don’t put Remove/Forget/Delete in the always-visible chrome.

---

## Main Surfaces (Reference)

### Sidebar
- **File:** `Microfiche/Views/SidebarView.swift`
- Custom scroll sections; collapsible via the system split-view divider and sidebar toggle

### Library canvas
- **File:** `Microfiche/Views/MainContentView.swift`
- Matte background, grid/list, floating view-mode control, empty states

### Shell / keyboard / toolbar
- **File:** `Microfiche/ContentView.swift`
- `NavigationSplitView`, inspector, selection model, key handling wiring

### Design helpers
- **File:** `Microfiche/Views/LiquidGlassDesign.swift`
- Motion tokens, selection/hover chrome, glass panel, sidebar material

### Detail & metadata
- **Files:** `Microfiche/Views/ImageDetailView.swift`, `PreviewView.swift`
- **Native metadata:** `NativeFileMetadataService` + `FinderLabel` read/write Finder color labels, tags, and comments; inspector `FinderLabelPicker` is the primary label UI.

### Welcome onboarding
- **Files:** `Microfiche/Views/OnboardingView.swift`, `SettingsView.swift`, `Services/UserPreferences.swift`
- Full-window dimmed overlay + `LiquidGlassPanel` (same modal pattern as quick preview).
- Shows once until completed/skipped when **Settings → Onboarding → Show welcome onboarding** is on.
- Testing: toggle the setting off to suppress; use **Replay Onboarding** or **Help → Replay Welcome Onboarding** to walk through again.
- **Copy:** Four steps, one job each — in-place library, linked folders/drives, Contact Sheets, Finder metadata. Titles are short and direct; body copy is one instructional sentence plus the payoff. Final CTAs: **Link a Folder** / **Browse Library**.

### Archive folder
- **Files:** `Services/ArchiveFolderStore.swift`, `Services/FileArchiver.swift`, `SettingsView.swift`
- Security-scoped bookmark for the destination folder; collision-safe rename on move.

---

## Future Enhancements

- Retire or wire unused helpers (`microficheToolbarChrome`, `sidebarSelectionBackground`) deliberately
