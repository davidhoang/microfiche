# SwiftUI and Liquid Glass UI audit

Reviewed November 12, 2026, against `f13eb58`.

## Direction

Keep the native split-view shell, system inspectors, matte photo canvas, semantic
colors, and crisp selection. Improve interaction and layout rather than adding
more glass.

## Prioritized findings

1. **Detail-menu accessibility:** the existing detail accessibility test received
   an empty More Actions label. The failure reproduced on the initial run and
   both subsequent runs. Check the exposed control, not only its SwiftUI modifier.
2. **Quick Preview:** provide a visible close control and predictable focus
   restoration. Use a neutral photo surface, with glass limited to controls.
3. **Inspector layout:** eight 28-point Finder-label controls, seven 10-point gaps,
   and 40 points of inspector padding require 334 points. The inspector declares
   a 280-point minimum, so the picker needs to adapt.
4. **Floating view control:** reserve scroll space beneath Grid/List so the last
   image or row cannot remain covered at the end of the scroll range.
5. **Native navigation and focus:** use native sidebar buttons and request library
   keyboard focus for intentional library interactions, not every view update.
6. **Toolbar hierarchy:** retain system-managed backgrounds and logical grouping
   for ordinary actions. Limit background opt-outs to custom slider/search
   clusters, and use symbols without redundant circle borders.

## Photo-browser inspiration, outside this implementation

- Apple Photos: Fit / 100% zoom, pinch-to-zoom, panning, and optional thumbnails
  below the focused image.
- Lightroom: explicit grid/loupe navigation and a filmstrip for reviewing sets.

Zoom, filmstrip, and compare modes are follow-up features, not requirements for
this UI pass.

## Baseline verification

- Debug build passed.
- The focused UI run passed six executions and failed one (including separate
  light/dark launch executions).
- The detail-menu accessibility check failed on both additional runs.
- Reviewed light/dark launch captures and the recorded detail view.
- The fixture images are single-pixel swatches, not evidence of photographic
  legibility, contrast, or mixed-aspect-ratio layout.

## Affected-state matrix for implementation

| Area | Required states and transitions |
| --- | --- |
| Selection | None, first, different, same, multiple, rapid repetition, removal; grid and list |
| Input | Selected/unselected double-click, Command-click, Shift-click, arrows, drag then click, context menu then click |
| Preview | Open/close twice by button, Escape, and backdrop; Space toggle; next image; keyboard focus after dismissal |
| Inspector | Collapsed/expanded both ways, no selection, selected item removed, narrow/normal widths, all eight labels reachable |
| Navigation/focus | Sidebar buttons, contact-sheet rename, text editing, non-text control focus, pointer selection after other controls |
| Floating control | Grid/list twice, scroll to last item, minimum/default window size, resized thumbnails |
| Toolbar | Library/detail, grid/list, active filters, contact-sheet export, sidebar/inspector both ways |
| Appearance/content | Light/dark, Reduce Motion, Increase Contrast, Reduce Transparency; preview loading, success, failure, cancellation, retry where reproducible |

Repeat changed interactions at least twice without relaunching. Record unverified
states explicitly; a successful build is not interaction verification.

## Implementation

The follow-up code commit implements the six findings above.

- The detail More Actions menu uses a native text-and-symbol label, visually
  reduced to its icon without discarding its accessible name.
- Inspection confirmed that the native macOS menu button exposes its name as
  `AXTitle`, not `AXLabel`. The regression now checks its title and opens its
  actions twice, rather than incorrectly requiring an AXLabel.
- Quick Preview has a visible Close Preview button, a solid photo surface,
  isolated background controls, and explicit keyboard navigation and dismissal.
- Finder-label controls use an adaptive grid within the existing inspector.
  Clearing a label also explicitly selects `FinderLabel.none`, rather than
  accidentally treating Swift's optional `nil` as a mixed-label selection.
- The floating Grid/List control reserves a bottom safe-area inset.
- Sidebar locations and Contact Sheets use native buttons; inline rename remains
  an editable row rather than a text field nested in a button.
- Keyboard focus follows explicit selection/dismissal requests, not unrelated
  metadata or layout updates.
- Filter/Sort share a native toolbar group; Export and Inspector retain native
  backgrounds. Custom slider/search clusters retain their background opt-outs.

The implementation includes upstream interaction coverage and visible-screen
window sizing from `4590a7c`. Minimum-window tests request 1100 x 700 content
while respecting the available display.

### Validation status

The initial combined unit/UI run was stopped after stalling in the existing
`testICloudDownloadCoordinatorHandlesSuccessFailureTimeoutAndCancellation`
unit test, before the UI checks started. Existing iCloud tests also emitted
background-thread publishing warnings. This is not a passing full suite.

Across the focused runs, 16 relevant unit tests, 15 functional UI regressions,
and the separate light/dark launch executions passed. The final standalone
Debug build also passed.

The broader UI run initially failed drag and comments-editor checks. Investigation
corrected test-harness assumptions rather than relaxing behavior assertions:
macOS drags now use the mouse API and verify the sheet count; context-menu queries
cannot match the main File menu; text editing is verified by actual pointer focus,
typed input, and readback instead of the native text view's false `AXEnabled`.
Thumbnail resizing also uses the real slider thumb and asserts both 80-point and
180-point values. Foreground-window interference was removed before final reruns.

| Exercised area | Verified transitions |
| --- | --- |
| Selection/input | None, first, different, same, rapid repetition, Command/Shift selection, arrows, removal; selected/unselected double-click; completed drag and context menu followed by later clicks, twice in grid/list |
| Preview | Close button, Escape, Space, backdrop, next/previous image, and restored browsing keyboard focus in both views |
| Inspector/detail | Panels open/close both ways; selection disappears; actual text editing twice; all eight labels selected twice at minimum window size; named native detail menu/actions twice |
| Navigation/layout | Native sidebar selection and repeated contact-sheet rename; repeated grid/list changes, scrolled cells, last-item visibility at default/minimum sizes and minimum/maximum thumbnail sizes |
| Toolbar/appearance | Library/detail controls, filters, search, sorting, panel controls at toolbar edges, deterministic accessibility appearance flags; light/dark launches |

Local evidence: `/tmp/Microfiche-UIFix-focused-5.xcresult`,
`/tmp/Microfiche-UIFix-final-ui.xcresult` (broader run with the two initial failures),
`/tmp/Microfiche-UIFix-unobstructed.xcresult` (final resizing check passed),
`/tmp/Microfiche-UIFix-native-semantics.xcresult` (both corrected checks passed),
and `/tmp/Microfiche-UIFix-final-build.log`. These are separate runs, not a claim
that the full default suite passed.

### Verification commands

Run from the repository root with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`:

```sh
xcodebuild -project Microfiche.xcodeproj -scheme Microfiche \
  -configuration Debug -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project Microfiche.xcodeproj -scheme Microfiche \
  -configuration Debug -destination 'platform=macOS' \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 150 \
  -maximum-test-execution-time-allowance 180 \
  -only-testing:MicroficheUITests/MicroficheUITests/testDragAndContextMenuDoNotDisableLaterClicksTwiceInBothViews \
  -only-testing:MicroficheUITests/MicroficheUITests/testInspectorTextEditingKeepsKeyboardInputOutOfLibraryNavigation \
  -only-testing:MicroficheUITests/MicroficheUITests/testFloatingViewControlNeverCoversLastItemRepeatedly \
  test
```

The signed test command above isolates the final corrected checks. The preceding
broader signed run selected the interaction, preview, sidebar, appearance,
search/filter/sort, panel-toolbar, and launch cases individually. The focused
unit run selected 16 relevant state/navigation/accessibility checks rather than
claiming a passing full suite.

### Remaining unverified states

- Actual VoiceOver navigation and keyboard traversal of every non-text control.
- Actual system accessibility settings, beyond deterministic test flags.
- Photo legibility and mixed-aspect-ratio content, since fixtures are swatches.
- Preview failure/retry/cancellation through the rendered UI, real iCloud
  placeholders, and disconnected external-drive recovery.
- Export dialogs and welcome-onboarding focus/modal behavior after this pass.

## References

- [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Modality](https://developer.apple.com/design/human-interface-guidelines/modality)
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Viewing photos in Apple Photos](https://support.apple.com/guide/photos/view-photos-and-videos-pht8b9ba4aa9/mac)
- [Viewing photos in Lightroom](https://helpx.adobe.com/lightroom-classic/help/view-photos.html)
