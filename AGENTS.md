# Repository Development Rules

These rules apply to every contributor and coding agent working in this repository.

## Verification is part of implementation

- Read `TESTING.md` before changing user-visible behavior.
- A successful build proves compilation only. Do not describe a change as tested or fixed based on `xcodebuild ... build` alone.
- Before editing an interaction, list the affected states and transitions. Cover every affected state during verification.
- Test an interaction at least twice in succession. The first successful interaction is not sufficient.
- For selection changes, verify at minimum: no selection, first selection, selection of a different item, reselecting the current item, rapid repeated selection, double-click, Command-click, Shift-click, keyboard selection, drag initiation, and context menu behavior.
- For asynchronous UI, verify idle, loading, success, empty, failure, cancellation, and retry states when those states are reachable.
- For panels and navigation, verify collapsed and expanded states, transitions in both directions, and behavior when the underlying selection disappears.
- Add an automated regression test whenever the behavior can be exercised deterministically. Prefer testing the state-transition logic separately from SwiftUI rendering.
- Run the relevant unit/UI tests plus a Debug build before handing off a change. If a state cannot be automated or manually exercised in the current environment, name it explicitly as unverified.
- Preserve unrelated working-tree changes and never weaken a test merely to make verification pass.

## Completion report

When handing off a change, report:

1. The build command and result.
2. The test command and result.
3. The affected-state matrix exercised.
4. Any states that remain unverified and why.
