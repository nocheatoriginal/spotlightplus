import AppKit
import SwiftUI
import ApplicationServices

struct Favorite: Codable, Identifiable, Equatable {
    var id: String { path }
    let path: String
    var name: String { FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "") }
}

enum ShortcutPolicy {
    static let codes: [Int64] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    static func index(code: Int64, flags: CGEventFlags, count: Int, visible: Bool) -> Int? {
        let modifiers = flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
        guard visible, modifiers == .maskCommand, let index = codes.firstIndex(of: code), index < count else { return nil }
        return index
    }
}

final class Favorites: ObservableObject {
    @Published var items: [Favorite] = [] { didSet { save() } }
    @Published var error: String?
    init() {
        if let data = UserDefaults.standard.data(forKey: "favorites"),
           let stored = try? JSONDecoder().decode([Favorite].self, from: data) {
            items = Array(stored.prefix(9))
        }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: "favorites") }
    }
    func add() {
        let picker = NSOpenPanel()
        picker.title = "Apps zu deinen Favoriten hinzufügen"
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.allowedContentTypes = [.applicationBundle]
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        guard picker.runModal() == .OK else { return }
        for url in picker.urls where !items.contains(where: { $0.path == url.path }) {
            guard items.count < 9 else { error = "Es sind maximal neun Favoriten möglich."; break }
            items.append(Favorite(path: url.path))
        }
    }
    func move(_ index: Int, by delta: Int) {
        let destination = index + delta
        guard items.indices.contains(index), items.indices.contains(destination) else { return }
        items.swapAt(index, destination)
    }
}

struct SpotlightWindow: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let rect: CGRect // Accessibility uses a top-left origin.
}

struct DismissalGate {
    private var id: CGWindowID?
    private var until: TimeInterval = 0
    mutating func dismiss(_ id: CGWindowID?, now: TimeInterval) {
        self.id = id
        until = now + 0.35
    }
    mutating func filter(_ window: SpotlightWindow?, now: TimeInterval) -> SpotlightWindow? {
        guard let window else { id = nil; return nil }
        if now >= until { id = nil }
        return window.id == id ? nil : window
    }
}

final class SpotlightBridge: ObservableObject {
    @Published var permitted = AXIsProcessTrusted()
    @Published var listening = false
    @Published var status = "Freigabe wird geprüft …"
    @Published var placementNote = ""
    var changed: ((SpotlightWindow?) -> Void)?
    var launch: ((Int) -> Void)?
    var favoriteCount: () -> Int = { 0 }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var swallowed = Set<Int64>()
    static let syntheticTag: Int64 = 0x53504C5553

    private let scanner = DispatchQueue(label: "de.nils.spotlightplus.windows", qos: .userInitiated)
    private var scanning = false
    private var generation = 0
    private var current: SpotlightWindow?
    private var dismissal = DismissalGate()
    private var spotlightPID: pid_t?
    private var lastPermissionCheck = Date.distantPast
    private var lastScan = Date.distantPast
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var burstToken = 0
    private var workspaceTokens: [NSObjectProtocol] = []

    // Observe lifecycle changes, but retain a polling fallback for unsupported AX notifications.
    private func observeSpotlight(_ pid: pid_t?) {
        guard observedPID != pid else { return }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        observedPID = nil
        guard let pid else { return }
        var newObserver: AXObserver?
        guard AXObserverCreate(pid, { _, _, notification, context in
            guard let context else { return }
            let bridge = Unmanaged<SpotlightBridge>.fromOpaque(context).takeUnretainedValue()
            if notification as String == kAXApplicationHiddenNotification as String {
                bridge.dismiss()
            }
            bridge.requestBurst()
        }, &newObserver) == .success, let newObserver else { return }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.02)
        for name in [kAXApplicationShownNotification, kAXApplicationHiddenNotification,
                     kAXApplicationActivatedNotification, kAXFocusedWindowChangedNotification,
                     kAXWindowCreatedNotification] {
            _ = AXObserverAddNotification(newObserver, application, name as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        observer = newObserver
        observedPID = pid
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
    }
    private func requestBurst() {
        burstToken += 1
        let token = burstToken
        // Multiple observations are needed because the triggering event precedes window creation.
        for delay in [0.0, 0.016, 0.032, 0.064, 0.10, 0.16, 0.24] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, token == self.burstToken else { return }
                self.refresh(urgent: true)
            }
        }
    }

    func start() {
        refresh()
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.bundleIdentifier == "com.apple.Spotlight" {
                    self.lastPermissionCheck = .distantPast
                }
                self.requestBurst()
            })
        }
    }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        lastPermissionCheck = .distantPast
    }
    func refresh(urgent: Bool = false) {
        if Date().timeIntervalSince(lastPermissionCheck) > 1 {
            lastPermissionCheck = Date()
            let trusted = AXIsProcessTrusted()
            if permitted != trusted { permitted = trusted }
            spotlightPID = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.Spotlight" }?.processIdentifier
            if permitted && tap == nil { installTap() }
            observeSpotlight(permitted ? spotlightPID : nil)
            if !permitted, let tap {
                CFMachPortInvalidate(tap)
                if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
                self.tap = nil
                self.source = nil
                listening = false
            }
        }
        guard permitted && listening, let pid = spotlightPID else {
            publish(nil)
            if !permitted {
                setStatus("macOS hat dieser App-Version noch keine Bedienungshilfen-Freigabe erteilt.")
            } else if !listening {
                setStatus("Freigabe erkannt, aber Tastaturzugriff blockiert. Bitte die App neu starten.")
            } else {
                setStatus("Spotlight-Prozess nicht gefunden. Öffne Spotlight mit ⌘Leertaste.")
            }
            return
        }
        guard !scanning else { return } // Never accumulate work behind a slow system query.
        if !urgent && current == nil && Date().timeIntervalSince(lastScan) < 0.18 { return }
        lastScan = Date()
        scanning = true
        let revision = generation
        let preferredID = current?.id
        scanner.async { [weak self] in
            let result = Self.scan(pid: pid, preferredID: preferredID)
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                guard revision == self.generation, self.permitted && self.listening else { return }
                self.publish(result)
                self.setStatus(result == nil ? "Freigabe aktiv. Warte auf ein sichtbares Spotlight-Fenster." : "Spotlight erkannt · Favoritenleiste aktiv")
            }
        }
    }
    private func setStatus(_ text: String) {
        if status != text { status = text }
    }
    private func publish(_ window: SpotlightWindow?) {
        let next = dismissal.filter(window, now: ProcessInfo.processInfo.systemUptime)
        let wasVisible = current != nil
        current = next
        if next != nil || wasVisible { changed?(next) }
    }
    // Called before launching: an old scan cannot bring the overlay back during dismissal.
    func dismiss() {
        dismissal.dismiss(current?.id, now: ProcessInfo.processInfo.systemUptime)
        generation += 1
        current = nil
        changed?(nil)
    }
    func visibleWindow() -> SpotlightWindow? {
        guard permitted && listening, let pid = spotlightPID else { return nil }
        let window = Self.scan(pid: pid, preferredID: current?.id)
        return dismissal.filter(window, now: ProcessInfo.processInfo.systemUptime)
    }
    private static func scan(pid: pid_t, preferredID: CGWindowID?) -> SpotlightWindow? {
        // WindowServer geometry is sufficient; no blocking cross-process AX calls.
        let options: CGWindowListOption = preferredID == nil ? [.optionOnScreenOnly, .excludeDesktopElements] : .optionIncludingWindow
        guard let entries = CGWindowListCopyWindowInfo(options, preferredID ?? kCGNullWindowID) as? [[String: Any]] else { return nil }
        let candidates = entries.compactMap { info -> SpotlightWindow? in
            guard (info[kCGWindowIsOnscreen as String] as? Bool) == true,
                  (info[kCGWindowOwnerPID as String] as? Int32) == pid,
                  let id = info[kCGWindowNumber as String] as? UInt32,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 250, rect.height > 35 else { return nil }
            return SpotlightWindow(id: id, pid: pid, rect: rect)
        }
        return candidates.first { $0.id == preferredID } ?? candidates.first
    }
    private func installTap() {
        let mask = [CGEventType.keyDown, .keyUp, .leftMouseDown, .rightMouseDown].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                               eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let bridge = Unmanaged<SpotlightBridge>.fromOpaque(context).takeUnretainedValue()
            return bridge.handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { listening = false; return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        listening = true
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            swallowed.removeAll()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticTag { return Unmanaged.passUnretained(event) }
        if type == .leftMouseDown || type == .rightMouseDown {
            if current != nil { requestBurst() }
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown, code == 49, event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]) == .maskCommand {
            if current != nil { dismiss() }
            requestBurst()
        } else if type == .keyDown, current != nil, code == 53 || code == 36 || code == 76 {
            // Escape can clear the query without closing Spotlight; verify instead of guessing.
            requestBurst()
        }
        if type == .keyUp, swallowed.remove(code) != nil { return nil }
        if type == .keyDown, swallowed.contains(code) { return nil }
        guard type == .keyDown,
              let index = ShortcutPolicy.index(code: code, flags: event.flags, count: favoriteCount(), visible: true),
              visibleWindow() != nil else { return Unmanaged.passUnretained(event) }
        swallowed.insert(code)
        DispatchQueue.main.async { [weak self] in self?.launch?(index) }
        return nil
    }
    func send(_ code: CGKeyCode, flags: CGEventFlags, to pid: pid_t) {
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
            event.postToPid(pid)
        }
    }
    func category(_ index: Int) {
        guard let window = visibleWindow() else { return }
        send(CGKeyCode(ShortcutPolicy.codes[index]), flags: .maskCommand, to: window.pid)
    }
}

enum PanelPlacement {
    static let height: CGFloat = 148
    static let minimumWidth: CGFloat = 480
    static let appWidth: CGFloat = 80
    static let appSpacing: CGFloat = 8
    static func frame(available: CGRect, favoriteCount: Int) -> CGRect {
        let count = CGFloat(min(9, max(0, favoriteCount)))
        let desired = max(minimumWidth, 40 + count * appWidth + max(0, count - 1) * appSpacing)
        let width = min(desired, available.width - 32)
        return CGRect(x: available.midX - width / 2,
                      y: available.maxY - height - 10, width: width, height: height)
    }
}

struct FavoritesBar: View {
    @ObservedObject var favorites: Favorites
    let launch: (Int) -> Void
    let category: (Int) -> Void
    let settings: () -> Void
    private let categories = [("Apps", "square.grid.2x2"), ("Dateien", "doc"), ("Aktionen", "bolt"), ("Zwischenablage", "clipboard")]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if favorites.items.isEmpty {
                Button(action: settings) { Label("Deine Lieblingsapps hinzufügen", systemImage: "plus.circle").frame(maxWidth: .infinity).padding(.vertical, 12) }.buttonStyle(.plain)
            } else {
                GeometryReader { geometry in
                    let count = CGFloat(favorites.items.count)
                    let tileWidth = min(PanelPlacement.appWidth, (geometry.size.width - (count - 1) * PanelPlacement.appSpacing) / count)
                    HStack(spacing: PanelPlacement.appSpacing) {
                        ForEach(Array(favorites.items.enumerated()), id: \.element.id) { index, item in
                            Button { launch(index) } label: {
                                VStack(spacing: 3) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.path)).resizable().frame(width: 36, height: 36)
                                    Text(item.name).font(.system(size: 10)).lineLimit(1)
                                    Text("⌘\(index + 1)").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                                }.frame(width: tileWidth).padding(.vertical, 4).contentShape(Rectangle())
                            }.buttonStyle(.plain).help("\(item.name) öffnen · ⌘\(index + 1)")
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.frame(height: 76)
            }
            Divider()
            HStack(spacing: 16) {
                ForEach(0..<categories.count, id: \.self) { index in
                    Button { category(index) } label: { Label(categories[index].0, systemImage: categories[index].1).font(.system(size: 11)) }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Button(action: settings) { Image(systemName: "slider.horizontal.3") }.buttonStyle(.plain).help("Favoriten bearbeiten")
            }.foregroundStyle(.secondary)
        }.padding(.horizontal, 20).padding(.vertical, 14).frame(maxWidth: .infinity, maxHeight: .infinity).ignoresSafeArea()
    }
}

struct SettingsView: View {
    @ObservedObject var favorites: Favorites
    @ObservedObject var bridge: SpotlightBridge
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: AppArtwork.icon ?? NSImage()).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Spotlight Plus").font(.title2.bold())
                }
            }
            GroupBox {
                HStack {
                    Image(systemName: bridge.listening ? "checkmark.circle.fill" : "hand.raised.fill").foregroundStyle(bridge.listening ? .green : .orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bridge.listening ? "Bereit für Spotlight" : "Bedienungshilfen erlauben").font(.headline)
                        Text(bridge.placementNote.isEmpty ? bridge.status : bridge.placementNote).font(.caption).foregroundStyle(.secondary)
                        if !bridge.permitted {
                            Text("Falls der Eintrag bereits aktiviert ist: beende die App, entferne den alten Eintrag und füge genau diese App erneut hinzu.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !bridge.permitted { Button("Freigeben") { bridge.requestPermission() } }
                }.padding(8)
            }
            HStack {
                Text("Deine Reihenfolge").font(.headline)
                Spacer()
                Text("\(favorites.items.count) / 9 Apps").foregroundStyle(.secondary)
                Button { favorites.add() } label: { Label("App hinzufügen", systemImage: "plus") }.disabled(favorites.items.count >= 9)
            }
            List {
                if favorites.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2").font(.largeTitle).foregroundStyle(.tertiary)
                        Text("Platz für deine Lieblingsapps").font(.headline)
                        Text("Füge Apps hinzu und bestimme ihre Reihenfolge.").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(40)
                }
                ForEach(Array(favorites.items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Text("⌘\(index + 1)").monospaced().foregroundStyle(.secondary).frame(width: 32)
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.path)).resizable().frame(width: 28, height: 28)
                        Text(item.name)
                        if !FileManager.default.fileExists(atPath: item.path) { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help("App wurde verschoben oder gelöscht. Bitte erneut hinzufügen.") }
                        Spacer()
                        Button { favorites.move(index, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0).help("Nach vorne")
                        Button { favorites.move(index, by: 1) } label: { Image(systemName: "chevron.down") }.disabled(index == favorites.items.count - 1).help("Nach hinten")
                        Button { favorites.items.remove(at: index) } label: { Image(systemName: "minus.circle") }.help("Entfernen")
                    }.padding(.vertical, 4)
                }
            }.listStyle(.inset).frame(minHeight: 220)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–") · \(Bundle.main.bundleURL.path)").font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled)
        }.padding(24).frame(width: 580, height: 520)
        .alert("Hinweis", isPresented: Binding(get: { favorites.error != nil }, set: { if !$0 { favorites.error = nil } })) { Button("OK") { favorites.error = nil } } message: { Text(favorites.error ?? "") }
    }
}

// Keep the requested dark tint explicit while allowing the desktop to show through.
final class SpotlightSurface: NSView {
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) { Self.paint(in: bounds) }

    static func paint(in bounds: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 24, yRadius: 24)
        NSColor(srgbRed: 29.0 / 255, green: 21.0 / 255, blue: 48.0 / 255, alpha: 0.84).setFill()
        shape.fill()
        NSColor(srgbRed: 0.40, green: 0.45, blue: 0.78, alpha: 0.35).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
    }
}

enum AppArtwork {
    static var icon: NSImage? {
        guard let filename = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
              let url = Bundle.main.resourceURL?.appendingPathComponent(filename) else { return nil }
        return NSImage(contentsOf: url)
    }
    static func menuIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let ring = NSBezierPath(ovalIn: CGRect(x: 2, y: 6, width: 10, height: 10))
            ring.lineWidth = 1.6
            ring.stroke()
            let marks = NSBezierPath()
            marks.move(to: CGPoint(x: 10.6, y: 7.4)); marks.line(to: CGPoint(x: 16, y: 2))
            marks.move(to: CGPoint(x: 4.5, y: 11)); marks.line(to: CGPoint(x: 9.5, y: 11))
            marks.move(to: CGPoint(x: 7, y: 8.5)); marks.line(to: CGPoint(x: 7, y: 13.5))
            marks.lineWidth = 1.5
            marks.lineCapStyle = .round
            marks.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Spotlight Plus"
        return image
    }
}

final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let favorites = Favorites()
    let bridge = SpotlightBridge()
    var statusItem: NSStatusItem!
    var panel: CompanionPanel!
    var settingsWindow: NSWindow!
    private var sessionScreen: NSScreen?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let icon = AppArtwork.icon { NSApp.applicationIconImage = icon }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = AppArtwork.menuIcon()
        let menu = NSMenu()
        menu.addItem(withTitle: "Favoriten bearbeiten …", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Spotlight Plus beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        panel = CompanionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        let content = NSHostingView(rootView: FavoritesBar(favorites: favorites, launch: { [weak self] in self?.launch($0) }, category: { [weak self] in self?.bridge.category($0) }, settings: { [weak self] in self?.showSettings() }))
        panel.appearance = NSAppearance(named: .darkAqua)
        let surface = SpotlightSurface()
        content.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            content.topAnchor.constraint(equalTo: surface.topAnchor),
            content.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
        panel.contentView = surface
        // Prepare layout while hidden so the first opening does not pay the initial layout cost.
        if let screen = NSScreen.main {
            panel.setFrame(PanelPlacement.frame(available: screen.visibleFrame, favoriteCount: favorites.items.count), display: false)
            panel.contentView?.layoutSubtreeIfNeeded()
        }
        bridge.favoriteCount = { [weak self] in self?.favorites.items.count ?? 0 }
        bridge.launch = { [weak self] in self?.launch($0) }
        bridge.changed = { [weak self] in self?.updatePanel($0) }
        bridge.start()
        if favorites.items.isEmpty || !bridge.permitted { showSettings() }
    }
    func updatePanel(_ window: SpotlightWindow?) {
        guard let window, let primary = NSScreen.screens.first else {
            if panel.isVisible { panel.orderOut(nil) }
            sessionScreen = nil
            if !bridge.placementNote.isEmpty { bridge.placementNote = "" }
            return
        }
        if sessionScreen == nil || !NSScreen.screens.contains(where: { $0 == sessionScreen }) {
            let spotlightTop = CGPoint(x: window.rect.midX, y: primary.frame.maxY - window.rect.minY - 1)
            sessionScreen = NSScreen.screens.first(where: { $0.frame.contains(spotlightTop) }) ?? primary
        }
        // Lock the screen for this opening. Spotlight's position and results never move the strip.
        guard let screen = sessionScreen else { return }
        let frame = PanelPlacement.frame(available: screen.visibleFrame, favoriteCount: favorites.items.count)
        if !bridge.placementNote.isEmpty { bridge.placementNote = "" }
        if abs(panel.frame.minX - frame.minX) > 1 || abs(panel.frame.minY - frame.minY) > 1 || panel.frame.size != frame.size {
            panel.setFrame(frame, display: false, animate: false)
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
    @objc func showSettings() {
        panel.orderOut(nil)
        if settingsWindow == nil {
            settingsWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 628, height: 568), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            settingsWindow.delegate = self
            settingsWindow.title = "Spotlight Plus"
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.contentView = NSHostingView(rootView: SettingsView(favorites: favorites, bridge: bridge))
            settingsWindow.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updatePanel(self.bridge.visibleWindow())
        }
    }
    func launch(_ index: Int) {
        guard favorites.items.indices.contains(index) else { return }
        let item = favorites.items[index]
        guard FileManager.default.fileExists(atPath: item.path) else {
            favorites.error = "\(item.name) wurde nicht gefunden. Füge die App bitte erneut hinzu."
            showSettings()
            return
        }
        let spotlight = bridge.visibleWindow()
        bridge.dismiss()
        panel.orderOut(nil)
        if let spotlight { bridge.send(53, flags: [], to: spotlight.pid) }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: item.path), configuration: config) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.favorites.error = error.localizedDescription; self?.showSettings() } }
        }
    }
}

if CommandLine.arguments.contains("--self-test") {
    func check(_ condition: Bool, _ label: String) {
        if !condition { fatalError("FAIL: \(label)") }
    }
    for (index, code) in ShortcutPolicy.codes.enumerated() {
        check(ShortcutPolicy.index(code: code, flags: .maskCommand, count: 9, visible: true) == index, "number \(index + 1)")
        check(ShortcutPolicy.index(code: code, flags: .maskCommand, count: 9, visible: false) == nil, "outside Spotlight")
        check(ShortcutPolicy.index(code: code, flags: [.maskCommand, .maskShift], count: 9, visible: true) == nil, "modified shortcut")
        check(ShortcutPolicy.index(code: code, flags: .maskCommand, count: index, visible: true) == nil, "unassigned slot")
    }
    check(ShortcutPolicy.index(code: 18, flags: [], count: 9, visible: true) == nil, "plain typing")
    check(ShortcutPolicy.index(code: 29, flags: .maskCommand, count: 9, visible: true) == nil, "command zero")
    check(ShortcutPolicy.index(code: 18, flags: [.maskCommand, .maskAlphaShift], count: 9, visible: true) == 0, "caps lock")
    let desktop = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let collapsed = CGRect(x: 400, y: 570, width: 640, height: 60)
    let initial = PanelPlacement.frame(available: desktop, favoriteCount: 4)
    check(desktop.contains(initial), "bar fully inside display")
    check(initial.midX == desktop.midX, "bar horizontally centered")
    check(initial.maxY == desktop.maxY - 10, "fixed gap below menu bar")
    let secondary = CGRect(x: -1440, y: -200, width: 1440, height: 900)
    check(secondary.contains(PanelPlacement.frame(available: secondary, favoriteCount: 9)), "negative-origin display")
    let narrow = CGRect(x: 0, y: 0, width: 500, height: 800)
    check(narrow.contains(PanelPlacement.frame(available: narrow, favoriteCount: 9)), "narrow display keeps margins")
    check(PanelPlacement.frame(available: desktop, favoriteCount: 1).width == 480, "single app keeps enough room for category buttons")
    check(PanelPlacement.frame(available: desktop, favoriteCount: 0).width == 480, "empty state minimum width")
    let sixApps = PanelPlacement.frame(available: desktop, favoriteCount: 6)
    let nineApps = PanelPlacement.frame(available: desktop, favoriteCount: 9)
    check(sixApps.width > initial.width && nineApps.width > sixApps.width, "width grows with favorites beyond minimum")
    check(nineApps.midX == initial.midX && nineApps.maxY == initial.maxY, "resizing keeps fixed top center")
    check(nineApps.width - 40 >= 9 * PanelPlacement.appWidth + 8 * PanelPlacement.appSpacing, "all nine tiles fit without clipping")
    var gate = DismissalGate()
    let testWindow = SpotlightWindow(id: 42, pid: 123, rect: collapsed)
    gate.dismiss(42, now: 10)
    check(gate.filter(testWindow, now: 10.1) == nil, "hide during dismissal animation")
    check(gate.filter(testWindow, now: 10.4) == testWindow, "reused window ID must not stay hidden indefinitely")
    gate.dismiss(42, now: 20)
    check(gate.filter(nil, now: 20.1) == nil, "closed Spotlight clears dismissal")
    check(gate.filter(testWindow, now: 20.2) == testWindow, "immediate reopening with reused ID")
    gate.dismiss(42, now: 30)
    let replacement = SpotlightWindow(id: 43, pid: 123, rect: collapsed)
    check(gate.filter(replacement, now: 30.1) == replacement, "replacement window is visible")
    // Render the actual background painter without a window; catch a washed-out or missing fill.
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 148,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    SpotlightSurface.paint(in: CGRect(x: 0, y: 0, width: 400, height: 148))
    NSGraphicsContext.restoreGraphicsState()
    let fill = bitmap.colorAt(x: 200, y: 74)!.usingColorSpace(.sRGB)!
    check(fill.redComponent < 0.25 && fill.greenComponent < 0.30 && fill.blueComponent < 0.50, "rendered background stays dark")
    check(abs(fill.alphaComponent - 0.84) < 0.02, "background remains dark while allowing visible transparency")
    check(fill.blueComponent > fill.redComponent && fill.redComponent > fill.greenComponent, "rendered fill preserves Alacritty violet")
    check(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0, "rounded corners remain transparent")
    check(abs(fill.redComponent - 29.0 / 255) < 0.025 && abs(fill.greenComponent - 21.0 / 255) < 0.025 && abs(fill.blueComponent - 48.0 / 255) < 0.025, "rendered tint matches Alacritty #1d1530")
    if CommandLine.arguments.contains("--check-icons") {
        // AppKit's ICNS decoder requires the desktop session and can abort inside a sandbox.
        check(AppArtwork.icon?.isValid == true, "bundle icon decodes successfully")
        check(AppArtwork.menuIcon().isTemplate, "menu icon adapts to light and dark menu bars")
        print("2 icon checks passed")
    }
    print("54 behavior and 5 rendered appearance checks passed")
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
