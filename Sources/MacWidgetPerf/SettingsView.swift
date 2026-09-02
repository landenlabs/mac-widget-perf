// Copyright (c) 2026 LanDen Labs - Dennis Lang
import SwiftUI

struct SettingsView: View {
    let configId:    String
    @ObservedObject var appSettings: AppSettings

    private var cfg: Binding<WidgetConfig> {
        Binding(
            get: { self.appSettings.configs.first(where: { $0.id == self.configId }) ?? WidgetConfig() },
            set: { self.appSettings.update($0) }
        )
    }

    var body: some View {
        Form {
            // ── Sampling ──────────────────────────────────────────────────
            Section("Sampling") {
                Picker("Sample interval", selection: cfg.sampleInterval) {
                    Text("0.5 s").tag(0.5)
                    Text("1 s").tag(1.0)
                    Text("2 s").tag(2.0)
                    Text("5 s").tag(5.0)
                }
                .pickerStyle(.menu)

                Picker("History window", selection: cfg.historySeconds) {
                    Text("30 s").tag(30.0)
                    Text("1 min").tag(60.0)
                    Text("2 min").tag(120.0)
                    Text("5 min").tag(300.0)
                    Text("10 min").tag(600.0)
                }
                .pickerStyle(.menu)

                let maxSamples = appSettings.configs.first(where: { $0.id == configId })?.maxSamples ?? 0
                Text("\(maxSamples) samples")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // ── Series Visibility ─────────────────────────────────────────
            Section("Show Series") {
                Toggle("CPU usage (%)", isOn: cfg.showCpu)
                Toggle("Disk I/O (bytes/sec)", isOn: cfg.showDisk)
                Toggle("Network download (bytes/sec)", isOn: cfg.showNetwork)
            }

            // ── Colors ────────────────────────────────────────────────────
            Section("Colors") {
                colorPicker("CPU color", selection: cfg.cpuColor)
                colorPicker("Disk color", selection: cfg.diskColor)
                colorPicker("Network color", selection: cfg.networkColor)
            }

            // ── Chart Elements ────────────────────────────────────────────
            Section("Chart Elements") {
                Toggle("Show title bar", isOn: cfg.showTitle)
                Toggle("Show top CPU process in title", isOn: cfg.showTopProcess)
                Toggle("Show legend", isOn: cfg.showLegend)
                Toggle("Show grid lines", isOn: cfg.showGrid)
            }

            // ── Graph Size ────────────────────────────────────────────────
            Section("Graph Size") {
                let w = appSettings.configs.first(where: { $0.id == configId })?.graphWidth ?? 320
                VStack(alignment: .leading, spacing: 4) {
                    Text("Width: \(Int(w)) pt")
                        .font(.caption).foregroundColor(.secondary)
                    Slider(value: cfg.graphWidth, in: 160...600, step: 10)
                }

                let h = appSettings.configs.first(where: { $0.id == configId })?.graphHeight ?? 100
                VStack(alignment: .leading, spacing: 4) {
                    Text("Height: \(Int(h)) pt")
                        .font(.caption).foregroundColor(.secondary)
                    Slider(value: cfg.graphHeight, in: 40...240, step: 5)
                }
            }

            // ── Appearance ────────────────────────────────────────────────
            Section("Appearance") {
                let opacityPct = Int((appSettings.configs.first(where: { $0.id == configId })?.backgroundOpacity ?? 0.15) * 100)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Background opacity: \(opacityPct)%")
                        .font(.caption).foregroundColor(.secondary)
                    Slider(value: cfg.backgroundOpacity, in: 0...0.7, step: 0.05)
                }
            }

            // ── System ────────────────────────────────────────────────────
            Section("System") {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 320, minHeight: 480)
    }

    // MARK: - Login item helpers

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { LoginItem.isEnabled },
            set: { enabled in LoginItem.set(enabled: enabled) }
        )
    }

    // MARK: - Helpers

    private func colorPicker(_ label: String, selection: Binding<GraphColor>) -> some View {
        Picker(label, selection: selection) {
            ForEach(GraphColor.allCases) { c in
                HStack(spacing: 6) {
                    Circle().fill(c.color).frame(width: 10, height: 10)
                    Text(c.rawValue)
                }
                .tag(c)
            }
        }
        .pickerStyle(.menu)
    }
}
