import AppKit
import Carbon.HIToolbox
import IOKit

/// The HID device an event came from, so the remote's Control key can be told
/// apart from the Mac keyboard's.
struct InputDevice: Equatable {
    var vendorID: Int
    var productID: Int
    var name: String

    var plist: [String: Any] { ["vendor": vendorID, "product": productID, "name": name] }

    static let norwiiVendorID = 0x3243
    var isNorwii: Bool { vendorID == Self.norwiiVendorID }

    /// Same maker, so one remote matches whether it comes in through its USB
    /// dongle ("BLE Presenter Dongle", 0x3243/0x382) or straight over
    /// Bluetooth ("Norwii N95s BLE", 0x3243/0x3a2). Devices without a vendor
    /// ID (the Mac's built-in keyboard) are matched by name.
    func isSameMaker(as other: InputDevice) -> Bool {
        if vendorID != 0 || other.vendorID != 0 { return vendorID == other.vendorID }
        return name == other.name
    }

    init(vendorID: Int, productID: Int, name: String) {
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
    }

    init?(plist: Any?) {
        guard let p = plist as? [String: Any], let v = p["vendor"] as? Int, let pr = p["product"] as? Int else { return nil }
        self.init(vendorID: v, productID: pr, name: p["name"] as? String ?? "")
    }

    /// CGEvent field 87 holds the registry ID of the HID service that sent the
    /// event. It isn't in the public headers, so callers treat nil as "unknown".
    private static let senderField = CGEventField(rawValue: 87)
    @MainActor private static var cache: [UInt64: InputDevice] = [:]

    /// The device that sent `event`, or nil if it can't be told (synthetic events).
    @MainActor static func of(_ event: NSEvent) -> InputDevice? {
        guard let field = senderField, let cg = event.cgEvent else { return nil }
        let id = UInt64(bitPattern: cg.getIntegerValueField(field))
        guard id != 0 else { return nil }
        if let hit = cache[id] { return hit }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        func property(_ key: String) -> Any? {
            IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
        }
        let device = InputDevice(
            vendorID: property("VendorID") as? Int ?? 0,
            productID: property("ProductID") as? Int ?? 0,
            name: property("Product") as? String ?? ""
        )
        cache[id] = device
        return device
    }
}

/// The button on the remote that shows the laser.
/// A keyboard key is caught with a Carbon hotkey (no permissions needed);
/// a modifier (the Norwii pointer key sends ⌃L / ⌃A, of which only the Control
/// part can be seen without Input Monitoring) and an extra mouse button
/// (3, 4, 5…) with global event monitors, which need none either.
enum LaserButton: Equatable {
    case key(code: Int, modifiers: Int, name: String)
    case modifier(code: Int, device: InputDevice?)
    case mouse(button: Int)

    /// Default when no button is set: Control from any Norwii remote (vendor
    /// 0x3243), i.e. the pointer key's ⌃L … ⌃A.
    static let norwiiPointer = LaserButton.modifier(
        code: kVK_Control, device: InputDevice(vendorID: InputDevice.norwiiVendorID, productID: 0, name: "Norwii"))

    /// The Norwii Pointer key sends PowerPoint's laser shortcut when a hold
    /// starts and ends: with ⌃ in the remote's Windows mode (⌃L … ⌃A) and with
    /// ⌘ in its Mac mode. Either modifier is the Pointer key.
    static let norwiiPointerModifiers: Set<Int> = [kVK_Control, kVK_Command]

    /// Modifier keys that trigger this button: both of the Pointer key's for a
    /// Norwii remote, so it keeps working when the remote switches mode.
    var modifierCodes: Set<Int> {
        guard case let .modifier(code, device) = self else { return [] }
        if let device, device.isNorwii, Self.norwiiPointerModifiers.contains(code) { return Self.norwiiPointerModifiers }
        return [code]
    }

    /// On a Norwii remote only the Pointer key can be the laser button. Its
    /// other keys send things slides need (Page Up / Down, B, E), and as a
    /// laser button each of their presses would latch the laser on.
    /// The Mac's built-in keyboard (no vendor ID) can't give a modifier: ⌘ / ⌃
    /// there are in every shortcut, and each quick one would latch the laser on.
    static func allowed(_ button: LaserButton, from device: InputDevice?) -> Bool {
        guard let device else { return true }
        if device.isNorwii {
            if case let .modifier(code, _) = button, norwiiPointerModifiers.contains(code) { return true }
            return false
        }
        if case .modifier = button, device.vendorID == 0 { return false }
        return true
    }

    static let allModifierFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]

    var title: String {
        switch self {
        case .key(_, _, let name): name
        case let .modifier(code, device):
            (modifierCodes.count > 1 ? "ปุ่ม Pointer (⌃ / ⌘)" : (Self.modifierKeys[code]?.name ?? "keyCode \(code)"))
                + (device.map { $0.name.isEmpty ? "" : " จาก \($0.name)" } ?? "")
        case .mouse(let button): "ปุ่มเมาส์ \(button + 1)"
        }
    }

    var plist: [String: Any] {
        switch self {
        case let .key(code, modifiers, name): return ["kind": "key", "code": code, "modifiers": modifiers, "name": name]
        case let .modifier(code, device):
            var p: [String: Any] = ["kind": "modifier", "code": code]
            if let device { p["device"] = device.plist }
            return p
        case let .mouse(button): return ["kind": "mouse", "button": button]
        }
    }

    init?(plist: [String: Any]) {
        switch plist["kind"] as? String {
        case "key":
            guard let code = plist["code"] as? Int, let mods = plist["modifiers"] as? Int else { return nil }
            self = .key(code: code, modifiers: mods, name: plist["name"] as? String ?? "keyCode \(code)")
        case "modifier":
            guard let code = plist["code"] as? Int, Self.modifierKeys[code] != nil else { return nil }
            self = .modifier(code: code, device: InputDevice(plist: plist["device"]))
        case "mouse":
            guard let button = plist["button"] as? Int else { return nil }
            self = .mouse(button: button)
        default:
            return nil
        }
    }

    // MARK: Modifier keys on their own

    /// `bit` is the device-dependent bit in `NSEvent.modifierFlags.rawValue`
    /// (tells left from right); `flag` the device-independent one.
    static let modifierKeys: [Int: (bit: UInt, flag: NSEvent.ModifierFlags, name: String)] = [
        kVK_Control: (0x0001, .control, "Control (⌃)"),
        kVK_RightControl: (0x2000, .control, "Control ขวา (⌃)"),
        kVK_Shift: (0x0002, .shift, "Shift (⇧)"),
        kVK_RightShift: (0x0004, .shift, "Shift ขวา (⇧)"),
        kVK_Command: (0x0008, .command, "Command (⌘)"),
        kVK_RightCommand: (0x0010, .command, "Command ขวา (⌘)"),
        kVK_Option: (0x0020, .option, "Option (⌥)"),
        kVK_RightOption: (0x0040, .option, "Option ขวา (⌥)"),
        kVK_Function: (NSEvent.ModifierFlags.function.rawValue, .function, "fn"),
    ]

    /// For a `.flagsChanged` event: whether its modifier key went down (true)
    /// or up (false); nil if it isn't one of `modifierKeys` (e.g. Caps Lock).
    static func modifierIsDown(_ e: NSEvent) -> Bool? {
        guard e.type == .flagsChanged, let key = modifierKeys[Int(e.keyCode)] else { return nil }
        return e.modifierFlags.rawValue & key.bit != 0
    }

    // MARK: Keys

    /// Builds a binding from the key press captured in the "learn" panel.
    static func from(keyEvent e: NSEvent) -> LaserButton {
        let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
        var carbon = 0
        var prefix = ""
        if flags.contains(.control) { carbon |= controlKey; prefix += "⌃" }
        if flags.contains(.option) { carbon |= optionKey; prefix += "⌥" }
        if flags.contains(.shift) { carbon |= shiftKey; prefix += "⇧" }
        if flags.contains(.command) { carbon |= cmdKey; prefix += "⌘" }
        return .key(code: Int(e.keyCode), modifiers: carbon, name: prefix + keyName(e))
    }

    private static func keyName(_ e: NSEvent) -> String {
        let named: [Int: String] = [
            kVK_PageUp: "Page Up", kVK_PageDown: "Page Down", kVK_Home: "Home", kVK_End: "End",
            kVK_Escape: "Esc", kVK_Tab: "Tab", kVK_Return: "Return", kVK_Space: "Space",
            kVK_Delete: "Delete", kVK_ForwardDelete: "Forward Delete",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
            kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        ]
        if let n = named[Int(e.keyCode)] { return n }
        if let c = e.charactersIgnoringModifiers, !c.isEmpty,
           c.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            return c.uppercased()
        }
        return "keyCode \(e.keyCode)"
    }
}

/// Small window that waits for the next key, bare modifier tap or extra mouse
/// button and hands it back.
@MainActor
final class ButtonCapture: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var completion: ((LaserButton?) -> Void)?
    /// A modifier that went down on its own; it becomes the button if it comes
    /// back up before any other key (a bare tap), or if a key follows within a
    /// few ms (a remote sending a shortcut, not a person pressing ⌃F5).
    private var pendingModifier: (code: Int, device: InputDevice?, at: TimeInterval)?
    /// A person needs well over this to add a key to a held modifier; the
    /// Norwii remote sends ⌃L with 7–17 ms between Control and L.
    private let remoteChordGap: TimeInterval = 0.05
    /// A bare modifier tap counts only if it's this quick: the remote's last
    /// 15–40 ms, while a person's ⌘ (⌘Tab out of this window, say) is longer.
    private let remoteTapMax: TimeInterval = 0.06

    func begin(completion: @escaping (LaserButton?) -> Void) {
        finish(nil)
        self.completion = completion

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 167),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        panel.title = "ตั้งปุ่มเลเซอร์"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let content = makeContent()
        panel.contentView = content
        content.layoutSubtreeIfNeeded()
        panel.setContentSize(content.fittingSize)
        panel.center()
        self.panel = panel

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)

        // Local: events sent to this app (the panel is key). Global: events
        // sent to other apps, in case the panel didn't become key or the
        // cursor isn't over it. Global key-downs would need Input Monitoring,
        // so plain keys only work while the panel is key.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .otherMouseDown], handler: { [weak self] event in
            guard let self, self.handle(event) else { return event }
            return nil
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .otherMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated { _ = self?.handle(event) }
        }) { monitors.append(m) }
    }

    /// Returns true when the event was used up.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            // A remote's shortcut (the Norwii pointer's ⌃L): bind the modifier
            // alone, so ⌃L isn't taken from other apps as a hotkey and the
            // remote's matching ⌃A can turn the laser off.
            if let p = pendingModifier, p.device != nil, event.timestamp - p.at < remoteChordGap {
                accept(.modifier(code: p.code, device: p.device), from: p.device)
                return true
            }
            accept(LaserButton.from(keyEvent: event), from: InputDevice.of(event))
            return true
        case .otherMouseDown:
            accept(.mouse(button: event.buttonNumber), from: InputDevice.of(event))
            return true
        case .flagsChanged:
            guard let down = LaserButton.modifierIsDown(event) else { return false }
            let code = Int(event.keyCode)
            if down {
                // Only a modifier pressed on its own counts, not one joining others.
                let held = event.modifierFlags.intersection(LaserButton.allModifierFlags)
                let alone = held == LaserButton.modifierKeys[code]?.flag
                pendingModifier = alone ? (code, InputDevice.of(event), event.timestamp) : nil
            } else if let pending = pendingModifier, pending.code == code {
                pendingModifier = nil
                if event.timestamp - pending.at <= remoteTapMax {
                    accept(.modifier(code: code, device: pending.device), from: pending.device)
                }
            }
            return false
        default:
            return false
        }
    }

    /// Saves the button, or keeps waiting with a warning if it's a Norwii key
    /// other than Pointer.
    private func accept(_ button: LaserButton, from device: InputDevice?) {
        guard LaserButton.allowed(button, from: device) else {
            pendingModifier = nil
            showWarning("ปุ่ม \(button.title) ของรีโมตมีหน้าที่อยู่แล้ว ใช้เป็นปุ่มเลเซอร์ไม่ได้ ให้กดปุ่ม Pointer แทน")
            return
        }
        finish(button)
    }

    private weak var warningLabel: NSTextField?

    private func showWarning(_ text: String) {
        guard let label = warningLabel, let panel, let content = panel.contentView else { return }
        label.stringValue = "⚠︎ " + text
        label.isHidden = false
        content.layoutSubtreeIfNeeded()
        panel.setContentSize(content.fittingSize)
    }

    /// The panel's content; also used by `--snapshot-capture` to check the layout.
    func makeContent() -> NSView {
        let title = NSTextField(wrappingLabelWithString: "กดปุ่มบนรีโมตที่อยากใช้เป็นปุ่มเลเซอร์")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        let norwii = NSTextField(wrappingLabelWithString:
            "รีโมต Norwii: กดปุ่ม pointer ค้างไว้จนหน้าต่างนี้ปิด ถ้าไม่ปิด รีโมตอาจอยู่ในโหมดเลเซอร์จริง ให้ดับเบิลคลิกปุ่ม pointer เพื่อสลับโหมด แล้วกดค้างใหม่")
        let body = NSTextField(wrappingLabelWithString:
            "ถ้าเลือกปุ่มคีย์บอร์ดทั่วไป แอปอื่นจะไม่ได้รับปุ่มนั้นอีก จึงไม่ควรเลือกปุ่มเลื่อนสไลด์ (Page Up / Page Down / ลูกศร)")
        body.textColor = .secondaryLabelColor
        let hint = NSTextField(wrappingLabelWithString:
            "ถ้ากดแล้วไม่มีอะไรเกิดขึ้น แปลว่าปุ่มนั้นไม่ได้ส่งอะไรมาที่เครื่อง ให้ลองปุ่มอื่น หรือใช้โหมด \"แสดงเมื่อขยับเมาส์\" แทน")
        hint.textColor = .secondaryLabelColor
        let warning = NSTextField(wrappingLabelWithString: "")
        warning.textColor = .systemRed
        warning.isHidden = true
        warningLabel = warning
        let cancel = NSButton(title: "ยกเลิก", target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = ""

        let stack = NSStackView(views: [title, norwii, warning, body, hint, cancel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 400),
        ])
        return content
    }

    @objc private func cancelPressed() { finish(nil) }

    func windowWillClose(_ notification: Notification) {
        if completion != nil { finish(nil, closing: true) }
    }

    private func finish(_ result: LaserButton?, closing: Bool = false) {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        pendingModifier = nil
        let done = completion
        completion = nil
        if !closing { panel?.close() }
        panel = nil
        done?(result)
    }
}
