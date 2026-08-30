# Microfiche Accessibility Audit

This checklist covers the library, detail, quick preview, inspector, and contact-sheet workflows required by PCD-31. Run the manual sections on a Mac after the automated suite because VoiceOver speech, system focus rings, Liquid Glass, and appearance settings cannot be validated from snapshots or a Linux build host.

## Automated coverage

| Area | Covered states |
| --- | --- |
| Keyboard selection | No selection, first and different selection, repeated selection, Command-click, Shift-click, arrows, Escape, grid/list transitions |
| Pointer interaction | Selected/unselected double-click twice, drag initiation, context menu, subsequent click |
| Panels and navigation | Sidebar and inspector collapse/expand in both directions, persistence across two relaunches, selected item removal |
| Accessibility semantics | Image names and selected values; detail image, inspector, share, and more-action labels; sidebar, contact-sheet, editor, and status semantics |
| Announcements | Empty/single/multiple selection, focused item, image loading/failure/cancellation, and contact-sheet drop outcomes |
| Reduce Motion | All shared snap, transition, and panel tokens resolve to no animation; repeated preview and view-mode transitions run with Reduce Motion enabled |
| Increased contrast | Selection fill/stroke metrics strengthen; repeated selection and view transitions run with a deterministic Increased Contrast override |
| Reduce Transparency | Glass panels, floating controls, inspector reading surfaces, and detail extension effects use deterministic solid-surface fallbacks |

## Manual VoiceOver audit

Run each workflow twice without relaunching.

- [ ] With VoiceOver on, traverse the toolbar, sidebar, grid, list, inspector, menus, and editors. Confirm each control announces an accurate name, role, value, enabled state, and selected state.
- [ ] Select one image, a different image, and multiple images. Confirm one concise selection announcement per change and that the focused filename is announced for multi-selection.
- [ ] Open and close Quick Preview and detail twice. Confirm focus remains predictable and the modal preview exposes its Close Preview action.
- [ ] Exercise local, iCloud placeholder, downloading, loaded, failed, cancelled, and retry states. Confirm state changes are announced once and retry controls remain reachable.
- [ ] Drop one image, multiple images, and duplicate images on a Contact Sheet. Confirm the result announcement reports newly added images without duplicate chatter.
- [ ] Use keyboard focus traversal and the documented shortcuts with the sidebar and inspector both collapsed and expanded. Confirm the visible accent focus/selection ring follows the focused image.

## Manual appearance audit

Test at minimum, ideal, and expanded window widths.

- [ ] Light appearance
- [ ] Dark appearance
- [ ] Increase Contrast
- [ ] Reduce Transparency
- [ ] Reduce Motion
- [ ] Liquid Glass on macOS 26

Confirm text and icons remain legible, selection does not rely on fill alone, increased contrast adds a stronger outline, floating controls retain a visible boundary, and Reduce Motion removes preview, onboarding, hover, resize, scroll, sidebar, and inspector animation without hiding state changes.
