// Copyright (c) 2026 LanDen Labs - Dennis Lang
import AppKit
import SwiftUI
import Combine

// Manages one borderless desktop widget window + its PerfMonitor.
final class WidgetWindowManager: NSObject {
    let configId: String

    private var window:      NSWindow?
    private var dragOverlay: DragOverlayView?
    private let appSettings: AppSettings
    private let monitor:     PerfMonitor
    private var cancellables = Set<AnyCancellable>()

    private(set) var isDragging = false

    // Desktop level: just above the wallpaper, below normal windows
    private let desktopLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(CGWindowLevelKey(rawValue: 2)!)) + 1
    )

    private var config: WidgetConfig {
        appSettings.configs.first(where: { $0.id == configId }) ?? WidgetConfig()
    }

    init(configId: String, appSettings: AppSettings) {
        self.configId    = configId
        self.appSettings = appSettings
        self.monitor     = PerfMonitor()
    }

    // MARK: - Setup

    func setup() {
        let cfg  = config
        monitor.configure(sampleInterval: cfg.sampleInterval, maxSamples: cfg.maxSamples,
                          historySeconds: cfg.historySeconds)
        monitor.start()

        let size = cfg.windowSize
        let win = NSWindow(
            contentRect: NSRect(x: cfg.effectiveX, y: cfg.effectiveY,
                                width: size.width, height: size.height),
            styleMask:   .borderless,
            backing:     .buffered,
            defer:       false
        )
        win.level                = desktopLevel
        win.backgroundColor      = .clear
        win.isOpaque             = false
        win.hasShadow            = false
        win.ignoresMouseEvents   = true
        win.isReleasedWhenClosed = false
        win.collectionBehavior   = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.delegate             = self

        rebuildContent(win: win)
        win.orderFront(nil)
        self.window = win

        // Resize when graph dimensions change
        appSettings.$configs
            .compactMap { [weak self] cfgs in cfgs.first(where: { $0.id == self?.configId }) }
            .map { ($0.windowSize.width, $0.windowSize.height) }
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (w, h) in
                self?.window?.setContentSize(NSSize(width: w, height: h))
            }
            .store(in: &cancellables)

        // Reconfigure monitor when sampling params change
        appSettings.$configs
            .compactMap { [weak self] cfgs in cfgs.first(where: { $0.id == self?.configId }) }
            .map { ($0.sampleInterval, $0.maxSamples, $0.historySeconds) }
            .removeDuplicates { $0 == $1 }
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (interval, samples, history) in
                self?.monitor.configure(sampleInterval: interval, maxSamples: samples,
                                        historySeconds: history)
            }
            .store(in: &cancellables)
    }

    func teardown() {
        disableDragMode()
        monitor.stop()
        window?.close()
        window = nil
        cancellables.removeAll()
    }

    private func rebuildContent(win: NSWindow) {
        let root = ContentView(monitor: monitor, appSettings: appSettings, configId: configId)
        win.contentViewController = NSHostingController(rootView: root)
    }

    // MARK: - Drag Mode

    func toggleDragMode() {
        isDragging ? disableDragMode() : enableDragMode()
    }

    private func enableDragMode() {
        guard let win = window, let contentView = win.contentView else { return }
        isDragging = true
        win.level              = .floating
        win.ignoresMouseEvents = false

        let overlay = DragOverlayView(frame: contentView.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.onMove = { [weak self] origin in
            guard let self else { return }
            appSettings.updatePosition(id: configId, x: origin.x, y: origin.y)
        }
        contentView.addSubview(overlay, positioned: .above, relativeTo: nil)
        dragOverlay = overlay
    }

    private func disableDragMode() {
        guard let win = window else { return }
        isDragging = false
        dragOverlay?.removeFromSuperview()
        dragOverlay = nil
        win.level              = desktopLevel
        win.ignoresMouseEvents = true
        if let origin = win.screen != nil ? Optional(win.frame.origin) : nil {
            appSettings.updatePosition(id: configId, x: origin.x, y: origin.y)
        }
    }
}

// MARK: - NSWindowDelegate

extension WidgetWindowManager: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard isDragging, let win = window else { return }
        appSettings.updatePosition(id: configId, x: win.frame.origin.x, y: win.frame.origin.y)
    }
}
