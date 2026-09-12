//
//  LibrarySelection.swift
//  Microfiche
//
//  Pure selection transitions for pointer, keyboard, and dismissal.
//  ContentView maps NSEvent modifiers into this reducer so the TESTING.md
//  matrix can run in MicroficheTests without driving the live UI.
//

import Foundation

enum LibrarySelectionModifier: Equatable {
    case none
    case command
    case shift
}

struct LibrarySelectionState: Equatable {
    var selectedIDs: Set<UUID>
    var focusedID: UUID?
}

enum LibrarySelectionTransition {
    static func applyingPointerClick(
        fileID: UUID,
        displayedIDs: [UUID],
        state: LibrarySelectionState,
        modifier: LibrarySelectionModifier
    ) -> LibrarySelectionState {
        var nextFocusedID: UUID? = fileID
        var selectedIDs = state.selectedIDs

        switch modifier {
        case .shift:
            if let lastID = state.focusedID,
               let lastIndex = displayedIDs.firstIndex(of: lastID),
               let currentIndex = displayedIDs.firstIndex(of: fileID) {
                let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
                selectedIDs = Set(displayedIDs[range])
            } else {
                selectedIDs = [fileID]
            }
        case .command:
            if selectedIDs.contains(fileID) {
                selectedIDs.remove(fileID)
                nextFocusedID = displayedIDs.first { selectedIDs.contains($0) }
            } else {
                selectedIDs.insert(fileID)
            }
        case .none:
            selectedIDs = [fileID]
        }

        return LibrarySelectionState(
            selectedIDs: selectedIDs,
            focusedID: nextFocusedID
        )
    }

    static func applyingKeyboardMove(
        nextFileID: UUID,
        selectedIDs: Set<UUID>,
        extendSelection: Bool
    ) -> LibrarySelectionState {
        LibrarySelectionState(
            selectedIDs: extendSelection
                ? selectedIDs.union([nextFileID])
                : [nextFileID],
            focusedID: nextFileID
        )
    }

    static func selectingFirstAvailable(displayedIDs: [UUID]) -> LibrarySelectionState {
        guard let firstID = displayedIDs.first else {
            return clearingSelection()
        }
        return LibrarySelectionState(selectedIDs: [firstID], focusedID: firstID)
    }

    static func openingDetail(fileID: UUID) -> LibrarySelectionState {
        LibrarySelectionState(selectedIDs: [fileID], focusedID: fileID)
    }

    static func clearingSelection() -> LibrarySelectionState {
        LibrarySelectionState(selectedIDs: [], focusedID: nil)
    }
}
