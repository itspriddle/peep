import Foundation

/// Collapsible sections on a loaded page (`App/Scripts/CollapsibleSections.js`): clicking a
/// top-level heading folds its section. The page does the folding; Swift turns it on or off and
/// sends View > Collapse All Sections / Expand All Sections.
extension WebViewCoordinator {
    /// Turns collapsible sections on or off in the loaded page, if any, from
    /// `collapsibleSections`. Turning them off unfolds everything. A page starts with them off,
    /// so `load(_:baseURL:)` calls this after each load while they are on.
    func applyCollapsibleSectionsToPage() async throws {
        guard hasLoadedPage else {
            return
        }
        let result = try await callBridge(
            "return peepSections.setEnabled(on);", arguments: ["on": collapsibleSections])
        guard (result as? NSNumber)?.boolValue == true else {
            throw BridgeError.unexpectedResult
        }
    }

    /// Folds every top-level section. Does nothing while collapsible sections are off.
    func collapseAllSections() async throws {
        guard hasLoadedPage, collapsibleSections else {
            return
        }
        _ = try await callBridge("return peepSections.collapseAll();")
    }

    /// Unfolds every section. Does nothing while collapsible sections are off.
    func expandAllSections() async throws {
        guard hasLoadedPage, collapsibleSections else {
            return
        }
        _ = try await callBridge("return peepSections.expandAll();")
    }
}
