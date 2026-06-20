// Copyright (c) 2026 LanDen Labs - Dennis Lang
import SwiftUI

// MARK: - ChartSeries

struct ChartSeries {
    let samples: [Double]  // normalized 0..1
    let color:   Color
}

// MARK: - StripChartView

struct StripChartView: View {
    let series:   [ChartSeries]
    var showGrid: Bool = true

    var body: some View {
        Canvas { context, size in
            drawGrid(context: context, size: size)
            for s in series where !s.samples.isEmpty {
                drawSeries(context: context, size: size, samples: s.samples, color: s.color)
            }
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        guard showGrid else { return }
        let gridColor = Color.white.opacity(0.12)
        for p in 1...3 {
            let y = size.height * CGFloat(p) / 4
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(gridColor), lineWidth: 1)
        }
    }

    private func drawSeries(context: GraphicsContext, size: CGSize,
                             samples: [Double], color: Color) {
        guard samples.count > 1 else { return }
        let stepX = size.width / CGFloat(samples.count - 1)

        func pt(_ i: Int) -> CGPoint {
            CGPoint(
                x: CGFloat(i) * stepX,
                y: size.height * (1 - CGFloat(samples[i]))
            )
        }

        var fill = Path()
        fill.move(to: CGPoint(x: 0, y: size.height))
        fill.addLine(to: pt(0))
        for i in 1..<samples.count { fill.addLine(to: pt(i)) }
        fill.addLine(to: CGPoint(x: size.width, y: size.height))
        fill.closeSubpath()
        context.fill(fill, with: .color(color.opacity(0.18)))

        var line = Path()
        line.move(to: pt(0))
        for i in 1..<samples.count { line.addLine(to: pt(i)) }
        context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5))
    }
}
