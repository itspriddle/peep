import AppKit

/// Raising on change: while Settings > Reading's "Bring the window to the front when a file is
/// saved" is on (`RaiseOnChangeSettings`, every window), a live reload that changed the text
/// brings one of the document's windows forward (`MarkdownDocument.raiseTarget`, the one nearest
/// the front) once the new content is shown, and activates the app.
extension DocumentWindowController {
    /// Restores the window if it is minimized, makes it key (selecting its tab), and activates
    /// the app. Activation is cooperative since macOS 14: the system may decline it while the
    /// reader is busy in another app, leaving the window front within Peep.
    func bringForwardAfterReload() {
        guard let window else {
            return
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
