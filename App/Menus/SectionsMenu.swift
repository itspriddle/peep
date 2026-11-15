import AppKit

/// View > Collapse All Sections / Expand All Sections: fold or unfold every section of the page
/// (collapsible sections, Settings > General). The actions are in
/// `DocumentWindowController+CollapsibleSections.swift`; the items are disabled while the
/// setting is off.
enum SectionsMenu: MenuContribution {
    static func contribute(to menu: MainMenu) {
        menu.addGroup(
            [
                NSMenuItem(
                    "Collapse All Sections", action: #selector(DocumentWindowController.collapseAllSections(_:))),
                NSMenuItem(
                    "Expand All Sections", action: #selector(DocumentWindowController.expandAllSections(_:))),
            ], to: .view)
    }
}
