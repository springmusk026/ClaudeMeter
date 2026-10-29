// ClaudeMeter — a menu bar app that shows Claude Code usage.
// Reads only local files: the logs Claude Code writes to ~/.claude/projects and
// the live data ~/.claude/statusline.sh saves. No network calls, no credentials.

import SwiftUI

@main
struct ClaudeMeterApp: App {
    @StateObject private var store = UsageStore()
    @AppStorage("menuLabel") private var labelMode = LabelMode.limit
    @AppStorage("dailyBudget") private var budget = 0.0

    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            PanelSnapshot.write(to: URL(fileURLWithPath: args[i + 1]), demo: args.contains("--demo"))
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(store)
        } label: {
            MenuBarLabel(all: store.snap(UsageStore.all),
                         current: store.snap(store.currentAccount.id),
                         currentName: store.multiAccount ? store.currentAccount.name : nil,
                         state: store.state(),
                         mode: labelMode, budget: budget)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(store).tint(.claude)
        }
    }
}

enum LabelMode: String, CaseIterable, Identifiable {
    case limit, todayCost, windowCost, windowTime, icon
    var id: Self { self }

    var title: String {
        switch self {
        case .limit:      return "5-hour limit used"
        case .todayCost:  return "Today's cost"
        case .windowCost: return "5-hour window cost"
        case .windowTime: return "Time until window reset"
        case .icon:       return "Icon only"
        }
    }
}

/// The status item, drawn as a single template image: it follows the menu bar's
/// light/dark colors like system icons (menu bar labels also drop symbols mixed into text).
struct MenuBarLabel: View {
    let all: Snapshot
    let current: Snapshot          // the account used most recently
    let currentName: String?       // set when there are several accounts
    let state: PanelState
    let mode: LabelMode
    let budget: Double

    var body: some View {
        Image(nsImage: rendered)
    }

    var content: MenuBarContent {
        let five = current.live.fiveHour
        let window = current.window
        // The ring is always the 5-hour window: share of the limit used when
        // Claude Code reports it, otherwise time elapsed in the estimated window
        let fraction = five.map { $0.usedPercent / 100 }
            ?? window.map { Date().timeIntervalSince($0.start) / WindowStats.length }
        let critical: Bool = {
            if case .limitReached = state { return true }
            return (five?.usedPercent ?? 0) >= 95 || (budget > 0 && all.today.cost >= budget)
        }()
        let working: Bool = { if case .working = state { return true }; return false }()
        return MenuBarContent(fraction: fraction, initial: currentName.map { String($0.prefix(1)).uppercased() },
                              working: working, critical: critical, text: text)
    }

    private var rendered: NSImage {
        let renderer = ImageRenderer(content: content.foregroundStyle(.black))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        image.accessibilityDescription = "ClaudeMeter\(text.map { ", \($0)" } ?? "")"
        return image
    }

    private var text: String? {
        let w = current.window
        switch mode {
        case .limit:
            if let limit = current.live.fiveHour { return "\(Int(limit.usedPercent.rounded()))%" }
            return w.map { fmtCost($0.bucket.cost) }
        case .todayCost:  return fmtCost(all.today.cost)
        case .windowCost: return w.map { fmtCost($0.bucket.cost) }
        case .windowTime: return w.map { fmtDuration($0.end.timeIntervalSinceNow) }
        case .icon:       return nil
        }
    }
}

/// Ring glyph plus optional value: the menu bar's version of the panel's ring gauge.
struct MenuBarContent: View {
    let fraction: Double?
    let initial: String?
    let working: Bool
    let critical: Bool
    let text: String?

    var body: some View {
        HStack(spacing: 5) {
            MenuGlyph(fraction: critical ? 1 : fraction, initial: initial, working: working, critical: critical)
                .frame(width: 16, height: 16)
            if let text {
                Text(text).font(.system(size: 13, weight: .medium).monospacedDigit())
            }
        }
        .padding(.vertical, 1)
    }
}

/// A ring filled clockwise by `fraction` over a dim track. Solid rather than
/// segmented: at menu bar size, segments read as a loading spinner.
/// Centre: "!" at a limit, the account's initial with several accounts, or a dot while Claude works.
struct MenuGlyph: View {
    let fraction: Double?
    let initial: String?
    let working: Bool
    let critical: Bool

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width / 2 - 1.3
            let fill = min(1, max(0, fraction ?? 0))

            var track = Path()
            track.addArc(center: center, radius: radius, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
            ctx.opacity = 0.3
            ctx.stroke(track, with: .foreground, lineWidth: 2.2)
            ctx.opacity = 1

            if fill > 0 {
                var arc = Path()
                arc.addArc(center: center, radius: radius, startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + 360 * max(fill, 0.03)), clockwise: false)
                ctx.stroke(arc, with: .foreground, style: StrokeStyle(lineWidth: 2.2, lineCap: fill < 1 ? .round : .butt))
            }

            if critical {
                ctx.draw(Text("!").font(.system(size: 9.5, weight: .heavy)), at: center)
            } else if let initial {
                ctx.draw(Text(initial).font(.system(size: 8, weight: .bold)), at: CGPoint(x: center.x, y: center.y + 0.3))
            } else if working {
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)), with: .foreground)
            }
        }
    }
}
