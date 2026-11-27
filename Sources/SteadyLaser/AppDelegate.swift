import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let controller = LaserController()
    private let capture = ButtonCapture()
    private var statusItem: NSStatusItem!

    private var laserButtonHotKey: UInt32?
    private var laserButtonMonitors: [Any] = []
    private var laserButtonError: String?
    private var modifierButtonDown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "smallcircle.filled.circle", accessibilityDescription: "Steady Laser")
            image?.isTemplate = true
            button.image = image
        }

        settings.onChange = { [weak self] in
            guard let self else { return }
            self.refreshMenu()
            self.controller.settingsChanged()
        }

        // ⌃⌥L toggles the laser on/off.
        HotKeyCenter.shared.register(keyCode: kVK_ANSI_L, modifiers: controlKey | optionKey) { [weak self] in
            guard let self else { return }
            self.settings.mode = (self.settings.mode == .off) ? self.settings.lastActiveMode : .off
        }

        // Pressing the laser button twice switches Laser / Spotlight.
        controller.onDoublePress = { [weak self] in
            guard let self else { return }
            self.settings.kind = (self.settings.kind == .laser) ? .spotlight : .laser
        }

        bindLaserButton()
        refreshMenu()
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    // MARK: - Laser button on the remote

    private func unbindLaserButton() {
        if let id = laserButtonHotKey { HotKeyCenter.shared.unregister(id) }
        laserButtonHotKey = nil
        laserButtonMonitors.forEach(NSEvent.removeMonitor)
        laserButtonMonitors.removeAll()
        modifierButtonDown = false
        pendingPress?.cancel()
        pendingPress = nil
        annotating = false
        skipRelease = false
        controller.resetLaserButton()
    }

    // MARK: Modifier button (Norwii pointer key)
    //
    // The Norwii pointer key, held in its PowerPoint-laser mode, sends ⌃L when
    // the hold starts and ⌃A when it ends. Its annotate key sends ⌃P, a left
    // mouse press for as long as it's held, then ⌃A. Without Input Monitoring
    // only the Control part shows, so a Control tap turns the laser on 0.1 s
    // later unless the remote's own mouse press comes first (annotate, skipped
    // along with its closing ⌃A), and the next tap turns it off.

    private var pendingPress: DispatchWorkItem?
    private var annotating = false
    private var skipRelease = false
    private let annotateWindow: TimeInterval = 0.1

    private func modifierButton(down: Bool) {
        guard down != modifierButtonDown else { return }
        modifierButtonDown = down
        if down {
            if annotating {
                annotating = false
                skipRelease = true
            } else if controller.buttonHeld {
                controller.laserButtonPressed()   // turns it off right away
            } else {
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.pendingPress = nil
                        self.controller.laserButtonPressed()
                        // A tap already came back up: let the controller latch it.
                        if !self.modifierButtonDown { self.controller.laserButtonReleased() }
                    }
                }
                pendingPress = work
                DispatchQueue.main.asyncAfter(deadline: .now() + annotateWindow, execute: work)
            }
        } else if skipRelease {
            skipRelease = false
        } else if pendingPress == nil {
            controller.laserButtonReleased()
        }
    }

    private func remoteMouseDown() {
        guard let pending = pendingPress else { return }
        pending.cancel()
        pendingPress = nil
        annotating = true
    }

    /// Watches `mask` both in other apps (global) and in this one (local).
    private func monitor(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            laserButtonMonitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { handler($0); return $0 }) {
            laserButtonMonitors.append(l)
        }
    }

    private func bindLaserButton() {
        unbindLaserButton()
        laserButtonError = nil
        // No button set: use the Norwii pointer key (⌃L … ⌃A from any Norwii remote).
        var binding = settings.laserButton ?? LaserButton.norwiiPointer
        if case let .modifier(_, device) = binding, !LaserButton.allowed(binding, from: device) {
            // A Norwii key other than Pointer, saved before the learn window
            // refused them: every press latched the laser on. Back to Pointer.
            settings.laserButton = nil
            binding = .norwiiPointer
        }

        switch binding {
        case let .key(code, modifiers, _):
            laserButtonHotKey = HotKeyCenter.shared.register(
                keyCode: code, modifiers: modifiers,
                onPress: { [weak self] in self?.controller.laserButtonPressed() },
                onRelease: { [weak self] in self?.controller.laserButtonReleased() }
            )
            if laserButtonHotKey == nil {
                laserButtonError = "ปุ่มนี้ถูกแอปอื่นจองไว้ ลองตั้งปุ่มใหม่"
            }

        case let .modifier(code, device):
            // Not a hotkey: the keys still reach other apps untouched.
            monitor(.flagsChanged) { [weak self] e in
                guard Int(e.keyCode) == code, let down = LaserButton.modifierIsDown(e) else { return }
                MainActor.assumeIsolated {
                    // Only the remote it was learned from, not the Mac keyboard's
                    // Control. Unknown senders are let through.
                    if let device, let from = InputDevice.of(e), !from.isSameMaker(as: device) { return }
                    self?.modifierButton(down: down)
                }
            }
            if let device {
                monitor(.leftMouseDown) { [weak self] e in
                    MainActor.assumeIsolated {
                        guard let from = InputDevice.of(e), from.isSameMaker(as: device) else { return }
                        self?.remoteMouseDown()
                    }
                }
            }

        case let .mouse(button):
            monitor([.otherMouseDown, .otherMouseUp]) { [weak self] e in
                guard e.buttonNumber == button else { return }
                MainActor.assumeIsolated {
                    if e.type == .otherMouseDown { self?.controller.laserButtonPressed() } else { self?.controller.laserButtonReleased() }
                }
            }
        }
    }

    @objc private func learnLaserButton(_ sender: Any?) {
        // In "off" and "always" the button would do nothing, so switch to the
        // button mode once one is learned.
        startLearning(switchToHold: settings.mode == .off || settings.mode == .always)
    }

    private func startLearning(switchToHold: Bool) {
        // Free the old key while learning, or the hotkey would swallow it.
        unbindLaserButton()
        capture.begin { [weak self] result in
            guard let self else { return }
            if let result {
                self.settings.laserButton = result
                if switchToHold { self.settings.mode = .hold }
            }
            self.bindLaserButton()
            self.refreshMenu()
        }
    }

    @objc private func clearLaserButton(_ sender: Any?) {
        settings.laserButton = nil
        bindLaserButton()
        refreshMenu()
    }

    // MARK: - Launch at login

    private var launchesAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        do {
            if launchesAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "ตั้งค่าเปิดอัตโนมัติไม่สำเร็จ"
            alert.informativeText = error.localizedDescription
            NSApp.activate()
            alert.runModal()
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        refreshMenu()
    }

    // MARK: - Menu

    private func refreshMenu() {
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(label("Steady Laser"))
        menu.addItem(.separator())

        menu.addItem(label("โหมดเลเซอร์"))
        for m in LaserMode.allCases {
            let item = choice(m.title, m.rawValue, selected: m == settings.mode, #selector(setMode(_:)))
            menu.addItem(item)
        }
        menu.addItem(.separator())

        menu.addItem(label("ปุ่มเลเซอร์บนรีโมต: " + (settings.laserButton?.title ?? "ปุ่ม pointer ของรีโมต Norwii")))
        if let laserButtonError { menu.addItem(label("⚠︎ " + laserButtonError)) }
        menu.addItem(action(settings.laserButton == nil ? "ตั้งปุ่มเลเซอร์…" : "เปลี่ยนปุ่มเลเซอร์…", #selector(learnLaserButton(_:))))
        if settings.laserButton != nil {
            menu.addItem(action("กลับไปใช้ปุ่ม Pointer ของ Norwii", #selector(clearLaserButton(_:))))
        }
        menu.addItem(.separator())

        menu.addItem(submenu("รูปแบบ", PointerKind.allCases.map {
            choice($0.title, $0.rawValue, selected: $0 == settings.kind, #selector(setKind(_:)))
        } + [.separator(), label("กดปุ่มเลเซอร์ 2 ครั้งเพื่อสลับ")]))
        menu.addItem(submenu("รูปแบบเลเซอร์", LaserStyle.allCases.map {
            choice($0.title, $0.rawValue, selected: $0 == settings.style, #selector(setStyle(_:)))
        }))
        menu.addItem(submenu("สี", LaserColor.allCases.map {
            let item = choice($0.title, $0.rawValue, selected: $0 == settings.color, #selector(setColor(_:)))
            item.image = swatch($0.color)
            return item
        }))
        menu.addItem(submenu("ขนาด", LaserSize.allCases.map {
            choice($0.title, $0.rawValue, selected: $0 == settings.size, #selector(setSize(_:)))
        }))
        menu.addItem(submenu("ความนิ่ง", Stability.allCases.map {
            choice($0.title, $0.rawValue, selected: $0 == settings.stability, #selector(setStability(_:)))
        }))

        let hide = action("ซ่อนเคอร์เซอร์ตอนเลเซอร์แสดง", #selector(toggleHideCursor(_:)))
        hide.state = settings.hideCursor ? .on : .off
        menu.addItem(hide)

        let login = action("เปิดอัตโนมัติตอนเข้าเครื่อง", #selector(toggleLaunchAtLogin(_:)))
        login.state = launchesAtLogin ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(label("เปิด/ปิดเลเซอร์: ⌃⌥L"))
        let quit = action("ออก", #selector(quit(_:)))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
        return menu
    }

    private func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func choice(_ title: String, _ value: String, selected: Bool, _ selector: Selector) -> NSMenuItem {
        let item = action(title, selector)
        item.representedObject = value
        item.state = selected ? .on : .off
        return item
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        items.forEach { sub.addItem($0) }
        parent.submenu = sub
        return parent
    }

    private func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    private func raw(_ sender: NSMenuItem) -> String { sender.representedObject as? String ?? "" }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let v = LaserMode(rawValue: raw(sender)) else { return }
        settings.mode = v
    }
    @objc private func setKind(_ sender: NSMenuItem) { if let v = PointerKind(rawValue: raw(sender)) { settings.kind = v } }
    @objc private func setStyle(_ sender: NSMenuItem) { if let v = LaserStyle(rawValue: raw(sender)) { settings.style = v } }
    @objc private func setColor(_ sender: NSMenuItem) { if let v = LaserColor(rawValue: raw(sender)) { settings.color = v } }
    @objc private func setSize(_ sender: NSMenuItem) { if let v = LaserSize(rawValue: raw(sender)) { settings.size = v } }
    @objc private func setStability(_ sender: NSMenuItem) { if let v = Stability(rawValue: raw(sender)) { settings.stability = v } }
    @objc private func toggleHideCursor(_ sender: NSMenuItem) { settings.hideCursor.toggle() }
    @objc private func quit(_ sender: NSMenuItem) { NSApp.terminate(nil) }
}
