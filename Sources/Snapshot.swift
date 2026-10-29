import SwiftUI

/// `ClaudeMeter --snapshot <folder> [--demo]` renders each panel tab in light and
/// dark mode, plus every menu bar icon state, to PNG files, then exits. Uses your
/// real data, or made-up data with `--demo` (for docs). Used to review the design.
enum PanelSnapshot {
    @MainActor
    static func write(to dir: URL, demo: Bool = false) {
        let app = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = demo ? Demo.store() : UsageStore(preview: true)

        for (scheme, name) in [(ColorScheme.light, "light"), (.dark, "dark")] {
            let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
            app.appearance = appearance
            UserDefaults.standard.set(false, forKey: "showLimitHistory")
            for tab in Tab.allCases + [.usage] {
                // The second Usage render shows the Limits view
                let limitsView = tab == .usage && FileManager.default.fileExists(atPath: dir.appendingPathComponent("usage-\(name).png").path)
                UserDefaults.standard.set(limitsView, forKey: "showLimitHistory")
                let file = limitsView ? "limits-\(name).png" : "\(tab.rawValue)-\(name).png"
                let view = PanelView(previewTab: tab)
                    .environmentObject(store)
                    .environment(\.colorScheme, scheme)
                    .environment(\.isSnapshot, true)
                    .background(scheme == .dark ? Color(white: 0.13) : Color(white: 0.955))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                appearance.performAsCurrentDrawingAppearance {
                    save(renderer, to: dir.appendingPathComponent(file))
                }
            }
        }
        let renderer = ImageRenderer(content: menuBarStates)
        renderer.scale = 3
        save(renderer, to: dir.appendingPathComponent("menubar.png"))

        // Settings uses standard controls, which ImageRenderer can't draw, so
        // capture it from a real (offscreen) window instead
        for (scheme, name) in [(ColorScheme.light, "light"), (.dark, "dark")] {
            let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
            app.appearance = appearance
            for tab in SettingsTab.allCases {
                let view = SettingsView(previewTab: tab)
                    .environmentObject(store)
                    .environment(\.isSnapshot, true)
                    .tint(.claude)
                    .background(Color(nsColor: .windowBackgroundColor))
                capture(view, appearance: appearance, to: dir.appendingPathComponent("settings-\(tab.rawValue)-\(name).png"))
            }
        }
    }

    @MainActor
    private static func capture<V: View>(_ view: V, appearance: NSAppearance, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    @MainActor
    private static func save<V: View>(_ renderer: ImageRenderer<V>, to url: URL) {
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    /// Every menu bar icon state, on light and dark menu bars, beside system icons for scale.
    private static var menuBarStates: some View {
        let states: [(String, MenuBarContent)] = [
            ("Idle, 48%", .init(fraction: 0.48, initial: nil, working: false, critical: false, text: "48%")),
            ("Working", .init(fraction: 0.48, initial: nil, working: true, critical: false, text: "48%")),
            ("Two accounts", .init(fraction: 0.83, initial: "W", working: true, critical: false, text: "83%")),
            ("Limit reached", .init(fraction: 1, initial: nil, working: false, critical: true, text: "100%")),
            ("No limit data", .init(fraction: 0.3, initial: nil, working: false, critical: false, text: "$4.24")),
            ("Icon only", .init(fraction: 0.48, initial: nil, working: true, critical: false, text: nil)),
            ("Weekly ring", .init(fraction: 0.48, weekly: 0.31, initial: nil, working: false, critical: false, text: "48%")),
            ("Weekly, working", .init(fraction: 0.62, weekly: 0.74, initial: nil, working: true, critical: false, text: "W 62%")),
        ]
        return HStack(spacing: 0) {
            ForEach([true, false], id: \.self) { dark in
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(states.indices, id: \.self) { i in
                        HStack(spacing: 14) {
                            states[i].1
                            Image(systemName: "wifi")
                            Image(systemName: "battery.75percent")
                            Text("Thu 9:30 PM").font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(states[i].0).font(.system(size: 10)).opacity(0.6)
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(dark ? .white : .black)
                        .padding(.horizontal, 10)
                        .frame(width: 380, height: 24)
                        .background(dark ? Color(white: 0.16) : Color(white: 0.93))
                    }
                }
                .padding(10)
                .background(dark ? Color(white: 0.08) : Color.white)
            }
        }
    }
}
