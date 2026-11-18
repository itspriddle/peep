import Foundation
import PeepCore

/// Change marks on a loaded page (`App/Scripts/ChangeMarks.js`): after a live reload, a bar
/// beside each block that changed. The page places, fades, and counts them; Swift sends the
/// changed lines and asks it to scroll to the next one.
extension WebViewCoordinator {
    /// Marks `changes` in the loaded page, replacing any marks; `nil` or empty only clears them.
    func markChanges(_ changes: SourceChanges?) async throws {
        guard hasLoadedPage else {
            return
        }
        guard let changes, !changes.isEmpty else {
            try await clearChanges()
            return
        }
        let changed = changes.changedLines.map { [$0.lowerBound, $0.upperBound] }
        _ = try await callBridge(
            "return peepChanges.mark(changed, deleted, atEnd);",
            arguments: ["changed": changed, "deleted": changes.deletionsBefore, "atEnd": changes.deletedAtEnd])
    }

    /// Removes every change mark from the loaded page.
    func clearChanges() async throws {
        guard hasLoadedPage else {
            return
        }
        _ = try await callBridge("return peepChanges.clear();")
    }

    /// Scrolls to the next change mark out of view (below first, then from the top), unfolding
    /// its section. Returns whether there was one.
    @discardableResult
    func scrollToNextChange() async throws -> Bool {
        guard hasLoadedPage else {
            return false
        }
        let result = try await callBridge("return peepChanges.scrollToNext();")
        return (result as? NSNumber)?.boolValue == true
    }

    /// Scrolls to the first change mark in the document, unless one is already on screen,
    /// unfolding its section. Returns whether it scrolled.
    @discardableResult
    func scrollToFirstChange() async throws -> Bool {
        guard hasLoadedPage else {
            return false
        }
        let result = try await callBridge("return peepChanges.scrollToFirst();")
        return (result as? NSNumber)?.boolValue == true
    }
}
