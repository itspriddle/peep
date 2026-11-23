import AppKit

/// Raising on change: while Settings > Reading's "Bring the window to the front when a file is
/// saved" is on (`RaiseOnChangeSettings`, every window), a live reload that changed the text
/// brings one of the document's windows forward (`MarkdownDocument.raiseTarget`, the one nearest
/// the front) once the new content is shown, and activates the app.
extension DocumentWindowController {
    /// Restores the window if it is minimized, makes it key (selecting its tab), and activates
    /// the app, taking focus from the app the reader saved in (the setting's whole point).
    ///
    /// `NSApp.activate()` is cooperative since macOS 14: from the background it only succeeds
    /// when the active app yields, which an editor saving a file never does, so the window
    /// stayed behind it. `activate(ignoringOtherApps: true)` still activates regardless (only
    /// marked to be deprecated, so no warning); revisit if a release ignores it.
    func bringForwardAfterReload() {
        guard let window else {
            return
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
