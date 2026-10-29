import SwiftUI

enum Metric: String, CaseIterable, Identifiable {
    case cost, tokens
    var id: Self { self }
    var title: String { self == .cost ? "Cost" : "Tokens" }
    func value(_ b: Bucket) -> Double { self == .cost ? b.cost : Double(b.tokens) }
    func format(_ v: Double) -> String { self == .cost ? fmtCost(v) : fmtTokens(Int(v)) }
}

enum Breakdown: String, CaseIterable, Identifiable {
    case models, projects, sessions
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum Tab: String, CaseIterable, Identifiable {
    case now, usage, accounts
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .now:      return "gauge.with.dots.needle.50percent"
        case .usage:    return "chart.xyaxis.line"
        case .accounts: return "person.2"
        }
    }
}


struct PanelView: View {
    var previewTab: Tab? = nil   // set when rendering snapshots

    @EnvironmentObject var store: UsageStore
    @Environment(\.openSettings) private var openSettings
    @AppStorage("tab") private var tab = Tab.now
    @AppStorage("period") private var period = Period.week
    @AppStorage("metric") private var metric = Metric.cost
    @AppStorage("breakdown") private var breakdown = Breakdown.models
    @AppStorage("dailyBudget") private var budget = 0.0
    @AppStorage("scope") private var scope = UsageStore.all

    /// The account being viewed, or all of them; falls back if that account was removed.
    private var scopeID: String {
        store.multiAccount && store.account(scope) != nil ? scope : UsageStore.all
    }

    var body: some View {
        let current = previewTab ?? tab
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Space.m)
                .padding(.top, Space.m)
            Segmented(items: Tab.allCases.map { .init(value: $0, title: $0.title, icon: $0.icon) },
                      selection: previewTab == nil ? $tab : .constant(current), stretch: true)
                .padding(.horizontal, Space.m)
                .padding(.top, Space.s)

            Group {
                if store.loading && store.snaps.isEmpty {
                    LoadingState()
                } else {
                    switch current {
                    case .now:      NowTab(scopeID: scopeID, budget: budget, metric: metric)
                    case .usage:    UsageTab(scopeID: scopeID, period: $period, metric: $metric, breakdown: $breakdown)
                    case .accounts: AccountsTab(openSettings: showSettings)
                    }
                }
            }
            .id(current)
            .transition(.opacity.combined(with: .offset(y: 4)))
            .padding(.horizontal, Space.m)
            .padding(.top, Space.s)

            footer
                .padding(Space.m)
        }
        .frame(width: 344)
        .animation(Motion.spring, value: current)
        .onAppear { if previewTab == nil { store.probeLimits() } }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(alignment: .top, spacing: Space.xs) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("ClaudeMeter").font(Typo.title)
                TimelineView(.periodic(from: .now, by: 10)) { ctx in
                    StatusLine(state: store.state(now: ctx.date), now: ctx.date)
                }
            }
            Spacer(minLength: Space.xs)
            if store.multiAccount { scopeMenu }
        }
    }

    private var scopeMenu: some View {
        Menu {
            Picker("Show", selection: $scope) {
                Text("All accounts").tag(UsageStore.all)
                ForEach(store.accounts) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: Space.xxs) {
                Text(store.account(scopeID)?.name ?? "All accounts")
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(Typo.caption.weight(.medium))
            .padding(.horizontal, Space.xs)
            .frame(height: 22)
            .background(Capsule().fill(Color.surface))
            .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 0.5))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Show stats for one account or all")
    }

    private var footer: some View {
        HStack(spacing: Space.xs) {
            PrimaryPill(title: "Open Claude Code",
                        detail: store.multiAccount ? store.activeAccount.name : nil,
                        icon: "terminal") {
                Accounts.launch(store.activeAccount)
            }
            .help("Start a session in Terminal with \(store.activeAccount.name)")
            Spacer()
            CircleButton(icon: "gearshape", help: "Settings (⌘,)", action: showSettings)
                .keyboardShortcut(",")
            CircleButton(icon: "power", help: "Quit ClaudeMeter (⌘Q)") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func showSettings() {
        NSApp.activate()
        openSettings()
    }
}

// MARK: - Status line

/// The panel's one-line answer to "what's going on right now?"
struct StatusLine: View {
    let state: PanelState
    let now: Date

    var body: some View {
        Group {
            switch state {
            case .loading:
                row { ProgressView().controlSize(.mini) } text: { Text("Reading usage…").foregroundStyle(.secondary) }
            case let .limitReached(account, kind, resetsAt, alternative):
                row { Image(systemName: "exclamationmark.octagon.fill").font(.system(size: 9)).foregroundStyle(Color.critical) } text: {
                    Text("\(account.map { "\($0) hit its" } ?? "Hit the") \(kind) limit · back in \(fmtDuration(resetsAt.timeIntervalSince(now)))\(alternative.map { " · \($0)" } ?? "")")
                        .foregroundStyle(Color.critical)
                }
            case let .working(project, model, others):
                row { StatusDot(color: .live, active: true) } text: {
                    Text("Working in \(project.isEmpty ? "a session" : project) · \(model)\(others > 0 ? " · +\(others) more" : "")")
                        .foregroundStyle(.secondary)
                }
            case let .idle(since):
                row { StatusDot(color: .secondary) } text: {
                    Text("Idle · last activity \(relative(since))").foregroundStyle(.secondary)
                }
            case .noSession:
                row { StatusDot(color: .secondary, hollow: true) } text: {
                    Text("No Claude Code session yet").foregroundStyle(.secondary)
                }
            }
        }
        .font(Typo.caption)
    }

    private func row<Icon: View, Label: View>(@ViewBuilder _ icon: () -> Icon, @ViewBuilder text: () -> Label) -> some View {
        HStack(spacing: 6) {
            icon().frame(width: 8)
            text().lineLimit(1).truncationMode(.middle)
        }
    }

    private func relative(_ date: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: now)
    }
}

// MARK: - Now

struct NowTab: View {
    let scopeID: String
    let budget: Double
    let metric: Metric
    @EnvironmentObject var store: UsageStore

    var body: some View {
        let s = store.snap(scopeID)
        // Limits belong to one account: with all accounts in view, show the one in use
        let limitAccount = scopeID == UsageStore.all ? store.currentAccount : (store.account(scopeID) ?? .main)
        let limits = store.snap(limitAccount.id)

        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            VStack(spacing: Space.s) {
                if limits.live.hasLimits {
                    LimitHero(window: limits.window, live: limits.live, now: ctx.date,
                              account: store.multiAccount ? limitAccount.name : nil,
                              plan: store.profile(limitAccount.id).plan)
                        .entrance(0)
                } else {
                    WindowHero(window: s.window, now: ctx.date).entrance(0)
                }
                if !s.live.sessions.isEmpty {
                    LiveCard(sessions: s.live.sessions, now: ctx.date,
                             accountNames: store.multiAccount && scopeID == UsageStore.all
                                ? Dictionary(uniqueKeysWithValues: store.accounts.map { ($0.id, $0.name) }) : [:])
                        .entrance(1)
                }
                if s.hasLogs {
                    TodayCard(s: s, budget: budget, metric: metric, now: ctx.date).entrance(2)
                } else {
                    EmptyCard(text: scopeID == UsageStore.all ? "No Claude Code activity yet" : "No activity for this account yet",
                              detail: "Usage appears here as soon as you use Claude Code.")
                        .entrance(2)
                }
            }
        }
    }
}

/// The number that matters most: how much of the 5-hour allowance is used.
struct LimitHero: View {
    let window: WindowStats?
    let live: LiveData
    let now: Date
    let account: String?
    let plan: String?

    var body: some View {
        let five = live.fiveHour
        let percent = five?.usedPercent ?? 0
        let tint = levelColor(percent)
        Card(glow: tint) {
            HStack(spacing: Space.xs) {
                Text("5-hour limit").font(Typo.heading).foregroundStyle(.secondary)
                Spacer()
                if let account { Badge(text: account) }
                if let plan { Badge(text: plan) }
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        AnimatedNumber(value: percent) { "\(Int($0.rounded()))" }
                            .font(Typo.hero)
                            .foregroundStyle(percent >= Thresholds.warn ? tint : Color.primary)
                        Text("%").font(Typo.unit).foregroundStyle(.secondary)
                    }
                    Text(percent >= 100 ? "Limit reached" : "of your allowance used")
                        .font(Typo.caption)
                        .foregroundStyle(percent >= 100 ? Color.critical : Color.secondary)
                }
                Spacer()
                if let five {
                    let elapsed = 1 - five.resetsAt.timeIntervalSince(now) / WindowStats.length
                    Animated(target: elapsed) { v in
                        RingGauge(value: v, tint: .primary.opacity(0.55)) {
                            VStack(spacing: 0) {
                                Text(fmtDuration(five.resetsAt.timeIntervalSince(now)))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                Text("left").font(Typo.micro).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .help("Time left in this 5-hour window")
                }
            }

            Animated(target: percent / 100) { DotTrack(value: $0, tint: tint) }

            HStack(spacing: Space.xs) {
                if let five { Text("Resets \(clock(five.resetsAt))").font(Typo.mono).foregroundStyle(.secondary) }
                Spacer()
                if let note { Text(note.text).font(Typo.caption).foregroundStyle(note.color).lineLimit(1) }
            }

            if live.sevenDay != nil || !live.modelWeeks.isEmpty {
                WeeklyRows(week: live.sevenDay, models: live.modelWeeks)
            }

            if let updated = live.limitsUpdated, now.timeIntervalSince(updated) > 5 * 60 {
                Label("As of \(clock(updated)). Claude Code reports limits while a session runs.", systemImage: "clock")
                    .font(Typo.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var note: (text: String, color: Color)? {
        if let f = window?.limitForecast(now: now) {
            if let hit = f.hitAt { return ("At this pace, out by \(clock(hit))", .caution) }
            return ("On pace for \(Int(f.projected.rounded()))%", .secondary)
        }
        return nil
    }
}

/// When Claude Code hasn't reported limits: the window approximated from the logs.
struct WindowHero: View {
    let window: WindowStats?
    let now: Date

    var body: some View {
        Card(glow: .claude) {
            HStack {
                Text("5-hour window").font(Typo.heading).foregroundStyle(.secondary)
                Spacer()
                Badge(text: "Estimated")
            }
            if let w = window {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        AnimatedNumber(value: w.bucket.cost, format: fmtCost).font(Typo.hero)
                        Text("est. cost in this window").font(Typo.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Animated(target: now.timeIntervalSince(w.start) / WindowStats.length) { v in
                        RingGauge(value: v, tint: .primary.opacity(0.55)) {
                            VStack(spacing: 0) {
                                Text(fmtDuration(w.end.timeIntervalSince(now)))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                Text("left").font(Typo.micro).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                HStack {
                    Text("\(fmtTokens(w.bucket.tokens)) tokens · \(w.bucket.messages) messages")
                    Spacer()
                    if let rate = w.costPerHour(now: now) { Text("\(fmtCost(rate))/hr") }
                }
                .font(Typo.mono)
                .foregroundStyle(.secondary)
            } else {
                Text("Idle").font(Typo.display)
                Text("Your next message starts a new window. Plan limits appear once Claude Code reports them.")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Sessions active in the last 15 minutes: working or idle, and how full their context is.
struct LiveCard: View {
    let sessions: [LiveSession]
    let now: Date
    var accountNames: [String: String] = [:]

    var body: some View {
        let shown = Array(sessions.prefix(4))
        let full = shown.first { ($0.contextPercent ?? 0) >= 80 }
        Card {
            HStack {
                Text("Live sessions").font(Typo.heading).foregroundStyle(.secondary)
                Spacer()
                Text("\(sessions.count)").font(Typo.mono).foregroundStyle(.tertiary)
            }
            VStack(spacing: Space.s) {
                ForEach(shown) { row($0) }
            }
            if let full {
                Label("\(full.project) is nearly out of context. /compact frees space.", systemImage: "exclamationmark.triangle")
                    .font(Typo.caption)
                    .foregroundStyle(Color.caution)
            }
        }
    }

    private func row(_ s: LiveSession) -> some View {
        let working = Activity(last: s.lastActivity, now: now) == .working
        let percent = s.contextPercent ?? 0
        let status = working ? "Working" : "Idle \(fmtDuration(now.timeIntervalSince(s.lastActivity)))"
        return HStack(spacing: Space.xs) {
            StatusDot(color: working ? .live : .secondary, active: working)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.project.isEmpty ? "Session" : s.project).font(Typo.body.weight(.medium)).lineLimit(1)
                Text(([status, s.model] + [accountNames[s.account]].compactMap { $0 }).joined(separator: " · "))
                    .font(Typo.mono)
                    .foregroundStyle(working ? Color.live : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.xs)
            VStack(alignment: .trailing, spacing: 3) {
                Text(s.contextPercent.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(Typo.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(percent >= 80 ? levelColor(percent) : Color.primary)
                // Neutral until nearly full: coral is reserved for the plan allowance
                Animated(target: percent / 100) {
                    DotTrack(value: $0, tint: percent >= 80 ? levelColor(percent) : .primary.opacity(0.6), dots: 14, size: 3)
                }
                    .frame(width: 58)
            }
            .help(detail(s))
        }
    }

    private func detail(_ s: LiveSession) -> String {
        guard let used = s.contextTokens, let size = s.contextSize else { return "Context window used" }
        return "Context: \(fmtTokens(used)) of \(fmtTokens(size)) tokens"
    }
}

struct TodayCard: View {
    let s: Snapshot
    let budget: Double
    let metric: Metric
    let now: Date

    var body: some View {
        let today = s.today
        let hours = hourly
        Card {
            HStack {
                Text("Today").font(Typo.heading).foregroundStyle(.secondary)
                Spacer()
                if let change { Text(change).font(Typo.mono).foregroundStyle(.tertiary) }
            }
            HStack(spacing: Space.xs) {
                MetricTile(label: "Est. cost", value: today.cost, format: fmtCost)
                MetricTile(label: "Tokens", value: Double(today.tokens)) { fmtTokens(Int($0)) }
                MetricTile(label: "Messages", value: Double(today.messages)) { "\(Int($0.rounded()))" }
                MetricTile(label: "Sessions", value: Double(s.todaySessions)) { "\(Int($0.rounded()))" }
            }
            VStack(spacing: Space.xxs) {
                Animated(target: 1, animation: Motion.draw) { p in
                    BarStrip(values: hours, progress: p, tint: .claude,
                             highlighted: Calendar.current.component(.hour, from: now))
                }
                .frame(height: 28)
                HStack {
                    ForEach(["00", "06", "12", "18", "24"], id: \.self) { h in
                        Text(h)
                        if h != "24" { Spacer() }
                    }
                }
                .font(Typo.mono)
                .foregroundStyle(.tertiary)
            }
            .help("\(metric.title) by hour")
            if budget > 0 {
                let used = today.cost / budget
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Animated(target: used) { DotTrack(value: $0, tint: used >= 1 ? .critical : used >= 0.8 ? .caution : .claude) }
                    HStack {
                        Text("Daily budget")
                        Spacer()
                        Text("\(fmtCost(today.cost)) of \(fmtCost(budget))").monospacedDigit()
                    }
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The chosen metric for each hour of today.
    private var hourly: [Double] {
        var values = Array(repeating: 0.0, count: 24)
        for p in s[.today].series {
            values[Calendar.current.component(.hour, from: p.date)] += metric.value(p.bucket)
        }
        return values
    }

    private var change: String? {
        let before = metric.value(s.previousWeek)
        guard before > 0 else { return nil }
        let delta = (metric.value(s[.week].total) - before) / before
        return "7d \(delta >= 0 ? "↑" : "↓")\(fmtPercent(abs(delta)))"
    }
}

// MARK: - Usage

struct UsageTab: View {
    let scopeID: String
    @Binding var period: Period
    @Binding var metric: Metric
    @Binding var breakdown: Breakdown
    @EnvironmentObject var store: UsageStore
    @AppStorage("showLimitHistory") private var showLimits = false
    @State private var hovered: Int?

    /// Cost and Tokens chart the logs; Limits charts saved plan limit readings.
    private var mode: Binding<String> {
        Binding(get: { showLimits ? "limits" : metric.rawValue },
                set: { value in
                    showLimits = value == "limits"
                    if let m = Metric(rawValue: value) { metric = m }
                })
    }

    var body: some View {
        let s = store.snap(scopeID)
        let stats = s[period]
        // Limits belong to one account: with all accounts in view, show the one in use
        let limitAccount = scopeID == UsageStore.all ? store.currentAccount : (store.account(scopeID) ?? .main)
        let limits = store.snap(limitAccount.id)
        VStack(spacing: Space.s) {
            HStack {
                Segmented(items: Period.allCases.map { .init(value: $0, title: $0.short) }, selection: $period, small: true)
                Spacer()
                Segmented(items: Metric.allCases.map { .init(value: $0.rawValue, title: $0.title) }
                                 + [.init(value: "limits", title: "Limits")],
                          selection: mode, small: true)
            }
            .entrance(0)

            if showLimits {
                LimitHistoryCard(samples: limits.limitSamples, period: period, start: stats.start, now: Date(),
                                 weekly: limits.live.sevenDay,
                                 account: store.multiAccount ? limitAccount.name : nil, hovered: $hovered)
                    .id("limits-\(period)-\(limitAccount.id)")
                    .entrance(1)
            } else {
                AnalyticsCard(stats: stats, period: period, metric: metric, previous: period == .week ? s.previousWeek : nil,
                              hovered: $hovered)
                    .id("\(period)-\(metric)-\(scopeID)")   // redraw the chart on change
                    .entrance(1)
            }

            Card {
                Segmented(items: Breakdown.allCases.map { .init(value: $0, title: $0.title) },
                          selection: $breakdown, stretch: true, small: true)
                switch breakdown {
                case .models:   ShareTable(shares: stats.models, metric: metric)
                case .projects: ShareTable(shares: stats.projects, metric: metric)
                case .sessions: SessionTable(sessions: s.sessions)
                }
            }
            .entrance(2)

            if !s.unpriced.isEmpty {
                Text("No price known for \(s.unpriced.joined(separator: ", ")); counted as $0.")
                    .font(Typo.caption)
                    .foregroundStyle(Color.caution)
            }
        }
        .onChange(of: period) { hovered = nil }
    }
}

extension Period {
    var short: String {
        switch self {
        case .today: return "Today"
        case .week:  return "7D"
        case .month: return "30D"
        }
    }
}

struct AnalyticsCard: View {
    let stats: PeriodStats
    let period: Period
    let metric: Metric
    let previous: Bucket?
    @Binding var hovered: Int?

    var body: some View {
        let slots = self.slots
        let values = slots.map { metric.value($0.bucket) }
        let focus = hovered.flatMap { slots.indices.contains($0) ? slots[$0] : nil }
        let bucket = focus?.bucket ?? stats.total
        Card(glow: .cobalt, glowAt: .topTrailing) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(focus.map { label($0.date) } ?? "Total · \(period.title.lowercased())")
                        .font(Typo.caption)
                        .foregroundStyle(.secondary)
                    AnimatedNumber(value: metric.value(bucket), instant: focus != nil, format: metric.format).font(Typo.display)
                }
                Spacer()
                if focus == nil, let change { Badge(text: change, tint: .cobalt) }
            }

            if values.contains(where: { $0 > 0 }) {
                GeometryReader { g in
                    Animated(target: 1, animation: Motion.draw) { p in
                        LineChart(values: values, progress: p, tint: .cobalt, highlighted: hovered)
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            let i = Int((point.x / max(1, g.size.width) * CGFloat(slots.count - 1)).rounded())
                            hovered = min(max(0, i), slots.count - 1)
                        case .ended:
                            hovered = nil
                        }
                    }
                }
                .frame(height: 92)
                HStack {
                    Text(axisLabel(slots.first?.date))
                    Spacer()
                    Text(axisLabel(slots.last?.date))
                }
                .font(Typo.mono)
                .foregroundStyle(.tertiary)
            } else {
                Text("No usage in this period")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 92)
            }

            HStack(spacing: Space.xs) {
                MetricTile(label: metric == .cost ? "Tokens" : "Est. cost",
                           value: metric == .cost ? Double(bucket.tokens) : bucket.cost, instant: focus != nil,
                           format: metric == .cost ? { fmtTokens(Int($0)) } : fmtCost)
                MetricTile(label: "Messages", value: Double(bucket.messages), instant: focus != nil) { "\(Int($0.rounded()))" }
                MetricTile(label: "Cache reuse", value: bucket.cacheReuse, instant: focus != nil) { fmtPercent($0) }
                    .help("Share of prompt tokens read from cache, billed at about a tenth of the normal price")
            }
        }
    }

    /// Every hour or day in the period, including empty ones.
    private var slots: [Point] {
        let cal = Calendar.current
        let byDate = Dictionary(stats.series.map { ($0.date, $0.bucket) }, uniquingKeysWith: { a, _ in a })
        var out: [Point] = []
        var d = stats.chartStart
        let end = period == .today ? min(stats.end, Date()) : stats.end
        while d < end {
            out.append(Point(date: d, bucket: byDate[d] ?? Bucket()))
            d = cal.date(byAdding: period.unit, value: 1, to: d)!
        }
        return out
    }

    private func label(_ d: Date) -> String {
        period == .today ? d.formatted(.dateTime.hour()) : d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func axisLabel(_ d: Date?) -> String {
        guard let d else { return "" }
        return period == .today ? d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))) + ":00"
                                : d.formatted(.dateTime.month(.abbreviated).day())
    }

    private var change: String? {
        guard let previous else { return nil }
        let before = metric.value(previous)
        guard before > 0 else { return nil }
        let delta = (metric.value(stats.total) - before) / before
        return "\(delta >= 0 ? "↑" : "↓") \(fmtPercent(abs(delta))) vs prior 7d"
    }
}

/// Weekly limits: all models, then any per-model limits (e.g. Sonnet only).
struct WeeklyRows: View {
    let week: Limit?
    let models: [ModelLimit]

    var body: some View {
        let rows = (week.map { [("All models", $0)] } ?? []) + models.map { ($0.name.capitalizedFirst, $0.limit) }
        VStack(alignment: .leading, spacing: Space.xs) {
            Divider().opacity(0.5)
            ForEach(rows.indices, id: \.self) { i in
                let (name, limit) = rows[i]
                HStack(spacing: Space.xs) {
                    Text(name).font(Typo.caption).foregroundStyle(.secondary).lineLimit(1)
                        .frame(width: 92, alignment: .leading)
                    Animated(target: limit.usedPercent / 100) {
                        DotTrack(value: $0, tint: levelColor(limit.usedPercent), dots: 22, size: 3)
                    }
                    Text("\(Int(limit.usedPercent.rounded()))%")
                        .font(Typo.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(limit.usedPercent >= Thresholds.warn ? levelColor(limit.usedPercent) : Color.primary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
            if let reset = rows.first?.1.resetsAt {
                Text("Weekly resets \(reset.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    .font(Typo.mono)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Saved plan limit readings: the highest 5-hour usage per hour or day.
struct LimitHistoryCard: View {
    let samples: [LimitSample]
    let period: Period
    let start: Date
    let now: Date
    let weekly: Limit?
    let account: String?
    @Binding var hovered: Int?

    var body: some View {
        let slots = self.slots
        let inRange = samples.filter { $0.date >= start }
        let peaks = slots.map { slot in inRange.filter { $0.date >= slot && $0.date < next(slot) }.compactMap(\.f).max() ?? 0 }
        let windows = Set(inRange.compactMap { $0.fr.map { Int($0 / 600) } })
        let hits = Set(inRange.filter { ($0.f ?? 0) >= 100 }.compactMap { $0.fr.map { Int($0 / 600) } })
        let focus = hovered.flatMap { peaks.indices.contains($0) ? $0 : nil }
        let shown = focus.map { peaks[$0] } ?? (peaks.max() ?? 0)
        let usedPeaks = peaks.filter { $0 > 0 }

        Card(glow: .claude, glowAt: .topTrailing) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(focus.map { label(slots[$0]) } ?? "Peak 5-hour use · \(period.title.lowercased())")
                        .font(Typo.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        AnimatedNumber(value: shown, instant: focus != nil) { "\(Int($0.rounded()))" }.font(Typo.display)
                        Text("%").font(Typo.unit).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Space.xxs) {
                    if let account { Badge(text: account) }
                    if focus == nil, !hits.isEmpty { Badge(text: "Limit hit \(hits.count)×", tint: .critical) }
                }
            }

            if inRange.isEmpty {
                Text("Limit history builds up as you use Claude. ClaudeMeter saves a reading every few minutes while it runs.")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            } else {
                GeometryReader { g in
                    Animated(target: 1, animation: Motion.draw) { p in
                        BarStrip(values: peaks, progress: p, tint: .claude, highlighted: focus, scale: 100, color: levelColor)
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            hovered = min(max(0, Int(point.x / max(1, g.size.width) * CGFloat(slots.count))), slots.count - 1)
                        case .ended:
                            hovered = nil
                        }
                    }
                }
                .frame(height: 72)
                HStack {
                    Text(axisLabel(slots.first))
                    Spacer()
                    Text(axisLabel(slots.last))
                }
                .font(Typo.mono)
                .foregroundStyle(.tertiary)
            }

            HStack(spacing: Space.xs) {
                MetricTile(label: period == .today ? "Average" : "Avg daily peak",
                           value: usedPeaks.isEmpty ? 0 : usedPeaks.reduce(0, +) / Double(usedPeaks.count)) { "\(Int($0.rounded()))%" }
                MetricTile(label: "Windows", value: Double(windows.count)) { "\(Int($0.rounded()))" }
                    .help("5-hour windows with Claude use in this period")
                MetricTile(label: "Weekly now", value: weekly?.usedPercent ?? 0) { weekly == nil ? "—" : "\(Int($0.rounded()))%" }
            }
        }
    }

    private var slots: [Date] {
        var out: [Date] = []
        var d = start
        while d < now {
            out.append(d)
            d = next(d)
        }
        return out
    }

    private func next(_ d: Date) -> Date { Calendar.current.date(byAdding: period.unit, value: 1, to: d)! }

    private func label(_ d: Date) -> String {
        period == .today ? d.formatted(.dateTime.hour()) : d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func axisLabel(_ d: Date?) -> String {
        guard let d else { return "" }
        return period == .today ? d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))) + ":00"
                                : d.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct ShareTable: View {
    let shares: [Share]
    let metric: Metric

    var body: some View {
        if shares.isEmpty {
            EmptyRow(text: "Nothing in this period")
        } else {
            let total = max(shares.reduce(0) { $0 + metric.value($1.bucket) }, .leastNonzeroMagnitude)
            VStack(spacing: Space.s) {
                ForEach(shares.prefix(5)) { share in
                    let fraction = metric.value(share.bucket) / total
                    VStack(spacing: Space.xxs) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(share.name).font(Typo.body).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(fmtPercent(fraction)).font(Typo.mono).foregroundStyle(.tertiary)
                            Text(metric.format(metric.value(share.bucket)))
                                .font(Typo.body.weight(.medium).monospacedDigit())
                                .frame(minWidth: 56, alignment: .trailing)
                        }
                        Animated(target: fraction) { v in
                            GeometryReader { g in
                                Capsule().fill(Color.track)
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Color.cobalt).frame(width: max(2, g.size.width * v))
                                    }
                            }
                        }
                        .frame(height: 2)
                    }
                }
            }
        }
    }
}

struct SessionTable: View {
    let sessions: [SessionStats]

    var body: some View {
        if sessions.isEmpty {
            EmptyRow(text: "No sessions yet")
        } else {
            VStack(spacing: Space.s) {
                ForEach(sessions.prefix(5)) { s in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.project).font(Typo.body).lineLimit(1)
                            Text("\(s.model) · \(s.end.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))) · \(fmtDuration(s.end.timeIntervalSince(s.start)))")
                                .font(Typo.mono)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(fmtCost(s.bucket.cost)).font(Typo.body.weight(.medium).monospacedDigit())
                    }
                }
            }
        }
    }
}

// MARK: - Accounts

struct AccountsTab: View {
    let openSettings: () -> Void
    @EnvironmentObject var store: UsageStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            VStack(spacing: Space.s) {
                ForEach(Array(store.accounts.enumerated()), id: \.element.id) { i, account in
                    AccountCard(account: account,
                                snap: store.snap(account.id),
                                profile: store.profile(account.id),
                                selected: store.activeID == account.id,
                                selectable: store.multiAccount,
                                now: ctx.date) {
                        withAnimation(Motion.spring) { store.setActive(account.id) }
                    }
                    .entrance(i)
                }
                HStack(spacing: Space.xs) {
                    Button(action: openSettings) {
                        Label("Add account", systemImage: "plus")
                            .font(Typo.caption.weight(.medium))
                            .padding(.horizontal, Space.s)
                            .frame(height: 26)
                            .background(Capsule().fill(Color.surface))
                            .overlay(Capsule().strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 0.5, dash: [3, 2])))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    Spacer()
                }
                .entrance(store.accounts.count)
                if store.multiAccount {
                    Text(Accounts.shellCommandsInstalled
                         ? "New `claude` sessions start with the selected account. Running sessions keep theirs."
                         : "Selecting changes which account “Open Claude Code” uses. Install terminal commands in Settings so `claude` follows it too.")
                        .font(Typo.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct AccountCard: View {
    let account: Account
    let snap: Snapshot
    let profile: AccountProfile
    let selected: Bool
    let selectable: Bool
    let now: Date
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        let five = snap.live.fiveHour
        let working = snap.live.sessions.contains { Activity(last: $0.lastActivity, now: now) == .working }
        Card(glow: selected && selectable ? .claude : nil, outline: selected && selectable ? Color.claude.opacity(0.55) : nil) {
            HStack(alignment: .center, spacing: Space.s) {
                if selectable {
                    ZStack {
                        Circle().strokeBorder(selected ? Color.claude : Color.track, lineWidth: 1.5)
                        if selected {
                            Circle().fill(Color.claude).padding(4)
                        }
                    }
                    .frame(width: 16, height: 16)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(account.name).font(Typo.title).lineLimit(1)
                        if let plan = profile.plan { Badge(text: plan) }
                        if working { StatusDot(color: .live, active: true).help("Working now") }
                    }
                    Text(profile.email ?? "Not signed in")
                        .font(Typo.caption)
                        .foregroundStyle(profile.signedIn ? Color.secondary : Color.caution)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if profile.signedIn {
                    CircleButton(icon: "terminal", help: "Open Claude Code with \(account.name)") { Accounts.launch(account) }
                } else {
                    PrimaryPill(title: "Sign in", icon: "person.badge.key") { Accounts.launch(account) }
                        .help("Opens Claude Code for this account. Run /login there.")
                }
            }
            if let five {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    HStack(spacing: Space.xs) {
                        Animated(target: five.usedPercent / 100) { DotTrack(value: $0, tint: levelColor(five.usedPercent), dots: 26) }
                        Text(five.usedPercent >= 100 ? "Full" : "\(Int(five.usedPercent.rounded()))%")
                            .font(Typo.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(five.usedPercent >= Thresholds.warn ? levelColor(five.usedPercent) : Color.primary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    Text(detail(five))
                        .font(Typo.mono)
                        .foregroundStyle(.secondary)
                }
            } else if profile.signedIn {
                Text(snap.live.lastReport == nil ? "Limits appear after its first session." : "No active 5-hour window")
                    .font(Typo.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .scaleEffect(hovering && selectable && !selected ? 1.006 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Radius.card))
        .onTapGesture { if selectable { select() } }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .help(selectable ? (selected ? "\(account.name) is used for new sessions" : "Use \(account.name) for new sessions") : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func detail(_ five: Limit) -> String {
        var parts = [five.usedPercent >= 100 ? "Back in \(fmtDuration(five.resetsAt.timeIntervalSince(now)))"
                                             : "Resets \(clock(five.resetsAt))"]
        if let week = snap.live.sevenDay { parts.append("weekly \(Int(week.usedPercent.rounded()))%") }
        for m in snap.live.modelWeeks {
            parts.append("\(m.name.replacingOccurrences(of: " only", with: "").lowercased()) \(Int(m.limit.usedPercent.rounded()))%")
        }
        if let updated = snap.live.limitsUpdated, now.timeIntervalSince(updated) > 5 * 60 {
            parts.append("as of \(clock(updated))")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - States

struct LoadingState: View {
    var body: some View {
        VStack(spacing: Space.s) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.surface)
                    .frame(height: i == 0 ? 132 : 72)
            }
        }
        .accessibilityLabel("Loading usage")
    }
}

struct EmptyCard: View {
    let text: String
    let detail: String

    var body: some View {
        Card {
            VStack(spacing: Space.xxs) {
                Image(systemName: "tray").font(.system(size: 18, weight: .light)).foregroundStyle(.tertiary)
                Text(text).font(Typo.body.weight(.medium))
                Text(detail).font(Typo.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s)
        }
    }
}

struct EmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typo.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 40)
    }
}
