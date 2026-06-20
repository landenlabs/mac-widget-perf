// Copyright (c) 2026 LanDen Labs - Dennis Lang
import Foundation
import AppKit
import SwiftUI

// MARK: - GraphColor

enum GraphColor: String, Codable, CaseIterable, Identifiable {
    case green  = "Green"
    case cyan   = "Cyan"
    case blue   = "Blue"
    case orange = "Orange"
    case yellow = "Yellow"
    case white  = "White"
    case red    = "Red"
    case pink   = "Pink"
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .green:  return .green
        case .cyan:   return .cyan
        case .blue:   return Color(red: 0.54, green: 0.71, blue: 0.98) // cornflower
        case .orange: return .orange
        case .yellow: return .yellow
        case .white:  return .white
        case .red:    return Color(red: 1, green: 0.35, blue: 0.35)
        case .pink:   return Color(red: 1, green: 0.55, blue: 0.75)
        }
    }
}

// MARK: - ScreenPosition

struct ScreenPosition: Codable, Equatable {
    var x: Double
    var y: Double
}

// MARK: - ScreenFingerprint

enum ScreenFingerprint {
    static var current: String {
        NSScreen.screens
            .sorted { $0.frame.minX < $1.frame.minX || ($0.frame.minX == $1.frame.minX && $0.frame.minY < $1.frame.minY) }
            .map { "\(Int($0.frame.width))x\(Int($0.frame.height))@\(Int($0.frame.origin.x)),\(Int($0.frame.origin.y))" }
            .joined(separator: "|")
    }
}

// MARK: - WidgetConfig

struct WidgetConfig: Codable {
    var id:                String     = UUID().uuidString
    var sampleInterval:    Double     = 1.0
    var historySeconds:    Double     = 120.0
    var graphWidth:        Double     = 320.0
    var graphHeight:       Double     = 100.0
    var backgroundOpacity: Double     = 0.15

    // Series visibility
    var showCpu:        Bool = true
    var showDisk:       Bool = true
    var showNetwork:    Bool = true
    var showTitle:      Bool = true
    var showLegend:     Bool = true
    var showGrid:       Bool = true
    var showTopProcess: Bool = true

    // Colors
    var cpuColor:     GraphColor = .blue
    var diskColor:    GraphColor = .orange
    var networkColor: GraphColor = .green

    // Position per screen layout
    var positionX:       Double = 40.0
    var positionY:       Double = 400.0
    var screenPositions: [String: ScreenPosition] = [:]

    // MARK: Computed

    var maxSamples: Int {
        max(10, Int((historySeconds / sampleInterval).rounded()))
    }

    static let headerHeight: Double = 20
    static let legendHeight: Double = 18
    static let verticalPadding: Double = 16

    var windowSize: CGSize {
        let titleH  = showTitle  ? WidgetConfig.headerHeight : 0
        let legendH = showLegend ? WidgetConfig.legendHeight : 0
        return CGSize(
            width:  graphWidth,
            height: graphHeight + titleH + legendH + WidgetConfig.verticalPadding + 4
        )
    }

    var effectiveX: Double { screenPositions[ScreenFingerprint.current]?.x ?? positionX }
    var effectiveY: Double { screenPositions[ScreenFingerprint.current]?.y ?? positionY }

    // MARK: Codable with forward-compatible defaults

    enum CodingKeys: String, CodingKey {
        case id, sampleInterval, historySeconds, graphWidth, graphHeight, backgroundOpacity
        case showCpu, showDisk, showNetwork, showTitle, showLegend, showGrid, showTopProcess
        case cpuColor, diskColor, networkColor
        case positionX, positionY, screenPositions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = (try? c.decode(String.self,     forKey: .id))                ?? UUID().uuidString
        sampleInterval    = (try? c.decode(Double.self,     forKey: .sampleInterval))    ?? 1.0
        historySeconds    = (try? c.decode(Double.self,     forKey: .historySeconds))    ?? 120.0
        graphWidth        = (try? c.decode(Double.self,     forKey: .graphWidth))        ?? 320.0
        graphHeight       = (try? c.decode(Double.self,     forKey: .graphHeight))       ?? 100.0
        backgroundOpacity = (try? c.decode(Double.self,     forKey: .backgroundOpacity)) ?? 0.15
        showCpu           = (try? c.decode(Bool.self,       forKey: .showCpu))           ?? true
        showDisk          = (try? c.decode(Bool.self,       forKey: .showDisk))          ?? true
        showNetwork       = (try? c.decode(Bool.self,       forKey: .showNetwork))       ?? true
        showTitle         = (try? c.decode(Bool.self,       forKey: .showTitle))         ?? true
        showLegend        = (try? c.decode(Bool.self,       forKey: .showLegend))        ?? true
        showGrid          = (try? c.decode(Bool.self,       forKey: .showGrid))          ?? true
        showTopProcess    = (try? c.decode(Bool.self,       forKey: .showTopProcess))    ?? true
        cpuColor          = (try? c.decode(GraphColor.self, forKey: .cpuColor))          ?? .blue
        diskColor         = (try? c.decode(GraphColor.self, forKey: .diskColor))         ?? .orange
        networkColor      = (try? c.decode(GraphColor.self, forKey: .networkColor))      ?? .green
        positionX         = (try? c.decode(Double.self,     forKey: .positionX))         ?? 40.0
        positionY         = (try? c.decode(Double.self,     forKey: .positionY))         ?? 400.0
        screenPositions   = (try? c.decode([String: ScreenPosition].self, forKey: .screenPositions)) ?? [:]
    }

    init() {}
}
