// ClaudeMeter design system: tokens and the components built from them.
// Follows the system light/dark appearance. Color carries meaning:
//   claude  – your allowance (plan limits, capacity, primary metrics)
//   cobalt  – history and analytics
//   live    – something is running right now
//   caution / critical – nearing / at a limit

import SwiftUI

// MARK: - Tokens

enum Radius {
    static let control: CGFloat = 6
    static let card: CGFloat = 12
}

/// The user's warning and critical levels for plan limits (Settings › Limits).
enum Thresholds {
    static var warn: Double { value("warnAt", fallback: 80) }
    static var critical: Double { value("criticalAt", fallback: 95) }

    private static func value(_ key: String, fallback: Double) -> Double {
        let v = UserDefaults.standard.double(forKey: key)
        return v > 0 ? v : fallback
    }
}

/// Color for a share of a limit: allowance, then caution and critical at the user's thresholds.
func levelColor(_ percent: Double) -> Color {
    percent >= Thresholds.critical ? .critical : percent >= Thresholds.warn ? .caution : .claude
}

enum Typo {
    static let hero    = Font.system(size: 34, weight: .semibold).monospacedDigit()
    static let display = Font.system(size: 26, weight: .semibold).monospacedDigit()
    static let metric  = Font.system(size: 15, weight: .semibold).monospacedDigit()
    static let title   = Font.system(size: 13, weight: .semibold)
    static let heading = Font.system(size: 12, weight: .medium)
    static let body    = Font.system(size: 13)
    static let unit    = Font.system(size: 15, weight: .medium)
    static let caption = Font.system(size: 11)
    static let micro   = Font.system(size: 10, weight: .medium)
    static let mono    = Font.system(size: 10.5, design: .monospaced)
}

enum Motion {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let quick  = Animation.snappy(duration: 0.22)
    static let count  = Animation.smooth(duration: 0.8)
    static let draw   = Animation.easeOut(duration: 0.9)
}

// MARK: - Environment

private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Rendering to an image: show final states, no entrance animations.
    var isSnapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}

// MARK: - Animation helpers

/// Holds a value that animates from zero when it first appears, then between updates.
/// With `instant` (e.g. while scrubbing a chart) it shows the target exactly and at
/// once, cancelling any count in flight, so it never passes through in-between values.
struct Animated<Content: View>: View {
    let target: Double
    var animation: Animation = Motion.count
    var instant = false
    let content: (Double) -> Content
    @State private var shown: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        content(instant ? target : shown ?? (reduceMotion || isSnapshot ? target : 0))
            .transaction { if instant { $0.animation = nil } }
            .onAppear {
                guard shown == nil else { return }
                if reduceMotion || instant { shown = target } else { withAnimation(animation) { shown = target } }
            }
            .onChange(of: target) { _, new in
                if reduceMotion || instant {
                    // Replace any running animation rather than retarget it
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { shown = new }
                } else {
                    withAnimation(Motion.spring) { shown = new }
                }
            }
    }
}

/// A number that counts toward its value.
struct CountingText: View, Animatable {
    var value: Double
    let format: (Double) -> String
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Text(format(value)) }
}

struct AnimatedNumber: View {
    let value: Double
    var instant = false
    let format: (Double) -> String

    var body: some View {
        Animated(target: value, instant: instant) { CountingText(value: $0, format: format) }
    }
}

/// Fades and lifts content in when the panel opens, staggered by `order`.
struct Entrance: ViewModifier {
    let order: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSnapshot) private var isSnapshot

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion || isSnapshot
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 6)
            .scaleEffect(visible ? 1 : 0.985, anchor: .top)
            .onAppear {
                withAnimation(Motion.spring.delay(Double(order) * 0.05)) { shown = true }
            }
    }
}

extension View {
    func entrance(_ order: Int) -> some View { modifier(Entrance(order: order)) }
}

/// Precise press feedback for custom buttons.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

// MARK: - Surfaces

/// The one card style. `glow` adds a soft light in one corner, in the color of what the card is about.
struct Card<Content: View>: View {
    var glow: Color? = nil
    var glowAt: UnitPoint = .topLeading
    var outline: Color? = nil
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: Space.s) { content }
            .padding(Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(Color.surface)
                    if let glow {
                        shape.fill(RadialGradient(colors: [glow.opacity(scheme == .dark ? 0.20 : 0.11), .clear],
                                                  center: glowAt, startRadius: 0, endRadius: 200))
                    }
                }
            }
            .overlay(shape.strokeBorder(outline ?? Color.hairline, lineWidth: outline == nil ? 0.5 : 1))
            .overlay(  // a faint top edge catching the light, dark mode only
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.07 : 0), .clear],
                                                  startPoint: .top, endPoint: .center), lineWidth: 0.5))
    }
}

// MARK: - Progress

/// Progress as a row of dots, lit up to `value` with a brighter head.
struct DotTrack: View, Animatable {
    var value: Double
    var tint: Color
    var dots = 32
    var size: CGFloat = 4

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Canvas { ctx, canvas in
            let gap = max(1, (canvas.width - CGFloat(dots) * size) / CGFloat(dots - 1))
            let lit = min(1, max(0, value)) * Double(dots)
            let y = (canvas.height - size) / 2
            for i in 0..<dots {
                let rect = CGRect(x: CGFloat(i) * (size + gap), y: y, width: size, height: size)
                let fill = Double(i) + 1 <= lit ? 1 : max(0, lit - Double(i))
                ctx.fill(Path(ellipseIn: rect), with: .color(.track))
                if fill > 0 { ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(fill))) }
            }
            // The head: where progress currently stands
            if lit > 0 && lit < Double(dots) {
                let i = min(dots - 1, Int(lit))
                let center = CGPoint(x: CGFloat(i) * (size + gap) + size / 2, y: canvas.height / 2)
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - size * 1.6, y: center.y - size * 1.6,
                                                width: size * 3.2, height: size * 3.2)),
                         with: .color(tint.opacity(0.22)))
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - size * 0.75, y: center.y - size * 0.75,
                                                width: size * 1.5, height: size * 1.5)),
                         with: .color(tint))
            }
        }
        .frame(height: size * 3.2)
        .accessibilityElement()
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}

/// A ring of segments, lit clockwise up to `value`.
struct RingGauge<Center: View>: View, Animatable {
    var value: Double
    var tint: Color
    var segments = 40
    var diameter: CGFloat = 64
    @ViewBuilder var center: Center

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let lit: Double = min(1, max(0, value)) * Double(segments)
                for i in 0..<segments {
                    let dot = segmentDot(i, in: size)
                    ctx.fill(dot, with: .color(.track))
                    let fill: Double = Double(i) + 1 <= lit ? 1 : max(0, lit - Double(i))
                    if fill > 0 { ctx.fill(dot, with: .color(tint.opacity(fill))) }
                }
            }
            center
        }
        .frame(width: diameter, height: diameter)
    }

    /// Segment `i`'s dot, starting at 12 o'clock and going clockwise.
    private func segmentDot(_ i: Int, in size: CGSize) -> Path {
        let angle: Double = Double(i) / Double(segments) * 2 * Double.pi - Double.pi / 2
        let radius: Double = Double(size.width) / 2 - 3
        let x: Double = Double(size.width) / 2 + radius * cos(angle)
        let y: Double = Double(size.height) / 2 + radius * sin(angle)
        return Path(ellipseIn: CGRect(x: x - 1.4, y: y - 1.4, width: 2.8, height: 2.8))
    }
}

// MARK: - Charts

/// A smooth line that draws itself left to right, with a soft area and a lit endpoint.
struct LineChart: View, Animatable {
    var values: [Double]
    var progress: Double
    var tint: Color
    var highlighted: Int?

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let top: CGFloat = 8, bottom = size.height - 2
            let peak = max(values.max() ?? 0, .leastNonzeroMagnitude)
            let points = values.enumerated().map { i, v in
                CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                        y: bottom - (bottom - top) * CGFloat(v / peak))
            }

            // Baseline grid: three faint lines
            for f in [0.0, 0.5, 1.0] {
                let y = bottom - (bottom - top) * f
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(.hairline), style: StrokeStyle(lineWidth: 0.5, dash: f == 0 ? [] : [2, 3]))
            }

            let samples = smooth(points, top: top, bottom: bottom)
            let count = max(2, Int(Double(samples.count - 1) * min(1, max(0, progress))) + 1)
            let shown = Array(samples.prefix(count))

            var area = Path()
            area.move(to: CGPoint(x: shown[0].x, y: bottom))
            shown.forEach { area.addLine(to: $0) }
            area.addLine(to: CGPoint(x: shown.last!.x, y: bottom))
            ctx.fill(area, with: .linearGradient(Gradient(colors: [tint.opacity(0.22), tint.opacity(0)]),
                                                 startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))

            var line = Path()
            line.addLines(shown)
            ctx.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

            if let i = highlighted, points.indices.contains(i) {
                var rule = Path()
                rule.move(to: CGPoint(x: points[i].x, y: top - 4))
                rule.addLine(to: CGPoint(x: points[i].x, y: bottom))
                ctx.stroke(rule, with: .color(tint.opacity(0.5)), lineWidth: 0.75)
                ctx.fill(Path(ellipseIn: CGRect(x: points[i].x - 3, y: points[i].y - 3, width: 6, height: 6)), with: .color(tint))
            } else if let end = shown.last {
                ctx.fill(Path(ellipseIn: CGRect(x: end.x - 7, y: end.y - 7, width: 14, height: 14)), with: .color(tint.opacity(0.2)))
                ctx.fill(Path(ellipseIn: CGRect(x: end.x - 2.75, y: end.y - 2.75, width: 5.5, height: 5.5)), with: .color(tint))
            }
        }
    }

    /// Catmull-Rom through the points, sampled densely and kept within the plot.
    private func smooth(_ p: [CGPoint], top: CGFloat, bottom: CGFloat) -> [CGPoint] {
        var out = [p[0]]
        let steps = max(4, 160 / p.count)
        for i in 0..<(p.count - 1) {
            let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, p.count - 1)]
            for s in 1...steps {
                let t = CGFloat(s) / CGFloat(steps), t2 = t * t, t3 = t2 * t
                let x = 0.5 * (2 * p1.x + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
                let y = 0.5 * (2 * p1.y + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
                out.append(CGPoint(x: x, y: min(bottom, max(top, y))))
            }
        }
        return out
    }
}

/// Compact bars that grow in from the baseline, staggered left to right.
/// `scale` fixes the top of the chart (e.g. 100 for percentages); `color`
/// colors each bar by its value instead of a neutral tone.
struct BarStrip: View, Animatable {
    var values: [Double]
    var progress: Double
    var tint: Color
    var highlighted: Int?
    var scale: Double? = nil
    var color: ((Double) -> Color)? = nil

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            guard !values.isEmpty else { return }
            let peak = max(scale ?? values.max() ?? 0, .leastNonzeroMagnitude)
            // Bars stay slim when there are few of them; the spare room goes between them
            let width = min(14, (size.width - 2 * CGFloat(values.count - 1)) / CGFloat(values.count))
            let gap = values.count > 1 ? (size.width - width * CGFloat(values.count)) / CGFloat(values.count - 1) : 0
            for (i, v) in values.enumerated() {
                let delay = Double(i) / Double(values.count) * 0.4
                let grow = min(1, max(0, (progress - delay) / 0.6))
                let h = max(2, size.height * CGFloat(min(1, v / peak)) * CGFloat(grow))
                let rect = CGRect(x: CGFloat(i) * (width + gap), y: size.height - h, width: width, height: h)
                let fill: Color
                if v <= 0 {
                    fill = .track
                } else if let color {
                    fill = highlighted == nil || i == highlighted ? color(v) : color(v).opacity(0.4)
                } else {
                    fill = i == highlighted ? tint : Color.primary.opacity(0.28)
                }
                ctx.fill(Path(roundedRect: rect, cornerRadius: min(1.5, width / 2)), with: .color(fill))
            }
        }
    }
}

// MARK: - Controls

/// A floating pill of choices with a sliding selection.
struct Segmented<Value: Hashable>: View {
    struct Item {
        let value: Value
        let title: String
        var icon: String? = nil
    }

    let items: [Item]
    @Binding var selection: Value
    var stretch = false
    var small = false
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                let selected = item.value == selection
                Button {
                    withAnimation(Motion.spring) { selection = item.value }
                } label: {
                    HStack(spacing: Space.xxs) {
                        if let icon = item.icon {
                            Image(systemName: icon).font(.system(size: small ? 10 : 11, weight: .medium))
                        }
                        Text(item.title)
                    }
                    .font(.system(size: small ? 11 : 12, weight: .medium))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .padding(.horizontal, small ? Space.xs : Space.s)
                    .frame(height: small ? 22 : 26)
                    .frame(maxWidth: stretch ? .infinity : nil)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Color.selection)
                                .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.surface))
        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 0.5))
    }
}

/// The primary action: a pill with a contrasting circular icon.
struct PrimaryPill: View {
    let title: String
    var detail: String? = nil
    let icon: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                ZStack {
                    Circle().fill(Color.claude)
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)
                Text(title).font(Typo.body.weight(.medium))
                if let detail {
                    Text(detail).font(Typo.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.leading, Space.xxs)
            .padding(.trailing, Space.s)
            .frame(height: 30)
            .background(Capsule().fill(Color.surface.opacity(hovering ? 2 : 1)))
            .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
    }
}

/// A round icon button for secondary actions.
struct CircleButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.surface.opacity(hovering ? 2 : 1)))
                .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Small pieces

/// A status light. Breathes only while something is happening.
struct StatusDot: View {
    let color: Color
    var active = false
    var hollow = false
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(hollow ? Color.clear : color)
            .overlay(Circle().strokeBorder(color, lineWidth: hollow ? 1 : 0))
            .frame(width: 7, height: 7)
            .background(
                Circle()
                    .fill(color.opacity(active ? (breathe ? 0 : 0.45) : 0))
                    .scaleEffect(breathe ? 2.6 : 1))
            .onAppear {
                guard active, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { breathe = true }
            }
    }
}

struct Badge: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(Capsule().fill(tint.opacity(0.08)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 0.5))
            .fixedSize()
    }
}

/// A label over a value, for metric grids.
struct MetricTile: View {
    let label: String
    let value: Double
    var instant = false
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            AnimatedNumber(value: value, instant: instant, format: format).font(Typo.metric)
            Text(label).font(Typo.micro).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
