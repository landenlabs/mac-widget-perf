// Copyright (c) 2026 LanDen Labs - Dennis Lang
import AppKit
import SwiftUI

// MARK: - Animated GIF view

struct AnimatedGIFView: NSViewRepresentable {
    let url: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyDown
        v.animates = false
        if let url { context.coordinator.load(url: url, into: v) }
        return v
    }

    func updateNSView(_ v: NSImageView, context: Context) {}

    class Coordinator {
        private var timer: Timer?
        private var frames: [(image: NSImage, duration: TimeInterval)] = []
        private var frameIndex = 0
        private weak var imageView: NSImageView?

        func load(url: URL, into imageView: NSImageView) {
            self.imageView = imageView
            guard let data = try? Data(contentsOf: url) else { return }
            guard let source = NSImage(data: data),
                  let rep = source.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
                  let frameCount = rep.value(forProperty: .frameCount) as? Int,
                  frameCount > 1
            else {
                imageView.image = NSImage(data: data)
                return
            }
            frames = (0..<frameCount).compactMap { i in
                rep.setProperty(.currentFrame, withValue: NSNumber(value: i))
                let duration = (rep.value(forProperty: .currentFrameDuration) as? TimeInterval) ?? 0.1
                guard let cg = rep.cgImage else { return nil }
                return (NSImage(cgImage: cg, size: rep.size), duration)
            }
            frameIndex = 0
            show(frameIndex)
            scheduleNext()
        }

        private func show(_ index: Int) { imageView?.image = frames[index].image }

        private func scheduleNext() {
            let delay = frames[frameIndex].duration
            timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self else { return }
                let next = self.frameIndex + 1
                guard next < self.frames.count else { return }
                self.frameIndex = next
                self.show(next)
                self.scheduleNext()
            }
        }

        deinit { timer?.invalidate() }
    }
}

// MARK: - AboutView

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let gifURL = Bundle.module.url(forResource: "landen_labs_about", withExtension: "gif") {
                    AnimatedGIFView(url: gifURL)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                }

                HStack(spacing: 16) {
                    Image(systemName: "chart.bar.xaxis.ascending.badge.clock")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Performance Widget - LanDen Labs (2026)")
                            .font(.title.bold())
                        Text("Version \(versionString)")
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description").font(.headline)
                    Text("A lightweight desktop wallpaper widget that displays real-time CPU load, disk I/O, and network traffic as scrolling strip charts. Supports multiple independently configured widget instances, each remembering its position per screen layout.")
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Metrics").font(.headline)
                    infoRow("CPU",     "Processor load (0–100%), all cores combined")
                    infoRow("Disk",    "Combined read + write bytes/sec, auto-scaled to learned peak")
                    infoRow("Network", "Download bytes/sec, auto-scaled to learned peak")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Details").font(.headline)
                    infoRow("Author",   "Dennis Lang")
                    infoRow("Built",    buildDate)
                    infoRow("Settings", settingsPath)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: settingsPath)]
                        )
                    }
                    .padding(.top, 4)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Created by LanDen Labs (2026)")
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Text("GitHub:")
                            .foregroundColor(.secondary)
                        Link("https://github.com/landenlabs/MacWidgetPerf",
                             destination: URL(string: "https://github.com/landenlabs/MacWidgetPerf")!)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? appVersion
        if let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String { return "\(v) (\(b))" }
        return v
    }

    private var buildDate: String {
        guard let url = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else { return "—" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    private var settingsPath: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("MacWidgetPerf/settings.json").path
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label).foregroundColor(.secondary).frame(width: 72, alignment: .leading)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
