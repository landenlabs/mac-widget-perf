// Copyright (c) 2026 LanDen Labs - Dennis Lang
import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private let appSettings = AppSettings.shared
    private var managers:   [WidgetWindowManager] = []
    private var statusItem: NSStatusItem?
    private var settingsControllers: [String: NSWindowController] = [:]  // keyed by widget id
    private var aboutWindowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupWidgets()
        setupStatusItem()

        // React to new widgets added or removed from settings
        appSettings.$configs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] configs in
                self?.syncManagers(to: configs)
            }
            .store(in: &cancellables)
    }

    private func setupWidgets() {
        for cfg in appSettings.configs {
            let mgr = WidgetWindowManager(configId: cfg.id, appSettings: appSettings)
            mgr.setup()
            managers.append(mgr)
        }
    }

    private func syncManagers(to configs: [WidgetConfig]) {
        let existingIds = Set(managers.map { $0.configId })
        let targetIds   = Set(configs.map { $0.id })

        // Add new
        for cfg in configs where !existingIds.contains(cfg.id) {
            let mgr = WidgetWindowManager(configId: cfg.id, appSettings: appSettings)
            mgr.setup()
            managers.append(mgr)
        }

        // Remove deleted
        for id in existingIds where !targetIds.contains(id) {
            if let mgr = managers.first(where: { $0.configId == id }) {
                mgr.teardown()
                managers.removeAll { $0.configId == id }
                settingsControllers.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(
            systemSymbolName: "chart.bar.xaxis",
            accessibilityDescription: "Performance Widget"
        )
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    // MARK: - Window helpers

    private func openWindow(
        width: CGFloat, height: CGFloat,
        title: String,
        rootView: some View,
        controller: inout NSWindowController?
    ) {
        if controller == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask:   [.titled, .closable, .resizable, .miniaturizable],
                backing:     .buffered,
                defer:       false
            )
            win.title       = title
            win.contentView = NSHostingView(rootView: rootView)
            win.center()
            let wc = NSWindowController(window: win)
            controller = wc
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: win, queue: .main
            ) { [weak self] _ in
                if self?.aboutWindowController?.window === win {
                    self?.aboutWindowController = nil
                }
                self?.settingsControllers = self?.settingsControllers.filter { $0.value.window !== win } ?? [:]
            }
        }
        controller?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Actions

    @objc func addWidget() {
        _ = appSettings.addWidget()
    }

    @objc func toggleDragMode(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let mgr = managers.first(where: { $0.configId == id }) else { return }
        mgr.toggleDragMode()
    }

    @objc func openSettings(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              appSettings.configs.contains(where: { $0.id == id }) else { return }
        var ctrl = settingsControllers[id]
        let view = SettingsView(configId: id, appSettings: appSettings)
        openWindow(width: 360, height: 560, title: "Performance Widget — Settings", rootView: view, controller: &ctrl)
        settingsControllers[id] = ctrl
    }

    @objc func removeWidget(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        appSettings.remove(id: id)
    }

    @objc func openAbout() {
        openWindow(width: 480, height: 540, title: "About Performance Widget",
                   rootView: AboutView(), controller: &aboutWindowController)
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(titleItem("Wid-Perf"))
        menu.addItem(.separator())

        menu.addItem(item("Add Widget", action: #selector(addWidget)))
        menu.addItem(.separator())

        for (index, cfg) in appSettings.configs.enumerated() {
            let mgr      = managers.first(where: { $0.configId == cfg.id })
            let dragging = mgr?.isDragging ?? false
            let label    = appSettings.configs.count > 1 ? "Widget \(index + 1)" : "Widget"

            let header = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            let moveTitle = dragging ? "Done Moving" : "Move Widget…"
            let moveItem = item(moveTitle, action: #selector(toggleDragMode))
            moveItem.representedObject = cfg.id
            menu.addItem(moveItem)

            let settingsItem = item("Settings…", action: #selector(openSettings), key: index == 0 ? "," : "")
            settingsItem.representedObject = cfg.id
            menu.addItem(settingsItem)

            if appSettings.configs.count > 1 {
                let removeItem = item("Remove Widget", action: #selector(removeWidget))
                removeItem.representedObject = cfg.id
                menu.addItem(removeItem)
            }

            menu.addItem(.separator())
        }

        menu.addItem(item("About…", action: #selector(openAbout)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.addItem(.separator())
        menu.addItem(versionItem())
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        return it
    }

    /// Bold, non-clickable title shown at the top of the menu.
    private func titleItem(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
        it.isEnabled = false
        return it
    }

    /// Small, light, non-clickable version label shown at the bottom of the menu.
    private func versionItem() -> NSMenuItem {
        let text = "v\(appVersion)"
        let it = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        it.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                         .foregroundColor: NSColor.secondaryLabelColor])
        it.isEnabled = false
        return it
    }
}
