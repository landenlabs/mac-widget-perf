// Copyright (c) 2026 LanDen Labs - Dennis Lang
import Foundation

struct NetworkConnectionStat: Codable {
    var maxBytesPerSec: Double
    var label: String
}

enum NetworkMaxStore {
    // 1 Mbit/s — keeps early percentages sane before any real traffic is observed.
    static let floor: Double = 125_000

    private static let storeURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("MacWidgetPerf")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("network-max.json")
    }()

    static func load() -> [String: NetworkConnectionStat] {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([String: NetworkConnectionStat].self, from: data) else {
            return [:]
        }
        return decoded
    }

    static func save(_ store: [String: NetworkConnectionStat]) {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
