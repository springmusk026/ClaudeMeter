import Foundation
import WidgetKit

/// Keeps the widget's data file current and tells WidgetKit when it changes.
enum WidgetFeed {
    private static var last: WidgetData?
    private static var lastReload = Date.distantPast
    private static var pendingReload: DispatchWorkItem?

    /// The widget's view of the account being worked in.
    static func make(_ store: UsageStore, now: Date = Date()) -> WidgetData {
        let account = store.currentAccount
        let s = store.snap(account.id)
        let all = store.snap(UsageStore.all)
        let gauge = { (l: Limit) in WidgetData.Gauge(percent: l.usedPercent, resets: l.resetsAt) }
        let working: Bool = { if case .working = store.state(now: now) { return true }; return false }()
        return WidgetData(account: store.multiAccount ? account.name : nil,
                          plan: store.profile(account.id).plan,
                          fiveHour: s.live.fiveHour.map(gauge),
                          weekly: s.live.sevenDay.map(gauge),
                          models: s.live.modelWeeks.map { .init(name: $0.name, gauge: gauge($0.limit)) },
                          todayCost: (all.today.cost * 100).rounded() / 100,
                          todayTokens: all.today.tokens,
                          limitAt: s.window?.limitForecast(now: now)?.hitAt,
                          working: working,
                          warn: Thresholds.warn,
                          critical: Thresholds.critical,
                          updated: now)
    }

    /// Saves the data when something other than the timestamp changed, and reloads
    /// the widget at most every 30 seconds so busy sessions don't exhaust WidgetKit's budget.
    static func update(_ store: UsageStore) {
        let data = make(store)
        var comparable = data
        comparable.updated = last?.updated ?? data.updated
        guard comparable != last else { return }
        last = data
        data.save()

        pendingReload?.cancel()
        let wait = max(0, 30 - Date().timeIntervalSince(lastReload))
        let reload = DispatchWorkItem {
            lastReload = Date()
            WidgetCenter.shared.reloadAllTimelines()
        }
        pendingReload = reload
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: reload)
    }
}
