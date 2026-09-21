//
//  AppCoordinator+Widgets.swift
//  Sajadah
//

import Foundation

extension AppCoordinator {
    /// Prayers logged from a widget button queue up as files until the app folds them in:
    /// once now, for anything tapped while the app wasn't running, then as they arrive.
    func startWidgetInbox() {
        log.mergeWidgetInbox()
        inboxWatcher = WidgetInboxWatcher { [log] in log.mergeWidgetInbox() }
        inboxWatcher?.start()
    }
}
