import AppKit

/// Collapsible sections: while Settings > General turns them on (`CollapsibleSectionsSettings`,
/// every window, live), clicking a top-level heading folds its section
/// (`App/Scripts/CollapsibleSections.js`). View > Collapse All Sections / Expand All Sections act
/// on this window's page. What is folded isn't restored with the window; live reload keeps it.
extension DocumentWindowController {
    /// Starts pages with the setting and follows it. Called once from `init`, before the first load.
    func installCollapsibleSections() {
        coordinator.collapsibleSections = collapsibleSectionsSettings.isEnabled
        NotificationCenter.default.addObserver(
            self, selector: #selector(collapsibleSectionsSettingsDidChange(_:)),
            name: CollapsibleSectionsSettings.didChangeNotification, object: collapsibleSectionsSettings)
    }

    @objc private func collapsibleSectionsSettingsDidChange(_ notification: Notification) {
        let isEnabled = collapsibleSectionsSettings.isEnabled
        guard coordinator.collapsibleSections != isEnabled else {
            return
        }
        coordinator.collapsibleSections = isEnabled
        Task { [coordinator] in
            // Fails only without a page to update (the web content process exited); the reload
            // that follows starts with the setting.
            try? await coordinator.applyCollapsibleSectionsToPage()
        }
    }

    // MARK: Actions

    /// View > Collapse All Sections.
    @objc func collapseAllSections(_ sender: Any?) {
        Task { [coordinator] in
            try? await coordinator.collapseAllSections()
        }
    }

    /// View > Expand All Sections.
    @objc func expandAllSections(_ sender: Any?) {
        Task { [coordinator] in
            try? await coordinator.expandAllSections()
        }
    }

    /// Both items are enabled only while collapsible sections are on.
    func validateSectionsItem(_ menuItem: NSMenuItem) -> Bool {
        collapsibleSectionsSettings.isEnabled
    }
}
