import SwiftUI

// Widget layouts. Plain SwiftUI shapes (no Canvas, no animation), because
// widgets render as static snapshots. Shared with the app so snapshot mode can
// render them for review.

extension WidgetData.Level {
    var color: Color {
        switch self {
        case .normal:   return .claude
        case .caution:  return .caution
        case .critical: return .critical
        }
    }
}

/// The 5-hour ring with the share used in the middle.
struct WidgetRing: View {
    let gauge: WidgetData.Gauge?
    let color: Color
    var lineWidth: CGFloat = 7

    var body: some View {
        let fraction = min(1, max(0, (gauge?.percent ?? 0) / 100))
        ZStack {
            Circle().stroke(Color.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(gauge.map { "\(Int($0.percent.rounded()))" } ?? "–")
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    Text("%").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                Text("5-hour").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Dots lit up to `value`, like the panel's dotted tracks.
struct WidgetDots: View {
    let value: Double
    let color: Color
    var count = 22

    var body: some View {
        let lit = Int((min(1, max(0, value)) * Double(count)).rounded())
        // Spread across the full width so the track lines up with the value above it
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                Circle().fill(i < lit ? color : Color.track).frame(width: 3.5, height: 3.5)
                if i < count - 1 { Spacer(minLength: 2) }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct WidgetSmallView: View {
    let data: WidgetData?
    var now = Date()

    var body: some View {
        if let data, let five = data.fiveHour {
            VStack(alignment: .leading, spacing: Space.xs) {
                header(data)
                WidgetRing(gauge: five, color: data.level(five.percent).color)
                    .frame(width: 92, height: 92)
                    .frame(maxWidth: .infinity)
                Text(footer(data, five))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(data.limitAt != nil ? Color.caution : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else {
            WidgetEmptyView(data: data)
        }
    }

    private func header(_ data: WidgetData) -> some View {
        HStack(spacing: Space.xxs) {
            Text(data.account ?? "Claude").font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 0)
            if data.working { Circle().fill(Color.live).frame(width: 6, height: 6) }
        }
    }

    private func footer(_ data: WidgetData, _ five: WidgetData.Gauge) -> String {
        if let hit = data.limitAt { return "Out by \(clock(hit))" }
        return "Resets \(clock(five.resets))"
    }
}

struct WidgetMediumView: View {
    let data: WidgetData?
    var now = Date()

    var body: some View {
        if let data, let five = data.fiveHour {
            HStack(spacing: Space.m) {
                WidgetSmallView(data: data, now: now)
                    .frame(width: 124)
                VStack(alignment: .leading, spacing: Space.xs) {
                    let weeks = (data.weekly.map { [("Weekly", $0)] } ?? []) + data.models.map { ($0.name.prefix(1).uppercased() + $0.name.dropFirst(), $0.gauge) }
                    if weeks.isEmpty {
                        row("Window", detail: "Resets \(clock(five.resets))")
                    }
                    ForEach(weeks.prefix(2).indices, id: \.self) { i in
                        let (name, gauge) = weeks[i]
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Text("\(Int(gauge.percent.rounded()))%")
                                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(data.level(gauge.percent) == .normal ? Color.primary : data.level(gauge.percent).color)
                            }
                            WidgetDots(value: gauge.percent / 100, color: data.level(gauge.percent).color)
                        }
                    }
                    Spacer(minLength: 0)
                    Divider().opacity(0.5)
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(fmtCost(data.todayCost)).font(.system(size: 15, weight: .semibold).monospacedDigit())
                            Text("Today, est.").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(fmtTokens(data.todayTokens)).font(.system(size: 15, weight: .semibold).monospacedDigit())
                            Text("Tokens").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } else {
            WidgetEmptyView(data: data)
        }
    }

    private func row(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(detail).font(.system(size: 10.5, design: .monospaced))
        }
    }
}

/// No data yet, or no limits reported.
struct WidgetEmptyView: View {
    let data: WidgetData?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text("ClaudeMeter").font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(data == nil ? "Open ClaudeMeter to start." : "Limits appear after Claude Code reports them.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let data {
                Text("\(fmtCost(data.todayCost)) today").font(.system(size: 15, weight: .semibold).monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// The widget's background: system surface with a soft glow in the allowance color.
struct WidgetBackground: View {
    let level: WidgetData.Level

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [level.color.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 170)
        }
    }
}
