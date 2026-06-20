// Copyright (c) 2026 LanDen Labs - Dennis Lang
import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor:     PerfMonitor
    @ObservedObject var appSettings: AppSettings
    let configId: String

    private var config: WidgetConfig {
        appSettings.configs.first(where: { $0.id == configId }) ?? WidgetConfig()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if config.showTitle {
                titleHeader
            }

            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.25))
                    .frame(height: config.graphHeight)

                StripChartView(series: activeSeries, showGrid: config.showGrid)
                    .frame(height: config.graphHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if config.showLegend {
                legendRow
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(config.backgroundOpacity))
        )
        .frame(width: config.windowSize.width, height: config.windowSize.height)
    }

    // MARK: - Title

    private var titleHeader: some View {
        HStack(spacing: 4) {
            if config.showTopProcess, let name = monitor.topProcessName {
                Text("🔥")
                    .font(.system(size: 9))
                Text(name)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(config.cpuColor.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(String(format: "%.0f%%", monitor.topProcessPercent))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(config.cpuColor.color.opacity(0.7))
            } else {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
                Text("Performance")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            Spacer()
            Text(formatDuration(config.historySeconds))
                .font(.system(size: 8))
                .foregroundColor(.secondary.opacity(0.4))
        }
        .frame(height: WidgetConfig.headerHeight)
    }

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: 8) {
            if config.showCpu {
                legendItem(
                    icon: "cpu",
                    label: String(format: "CPU %.0f%%", monitor.currentCpu),
                    color: config.cpuColor.color
                )
            }
            if config.showDisk {
                legendItem(
                    icon: "internaldrive",
                    label: "Disk \(formatBytes(monitor.currentDisk))",
                    color: config.diskColor.color
                )
            }
            if config.showNetwork {
                legendItem(
                    icon: "arrow.down",
                    label: "Net \(formatBytes(monitor.currentNetDown))",
                    color: config.networkColor.color
                )
            }
            Spacer()
        }
        .frame(height: WidgetConfig.legendHeight)
    }

    private func legendItem(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(color)
        }
    }

    // MARK: - Series

    private var activeSeries: [ChartSeries] {
        var result: [ChartSeries] = []
        if config.showDisk    { result.append(ChartSeries(samples: monitor.diskSamples,    color: config.diskColor.color)) }
        if config.showNetwork { result.append(ChartSeries(samples: monitor.netDownSamples, color: config.networkColor.color)) }
        if config.showCpu     { result.append(ChartSeries(samples: monitor.cpuSamples,     color: config.cpuColor.color)) }
        return result
    }

    // MARK: - Formatting

    private func formatBytes(_ bytesPerSec: Double) -> String {
        switch bytesPerSec {
        case 1_000_000_000...: return String(format: "%.1fGB/s", bytesPerSec / 1_000_000_000)
        case 1_000_000...:     return String(format: "%.1fMB/s", bytesPerSec / 1_000_000)
        case 1_000...:         return String(format: "%.0fKB/s", bytesPerSec / 1_000)
        default:               return String(format: "%.0fB/s",  bytesPerSec)
        }
    }

    private func formatDuration(_ s: Double) -> String {
        Int(s) < 60 ? "\(Int(s))s" : "\(Int(s) / 60)m"
    }
}
