// Copyright (c) 2026 LanDen Labs - Dennis Lang
import Foundation
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var configs: [WidgetConfig] {
        didSet { save() }
    }

    private let saveURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("MacWidgetPerf")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        saveURL = dir.appendingPathComponent("settings.json")

        if let data = try? Data(contentsOf: saveURL),
           let loaded = try? JSONDecoder().decode([WidgetConfig].self, from: data),
           !loaded.isEmpty {
            configs = loaded
        } else {
            configs = [WidgetConfig()]
        }
    }

    // MARK: - Mutators (each triggers save via didSet)

    func addWidget() -> WidgetConfig {
        var cfg = WidgetConfig()
        // Offset new widgets so they don't stack exactly
        let offset = Double(configs.count) * 20
        cfg.positionX = 60 + offset
        cfg.positionY = 400 + offset
        configs.append(cfg)
        return cfg
    }

    func remove(id: String) {
        configs.removeAll { $0.id == id }
        if configs.isEmpty { configs.append(WidgetConfig()) }
    }

    func update(_ config: WidgetConfig) {
        guard let idx = configs.firstIndex(where: { $0.id == config.id }) else { return }
        configs[idx] = config
    }

    func updatePosition(id: String, x: Double, y: Double) {
        guard let idx = configs.firstIndex(where: { $0.id == id }) else { return }
        configs[idx].positionX = x
        configs[idx].positionY = y
        configs[idx].screenPositions[ScreenFingerprint.current] = ScreenPosition(x: x, y: y)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }
}
