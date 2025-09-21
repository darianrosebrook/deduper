import SwiftUI
import DeduperUI

/**
 * Main entry point for the Deduper macOS application.
 *
 * - Author: @darianrosebrook
 */
@main
struct DeduperApp: App {
    public var body: some Scene {
        WindowGroup {
            DeduperUI.DeduperApp()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
