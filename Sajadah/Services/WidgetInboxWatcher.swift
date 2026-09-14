//
//  WidgetInboxWatcher.swift
//  Sajadah
//

import Foundation

/// Wakes the app when a widget button writes a tap, so the menubar and the window follow
/// within a moment rather than at the next launch.
///
/// A kernel event on the inbox directory rather than polling: the app already has a ticker,
/// but it sleeps a minute at a time when nothing is on screen, and a minute is long enough to
/// tap a widget, open the popover and find it disagreeing with the desktop.
@MainActor
final class WidgetInboxWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    /// Creates the directory if it can — the app has write access to the widget's container
    /// for the cache mirror — and starts watching. Silently does nothing where it can't: an
    /// unsigned build with no widget container yet has no widget to hear from either.
    func start() {
        guard source == nil, let directory = AppFiles.widgetInboxURL else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.onChange()
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        source.resume()
        self.source = source
    }

    deinit {
        source?.cancel()
    }
}
