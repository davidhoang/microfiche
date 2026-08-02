# Testing Microfiche

Microfiche is a stateful macOS application. Verification must cover transitions between states, not only a static result after launch.

## Definition of done

A change is complete when:

1. The app builds successfully.
2. Relevant automated tests pass.
3. Every affected state and transition has been exercised.
4. Repeated use works; perform each changed interaction at least twice without relaunching.
5. Any unverified state is documented in the handoff.

“Build succeeded” must never be used as a synonym for “behavior verified.”

## Affected-state matrix

Create a small matrix for the feature being changed before implementation. Remove irrelevant rows, add feature-specific rows, and test every remaining combination that can change the outcome.

| Dimension | States to consider |
| --- | --- |
| Selection | none, first item, different item, same item, multiple items, selection removed |
| Repetition | first use, second use, rapid repeated use, use after cancellation |
| Pointer input | click, double-click, Command-click, Shift-click, drag, context menu |
| Keyboard input | focus entry, arrows, Space, Escape, Delete, shortcuts |
| Inspector | collapsed, expanding, expanded, collapsing, selected item removed |
| Content | loading, loaded, empty, missing, failed, retrying |
| Storage | local, iCloud downloaded, iCloud placeholder, external volume unavailable |
| View | grid, list, resized grid, scrolled/lazily created cell |
| Motion | standard motion, Reduce Motion |

Focus on all **affected** states rather than the full Cartesian product of the application. A state is affected when the changed code branches on it, renders it, enters or exits it, or competes with another gesture/task while it is active.

## Interaction regression checklist

For any click, selection, gesture, or navigation change:

- Start with no selection and select an item.
- Select a different item immediately afterward.
- Select several more items without relaunching.
- Click the selected item again.
- Double-click both an unselected and selected item.
- Exercise Command-click and Shift-click selection.
- Confirm keyboard navigation still follows pointer selection.
- Begin a drag and confirm it neither gets mistaken for a click nor disables later clicks.
- Open the context menu and confirm later clicks still work.
- Dismiss or collapse any presented panel, then repeat the interaction.
- Repeat with a cell that has just appeared after scrolling.

The second and later interaction is mandatory. This catches gesture state, focus, cancellation, and stale-state bugs that a first-click smoke test misses.

## Commands

Build the macOS app:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Microfiche.xcodeproj \
  -scheme Microfiche \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run the test suite on the local Mac:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Microfiche.xcodeproj \
  -scheme Microfiche \
  -configuration Debug \
  -destination 'platform=macOS' \
  test
```

Keep the test host's Debug ad-hoc signing enabled. macOS UI automation injects
signed XCTest support frameworks into the app and the UI runner can exit before
launch when `CODE_SIGNING_ALLOWED=NO` is applied to the entire test action.
Use the unsigned override for standalone builds only.

Use a temporary `-derivedDataPath` when isolation from local Xcode state is useful.

## Automated test expectations

- Put pure state-transition and navigation coverage in `MicroficheTests`.
- Put pointer, keyboard, focus, panel, and repeated-interaction coverage in `MicroficheUITests`.
- Give UI elements stable accessibility identifiers before relying on coordinate-based interaction.
- Seed deterministic fixtures for UI tests. Tests must not depend on a developer’s current linked folders or iCloud availability.
- A regression test should fail for the original bug and pass after the fix.
- Do not replace transition assertions with screenshots alone; screenshots supplement assertions.

## Handoff example

```text
Build: passed (Debug, generic macOS)
Tests: passed (MicroficheTests and relevant MicroficheUITests)
States: none -> selected; selected -> different selected; repeated click x5;
        selected/unselected double-click; Command-click; drag then click
Unverified: iCloud placeholder state (fixture unavailable)
```
